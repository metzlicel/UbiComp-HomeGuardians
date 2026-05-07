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
    
    // Contador de Stars
    var starCounter: Int = 0
    var showRedFilter: Bool = false

    private var dangerStartTime: Date?
    private var safeStartTime: Date?
    private var hasEarnedStarForCurrentDanger = false
    private var wasInDangerZone = false

    private let dangerStayDuration: TimeInterval = 5.0
    private let safeStayDuration: TimeInterval = 5.0
    
    // Detectar DangerZone
    private let dangerDistanceThreshold: Float = 1.0
//    var isStoveDetected: Bool = false
//    var isOutletDetected: Bool = false
//    var isStairsDetected: Bool = false
    
    var isDangerNear: Bool {
        guard let distanceInMeters else { return false }
        return isDangerLabel(detectedLabel) && distanceInMeters <= dangerDistanceThreshold
    }

    var isDangerText: String {
        if isStoveLabel(detectedLabel) {
            return "¡Está caliente, caliente! Mejor mira desde lejos"
        }
        if isOutletLabel(detectedLabel) {
            return "¡Aquí pica como abeja. Mejor aleja tus manitas"
        }
        if isStairsLabel(detectedLabel) {
            return "¡Yo estoy acompañado! Busca un acompañante para acercarte aquí"
        }
        return ""
    }
//    var shouldShowStoveWarning: Bool {
//        guard let distanceInMeters else { return false }
//        return isStoveLabel(detectedLabel) && distanceInMeters <= dangerDistanceThreshold
//    }
//
//    var shouldShowOutletWarning: Bool {
//        guard let distanceInMeters else { return false }
//        return isOutletLabel(detectedLabel) && distanceInMeters <= dangerDistanceThreshold
//    }
//
//    var shouldShowStairsWarning: Bool {
//        guard let distanceInMeters else { return false }
//        return isStairsLabel(detectedLabel) && distanceInMeters <= dangerDistanceThreshold
//    }
//
//    var warningText: String {
//        if shouldShowStoveWarning {
//            return "¡Está caliente, caliente! Mejor mira desde lejos"
//        }
//        if shouldShowOutletWarning {
//            return "¡Aquí pica como abeja. Mejor aleja tus manitas"
//        }
//        if shouldShowStairsWarning {
//            return "Yo ruedo y ruedo. ¡Pero tu camina como grande!"
//        }
//        return ""
//    }

    var modelNameForCurrentDanger: String? {
        if isStoveLabel(detectedLabel) {
            return "Stufi"
        }
        if isOutletLabel(detectedLabel) {
            return "Sparky"
        }
        if isStairsLabel(detectedLabel) {
            return "Stepys" 
        }
        return nil
    }
    
    private func updateDangerZoneState() {
        let now = Date()
        
        if isDangerNear {
            wasInDangerZone = true
            safeStartTime = nil
            
            if dangerStartTime == nil {
                dangerStartTime = now
            }
            
            if let dangerStartTime,
               now.timeIntervalSince(dangerStartTime) >= dangerStayDuration {
                showRedFilter = true
            }
            
        } else {
            dangerStartTime = nil
            showRedFilter = false
            
            guard wasInDangerZone else { return }
            
            if safeStartTime == nil {
                safeStartTime = now
            }
            
            if let safeStartTime,
               now.timeIntervalSince(safeStartTime) >= safeStayDuration,
               !hasEarnedStarForCurrentDanger {
                
                starCounter += 1
                hasEarnedStarForCurrentDanger = true
                wasInDangerZone = false
                self.safeStartTime = nil
            }
        }
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
//                self?.isStoveDetected = false
//                self?.isOutletDetected = false
//                self?.isStairsDetected = false
                self?.distanceInMeters = nil
                self?.detectedLabel = ""
                self?.confidence = 0
                self?.boundingBox = nil
                self?.arManager.removeModel()
                self?.updateDangerZoneState()
            }
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.detectedLabel = label
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
            
            self.confidence = confidence
//            self.boundingBox = boundingBox
            self.distanceInMeters = distanceInMeters
            self.boundingBox = self.isDangerNear ? boundingBox : nil
            
            self.updateDangerZoneState()

//            self.isStoveDetected = self.isStoveLabel(label)
//            self.isOutletDetected = self.isOutletLabel(label)
//            self.isStairsDetected = self.isStairsLabel(label)

                   
            if let modelName = self.modelNameForCurrentDanger, self.isDangerNear {
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

//    private func isDangerObjectNear(label: String, distance: Float?) -> Bool {
//        guard let distance else { return false }
//        
//        let isDanger =
//            isStoveLabel(label) || isOutletLabel(label) || isStairsLabel(label)
//        
//        return isDanger && distance <= dangerDistanceThreshold
//    }
    
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
