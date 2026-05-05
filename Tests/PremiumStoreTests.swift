import XCTest

@MainActor
final class PremiumStoreTests: XCTestCase {
    func testInitialStateReadsPersistedPremiumAccess() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "playce.premium.unlocked")

        let store = PremiumStore(defaults: defaults)

        XCTAssertTrue(store.isPremiumUnlocked)
        XCTAssertFalse(store.isBillingReady)
        XCTAssertTrue(store.isLoading)
    }

    func testDebugUnlockPersistsPremiumAccessWhenStoreKitProductIsUnavailable() async throws {
        let defaults = makeDefaults()
        let store = PremiumStore(defaults: defaults)

        store.unlockPremium()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(store.isPremiumUnlocked)
        XCTAssertTrue(defaults.bool(forKey: "playce.premium.unlocked"))
        XCTAssertNotNil(store.message)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "playce.tests.premium.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
