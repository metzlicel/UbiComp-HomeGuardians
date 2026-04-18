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
    private let processingInterval: TimeInterval = 0.5
    
    private lazy var coreMLModel: VNCoreMLModel? = {
        try? VNCoreMLModel(for: COMOO().model)
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
    }
    
    // MARK: - ARSessionDelegate
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let now = Date()
        guard now.timeIntervalSince(lastProcessedTime) >= processingInterval else { return }
        lastProcessedTime = now
        
        updateTrackingText(from: frame.camera.trackingState)
        processFrame(frame)
    }
    
    // MARK: - CoreML + Vision
    
    private func processFrame(_ frame: ARFrame) {
        guard let model = coreMLModel else { return }
        
        let request = VNCoreMLRequest(model: model) { [weak self] request, _ in
            guard let self = self else { return }
            
            // Caso 1: object detection con bounding boxes
            if let observations = request.results as? [VNRecognizedObjectObservation],
               let top = observations.first,
               let label = top.labels.first {
                
                let box = top.boundingBox
                let screenPoint = self.screenPoint(from: box, in: self.arView)
                let distance = self.measureDistance(from: screenPoint, currentFrame: frame)
                
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
            
            // Caso 2: classification fallback
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
            cvPixelBuffer: frame.capturedImage,
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
    
    private func measureDistance(from point: CGPoint, currentFrame: ARFrame) -> Float? {
        // Primero intenta sobre geometría/plano existente
        let existingResults = arView.raycast(
            from: point,
            allowing: .existingPlaneGeometry,
            alignment: .any
        )
        
        if let first = existingResults.first {
            return distanceToCamera(from: first.worldTransform, currentFrame: currentFrame)
        }
        
        // Si no encuentra, intenta con plano estimado
        let estimatedResults = arView.raycast(
            from: point,
            allowing: .estimatedPlane,
            alignment: .any
        )
        
        if let first = estimatedResults.first {
            return distanceToCamera(from: first.worldTransform, currentFrame: currentFrame)
        }
        
        return nil
    }
    
    private func distanceToCamera(from worldTransform: simd_float4x4, currentFrame: ARFrame) -> Float {
        let hitPosition = SIMD3<Float>(
            worldTransform.columns.3.x,
            worldTransform.columns.3.y,
            worldTransform.columns.3.z
        )
        
        let cameraTransform = currentFrame.camera.transform
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
}
