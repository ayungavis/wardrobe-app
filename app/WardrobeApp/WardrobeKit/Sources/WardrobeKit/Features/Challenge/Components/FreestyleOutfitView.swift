//
//  FreestyleOutfitView.swift
//  WardrobeKit
//
//  Created by Luisa Haning Tyas on 22/08/26.
//

import SwiftUI
import DesignSystem

struct FreestyleOutfitView: View {
    let titleKey: LocalizedStringKey
    let messageKey: LocalizedStringKey
    let buttonKey: LocalizedStringKey
    let onAccept: () -> Void
    
    var body: some View {
        ZStack {
            Image("BrownCard", bundle: .module)
                .resizable()
                .ignoresSafeArea()
            VStack(alignment: .center, spacing: Spacing.lg) {
                Text(titleKey, bundle: .module)
                    .font(AppFont.roundedTitle2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Image("CameraStraight", bundle: .module)
                Text(messageKey, bundle: .module)
                    .font(AppFont.body)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Spacing.sm)
                PrimaryButtonView(Text(buttonKey, bundle: .module), action: onAccept)
                    .frame(width: 108, height: 50)
                
            }
            .padding(Spacing.lg)
        }.frame(width: 254, height: 362)
        
    }
}
