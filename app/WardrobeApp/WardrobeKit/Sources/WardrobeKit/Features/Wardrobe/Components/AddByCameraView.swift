import DesignSystem
import SwiftUI

#if os(iOS)
    @preconcurrency import AVFoundation
#endif

struct AddByCameraView: View {
    private enum Phase {
        case capturing
        case reviewing
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let camera: CameraService

    @State private var review: GarmentReviewModel
    @State private var phase: Phase = .capturing
    @State private var permission: CameraPermission = .notDetermined
    @State private var isCapturing = false
    @State private var capturedCount = 0
    @State private var alertError: AppError?
    @State private var sessionTask: Task<Void, Never>?

    init(camera: CameraService, review: GarmentReviewModel) {
        self.camera = camera
        _review = State(wrappedValue: review)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .capturing: capturePhase
                case .reviewing: reviewPhase
                }
            }
            .navigationTitle(Text(title, bundle: .module))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar { toolbar }
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
                    if newPhase == .active, phase == .capturing, permission != .granted {
                        permission = camera.permission
                        startSessionIfNeeded()
                    }
                }
        }
    }

    private var title: LocalizedStringKey {
        phase == .capturing ? "wardrobe.add.camera.title" : "wardrobe.review.title"
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            switch phase {
            case .capturing:
                Button {
                    Task { await beginReview() }
                } label: {
                    Text("wardrobe.scan.review", bundle: .module)
                }
                .disabled(capturedCount == 0 || isCapturing)
            case .reviewing:
                Button {
                    review.commit(completionID: nil, at: Date())
                    dismiss()
                } label: {
                    Text("wardrobe.review.confirm", bundle: .module)
                }
                .disabled(review.garments.isEmpty)
            }
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

    private var capturePhase: some View {
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
    }

    @ViewBuilder
    private var reviewPhase: some View {
        if review.isScanning {
            ProgressView {
                Text("wardrobe.scan.processing", bundle: .module)
            }
        } else if review.garments.isEmpty {
            ContentUnavailableView {
                Label { Text("wardrobe.scan.empty", bundle: .module) } icon: {
                    Image(systemName: "tshirt")
                }
            } actions: {
                Button {
                    resumeCapturing()
                } label: {
                    Text("wardrobe.scan.retake", bundle: .module)
                }
            }
        } else {
            List {
                GarmentReviewListView(review: review, allowsMatching: false)
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
            Text("camera.permission.denied.wardrobe", bundle: .module)
        }
    }

    private func beginReview() async {
        sessionTask?.cancel()
        camera.stopSession()
        phase = .reviewing
        await review.finishScanning()
    }

    private func resumeCapturing() {
        capturedCount = 0
        phase = .capturing
        startSessionIfNeeded()
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
