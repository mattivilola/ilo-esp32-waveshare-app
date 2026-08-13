import CoreLocation
import Foundation
import Testing
@testable import ILOBoardMenu

@MainActor
@Test func weatherLocationRefreshSurfacesRevokedPermission() {
    let (defaults, suiteName) = testDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(true, forKey: MacWeatherLocationController.enabledKey)
    let manager = TestWeatherLocationManager(authorizationStatus: .authorizedAlways)
    let controller = MacWeatherLocationController(defaults: defaults, manager: manager)

    #expect(controller.state == .requesting)
    #expect(manager.requestLocationCount == 1)

    manager.authorizationStatus = .denied
    controller.refresh()

    #expect(controller.state == .denied)
    #expect(controller.detail == "Location access is off for ILO Board. Open Location Settings to allow it.")
}

@MainActor
@Test func weatherLocationUndeterminedPermissionIsNotShownAsLocating() {
    let (defaults, suiteName) = testDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(true, forKey: MacWeatherLocationController.enabledKey)
    let manager = TestWeatherLocationManager(authorizationStatus: .notDetermined)
    let controller = MacWeatherLocationController(defaults: defaults, manager: manager)

    #expect(controller.state == .permissionRequired)
    #expect(controller.state.title == "Permission needed")
    #expect(manager.requestLocationCount == 0)

    controller.enable()

    #expect(manager.requestAuthorizationCount == 1)
    #expect(controller.state == .permissionRequired)
}

@MainActor
@Test func weatherLocationDeniedStateOpensLocationSettings() {
    let (defaults, suiteName) = testDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(true, forKey: MacWeatherLocationController.enabledKey)
    let manager = TestWeatherLocationManager(authorizationStatus: .denied)
    var openCount = 0
    let controller = MacWeatherLocationController(
        defaults: defaults,
        manager: manager,
        openLocationSettings: { openCount += 1 }
    )

    controller.openLocationSettings()

    #expect(openCount == 1)
}

@MainActor
@Test func weatherLocationRequestTimesOutInsteadOfLocatingForever() async {
    let (defaults, suiteName) = testDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(true, forKey: MacWeatherLocationController.enabledKey)
    let manager = TestWeatherLocationManager(authorizationStatus: .authorizedAlways)
    let controller = MacWeatherLocationController(
        defaults: defaults,
        manager: manager,
        requestTimeoutNanoseconds: 10_000_000
    )

    try? await Task.sleep(nanoseconds: 40_000_000)

    #expect(controller.state == .unavailable)
    #expect(controller.detail == "macOS did not return a location. Check Location Services and Wi-Fi, then try again.")
}

private func testDefaults() -> (UserDefaults, String) {
    let suiteName = "MacWeatherLocationControllerTests.\(UUID().uuidString)"
    return (UserDefaults(suiteName: suiteName)!, suiteName)
}

private final class TestWeatherLocationManager: WeatherLocationManaging {
    weak var delegate: (any CLLocationManagerDelegate)?
    var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    var distanceFilter: CLLocationDistance = kCLDistanceFilterNone
    var authorizationStatus: CLAuthorizationStatus
    var requestAuthorizationCount = 0
    var requestLocationCount = 0

    init(authorizationStatus: CLAuthorizationStatus) {
        self.authorizationStatus = authorizationStatus
    }

    func requestWhenInUseAuthorization() {
        requestAuthorizationCount += 1
    }

    func requestLocation() {
        requestLocationCount += 1
    }

    func stopUpdatingLocation() {}
}
