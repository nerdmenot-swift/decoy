extension Faker {
    public var internet: InternetFaker {
        get { InternetFaker(faker: self) }
        set { self = newValue.faker }
    }

    public var phone: PhoneFaker {
        get { PhoneFaker(faker: self) }
        set { self = newValue.faker }
    }
}

// MARK: - Internet

public struct InternetFaker {
    var faker: Faker

    public mutating func domainSuffix() -> String { faker.require("internet.domain_suffix") }

    public mutating func domainWord() -> String {
        faker.person.lastName().asSlug
    }

    public mutating func domainName() -> String {
        "\(domainWord()).\(domainSuffix())"
    }

    public mutating func url(secure: Bool = true) -> String {
        "\(secure ? "https" : "http")://\(domainName())"
    }

    /// Returns an email address.
    ///
    /// Defaults to a domain from `internet.example_email`, which is the RFC 2606
    /// reserved set — test data must not be able to reach a real inbox. Seed data
    /// escaping into a live mailer is an expensive mistake to make once, so opting out
    /// is explicit.
    public mutating func email(
        firstName: String? = nil,
        lastName: String? = nil,
        domain: String? = nil
    ) -> String {
        let first = (firstName ?? faker.person.firstName()).asSlug
        let last = (lastName ?? faker.person.lastName()).asSlug
        let host = domain ?? faker.draw("internet.example_email") ?? "example.com"
        return "\(first).\(last)@\(host)"
    }

    /// An address at a real free-mail provider. Use only when you specifically need
    /// one — unlike ``email(firstName:lastName:domain:)`` this domain accepts mail.
    public mutating func freeEmail() -> String {
        let host = faker.draw("internet.free_email") ?? "gmail.com"
        return email(domain: host)
    }

    public mutating func username() -> String {
        "\(faker.person.firstName().asSlug)\(faker.int(in: 1...9_999))"
    }

    public mutating func password(length: Int = 16) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*")
        return String((0..<length).map { _ in faker.pick(alphabet) })
    }

    public mutating func ipv4() -> String {
        "\(faker.int(in: 1...255)).\(faker.int(in: 0...255))"
            + ".\(faker.int(in: 0...255)).\(faker.int(in: 1...254))"
    }

    public mutating func ipv6() -> String {
        let hex = Array("0123456789abcdef")
        return (0..<8)
            .map { _ in String((0..<4).map { _ in faker.pick(hex) }) }
            .joined(separator: ":")
    }

    public mutating func macAddress() -> String {
        (0..<6).map { _ in
            let value = faker.int(in: 0...255)
            let hex = String(value, radix: 16)
            return hex.count == 1 ? "0\(hex)" : hex
        }
        .joined(separator: ":")
    }

    public mutating func port() -> Int { faker.int(in: 1...65_535) }

    public mutating func httpMethod() -> String {
        faker.pick(["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"])
    }

    /// An HTTP status code, optionally restricted to a class.
    public mutating func httpStatusCode(_ category: HTTPStatusCategory? = nil) -> Int {
        let key = (category ?? faker.pick(HTTPStatusCategory.allCases)).corpusKey
        guard let value = faker.draw("internet.http_status_code.\(key)") else { return 200 }
        return Int(value) ?? 200
    }

    public enum HTTPStatusCategory: Sendable, CaseIterable {
        case informational, success, redirection, clientError, serverError

        var corpusKey: String {
            switch self {
            case .informational: return "informational"
            case .success: return "success"
            case .redirection: return "redirection"
            case .clientError: return "clientError"
            case .serverError: return "serverError"
            }
        }
    }

    public mutating func userAgent() -> String {
        faker.expand(faker.require("internet.user_agent_pattern"))
    }

    public mutating func jwtAlgorithm() -> String { faker.require("internet.jwt_algorithm") }

    public mutating func emoji(_ category: String? = nil) -> String {
        let categories = [
            "smiley", "body", "person", "nature", "food", "travel", "activity", "object",
            "symbol", "flag",
        ]
        return faker.require("internet.emoji.\(category ?? faker.pick(categories))")
    }

    public mutating func hexColor() -> String {
        var out = "#"
        for _ in 0..<6 { out.append(faker.pick(Array("0123456789abcdef"))) }
        return out
    }
}

// MARK: - Phone

public struct PhoneFaker {
    var faker: Faker

    /// A phone number in one of the locale's own formats.
    ///
    /// Formats use `!` for a digit 2-9, so North American area codes and exchange
    /// prefixes come out structurally valid rather than merely digit-shaped.
    public mutating func number(_ style: Style = .human) -> String {
        guard let format = faker.draw("phone_number.format.\(style.corpusKey)") else {
            return faker.numerify("###-###-####")
        }
        return faker.numerify(format)
    }

    public enum Style: Sendable, CaseIterable {
        case human, international, national, mobile

        var corpusKey: String {
            switch self {
            case .human: return "human"
            case .international: return "international"
            case .national: return "national"
            case .mobile: return "mobile"
            }
        }
    }

    public mutating func imei() -> String {
        let body = faker.numerify("##############")
        return body + String(CommerceFaker.eanCheckDigit(body))
    }
}

// MARK: - Shared helpers

extension String {
    /// Lowercased and reduced to ASCII alphanumerics.
    ///
    /// Deliberately lossy: corpus names carry diacritics and non-Latin scripts, and an
    /// address local part or domain label built from them must still be something a
    /// naive validator accepts. Falls back to `"user"` when nothing survives — a
    /// Japanese or Arabic name reduces to the empty string, and an address beginning
    /// with `.` is malformed.
    var asSlug: String {
        var out = String()
        out.reserveCapacity(count)
        for scalar in lowercased().unicodeScalars {
            switch scalar {
            case "a"..."z", "0"..."9": out.unicodeScalars.append(scalar)
            default: break
            }
        }
        return out.isEmpty ? "user" : out
    }
}
