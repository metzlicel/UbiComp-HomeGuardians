//
//  ScannerView.swift
//  HomeGuardians
//
//  Created by Marlon Corona Arango on 18/03/26.
//

import SwiftUI

struct ScannerView: View {
    
    @State private var viewModel = DetectionViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            
            // AR camera feed
            ARDetectionView(arView: viewModel.arManager.arView)
                .ignoresSafeArea()
            
            // Bounding box overlay
            if let box = viewModel.boundingBox {
                BoundingBoxOverlay(
                    boundingBox: box,
                    label: viewModel.detectedLabel
                )
            }
            
            // Detection popup
            if viewModel.showPopup {
                DetectionPopup(
                    label: viewModel.detectedLabel,
                    confidence: viewModel.confidenceText,
                    color: viewModel.confidenceColor
                )
                .transition(.scale(scale: 0.85).combined(with: .opacity))
                .animation(.spring(duration: 0.3), value: viewModel.showPopup)
            }
            
            // Stove alert
            if viewModel.isStoveDetected {
                VStack {
                    Text("⚠️ Estufa detectada")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.9))
                        .clipShape(Capsule())
                        .shadow(radius: 10)
                        .padding(.top, 90)
                    
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.25), value: viewModel.isStoveDetected)
            }
            
            // Top / bottom overlays
            VStack {
                HStack(alignment: .top) {
                    // Back button
                    Button {
                        viewModel.stopCamera()
                        dismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("Home")
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                    }
                    
                    Spacer()
                    
                    // Right badges
                    if !viewModel.detectedLabel.isEmpty {
                        VStack(alignment: .trailing, spacing: 8) {
                            Text(viewModel.confidenceText)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(viewModel.confidenceColor.opacity(0.85))
                                .clipShape(Capsule())
                            
                            Text(viewModel.distanceText)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.black.opacity(0.55))
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding()
                
                Spacer()
                
                VStack(spacing: 6) {
                    Text("Scanning for objects…")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                    
                    Text(viewModel.trackingStateText)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.75))
                }
                .padding(.bottom, 40)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            viewModel.startCamera()
        }
        .onDisappear {
            viewModel.stopCamera()
        }
    }
}

// MARK: - Popup

struct DetectionPopup: View {
    let label: String
    let confidence: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Text("\(label) detected")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                    
            Text(confidence)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .background(.ultraThinMaterial)
        .background(color.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.2), radius: 16)
        .padding(.horizontal, 40)
    }
}

// MARK: - Bounding box overlay

struct BoundingBoxOverlay: View {
    let boundingBox: CGRect
    let label: String
    
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let x = boundingBox.minX * w
            let y = (1 - boundingBox.maxY) * h
            let boxW = boundingBox.width * w
            let boxH = boundingBox.height * h
            
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.green, lineWidth: 2)
                    .frame(width: boxW, height: boxH)
                    .offset(x: x, y: y)
                
                Text(label)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.green)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .offset(x: x, y: max(0, y - 24))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
