import XCTest
@testable import BudgetBot

final class CategoryClassifierTests: XCTestCase {

    func test_necessaryCategories_areMarkedNecessary() {
        for name in ["Rent", "Mortgage", "Electricity", "Heating & Gas",
                     "Water", "Internet", "Mobile Plan", "Insurance",
                     "Pharmacy", "Medical", "Groceries", "Fuel",
                     "Public Transport", "Childcare", "Education"] {
            XCTAssertEqual(CategoryClassifier.bucket(forCategoryName: name), .necessary,
                           "\(name) should be considered necessary")
        }
    }

    func test_discretionaryCategories_areMarkedDiscretionary() {
        for name in ["Dining", "Coffee", "Streaming", "Other Subscriptions",
                     "Entertainment", "Shopping", "Clothing", "Electronics",
                     "Books & Media", "Hobbies", "Travel", "Personal Care"] {
            XCTAssertEqual(CategoryClassifier.bucket(forCategoryName: name), .discretionary,
                           "\(name) should be considered discretionary")
        }
    }

    func test_viceCategories_areMarkedRegret() {
        XCTAssertEqual(CategoryClassifier.bucket(forCategoryName: "Alcohol"), .regret)
    }

    func test_caseInsensitive() {
        XCTAssertEqual(CategoryClassifier.bucket(forCategoryName: "RENT"), .necessary)
        XCTAssertEqual(CategoryClassifier.bucket(forCategoryName: "dining"), .discretionary)
    }

    func test_unknownCategory_defaultsToDiscretionary() {
        // Safer to under-mark "necessary" than over-mark — unknowns become
        // candidates for cutting in budgeting suggestions.
        XCTAssertEqual(CategoryClassifier.bucket(forCategoryName: "Crypto Mining"),
                       .discretionary)
    }

    func test_emptyAndNilCategoryName_defaultsToDiscretionary() {
        XCTAssertEqual(CategoryClassifier.bucket(forCategoryName: nil), .discretionary)
        XCTAssertEqual(CategoryClassifier.bucket(forCategoryName: ""),  .discretionary)
        XCTAssertEqual(CategoryClassifier.bucket(forCategoryName: "   "), .discretionary)
    }

    func test_incomeCategories_returnNil() {
        for name in ["Salary", "Freelance", "Investment Returns", "Refund",
                     "Gift Received", "Interest", "Other Income"] {
            XCTAssertNil(CategoryClassifier.bucket(forCategoryName: name),
                         "\(name) is income and shouldn't be bucketed")
        }
    }
}
