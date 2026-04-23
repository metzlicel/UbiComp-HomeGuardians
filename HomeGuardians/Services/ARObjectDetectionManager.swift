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
    private let processingInterval: TimeInterval = 0.8
    private let processingQueue = DispatchQueue(label: "com.homeguardians.visionProcessing")
    private var isProcessingFrame = false
    
    // MARK: - AR model state
    private var currentModelName: String?
    private var placedAnchor: AnchorEntity?
    private var placedEntity: Entity?
    private var isPlaced = false
    
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
        
        arView.session.run(
            configuration,
            options: [.resetTracking, .removeExistingAnchors]
        )
        
        delegate?.didUpdateTrackingState("Inicializando AR...")
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
        
        let pixelBuffer = frame.capturedImage
        let cameraTransform = frame.camera.transform
        
        isProcessingFrame = true
        
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            autoreleasepool {
                self.processFrame(
                    pixelBuffer: pixelBuffer,
                    cameraTransform: cameraTransform
                )
            }
            
            DispatchQueue.main.async {
                self.isProcessingFrame = false
            }
        }
    }
    
    // MARK: - CoreML + Vision
    
    private func processFrame(
        pixelBuffer: CVPixelBuffer,
        cameraTransform: simd_float4x4
    ) {
        guard let model = coreMLModel else { return }
        
        let request = VNCoreMLRequest(model: model) { [weak self] request, _ in
            guard let self = self else { return }
            
            if let observations = request.results as? [VNRecognizedObjectObservation],
               let top = observations.first,
               let label = top.labels.first {
                
                let box = top.boundingBox
                let screenPoint = self.screenPoint(from: box, in: self.arView)
                let distance = self.measureDistance(
                    from: screenPoint,
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
            cvPixelBuffer: pixelBuffer,
            orientation: .right,
            options: [:]
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
    
    func placeModelIfNeeded(modelName: String, boundingBox: CGRect?) {
        guard let boundingBox else { return }
        guard !modelName.isEmpty else { return }
        
        if isPlaced && currentModelName == modelName {
            return
        }
        
        removeModel()
        placeModel(named: modelName, at: boundingBox)
        currentModelName = modelName
    }
    
    private func placeModel(named modelName: String, at boundingBox: CGRect) {
        let viewSize = arView.bounds.size
        
        let centerX = boundingBox.midX * viewSize.width
        let centerY = (1 - boundingBox.midY) * viewSize.height
        
        let screenPoint = CGPoint(x: centerX, y: centerY)
        
        if let result = arView.raycast(
            from: screenPoint,
            allowing: .estimatedPlane,
            alignment: .any
        ).first {
            
            do {
                let entity = try Entity.load(named: "\(modelName).usdz")
                
                entity.scale = SIMD3<Float>(0.25, 0.25, 0.25)
                entity.position = [0, 0, -0.15]
                
                let anchor = AnchorEntity(world: result.worldTransform)
                anchor.addChild(entity)
                
                arView.scene.addAnchor(anchor)
                
                playAnimation(on: entity)
                
                placedAnchor = anchor
                placedEntity = entity
                isPlaced = true
                
            } catch {
                print("Error cargando modelo: \(error)")
            }
        } else {
            placeInFrontOfCamera(named: modelName)
        }
    }
    
    private func placeInFrontOfCamera(named modelName: String) {
        guard let cameraTransform = arView.session.currentFrame?.camera.transform else { return }
        
        do {
            let entity = try Entity.load(named: "\(modelName).usdz")
            entity.scale = SIMD3<Float>(0.25, 0.25, 0.25)
            
            var forward = matrix_identity_float4x4
            forward.columns.3.z = -0.8
            
            let finalTransform = simd_mul(cameraTransform, forward)
            
            let anchor = AnchorEntity(world: finalTransform)
            anchor.addChild(entity)
            
            arView.scene.addAnchor(anchor)
            
            playAnimation(on: entity)
            
            placedAnchor = anchor
            placedEntity = entity
            isPlaced = true
            
        } catch {
            print("Error fallback modelo: \(error)")
        }
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
