extension Faker {
    public var company: CompanyFaker {
        get { CompanyFaker(faker: self) }
        set { self = newValue.faker }
    }

    public var commerce: CommerceFaker {
        get { CommerceFaker(faker: self) }
        set { self = newValue.faker }
    }

    public var finance: FinanceFaker {
        get { FinanceFaker(faker: self) }
        set { self = newValue.faker }
    }
}

// MARK: - Company

public struct CompanyFaker {
    var faker: Faker

    public mutating func name() -> String {
        faker.expand(faker.require("company.name_pattern"))
    }

    public mutating func adjective() -> String { faker.require("company.adjective") }
    public mutating func descriptor() -> String { faker.require("company.descriptor") }
    public mutating func noun() -> String { faker.require("company.noun") }
    public mutating func legalEntityType() -> String { faker.require("company.legal_entity_type") }

    /// Deliberately awful corporate jargon: "synergise frictionless paradigms".
    public mutating func buzzPhrase() -> String {
        "\(buzzVerb()) \(buzzAdjective()) \(buzzNoun())"
    }

    public mutating func buzzVerb() -> String { faker.require("company.buzz_verb") }
    public mutating func buzzAdjective() -> String { faker.require("company.buzz_adjective") }
    public mutating func buzzNoun() -> String { faker.require("company.buzz_noun") }

    public mutating func catchPhrase() -> String {
        "\(adjective()) \(descriptor()) \(noun())"
    }
}

// MARK: - Commerce

public struct CommerceFaker {
    var faker: Faker

    public mutating func department() -> String { faker.require("commerce.department") }
    public mutating func product() -> String { faker.require("commerce.product_name.product") }
    public mutating func productAdjective() -> String {
        faker.require("commerce.product_name.adjective")
    }
    public mutating func productMaterial() -> String {
        faker.require("commerce.product_name.material")
    }

    public mutating func productName() -> String {
        faker.expand(faker.require("commerce.product_name.pattern"))
    }

    public mutating func productDescription() -> String {
        faker.expand(faker.require("commerce.product_description"))
    }

    /// A price as a fixed-point decimal string.
    ///
    /// Formatted by hand rather than through `String(format:)` so the core module
    /// stays Foundation-free and the output does not shift with the host locale — a
    /// German machine must not emit `19,99` into a fixture another machine reads.
    public mutating func price(
        in range: ClosedRange<Double> = 1...1_000,
        decimals: Int = 2
    ) -> String {
        var scale = 1.0
        for _ in 0..<decimals { scale *= 10 }
        let raw = (faker.double(in: range) * scale).rounded()
        let units = Int(raw / scale)
        let fraction = Int(raw) - units * Int(scale)
        guard decimals > 0 else { return String(units) }
        var fractionText = String(fraction)
        while fractionText.count < decimals { fractionText = "0" + fractionText }
        return "\(units).\(fractionText)"
    }

    /// A 12-digit EAN plus its check digit, so the barcode actually validates.
    public mutating func ean13() -> String {
        let body = faker.numerify(String(repeating: "#", count: 12))
        return body + String(Self.eanCheckDigit(body))
    }

    static func eanCheckDigit(_ digits: String) -> Int {
        var sum = 0
        for (index, character) in digits.enumerated() {
            let value = character.wholeNumberValue ?? 0
            sum += index % 2 == 0 ? value : value * 3
        }
        return (10 - sum % 10) % 10
    }

    public mutating func sku() -> String {
        faker.bothify("??-####-??")
    }
}

// MARK: - Finance

public struct FinanceFaker {
    var faker: Faker

    public mutating func accountType() -> String { faker.require("finance.account_type") }
    public mutating func transactionType() -> String { faker.require("finance.transaction_type") }

    public mutating func transactionDescription() -> String {
        faker.expand(faker.require("finance.transaction_description_pattern"))
    }

    public mutating func accountNumber(digits: Int = 8) -> String {
        faker.numerify(String(repeating: "#", count: digits))
    }

    public mutating func routingNumber() -> String {
        faker.require("finance.federal_reserve_routing_symbol")
    }

    /// A currency as a coherent `(name, code, symbol, numericCode)` row.
    public mutating func currency() -> [String: String] {
        faker.drawRow("finance.currency") ?? [:]
    }

    public mutating func currencyName() -> String { currency()["name"] ?? "" }
    public mutating func currencyCode() -> String { currency()["code"] ?? "" }
    public mutating func currencySymbol() -> String { currency()["symbol"] ?? "" }

    /// A credit card number that passes the Luhn check.
    ///
    /// Generating digit-shaped strings would be easier, but anything validating input
    /// — which is most code worth testing — would reject every fixture. The corpus
    /// supplies the issuer prefix patterns; the final digit is computed.
    public mutating func creditCardNumber(issuer: String? = nil) -> String {
        let issuers = ["visa", "mastercard", "american_express", "discover", "diners_club", "jcb"]
        let chosen = issuer ?? faker.pick(issuers)
        guard let pattern = faker.draw("finance.credit_card.\(chosen)") else {
            return Self.luhnComplete(faker.numerify("################"))
        }
        // Corpus patterns may carry a trailing `L` marking "append a Luhn digit".
        let cleaned = pattern.hasSuffix("L") ? String(pattern.dropLast()) : pattern
        let body = faker.bothify(cleaned.replacingOccurrencesOfSlash())
        return Self.luhnComplete(body)
    }

    /// Appends the digit that makes `body` satisfy the Luhn checksum.
    ///
    /// `static` and shared: IMEI needs the same algorithm, and reaching for the
    /// nearest-looking check-digit function instead is how `phone.imei()` shipped with an
    /// EAN-13 check digit on a number the world validates with Luhn.
    static func luhnComplete(_ body: String) -> String {
        let digits = body.compactMap(\.wholeNumberValue)
        var sum = 0
        // The check digit will sit at the end, so positions double from the right of
        // the *completed* number — i.e. the last body digit doubles.
        for (offset, value) in digits.reversed().enumerated() {
            if offset % 2 == 0 {
                let doubled = value * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += value
            }
        }
        return body + String((10 - sum % 10) % 10)
    }

    /// An IBAN with a valid mod-97 check, so it survives real validators.
    public mutating func iban(country: String = "GB") -> String {
        let bban = faker.bothify("????" + String(repeating: "#", count: 14))
        let rearranged = bban + country + "00"
        let check = 98 - Self.mod97(rearranged)
        let checkDigits = check < 10 ? "0\(check)" : "\(check)"
        return country + checkDigits + bban
    }

    /// Mod-97 over the alphanumeric expansion, computed incrementally so no
    /// arbitrary-precision integer is needed.
    static func mod97(_ input: String) -> Int {
        var remainder = 0
        for character in input.uppercased() {
            if let digit = character.wholeNumberValue, character.isNumber {
                remainder = (remainder * 10 + digit) % 97
            } else if let ascii = character.asciiValue, ascii >= 65, ascii <= 90 {
                remainder = (remainder * 100 + Int(ascii - 55)) % 97
            }
        }
        return remainder
    }

    /// A Bitcoin address.
    ///
    /// Delegates to ``CryptoFaker/bitcoinAddress()``. The former implementation built
    /// `"1" + bothify(…)`, which emitted `0`, `O` and `I` — characters Base58 excludes —
    /// and carried no checksum, so nothing that validated an address would accept one.
    public mutating func bitcoinAddress() -> String {
        faker.crypto.bitcoinAddress()
    }

    /// An Employer Identification Number, `NN-NNNNNNN`.
    ///
    /// US-specific, like the IRS that issues it. The prefix is drawn from the campus
    /// codes actually in use, so the result matches the validation most systems apply.
    public mutating func ein() -> String {
        let prefixes = [
            "01", "02", "03", "04", "05", "06", "10", "11", "12", "13", "14", "15", "16",
            "20", "21", "22", "23", "24", "25", "26", "27", "30", "31", "32", "33", "34",
            "35", "36", "37", "38", "39", "40", "41", "42", "43", "44", "45", "46", "47",
            "48", "50", "51", "52", "53", "54", "55", "56", "57", "58", "59", "60", "61",
            "62", "63", "64", "65", "66", "67", "68", "71", "72", "73", "74", "75", "76",
            "77", "80", "81", "82", "83", "84", "85", "86", "87", "88", "90", "91", "92",
            "93", "94", "95", "98", "99",
        ]
        return faker.pick(prefixes) + "-" + faker.numerify("#######")
    }
}

extension String {
    /// faker's card patterns use `/` to separate alternatives; take the first.
    fileprivate func replacingOccurrencesOfSlash() -> String {
        split(separator: "/").first.map(String.init) ?? self
    }
}
