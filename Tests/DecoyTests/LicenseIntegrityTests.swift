import Foundation
import Testing

/// Checks the licence metadata against the licence texts sitting next to it.
///
/// Every one of these caught something real. Five descriptors named a licence their own
/// upstream text contradicts: `omw-da` and `omw-nb` claimed `WordNet-3.0` while shipping
/// bespoke Danish and Norwegian licences, and three more claimed a bare `CC-BY-3.0` over
/// text that carves out Princeton's terms as well. Nothing detected it because nothing
/// had ever compared the two — the descriptors were written from the project's README
/// rather than from the file in the tarball.
///
/// These are cheap, mechanical and run on every build, which is the only way licence
/// metadata stays true: it is correct exactly once, on the day someone checks it, unless
/// a test keeps checking.
@Suite("Licence integrity")
struct LicenseIntegrityTests {

    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // DecoyTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repository root

    private struct Descriptor {
        let id: String
        let license: String
        let copyright: String
        let url: String
    }

    private static let descriptors: [Descriptor] = {
        let directory = root.appendingPathComponent("Tools/adapters/sources")
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []

        return files.compactMap { file in
            guard let data = try? Data(contentsOf: file),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let id = object["id"] as? String,
                let license = object["license"] as? String
            else { return nil }
            return Descriptor(
                id: id,
                license: license,
                copyright: object["copyright"] as? String ?? "",
                url: object["url"] as? String ?? ""
            )
        }
    }()

    @Test("every source descriptor names a licence")
    func licenceDeclared() throws {
        try #require(!Self.descriptors.isEmpty, "no source descriptors found")
        for descriptor in Self.descriptors {
            #expect(!descriptor.license.isEmpty, "\(descriptor.id) declares no licence")
            #expect(!descriptor.url.isEmpty, "\(descriptor.id) declares no URL")
        }
    }

    /// A licence that requires attribution needs somebody to attribute.
    ///
    /// MIT wants the copyright line reproduced and CC BY §3(a)(1) wants the creator
    /// named. Neither can be satisfied from a source id: `cities-json` is not GeoNames,
    /// and `mime-db` is not Jonathan Ong and Douglas Christopher Wilson.
    @Test("attribution licences carry a copyright holder")
    func holderRecorded() {
        // `public-facts` and `public-domain` are the deliberate exceptions — there is no
        // holder because there is no grant, which `LICENSES/<id>.txt` states in prose.
        // `Unlicense` joins them for the same reason: it is a dedication *away* from
        // copyright, so naming a holder would contradict the grant it makes. `CC0-1.0` is
        // the same instrument despite the Creative Commons name it shares with the CC BY
        // licences: it waives the rights rather than licensing them.
        let noGrant: Set<String> = ["public-facts", "public-domain", "Unlicense", "CC0-1.0"]

        for descriptor in Self.descriptors where !noGrant.contains(descriptor.license) {
            #expect(
                !descriptor.copyright.isEmpty,
                "\(descriptor.id) is \(descriptor.license) but names no copyright holder"
            )
        }
    }

    /// The check that would have caught all five mislabelled descriptors.
    ///
    /// Deliberately narrow: it does not try to identify a licence from its text, which
    /// is a research problem. It asserts only that a descriptor claiming a licence does
    /// not sit atop a text that names a *different* licensor — the specific way these
    /// five were wrong, and the way a sixth would be.
    @Test("a descriptor's licence is not contradicted by its own text")
    func licenceMatchesText() throws {
        // Each entry: a phrase that, appearing in the text, rules the claimed licence out.
        //
        // The phrase is "princeton", never "wordnet". Half the sources here have WordNet
        // in their *project name* — MultiWordNet is plain CC BY 3.0 and says so in its
        // first line — so matching the word flags four correct descriptors and teaches
        // whoever hits it to widen the exception list. Princeton is the licensor, and
        // its name appears only where its terms actually apply.
        let contradictions: [(claim: String, phrase: String, means: String)] = [
            ("WordNet-3.0", "commercial use of dannet", "the DanNet licence"),
            ("WordNet-3.0", "norwegian wordnet", "the NWN licence"),
            // A WordNet-3.0 claim over a text that never names Princeton is the error
            // found in `omw-cmn`, `omw-he`, `omw-ja` and `omw-th`: all four ship the PWN
            // licence *template* re-issued by NICT, the University of Haifa or Francis
            // Bond, which is a different licence with the same wording.
            ("CC-BY-3.0", "princeton", "a Princeton grant the CC BY claim omits"),
            ("CC-BY-4.0", "princeton", "a Princeton grant the CC BY claim omits"),
            ("MIT", "gnu general public license", "the GPL"),
            ("MIT", "apache license", "Apache-2.0"),
        ]

        for descriptor in Self.descriptors {
            let file = Self.root.appendingPathComponent("LICENSES/\(descriptor.id).txt")
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let lowered = text.lowercased()

            for rule in contradictions where descriptor.license == rule.claim {
                let complaint =
                    "\(descriptor.id) claims \(rule.claim), but LICENSES/\(descriptor.id).txt "
                    + "reads as \(rule.means) — it contains '\(rule.phrase)'"
                #expect(!lowered.contains(rule.phrase), "\(complaint)")
            }
        }
    }

    /// The obligation the whole `LICENSES/` directory exists to discharge.
    ///
    /// MIT, the WordNet family and Unicode-3.0 all require their notice to travel with
    /// the distribution; a link does not satisfy any of them. The public-domain sources
    /// need the opposite — a recorded reason why no text exists, so the absence reads as
    /// a conclusion rather than an oversight. Both live in the same place, so one check
    /// covers both.
    @Test("every source has a licence text or a recorded reason")
    func textCommitted() throws {
        for descriptor in Self.descriptors {
            let file = Self.root.appendingPathComponent("LICENSES/\(descriptor.id).txt")
            let text = try? String(contentsOf: file, encoding: .utf8)
            // A low floor on purpose. It is here to catch an empty or truncated file,
            // not to judge length: the Croatian wordnet's entire rights statement is one
            // sentence, and demanding more of it would mean padding a verbatim copy.
            let complaint =
                "LICENSES/\(descriptor.id).txt is missing or too short to be a licence "
                + "or a reasoned statement of why none exists"
            #expect((text?.count ?? 0) > 60, "\(complaint)")
        }
    }

    /// `LICENSES/` must describe what ships, in both directions.
    ///
    /// A file for a source that was dropped is stale rather than harmless: it makes the
    /// distribution look like it carries data it does not, which is its own kind of
    /// untrue statement about provenance.
    @Test("no licence file names a source that is no longer used")
    func noOrphanedTexts() throws {
        let ids = Set(Self.descriptors.map(\.id))
        let names = try FileManager.default.contentsOfDirectory(
            atPath: Self.root.appendingPathComponent("LICENSES").path
        )
        for name in names where name.hasSuffix(".txt") {
            let id = String(name.dropLast(4))
            #expect(ids.contains(id), "LICENSES/\(name) has no matching source descriptor")
        }
    }

    /// The question the whole licence apparatus exists to answer.
    ///
    /// Decoy is distributed under Apache-2.0, which is only possible if every source
    /// permits it. Share-alike would force the corpus open under a different licence;
    /// a non-commercial term would forbid most of what users do with a fixture library.
    /// Neither can be allowed in by accident, so the test asserts the *shape* of every
    /// licence rather than trusting the label.
    @Test("no source licence forbids Apache-2.0 distribution")
    func everyLicencePermitsApacheDistribution() throws {
        let forbidden = [
            "noncommercial", "non-commercial use", "share-alike", "sharealike",
            "gnu general public license", "lesser general public license",
            "for research purposes only", "academic use only",
        ]

        for descriptor in Self.descriptors {
            let file = Self.root.appendingPathComponent("LICENSES/\(descriptor.id).txt")
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let lowered = text.lowercased()

            for phrase in forbidden {
                guard let hit = lowered.range(of: phrase) else { continue }
                // The Unlicense grants "commercial or non-commercial" use. A substring
                // match cannot tell a permission from a prohibition, and this is the one
                // construction that recurs.
                if phrase.contains("commercial"),
                    lowered.contains("commercial or non-commercial")
                {
                    continue
                }
                // Where a source publishes no licence file, `LICENSES/<id>.txt` records the
                // conclusion in prose instead — and prose says things like "no share-alike
                // condition", which a substring scan reads as the opposite of its meaning.
                // A short look-back for a negator is enough: the window is deliberately too
                // narrow to reach a negation two clauses away, which would start excusing
                // text that really does impose the term.
                let start =
                    lowered.index(hit.lowerBound, offsetBy: -32, limitedBy: lowered.startIndex)
                    ?? lowered.startIndex
                // Whitespace collapsed first: a licence file is wrapped prose, so the
                // negation lands wherever the line breaks. `impose no\nshare-alike` was
                // read as a share-alike term by this check, in a file saying the opposite.
                // Trailing space appended: the window ends where the phrase begins, so a
                // negator immediately before it has nothing after it to match "no ".
                let before =
                    lowered[start..<hit.lowerBound]
                    .split(whereSeparator: \.isWhitespace)
                    .joined(separator: " ") + " "
                let negators = ["no ", "not ", "nor ", "neither ", "without ", "waives ", "free of "]
                if negators.contains(where: before.contains) { continue }
                let complaint =
                    "\(descriptor.id) contains '\(phrase)', which Apache-2.0 distribution "
                    + "cannot accommodate"
                Issue.record("\(complaint)")
            }
        }
    }

    /// Attribution is the one obligation every source here imposes, and the one that is
    /// easiest to fail silently — a source can be fetched, used and never named.
    @Test("every source reaches NOTICE")
    func everySourceIsAttributed() throws {
        let notice = try String(
            contentsOf: Self.root.appendingPathComponent("NOTICE"), encoding: .utf8)
        for descriptor in Self.descriptors {
            #expect(
                notice.contains(descriptor.id),
                "\(descriptor.id) is fetched and used but never named in NOTICE"
            )
        }
    }

    /// Decoy's own copyright, which nothing else asserts.
    @Test("the project asserts its own copyright")
    func ownCopyright() throws {
        let license = try String(
            contentsOf: Self.root.appendingPathComponent("LICENSE"), encoding: .utf8)
        #expect(
            !license.contains("[name of copyright owner]"),
            "LICENSE still carries Apache's unfilled boilerplate placeholder"
        )
    }
}
