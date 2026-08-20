//
//  TipsStageView.swift
//  WardrobeKit
//
//  Created by Luisa Haning Tyas on 20/08/26.
//
import DesignSystem
import SwiftUI

struct TipsStageView: View {
    let onContinue: (Bool) -> Void
    let onClose: () -> Void
    @State private var dontShowAgain = false
    
    var body: some View {
        ZStack(alignment: .center) {
            Color.black.opacity(0.3).ignoresSafeArea()
                
            
            VStack {
                Spacer()
                
                ZStack(alignment: .bottomTrailing) {
                    Image("TipsScreen", bundle: .module)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 345, height: 595)
                        .overlay(alignment: .top) {
                            Image("OutfitPoseIllustration", bundle: .module)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 230, height: 292)
                                .padding(.top, Spacing.xxl)
                                .padding(.horizontal, Spacing.xl)
                        }
                        .overlay(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: Spacing.md) {
                                Text("capture.tips.title", bundle: .module)
                                    .font(AppFont.title.bold())
                                    .foregroundStyle(AppColor.textPrimary)
                                
                                VStack(alignment: .leading, spacing: Spacing.xs) {
                                    bullet("capture.tips.bullet1")
                                    bullet("capture.tips.bullet2")
                                }
                                
                                Button {
                                    dontShowAgain.toggle()
                                } label: {
                                    HStack(spacing: Spacing.sm) {
                                        Image(systemName: dontShowAgain ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(dontShowAgain ? AppColor.accent : AppColor.textSecondary)
                                        Text("capture.tips.dontShowAgain", bundle: .module)
                                            .font(AppFont.body)
                                            .foregroundStyle(AppColor.textSecondary)
                                    }
                                }
                                .buttonStyle(.plain)
                                
                                HStack {
                                    Spacer()
                                    PrimaryButtonView(Text("capture.tips.gotIt", bundle: .module), minHeight: 28) {
                                        onContinue(dontShowAgain)
                                    }
                                    .fixedSize()
                                }
                            }
                            .padding(Spacing.xl)
                        }
                }
                .padding(.horizontal, Spacing.lg)
                
                Spacer()
            }
            
//            Button(action: onClose) {
//                Image(systemName: "chevron.left")
//                    .font(.system(size: 20, weight: .semibold))
//                    .foregroundStyle(.white)
//                    .padding()
//            }
        }
    }
    
    private func bullet(_ key: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            Text("•")
            Text(key, bundle: .module)
        }
        .font(AppFont.body)
        .foregroundStyle(AppColor.textPrimary)
    }
}
