/// Every adapter, once.
///
/// The list used to exist twice — the builder had one and the parity suite had another —
/// and a third thing wanted it: `decoy-validate` checks that every source an adapter names
/// has a descriptor beside it.
///
/// That check used to read the adapter *files*, scanning for `export const source =` and
/// reporting what it found. When the JavaScript went, so did the directory it scanned, and
/// the check went quietly to zero adapters while still printing a reassuring summary line.
/// That is the failure mode the whole project exists to argue against, so it is not
/// replaced with the same scan against `.swift` files: the adapters are compiled, they
/// declare their sources in the type system, and the validator now links this and asks
/// them.
///
/// The order is the old filename order. It matters only for which of two conflicting
/// adapters is named first in the error — a conflict is refused rather than resolved.
public enum Adapters {

    public static var all: [any Adapter] {
        [
            AirportsAdapter(),
            AuthoredCommerceAdapter(),
            AuthoredListsAdapter.fixtures(),
            AuthoredListsAdapter.whimsy(),
            AuthoredAdapter(),
            CitiesAdapter(),
            ChineseNamesAdapter(),
            CivilNamesAdapter(),
            CLDRDatesAdapter(),
            AuthoredListsAdapter.commonKnowledge(),
            EmojiAdapter(),
            IANATLDAdapter(),
            IANATZDBAdapter(),
            IANAWebAdapter(),
            ISO31662Adapter(),
            ISO3166Adapter(),
            ISO4217Adapter(),
            ISO639Adapter(),
            KoreanNamesAdapter(),
            LatinWordsAdapter(),
            LegalEntitiesAdapter(),
            MIMETypesAdapter(),
            OccupationsAdapter(),
            PeriodicTableAdapter(),
            PersianWordsAdapter(),
            PhoneFormatsAdapter(),
            PostalAdapter(),
            ProgrammingLanguagesAdapter(),
            SIUnitsAdapter(),
            SpanishSurnamesAdapter(),
            USSurnamesAdapter(),
            VietnameseNamesAdapter(),
            WikidataColoursAdapter(),
            WikidataNamesAdapter(),
            WikidataTermsAdapter(),
            WordNetAdapter(),
        ]
    }

    /// Object nodes whose keys are data. The compiler emits a `__keys` table for these and
    /// for nothing else.
    public static let keyTables = ["system.mime_type"]
}
