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
        private var subjectAreaObserver: (any NSObjectProtocol)?
        /// Device zoom that equals a displayed "1x". On virtual multi-camera
        /// devices `videoZoomFactor == 1` is the ultra-wide lens, so the
        /// standard lens sits at the first switch-over factor.
        private var baseZoomFactor: CGFloat = 1
        public private(set) var isFlashOn = false

        public var isUsingFrontCamera: Bool {
            position == .front
        }

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
                adoptInput(input)
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
            position = newPosition
            adoptInput(newInput)
        }

        /// Prefers the virtual multi-camera devices, because they are what
        /// expose the ultra-wide lens behind a single continuous zoom scale.
        private static func makeInput(position: AVCaptureDevice.Position) -> AVCaptureDeviceInput? {
            let types: [AVCaptureDevice.DeviceType] = position == .back
                ? [.builtInTripleCamera, .builtInDualWideCamera, .builtInWideAngleCamera]
                : [.builtInWideAngleCamera]
            guard let device = types.lazy
                .compactMap({ AVCaptureDevice.default($0, for: .video, position: position) })
                .first
            else {
                return nil
            }
            return try? AVCaptureDeviceInput(device: device)
        }

        /// Adopts a freshly added input: reset zoom mapping, put the device in
        /// the continuous-autofocus mode iPhone's own Camera uses, and watch
        /// for subject changes so a tap-to-focus never stays locked forever.
        private func adoptInput(_ input: AVCaptureDeviceInput) {
            currentInput = input
            let device = input.device
            baseZoomFactor = device.virtualDeviceSwitchOverVideoZoomFactors.first.map { CGFloat($0.doubleValue) } ?? 1

            configure(device) { device in
                device.videoZoomFactor = baseZoomFactor
                device.isSubjectAreaChangeMonitoringEnabled = true
                if device.isSmoothAutoFocusSupported {
                    device.isSmoothAutoFocusEnabled = true
                }
                applyContinuousModes(to: device)
            }
            observeSubjectAreaChanges(of: device)
        }

        private func applyContinuousModes(to device: AVCaptureDevice) {
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
        }

        private func observeSubjectAreaChanges(of device: AVCaptureDevice) {
            removeSubjectAreaObserver()
            // `queue: .main` means the block already runs on the main actor —
            // no non-Sendable `Notification` crosses an isolation boundary.
            subjectAreaObserver = NotificationCenter.default.addObserver(
                forName: AVCaptureDevice.subjectAreaDidChangeNotification,
                object: device,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.resetFocusToContinuous()
                }
            }
        }

        private func removeSubjectAreaObserver() {
            guard let subjectAreaObserver else { return }
            NotificationCenter.default.removeObserver(subjectAreaObserver)
            self.subjectAreaObserver = nil
        }

        /// Back to "the camera decides", centred — what Camera.app does once
        /// the framing changes after a manual tap.
        private func resetFocusToContinuous() {
            guard let device = currentInput?.device else { return }
            configure(device) { device in
                let center = CGPoint(x: 0.5, y: 0.5)
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = center
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = center
                }
                applyContinuousModes(to: device)
            }
        }

        public func stopSession() {
            removeSubjectAreaObserver()
            let session = session
            Task.detached { session.stopRunning() }
        }

        public func toggleFlash() {
            isFlashOn.toggle()
        }

        public var displayZoomFactor: CGFloat {
            guard let device = currentInput?.device else { return CameraZoom.standard }
            return device.videoZoomFactor / baseZoomFactor
        }

        /// Only the presets this device can actually reach — 0.5x needs an
        /// ultra-wide lens, so it disappears on a plain wide-angle camera.
        public var zoomOptions: [CGFloat] {
            guard let device = currentInput?.device else { return [CameraZoom.standard] }
            let lowest = device.minAvailableVideoZoomFactor / baseZoomFactor
            let highest = device.maxAvailableVideoZoomFactor / baseZoomFactor
            let supported = CameraZoom.presets.filter { $0 >= lowest && $0 <= highest }
            return supported.isEmpty ? [CameraZoom.standard] : supported
        }

        public func setDisplayZoom(_ factor: CGFloat) {
            guard let device = currentInput?.device else { return }
            let deviceFactor = min(
                device.maxAvailableVideoZoomFactor,
                max(device.minAvailableVideoZoomFactor, factor * baseZoomFactor)
            )
            configure(device) { $0.videoZoomFactor = deviceFactor }
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
                // Subject-area monitoring hands focus back to the camera once
                // the framing changes — see `observeSubjectAreaChanges`.
                device.isSubjectAreaChangeMonitoringEnabled = true
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
