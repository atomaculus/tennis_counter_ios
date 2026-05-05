import XCTest

@MainActor
final class MatchHistoryStoreTests: XCTestCase {
    func testUpsertReplacesMatchingIdempotencyKey() {
        let store = MatchHistoryStore(storageURL: temporaryStorageURL())
        let first = makeRecord(idempotencyKey: "same-key", score: "6-3")
        let replacement = makeRecord(idempotencyKey: "same-key", score: "6-4")

        store.upsert(first)
        store.upsert(replacement)

        XCTAssertEqual(store.matches.count, 1)
        XCTAssertEqual(store.matches.first?.finalScoreText, "6-4")
    }

    func testPersistsVersionedArchiveAndReloadsMatches() throws {
        let url = temporaryStorageURL()
        let store = MatchHistoryStore(storageURL: url)
        let record = makeRecord(idempotencyKey: "archive-key", score: "7-6")

        store.upsert(record)

        let data = try Data(contentsOf: url)
        let archive = try JSONDecoder().decode(MatchHistoryArchive.self, from: data)
        XCTAssertEqual(archive.version, 1)
        XCTAssertEqual(archive.matches.first?.idempotencyKey, "archive-key")

        let reloaded = MatchHistoryStore(storageURL: url)
        XCTAssertEqual(reloaded.matches.first?.idempotencyKey, "archive-key")
    }

    func testLoadsLegacyArrayAndMigratesToVersionedArchive() throws {
        let url = temporaryStorageURL()
        let legacy = [makeRecord(idempotencyKey: "legacy-key", score: "6-0")]
        let legacyData = try JSONEncoder().encode(legacy)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try legacyData.write(to: url, options: .atomic)

        let store = MatchHistoryStore(storageURL: url)

        XCTAssertEqual(store.matches.first?.idempotencyKey, "legacy-key")
        let migratedData = try Data(contentsOf: url)
        let archive = try JSONDecoder().decode(MatchHistoryArchive.self, from: migratedData)
        XCTAssertEqual(archive.version, 1)
    }

    func testAttachAndRemovePhotoData() throws {
        let store = MatchHistoryStore(storageURL: temporaryStorageURL())
        let record = makeRecord(idempotencyKey: "photo-key", score: "6-2")
        let photoData = Data([0x01, 0x02, 0x03])

        store.upsert(record)
        try store.attachPhotoData(photoData, fileExtension: "jpg", to: record)

        guard let updated = store.matches.first,
              let photoURL = store.photoURL(for: updated) else {
            return XCTFail("Expected attached photo URL")
        }
        XCTAssertEqual(try Data(contentsOf: photoURL), photoData)

        store.updatePhotoBookmark(nil, for: updated)

        XCTAssertNil(store.matches.first?.photoBookmark)
        XCTAssertFalse(FileManager.default.fileExists(atPath: photoURL.path))
    }

    private func temporaryStorageURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("matches.json")
    }

    private func makeRecord(idempotencyKey: String, score: String) -> FinishedMatchRecord {
        FinishedMatchRecord(
            createdAt: Date(),
            durationSeconds: 3600,
            finalScoreText: score,
            setScoresText: "6-3",
            detailText: "Player A vs Player B | Sets 6-3",
            photoBookmark: nil,
            source: "test",
            idempotencyKey: idempotencyKey
        )
    }
}
