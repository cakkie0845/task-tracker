import Foundation

enum WatchCategory: String, CaseIterable, Codable, Identifiable {
    case anime
    case game
    case comics

    var id: String { rawValue }
    var title: String { rawValue }

    var bangumiType: Int {
        switch self {
        case .anime: 2
        case .game: 4
        case .comics: 1
        }
    }

    var symbol: String {
        switch self {
        case .anime: "play.rectangle.fill"
        case .game: "gamecontroller.fill"
        case .comics: "books.vertical.fill"
        }
    }

    var creditTitle: String {
        switch self {
        case .anime: "制作方"
        case .game: "开发／发行"
        case .comics: "作者／出版社"
        }
    }

    var statusTitles: [String] {
        switch self {
        case .anime: ["待看", "在看", "已看", "搁置", "抛弃"]
        case .game: ["待玩", "在玩", "已玩", "搁置", "抛弃"]
        case .comics: ["待读", "在读", "已读", "搁置", "抛弃"]
        }
    }
}

enum WatchStatus: String, Codable, CaseIterable, Identifiable {
    case planned
    case inProgress
    case finished
    case onHold
    case dropped

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .planned: "bookmark.fill"
        case .inProgress: "play.fill"
        case .finished: "checkmark.circle.fill"
        case .onHold: "pause.fill"
        case .dropped: "xmark.circle.fill"
        }
    }

    var bangumiType: Int {
        switch self {
        case .planned: 1
        case .finished: 2
        case .inProgress: 3
        case .onHold: 4
        case .dropped: 5
        }
    }

    func title(for category: WatchCategory) -> String {
        let index = Self.allCases.firstIndex(of: self) ?? 0
        return category.statusTitles[index]
    }
}

struct WatchCollectionDetails: Equatable {
    var rating: Int
    var comment: String
    var tags: [String]
    var episodeProgress: Int
    var volumeProgress: Int
    var isPrivate: Bool

    init(item: WatchItem) {
        rating = item.rating
        comment = item.comment
        tags = item.tags
        episodeProgress = item.episodeProgress
        volumeProgress = item.volumeProgress
        isPrivate = item.isPrivate
    }
}

struct BangumiCollectionPayload: Encodable {
    let type: Int
    let rate: Int
    let comment: String
    let tags: [String]
    let epStatus: Int?
    let volStatus: Int?
    let isPrivate: Bool

    private enum CodingKeys: String, CodingKey {
        case type, rate, comment, tags
        case epStatus = "ep_status"
        case volStatus = "vol_status"
        case isPrivate = "private"
    }
}

struct WatchItem: Identifiable, Codable, Hashable {
    let subjectID: Int
    let category: WatchCategory
    let originalTitle: String
    let chineseTitle: String
    let summary: String
    let credits: String
    let coverURL: URL?
    let addedAt: Date
    var status: WatchStatus
    var rating: Int
    var comment: String
    var tags: [String]
    var episodeProgress: Int
    var volumeProgress: Int
    var isPrivate: Bool
    var localUpdatedAt: Date
    var bangumiUpdatedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case subjectID, category, originalTitle, chineseTitle, summary, credits
        case coverURL, addedAt, status, rating, comment, tags
        case episodeProgress, volumeProgress, isPrivate, localUpdatedAt, bangumiUpdatedAt
    }

    init(
        subjectID: Int,
        category: WatchCategory,
        originalTitle: String,
        chineseTitle: String,
        summary: String,
        credits: String,
        coverURL: URL?,
        addedAt: Date,
        status: WatchStatus,
        rating: Int = 0,
        comment: String = "",
        tags: [String] = [],
        episodeProgress: Int = 0,
        volumeProgress: Int = 0,
        isPrivate: Bool = false,
        localUpdatedAt: Date? = nil,
        bangumiUpdatedAt: Date? = nil
    ) {
        self.subjectID = subjectID
        self.category = category
        self.originalTitle = originalTitle
        self.chineseTitle = chineseTitle
        self.summary = summary
        self.credits = credits
        self.coverURL = coverURL
        self.addedAt = addedAt
        self.status = status
        self.rating = rating
        self.comment = comment
        self.tags = tags
        self.episodeProgress = episodeProgress
        self.volumeProgress = volumeProgress
        self.isPrivate = isPrivate
        self.localUpdatedAt = localUpdatedAt ?? addedAt
        self.bangumiUpdatedAt = bangumiUpdatedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        subjectID = try values.decode(Int.self, forKey: .subjectID)
        category = try values.decode(WatchCategory.self, forKey: .category)
        originalTitle = try values.decode(String.self, forKey: .originalTitle)
        chineseTitle = try values.decode(String.self, forKey: .chineseTitle)
        summary = try values.decode(String.self, forKey: .summary)
        credits = try values.decode(String.self, forKey: .credits)
        coverURL = try values.decodeIfPresent(URL.self, forKey: .coverURL)
        addedAt = try values.decode(Date.self, forKey: .addedAt)
        status = try values.decode(WatchStatus.self, forKey: .status)
        rating = try values.decodeIfPresent(Int.self, forKey: .rating) ?? 0
        comment = try values.decodeIfPresent(String.self, forKey: .comment) ?? ""
        tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? []
        episodeProgress = try values.decodeIfPresent(Int.self, forKey: .episodeProgress) ?? 0
        volumeProgress = try values.decodeIfPresent(Int.self, forKey: .volumeProgress) ?? 0
        isPrivate = try values.decodeIfPresent(Bool.self, forKey: .isPrivate) ?? false
        localUpdatedAt = try values.decodeIfPresent(Date.self, forKey: .localUpdatedAt) ?? addedAt
        bangumiUpdatedAt = try values.decodeIfPresent(Date.self, forKey: .bangumiUpdatedAt)
    }

    var id: Int { subjectID }

    var title: String {
        chineseTitle.isEmpty ? originalTitle : chineseTitle
    }

    var subtitle: String? {
        chineseTitle.isEmpty || chineseTitle == originalTitle ? nil : originalTitle
    }

    var bangumiURL: URL {
        URL(string: "https://bgm.tv/subject/\(subjectID)")!
    }

    var bangumiCollectionPayload: BangumiCollectionPayload {
        BangumiCollectionPayload(
            type: status.bangumiType,
            rate: rating,
            comment: comment,
            tags: tags,
            epStatus: category == .comics ? episodeProgress : nil,
            volStatus: category == .comics ? volumeProgress : nil,
            isPrivate: isPrivate
        )
    }
}
