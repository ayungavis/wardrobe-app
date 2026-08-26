import CoreLocation
import Foundation

public enum LocationPermission: Sendable {
    case notDetermined
    case denied
    case authorized
}

@MainActor
public protocol LocationService: AnyObject, Sendable {
    var permission: LocationPermission { get }
    func requestPermission() async -> LocationPermission
    func currentLocation() async throws -> CLLocation
}

@MainActor
public final class CoreLocationService: NSObject, LocationService, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var permissionWaiters: [CheckedContinuation<LocationPermission, Never>] = []
    private var locationWaiters: [CheckedContinuation<CLLocation, Error>] = []

    override public init() {
        super.init()
        // ponytail: city granularity is all a forecast needs, and it is the
        // smallest request that answers it. Raise it only if a feature needs
        // a street.
        manager.desiredAccuracy = kCLLocationAccuracyReduced
        manager.delegate = self
    }

    public var permission: LocationPermission {
        switch manager.authorizationStatus {
        case .notDetermined: .notDetermined
        case .authorizedWhenInUse, .authorizedAlways: .authorized
        default: .denied
        }
    }

    public func requestPermission() async -> LocationPermission {
        guard manager.authorizationStatus == .notDetermined else { return permission }
        return await withCheckedContinuation { continuation in
            permissionWaiters.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
    }

    public func currentLocation() async throws -> CLLocation {
        guard permission == .authorized else { throw AppError.unavailable }
        return try await withCheckedThrowingContinuation { continuation in
            locationWaiters.append(continuation)
            manager.requestLocation()
        }
    }

    public nonisolated func locationManagerDidChangeAuthorization(_: CLLocationManager) {
        MainActor.assumeIsolated {
            let resolved = permission
            guard resolved != .notDetermined else { return }
            permissionWaiters.forEach { $0.resume(returning: resolved) }
            permissionWaiters.removeAll()
        }
    }

    public nonisolated func locationManager(
        _: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        MainActor.assumeIsolated {
            guard let location = locations.last else { return }
            locationWaiters.forEach { $0.resume(returning: location) }
            locationWaiters.removeAll()
        }
    }

    public nonisolated func locationManager(
        _: CLLocationManager,
        didFailWithError error: any Error
    ) {
        MainActor.assumeIsolated {
            locationWaiters.forEach { $0.resume(throwing: error) }
            locationWaiters.removeAll()
        }
    }
}

public final class DeniedLocationService: LocationService {
    public init() {}

    public var permission: LocationPermission {
        .denied
    }

    public func requestPermission() async -> LocationPermission {
        .denied
    }

    public func currentLocation() async throws -> CLLocation {
        throw AppError.unavailable
    }
}
