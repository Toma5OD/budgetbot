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
}
