import Combine
import Foundation

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var activeTasks: [TaskItem] = []
    @Published private(set) var archivedDays: [ArchivedDay] = []
    @Published private(set) var archivedLongTermTasks: [TaskItem] = []
    @Published var errorMessage: String?

    private struct PersistedState: Codable {
        var version: Int
        var activeTasks: [TaskItem]
        var archivedDays: [ArchivedDay]
        var archivedLongTermTasks: [TaskItem]?
        var lastDailyResetDate: Date
    }

    private let storageURL: URL
    private var lastDailyResetDate: Date
    private var calendar: Calendar
    private var hasLoadFailure = false
    private var dailyRefreshTimer: Timer?

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
        self.lastDailyResetDate = Self.dailyCycleStart(for: now, calendar: calendar)

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

        load(now: now)
        refreshDailyTasksIfNeeded(now: now)
    }

    func addTask(
        title: String,
        description: String,
        importance: Importance,
        urgency: Urgency,
        area: TaskArea,
        deadline: Date? = nil,
        dailyDeadlineTime: DailyDeadlineTime? = nil,
        now: Date = .now
    ) {
        refreshDailyTasksIfNeeded(now: now)
        let task = TaskItem(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            taskDescription: description.trimmingCharacters(in: .whitespacesAndNewlines),
            importance: importance,
            urgency: urgency,
            area: area,
            deadline: area == .longTerm ? deadline : nil,
            dailyDeadlineTime: area == .daily ? dailyDeadlineTime : nil,
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
        deadline: Date? = nil,
        dailyDeadlineTime: DailyDeadlineTime? = nil,
        now: Date = .now
    ) {
        guard let index = activeTasks.firstIndex(where: { $0.id == task.id }) else { return }
        let previousArea = activeTasks[index].area
        activeTasks[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        activeTasks[index].taskDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        activeTasks[index].importance = importance
        activeTasks[index].urgency = urgency
        activeTasks[index].area = area
        activeTasks[index].deadline = deadline
        activeTasks[index].dailyDeadlineTime = dailyDeadlineTime
        if previousArea == .longTerm && area == .daily {
            activeTasks[index].returnsToLongTermIfUnaccomplished = true
        } else if area == .longTerm {
            activeTasks[index].returnsToLongTermIfUnaccomplished = false
        }
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

    func toggleState(_ task: TaskItem, now: Date = .now) {
        guard let index = activeTasks.firstIndex(where: { $0.id == task.id }) else { return }
        activeTasks[index].state = activeTasks[index].state == .accomplished
            ? .unaccomplished
            : .accomplished
        activeTasks[index].updatedAt = now
        persist()
    }

    func moveTask(_ task: TaskItem, to area: TaskArea, now: Date = .now) {
        refreshDailyTasksIfNeeded(now: now)
        guard let index = activeTasks.firstIndex(where: { $0.id == task.id }),
              activeTasks[index].area != area else { return }

        let previousArea = activeTasks[index].area
        if previousArea == .longTerm && area == .daily,
           activeTasks[index].dailyDeadlineTime == nil,
           let deadline = activeTasks[index].deadline {
            activeTasks[index].dailyDeadlineTime = DailyDeadlineTime(from: deadline, calendar: calendar)
        }
        activeTasks[index].area = area
        activeTasks[index].returnsToLongTermIfUnaccomplished = previousArea == .longTerm
            && area == .daily
        activeTasks[index].updatedAt = now
        persist()
    }

    func archiveAccomplishedLongTermTasks(now: Date = .now) {
        let completedTasks = activeTasks.filter {
            $0.area == .longTerm && $0.state == .accomplished
        }
        guard !completedTasks.isEmpty else { return }

        let completedIDs = Set(completedTasks.map(\.id))
        let archivedTasks = completedTasks.map { task in
            var archivedTask = task
            archivedTask.isPinned = false
            archivedTask.returnsToLongTermIfUnaccomplished = false
            archivedTask.updatedAt = now
            return archivedTask
        }
        activeTasks.removeAll { completedIDs.contains($0.id) }
        archivedLongTermTasks.insert(contentsOf: archivedTasks, at: 0)
        persist()
    }

    func deleteArchivedLongTermTask(_ task: TaskItem) {
        archivedLongTermTasks.removeAll { $0.id == task.id }
        persist()
    }

    func deleteArchivedDailyTask(_ task: TaskItem, from day: ArchivedDay) {
        guard let dayIndex = archivedDays.firstIndex(where: { $0.id == day.id }),
              archivedDays[dayIndex].tasks.contains(where: { $0.id == task.id }) else { return }

        archivedDays[dayIndex].tasks.removeAll { $0.id == task.id }
        if archivedDays[dayIndex].tasks.isEmpty {
            archivedDays.remove(at: dayIndex)
        }
        persist()
    }

    func deleteAllArchivedLongTermTasks() {
        guard !archivedLongTermTasks.isEmpty else { return }
        archivedLongTermTasks.removeAll()
        persist()
    }

    func refreshDailyTasksIfNeeded(now: Date = .now) {
        let today = Self.dailyCycleStart(for: now, calendar: calendar)
        let lastResetDay = calendar.startOfDay(for: lastDailyResetDate)
        guard today > lastResetDay else { return }

        let dailyTasks = activeTasks.filter { $0.area == .daily }
        if !dailyTasks.isEmpty {
            var tasksToArchive: [TaskItem] = []
            var tasksReturningToLongTerm: [TaskItem] = []

            for task in dailyTasks {
                if task.returnsToLongTermIfUnaccomplished && task.state == .unaccomplished {
                    var returnedTask = task
                    returnedTask.area = .longTerm
                    returnedTask.returnsToLongTermIfUnaccomplished = false
                    returnedTask.updatedAt = today
                    tasksReturningToLongTerm.append(returnedTask)
                } else {
                    var archivedTask = task
                    archivedTask.returnsToLongTermIfUnaccomplished = false
                    tasksToArchive.append(archivedTask)
                }
            }

            if !tasksToArchive.isEmpty {
                mergeIntoArchive(tasksToArchive, on: lastResetDay)
            }
            activeTasks.removeAll { $0.area == .daily }
            activeTasks.append(contentsOf: tasksReturningToLongTerm)
        }

        lastDailyResetDate = today
        persist()
    }

    func startAutomaticDailyRefresh() {
        refreshDailyTasksIfNeeded()
        scheduleNextDailyRefresh()
    }

    func stopAutomaticDailyRefresh() {
        dailyRefreshTimer?.invalidate()
        dailyRefreshTimer = nil
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
        let entries: [(date: Date, task: TaskItem)] = tasks(in: scope).flatMap { day in
            day.tasks.map { (date: day.date, task: $0) }
        }
        return csv(entries: entries)
    }

    func csvForArchivedLongTermTasks(_ tasks: [TaskItem]) -> String {
        csv(entries: tasks.map { (date: $0.updatedAt, task: $0) })
    }

    func csvForArchivedDailyTask(_ task: TaskItem, on date: Date) -> String {
        csv(entries: [(date: date, task: task)])
    }

    private func csv(entries: [(date: Date, task: TaskItem)]) -> String {
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = calendar
        dayFormatter.locale = Locale(identifier: "zh_CN")
        dayFormatter.dateFormat = "yyyy-MM-dd"

        var rows = ["日期,标题,描述,状态,重要性,紧急性,创建时间,更新时间,截止时间"]
        let timestampFormatter = ISO8601DateFormatter()

        for (date, task) in entries {
            rows.append([
                dayFormatter.string(from: date),
                task.title,
                task.taskDescription,
                task.state.title,
                task.importance.title,
                task.urgency.title,
                timestampFormatter.string(from: task.createdAt),
                timestampFormatter.string(from: task.updatedAt),
                csvDeadline(for: task)
            ].map(csvField).joined(separator: ","))
        }

        return "\u{FEFF}" + rows.joined(separator: "\n")
    }

    private func load(now: Date) {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }

        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let state = try decoder.decode(PersistedState.self, from: data)
            activeTasks = state.activeTasks
            archivedDays = state.archivedDays
            archivedLongTermTasks = state.archivedLongTermTasks ?? []
            if state.version < 5 {
                for index in activeTasks.indices where activeTasks[index].area == .daily {
                    if let deadline = activeTasks[index].deadline {
                        activeTasks[index].dailyDeadlineTime = DailyDeadlineTime(from: deadline, calendar: calendar)
                    }
                }
                for dayIndex in archivedDays.indices {
                    for taskIndex in archivedDays[dayIndex].tasks.indices {
                        if let deadline = archivedDays[dayIndex].tasks[taskIndex].deadline {
                            archivedDays[dayIndex].tasks[taskIndex].dailyDeadlineTime = DailyDeadlineTime(
                                from: deadline,
                                calendar: calendar
                            )
                        }
                    }
                }
            }
            lastDailyResetDate = calendar.startOfDay(for: state.lastDailyResetDate)
            if state.version < 4,
               calendar.isDate(lastDailyResetDate, inSameDayAs: now),
               calendar.component(.hour, from: now) < 4 {
                // The old midnight cycle already started today; under the new
                // 04:00 boundary, this still belongs to yesterday's cycle.
                lastDailyResetDate = calendar.date(
                    byAdding: .day,
                    value: -1,
                    to: lastDailyResetDate
                ) ?? lastDailyResetDate
            }
            if state.version < 5 {
                persist()
            }
        } catch {
            hasLoadFailure = true
            errorMessage = "本地数据暂时无法读取。原文件会保留，不会被覆盖。"
        }
    }

    private func persist() {
        guard !hasLoadFailure else { return }

        do {
            let state = PersistedState(
                version: 5,
                activeTasks: activeTasks,
                archivedDays: archivedDays,
                archivedLongTermTasks: archivedLongTermTasks,
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

    private func csvDeadline(for task: TaskItem) -> String {
        switch task.area {
        case .longTerm:
            return task.deadline.map { TaskDeadlineFormatter.string(from: $0, calendar: calendar) } ?? ""
        case .daily:
            return task.dailyDeadlineTime?.displayString ?? ""
        }
    }

    private static func dailyCycleStart(for date: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: date)
        guard calendar.component(.hour, from: date) < 4 else { return today }
        return calendar.date(byAdding: .day, value: -1, to: today) ?? today
    }

    private func scheduleNextDailyRefresh() {
        dailyRefreshTimer?.invalidate()

        let now = Date()
        guard let nextRefresh = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: 4, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) else { return }
        let interval = max(nextRefresh.timeIntervalSince(now) + 0.1, 1)
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.startAutomaticDailyRefresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        dailyRefreshTimer = timer
    }
}
