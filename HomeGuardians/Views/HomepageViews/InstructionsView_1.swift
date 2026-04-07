//
//  InstructionsView_1.swift
//  HomeGuardians
//
//  Created by Metzli Celeste on 05/04/26.
//

import SwiftUI

struct InstructionsView_1: View {
    
    @State var move = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Image("1")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                
                GeometryReader { proxy in
                    Image("ipad")
                        .resizable()
                        .scaledToFit()
                        .frame(width: proxy.size.width * 0.8, height: 450)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2.5)

                        .offset(x: move ? 40 : -40)
                                    .animation(
                                    .easeInOut(duration: 1.5)
                                    .repeatForever(autoreverses: true),
                                    value: move
                                )
                                .onAppear {
                                    move.toggle()
                                }
                }
                
                
                NavigationLink(destination: InstructionsView_2(), label: {
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
                .position(x: 1000, y: 735)
                .navigationBarHidden(true)
            }
        }
    }
}

#Preview {
    InstructionsView_1()
}
