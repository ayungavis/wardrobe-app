import DesignSystem
import SwiftUI

public struct ConsentView: View {
    @State private var viewModel: ConsentViewModel
    private let onFinished: () -> Void

    public init(viewModel: ConsentViewModel, onFinished: @escaping () -> Void) {
        _viewModel = State(wrappedValue: viewModel)
        self.onFinished = onFinished
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    Text("consent.intro", bundle: .module)

                    section("consent.stores.title", "consent.stores.body")
                    aiSection
                    section("consent.control.title", "consent.control.body")
                }
                .padding(Spacing.lg)
            }
            .navigationTitle(Text("consent.title", bundle: .module))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: Spacing.sm) {
                        Button {
                            viewModel.grant()
                            onFinished()
                        } label: {
                            Text("consent.allow", bundle: .module)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            viewModel.decline()
                            onFinished()
                        } label: {
                            Text("consent.decline", bundle: .module)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(Spacing.lg)
                    .background(.thinMaterial)
                }
        }
        .interactiveDismissDisabled()
    }

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("consent.ai.title", bundle: .module)
                .font(.headline)
            Text(String(
                format: String(localized: "consent.ai.body", bundle: .module),
                viewModel.providerName
            ))
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private func section(_ title: LocalizedStringKey, _ body: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title, bundle: .module)
                .font(.headline)
            Text(body, bundle: .module)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
