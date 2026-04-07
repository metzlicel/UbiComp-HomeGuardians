//
//  HomeView.swift
//  HomeGuardians
//
//  Created by Marlon Corona Arango on 18/03/26.
//

import Foundation
import SwiftUI

struct HomeView: View {
    
    var body: some View {
        NavigationStack {
            ZStack {
                Image("homepage")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                
                NavigationLink(destination: InstructionsView_1(), label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(
                                LinearGradient(
                                    colors: [.teal, .cyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 700, height: 80)
                            .shadow(color: .blue.opacity(0.3), radius: 12, y: 6)

                        HStack (spacing: 20){
                            Text("¡Empieza a explorar!")
                                .font(.largeTitle)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)

                            Image(systemName: "magnifyingglass")
                                .font(.largeTitle)
                                .foregroundColor(.white)
                            
                        }
                    }
                })
                .position(x: 750, y: 530)
                .navigationBarHidden(true)
            }
        }
    }
}

#Preview("HomeView") {
    HomeView()
}
