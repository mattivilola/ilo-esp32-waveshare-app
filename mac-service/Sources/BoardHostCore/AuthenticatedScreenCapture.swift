import BoardProtocol
import Foundation

public enum AuthenticatedScreenCapture {
    public static func capture(
        configuration: HostConfiguration,
        secret: Data,
        timeoutSeconds: Int
    ) async throws -> CapturedScreen {
        let (events, continuation) = AsyncStream.makeStream(
            of: Result<CapturedScreen, ScreenCaptureError>.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        let server = BoardServer(
            boardID: configuration.boardID,
            secret: secret,
            source: MockTaskSource(),
            screenCaptureHandler: { result in
                continuation.yield(result)
                continuation.finish()
            },
            eventHandler: { event in
                if case let .listenerFailed(message) = event {
                    continuation.yield(.failure(.hostUnavailable(message)))
                    continuation.finish()
                }
            }
        )
        try server.start(port: configuration.port)
        defer { server.stop() }

        return try await withThrowingTaskGroup(of: CapturedScreen.self) { group in
            group.addTask {
                var iterator = events.makeAsyncIterator()
                guard let result = await iterator.next() else {
                    throw ScreenCaptureError.connectionClosed
                }
                return try result.get()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeoutSeconds))
                throw ScreenCaptureError.timedOut
            }
            guard let capture = try await group.next() else {
                throw ScreenCaptureError.connectionClosed
            }
            group.cancelAll()
            return capture
        }
    }
}
