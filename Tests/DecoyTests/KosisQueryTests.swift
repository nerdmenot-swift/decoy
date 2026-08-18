import Foundation
import Testing

@testable import DecoyAdapterKit

/// The KOSIS transform, which is the only part of that fetcher that can be tested here.
///
/// The request itself has never run: the portal answers only to a registered key and there
/// was none. So the shape below is KOSIS's published field list rather than an observed
/// response, and these tests prove the transform does the right thing *given* that shape —
/// not that the shape is right. The fetcher's errors are written to say which assumption
/// broke, because that is what the first real run will need.
@Suite("KOSIS query")
struct KosisQueryTests {

    /// A response in the documented shape: positional classifications, values as strings.
    ///
    /// A function rather than a stored property: `[[String: Any]]` is not `Sendable`, and a
    /// static one is shared across the suite's parallel tests.
    private static func sample() -> [[String: Any]] { [
        ["C1_NM": "김", "C2_NM": "김해", "DT": "4456700", "ITM_NM": "인구"],
        ["C1_NM": "김", "C2_NM": "경주", "DT": "1802700", "ITM_NM": "인구"],
        ["C1_NM": "이", "C2_NM": "전주", "DT": "2631000", "ITM_NM": "인구"],
        ["C1_NM": "박", "C2_NM": "밀양", "DT": "3031000", "ITM_NM": "인구"],
        // KOSIS marks aggregates with 계. Including one makes it the commonest surname in
        // Korea by a factor of four.
        ["C1_NM": "계", "C2_NM": "계", "DT": "49705000", "ITM_NM": "인구"],
        // Thousands separators appear in some tables and not others.
        ["C1_NM": "최", "C2_NM": "경주", "DT": "1,000,000", "ITM_NM": "인구"],
    ] }

    @Test("clan rows are summed per surname, and totals dropped")
    func aggregation() throws {
        let rows = try KosisQuery.rows(from: Self.sample())
        let surnames = try KosisQuery.aggregate(rows, minimum: 1)

        // 김 appears twice and must be added up, not taken once.
        let kim = try #require(surnames.first { $0.name == "김" })
        #expect(kim.count == 6_259_400)
        #expect(surnames.first?.name == "김", "commonest first")
        #expect(!surnames.contains { $0.name == "계" }, "the total row survived")
        #expect(surnames.map(\.name) == ["김", "박", "이", "최"])
    }

    @Test("a rejected request is not mistaken for an empty one")
    func errorResponse() {
        // KOSIS reports failure as a JSON *object* with HTTP 200, so a rejected request
        // looks exactly like a successful one to anything checking the status code.
        let error: [String: Any] = ["err": "30", "errMsg": "인증키가 유효하지 않습니다"]
        #expect(throws: KosisQuery.Failure.self) { _ = try KosisQuery.rows(from: error) }
    }

    @Test("the wrong classification column is reported, not silently empty")
    func wrongColumn() {
        // A surname-by-clan table may put the surname in C2. Asking for a column that is
        // not there must say so rather than return nothing.
        #expect(throws: KosisQuery.Failure.self) {
            _ = try KosisQuery.rows(from: Self.sample(), classification: "C7_NM")
        }
    }

    @Test("too few surnames is a failure, because Korea has about 250")
    func floor() throws {
        let rows = try KosisQuery.rows(from: Self.sample())
        #expect(throws: KosisQuery.Failure.self) { _ = try KosisQuery.aggregate(rows) }
    }

    @Test("the request carries the key and the table it was given")
    func requestURL() throws {
        let url = try #require(
            KosisQuery.url(key: "SECRET", org: "101", table: "DT_1IN1503", period: "2015"))
        let text = url.absoluteString
        for expected in ["apiKey=SECRET", "orgId=101", "tblId=DT_1IN1503", "startPrdDe=2015",
                         "format=json", "method=getList"] {
            #expect(text.contains(expected), "missing \(expected)")
        }
    }
}
