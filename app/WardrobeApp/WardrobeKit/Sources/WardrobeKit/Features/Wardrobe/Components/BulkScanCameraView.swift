import DesignSystem
import SwiftUI

#if os(iOS)
    @preconcurrency import AVFoundation
#endif

/// A lightweight, repeatable capture loop for bulk-scanning outfits straight
/// from the camera — snap several photos in a row, each fed into the same
/// GarmentReviewModel pipeline BulkScanView uses for library photos.
struct BulkScanCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let camera: CameraService
    let review: GarmentReviewModel

    @State private var permission: CameraPermission = .notDetermined
    @State private var isCapturing = false
    @State private var capturedCount = 0
    @State private var alertError: AppError?
    @State private var sessionTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                switch permission {
                case .granted:
                    cameraContent
                case .notDetermined:
                    ProgressView()
                case .denied, .restricted:
                    deniedState
                }
            }
            .navigationTitle(Text(verbatim: "Camera"))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            Task {
                                await review.finishScanning()
                                dismiss()
                            }
                        } label: {
                            Text("wardrobe.review.confirm", bundle: .module)
                        }
                        .disabled(capturedCount == 0)
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .cancel) {
                            review.cancel()
                            dismiss()
                        } label: {
                            Text("common.cancel", bundle: .module)
                        }
                    }
                }
                .alert(
                    Text("common.errorTitle", bundle: .module),
                    isPresented: Binding(
                        get: { alertError != nil },
                        set: {
                            if !$0 {
                                alertError = nil
                            }
                        }
                    )
                ) {
                    Button(role: .cancel) {} label: { Text("common.ok", bundle: .module) }
                } message: {
                    Text(alertError?.userMessage ?? "")
                }
                .task { await requestPermissionIfNeeded() }
                .onDisappear {
                    sessionTask?.cancel()
                    camera.stopSession()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active, permission != .granted {
                        permission = camera.permission
                        startSessionIfNeeded()
                    }
                }
        }
    }

    private var cameraContent: some View {
        ZStack(alignment: .bottom) {
            #if os(iOS)
                if let session = camera.previewSession {
                    CameraPreviewView(session: session)
                        .ignoresSafeArea()
                }
            #endif

            VStack(spacing: Spacing.md) {
                if capturedCount > 0 {
                    Text("bulkScan.captured \(capturedCount)", bundle: .module)
                        .font(AppFont.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(Capsule().fill(.ultraThinMaterial))
                }

                Button {
                    capture()
                } label: {
                    Circle()
                        .fill(.white)
                        .frame(width: 72, height: 72)
                        .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 4).frame(width: 84, height: 84))
                }
                .disabled(isCapturing)
                .padding(.bottom, Spacing.xl)
            }
        }
    }

    private var deniedState: some View {
        ContentUnavailableView {
            Label { Text("camera.permission.denied.title", bundle: .module) } icon: { Image(systemName: "camera") }
        } description: {
            Text(verbatim: "Enable camera access in Settings to scan outfits.")
        }
    }

    private func requestPermissionIfNeeded() async {
        permission = camera.permission
        if permission == .notDetermined {
            permission = await camera.requestPermission()
        }
        startSessionIfNeeded()
    }

    private func startSessionIfNeeded() {
        guard permission == .granted else { return }
        sessionTask?.cancel()
        sessionTask = Task {
            do {
                try await camera.startSession()
            } catch {
                Log.report(error, logger: Log.ui)
                alertError = .cameraUnavailable
            }
        }
    }

    private func capture() {
        guard !isCapturing else { return }
        isCapturing = true
        Task {
            defer { isCapturing = false }
            do {
                let data = try await camera.capturePhoto()
                review.scan(photo: data)
                capturedCount += 1
            } catch {
                Log.report(error, logger: Log.ui)
                alertError = .captureFailed
            }
        }
    }
}
