import XCTest
@testable import BudgetBot

final class SubscriptionStyleTests: XCTestCase {

    func test_streamingServices_getTVGlyph() {
        for name in ["Netflix", "Disney+", "Now TV", "Paramount+", "Apple TV+"] {
            XCTAssertEqual(SubscriptionStyle.resolve(name: name).symbol,
                           "play.tv.fill", "\(name) should map to a TV glyph")
        }
    }

    func test_youtube_getsVideoRectangle() {
        XCTAssertEqual(SubscriptionStyle.resolve(name: "YouTube Premium").symbol,
                       "play.rectangle.fill")
    }

    func test_musicServices_getMusicNote() {
        for name in ["Spotify Premium", "Apple Music", "Tidal", "Deezer"] {
            XCTAssertEqual(SubscriptionStyle.resolve(name: name).symbol, "music.note")
        }
    }

    func test_mobileCarriers_getSignalGlyph() {
        for name in ["GoMo", "Vodafone", "Tesco Mobile", "Eir Mobile"] {
            XCTAssertEqual(SubscriptionStyle.resolve(name: name).symbol,
                           "antenna.radiowaves.left.and.right",
                           "\(name) should map to a signal glyph")
        }
    }

    func test_broadband_winsOverMobile_forSharedTokens() {
        // "Eir Broadband" and "Eir Mobile" share the "eir" token —
        // the broadband check must run first.
        XCTAssertEqual(SubscriptionStyle.resolve(name: "Eir Broadband").symbol, "wifi")
        XCTAssertEqual(SubscriptionStyle.resolve(name: "Virgin Media").symbol, "wifi")
        XCTAssertEqual(SubscriptionStyle.resolve(name: "Eir Mobile").symbol,
                       "antenna.radiowaves.left.and.right")
    }

    func test_utilities_getRightGlyphs() {
        XCTAssertEqual(SubscriptionStyle.resolve(name: "Electric Ireland").symbol, "bolt.fill")
        XCTAssertEqual(SubscriptionStyle.resolve(name: "Bord Gáis Energy").symbol, "flame.fill")
        XCTAssertEqual(SubscriptionStyle.resolve(name: "Irish Water").symbol, "drop.fill")
    }

    func test_gym_getsRunner() {
        XCTAssertEqual(SubscriptionStyle.resolve(name: "FlyeFit Stephen's Green").symbol,
                       "figure.run")
        XCTAssertEqual(SubscriptionStyle.resolve(name: "Anytime Fitness").symbol,
                       "figure.run")
    }

    func test_audible_getsHeadphones() {
        XCTAssertEqual(SubscriptionStyle.resolve(name: "Audible").symbol, "headphones")
    }

    func test_unknownName_fallsBackToCategory() {
        // A merchant name we don't recognise, but the detected
        // category tells us what it is.
        XCTAssertEqual(
            SubscriptionStyle.resolve(name: "Some Random ISP", categoryName: "Internet").symbol,
            "wifi")
        XCTAssertEqual(
            SubscriptionStyle.resolve(name: "Mystery Charge", categoryName: "Streaming").symbol,
            "play.tv.fill")
    }

    func test_unknownNameAndCategory_fallsBackToGeneric() {
        let style = SubscriptionStyle.resolve(name: "Totally Unknown Thing")
        XCTAssertEqual(style, SubscriptionStyle.generic)
        XCTAssertEqual(style.symbol, "arrow.triangle.2.circlepath")
    }

    func test_caseInsensitive() {
        XCTAssertEqual(SubscriptionStyle.resolve(name: "NETFLIX").symbol, "play.tv.fill")
        XCTAssertEqual(SubscriptionStyle.resolve(name: "spotify").symbol, "music.note")
    }
}
