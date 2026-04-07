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
class DetectionViewModel: CameraFeedManagerDelegate {
    
    var detectedLabel: String = ""
    var confidence: Float = 0
    var boundingBox: CGRect? = nil
    var showPopup: Bool = false
    var isLive: Bool = true
    
    // Detectar estufa
    var isStoveDetected: Bool = false
    
    let cameraManager = CameraFeedManager()
    
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
        default:     return .red
        }
    }
    
    func startCamera() {
        cameraManager.delegate = self
        cameraManager.startSession()
    }
    
    func stopCamera() {
        cameraManager.stopSession()
    }
    
    
    // MARK: - CameraFeedManagerDelegate
    
    func didDetect(label: String, confidence: Float, boundingBox: CGRect?) {
        guard confidence >= confidenceThreshold else {
            DispatchQueue.main.async { [weak self] in
            self?.isStoveDetected = false
            }
            return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.detectedLabel = label
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
            self.confidence = confidence
            self.boundingBox = boundingBox
            
            // Detectar estufa
            self.isStoveDetected = self.isStoveLabel(label)
            
            self.triggerPopup()
        }
    }
    
    // funcion para detectar estufa
    private func isStoveLabel(_ label: String) -> Bool {
        let normalized = label.lowercased()
        return normalized.contains("stove") ||
               normalized.contains("oven") ||
               normalized.contains("range")
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
