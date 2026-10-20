import XCTest
@testable import TaskTracker

@MainActor
final class TaskStoreTests: XCTestCase {
    private var storageURL: URL!
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TaskTrackerTests-\(UUID().uuidString).json")
    }

    override func tearDown() {
        if let storageURL {
            try? FileManager.default.removeItem(at: storageURL)
        }
        super.tearDown()
    }

    func testDailyTasksArchiveAndClearWhenDayChanges() throws {
        let firstDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 9)))
        let nextDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 8)))
        let store = TaskStore(storageURL: storageURL, now: firstDay, calendar: calendar)

        store.addTask(
            title: "完成日报",
            description: "整理今天的进度",
            importance: .high,
            urgency: .immediate,
            area: .daily,
            now: firstDay
        )
        store.addTask(
            title: "学习 SwiftUI",
            description: "长期保持",
            importance: .medium,
            urgency: .relaxed,
            area: .longTerm,
            now: firstDay
        )

        store.refreshDailyTasksIfNeeded(now: nextDay)

        XCTAssertTrue(store.dailyTasks.isEmpty)
        XCTAssertEqual(store.longTermTasks.map(\.title), ["学习 SwiftUI"])
        XCTAssertEqual(store.archivedDays.count, 1)
        XCTAssertEqual(store.archivedDays.first?.tasks.map(\.title), ["完成日报"])
        XCTAssertTrue(calendar.isDate(store.archivedDays[0].date, inSameDayAs: firstDay))
    }

    func testMonthDeletionOnlyRemovesSelectedMonth() throws {
        let january = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 12)))
        let february = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 1, hour: 12)))
        let store = TaskStore(storageURL: storageURL, now: january, calendar: calendar)

        store.addTask(
            title: "一月任务",
            description: "",
            importance: .medium,
            urgency: .urgent,
            area: .daily,
            now: january
        )
        store.refreshDailyTasksIfNeeded(now: february)
        store.addTask(
            title: "二月任务",
            description: "",
            importance: .low,
            urgency: .relaxed,
            area: .daily,
            now: february
        )
        let march = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 12)))
        store.refreshDailyTasksIfNeeded(now: march)

        store.deleteArchive(.month(year: 2026, month: 1))

        XCTAssertEqual(store.archivedDays.count, 1)
        XCTAssertEqual(store.archivedDays.first?.tasks.first?.title, "二月任务")
    }

    func testCSVExportEscapesQuotesAndKeepsChineseText() throws {
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 9)))
        let nextDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: day))
        let store = TaskStore(storageURL: storageURL, now: day, calendar: calendar)
        store.addTask(
            title: "写“总结”",
            description: "第一行, 第二列",
            importance: .high,
            urgency: .urgent,
            area: .daily,
            now: day
        )
        store.refreshDailyTasksIfNeeded(now: nextDay)

        let csv = store.csv(in: .day(day))

        XCTAssertTrue(csv.hasPrefix("\u{FEFF}"))
        XCTAssertTrue(csv.contains("写“总结”"))
        XCTAssertTrue(csv.contains("\"第一行, 第二列\""))
        XCTAssertTrue(csv.contains("高度重要"))
    }

    func testMultiplePinnedTasksStayAtTopOfTheirOwnAreaAfterReload() throws {
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 9)))
        let store = TaskStore(storageURL: storageURL, now: day, calendar: calendar)

        store.addTask(title: "每日普通", description: "", importance: .high, urgency: .immediate, area: .daily, now: day)
        for number in 1...5 {
            store.addTask(
                title: "每日置顶\(number)",
                description: "",
                importance: .low,
                urgency: .relaxed,
                area: .daily,
                now: day
            )
        }
        store.addTask(title: "长期普通", description: "", importance: .high, urgency: .immediate, area: .longTerm, now: day)
        store.addTask(title: "长期置顶", description: "", importance: .low, urgency: .relaxed, area: .longTerm, now: day)

        for task in store.dailyTasks.filter({ $0.title.hasPrefix("每日置顶") }) {
            store.togglePin(task)
        }
        let longTermPinned = try XCTUnwrap(store.longTermTasks.first { $0.title == "长期置顶" })
        store.togglePin(longTermPinned)

        XCTAssertEqual(store.dailyTasks.prefix(5).filter(\.isPinned).count, 5)
        XCTAssertEqual(store.dailyTasks.last?.title, "每日普通")
        XCTAssertEqual(store.longTermTasks.first?.title, "长期置顶")

        let reloaded = TaskStore(storageURL: storageURL, now: day, calendar: calendar)
        XCTAssertEqual(reloaded.dailyTasks.prefix(5).filter(\.isPinned).count, 5)
        XCTAssertEqual(reloaded.longTermTasks.first?.title, "长期置顶")
    }

    func testExistingTaskDataWithoutPinFieldStillLoads() throws {
        let task = TaskItem(title: "旧任务", area: .longTerm)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(task)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "isPinned")
        let oldData = try JSONSerialization.data(withJSONObject: object)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TaskItem.self, from: oldData)

        XCTAssertEqual(decoded.title, "旧任务")
        XCTAssertFalse(decoded.isPinned)
    }
}
