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

        let csv = store.csv(in: .day(firstDay))
        try expect(csv.contains("每日任务"), "CSV 没有包含归档任务")
        try expect(csv.contains("高度重要"), "CSV 没有包含任务属性")

        store.deleteArchive(.month(year: 2026, month: 10))
        try expect(store.archivedDays.isEmpty, "月份范围删除失败")

        let reloadedStore = TaskStore(storageURL: storageURL, now: nextDay, calendar: calendar)
        try expect(reloadedStore.longTermTasks.count == 1, "本地持久化后长期任务丢失")

        print("TaskStore smoke tests passed")
    }

    private static func requireDate(_ date: Date?) throws -> Date {
        guard let date else { throw SmokeTestError("无法创建测试日期") }
        return date
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
