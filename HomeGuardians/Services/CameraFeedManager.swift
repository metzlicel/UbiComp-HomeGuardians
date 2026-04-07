//
//  CameraFeedManager.swift
//  HomeGuardians
//
//  Created by Marlon Corona Arango on 18/03/26.
//

import Foundation
import AVFoundation
import Vision
import UIKit

protocol CameraFeedManagerDelegate: AnyObject {
    func didDetect(label: String, confidence: Float, boundingBox: CGRect?)
}

class CameraFeedManager: NSObject {
    
    weak var delegate: CameraFeedManagerDelegate?
    
    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let processingQueue = DispatchQueue(label: "camera.processing.queue")
    
    private var lastProcessedTime = Date()
    private let processingInterval: TimeInterval = 0.5 // process a frame every 0.5s
    
    private lazy var coreMLModel: VNCoreMLModel? = {
        try? VNCoreMLModel(for: Resnet50().model)
    }()
    
    func startSession() {
        sessionQueue.async { [weak self] in
            self?.configureSession()
            self?.session.startRunning()
        }
    }
    
    func stopSession() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }
    
    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .high
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                    for: .video,
                                                    position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        
        session.addInput(input)
        
        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
        
        session.commitConfiguration()
    }
    
    private func processFrame(_ pixelBuffer: CVPixelBuffer) {
        guard let model = coreMLModel else { return }
        
        // For object detection models — use VNCoreMLRequest with bounding boxes
        let request = VNCoreMLRequest(model: model) { [weak self] request, _ in
            guard let self = self else { return }
            
            // Object detection result (custom model)
            if let observations = request.results as? [VNRecognizedObjectObservation],
               let top = observations.first,
               let label = top.labels.first {
                let box = top.boundingBox
                self.delegate?.didDetect(label: label.identifier,
                                         confidence: label.confidence,
                                         boundingBox: box)
                return
            }
            
            // Classification result (ResNet50 fallback)
            if let observations = request.results as? [VNClassificationObservation],
               let top = observations.first {
                self.delegate?.didDetect(label: top.identifier,
                                         confidence: top.confidence,
                                         boundingBox: nil)
            }
        }
        
        request.imageCropAndScaleOption = .centerCrop
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([request])
    }
}

extension CameraFeedManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let now = Date()
        guard now.timeIntervalSince(lastProcessedTime) >= processingInterval,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastProcessedTime = now
        processFrame(pixelBuffer)
    }
}
