import XCTest
@testable import TaskTracker

@MainActor
final class WatchLaterTests: XCTestCase {
    private var storageURL: URL!

    override func setUp() {
        super.setUp()
        storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WatchLaterTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("watch-later.json")
    }

    override func tearDown() {
        if let storageURL {
            try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent())
        }
        super.tearDown()
    }

    func testLocalItemsSortByAddedTimeAndKeepStatusesAfterReload() {
        let store = WatchLaterStore(storageURL: storageURL)
        let earlier = Date(timeIntervalSince1970: 100)
        let later = Date(timeIntervalSince1970: 200)
        XCTAssertTrue(store.add(makeItem(id: 101, category: .comics, addedAt: earlier)))
        XCTAssertTrue(store.add(makeItem(id: 202, category: .comics, addedAt: later)))
        XCTAssertFalse(store.add(makeItem(id: 101, category: .comics, addedAt: later)))
        store.setStatus(.inProgress, for: 101)

        let reloaded = WatchLaterStore(storageURL: storageURL)
        XCTAssertEqual(reloaded.items(in: .comics).map(\.subjectID), [202, 101])
        XCTAssertEqual(reloaded.item(for: 101)?.status, .inProgress)
        XCTAssertEqual(WatchStatus.inProgress.title(for: .comics), "在读")
        XCTAssertEqual(WatchStatus.inProgress.title(for: .game), "在玩")

        reloaded.remove(202)
        XCTAssertEqual(WatchLaterStore(storageURL: storageURL).items(in: .comics).map(\.subjectID), [101])
    }

    func testVersionOneFileLoadsWithoutLosingExistingItems() throws {
        try FileManager.default.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let legacy = Data(#"""
        {"version":1,"items":[{
            "subjectID":42,"category":"game","originalTitle":"旧游戏","chineseTitle":"",
            "summary":"简介","credits":"开发商","addedAt":"2020-01-01T00:00:00Z",
            "status":"finished"
        }]}
        """#.utf8)
        try legacy.write(to: storageURL)

        let store = WatchLaterStore(storageURL: storageURL)
        let item = try XCTUnwrap(store.item(for: 42))
        XCTAssertEqual(item.status, .finished)
        XCTAssertEqual(item.rating, 0)
        XCTAssertEqual(item.comment, "")
        XCTAssertEqual(item.tags, [])
        XCTAssertEqual(item.episodeProgress, 0)
        XCTAssertEqual(item.volumeProgress, 0)
        XCTAssertFalse(item.isPrivate)
        XCTAssertEqual(item.localUpdatedAt, item.addedAt)
        XCTAssertNil(item.bangumiUpdatedAt)

        XCTAssertTrue(store.setStatus(.onHold, for: 42))
        XCTAssertEqual(WatchLaterStore(storageURL: storageURL).item(for: 42)?.status, .onHold)
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: storageURL)) as? [String: Any]
        XCTAssertEqual(saved?["version"] as? Int, 2)
    }

    func testCollectionDetailsPersistAndMapToBangumiPayload() throws {
        let store = WatchLaterStore(storageURL: storageURL)
        XCTAssertTrue(store.add(makeItem(id: 201, category: .game, addedAt: .now)))
        XCTAssertTrue(store.setStatus(.dropped, for: 201))

        var details = WatchCollectionDetails(item: try XCTUnwrap(store.item(for: 201)))
        details.rating = 8
        details.comment = "值得一玩"
        details.tags = ["RPG", "独立游戏"]
        details.isPrivate = true
        XCTAssertTrue(store.updateCollection(details, for: 201))

        let reloaded = WatchLaterStore(storageURL: storageURL)
        let item = try XCTUnwrap(reloaded.item(for: 201))
        XCTAssertEqual(item.status, .dropped)
        XCTAssertEqual(item.rating, 8)
        XCTAssertEqual(item.comment, "值得一玩")
        XCTAssertEqual(item.tags, ["RPG", "独立游戏"])
        XCTAssertTrue(item.isPrivate)
        XCTAssertEqual(item.bangumiCollectionPayload.type, 5)

        let payload = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(item.bangumiCollectionPayload)
        ) as? [String: Any])
        XCTAssertEqual(payload["type"] as? Int, 5)
        XCTAssertEqual(payload["rate"] as? Int, 8)
        XCTAssertEqual(payload["comment"] as? String, "值得一玩")
        XCTAssertEqual(payload["tags"] as? [String], ["RPG", "独立游戏"])
        XCTAssertEqual(payload["private"] as? Bool, true)
        XCTAssertNil(payload["ep_status"])
        XCTAssertNil(payload["vol_status"])

        XCTAssertTrue(store.add(makeItem(id: 202, category: .comics, addedAt: .now)))
        var bookDetails = WatchCollectionDetails(item: try XCTUnwrap(store.item(for: 202)))
        bookDetails.episodeProgress = 12
        bookDetails.volumeProgress = 3
        XCTAssertTrue(store.updateCollection(bookDetails, for: 202))
        let book = try XCTUnwrap(store.item(for: 202))
        let bookPayload = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(book.bangumiCollectionPayload)
        ) as? [String: Any])
        XCTAssertEqual(bookPayload["ep_status"] as? Int, 12)
        XCTAssertEqual(bookPayload["vol_status"] as? Int, 3)
    }

    func testCollectionValidationKeepsPreviousValues() throws {
        let store = WatchLaterStore(storageURL: storageURL)
        XCTAssertTrue(store.add(makeItem(id: 301, category: .anime, addedAt: .now)))
        var details = WatchCollectionDetails(item: try XCTUnwrap(store.item(for: 301)))
        details.rating = 11
        XCTAssertFalse(store.updateCollection(details, for: 301))
        XCTAssertEqual(store.item(for: 301)?.rating, 0)
        details.rating = 10
        details.tags = ["有 空格"]
        XCTAssertFalse(store.updateCollection(details, for: 301))
        XCTAssertEqual(store.item(for: 301)?.tags, [])
    }

    func testAllStatusesHaveBangumiCollectionTypes() {
        XCTAssertEqual(WatchStatus.allCases.map(\.bangumiType), [1, 3, 2, 4, 5])
        XCTAssertEqual(WatchStatus.onHold.title(for: .game), "搁置")
        XCTAssertEqual(WatchStatus.dropped.title(for: .comics), "抛弃")
    }

    func testCorruptLocalFileIsPreserved() throws {
        try FileManager.default.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let original = Data("not valid JSON".utf8)
        try original.write(to: storageURL)
        let store = WatchLaterStore(storageURL: storageURL)

        XCTAssertNotNil(store.errorMessage)
        XCTAssertFalse(store.add(makeItem(id: 1, category: .anime, addedAt: .now)))
        XCTAssertEqual(try Data(contentsOf: storageURL), original)
    }

    func testBangumiBookResponseMapsToComicsMetadata() throws {
        let data = Data(#"""
        {
            "id": 42,
            "type": 1,
            "name": "Original title",
            "name_cn": "中文名",
            "summary": "作品简介",
            "platform": "漫画",
            "images": {"large": "https://lain.bgm.tv/pic/cover/example.jpg"},
            "infobox": [
                {"key": "作者", "value": [{"v": "作者甲"}, {"v": "作者乙"}]},
                {"key": "出版社", "value": "出版社甲"}
            ]
        }
        """#.utf8)
        let subject = try JSONDecoder().decode(BangumiSubject.self, from: data)

        XCTAssertEqual(subject.title, "中文名")
        XCTAssertEqual(subject.images?.coverURL?.host, "lain.bgm.tv")
        XCTAssertEqual(BangumiClient.credits(from: subject, category: .comics),
                       "作者：作者甲、作者乙 · 出版社：出版社甲")
        XCTAssertEqual(WatchCategory.comics.bangumiType, 1)
    }

    func testSearchKeepsResultsWhenBangumiReturnsEmptyCoverURLs() throws {
        let data = Data(#"""
        {"total":3,"data":[
            {"id":101,"type":2,"name":"有封面的作品","images":{"grid":"https://lain.bgm.tv/cover.jpg"}},
            {"id":102,"type":2,"name":"无封面的作品","images":{"small":"","grid":"","large":"","medium":"","common":""}},
            {"id":103,"type":2,"name":"另一部作品","images":null}
        ]}
        """#.utf8)

        let page = try JSONDecoder().decode(BangumiSearchPage.self, from: data)
        XCTAssertEqual(page.data.map(\.id), [101, 102, 103])
        XCTAssertEqual(page.returnedCount, 3)
        XCTAssertEqual(page.data[0].images?.thumbnailURL?.host, "lain.bgm.tv")
        XCTAssertNil(page.data[1].images?.coverURL)
        XCTAssertNil(page.data[2].images)
    }

    func testOneMalformedSubjectDoesNotBlockSearchOrBreakPagination() throws {
        let data = Data(#"""
        {"total":3,"data":[
            {"id":101,"type":2,"name":"作品一","images":{"grid":""}},
            {"id":"invalid","type":2,"name":"异常作品"},
            {"id":103,"type":2,"name":"作品三"}
        ]}
        """#.utf8)

        let page = try JSONDecoder().decode(BangumiSearchPage.self, from: data)
        XCTAssertEqual(page.data.map(\.id), [101, 103])
        XCTAssertEqual(page.returnedCount, 3)
        XCTAssertEqual(page.total, 3)
    }

    func testCancelledSearchRequestsAreNotReportedAsFailures() {
        XCTAssertTrue(BangumiClient.isCancellation(CancellationError()))
        XCTAssertTrue(BangumiClient.isCancellation(URLError(.cancelled)))
        XCTAssertFalse(BangumiClient.isCancellation(URLError(.notConnectedToInternet)))
    }

    private func makeItem(id: Int, category: WatchCategory, addedAt: Date) -> WatchItem {
        WatchItem(
            subjectID: id,
            category: category,
            originalTitle: "作品 \(id)",
            chineseTitle: "",
            summary: "简介",
            credits: "制作方",
            coverURL: nil,
            addedAt: addedAt,
            status: .planned
        )
    }
}
