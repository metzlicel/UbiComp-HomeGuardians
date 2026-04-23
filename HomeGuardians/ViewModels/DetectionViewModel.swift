//
//  DetectionViewModel.swift
//  HomeGuardians
//
//  Created by Marlon Corona Arango on 15/03/26.
//

import Foundation
import SwiftUI
import Observation


@Observable
class DetectionViewModel: ARObjectDetectionManagerDelegate {
    
    var detectedLabel: String = ""
    var confidence: Float = 0
    var boundingBox: CGRect? = nil
    var showPopup: Bool = false
    var isLive: Bool = true
    
    // Detectar DangerZone
    private let dangerDistanceThreshold: Float = 1.0
    var isStoveDetected: Bool = false
    var isOutletDetected: Bool = false
    var isStairsDetected: Bool = false
    
    var isDangerNear: Bool {
        guard let distanceInMeters else { return false }
        return isDangerLabel(detectedLabel) && distanceInMeters <= dangerDistanceThreshold
    }

    var shouldShowStoveWarning: Bool {
        guard let distanceInMeters else { return false }
        return isStoveLabel(detectedLabel) && distanceInMeters <= dangerDistanceThreshold
    }

    var shouldShowOutletWarning: Bool {
        guard let distanceInMeters else { return false }
        return isOutletLabel(detectedLabel) && distanceInMeters <= dangerDistanceThreshold
    }

    var shouldShowStairsWarning: Bool {
        guard let distanceInMeters else { return false }
        return isStairsLabel(detectedLabel) && distanceInMeters <= dangerDistanceThreshold
    }

    var warningText: String {
        if shouldShowStoveWarning {
            return "¡Está caliente, caliente! Mejor mira desde lejos"
        }
        if shouldShowOutletWarning {
            return "¡Aquí pica como abeja. Mejor aleja tus manitas"
        }
        if shouldShowStairsWarning {
            return "Yo ruedo y ruedo. ¡Pero tu camina como grande!"
        }
        return ""
    }

    var modelNameForCurrentDanger: String? {
        if shouldShowStoveWarning {
            return "Stufi"
        }
        if shouldShowOutletWarning {
            return "Sparky"
        }
        if shouldShowStairsWarning {
            return nil   // Stepy
        }
        return nil
    }
    

    
    // Nueva información AR
    var distanceInMeters: Float? = nil
    var trackingStateText: String = "Inicializando AR..."
    
    let arManager = ARObjectDetectionManager()
    
    private var popupTimer: Timer?
    private let confidenceThreshold: Float = 0.6
    
    var confidenceText: String {
        guard confidence > 0 else { return "" }
        return "\(Int(confidence * 100))%"
    }
    
    var confidenceColor: Color {
        switch confidence {
        case 0.85...: return .green
        case 0.6...:  return .orange
        default:      return .red
        }
    }
    
    var distanceText: String {
        guard let distanceInMeters else { return "Distancia no disponible" }
        return String(format: "%.2f m", distanceInMeters)
    }
    
    func startCamera() {
        arManager.delegate = self
        arManager.startSession()
    }
    
    func stopCamera() {
        arManager.stopSession()
    }
    
    // MARK: - ARObjectDetectionManagerDelegate
    
    func didUpdateDetection(
        label: String,
        confidence: Float,
        boundingBox: CGRect?,
        distanceInMeters: Float?
    ) {
        guard confidence >= confidenceThreshold else {
            DispatchQueue.main.async { [weak self] in
                self?.isStoveDetected = false
                self?.isOutletDetected = false
                self?.isStairsDetected = false
                self?.distanceInMeters = nil
                self?.detectedLabel = ""
                self?.confidence = 0
                self?.boundingBox = nil
                self?.arManager.removeModel()
            }
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.detectedLabel = label
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
            
            self.confidence = confidence
            self.boundingBox = boundingBox
            self.distanceInMeters = distanceInMeters
            
            self.isStoveDetected = self.isStoveLabel(label)
            self.isOutletDetected = self.isOutletLabel(label)
            self.isStairsDetected = self.isStairsLabel(label)

                   
            if let modelName = self.modelNameForCurrentDanger {
                self.arManager.placeModelIfNeeded(
                    modelName: modelName,
                    boundingBox: boundingBox
                )
            } else {
                self.arManager.removeModel()
            }
            
            self.triggerPopup()
        }
    }
    
    func didUpdateTrackingState(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.trackingStateText = text
        }
    }
    
    
    
    // MARK: - Helpers
    
    private func isStoveLabel(_ label: String) -> Bool {
        let normalized = label.lowercased()
        return normalized.contains("stove")
    }
    
    private func isOutletLabel(_ label: String) -> Bool {
        let normalized = label.lowercased()
        return normalized.contains("outlet")
    }
    
    private func isStairsLabel(_ label: String) -> Bool {
        let normalized = label.lowercased()
        return normalized.contains("stairs")
    }

    private func isDangerObjectNear(label: String, distance: Float?) -> Bool {
        guard let distance else { return false }
        
        let isDanger =
            isStoveLabel(label) || isOutletLabel(label) || isStairsLabel(label)
        
        return isDanger && distance <= dangerDistanceThreshold
    }
    
    private func isDangerLabel(_ label: String) -> Bool {
        isStoveLabel(label) || isOutletLabel(label) || isStairsLabel(label)
    }
    
    private func triggerPopup() {
        showPopup = true
        popupTimer?.invalidate()
        popupTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            withAnimation(.easeOut(duration: 0.3)) {
                self?.showPopup = false
            }
        }
    }
}
