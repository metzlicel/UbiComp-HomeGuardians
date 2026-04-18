//
//  ARDetectionView.swift
//  HomeGuardians
//
//  Created by OpenAI on 09/04/26.
//

import SwiftUI
import RealityKit
import ARKit

struct ARDetectionView: UIViewRepresentable {
    
    let arView: ARView
    
    func makeUIView(context: Context) -> ARView {
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) { }
}
