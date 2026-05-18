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
    var showStarRewardAnimation: Bool = false
    
    private struct DetectionSample {
        let label: String
        let confidence: Float
        let boundingBox: CGRect?
        let distanceInMeters: Float?
        let date: Date
    }

    private var recentDetections: [DetectionSample] = []

    private let detectionMemoryLimit = 5
    private let minimumStableDetections = 2
    private let maximumMissedDetections = 3

    private var missedDetectionCount = 0
    
    private enum DetectionState {
        case noObject // No hay objeto estable
        case objectSeen // Hay objeto peligroso detectado, pero todavia no esta cerca
        case dangerNear(startTime: Date) // Esta cerca y empezo el contador de peligro
        case dangerHeld // Lleva cerca mas de 5seg, entonces se muestra el filtro rojo
        case safeRecovering(startTime: Date) // Ya se alejo o se perdio el peligro, y esta contando los 5seg seguros
        case rewarded // Ya gano estrella por este ciclo
    }
    
    private var detectionState: DetectionState = .noObject

//    private var dangerStartTime: Date?
//    private var safeStartTime: Date?
//    private var hasEarnedStarForCurrentDanger = false
//    private var wasInDangerZone = false

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

        switch detectionState {
        case .noObject:
            showRedFilter = false

            if isDangerLabel(detectedLabel) {
                detectionState = isDangerNear
                    ? .dangerNear(startTime: now)
                    : .objectSeen
            }

        case .objectSeen:
            showRedFilter = false

            if detectedLabel.isEmpty {
                detectionState = .noObject
            } else if isDangerNear {
                detectionState = .dangerNear(startTime: now)
            }

        case .dangerNear(let startTime):
            if detectedLabel.isEmpty {
                detectionState = .safeRecovering(startTime: now)
                showRedFilter = false
                return
            }

            if !isDangerNear {
                detectionState = .safeRecovering(startTime: now)
                showRedFilter = false
                return
            }

            if now.timeIntervalSince(startTime) >= dangerStayDuration {
                detectionState = .dangerHeld
                showRedFilter = true
            }

        case .dangerHeld:
            if detectedLabel.isEmpty || !isDangerNear {
                detectionState = .safeRecovering(startTime: now)
                showRedFilter = false
            } else {
                showRedFilter = true
            }

        case .safeRecovering(let startTime):
            showRedFilter = false

            if isDangerNear {
                detectionState = .dangerNear(startTime: now)
                return
            }

            if now.timeIntervalSince(startTime) >= safeStayDuration {
                starCounter += 1
                triggerStarRewardAnimation()
                detectionState = .rewarded
            }

        case .rewarded:
            showRedFilter = false

            if detectedLabel.isEmpty {
                detectionState = .noObject
            } else if isDangerNear {
                detectionState = .dangerNear(startTime: now)
            } else {
                detectionState = .objectSeen
            }
        }
    }
    
    private func triggerStarRewardAnimation() {
        showStarRewardAnimation = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            withAnimation(.easeOut(duration: 0.25)) {
                self?.showStarRewardAnimation = false
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
    
    private func addDetectionSample(
        label: String,
        confidence: Float,
        boundingBox: CGRect?,
        distanceInMeters: Float?
    ) {
        let sample = DetectionSample(
            label: label,
            confidence: confidence,
            boundingBox: boundingBox,
            distanceInMeters: distanceInMeters,
            date: Date()
        )

        recentDetections.append(sample)

        if recentDetections.count > detectionMemoryLimit {
            recentDetections.removeFirst()
        }
    }
    
    private func stableDetection() -> DetectionSample? {
        let validSamples = recentDetections.filter { $0.confidence >= confidenceThreshold }

        guard validSamples.count >= minimumStableDetections else {
            return nil
        }

        let groupedByLabel = Dictionary(grouping: validSamples) { normalizedLabel($0.label) }

        guard let strongestGroup = groupedByLabel.values.max(by: { $0.count < $1.count }),
              strongestGroup.count >= minimumStableDetections else {
            return nil
        }

        let latest = strongestGroup.last
        let smoothedDistance = medianDistance(from: strongestGroup)

        return DetectionSample(
            label: latest?.label ?? "",
            confidence: strongestGroup.map(\.confidence).max() ?? 0,
            boundingBox: latest?.boundingBox,
            distanceInMeters: smoothedDistance,
            date: Date()
        )
    }
    
    func didUpdateDetection(
        label: String,
        confidence: Float,
        boundingBox: CGRect?,
        distanceInMeters: Float?
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            guard confidence >= self.confidenceThreshold else {
                self.handleMissedDetection()
                return
            }

            self.missedDetectionCount = 0

            self.addDetectionSample(
                label: label,
                confidence: confidence,
                boundingBox: boundingBox,
                distanceInMeters: distanceInMeters
            )

            guard let stable = self.stableDetection() else {
                return
            }

            self.detectedLabel = self.displayLabel(stable.label)
            self.confidence = stable.confidence
            self.distanceInMeters = stable.distanceInMeters
            self.boundingBox = self.isDangerNear ? stable.boundingBox : nil

            self.updateDangerZoneState()

            if let modelName = self.modelNameForCurrentDanger, self.isDangerNear {
                self.arManager.placeModelIfNeeded(
                    modelName: modelName,
                    boundingBox: stable.boundingBox
                )
            } else {
                self.arManager.removeModel()
            }

            self.triggerPopup()
        }
    }
    
    private func handleMissedDetection() {
        missedDetectionCount += 1

        guard missedDetectionCount >= maximumMissedDetections else {
            updateDangerZoneState()
            return
        }

        recentDetections.removeAll()
        distanceInMeters = nil
        detectedLabel = ""
        confidence = 0
        boundingBox = nil
        arManager.removeModel()

        switch detectionState {
        case .dangerNear, .dangerHeld:
            detectionState = .safeRecovering(startTime: Date())
        default:
            detectionState = .noObject
        }

        updateDangerZoneState()
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
    
    private func normalizedLabel(_ label: String) -> String {
        label
            .replacingOccurrences(of: "_", with: " ")
            .lowercased()
    }

    private func displayLabel(_ label: String) -> String {
        label
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private func medianDistance(from samples: [DetectionSample]) -> Float? {
        let distances = samples
            .compactMap(\.distanceInMeters)
            .filter { $0.isFinite && $0 > 0 }

        guard !distances.isEmpty else { return nil }

        let sorted = distances.sorted()
        let middle = sorted.count / 2

        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        } else {
            return sorted[middle]
        }
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
