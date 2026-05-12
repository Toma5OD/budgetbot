import Foundation

/// Registered by tests via `URLSessionConfiguration.protocolClasses = [StubURLProtocol.self]`.
/// Lets us simulate Anthropic responses without touching the network — sequential
/// scripted responses, captures of outgoing requests, all in-process.
final class StubURLProtocol: URLProtocol {

    /// A scripted response. `data` is the body; `status` is the HTTP status.
    struct Stub {
        var status: Int
        var data: Data
        var headers: [String: String] = ["Content-Type": "application/json"]
    }

    /// Queue of upcoming responses. Each request pops the front element. If
    /// empty, returns the `defaultStub`.
    nonisolated(unsafe) static var queue: [Stub] = []
    nonisolated(unsafe) static var defaultStub = Stub(status: 200, data: Data("{}".utf8))
    /// Optional capture for assertions.
    nonisolated(unsafe) static var capturedRequests: [URLRequest] = []

    static func reset() {
        queue = []
        capturedRequests = []
        defaultStub = Stub(status: 200, data: Data("{}".utf8))
    }

    static func enqueue(_ stub: Stub) {
        queue.append(stub)
    }

    static func enqueueJSON(_ string: String, status: Int = 200) {
        queue.append(Stub(status: status, data: Data(string.utf8)))
    }

    // MARK: - URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.capturedRequests.append(request)
        let stub = Self.queue.isEmpty ? Self.defaultStub : Self.queue.removeFirst()
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: stub.status,
                httpVersion: "HTTP/1.1",
                headerFields: stub.headers
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Convenience for building a `URLSessionConfiguration` wired up to the stub.
extension URLSessionConfiguration {
    static func stubbed() -> URLSessionConfiguration {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        cfg.urlCache = nil
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return cfg
    }
}
