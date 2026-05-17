import XCTest
import SwiftUI
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

    func test_everyBrandHasAStableAssetNameAndParseableTint() {
        for brand in BrandCatalog.all {
            XCTAssertEqual(brand.assetName, "brand.\(brand.id)")
            XCTAssertFalse(brand.matchKeys.isEmpty, "\(brand.id) needs match keys")
            // Hex must be 6 chars — Color(hex:) tolerates more, but the
            // catalogue should stay tidy.
            XCTAssertEqual(brand.tintHex.count, 6,
                           "\(brand.id) tint hex should be 6 digits")
        }
    }

    func test_brandIDsAreUnique() {
        let ids = BrandCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Brand ids must be unique")
    }

    func test_irishRegionalBrands_haveADomainForTheAPITier() {
        // simple-icons doesn't stock these — they rely entirely on the
        // logo-API tier, so a domain is mandatory.
        for id in ["gomo", "eir", "electricireland", "bordgais",
                   "virginmedia", "flyefit"] {
            let brand = BrandCatalog.all.first { $0.id == id }
            XCTAssertNotNil(brand, "expected catalogue entry: \(id)")
            XCTAssertNotNil(brand?.domain, "\(id) needs a domain for the logo API")
        }
    }

    func test_colorHexParsing() {
        // 6-digit, with + without leading hash.
        let red = Color(hex: "E50914")
        let redHashed = Color(hex: "#E50914")
        XCTAssertEqual(red, redHashed)
        // Garbage falls back to gray rather than crashing.
        XCTAssertEqual(Color(hex: "not-a-colour"), .gray)
    }
}
