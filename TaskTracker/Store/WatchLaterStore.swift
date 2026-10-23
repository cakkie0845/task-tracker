import Combine
import Foundation
import UIKit

@MainActor
final class WatchLaterStore: ObservableObject {
    @Published private(set) var items: [WatchItem] = []
    @Published var errorMessage: String?

    private struct PersistedState: Codable {
        let version: Int
        let items: [WatchItem]
    }

    private let storageURL: URL
    private let coversDirectory: URL
    private var hasLoadFailure = false

    init(storageURL: URL? = nil) {
        if let storageURL {
            self.storageURL = storageURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.storageURL = support
                .appendingPathComponent("TaskTracker", isDirectory: true)
                .appendingPathComponent("watch-later.json")
        }
        coversDirectory = self.storageURL.deletingLastPathComponent()
            .appendingPathComponent("WatchLaterCovers", isDirectory: true)
        load()
    }

    func items(in category: WatchCategory) -> [WatchItem] {
        items.filter { $0.category == category }
            .sorted {
                if $0.addedAt == $1.addedAt { return $0.subjectID > $1.subjectID }
                return $0.addedAt > $1.addedAt
            }
    }

    func item(for subjectID: Int) -> WatchItem? {
        items.first { $0.subjectID == subjectID }
    }

    func contains(_ subjectID: Int) -> Bool {
        item(for: subjectID) != nil
    }

    @discardableResult
    func add(_ item: WatchItem) -> Bool {
        guard !hasLoadFailure, !contains(item.subjectID) else { return false }
        let previous = items
        items.append(item)
        if persist() { return true }
        items = previous
        return false
    }

    @discardableResult
    func setStatus(_ status: WatchStatus, for subjectID: Int) -> Bool {
        guard !hasLoadFailure, let index = items.firstIndex(where: { $0.subjectID == subjectID }) else { return false }
        let previous = items[index]
        items[index].status = status
        items[index].localUpdatedAt = .now
        if persist() { return true }
        items[index] = previous
        return false
    }

    @discardableResult
    func updateCollection(_ details: WatchCollectionDetails, for subjectID: Int) -> Bool {
        guard !hasLoadFailure, let index = items.firstIndex(where: { $0.subjectID == subjectID }) else { return false }
        guard (0...10).contains(details.rating),
              details.episodeProgress >= 0, details.volumeProgress >= 0,
              details.tags.allSatisfy({ !$0.isEmpty && !$0.contains(where: \.isWhitespace) }) else {
            errorMessage = "收藏信息不符合 Bangumi 格式；评分须为 0–10，进度不能为负数，标签不能包含空格。"
            return false
        }
        let previous = items[index]
        items[index].rating = details.rating
        items[index].comment = details.comment
        items[index].tags = details.tags
        items[index].episodeProgress = details.episodeProgress
        items[index].volumeProgress = details.volumeProgress
        items[index].isPrivate = details.isPrivate
        items[index].localUpdatedAt = .now
        if persist() { return true }
        items[index] = previous
        return false
    }

    func remove(_ subjectID: Int) {
        guard !hasLoadFailure, contains(subjectID) else { return }
        let previous = items
        items.removeAll { $0.subjectID == subjectID }
        if persist() {
            try? FileManager.default.removeItem(at: coverFileURL(for: subjectID))
        } else {
            items = previous
        }
    }

    func cover(for item: WatchItem) async -> UIImage? {
        let fileURL = coverFileURL(for: item.subjectID)
        if let image = UIImage(contentsOfFile: fileURL.path) { return image }
        guard let coverURL = item.coverURL else { return nil }

        do {
            var request = URLRequest(url: coverURL)
            request.setValue(BangumiClient.userAgent, forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = UIImage(data: data) else { return nil }
            if let jpeg = image.jpegData(compressionQuality: 0.88) {
                try? FileManager.default.createDirectory(at: coversDirectory, withIntermediateDirectories: true)
                try? jpeg.write(to: fileURL, options: .atomic)
            }
            return image
        } catch {
            return nil
        }
    }

    private func coverFileURL(for subjectID: Int) -> URL {
        coversDirectory.appendingPathComponent("\(subjectID).jpg")
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let state = try decoder.decode(PersistedState.self, from: data)
            guard state.version == 1 || state.version == 2 else { throw WatchStoreError.unsupportedVersion }
            items = state.items
        } catch {
            hasLoadFailure = true
            errorMessage = "BookMark 数据无法读取；原文件已保留，不会被覆盖。"
        }
    }

    @discardableResult
    private func persist() -> Bool {
        guard !hasLoadFailure else { return false }
        do {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(PersistedState(version: 2, items: items))
                .write(to: storageURL, options: .atomic)
            return true
        } catch {
            errorMessage = "BookMark 保存失败，请检查设备可用空间。"
            return false
        }
    }
}

private enum WatchStoreError: Error {
    case unsupportedVersion
}
