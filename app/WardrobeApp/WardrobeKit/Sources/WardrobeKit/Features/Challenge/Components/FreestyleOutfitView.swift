//
//  FreestyleOutfitView.swift
//  WardrobeKit
//
//  Created by Luisa Haning Tyas on 22/08/26.
//

import SwiftUI
import DesignSystem

struct FreestyleOutfitView: View {
    let onAccept: () -> Void
    var body: some View {
        ZStack {
            Image("BrownCard", bundle: .module)
                .resizable()
                .ignoresSafeArea()
            VStack(alignment: .center, spacing: Spacing.xl) {
                Spacer()
                Image("CameraStraight", bundle: .module)
                Text("challenge.freestyle.text", bundle: .module)
                    .font(AppFont.body)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                PrimaryButtonView(Text("challenge.accept", bundle: .module), action: onAccept)
                    .frame(width: 108, height: 50)
                Spacer()
            }
            .padding(Spacing.lg)
        }.frame(width: 254, height: 343)
        
    }
}
