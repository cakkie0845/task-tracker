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

    func testDailyTasksWaitUntilFourInTheMorning() throws {
        let firstDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 9)))
        let afterMidnight = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 0, minute: 1)))
        let beforeFour = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 3, minute: 59)))
        let four = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 4)))
        let store = TaskStore(storageURL: storageURL, now: firstDay, calendar: calendar)
        store.addTask(title: "凌晨仍显示", description: "", importance: .medium, urgency: .urgent, area: .daily, now: firstDay)

        store.refreshDailyTasksIfNeeded(now: afterMidnight)
        store.refreshDailyTasksIfNeeded(now: beforeFour)
        XCTAssertEqual(store.dailyTasks.map(\.title), ["凌晨仍显示"])
        XCTAssertTrue(store.archivedDays.isEmpty)

        store.refreshDailyTasksIfNeeded(now: four)
        XCTAssertTrue(store.dailyTasks.isEmpty)
        XCTAssertEqual(store.archivedDays.first?.tasks.map(\.title), ["凌晨仍显示"])
        XCTAssertTrue(calendar.isDate(store.archivedDays[0].date, inSameDayAs: firstDay))
    }

    func testTaskCreatedBeforeFourBelongsToPreviousDailyCycle() throws {
        let two = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 2)))
        let four = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 4)))
        let previousDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19)))
        let store = TaskStore(storageURL: storageURL, now: two, calendar: calendar)
        store.addTask(title: "夜间任务", description: "", importance: .medium, urgency: .relaxed, area: .daily, now: two)

        store.refreshDailyTasksIfNeeded(now: four)

        XCTAssertTrue(store.dailyTasks.isEmpty)
        XCTAssertTrue(calendar.isDate(store.archivedDays[0].date, inSameDayAs: previousDay))
    }

    func testExistingMidnightResetDateMigratesWithoutEarlyArchive() throws {
        let two = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 2)))
        let three = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 3)))
        let threeThirty = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 3, minute: 30)))
        let four = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 4)))
        let midnight = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 20)))
        let oldStore = TaskStore(storageURL: storageURL, now: two, calendar: calendar)
        oldStore.addTask(title: "升级前任务", description: "", importance: .medium, urgency: .relaxed, area: .daily, now: two)

        let data = try Data(contentsOf: storageURL)
        var state = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        state["version"] = 3
        state["lastDailyResetDate"] = ISO8601DateFormatter().string(from: midnight)
        try JSONSerialization.data(withJSONObject: state).write(to: storageURL, options: .atomic)

        let upgradedStore = TaskStore(storageURL: storageURL, now: three, calendar: calendar)
        XCTAssertEqual(upgradedStore.dailyTasks.map(\.title), ["升级前任务"])
        XCTAssertTrue(upgradedStore.archivedDays.isEmpty)

        let reopenedStore = TaskStore(storageURL: storageURL, now: threeThirty, calendar: calendar)
        XCTAssertEqual(reopenedStore.dailyTasks.map(\.title), ["升级前任务"])
        reopenedStore.refreshDailyTasksIfNeeded(now: four)
        XCTAssertTrue(reopenedStore.dailyTasks.isEmpty)
        XCTAssertEqual(reopenedStore.archivedDays.first?.tasks.map(\.title), ["升级前任务"])
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

    func testArchivedDailyTaskCanBeExportedAndDeletedIndividually() throws {
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 9)))
        let nextDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 4)))
        let store = TaskStore(storageURL: storageURL, now: day, calendar: calendar)
        store.addTask(title: "单项导出", description: "", importance: .high, urgency: .urgent, area: .daily, now: day)
        store.addTask(title: "另一项", description: "", importance: .low, urgency: .relaxed, area: .daily, now: day)
        store.refreshDailyTasksIfNeeded(now: nextDay)

        let archivedDay = try XCTUnwrap(store.archivedDays.first)
        let selected = try XCTUnwrap(archivedDay.tasks.first { $0.title == "单项导出" })
        let csv = store.csvForArchivedDailyTask(selected, on: archivedDay.date)
        XCTAssertTrue(csv.contains("单项导出"))
        XCTAssertFalse(csv.contains("另一项"))

        store.deleteArchivedDailyTask(selected, from: archivedDay)
        XCTAssertEqual(store.archivedDays.first?.tasks.map(\.title), ["另一项"])
        let remaining = try XCTUnwrap(store.archivedDays.first?.tasks.first)
        store.deleteArchivedDailyTask(remaining, from: archivedDay)
        XCTAssertTrue(store.archivedDays.isEmpty)
        XCTAssertTrue(TaskStore(storageURL: storageURL, now: nextDay, calendar: calendar).archivedDays.isEmpty)
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

    func testTaskStateCanToggleAndPersistsAfterReload() throws {
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 9)))
        let store = TaskStore(storageURL: storageURL, now: day, calendar: calendar)
        store.addTask(
            title: "完成测试",
            description: "",
            importance: .medium,
            urgency: .urgent,
            area: .longTerm,
            now: day
        )

        let task = try XCTUnwrap(store.longTermTasks.first)
        XCTAssertEqual(task.state, .unaccomplished)

        store.toggleState(task, now: day)

        XCTAssertEqual(store.longTermTasks.first?.state, .accomplished)
        let reloaded = TaskStore(storageURL: storageURL, now: day, calendar: calendar)
        XCTAssertEqual(reloaded.longTermTasks.first?.state, .accomplished)
    }

    func testLongTermDeadlinePersistsFormatsAndCanBeCleared() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 9)))
        let deadline = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 17, minute: 30)))
        let store = TaskStore(storageURL: storageURL, now: now, calendar: calendar)
        store.addTask(
            title: "提交项目",
            description: "",
            importance: .high,
            urgency: .urgent,
            area: .longTerm,
            deadline: deadline,
            now: now
        )

        let task = try XCTUnwrap(store.longTermTasks.first)
        XCTAssertEqual(task.deadline, deadline)
        XCTAssertEqual(
            TaskDeadlineFormatter.string(from: deadline, calendar: calendar),
            "2026年10月22日，周四，17:30"
        )
        XCTAssertEqual(TaskStore(storageURL: storageURL, now: now, calendar: calendar).longTermTasks.first?.deadline, deadline)

        store.moveTask(task, to: .daily, now: now)
        XCTAssertEqual(store.dailyTasks.first?.deadline, deadline)
        XCTAssertEqual(store.dailyTasks.first?.dailyDeadlineTime?.displayString, "17:30")
        let movedTask = try XCTUnwrap(store.dailyTasks.first)
        store.moveTask(movedTask, to: .longTerm, now: now)

        let returnedTask = try XCTUnwrap(store.longTermTasks.first)
        store.updateTask(
            returnedTask,
            title: returnedTask.title,
            description: returnedTask.taskDescription,
            importance: returnedTask.importance,
            urgency: returnedTask.urgency,
            area: .longTerm,
            deadline: nil,
            now: now
        )
        XCTAssertNil(store.longTermTasks.first?.deadline)
        XCTAssertNil(TaskStore(storageURL: storageURL, now: now, calendar: calendar).longTermTasks.first?.deadline)
    }

    func testDailyDeadlineUsesOnlyTimeAndPersistsThroughEditAndArchive() throws {
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 9)))
        let nextMorning = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 4)))
        let store = TaskStore(storageURL: storageURL, now: day, calendar: calendar)
        store.addTask(
            title: "傍晚锻炼",
            description: "",
            importance: .medium,
            urgency: .urgent,
            area: .daily,
            dailyDeadlineTime: DailyDeadlineTime(hour: 17, minute: 30),
            now: day
        )

        let created = try XCTUnwrap(store.dailyTasks.first)
        XCTAssertNil(created.deadline)
        XCTAssertEqual(created.dailyDeadlineTime?.displayString, "17:30")
        XCTAssertEqual(
            TaskStore(storageURL: storageURL, now: day, calendar: calendar).dailyTasks.first?.dailyDeadlineTime,
            DailyDeadlineTime(hour: 17, minute: 30)
        )

        store.updateTask(
            created,
            title: created.title,
            description: created.taskDescription,
            importance: created.importance,
            urgency: created.urgency,
            area: .daily,
            dailyDeadlineTime: DailyDeadlineTime(hour: 18, minute: 5),
            now: day
        )
        XCTAssertEqual(store.dailyTasks.first?.dailyDeadlineTime?.displayString, "18:05")

        store.refreshDailyTasksIfNeeded(now: nextMorning)
        XCTAssertEqual(store.archivedDays.first?.tasks.first?.dailyDeadlineTime?.displayString, "18:05")
        let csv = store.csv(in: .day(day))
        XCTAssertTrue(csv.contains("\"18:05\""))
        XCTAssertFalse(csv.contains("2026年10月21日"))
    }

    func testDailyDeadlineCanBeClearedWithoutRemovingLongTermDate() throws {
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 9)))
        let deadline = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 12)))
        let store = TaskStore(storageURL: storageURL, now: day, calendar: calendar)
        store.addTask(title: "跨区域任务", description: "", importance: .high, urgency: .urgent,
                      area: .longTerm, deadline: deadline, now: day)

        let longTerm = try XCTUnwrap(store.longTermTasks.first)
        store.moveTask(longTerm, to: .daily, now: day)
        let daily = try XCTUnwrap(store.dailyTasks.first)
        XCTAssertEqual(daily.dailyDeadlineTime?.displayString, "12:00")
        store.updateTask(daily, title: daily.title, description: daily.taskDescription,
                         importance: daily.importance, urgency: daily.urgency,
                         area: .daily, deadline: daily.deadline, dailyDeadlineTime: nil, now: day)
        XCTAssertNil(store.dailyTasks.first?.dailyDeadlineTime)
        XCTAssertEqual(store.dailyTasks.first?.deadline, deadline)
        XCTAssertNil(TaskStore(storageURL: storageURL, now: day, calendar: calendar).dailyTasks.first?.dailyDeadlineTime)

        let clearedDaily = try XCTUnwrap(store.dailyTasks.first)
        store.moveTask(clearedDaily, to: .longTerm, now: day)
        XCTAssertEqual(store.longTermTasks.first?.deadline, deadline)
    }

    func testArchivingLongTermTasksOnlyMovesAccomplishedTasks() throws {
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 9)))
        let store = TaskStore(storageURL: storageURL, now: day, calendar: calendar)
        store.addTask(title: "已完成长期", description: "", importance: .high, urgency: .urgent, area: .longTerm, now: day)
        store.addTask(title: "未完成长期", description: "", importance: .low, urgency: .relaxed, area: .longTerm, now: day)

        let completed = try XCTUnwrap(store.longTermTasks.first { $0.title == "已完成长期" })
        store.toggleState(completed, now: day)
        store.archiveAccomplishedLongTermTasks(now: day)

        XCTAssertEqual(store.longTermTasks.map(\.title), ["未完成长期"])
        XCTAssertEqual(store.archivedLongTermTasks.map(\.title), ["已完成长期"])
        XCTAssertEqual(store.archivedLongTermTasks.first?.state, .accomplished)

        let reloaded = TaskStore(storageURL: storageURL, now: day, calendar: calendar)
        XCTAssertEqual(reloaded.longTermTasks.map(\.title), ["未完成长期"])
        XCTAssertEqual(reloaded.archivedLongTermTasks.map(\.title), ["已完成长期"])
    }

    func testArchivedLongTermTasksCanExportAndDelete() throws {
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 9)))
        let store = TaskStore(storageURL: storageURL, now: day, calendar: calendar)
        store.addTask(title: "导出这一项", description: "", importance: .high, urgency: .urgent, area: .longTerm, now: day)
        store.addTask(title: "保留另一项", description: "", importance: .low, urgency: .relaxed, area: .longTerm, now: day)
        for task in store.longTermTasks {
            store.toggleState(task, now: day)
        }
        store.archiveAccomplishedLongTermTasks(now: day)

        let selected = try XCTUnwrap(store.archivedLongTermTasks.first { $0.title == "导出这一项" })
        let csv = store.csvForArchivedLongTermTasks([selected])
        XCTAssertTrue(csv.contains("导出这一项"))
        XCTAssertFalse(csv.contains("保留另一项"))
        XCTAssertTrue(csv.contains("已完成"))

        store.deleteArchivedLongTermTask(selected)
        XCTAssertEqual(store.archivedLongTermTasks.map(\.title), ["保留另一项"])
        store.deleteAllArchivedLongTermTasks()
        XCTAssertTrue(store.archivedLongTermTasks.isEmpty)
        XCTAssertTrue(TaskStore(storageURL: storageURL, now: day, calendar: calendar).archivedLongTermTasks.isEmpty)
    }

    func testLongTermTasksMovedToDailyArchiveWhenDoneAndReturnWhenUndone() throws {
        let firstDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 9)))
        let nextDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: firstDay))
        let store = TaskStore(storageURL: storageURL, now: firstDay, calendar: calendar)
        store.addTask(title: "完成后归档", description: "", importance: .high, urgency: .urgent, area: .longTerm, now: firstDay)
        store.addTask(title: "未完成则返回", description: "", importance: .medium, urgency: .relaxed, area: .longTerm, now: firstDay)

        let completed = try XCTUnwrap(store.longTermTasks.first { $0.title == "完成后归档" })
        let uncompleted = try XCTUnwrap(store.longTermTasks.first { $0.title == "未完成则返回" })
        store.toggleState(completed, now: firstDay)
        store.moveTask(completed, to: .daily, now: firstDay)
        store.moveTask(uncompleted, to: .daily, now: firstDay)

        store.refreshDailyTasksIfNeeded(now: nextDay)

        XCTAssertTrue(store.dailyTasks.isEmpty)
        XCTAssertEqual(store.longTermTasks.map(\.title), ["未完成则返回"])
        XCTAssertFalse(store.longTermTasks[0].returnsToLongTermIfUnaccomplished)
        XCTAssertEqual(store.archivedDays.first?.tasks.map(\.title), ["完成后归档"])
        XCTAssertEqual(store.archivedDays.first?.tasks.first?.state, .accomplished)
    }

    func testExistingTaskDataWithoutPinFieldStillLoads() throws {
        let task = TaskItem(title: "旧任务", area: .longTerm)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(task)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "isPinned")
        object.removeValue(forKey: "state")
        object.removeValue(forKey: "returnsToLongTermIfUnaccomplished")
        object.removeValue(forKey: "deadline")
        let oldData = try JSONSerialization.data(withJSONObject: object)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TaskItem.self, from: oldData)

        XCTAssertEqual(decoded.title, "旧任务")
        XCTAssertFalse(decoded.isPinned)
        XCTAssertEqual(decoded.state, .unaccomplished)
        XCTAssertFalse(decoded.returnsToLongTermIfUnaccomplished)
        XCTAssertNil(decoded.deadline)
    }
}
