//
//  SplashScreenView.swift
//  WardrobeKit
//
//  Created by Luisa Haning Tyas on 25/08/26.
//


import Lottie
import SwiftUI

struct SplashScreenView: View {
    let onFinished: () -> Void

    var body: some View {
        ZStack {
            GeometryReader { geo in
                    LottieView(animation: .named("Splash Screen", bundle: .module))
                        .playbackMode(.playing(.toProgress(1, loopMode: .playOnce)))
                        .animationDidFinish { _ in
                            onFinished()
                        }
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
                .ignoresSafeArea()
        }
    }
}
