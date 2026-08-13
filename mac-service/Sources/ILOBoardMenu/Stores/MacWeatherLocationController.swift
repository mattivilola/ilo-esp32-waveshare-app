import AppKit
import BoardHostCore
import BoardProtocol
import CoreLocation
import Foundation

@MainActor
private func openMacLocationSettings() {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") else {
        return
    }
    NSWorkspace.shared.open(url)
}

enum MacWeatherLocationState: Equatable {
    case off
    case permissionRequired
    case requesting
    case ready
    case denied
    case unavailable

    var title: String {
        switch self {
        case .off: "Off"
        case .permissionRequired: "Permission needed"
        case .requesting: "Locating…"
        case .ready: "Shared coarsely"
        case .denied: "Permission denied"
        case .unavailable: "Unavailable"
        }
    }
}

protocol WeatherLocationManaging: AnyObject {
    var delegate: (any CLLocationManagerDelegate)? { get set }
    var desiredAccuracy: CLLocationAccuracy { get set }
    var distanceFilter: CLLocationDistance { get set }
    var authorizationStatus: CLAuthorizationStatus { get }

    func requestWhenInUseAuthorization()
    func requestLocation()
    func stopUpdatingLocation()
}

extension CLLocationManager: WeatherLocationManaging {}

@MainActor
final class MacWeatherLocationController: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var state: MacWeatherLocationState = .off
    @Published private(set) var detail = "The board has no Mac-provided weather location."

    let cache = WeatherLocationCache()
    private let manager: any WeatherLocationManaging
    private let geocoder = CLGeocoder()
    private let defaults: UserDefaults
    private let requestTimeoutNanoseconds: UInt64
    private let openLocationSettingsAction: @MainActor () -> Void
    private var requestTimeoutTask: Task<Void, Never>?
    // City lookup adds a macOS reverse-geocoding step, so it requires fresh
    // consent instead of silently reusing the earlier coordinate-only choice.
    static let enabledKey = "ilo-board.weather-location-sharing.v2"

    init(
        defaults: UserDefaults = .standard,
        autoRefresh: Bool = true,
        manager: any WeatherLocationManaging = CLLocationManager(),
        requestTimeoutNanoseconds: UInt64 = 20_000_000_000,
        openLocationSettings: @escaping @MainActor () -> Void = openMacLocationSettings
    ) {
        self.defaults = defaults
        self.manager = manager
        self.requestTimeoutNanoseconds = requestTimeoutNanoseconds
        openLocationSettingsAction = openLocationSettings
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.distanceFilter = 5_000
        if autoRefresh && defaults.bool(forKey: Self.enabledKey) {
            refreshAfterAuthorizationChange()
        }
    }

    func refresh() {
        refreshAfterAuthorizationChange()
    }

    func enable() {
        defaults.set(true, forKey: Self.enabledKey)
        switch manager.authorizationStatus {
        case .notDetermined:
            cancelLocationRequestTimeout()
            state = .permissionRequired
            detail = "Approve ILO Board in the macOS location permission prompt."
            manager.requestWhenInUseAuthorization()
        case .authorized, .authorizedAlways:
            beginLocationRequest()
        case .denied, .restricted:
            showPermissionDenied()
        @unknown default:
            showUnavailable("macOS location status is unavailable.")
        }
    }

    func disable() {
        defaults.set(false, forKey: Self.enabledKey)
        cancelLocationRequestTimeout()
        manager.stopUpdatingLocation()
        geocoder.cancelGeocode()
        state = .off
        detail = "The board has no Mac-provided weather location."
        Task { await cache.update(nil) }
    }

    func openLocationSettings() {
        openLocationSettingsAction()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refreshAfterAuthorizationChange()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard defaults.bool(forKey: Self.enabledKey), let location = locations.last else { return }
        cancelLocationRequestTimeout()
        let latitude = (location.coordinate.latitude * 100).rounded() / 100
        let longitude = (location.coordinate.longitude * 100).rounded() / 100
        let coarseLocation = CLLocation(latitude: latitude, longitude: longitude)
        state = .requesting
        detail = "Identifying the city from the approved coarse location."
        Task {
            let placemarks = try? await geocoder.reverseGeocodeLocation(coarseLocation)
            guard defaults.bool(forKey: Self.enabledKey) else { return }
            let placemark = placemarks?.first
            let city = placemark?.locality
                ?? placemark?.subAdministrativeArea
                ?? placemark?.administrativeArea
                ?? "Current location"
            let weatherLocation = WeatherLocation(name: city, latitude: latitude, longitude: longitude)
            state = .ready
            detail = "\(weatherLocation.name) / about 1 km precision; sent only to the paired board."
            await cache.update(weatherLocation)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard defaults.bool(forKey: Self.enabledKey) else { return }
        cancelLocationRequestTimeout()
        if let locationError = error as? CLError, locationError.code == .denied {
            showPermissionDenied()
        } else {
            showUnavailable("A current Mac location could not be obtained. Check Location Services and Wi-Fi, then try again.")
        }
    }

    private func refreshAfterAuthorizationChange() {
        guard defaults.bool(forKey: Self.enabledKey) else {
            state = .off
            return
        }
        switch manager.authorizationStatus {
        case .authorized, .authorizedAlways:
            if state != .ready && state != .requesting {
                beginLocationRequest()
            }
        case .notDetermined:
            cancelLocationRequestTimeout()
            state = .permissionRequired
            detail = "Location permission has not been granted yet."
        case .denied, .restricted:
            showPermissionDenied()
        @unknown default:
            showUnavailable("macOS location status is unavailable.")
        }
    }

    private func beginLocationRequest() {
        cancelLocationRequestTimeout()
        state = .requesting
        detail = "Getting a coarse location from macOS."
        manager.requestLocation()
        requestTimeoutTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: requestTimeoutNanoseconds)
            guard !Task.isCancelled else { return }
            locationRequestTimedOut()
        }
    }

    private func locationRequestTimedOut() {
        requestTimeoutTask = nil
        guard defaults.bool(forKey: Self.enabledKey), state == .requesting else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            state = .permissionRequired
            detail = "Location permission has not been granted yet."
        case .denied, .restricted:
            showPermissionDenied()
        case .authorized, .authorizedAlways:
            showUnavailable("macOS did not return a location. Check Location Services and Wi-Fi, then try again.")
        @unknown default:
            showUnavailable("macOS location status is unavailable.")
        }
    }

    private func showPermissionDenied() {
        cancelLocationRequestTimeout()
        state = .denied
        detail = "Location access is off for ILO Board. Open Location Settings to allow it."
        Task { await cache.update(nil) }
    }

    private func showUnavailable(_ message: String) {
        cancelLocationRequestTimeout()
        state = .unavailable
        detail = message
        Task { await cache.update(nil) }
    }

    private func cancelLocationRequestTimeout() {
        requestTimeoutTask?.cancel()
        requestTimeoutTask = nil
    }

}
