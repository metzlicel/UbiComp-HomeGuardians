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
            
            // Filtro rojo si se permanece en Danger Zone
            if viewModel.showRedFilter {
                Color.red.opacity(0.35)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: viewModel.showRedFilter)
            }
            
            if viewModel.showStarRewardAnimation {
                StarRewardAnimationView()
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                    .zIndex(10)
            }
            
            // Bounding box overlay
            if viewModel.isDangerNear, let box = viewModel.boundingBox {
                BoundingBoxOverlay(
                    boundingBox: box,
                    label: viewModel.detectedLabel
                )
            }
            
            // Detection info panel - top right
            VStack {
                HStack {
                    Spacer()
                    
                    VStack(alignment: .center, spacing: 12) {
                        
                        // Precision
                        if !viewModel.detectedLabel.isEmpty {
                            Text("Precision: \(viewModel.confidenceText)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(viewModel.confidenceColor.opacity(0.85))
                                .clipShape(Capsule())
                        }
                        
                        // Detection popup
                        if viewModel.showPopup {
                            DetectionPopup(
                                label: viewModel.detectedLabel,
                                confidence: viewModel.confidenceText,
                                color: viewModel.confidenceColor
                            )
                            .frame(width: 220)
                            .transition(.scale(scale: 0.85).combined(with: .opacity))
                            .animation(.spring(duration: 0.3), value: viewModel.showPopup)
                        }
                        
                        // Distance
                        if !viewModel.distanceText.isEmpty {
                            Text("Distance: \(viewModel.distanceText)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(.black.opacity(0.6))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.white.opacity(0.7))
                            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
                    )
                }
                
                Spacer()
            }
            .padding(.top, 16)
            .padding(.trailing, 16)
            
            // DangerZone alert at bottom
            if viewModel.isDangerNear {
                VStack {
                    Spacer()
                    
                    Text(viewModel.isDangerText)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(Color.red.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .shadow(radius: 12)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 95)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.25), value: viewModel.isDangerNear)
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
                    
                    Text("⭐ \(viewModel.starCounter)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.yellow.opacity(0.9))
                        .clipShape(Capsule())
                        .shadow(radius: 8)
                    
                    Spacer()
                                    
                    
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

// MARK: Star Animation
struct StarRewardAnimationView: View {
    @State private var scale: CGFloat = 0.25
    @State private var opacity: Double = 0
    @State private var rotation: Double = -12
    @State private var yOffset: CGFloat = 20

    var body: some View {
        Image("star")
            .resizable()
            .scaledToFit()
            .frame(width: 220, height: 220)
            .scaleEffect(scale)
            .opacity(opacity)
            .rotationEffect(.degrees(rotation))
            .offset(y: yOffset)
            .shadow(color: .yellow.opacity(0.55), radius: 24)
            .onAppear {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) {
                    scale = 1.15
                    opacity = 1
                    rotation = 8
                    yOffset = -8
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        scale = 1.0
                        rotation = 0
                        yOffset = 0
                    }
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation(.easeIn(duration: 0.3)) {
                        scale = 1.35
                        opacity = 0
                        yOffset = -30
                    }
                }
            }
    }
}
