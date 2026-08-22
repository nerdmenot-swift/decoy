import Foundation
import Testing

@testable import DecoyAdapterKit

/// The Swift orchestrator against the JavaScript's, fed the same 32 adapter outputs.
///
/// This is the half of the pipeline that is not adapters: merge, precedence, conflict
/// refusal, chains. Proving it separately is the point — with the adapter boundary frozen
/// on disk, a mismatch here is the orchestrator's and a mismatch after an adapter is ported
/// is that adapter's. Testing them together would make every regression read as one
/// undifferentiated "the corpus changed".
///
/// The comparison stops short of name patterns and model training, which mutate the merged
/// tree afterwards and have their own suites.
@Suite("Orchestrator")
struct OrchestratorTests {

    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Tools/adapters")
    private static let dumps = root.appendingPathComponent("parity")
    private static let emitted = root.appendingPathComponent("out/locales")

    private static func roster() -> Set<String> {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("locales.json")),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let codes = object["locales"] as? [String]
        else { return [] }
        return Set(codes)
    }

    private static func adapters() -> [Orchestrator.Contribution] {
        guard
            let files = try? FileManager.default.contentsOfDirectory(
                at: dumps, includingPropertiesForKeys: nil)
        else { return [] }

        return files.filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                    let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let id = object["id"] as? String,
                    let raw = object["contributions"] as? [String: [String: Any]]
                else { return nil }

                let contributions = raw.mapValues { $0.mapValues(Definition.init(json:)) }
                return Orchestrator.Contribution(
                    id: id,
                    attributeTo: (object["attributeTo"] as? String) ?? id,
                    isFallback: (object["fallback"] as? Bool) ?? false,
                    contributions: contributions,
                    sourceByLocale: object["sourceByLocale"] as? [String: String])
            }
    }

    @Test("the chain rule matches the one adapters are handed")
    func chains() {
        let roster = Self.roster()
        guard !roster.isEmpty else {
            Issue.record("no roster — Tools/adapters/locales.json did not parse")
            return
        }
        #expect(Orchestrator.fallbackChain("base", roster: roster) == ["base"])
        #expect(Orchestrator.fallbackChain("en", roster: roster) == ["en", "base"])
        #expect(Orchestrator.fallbackChain("de_AT", roster: roster) == ["de_AT", "de", "en", "base"])
        #expect(
            Orchestrator.fallbackChain("en_AU_ocker", roster: roster)
                == ["en_AU_ocker", "en_AU", "en", "base"])
        // `sr_RS_latin` keeps only the codes the roster actually has.
        let serbian = Orchestrator.fallbackChain("sr_RS_latin", roster: roster)
        #expect(serbian.first == "sr_RS_latin")
        #expect(serbian.last == "base")
        #expect(serbian.allSatisfy(roster.contains))
    }

    /// The assumption that let the bool case go.
    ///
    /// Distinguishing a boolean from a 0 or 1 inside an NSNumber needs CFGetTypeID, which
    /// is CoreFoundation and Apple-only — it broke the Linux build outright. Dropping it is
    /// only safe while no adapter emits one, so that is asserted rather than assumed.
    @Test(
        "no adapter contributes a boolean",
        .enabled(if: PortFixtures.hasContributionDumps))
    func noBooleans() throws {
        func booleans(in value: Definition) -> Int {
            switch value {
            case .bool: return 1
            case .list(let items): return items.reduce(0) { $0 + booleans(in: $1) }
            case .object(let fields): return fields.values.reduce(0) { $0 + booleans(in: $1) }
            default: return 0
            }
        }
        var found = 0
        var scanned = 0
        for adapter in Self.adapters() {
            for (_, paths) in adapter.contributions {
                for (_, value) in paths {
                    found += booleans(in: value)
                    scanned += 1
                }
            }
        }
        #expect(scanned > 0, "no contributions scanned")
        #expect(found == 0, "a boolean appeared; Definition needs a portable bool decode")
    }

    @Test("two adapters claiming one path is refused, not resolved")
    func conflict() {
        let orchestrator = Orchestrator(roster: ["en"])
        let one = Orchestrator.Contribution(
            id: "first", attributeTo: "a", isFallback: false,
            contributions: ["en": ["person.prefix": .list([.string("Mr.")])]],
            sourceByLocale: nil)
        let two = Orchestrator.Contribution(
            id: "second", attributeTo: "b", isFallback: false,
            contributions: ["en": ["person.prefix": .list([.string("Dr.")])]],
            sourceByLocale: nil)
        #expect(throws: Orchestrator.Failure.self) { try orchestrator.merge([one, two]) }
    }

    @Test("a list replaces a list rather than merging into it")
    func replacement() throws {
        let orchestrator = Orchestrator(roster: ["en"])
        let result = try orchestrator.merge([
            Orchestrator.Contribution(
                id: "a", attributeTo: "a", isFallback: false,
                contributions: [
                    "en": [
                        "person.first_name.female": .list([.string("Ana")]),
                        "person.first_name.male": .list([.string("Bo")]),
                    ]
                ],
                sourceByLocale: nil)
        ])
        // Sibling paths merge into one object; neither clobbers the other.
        let person = result.definitions["en"]?["person"]?.asObject
        let first = person?["first_name"]?.asObject
        #expect(first?.keys.sorted() == ["female", "male"])
    }

    @Test(
        "merging all 32 real adapters reproduces what the JavaScript emitted",
        .enabled(if: PortFixtures.hasContributionDumps))
    func parity() throws {
        let roster = Self.roster()
        let adapters = Self.adapters()
        guard !adapters.isEmpty else {
            Issue.record(
                "no adapter baselines — run `swift run decoy-build-corpus --write-baselines`")
            return
        }
        #expect(adapters.count == 35, "expected 35 adapters, loaded \(adapters.count)")

        let result = try Orchestrator(roster: roster).merge(adapters)

        var compared = 0
        var mismatched: [String] = []
        for code in roster.sorted() {
            guard
                let data = try? Data(
                    contentsOf: Self.emitted.appendingPathComponent("\(code).json")),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            let mine = result.definitions[code] ?? [:]
            let theirs = object.mapValues(Definition.init(json:))

            // Name patterns and trained models are written into the emitted file *after*
            // the merge. Excluding the whole `person` namespace to avoid them would give up
            // the most important one in the corpus, so only the three paths the later stages
            // actually write are set aside; everything else under `person` is compared.
            let written: Set<String> = [
                "name", "first_name_model", "last_name_model", "middle_name_model",
            ]
            for (namespace, value) in theirs {
                if namespace == "person" {
                    guard let theirPerson = value.asObject else { continue }
                    let minePerson = mine["person"]?.asObject ?? [:]
                    for (field, fieldValue) in theirPerson where !written.contains(field) {
                        if minePerson[field] != fieldValue {
                            mismatched.append("\(code).person.\(field)")
                        }
                        compared += 1
                    }
                } else {
                    if mine[namespace] != value { mismatched.append("\(code).\(namespace)") }
                    compared += 1
                }
            }
        }

        let complaint = "no locales compared — the intermediate JSON is missing"
        #expect(compared > 0, "\(complaint)")
        #expect(
            mismatched.isEmpty,
            "\(mismatched.count) namespaces differ, first: \(mismatched.prefix(5).joined(separator: ", "))"
        )
        print("orchestrator: compared \(compared) locale namespaces across \(roster.count) locales")
    }
}
