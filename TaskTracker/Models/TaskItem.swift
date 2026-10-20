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

struct TaskItem: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var taskDescription: String
    var importance: Importance
    var urgency: Urgency
    var area: TaskArea
    var isPinned: Bool
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        taskDescription: String = "",
        importance: Importance = .medium,
        urgency: Urgency = .urgent,
        area: TaskArea,
        isPinned: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.taskDescription = taskDescription
        self.importance = importance
        self.urgency = urgency
        self.area = area
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, taskDescription, importance, urgency, area, isPinned, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        taskDescription = try values.decode(String.self, forKey: .taskDescription)
        importance = try values.decode(Importance.self, forKey: .importance)
        urgency = try values.decode(Urgency.self, forKey: .urgency)
        area = try values.decode(TaskArea.self, forKey: .area)
        isPinned = try values.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
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
