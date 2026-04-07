//
//  InstructionsView_3.swift
//  HomeGuardians
//
//  Created by Metzli Celeste on 05/04/26.
//

import SwiftUI

struct InstructionsView_3: View {
    
    @State var animate = false
    @State private var navigateToScanner = false

    var body: some View {
        NavigationStack {
            ZStack {
                Image("3")
                    .resizable()
                    .scaledToFill()
                
                GeometryReader { proxy in
                    Image("star")
                        .resizable()
                        .scaledToFit()
                        .frame(width: proxy.size.width * 0.8, height: 200)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2.5)

                    // 1. Escala (crece)
                            .scaleEffect(animate ? 1.25 : 1.0)
                            
                            // 2. Brinquito (sube ligeramente)
                            .offset(y: animate ? -12 : 0)
                            
                            // 3. Animación tipo resorte
                            .animation(
                                .spring(response: 0.35, dampingFraction: 0.55, blendDuration: 0)
                                    .repeatForever(autoreverses: true),
                                value: animate
                            )
                            
                            .onAppear {
                                animate.toggle()
                            }
                }
                
                    // Start scanning button
                    Button {
                        navigateToScanner = true
                    } label: {
                        HStack (spacing: 10){
                            Text("¡Comienza!")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Image(systemName: "arrow.right.circle")
                                .font(.title2)
                            
                        }
                            
                        .foregroundColor(.white)
                        .frame(width: 230)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: [.teal, .cyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .shadow(color: .blue.opacity(0.3), radius: 12, y: 6)
                    }
                    .position(x:760,y:740)
            }
            .navigationDestination(isPresented: $navigateToScanner) {
                ScannerView()
            }
            .navigationBarHidden(true)
        }
    }
}

#Preview {
    InstructionsView_3()
}
