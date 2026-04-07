//
//  ResultsView.swift
//  HomeGuardians
//
//  Created by Marlon Corona Arango on 15/03/26.
//

import Foundation
import SwiftUI

struct ResultsView: View {
    
    let label: String
    let confidenceText: String
    let confidenceColor: Color
    let isClassifying: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            if isClassifying {
                ProgressView("Analysing image…")
                    .padding()
            } else if !label.isEmpty {
                VStack(spacing: 6) {
                    Text(label)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                    
                    Text(confidenceText)
                        .font(.headline)
                        .foregroundColor(confidenceColor)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(confidenceColor.opacity(0.12))
                        .cornerRadius(20)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.systemGray6))
                .cornerRadius(16)
                .padding(.horizontal)
            }
        }
    }
}
