//
//  TextModifiers.swift
//  WardrobeKit
//
//  Created by Luisa Haning Tyas on 18/08/26.
//

import SwiftUI

public struct StrokeTextModifier: ViewModifier {
    public let color: Color
    public let width: CGFloat
    
    // Explicit public initializer is required when making a struct public
    public init(color: Color, width: CGFloat) {
        self.color = color
        self.width = width
    }

    public func body(content: Content) -> some View {
        ZStack {
            ZStack {
                content.offset(x: width, y: width)
                content.offset(x: -width, y: -width)
                content.offset(x: -width, y: width)
                content.offset(x: width, y: -width)
                content.offset(x: 0, y: width)
                content.offset(x: 0, y: -width)
                content.offset(x: width, y: 0)
                content.offset(x: -width, y: 0)
            }
            .foregroundColor(color)
            
            content
        }
    }
}

public extension View {
    /// Adds a solid outline stroke around text.
    func stroke(color: Color, width: CGFloat = 1) -> some View {
        self.modifier(StrokeTextModifier(color: color, width: width))
    }
}
