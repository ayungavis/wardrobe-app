import DesignSystem
import PhotosUI
import SwiftUI

// ponytail: strings here are deliberately NOT localized (`Text(verbatim:)`),
// same as the dev menu that opens it — no user ever reads them.

struct MatchBenchmarkView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: MatchBenchmarkViewModel
    @State private var selectedPhotos: [PhotosPickerItem] = []

    init(viewModel: MatchBenchmarkViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            List {
                garmentsSection
                actionsSection
                reportSection
            }
            .navigationTitle(Text(verbatim: "Match benchmark"))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Text("common.done", bundle: .module)
                        }
                    }
                }
        }
        .presentationDetents([.large])
    }

    private var garmentsSection: some View {
        Section {
            ForEach(viewModel.groups) { group in
                LabeledContent {
                    Text(verbatim: "\(group.garmentCount) detected")
                } label: {
                    Text(verbatim: "Garment \(group.id + 1) — \(group.photoCount) photos")
                }
            }
            picker
        } header: {
            Text(verbatim: "Labelled garments")
        } footer: {
            Text(verbatim: "One batch per physical garment: pick 2–5 photos of the same "
                + "piece of clothing, taken on different days or in different light. "
                + "Add a trap too — two different garments of a similar colour.")
        }
    }

    private var picker: some View {
        PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 10, matching: .images) {
            if viewModel.isScanning {
                HStack(spacing: Spacing.sm) {
                    ProgressView()
                    Text(verbatim: "Scanning…")
                }
            } else {
                Text(verbatim: "Add garment")
            }
        }
        .disabled(viewModel.isScanning)
        .onChange(of: selectedPhotos) { _, newItems in
            Task { await load(newItems) }
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                viewModel.run()
            } label: {
                Text(verbatim: "Run")
            }
            .disabled(viewModel.groups.count < 2 || viewModel.isScanning)

            Button(role: .destructive) {
                viewModel.reset()
            } label: {
                Text(verbatim: "Clear")
            }
            .disabled(viewModel.groups.isEmpty)
        } footer: {
            Text(verbatim: "Nothing is written to the wardrobe. Two garments minimum, "
                + "because a benchmark needs at least one pair that should not match.")
        }
    }

    @ViewBuilder
    private var reportSection: some View {
        if let report = viewModel.report {
            Section {
                Text(verbatim: report.formatted)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            } header: {
                Text(verbatim: "Report")
            } footer: {
                Text(verbatim: "Also written to the Console under \"Benchmark\".")
            }
        }
    }

    private func load(_ pickerItems: [PhotosPickerItem]) async {
        var photos: [Data] = []
        for item in pickerItems {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            photos.append(data)
        }
        selectedPhotos = []
        viewModel.add(photos: photos)
    }
}
