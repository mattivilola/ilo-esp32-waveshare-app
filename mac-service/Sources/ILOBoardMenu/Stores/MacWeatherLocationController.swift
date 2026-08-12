import BoardHostCore
import BoardProtocol
import CoreLocation
import Foundation

enum MacWeatherLocationState: Equatable {
    case off
    case requesting
    case ready
    case denied
    case unavailable

    var title: String {
        switch self {
        case .off: "Off"
        case .requesting: "Locating…"
        case .ready: "Shared coarsely"
        case .denied: "Permission denied"
        case .unavailable: "Unavailable"
        }
    }
}

@MainActor
final class MacWeatherLocationController: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var state: MacWeatherLocationState = .off
    @Published private(set) var detail = "The board has no Mac-provided weather location."

    let cache = WeatherLocationCache()
    private let manager = CLLocationManager()
    private let defaults: UserDefaults
    private static let enabledKey = "ilo-board.weather-location-sharing.v1"

    init(defaults: UserDefaults = .standard, autoRefresh: Bool = true) {
        self.defaults = defaults
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.distanceFilter = 5_000
        if autoRefresh && defaults.bool(forKey: Self.enabledKey) {
            refreshAfterAuthorizationChange()
        }
    }

    func enable() {
        defaults.set(true, forKey: Self.enabledKey)
        state = .requesting
        detail = "Waiting for macOS location permission."
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorized, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            state = .denied
            detail = "Allow location for ILO Board in System Settings, then try again."
        @unknown default:
            state = .unavailable
            detail = "macOS location status is unavailable."
        }
    }

    func disable() {
        defaults.set(false, forKey: Self.enabledKey)
        manager.stopUpdatingLocation()
        state = .off
        detail = "The board has no Mac-provided weather location."
        Task { await cache.update(nil) }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refreshAfterAuthorizationChange()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard defaults.bool(forKey: Self.enabledKey), let location = locations.last else { return }
        let weatherLocation = WeatherLocation(
            name: "Mac location",
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        state = .ready
        detail = "About 1 km precision; sent only to the paired board."
        Task { await cache.update(weatherLocation) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard defaults.bool(forKey: Self.enabledKey) else { return }
        if let locationError = error as? CLError, locationError.code == .denied {
            state = .denied
            detail = "Allow location for ILO Board in System Settings, then try again."
        } else {
            state = .unavailable
            detail = "A current Mac location could not be obtained."
        }
        Task { await cache.update(nil) }
    }

    private func refreshAfterAuthorizationChange() {
        guard defaults.bool(forKey: Self.enabledKey) else {
            state = .off
            return
        }
        switch manager.authorizationStatus {
        case .authorized, .authorizedAlways:
            state = .requesting
            detail = "Getting a coarse location from macOS."
            manager.requestLocation()
        case .notDetermined:
            state = .requesting
            detail = "Choose Enable to approve Mac location sharing."
        case .denied, .restricted:
            state = .denied
            detail = "Allow location for ILO Board in System Settings, then try again."
        @unknown default:
            state = .unavailable
            detail = "macOS location status is unavailable."
        }
    }
}
