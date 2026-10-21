import Foundation

enum TaskArea: String, Codable, CaseIterable, Identifiable {
    case daily
    case longTerm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: "每日任务"
        case .longTerm: "长期任务"
        }
    }

    var shortTitle: String {
        switch self {
        case .daily: "每日"
        case .longTerm: "长期"
        }
    }
}

enum TaskState: String, Codable, CaseIterable, Identifiable {
    case accomplished
    case unaccomplished

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accomplished: "已完成"
        case .unaccomplished: "未完成"
        }
    }
}

enum Importance: String, Codable, CaseIterable, Identifiable {
    case high
    case medium
    case low

    var id: String { rawValue }

    var title: String {
        switch self {
        case .high: "高度重要"
        case .medium: "中等重要"
        case .low: "不重要"
        }
    }
}

enum Urgency: String, Codable, CaseIterable, Identifiable {
    case immediate
    case urgent
    case relaxed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .immediate: "特急"
        case .urgent: "紧急"
        case .relaxed: "不急"
        }
    }
}

struct DailyDeadlineTime: Codable, Hashable {
    let hour: Int
    let minute: Int

    init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    init(from date: Date, calendar: Calendar = .autoupdatingCurrent) {
        hour = calendar.component(.hour, from: date)
        minute = calendar.component(.minute, from: date)
    }

    func date(on day: Date = .now, calendar: Calendar = .autoupdatingCurrent) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    var displayString: String {
        String(format: "%02d:%02d", hour, minute)
    }
}

struct TaskItem: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var taskDescription: String
    var importance: Importance
    var urgency: Urgency
    var area: TaskArea
    var state: TaskState
    var isPinned: Bool
    var returnsToLongTermIfUnaccomplished: Bool
    var deadline: Date?
    var dailyDeadlineTime: DailyDeadlineTime?
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        taskDescription: String = "",
        importance: Importance = .medium,
        urgency: Urgency = .urgent,
        area: TaskArea,
        state: TaskState = .unaccomplished,
        isPinned: Bool = false,
        returnsToLongTermIfUnaccomplished: Bool = false,
        deadline: Date? = nil,
        dailyDeadlineTime: DailyDeadlineTime? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.taskDescription = taskDescription
        self.importance = importance
        self.urgency = urgency
        self.area = area
        self.state = state
        self.isPinned = isPinned
        self.returnsToLongTermIfUnaccomplished = returnsToLongTermIfUnaccomplished
        self.deadline = deadline
        self.dailyDeadlineTime = dailyDeadlineTime
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, taskDescription, importance, urgency, area, state, isPinned
        case returnsToLongTermIfUnaccomplished, deadline, dailyDeadlineTime, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        taskDescription = try values.decode(String.self, forKey: .taskDescription)
        importance = try values.decode(Importance.self, forKey: .importance)
        urgency = try values.decode(Urgency.self, forKey: .urgency)
        area = try values.decode(TaskArea.self, forKey: .area)
        state = try values.decodeIfPresent(TaskState.self, forKey: .state) ?? .unaccomplished
        isPinned = try values.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        returnsToLongTermIfUnaccomplished = try values.decodeIfPresent(
            Bool.self,
            forKey: .returnsToLongTermIfUnaccomplished
        ) ?? false
        deadline = try values.decodeIfPresent(Date.self, forKey: .deadline)
        dailyDeadlineTime = try values.decodeIfPresent(DailyDeadlineTime.self, forKey: .dailyDeadlineTime)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
    }
}

enum TaskDeadlineFormatter {
    static func string(from date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy年M月d日，EEE，HH:mm"
        return formatter.string(from: date)
    }
}

struct ArchivedDay: Identifiable, Codable, Hashable {
    let id: UUID
    let date: Date
    var tasks: [TaskItem]

    init(id: UUID = UUID(), date: Date, tasks: [TaskItem]) {
        self.id = id
        self.date = date
        self.tasks = tasks
    }
}

enum ArchiveScope: Equatable {
    case month(year: Int, month: Int)
    case week(year: Int, month: Int, weekOfYear: Int)
    case day(Date)
}
