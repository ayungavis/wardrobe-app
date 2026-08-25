import DesignSystem
import SwiftUI

public struct ProfileView: View {
    @State private var viewModel: ProfileViewModel
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: ProfileViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            List {
                accountSection
                if viewModel.isSignedIn {
                    signOutSection
                }
                deletionSection
            }
            .navigationTitle(Text("profile.title", bundle: .module))
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
        .task { viewModel.load() }
        .onChange(of: viewModel.didFinish) { _, finished in
            if finished {
                dismiss()
            }
        }
        .confirmationDialog(
            Text("profile.signOut.pending.title", bundle: .module),
            isPresented: $viewModel.isSignOutWarningPresented,
            titleVisibility: .visible
        ) {
            Button {
                Task { await viewModel.syncPendingWrites() }
            } label: {
                Text("profile.signOut.pending.sync", bundle: .module)
            }
            Button(role: .destructive) {
                Task { await viewModel.signOutDiscardingPendingWrites() }
            } label: {
                Text("profile.signOut.pending.discard", bundle: .module)
            }
            Button(role: .cancel) {} label: {
                Text("common.cancel", bundle: .module)
            }
        } message: {
            Text(pendingMessage)
        }
        .confirmationDialog(
            Text("profile.delete.confirm.title", bundle: .module),
            isPresented: $viewModel.isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                Task { await viewModel.deleteAccount() }
            } label: {
                Text("profile.delete.confirm.action", bundle: .module)
            }
            Button(role: .cancel) {} label: {
                Text("common.cancel", bundle: .module)
            }
        } message: {
            Text("profile.delete.disclosure", bundle: .module)
        }
        .alert(
            Text("profile.error.title", bundle: .module),
            isPresented: Binding(
                get: { viewModel.alertError != nil },
                set: {
                    if !$0 {
                        viewModel.alertError = nil
                    }
                }
            )
        ) {
            Button(role: .cancel) {} label: {
                Text("common.ok", bundle: .module)
            }
        } message: {
            Text(viewModel.alertError?.userMessage ?? "")
        }
    }

    private var accountSection: some View {
        Section {
            if let account = viewModel.account {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(account.fullName ?? String(localized: "profile.signedIn", bundle: .module))
                        .font(.headline)
                    if let email = account.email {
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("profile.anonymous", bundle: .module)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("profile.account.header", bundle: .module)
        }
    }

    private var signOutSection: some View {
        Section {
            Button {
                Task { await viewModel.requestSignOut() }
            } label: {
                Text("profile.signOut", bundle: .module)
            }
        } footer: {
            Text("profile.signOut.footer", bundle: .module)
        }
    }

    private var deletionSection: some View {
        Section {
            if viewModel.isDeletionRetryable {
                Text("profile.delete.retryable", bundle: .module)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button(role: .destructive) {
                viewModel.requestDeletion()
            } label: {
                if viewModel.isDeleting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if viewModel.isDeletionRetryable {
                    Text("profile.delete.retry", bundle: .module)
                } else {
                    Text("profile.delete", bundle: .module)
                }
            }
            .disabled(viewModel.isDeleting)
        } header: {
            Text("profile.delete.header", bundle: .module)
        } footer: {
            Text("profile.delete.footer", bundle: .module)
        }
    }

    private var pendingMessage: String {
        String(
            format: String(localized: "profile.signOut.pending.message", bundle: .module),
            viewModel.pendingWrites
        )
    }
}
