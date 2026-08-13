import Foundation
import Testing

@testable import DecoyAdapterKit

/// Name composition against the patterns the JavaScript produced for all 63 locales.
///
/// A pattern decides the shape of every full name a locale generates, so getting one wrong
/// is not a subtle failure for that locale — it is every name. The comparison is against
/// the emitted intermediate JSON rather than a fixture, for the same reason as the n-gram
/// parity suite: what has to be reproduced is what shipped.
@Suite("Name patterns")
struct NamePatternTests {

    private static let reference = URL(fileURLWithPath: "/tmp/patterns-node.json")
    private static let locales = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Tools/adapters/out/locales")

    @Test("state distinguishes filled, deliberately empty, and absent")
    func threeWay() {
        let definitions: [String: Any] = [
            "person": [
                "first_name": ["Ana", "Bob"],
                "prefix": NSNull(),
                "suffix": [String](),
                "nested": ["generic": ["Dr."]],
            ] as [String: Any]
        ]
        #expect(NamePatterns.state(of: definitions, at: "person.first_name") == .filled)
        // The distinction the corpus format exists to carry: an explicit null blocks the
        // chain, an absent key lets it continue.
        #expect(NamePatterns.state(of: definitions, at: "person.prefix") == .empty)
        #expect(NamePatterns.state(of: definitions, at: "person.suffix") == .empty)
        #expect(NamePatterns.state(of: definitions, at: "person.missing") == .absent)
        #expect(NamePatterns.state(of: definitions, at: "person.nested") == .filled)
    }

    @Test("an explicit null stops the chain, an absent key does not")
    func blocking() {
        let blocking: [String: Any] = ["person": ["prefix": NSNull()] as [String: Any]]
        let silent: [String: Any] = ["person": ["first_name": ["A"]] as [String: Any]]
        let english: [String: Any] = ["person": ["prefix": ["Dr."]] as [String: Any]]

        #expect(NamePatterns.resolver(definitions: blocking, chain: [english])("person.prefix") == false)
        #expect(NamePatterns.resolver(definitions: silent, chain: [english])("person.prefix") == true)
    }

    @Test("surname order and separator follow CLDR")
    func composition() {
        let always: (String) -> Bool = { _ in false }
        #expect(
            NamePatterns.namePattern(resolves: always, surnameFirst: false, separator: " ")
                == [.init(value: "{{person.firstName}} {{person.lastName}}", weight: 90)])
        #expect(
            NamePatterns.namePattern(resolves: always, surnameFirst: true, separator: "")
                == [.init(value: "{{person.lastName}}{{person.firstName}}", weight: 90)])

        // No prefix or suffix variant where the script joins its parts: attaching a title
        // in such a language is a question CLDR's defaults do not answer.
        let has: (String) -> Bool = { _ in true }
        #expect(
            NamePatterns.namePattern(resolves: has, surnameFirst: true, separator: "").count == 1)
        #expect(
            NamePatterns.namePattern(resolves: has, surnameFirst: false, separator: " ").count == 3)
    }

    @Test(
        "Swift reproduces every locale's pattern",
        .enabled(if: PortFixtures.hasReference("/tmp/patterns-node.json")))
    func parity() throws {
        guard let data = try? Data(contentsOf: Self.reference),
            let expected = try? JSONSerialization.jsonObject(with: data) as? [String: [[String: Any]]]
        else {
            Issue.record("no /tmp/patterns-node.json — dump it before trusting this suite")
            return
        }

        var compared = 0
        for (code, variants) in expected.sorted(by: { $0.key < $1.key }) {
            let path = Self.locales.appendingPathComponent("\(code).json")
            guard let raw = try? Data(contentsOf: path),
                let definitions = try? JSONSerialization.jsonObject(with: raw) as? [String: Any]
            else { continue }

            // The chain is not reconstructed here; what is checked is that given the same
            // resolution answers, the composition matches. The resolver itself is covered
            // by `blocking` above.
            let resolves: (String) -> Bool = { path in
                variants.contains { ($0["value"] as? String)?.contains(path.replacingOccurrences(
                    of: "person.prefix", with: "{{person.prefix}}").replacingOccurrences(
                        of: "person.suffix", with: "{{person.suffix}}")) == true }
            }
            let plain = variants.first?["value"] as? String ?? ""
            let surnameFirst = plain.hasPrefix("{{person.lastName}}")
            let separator = plain
                .replacingOccurrences(of: "{{person.firstName}}", with: "")
                .replacingOccurrences(of: "{{person.lastName}}", with: "")

            let built = NamePatterns.namePattern(
                resolves: resolves, surnameFirst: surnameFirst, separator: separator)
            let mine = built.map { [$0.value, String($0.weight)] }
            let theirs = variants.map {
                [($0["value"] as? String) ?? "", String(($0["weight"] as? Int) ?? 0)]
            }
            #expect(mine == theirs, "\(code)")
            compared += 1
            _ = definitions
        }
        let complaint = "no locales compared — the intermediate JSON is missing"
        #expect(compared > 0, "\(complaint)")
        print("patterns: compared \(compared) locales")
    }
}
