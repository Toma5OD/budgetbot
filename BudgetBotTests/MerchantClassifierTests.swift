import XCTest
@testable import BudgetBot

final class MerchantClassifierTests: XCTestCase {

    func test_fastFood_matchesChainsAndDelivery() {
        for name in ["Domino's Pizza — Camden St", "DOMINOS BURRO",
                     "Apache Pizza", "Four Star Pizza", "McDonald's Henry St",
                     "Burger King O'Connell", "KFC Coolock", "Subway Wexford",
                     "Just Eat", "Deliveroo", "Uber Eats",
                     "Eddie Rocket's", "Supermac's Galway", "Boojum",
                     "Chopped Stephen's Green"] {
            XCTAssertTrue(MerchantClassifier.isFastFood(name),
                          "Expected fast-food match for: \(name)")
        }
    }

    func test_fastFood_doesNotMatchSitDownRestaurants() {
        for name in ["Bunsen Wexford St", "Manifesto Rathmines",
                     "Klaw Crow St", "Pichet", "Bastible",
                     "Forest Avenue", "Featherblade", "Yamamori Sushi"] {
            XCTAssertFalse(MerchantClassifier.isFastFood(name),
                           "Sit-down restaurant should not be fast food: \(name)")
        }
    }

    func test_coffee_matchesChains() {
        for name in ["Starbucks Henry St", "Costa Liffey Valley",
                     "Insomnia", "Java Republic", "Butlers Café Grafton",
                     "3FE Grand Canal", "Black & Stone", "Two Pups Coffee",
                     "Cinnamon", "Some Local Cafe", "Espresso Bar Phibsboro"] {
            XCTAssertTrue(MerchantClassifier.isCoffee(name),
                          "Expected coffee match for: \(name)")
        }
    }

    func test_coffee_doesNotMatchUnrelated() {
        XCTAssertFalse(MerchantClassifier.isCoffee("Tesco Express"))
        XCTAssertFalse(MerchantClassifier.isCoffee("Boots Pharmacy"))
        XCTAssertFalse(MerchantClassifier.isCoffee("Manifesto Rathmines"))
    }

    func test_alcohol_prefersCategoryMatchOverPayee() {
        // Even with a generic merchant name, the Alcohol category wins.
        XCTAssertTrue(MerchantClassifier.isAlcohol(
            payee: "Generic Shop", categoryName: "Alcohol"))
        XCTAssertTrue(MerchantClassifier.isAlcohol(
            payee: "The Long Hall", categoryName: nil))
        XCTAssertTrue(MerchantClassifier.isAlcohol(
            payee: "Eight Degrees Brewing — Taproom", categoryName: nil))
        XCTAssertFalse(MerchantClassifier.isAlcohol(
            payee: "Tesco", categoryName: "Groceries"))
    }

    func test_premiumRetail_matchesKnownChains() {
        for name in ["Brown Thomas Online", "Marks & Spencer Grafton",
                     "M&S Food", "Avoca Suffolk St", "Donnybrook Fair",
                     "Tesco Finest"] {
            XCTAssertTrue(MerchantClassifier.isPremiumRetail(name),
                          "Expected premium retail match for: \(name)")
        }
    }

    func test_valueRetail_matchesDiscountChains() {
        for name in ["Aldi Camden St", "Lidl Phibsboro", "Penneys Mary St",
                     "TK Maxx", "Mr Price", "B&M Bargains", "Dealz"] {
            XCTAssertTrue(MerchantClassifier.isValueRetail(name),
                          "Expected value retail match for: \(name)")
        }
    }

    func test_premiumAndValue_areMutuallyExclusiveForCleanCases() {
        // Penneys clearly value, Brown Thomas clearly premium — neither
        // should match the other bucket.
        XCTAssertFalse(MerchantClassifier.isPremiumRetail("Penneys Mary St"))
        XCTAssertFalse(MerchantClassifier.isValueRetail("Brown Thomas"))
    }

    func test_buckets_returnsAllApplicable() {
        let buckets = MerchantClassifier.buckets(
            forPayee: "Domino's Pizza — Camden St", categoryName: "Dining")
        XCTAssertTrue(buckets.contains(.fastFood))
        XCTAssertFalse(buckets.contains(.coffee))

        let alcoholBuckets = MerchantClassifier.buckets(
            forPayee: "Generic Off Licence", categoryName: "Alcohol")
        XCTAssertTrue(alcoholBuckets.contains(.alcohol))
    }
}
