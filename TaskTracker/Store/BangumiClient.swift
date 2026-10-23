import Foundation

struct BangumiSubject: Decodable, Identifiable {
    struct Images: Decodable {
        let large: URL?
        let common: URL?
        let medium: URL?
        let small: URL?
        let grid: URL?

        private enum CodingKeys: String, CodingKey {
            case large, common, medium, small, grid
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            large = Self.url(for: .large, in: values)
            common = Self.url(for: .common, in: values)
            medium = Self.url(for: .medium, in: values)
            small = Self.url(for: .small, in: values)
            grid = Self.url(for: .grid, in: values)
        }

        private static func url(
            for key: CodingKeys,
            in values: KeyedDecodingContainer<CodingKeys>
        ) -> URL? {
            guard let raw = try? values.decode(String.self, forKey: key),
                  !raw.isEmpty,
                  let url = URL(string: raw),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  url.host != nil else { return nil }
            return url
        }

        var coverURL: URL? { common ?? medium ?? large ?? grid ?? small }
        var thumbnailURL: URL? { grid ?? small ?? medium ?? common ?? large }
    }

    struct InfoField: Decodable {
        struct Entry: Decodable {
            let k: String?
            let v: String
        }

        let key: String
        let values: [String]

        private enum CodingKeys: String, CodingKey { case key, value }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            key = try container.decode(String.self, forKey: .key)
            if let value = try? container.decode(String.self, forKey: .value) {
                values = [value]
            } else {
                values = (try? container.decode([Entry].self, forKey: .value))?
                    .map(\.v) ?? []
            }
        }
    }

    let id: Int
    let type: Int
    let name: String
    let name_cn: String?
    let summary: String?
    let platform: String?
    let images: Images?
    let infobox: [InfoField]?

    var title: String {
        let chinese = name_cn?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return chinese.isEmpty ? name : chinese
    }
}

struct BangumiSearchPage: Decodable {
    let total: Int
    let data: [BangumiSubject]
    let returnedCount: Int

    private enum CodingKeys: String, CodingKey { case total, data }

    private struct DecodableSubject: Decodable {
        let value: BangumiSubject?

        init(from decoder: Decoder) throws {
            value = try? BangumiSubject(from: decoder)
        }
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        total = try values.decode(Int.self, forKey: .total)
        let subjects = try values.decode([DecodableSubject].self, forKey: .data)
        returnedCount = subjects.count
        data = subjects.compactMap(\.value)
    }
}

struct BangumiPerson: Decodable {
    let name: String
    let type: Int
    let relation: String
}

struct BangumiClient {
    static let userAgent = "cakkie0845/TaskTracker/1.0 (iOS; https://github.com/cakkie0845/task-tracker)"

    static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(_ keyword: String, category: WatchCategory, offset: Int = 0) async throws -> BangumiSearchPage {
        let url = URL(string: "https://api.bgm.tv/v0/search/subjects?limit=20&offset=\(offset)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "keyword": keyword,
            "sort": "match",
            "filter": ["type": [category.bangumiType], "nsfw": false]
        ])
        return try await send(request)
    }

    func item(for subjectID: Int, category: WatchCategory, addedAt: Date = .now) async throws -> WatchItem {
        let subject: BangumiSubject = try await send(URLRequest(
            url: URL(string: "https://api.bgm.tv/v0/subjects/\(subjectID)")!
        ))
        guard subject.type == category.bangumiType else { throw BangumiError.wrongCategory }

        var credits = Self.credits(from: subject, category: category)
        if credits.isEmpty {
            let persons: [BangumiPerson]? = try? await send(URLRequest(
                url: URL(string: "https://api.bgm.tv/v0/subjects/\(subjectID)/persons")!
            ))
            credits = Self.credits(from: persons ?? [], category: category)
        }

        return WatchItem(
            subjectID: subject.id,
            category: category,
            originalTitle: subject.name,
            chineseTitle: subject.name_cn ?? "",
            summary: subject.summary ?? "",
            credits: credits,
            coverURL: subject.images?.coverURL,
            addedAt: addedAt,
            status: .planned
        )
    }

    static func credits(from subject: BangumiSubject, category: WatchCategory) -> String {
        let keys: [String]
        switch category {
        case .anime:
            keys = ["动画制作", "制作", "製作", "制作公司", "动画公司"]
        case .game:
            keys = ["开发", "开发商", "制作", "发行", "发行商"]
        case .comics:
            keys = ["作者", "原作", "作画", "绘画", "出版社", "出版"]
        }

        return keys.compactMap { wanted in
            guard let field = subject.infobox?.first(where: { $0.key == wanted }) else { return nil }
            let value = field.values
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "、")
            return value.isEmpty ? nil : "\(wanted)：\(value)"
        }
        .prefix(3)
        .joined(separator: " · ")
    }

    static func credits(from persons: [BangumiPerson], category: WatchCategory) -> String {
        let roles: [String]
        switch category {
        case .anime: roles = ["动画制作", "制作", "製作"]
        case .game: roles = ["开发", "发行", "制作"]
        case .comics: roles = ["作者", "作画", "原作", "出版社"]
        }
        return persons.filter { person in
            person.type == 2 || roles.contains(where: { person.relation.contains($0) })
        }
        .prefix(3)
        .map { "\($0.relation)：\($0.name)" }
        .joined(separator: " · ")
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        var request = request
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BangumiError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw BangumiError.httpStatus(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch is DecodingError {
            throw BangumiError.malformedData
        }
    }
}

enum BangumiError: LocalizedError {
    case invalidResponse
    case malformedData
    case httpStatus(Int)
    case wrongCategory

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Bangumi 返回了无法识别的响应。"
        case .malformedData: "Bangumi 返回的数据暂时无法读取，请稍后重试。"
        case .httpStatus(429): "Bangumi 请求过于频繁，请稍后重试。"
        case let .httpStatus(status): "Bangumi 请求失败（HTTP \(status)）。"
        case .wrongCategory: "这项作品不属于当前列表。"
        }
    }
}
