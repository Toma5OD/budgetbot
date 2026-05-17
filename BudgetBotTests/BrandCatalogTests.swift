import XCTest
@testable import BudgetBot

final class BrandCatalogTests: XCTestCase {

    func test_matchesKnownBrandsCaseInsensitively() {
        XCTAssertEqual(BrandCatalog.match(name: "Netflix")?.id, "netflix")
        XCTAssertEqual(BrandCatalog.match(name: "NETFLIX")?.id, "netflix")
        XCTAssertEqual(BrandCatalog.match(name: "Spotify Premium")?.id, "spotify")
        XCTAssertEqual(BrandCatalog.match(name: "Disney+")?.id, "disneyplus")
    }

    func test_matchesWithinLongerDisplayNames() {
        // RecurringRule display names carry branch / plan suffixes.
        XCTAssertEqual(BrandCatalog.match(name: "GoMo")?.id, "gomo")
        XCTAssertEqual(BrandCatalog.match(name: "Eir Broadband")?.id, "eir")
        XCTAssertEqual(BrandCatalog.match(name: "Electric Ireland")?.id, "electricireland")
        XCTAssertEqual(BrandCatalog.match(name: "FlyeFit Stephen's Green")?.id, "flyefit")
    }

    func test_unknownBrand_returnsNil() {
        XCTAssertNil(BrandCatalog.match(name: "Some Local Window Cleaner"))
    }

    func test_brandIDsAreUnique() {
        let ids = BrandCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Brand ids must be unique")
    }

    func test_everyBrandHasMatchKeysAndADomain() {
        // Logos are fetched by domain — a brand with no domain could
        // never resolve a logo; one with no match keys is unreachable.
        for brand in BrandCatalog.all {
            XCTAssertFalse(brand.matchKeys.isEmpty, "\(brand.id) needs match keys")
            XCTAssertFalse(brand.domain.isEmpty, "\(brand.id) needs a domain")
            XCTAssertTrue(brand.domain.contains("."),
                          "\(brand.id) domain looks malformed: \(brand.domain)")
        }
    }

    func test_irishRegionalBrands_areCatalogued() {
        for id in ["gomo", "eir", "electricireland", "bordgais",
                   "virginmedia", "flyefit"] {
            XCTAssertTrue(BrandCatalog.all.contains { $0.id == id },
                          "expected catalogue entry: \(id)")
        }
    }

    func test_matchesEverydayMerchants() {
        // Demo-data-style payees carry branch suffixes / casing noise.
        XCTAssertEqual(BrandCatalog.match(name: "Tesco Express Camden")?.id, "tesco")
        XCTAssertEqual(BrandCatalog.match(name: "TESCO EXTRA LIFFEY VALLEY")?.id, "tesco")
        XCTAssertEqual(BrandCatalog.match(name: "Boots Pharmacy Henry St")?.id, "boots")
        XCTAssertEqual(BrandCatalog.match(name: "Penneys Mary St")?.id, "penneys")
        XCTAssertEqual(BrandCatalog.match(name: "Domino's Pizza — Camden St")?.id, "dominos")
        XCTAssertEqual(BrandCatalog.match(name: "Free Now Dublin")?.id, "freenow")
        XCTAssertEqual(BrandCatalog.match(name: "Circle K")?.id, "circlek")
    }

    func test_longerKeysWinOverGenericOnes() {
        // "Applegreen" must not be swallowed by an Apple* subscription
        // key, and "Amazon Prime" must beat the bare "amazon" merchant.
        XCTAssertEqual(BrandCatalog.match(name: "Applegreen Stores")?.id, "applegreen")
        XCTAssertEqual(BrandCatalog.match(name: "Amazon Prime")?.id, "primevideo")
        XCTAssertEqual(BrandCatalog.match(name: "Amazon UK")?.id, "amazon")
    }
}
