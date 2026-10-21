import Foundation

@main
enum TaskStoreSmokeTests {
    @MainActor
    static func main() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TaskTrackerSmoke-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: storageURL) }

        let firstDay = try requireDate(
            calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 9))
        )
        let nextDay = try requireDate(calendar.date(byAdding: .day, value: 1, to: firstDay))
        let store = TaskStore(storageURL: storageURL, now: firstDay, calendar: calendar)

        store.addTask(
            title: "每日任务",
            description: "需要归档",
            importance: .high,
            urgency: .immediate,
            area: .daily,
            now: firstDay
        )
        store.addTask(
            title: "长期任务",
            description: "需要保留",
            importance: .medium,
            urgency: .relaxed,
            area: .longTerm,
            now: firstDay
        )
        store.refreshDailyTasksIfNeeded(now: nextDay)

        try expect(store.dailyTasks.isEmpty, "跨日后每日任务没有清空")
        try expect(store.longTermTasks.count == 1, "跨日后长期任务没有保留")
        try expect(store.archivedDays.first?.tasks.first?.title == "每日任务", "每日任务没有归档")

        let completedLongTerm = try requireTask(store.longTermTasks.first)
        store.toggleState(completedLongTerm, now: nextDay)
        store.archiveAccomplishedLongTermTasks(now: nextDay)
        try expect(store.longTermTasks.isEmpty, "完成的长期任务没有离开活动区")
        try expect(store.archivedLongTermTasks.first?.title == "长期任务", "完成的长期任务没有归档")

        store.addTask(title: "移动后完成", description: "", importance: .high, urgency: .urgent, area: .longTerm, now: nextDay)
        store.addTask(title: "移动后未完成", description: "", importance: .medium, urgency: .relaxed, area: .longTerm, now: nextDay)
        let movedCompleted = try requireTask(store.longTermTasks.first { $0.title == "移动后完成" })
        let movedUncompleted = try requireTask(store.longTermTasks.first { $0.title == "移动后未完成" })
        store.toggleState(movedCompleted, now: nextDay)
        store.moveTask(movedCompleted, to: .daily, now: nextDay)
        store.moveTask(movedUncompleted, to: .daily, now: nextDay)
        let followingDay = try requireDate(calendar.date(byAdding: .day, value: 1, to: nextDay))
        store.refreshDailyTasksIfNeeded(now: followingDay)
        try expect(store.longTermTasks.first?.title == "移动后未完成", "未完成的转入任务没有返回长期区")
        try expect(
            store.archivedDays.flatMap(\.tasks).contains { $0.title == "移动后完成" },
            "已完成的转入任务没有归档到每日任务"
        )

        let csv = store.csv(in: .day(firstDay))
        try expect(csv.contains("每日任务"), "CSV 没有包含归档任务")
        try expect(csv.contains("高度重要"), "CSV 没有包含任务属性")

        store.deleteArchive(.month(year: 2026, month: 10))
        try expect(store.archivedDays.isEmpty, "月份范围删除失败")

        let reloadedStore = TaskStore(storageURL: storageURL, now: followingDay, calendar: calendar)
        try expect(reloadedStore.longTermTasks.count == 1, "本地持久化后长期任务丢失")
        try expect(reloadedStore.archivedLongTermTasks.count == 1, "长期任务归档没有持久化")

        print("TaskStore smoke tests passed")
    }

    private static func requireDate(_ date: Date?) throws -> Date {
        guard let date else { throw SmokeTestError("无法创建测试日期") }
        return date
    }

    private static func requireTask(_ task: TaskItem?) throws -> TaskItem {
        guard let task else { throw SmokeTestError("无法找到测试任务") }
        return task
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw SmokeTestError(message) }
    }
}

private struct SmokeTestError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
