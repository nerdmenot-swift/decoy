import Testing

// The documented fix for swift-testing also exporting a `Trait`. Written here rather
// than worked around, so the advice in `Trait`'s doc comment is the advice that is tested.
import struct Decoy.Trait

@testable import Decoy
@testable import DecoyLocaleEN

/// Every code example in `Forge`'s and `Faker`'s documentation, transcribed and compiled.
///
/// Four of them did not compile. Two called `Forge<User> { User() }`, an initialiser
/// deliberately removed when forge names were made explicit; two called `$0.name.firstName()`
/// against a namespace since renamed to `person`. Doc examples are the first thing anybody
/// reads and the only part of the library nothing checks, so they drifted silently — and
/// an example showing a shorter initialiser than the one that exists made the real API look
/// more verbose than it is.
///
/// These are copies rather than the originals, which is the honest limitation: nothing forces
/// somebody editing a doc comment to edit here too. What it does catch is the API moving
/// underneath prose that was correct when written, which is what actually happened all four
/// times.
@Suite("Documentation examples compile")
struct DocExampleTests {

    enum Role { case member, admin }
    struct User {
        var name = ""
        var firstName = ""
        var email = ""
        var role: Role = .member
        var posts: [Post] = []
    }
    struct Post { var title = "" }

    /// `Forge` header — specialising a recipe is assignment.
    @Test("a copy specialises without touching the original")
    func specialisationIsAssignment() {
        let users = Forge<User>("user") { User() }
            .locale(DecoyLocaleEN.locale)
            .rule(\.name) { $0.person.fullName() }
        let admins = users.rule(\.role) { _ in .admin }

        #expect(users.generate(4, seed: 1337).allSatisfy { $0.role == .member })
        #expect(admins.generate(4, seed: 1337).allSatisfy { $0.role == .admin })
        // The point of the example: `users` still generates what it did before.
        #expect(
            users.generate(4, seed: 1337).map(\.name)
                == admins.generate(4, seed: 1337).map(\.name))
    }

    /// `rule(_:_:)` reading the partially built instance.
    @Test("a later rule reads what an earlier one wrote")
    func rulesSeeEarlierWrites() {
        let users = Forge<User>("user") { User() }
            .locale(DecoyLocaleEN.locale)
            .rule(\.firstName) { $0.person.firstName() }
            .rule(\.email) { _, user in "\(user.firstName.lowercased())@example.com" }

        for user in users.generate(8, seed: 1337) {
            #expect(user.email == "\(user.firstName.lowercased())@example.com")
        }
    }

    /// `locale(_:)` and `novelNames()`.
    @Test("locale and novelNames read as the docs show them")
    func configuration() {
        let german = DecoyLocaleEN.locale
        let users = Forge<User>("user") { User() }.locale(german)
        #expect(users.generate(2, seed: 1337).count == 2)

        let novel = Forge<User>("user") { User() }
            .locale(DecoyLocaleEN.locale)
            .novelNames()
            .rule(\.name) { $0.person.fullName() }
        #expect(novel.generate(4, seed: 1337).allSatisfy { !$0.name.isEmpty })
    }

    /// `each(_:_:of:)`, both the range and the fixed-count form.
    @Test("children fan out by range or by exact count")
    func fanOut() {
        let posts = Forge<Post>("post") { Post() }.rule(\.title) { $0.lorem.sentence(words: 3) }
        let byRange = Forge<User>("user") { User() }
            .locale(DecoyLocaleEN.locale)
            .each(\.posts, 0...5, of: posts)
        let byCount = Forge<User>("user") { User() }
            .locale(DecoyLocaleEN.locale)
            .each(\.posts, 3, of: posts)

        #expect(byRange.generate(20, seed: 1337).allSatisfy { (0...5).contains($0.posts.count) })
        #expect(byCount.generate(20, seed: 1337).allSatisfy { $0.posts.count == 3 })
        // The fixed form is the range form, so it must produce identical rows.
        #expect(
            byCount.generate(6, seed: 1337).map { $0.posts.map(\.title) }
                == Forge<User>("user") { User() }
                    .locale(DecoyLocaleEN.locale)
                    .each(\.posts, 3...3, of: posts)
                    .generate(6, seed: 1337).map { $0.posts.map(\.title) })
    }

    /// `generate(rows:seed:)` — the example splits a large run across tasks.
    @Test("a slice equals the same indices of the whole run")
    func chunkedGeneration() {
        let events = Forge<Post>("event") { Post() }
            .locale(DecoyLocaleEN.locale)
            .rule(\.title) { $0.lorem.word() }

        let whole = events.generate(400, seed: 1337).map(\.title)
        var joined = [String]()
        for start in stride(from: 0, to: 400, by: 50) {
            joined += events.generate(rows: start..<start + 50, seed: 1337).map(\.title)
        }
        #expect(joined == whole)
    }

    /// `stream(seed:)`.
    @Test("a stream matches the run it streams")
    func streaming() {
        let users = Forge<User>("user") { User() }
            .locale(DecoyLocaleEN.locale)
            .rule(\.name) { $0.person.fullName() }

        #expect(
            Array(users.stream(seed: 1337).prefix(25)).map(\.name)
                == users.generate(25, seed: 1337).map(\.name))
    }

    /// The `Trait` example, including static-member lookup at the call site.
    @Test("traits apply by static-member lookup")
    func traits() {
        let users = Forge<User>("user") { User() }.locale(DecoyLocaleEN.locale)
        let staff = users.generate(10, seed: 1337, applying: .admin)
        #expect(staff.allSatisfy { $0.role == .admin })
    }

    /// `Faker`'s header — a namespace method advances the RNG through a value type.
    @Test("namespace access advances the shared stream")
    func namespacesAdvanceTheRNG() {
        var faker = Faker(seed: 1337, locale: DecoyLocaleEN.locale)
        let drawn = (0..<6).map { _ in faker.person.firstName() }
        // If the namespace were not written back, every draw would repeat the first.
        #expect(Set(drawn).count > 1)
    }
}

extension Trait where T == DocExampleTests.User {
    static var admin: Trait {
        Trait("admin") { $0.rule(\.role) { _ in .admin } }
    }
}
