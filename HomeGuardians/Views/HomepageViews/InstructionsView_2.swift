//
//  InstructionsView_2.swift
//  HomeGuardians
//
//  Created by Metzli Celeste on 05/04/26.
//

import SwiftUI

struct InstructionsView_2: View {
    @State var rotate = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Image("2")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                
                GeometryReader { proxy in
                    Image("sparky")
                        .resizable()
                        .scaledToFit()
                        .frame(width: proxy.size.width * 0.8, height: 350)
                        .position(x: proxy.size.width / 2.75, y: proxy.size.height / 2)

                        .rotationEffect(.degrees(rotate ? 4 : -4))
                            .animation(
                                .easeInOut(duration: 1.0)
                                    .repeatForever(autoreverses: true),
                                value: rotate
                            )
                            .onAppear {
                                rotate.toggle()
                            }
                }
                
                
                NavigationLink(destination: InstructionsView_3(), label: {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.teal, .cyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 50)
                            .shadow(color: .blue.opacity(0.3), radius: 12, y: 6)
                            
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.title)
                                .foregroundColor(.white)
                            
                        
                    }
                })
                .position(x: 660, y: 735)
                .navigationBarHidden(true)
            }
        }
    }
}

#Preview {
    InstructionsView_2()
}
