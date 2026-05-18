//
//  ARObjectDetectionManager.swift
//  HomeGuardians
//
//  Created by Marlon on 09/04/26.
//

import Foundation
import ARKit
import RealityKit
import Vision
import UIKit
import simd
import Combine

protocol ARObjectDetectionManagerDelegate: AnyObject {
    func didUpdateDetection(
        label: String,
        confidence: Float,
        boundingBox: CGRect?,
        distanceInMeters: Float?
    )
    
    func didUpdateTrackingState(_ text: String)
}

final class ARObjectDetectionManager: NSObject, ARSessionDelegate {
    
    weak var delegate: ARObjectDetectionManagerDelegate?
    
    let arView: ARView
    
    private var lastProcessedTime = Date.distantPast
    private let processingInterval: TimeInterval = 0.5
    private let processingQueue = DispatchQueue(label: "com.homeguardians.visionProcessing")
    private var isProcessingFrame = false
    private let ciContext = CIContext()
    
    // MARK: - AR model state
    private var currentModelName: String?
    private var placedAnchor: AnchorEntity?
    private var placedEntity: Entity?
    private var isPlaced = false
    
    private var modelCache: [String: Entity] = [:]
    private var modelLoadCancellables = Set<AnyCancellable>()
    private var modelNamesBeingLoaded = Set<String>()
    private let availableModelNames = ["Stufi", "Sparky", "Stepys"]

    private struct ModelPlacementConfig {
        let scale: SIMD3<Float>
        let localOffset: SIMD3<Float>
        let orientationCorrection: simd_quatf
    }
    
    // Cambia Connulls() por el nombre real de tu modelo CoreML si hace falta
    private lazy var coreMLModel: VNCoreMLModel? = {
        try? VNCoreMLModel(for: Connulls().model)
    }()
    
    init(arView: ARView = ARView(frame: .zero)) {
        self.arView = arView
        super.init()
        self.arView.session.delegate = self
        self.arView.automaticallyConfigureSession = false
    }
    
    func startSession() {
        guard ARWorldTrackingConfiguration.isSupported else {
            delegate?.didUpdateTrackingState("AR World Tracking no es compatible en este dispositivo")
            return
        }
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            configuration.frameSemantics.insert(.smoothedSceneDepth)
        } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }
        
        arView.session.run(
            configuration,
            options: [.resetTracking, .removeExistingAnchors]
        )
        
        delegate?.didUpdateTrackingState("Inicializando AR...")
        preloadModelsIfNeeded()
    }
    
    func stopSession() {
        arView.session.pause()
        removeModel()
        isProcessingFrame = false
    }
    
    // MARK: - ARSessionDelegate
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let now = Date()

        guard now.timeIntervalSince(lastProcessedTime) >= processingInterval else { return }
        guard !isProcessingFrame else { return }

        lastProcessedTime = now
        updateTrackingText(from: frame.camera.trackingState)

        let cameraTransform = frame.camera.transform
        let depthMap = frame.smoothedSceneDepth?.depthMap ?? frame.sceneDepth?.depthMap

        guard let cgImage = makeCGImage(from: frame.capturedImage) else { return }

        isProcessingFrame = true

        processingQueue.async { [weak self] in
            guard let self = self else { return }

            defer {
                DispatchQueue.main.async {
                    self.isProcessingFrame = false
                }
            }

            autoreleasepool {
                self.processFrame(
                    cgImage: cgImage,
                    depthMap: depthMap,
                    cameraTransform: cameraTransform
                )
            }
        }
    }
    
    private func makeCGImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        return ciContext.createCGImage(ciImage, from: ciImage.extent)
    }
    
    // MARK: - CoreML + Vision
    
    private func processFrame(
        cgImage: CGImage,
        depthMap: CVPixelBuffer?,
        cameraTransform: simd_float4x4
    ) {
        guard let model = coreMLModel else { return }

        let request = VNCoreMLRequest(model: model) { [weak self] request, _ in
            guard let self = self else { return }

            if let observations = request.results as? [VNRecognizedObjectObservation],
               let top = observations.first,
               let label = top.labels.first {

                let box = top.boundingBox
                let distance = self.measureDistance(
                    for: box,
                    depthMap: depthMap,
                    cameraTransform: cameraTransform
                )

                DispatchQueue.main.async {
                    self.delegate?.didUpdateDetection(
                        label: label.identifier,
                        confidence: label.confidence,
                        boundingBox: box,
                        distanceInMeters: distance
                    )
                }
                return
            }

            if let observations = request.results as? [VNClassificationObservation],
               let top = observations.first {

                DispatchQueue.main.async {
                    self.delegate?.didUpdateDetection(
                        label: top.identifier,
                        confidence: top.confidence,
                        boundingBox: nil,
                        distanceInMeters: nil
                    )
                }
            }
        }

        request.imageCropAndScaleOption = .centerCrop

        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: .right
        )

        do {
            try handler.perform([request])
        } catch {
            print("Vision error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Coordinate conversion
    
    private func screenPoint(from boundingBox: CGRect, in view: UIView) -> CGPoint {
        let centerX = boundingBox.midX
        let centerY = 1.0 - boundingBox.midY
        
        return CGPoint(
            x: centerX * view.bounds.width,
            y: centerY * view.bounds.height
        )
    }
    
    // MARK: - Distance
    private func measureDistance(
        for boundingBox: CGRect,
        depthMap: CVPixelBuffer?,
        cameraTransform: simd_float4x4
    ) -> Float? {
        if let depthMap,
           let depthDistance = medianDepthDistance(for: boundingBox, depthMap: depthMap) {
            return depthDistance
        }

        return medianRaycastDistance(for: boundingBox, cameraTransform: cameraTransform)
    }
    
    private func measureDistance(from point: CGPoint, cameraTransform: simd_float4x4) -> Float? {
        let existingResults = arView.raycast(
            from: point,
            allowing: .existingPlaneGeometry,
            alignment: .any
        )
        
        if let first = existingResults.first {
            return distanceToCamera(
                from: first.worldTransform,
                cameraTransform: cameraTransform
            )
        }
        
        let estimatedResults = arView.raycast(
            from: point,
            allowing: .estimatedPlane,
            alignment: .any
        )
        
        if let first = estimatedResults.first {
            return distanceToCamera(
                from: first.worldTransform,
                cameraTransform: cameraTransform
            )
        }
        
        return nil
    }
    
    private func medianDepthDistance(
        for boundingBox: CGRect,
        depthMap: CVPixelBuffer
    ) -> Float? {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            return nil
        }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let floatBuffer = baseAddress.assumingMemoryBound(to: Float32.self)

        let samplePoints = normalizedSamplePoints(in: boundingBox)
        var distances: [Float] = []

        for point in samplePoints {
            let x = min(max(Int(point.x * CGFloat(width)), 0), width - 1)
            let y = min(max(Int((1.0 - point.y) * CGFloat(height)), 0), height - 1)

            let row = bytesPerRow / MemoryLayout<Float32>.size
            let depth = floatBuffer[y * row + x]

            if depth.isFinite, depth > 0 {
                distances.append(depth)
            }
        }

        return median(of: distances)
    }
    
    private func medianRaycastDistance(
        for boundingBox: CGRect,
        cameraTransform: simd_float4x4
    ) -> Float? {
        let samplePoints = normalizedSamplePoints(in: boundingBox)
        var distances: [Float] = []

        for point in samplePoints {
            let screenPoint = CGPoint(
                x: point.x * arView.bounds.width,
                y: (1.0 - point.y) * arView.bounds.height
            )

            if let distance = measureDistance(from: screenPoint, cameraTransform: cameraTransform) {
                distances.append(distance)
            }
        }

        return median(of: distances)
    }
    
    
    private func distanceToCamera(
        from worldTransform: simd_float4x4,
        cameraTransform: simd_float4x4
    ) -> Float {
        let hitPosition = SIMD3<Float>(
            worldTransform.columns.3.x,
            worldTransform.columns.3.y,
            worldTransform.columns.3.z
        )
        
        let cameraPosition = SIMD3<Float>(
            cameraTransform.columns.3.x,
            cameraTransform.columns.3.y,
            cameraTransform.columns.3.z
        )
        
        return simd_distance(hitPosition, cameraPosition)
    }
    
    // MARK: Helpers
    private func normalizedSamplePoints(in boundingBox: CGRect) -> [CGPoint] {
        let minX = boundingBox.minX
        let midX = boundingBox.midX
        let maxX = boundingBox.maxX

        let minY = boundingBox.minY
        let midY = boundingBox.midY
        let maxY = boundingBox.maxY

        return [
            CGPoint(x: midX, y: midY),
            CGPoint(x: minX + boundingBox.width * 0.25, y: midY),
            CGPoint(x: maxX - boundingBox.width * 0.25, y: midY),
            CGPoint(x: midX, y: minY + boundingBox.height * 0.25),
            CGPoint(x: midX, y: maxY - boundingBox.height * 0.25)
        ]
    }

    private func median(of values: [Float]) -> Float? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return nil }

        let middle = sorted.count / 2

        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        } else {
            return sorted[middle]
        }
    }
    
//    private func distanceToCenterObject(cameraTransform: simd_float4x4) -> Float? {
//        let centerPoint = CGPoint(
//            x: arView.bounds.midX,
//            y: arView.bounds.midY
//        )
//        
//        let results = arView.raycast(
//            from: centerPoint,
//            allowing: .estimatedPlane,
//            alignment: .any
//        )
//        
//        guard let first = results.first else { return nil }
//        
//        return distanceToCamera(
//            from: first.worldTransform,
//            cameraTransform: cameraTransform
//        )
//    }
    
    // MARK: - Tracking state
    
    private func updateTrackingText(from trackingState: ARCamera.TrackingState) {
        let text: String
        
        switch trackingState {
        case .normal:
            text = "AR listo"
            
        case .notAvailable:
            text = "AR no disponible"
            
        case .limited(let reason):
            switch reason {
            case .initializing:
                text = "Inicializando AR..."
            case .excessiveMotion:
                text = "Mueve el dispositivo más despacio"
            case .insufficientFeatures:
                text = "Apunta a una superficie con más detalle"
            case .relocalizing:
                text = "Recuperando seguimiento..."
            @unknown default:
                text = "Seguimiento AR limitado"
            }
        }
        
        DispatchQueue.main.async {
            self.delegate?.didUpdateTrackingState(text)
        }
    }
    
    // MARK: - AR Model functions
    private func preloadModelsIfNeeded() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            for modelName in self.availableModelNames {
                if self.modelCache[modelName] != nil || self.modelNamesBeingLoaded.contains(modelName) {
                    continue
                }

                self.modelNamesBeingLoaded.insert(modelName)

                Entity.loadAsync(named: "\(modelName).usdz")
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] completion in
                        self?.modelNamesBeingLoaded.remove(modelName)

                        if case .failure(let error) = completion {
                            print("Error precargando modelo \(modelName): \(error)")
                        }
                    } receiveValue: { [weak self] entity in
                        self?.modelCache[modelName] = entity
                    }
                    .store(in: &self.modelLoadCancellables)
            }
        }
    }
    
    private func cachedEntity(named modelName: String) -> Entity? {
        guard let cached = modelCache[modelName] else {
            return nil
        }

        return cached.clone(recursive: true)
    }

    private func placementConfig(for modelName: String) -> ModelPlacementConfig {
        switch modelName {
        case "Sparky":
            return ModelPlacementConfig(
                scale: [0.20, 0.20, 0.20],
                localOffset: [0, 0, 0],
                orientationCorrection: rotationDegrees(x: 0, y: 180, z: 0)
            )
        case "Stepys":
            return ModelPlacementConfig(
                scale: [0.011, 0.011, 0.011],
                localOffset: [0, 0, 0],
                orientationCorrection: rotationDegrees(x: 0, y: -90, z: 0)
            )
        default: // Stufi
            return ModelPlacementConfig(
                scale: [0.20, 0.20, 0.20],
                localOffset: [0, 0, 0],
                orientationCorrection: rotationDegrees(x: 0, y: 180, z: 0)
            )
        }
    }

    private func translationOnlyTransform(from worldTransform: simd_float4x4) -> simd_float4x4 {
        var transform = matrix_identity_float4x4
        transform.columns.3 = worldTransform.columns.3
        return transform
    }
    
    func placeModelIfNeeded(modelName: String, boundingBox: CGRect?) {
        guard let boundingBox else { return }
        guard !modelName.isEmpty else { return }
        
        if isPlaced && currentModelName == modelName {
            return
        }
        
        removeModel()
        if placeModel(named: modelName, at: boundingBox) {
            currentModelName = modelName
        } else {
            preloadModelsIfNeeded()
        }
    }
    
    private func placeModel(named modelName: String, at boundingBox: CGRect) -> Bool {
        let viewSize = arView.bounds.size

        let centerX = boundingBox.midX * viewSize.width
        let centerY = (1 - boundingBox.midY) * viewSize.height

        let screenPoint: CGPoint

        if modelName == "Stepys" {
            screenPoint = CGPoint(
                x: boundingBox.midX * viewSize.width,
                y: (1 - boundingBox.minY) * viewSize.height
            )
        } else {
            screenPoint = CGPoint(
                x: boundingBox.midX * viewSize.width,
                y: (1 - boundingBox.midY) * viewSize.height
            )
        }
        

        guard let entity = cachedEntity(named: modelName) else {
            print("Modelo no disponible en cache: \(modelName)")
            return false
        }

        let config = placementConfig(for: modelName)
        entity.scale = config.scale
        entity.position = config.localOffset

        if let result = arView.raycast(
            from: screenPoint,
            allowing: .estimatedPlane,
            alignment: .any
        ).first {

            let anchor = AnchorEntity(world: translationOnlyTransform(from: result.worldTransform))
            anchor.addChild(entity)

            arView.scene.addAnchor(anchor)

            makeEntityFaceCamera(
                entity,
                cameraTransform: arView.cameraTransform.matrix,
                modelName: modelName
            )

            playAnimation(on: entity)

            placedAnchor = anchor
            placedEntity = entity
            isPlaced = true
            return true

        } else {
            return false
        }
    }
    
//    private func placeInFrontOfCamera(named modelName: String) -> Bool {
//        guard let cameraTransform = arView.session.currentFrame?.camera.transform else { return false }
//
//        guard let entity = cachedEntity(named: modelName) else {
//            print("Modelo no disponible en cache: \(modelName)")
//            return false
//        }
//
//        let config = placementConfig(for: modelName)
//        entity.scale = config.scale
//        entity.position = config.localOffset
//
//        var forward = matrix_identity_float4x4
//        forward.columns.3.z = -0.8
//
//        let finalTransform = simd_mul(cameraTransform, forward)
//
//        let anchor = AnchorEntity(world: finalTransform)
//        anchor.addChild(entity)
//
//        arView.scene.addAnchor(anchor)
//        
//        makeEntityFaceCamera(
//            entity,
//            cameraTransform: cameraTransform,
//            modelName: modelName
//        )
//
//        playAnimation(on: entity)
//
//        placedAnchor = anchor
//        placedEntity = entity
//        isPlaced = true
//        return true
//    }
    
    private func makeEntityFaceCamera(
        _ entity: Entity,
        cameraTransform: simd_float4x4,
        modelName: String
    ) {
        let cameraPosition = SIMD3<Float>(
            cameraTransform.columns.3.x,
            cameraTransform.columns.3.y,
            cameraTransform.columns.3.z
        )

        let entityWorldPosition = entity.position(relativeTo: nil)

        let direction = cameraPosition - entityWorldPosition
        let angle = atan2(direction.x, direction.z) + .pi

        let faceCameraRotation = simd_quatf(angle: angle, axis: [0, 1, 0])
        let config = placementConfig(for: modelName)

        entity.orientation = faceCameraRotation * config.orientationCorrection
    }
    
    private func playAnimation(on entity: Entity) {
        if let model = entity as? ModelEntity, !model.availableAnimations.isEmpty {
            model.playAnimation(model.availableAnimations[0].repeat())
            return
        }
        
        for child in entity.children {
            if let model = child as? ModelEntity, !model.availableAnimations.isEmpty {
                model.playAnimation(model.availableAnimations[0].repeat())
                return
            }
        }
    }
    
    func removeModel() {
        placedAnchor?.removeFromParent()
        placedAnchor = nil
        placedEntity = nil
        isPlaced = false
        currentModelName = nil
    }
}

private func rotationDegrees(x: Float = 0, y: Float = 0, z: Float = 0) -> simd_quatf {
    let xRotation = simd_quatf(angle: x * .pi / 180, axis: [1, 0, 0])
    let yRotation = simd_quatf(angle: y * .pi / 180, axis: [0, 1, 0])
    let zRotation = simd_quatf(angle: z * .pi / 180, axis: [0, 0, 1])

    return yRotation * xRotation * zRotation
}
