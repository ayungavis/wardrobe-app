//
//  HistoryDetailView.swift
//  WardrobeKit
//
//  Created by Luisa Haning Tyas on 17/08/26.
//


import DesignSystem
import SwiftUI

public struct HistoryDetailView: View {
    public let completion: CompletedChallenge
    public let photoData: Data?
    let viewModel: HistoryViewModel
    
    public init(completion: CompletedChallenge, photoData: Data?, viewModel: HistoryViewModel) {
        self.completion = completion
        self.photoData = photoData
        self.viewModel = viewModel
    }
    
    public var body: some View {
        ZStack {
            // Main Background
            Image("appBG", bundle: .module)
                .resizable()
                .ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                ZStack(alignment: .top) {
                    
                    // Main Content Stack
                    VStack(spacing: 0) {
                        // 1. Top Canvas / Polaroid
                        HistoryPolaroidCardView(
                            completion: completion,
                            photoData: photoData
                        )
                        .padding(.horizontal, Spacing.lg)
                        .padding(.top, Spacing.lg)
                        .zIndex(2)
                        .frame(width : 345, height : 614)
                        
                        // 2. Receipt Card Background + Content
                        receiptContent
                            .padding(.horizontal, Spacing.lg)
                            .zIndex(1)
                            .frame(width : 345, height : 465)
                    }
                    
                    // 3. Trinkets Overlay
                    // Allows you to use absolute positioning (x/y) for your tape and pins
                    GeometryReader { geo in
                        // Example Tape Placement:
                        // Image("masking_tape_asset", bundle: .module)
                        //     .position(x: geo.size.width / 2, y: /* calculate based on polaroid height */)
                    }
                }
            }
        }
        .navigationTitle(Text("tab.history", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var receiptContent: some View {
        // Layer the text content directly over your existing receipt paper asset
        ZStack(alignment: .top) {
            
            // Your custom torn paper asset
            Image("TornReceipt", bundle: .module)
                .resizable()
            
            VStack(alignment: .leading, spacing: 16) {
                
                // Header Info
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        Text("Challenge :").bold()
                        Text("Unused Wear") // Fallback until short titles are added
                    }
                    
                    HStack(alignment: .top) {
                        Text("Date :").bold()
                        Text(formattedDate(completion.completedAt))
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Description :").bold()
                        Text(completion.card.prompt)
                            .font(.body)
                            .foregroundColor(AppColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                // If your dotted line is a separate asset, place it here:
                // Image("dotted_line_asset", bundle: .module)
                //     .resizable()
                //     .frame(height: 1)
                //     .padding(.vertical, 8)
                
                
                wearSection
                
            }
            // Adjust these paddings to match the inner safe area of your specific receipt asset
            .padding(.horizontal, Spacing.sm)
            .padding(.top, Spacing.xxl)
        }
        
    }
    private var wearSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Wear :").bold()
            
            let garments = viewModel.garmentsWorn(in: completion)
            
            if garments.isEmpty {
                Text("No garments recorded for this outfit")
                    .font(.caption)
                    .foregroundStyle(AppColor.textSecondary)
            } else {
                HStack(spacing: 16) {
                    ForEach(garments, id: \.item.id) { entry in
                        garmentView(item: entry.item, wearCount: entry.wearCount)
                    }
                }
            }
        }
        .padding(.bottom, 24)
    }
    private func garmentView(item: WardrobeItem, wearCount: Int) -> some View {
        VStack(spacing: 8) {
            if let data = viewModel.thumbnailData(for: item) {
                DownsampledPhotoView(data: data)
                    .frame(width: 130, height: 130)
               
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppColor.surface)
                    .frame(width: 80, height: 80)
            }
            Text("\(wearCount)x")
                .font(.subheadline)
                .bold()
                .foregroundColor(.black)
        }
    }
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM dd, yyyy"
        return formatter.string(from: date)
    }
    
}
