//
//  FontRegistration.swift
//  WardrobeKit
//
//  Created by Luisa Haning Tyas on 16/08/26.
//


import CoreText
import Foundation

public enum FontRegistration {
    public static func registerCustomFonts() {
        let fontNames = ["Allison-Regular", "SeymourOne-Regular"]
        for name in fontNames {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf") else {
                print("❌ Could not find font file: \(name).ttf")
                continue
            }
            print("✅ Found font file at: \(url)")
            let success = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            print(success ? "✅ Registered \(name)" : "❌ Failed to register \(name)")
        }
    }
}
