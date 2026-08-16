//
//  FigmaPosition.swift
//  WardrobeKit
//
//  Created by Luisa Haning Tyas on 16/08/26.
//


import Foundation

struct FigmaPosition {
    let x: CGFloat            // fraction 0-1, relative to its container
    let y: CGFloat
    let widthFraction: CGFloat
    let rotation: Double      // degrees, 0 if none

    init(
        figmaX: CGFloat,
        figmaY: CGFloat,
        figmaWidth: CGFloat,
        figmaHeight: CGFloat,
        frameWidth: CGFloat,
        frameHeight: CGFloat,
        rotation: Double = 0
    ) {
        self.x = (figmaX + figmaWidth / 2) / frameWidth
        self.y = (figmaY + figmaHeight / 2) / frameHeight
        self.widthFraction = figmaWidth / frameWidth
        self.rotation = rotation
    }
}
