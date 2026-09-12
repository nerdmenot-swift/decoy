import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// One HTTP round trip, on the platforms that can make one.
///
/// Every request the pipeline sends goes through here, for two reasons that used to be
/// spread across four call sites. `URLSession` lives in a separate module off Apple
/// platforms, and a caller that forgot the conditional import compiled on macOS and failed
/// on Linux and Windows — which happened twice. And on Wasm there is no such module at
/// all: the pipeline is host-only, but SwiftPM compiles every target for every platform it
/// is asked about, and the Swift Package Index asks about Wasm and Android. One guarded
/// function keeps the whole package building there without teaching each call site the
/// platform list.
///
/// `DECOY_PIPELINE_HOST` is defined in `Package.swift` for exactly the platforms the
/// corpus is built on. Everywhere else the request throws before it is made.
enum HTTP {

    struct Response {
        let status: Int
        let body: Data
    }

    enum Failure: Error, CustomStringConvertible {
        /// The platform cannot open a connection at all.
        case unavailable

        var description: String {
            "this platform cannot make HTTP requests, so the corpus cannot be built on it"
        }
    }

    static func send(
        _ url: URL,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Data? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> Response {
        #if DECOY_PIPELINE_HOST
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.httpBody = body
            for (field, value) in headers {
                request.setValue(value, forHTTPHeaderField: field)
            }
            if let timeout { request.timeoutInterval = timeout }
            let (data, response) = try await URLSession.shared.data(for: request)
            return Response(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: data)
        #else
            throw Failure.unavailable
        #endif
    }
}
