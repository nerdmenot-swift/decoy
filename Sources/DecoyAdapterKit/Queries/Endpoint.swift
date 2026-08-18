import Foundation

// URLSession lives in a separate module off Apple platforms, the same as in ArtifactStore.
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// The two endpoints that answer a query rather than publish a file.
///
/// Every other source Decoy uses is a URL with an integrity hash, which is what makes a
/// silently changed upstream fail the build instead of quietly altering everyone's fixtures.
/// Wikidata answers SPARQL and the statistical offices answer PxWeb over POST: there is no
/// file to hash and no version to pin.
///
/// So the arrangement is the opposite one. The query is run deliberately, by hand, and its
/// result is committed beside the query that produced it. Anyone can re-run and diff, which
/// is a stronger guarantee than a hash over somebody else's server because it can be checked
/// by inspection rather than only by comparison.
public enum Endpoint {

    public static let agent = "DecoyCorpusBuild/1.0 (https://github.com/nerdmenot-swift/decoy)"
    public static let wikidata = "https://query.wikidata.org/sparql"

    /// `encodeURIComponent`, which is narrower than any `CharacterSet` Foundation ships.
    ///
    /// A SPARQL query is full of `?`, `#`, `{` and `&`, and `.urlQueryAllowed` passes `?`
    /// and `&` through unescaped — which truncates the query at the first one and returns a
    /// parse error from the endpoint rather than anything that looks like an encoding bug.
    static let componentAllowed: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.!~*'()")
        return allowed
    }()

    public static func encode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: componentAllowed) ?? text
    }

    /// Sleeps, for the polite pause between requests to shared infrastructure.
    public static func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// One SPARQL query's result bindings, or nil once the endpoint has given up.
    ///
    /// The body is parsed *inside* the retry rather than after it. A 200 with a truncated
    /// body is a real failure mode of this endpoint under load — it cut off mid-string on
    /// the eleventh language and took the whole run with it, because the parse sat outside
    /// the loop where nothing could retry it.
    public static func sparql(
        _ query: String, attempts: Int = 5, backoff: Double = 5,
        log: (String) -> Void = { _ in }
    ) async -> [[String: Any]]? {
        guard let url = URL(string: "\(wikidata)?query=\(encode(query))") else { return nil }

        for attempt in 0..<attempts {
            var request = URLRequest(url: url)
            request.setValue("application/sparql-results+json", forHTTPHeaderField: "Accept")
            request.setValue(agent, forHTTPHeaderField: "User-Agent")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if (200..<300).contains(status),
                    let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let results = body["results"] as? [String: Any],
                    let bindings = results["bindings"] as? [[String: Any]]
                {
                    return bindings
                }
                log("  HTTP \(status), retrying")
            } catch {
                // Truncated body, reset connection, or malformed JSON. All retryable.
                log("  \(error.localizedDescription), retrying")
            }
            // Shared infrastructure that answers 429 and 502 under load. Backing off is the
            // courtesy that keeps it usable, and this is run by hand anyway.
            await pause(backoff * Double(attempt + 1))
        }
        return nil
    }

    /// One PxWeb POST's decoded response, or nil once the endpoint has given up.
    ///
    /// Decoded through `OrderedJSON` rather than `JSONSerialization`, because json-stat2
    /// carries meaning in the order of an object's keys: a category's `label` lists its
    /// members in the order the table presents them.
    public static func pxweb(
        _ url: String, body: [String: Any], attempts: Int = 4, backoff: Double = 4,
        log: (String) -> Void = { _ in }
    ) async -> OrderedJSON? {
        guard let target = URL(string: url),
            let payload = try? JSONSerialization.data(withJSONObject: body)
        else { return nil }

        for attempt in 0..<attempts {
            var request = URLRequest(url: target)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(agent, forHTTPHeaderField: "User-Agent")
            request.httpBody = payload

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if (200..<300).contains(status), let decoded = try? OrderedJSON.parse(data) {
                    return decoded
                }
                log("  HTTP \(status), retrying")
            } catch {
                log("  \(error.localizedDescription), retrying")
            }
            await pause(backoff * Double(attempt + 1))
        }
        return nil
    }

    /// One GET, decoded as JSON, or a message saying what went wrong.
    ///
    /// Here rather than in the fetcher because `URLSession` lives in a separate module off
    /// Apple platforms, and a caller that forgets the conditional import compiles on macOS
    /// and fails on Linux and Windows — which it did, twice. Nothing outside this file
    /// needs to know that.
    public enum RequestFailure: Error, CustomStringConvertible {
        case status(Int)
        case transport(String)

        public var description: String {
            switch self {
            case .status(let code): return "HTTP \(code)"
            case .transport(let detail): return detail
            }
        }
    }

    public static func json(from url: URL) async throws -> Any {
        var request = URLRequest(url: url)
        request.setValue(agent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else { throw RequestFailure.status(status) }
            return try JSONSerialization.jsonObject(with: data)
        } catch let failure as RequestFailure {
            throw failure
        } catch {
            throw RequestFailure.transport(error.localizedDescription)
        }
    }

    // MARK: - Shared shaping

    /// The value of a SPARQL binding, by variable name.
    public static func value(_ binding: [String: Any], _ variable: String) -> String? {
        (binding[variable] as? [String: Any])?["value"] as? String
    }

    /// The language tag a SPARQL label came back in.
    public static func language(_ binding: [String: Any], _ variable: String) -> String? {
        (binding[variable] as? [String: Any])?["xml:lang"] as? String
    }

    /// The QID at the end of a Wikidata entity URI.
    public static func qid(_ uri: String) -> String {
        String(uri.split(separator: "/").last ?? "")
    }

    /// Whether a label is a word somebody would actually say.
    ///
    /// Wikidata labels carry disambiguators, trade names and transliterations — `Müller
    /// (Familienname)`, `Kassler Erde`, `John Smith`. Anything with a bracket, a digit or a
    /// space goes, which loses a few genuine compound surnames and keeps the list clean.
    /// The bound is on UTF-16 code units, not on characters: `String.prototype.length`
    /// counts code units, so a decomposed accent or an astral character costs two there and
    /// one in Swift. Counting differently would keep or drop labels the snapshot does not.
    public static func usable(_ label: String) -> Bool {
        let length = label.utf16.count
        guard length >= 2, length <= 24 else { return false }
        for scalar in label.unicodeScalars {
            // `\s` plus the byte order mark, which JavaScript's `\s` includes.
            if scalar == "\u{FEFF}" || Character(scalar).isWhitespace { return false }
            if ("0"..."9").contains(scalar) { return false }
            if "()[]{}.,;:!?/\\".unicodeScalars.contains(scalar) { return false }
        }
        return true
    }

    /// Deduplicated on code units and sorted the way `[...new Set(x)].sort()` sorts.
    public static func distinctSorted(_ labels: [String]) -> [String] {
        var seen = Set<[UInt16]>()
        var kept: [String] = []
        for label in labels where seen.insert(CodeUnitOrder.key(label)).inserted {
            kept.append(label)
        }
        return CodeUnitOrder.sorted(kept)
    }

    /// Today, as the snapshots record it.
    public static var today: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }
}
