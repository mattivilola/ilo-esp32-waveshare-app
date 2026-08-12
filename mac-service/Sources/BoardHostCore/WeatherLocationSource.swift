import BoardProtocol
import Foundation

public protocol WeatherLocationProviding: Sendable {
    func currentLocation() async -> WeatherLocation?
}

public actor WeatherLocationCache: WeatherLocationProviding {
    private var location: WeatherLocation?

    public init() {}

    public func update(_ location: WeatherLocation?) {
        self.location = location
    }

    public func currentLocation() -> WeatherLocation? {
        location
    }
}

public struct NoWeatherLocationSource: WeatherLocationProviding {
    public init() {}
    public func currentLocation() async -> WeatherLocation? { nil }
}
