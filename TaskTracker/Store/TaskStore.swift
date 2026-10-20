import Combine
import Foundation

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var activeTasks: [TaskItem] = []
    @Published private(set) var archivedDays: [ArchivedDay] = []
    @Published var errorMessage: String?

    private struct PersistedState: Codable {
        var version: Int
        var activeTasks: [TaskItem]
        var archivedDays: [ArchivedDay]
        var lastDailyResetDate: Date
    }

    private let storageURL: URL
    private var lastDailyResetDate: Date
    private var calendar: Calendar
    private var hasLoadFailure = false
    private var midnightTimer: Timer?

    var dailyTasks: [TaskItem] {
        activeTasks
            .filter { $0.area == .daily }
            .sorted(by: taskSort)
    }

    var longTermTasks: [TaskItem] {
        activeTasks
            .filter { $0.area == .longTerm }
            .sorted(by: taskSort)
    }

    init(
        storageURL: URL? = nil,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.calendar = calendar
        self.lastDailyResetDate = calendar.startOfDay(for: now)

        if let storageURL {
            self.storageURL = storageURL
        } else {
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory
            let directory = applicationSupport.appendingPathComponent("TaskTracker", isDirectory: true)
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            self.storageURL = directory.appendingPathComponent("task-data.json")
        }

        load()
        refreshDailyTasksIfNeeded(now: now)
    }

    func addTask(
        title: String,
        description: String,
        importance: Importance,
        urgency: Urgency,
        area: TaskArea,
        now: Date = .now
    ) {
        refreshDailyTasksIfNeeded(now: now)
        let task = TaskItem(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            taskDescription: description.trimmingCharacters(in: .whitespacesAndNewlines),
            importance: importance,
            urgency: urgency,
            area: area,
            createdAt: now,
            updatedAt: now
        )
        activeTasks.append(task)
        persist()
    }

    func updateTask(
        _ task: TaskItem,
        title: String,
        description: String,
        importance: Importance,
        urgency: Urgency,
        area: TaskArea,
        now: Date = .now
    ) {
        guard let index = activeTasks.firstIndex(where: { $0.id == task.id }) else { return }
        activeTasks[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        activeTasks[index].taskDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        activeTasks[index].importance = importance
        activeTasks[index].urgency = urgency
        activeTasks[index].area = area
        activeTasks[index].updatedAt = now
        persist()
    }

    func deleteTask(_ task: TaskItem) {
        activeTasks.removeAll { $0.id == task.id }
        persist()
    }

    func togglePin(_ task: TaskItem) {
        guard let index = activeTasks.firstIndex(where: { $0.id == task.id }) else { return }
        activeTasks[index].isPinned.toggle()
        persist()
    }

    func refreshDailyTasksIfNeeded(now: Date = .now) {
        let today = calendar.startOfDay(for: now)
        let lastResetDay = calendar.startOfDay(for: lastDailyResetDate)
        guard today > lastResetDay else { return }

        let tasksToArchive = activeTasks.filter { $0.area == .daily }
        if !tasksToArchive.isEmpty {
            mergeIntoArchive(tasksToArchive, on: lastResetDay)
            activeTasks.removeAll { $0.area == .daily }
        }

        lastDailyResetDate = today
        persist()
    }

    func startAutomaticDailyRefresh() {
        refreshDailyTasksIfNeeded()
        scheduleMidnightRefresh()
    }

    func stopAutomaticDailyRefresh() {
        midnightTimer?.invalidate()
        midnightTimer = nil
    }

    func deleteArchive(_ scope: ArchiveScope) {
        archivedDays.removeAll { archivedDay in
            matches(archivedDay.date, scope: scope)
        }
        persist()
    }

    func tasks(in scope: ArchiveScope) -> [ArchivedDay] {
        archivedDays
            .filter { matches($0.date, scope: scope) }
            .sorted { $0.date < $1.date }
    }

    func csv(in scope: ArchiveScope) -> String {
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = calendar
        dayFormatter.locale = Locale(identifier: "zh_CN")
        dayFormatter.dateFormat = "yyyy-MM-dd"

        var rows = ["日期,标题,描述,重要性,紧急性,创建时间,更新时间"]
        let timestampFormatter = ISO8601DateFormatter()

        for day in tasks(in: scope) {
            for task in day.tasks {
                rows.append([
                    dayFormatter.string(from: day.date),
                    task.title,
                    task.taskDescription,
                    task.importance.title,
                    task.urgency.title,
                    timestampFormatter.string(from: task.createdAt),
                    timestampFormatter.string(from: task.updatedAt)
                ].map(csvField).joined(separator: ","))
            }
        }

        return "\u{FEFF}" + rows.joined(separator: "\n")
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }

        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let state = try decoder.decode(PersistedState.self, from: data)
            activeTasks = state.activeTasks
            archivedDays = state.archivedDays
            lastDailyResetDate = state.lastDailyResetDate
        } catch {
            hasLoadFailure = true
            errorMessage = "本地数据暂时无法读取。原文件会保留，不会被覆盖。"
        }
    }

    private func persist() {
        guard !hasLoadFailure else { return }

        do {
            let state = PersistedState(
                version: 2,
                activeTasks: activeTasks,
                archivedDays: archivedDays,
                lastDailyResetDate: lastDailyResetDate
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(state)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            errorMessage = "保存失败，请确认设备仍有可用空间后重试。"
        }
    }

    private func mergeIntoArchive(_ tasks: [TaskItem], on date: Date) {
        if let index = archivedDays.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
            let existingIDs = Set(archivedDays[index].tasks.map(\.id))
            archivedDays[index].tasks.append(contentsOf: tasks.filter { !existingIDs.contains($0.id) })
        } else {
            archivedDays.append(ArchivedDay(date: date, tasks: tasks))
        }
        archivedDays.sort { $0.date > $1.date }
    }

    private func matches(_ date: Date, scope: ArchiveScope) -> Bool {
        let components = calendar.dateComponents([.year, .month, .weekOfYear], from: date)
        switch scope {
        case let .month(year, month):
            return components.year == year && components.month == month
        case let .week(year, month, weekOfYear):
            return components.year == year
                && components.month == month
                && components.weekOfYear == weekOfYear
        case let .day(targetDate):
            return calendar.isDate(date, inSameDayAs: targetDate)
        }
    }

    private func taskSort(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
        let importanceOrder: [Importance: Int] = [.high: 0, .medium: 1, .low: 2]
        let urgencyOrder: [Urgency: Int] = [.immediate: 0, .urgent: 1, .relaxed: 2]
        let leftRank = (
            importanceOrder[lhs.importance, default: 3],
            urgencyOrder[lhs.urgency, default: 3]
        )
        let rightRank = (
            importanceOrder[rhs.importance, default: 3],
            urgencyOrder[rhs.urgency, default: 3]
        )
        if leftRank.0 != rightRank.0 { return leftRank.0 < rightRank.0 }
        if leftRank.1 != rightRank.1 { return leftRank.1 < rightRank.1 }
        return lhs.createdAt < rhs.createdAt
    }

    private func csvField(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private func scheduleMidnightRefresh() {
        midnightTimer?.invalidate()

        let now = Date()
        let today = calendar.startOfDay(for: now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return }
        let interval = max(tomorrow.timeIntervalSince(now) + 0.1, 1)
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.startAutomaticDailyRefresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        midnightTimer = timer
    }
}
