import XCTest

@MainActor
final class TrainingHistoryStoreTests: XCTestCase {
    func testAppendPersistsVersionedArchiveAndReloadsSessions() throws {
        let url = temporaryStorageURL()
        let store = TrainingHistoryStore(storageURL: url)
        let session = makeSession(modality: TrainingSession.Modality.veintiuno, finalCount: 21)

        store.append(session)

        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions.first?.id, session.id)

        let data = try Data(contentsOf: url)
        let archive = try JSONDecoder().decode(TrainingHistoryArchive.self, from: data)
        XCTAssertEqual(archive.version, 1)
        XCTAssertEqual(archive.sessions.first?.id, session.id)

        let reloaded = TrainingHistoryStore(storageURL: url)
        XCTAssertEqual(reloaded.sessions.first?.id, session.id)
        XCTAssertEqual(reloaded.sessions.first?.modality, TrainingSession.Modality.veintiuno)
        XCTAssertEqual(reloaded.sessions.first?.finalCount, 21)
    }

    func testAppendOrdersSessionsNewestFirst() {
        let store = TrainingHistoryStore(storageURL: temporaryStorageURL())
        let older = makeSession(modality: TrainingSession.Modality.paredon, createdAt: Date(timeIntervalSince1970: 1_000))
        let newer = makeSession(modality: TrainingSession.Modality.paredon, createdAt: Date(timeIntervalSince1970: 2_000))

        store.append(older)
        store.append(newer)

        XCTAssertEqual(store.sessions.map(\.id), [newer.id, older.id])
    }

    func testLastModeHidesWallWhenTheStubIsUnavailable() {
        let suite = "playce.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        PlayModePrefs.setLastMode(.veintiuno, defaults: defaults)
        XCTAssertEqual(PlayModePrefs.lastMode(defaults: defaults), .veintiuno)

        PlayModePrefs.setLastMode(.wall, defaults: defaults)
        if PlayMode.isWallStubAvailable {
            XCTAssertEqual(PlayModePrefs.lastMode(defaults: defaults), .wall)
        } else {
            XCTAssertEqual(PlayModePrefs.lastMode(defaults: defaults), .match)
        }
    }

    func testAppendCapsStoredSessionsAtTwoHundred() {
        let store = TrainingHistoryStore(storageURL: temporaryStorageURL())
        for i in 0..<205 {
            store.append(makeSession(
                modality: TrainingSession.Modality.veintiuno,
                createdAt: Date(timeIntervalSince1970: TimeInterval(i))
            ))
        }

        XCTAssertEqual(store.sessions.count, 200)
        // Newest-first ordering means the earliest (oldest) sessions are the
        // ones dropped once the cap is exceeded.
        XCTAssertEqual(store.sessions.last?.createdAt, Date(timeIntervalSince1970: 5))
    }

    private func temporaryStorageURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("trainings.json")
    }

    private func makeSession(
        modality: String,
        createdAt: Date = Date(),
        finalCount: Int = 0
    ) -> TrainingSession {
        TrainingSession(
            modality: modality,
            createdAt: createdAt,
            durationSeconds: 60,
            targetPoints: modality == TrainingSession.Modality.veintiuno ? 21 : 0,
            finalCount: finalCount,
            bestStreak: finalCount,
            attempts: 1
        )
    }
}
