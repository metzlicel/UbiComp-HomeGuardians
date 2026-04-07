//
//  Services.swift
//  HomeGuardians
//
//  Created by Marlon Corona Arango on 15/03/26.
//

import Foundation
import Vision
import CoreML
import UIKit

struct ClassificationResult {
    let label: String
    let confidence: Float
}

class ImageClassifier {
    
    private lazy var model: VNCoreMLModel? = {
        try? VNCoreMLModel(for: Resnet50().model)
    }()
    
    func classify(image: UIImage, completion: @escaping (ClassificationResult?) -> Void) {
        guard let model = model,
              let ciImage = CIImage(image: image) else {
            completion(nil)
            return
        }
        
        let request = VNCoreMLRequest(model: model) { request, error in
            guard let results = request.results as? [VNClassificationObservation],
                  let top = results.first else {
                completion(nil)
                return
            }
            let result = ClassificationResult(label: top.identifier, confidence: top.confidence)
            completion(result)
        }
        
        request.imageCropAndScaleOption = .centerCrop
        
        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
            try? handler.perform([request])
        }
    }
}
