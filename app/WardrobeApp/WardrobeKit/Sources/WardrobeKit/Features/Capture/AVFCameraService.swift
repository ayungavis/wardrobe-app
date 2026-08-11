#if os(iOS)
    @preconcurrency import AVFoundation
    import Foundation

    /// Real-device camera backed by AVFoundation.
    @MainActor
    public final class AVFCameraService: CameraService {
        private let session = AVCaptureSession()
        private let output = AVCapturePhotoOutput()
        private var isConfigured = false
        private var inFlightDelegate: PhotoCaptureDelegate?
        private var position: AVCaptureDevice.Position = .back
        private var currentInput: AVCaptureDeviceInput?
        public private(set) var isFlashOn = false

        public init() {}

        public var permission: CameraPermission {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: .granted
            case .notDetermined: .notDetermined
            case .denied: .denied
            case .restricted: .restricted
            @unknown default: .denied
            }
        }

        public var previewSession: AVCaptureSession? {
            session
        }

        public func requestPermission() async -> CameraPermission {
            _ = await AVCaptureDevice.requestAccess(for: .video)
            return permission
        }

        public func startSession() async throws {
            guard permission == .granted else { throw AppError.cameraUnavailable }

            if !isConfigured {
                // ponytail: configuration on the main actor; move to a session
                // queue if Instruments shows startup jank.
                session.beginConfiguration()
                session.sessionPreset = .photo
                guard
                    let input = Self.makeInput(position: position),
                    session.canAddInput(input), session.canAddOutput(output)
                else {
                    session.commitConfiguration()
                    throw AppError.cameraUnavailable
                }
                session.addInput(input)
                session.addOutput(output)
                session.commitConfiguration()
                currentInput = input
                isConfigured = true
            }

            guard !session.isRunning else { return }
            let session = session
            // startRunning blocks — keep it off the main actor.
            await Task.detached(priority: .userInitiated) { session.startRunning() }.value
        }

        /// Swaps the capture input between back and front camera.
        public func toggleCamera() async throws {
            guard isConfigured, let oldInput = currentInput else { return }
            let newPosition: AVCaptureDevice.Position = position == .back ? .front : .back

            session.beginConfiguration()
            session.removeInput(oldInput)
            guard let newInput = Self.makeInput(position: newPosition), session.canAddInput(newInput) else {
                // Restore the previous camera; never leave the session inputless.
                session.addInput(oldInput)
                session.commitConfiguration()
                throw AppError.cameraUnavailable
            }
            session.addInput(newInput)
            session.commitConfiguration()
            currentInput = newInput
            position = newPosition
            zoomFactor = CameraZoom.minFactor // the new device starts unzoomed
        }

        private static func makeInput(position: AVCaptureDevice.Position) -> AVCaptureDeviceInput? {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
                return nil
            }
            return try? AVCaptureDeviceInput(device: device)
        }

        public func stopSession() {
            let session = session
            Task.detached { session.stopRunning() }
        }

        public func toggleFlash() {
            isFlashOn.toggle()
        }

        public private(set) var zoomFactor: CGFloat = CameraZoom.minFactor

        public func setZoom(_ factor: CGFloat) {
            guard let device = currentInput?.device else { return }
            let clamped = CameraZoom.clamp(factor, deviceMax: device.maxAvailableVideoZoomFactor)
            configure(device) { $0.videoZoomFactor = clamped }
            zoomFactor = clamped
        }

        // ponytail: no `captureDevicePointConverted` — close enough under
        // resizeAspectFill; convert via the preview layer if precision bites.

        /// `point` is normalized preview space; AVFoundation wants the same
        /// 0...1 device space.
        public func focus(at point: CGPoint) {
            guard let device = currentInput?.device else { return }
            configure(device) { device in
                if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
                    device.focusPointOfInterest = point
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.autoExpose) {
                    device.exposurePointOfInterest = point
                    device.exposureMode = .autoExpose
                }
            }
        }

        private func configure(_ device: AVCaptureDevice, _ body: (AVCaptureDevice) -> Void) {
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                body(device)
            } catch {
                Log.report(error, logger: Log.ui) // non-fatal: framing stays as-is
            }
        }

        public func capturePhoto() async throws -> Data {
            guard inFlightDelegate == nil else { throw AppError.captureFailed }
            defer { inFlightDelegate = nil }

            let settings = AVCapturePhotoSettings()
            if currentInput?.device.hasFlash == true {
                settings.flashMode = isFlashOn ? .on : .off
            }

            return try await withCheckedThrowingContinuation { continuation in
                let delegate = PhotoCaptureDelegate { result in
                    continuation.resume(with: result)
                }
                inFlightDelegate = delegate
                output.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }

    private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
        private let completion: @Sendable (Result<Data, Error>) -> Void

        init(completion: @escaping @Sendable (Result<Data, Error>) -> Void) {
            self.completion = completion
        }

        func photoOutput(_: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
            if let error {
                completion(.failure(error))
                return
            }
            guard let data = photo.fileDataRepresentation() else {
                completion(.failure(AppError.captureFailed))
                return
            }
            completion(.success(data))
        }
    }
#endif
