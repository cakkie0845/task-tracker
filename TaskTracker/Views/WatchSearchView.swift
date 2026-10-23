import SwiftUI

struct WatchSearchView: View {
    private struct SearchRequest: Equatable {
        let query: String
        let id = UUID()
    }

    @EnvironmentObject private var store: WatchLaterStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isSearchFocused: Bool

    let category: WatchCategory
    private let client = BangumiClient()

    @State private var keyword = ""
    @State private var searchRequest: SearchRequest?
    @State private var results: [BangumiSubject] = []
    @State private var total = 0
    @State private var nextOffset = 0
    @State private var isSearching = false
    @State private var isLoadingMore = false
    @State private var addingID: Int?
    @State private var searchErrorMessage: String?
    @State private var addErrorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar

                List {
                    if keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ContentUnavailableView(
                            "搜索 \(category.title) 作品",
                            systemImage: "magnifyingglass",
                            description: Text("输入作品名，从 Bangumi 搜索并添加到本地列表。")
                        )
                    } else if isSearching && results.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView("搜索中…")
                            Spacer()
                        }
                    } else if results.isEmpty && searchErrorMessage == nil {
                        ContentUnavailableView.search(text: keyword)
                    } else {
                        ForEach(results) { subject in
                            Button {
                                Task { await add(subject) }
                            } label: {
                                searchRow(subject)
                            }
                            .buttonStyle(.plain)
                            .disabled(store.contains(subject.id) || addingID != nil)
                            .accessibilityLabel("\(subject.title)，\(store.contains(subject.id) ? "已添加" : "添加到本地列表")")
                        }

                        if nextOffset < total {
                            Button {
                                Task { await loadMore() }
                            } label: {
                                HStack {
                                    Spacer()
                                    if isLoadingMore { ProgressView() }
                                    Text(isLoadingMore ? "加载中…" : "加载更多")
                                    Spacer()
                                }
                            }
                            .disabled(isLoadingMore || addingID != nil)
                        }
                    }

                    if let searchErrorMessage, let request = searchRequest {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(searchErrorMessage, systemImage: "wifi.exclamationmark")
                                .foregroundStyle(.secondary)
                            Button("重试") {
                                if results.isEmpty {
                                    startSearch(query: request.query)
                                } else {
                                    Task { await loadMore() }
                                }
                            }
                        }
                        .font(.subheadline)
                    }

                    if let addErrorMessage {
                        Label(addErrorMessage, systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("添加 \(category.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !isSearchFocused {
                        Button("取消") { dismiss() }
                    }
                }
            }
            .onChange(of: keyword) { _, newValue in
                let query = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard query != searchRequest?.query else { return }
                searchRequest = nil
                results = []
                total = 0
                nextOffset = 0
                isSearching = !query.isEmpty
                isLoadingMore = false
                searchErrorMessage = nil
                addErrorMessage = nil
            }
            .task(id: keyword) {
                let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty else { return }
                do {
                    try await Task.sleep(for: .milliseconds(400))
                } catch {
                    return
                }
                guard !Task.isCancelled,
                      query == keyword.trimmingCharacters(in: .whitespacesAndNewlines),
                      searchRequest?.query != query else { return }
                startSearch(query: query)
            }
            .task(id: searchRequest) {
                guard let request = searchRequest else { return }
                isSearching = true
                do {
                    let page = try await client.search(request.query, category: category)
                    try Task.checkCancellation()
                    guard searchRequest == request else { return }
                    results = page.data
                    total = page.total
                    nextOffset = page.returnedCount
                } catch {
                    guard !Task.isCancelled, searchRequest == request,
                          !BangumiClient.isCancellation(error) else { return }
                    searchErrorMessage = error.localizedDescription
                }
                if searchRequest == request { isSearching = false }
            }
            .overlay {
                if addingID != nil {
                    ProgressView("正在获取作品资料…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            if isSearchFocused {
                Button("取消") {
                    keyword = ""
                    isSearchFocused = false
                }
                .accessibilityLabel("取消搜索")
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索作品名", text: $keyword)
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                    .onSubmit { isSearchFocused = false }
                if !keyword.isEmpty {
                    Button {
                        keyword = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("清除搜索内容")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func startSearch(query: String) {
        guard !query.isEmpty else { return }
        results = []
        total = 0
        nextOffset = 0
        isSearching = true
        isLoadingMore = false
        searchErrorMessage = nil
        addErrorMessage = nil
        searchRequest = SearchRequest(query: query)
    }

    private func searchRow(_ subject: BangumiSubject) -> some View {
        HStack(alignment: .top, spacing: 12) {
            BangumiThumbnailView(url: subject.images?.thumbnailURL, symbol: category.symbol)

            VStack(alignment: .leading, spacing: 5) {
                Text(subject.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if subject.title != subject.name {
                    Text(subject.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let platform = subject.platform, !platform.isEmpty {
                    Text(platform)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let summary = subject.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: store.contains(subject.id) ? "checkmark.circle.fill" : "plus.circle.fill")
                .foregroundStyle(store.contains(subject.id) ? Color.green : AppTheme.accent)
                .font(.title3)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func loadMore() async {
        guard let request = searchRequest, !isLoadingMore else { return }
        isLoadingMore = true
        searchErrorMessage = nil
        defer { if searchRequest == request { isLoadingMore = false } }
        do {
            let page = try await client.search(request.query, category: category, offset: nextOffset)
            guard searchRequest == request else { return }
            let existing = Set(results.map(\.id))
            results.append(contentsOf: page.data.filter { !existing.contains($0.id) })
            total = page.total
            nextOffset = page.returnedCount == 0 ? page.total : nextOffset + page.returnedCount
        } catch {
            guard searchRequest == request, !BangumiClient.isCancellation(error) else { return }
            searchErrorMessage = error.localizedDescription
        }
    }

    private func add(_ subject: BangumiSubject) async {
        guard addingID == nil, !store.contains(subject.id) else { return }
        addingID = subject.id
        defer { addingID = nil }
        do {
            let item = try await client.item(for: subject.id, category: category)
            if store.add(item) {
                dismiss()
            } else if !store.contains(subject.id) {
                addErrorMessage = store.errorMessage ?? "无法保存到本地列表。"
            }
        } catch {
            guard !BangumiClient.isCancellation(error) else { return }
            addErrorMessage = error.localizedDescription
        }
    }
}

private struct BangumiThumbnailView: View {
    let url: URL?
    let symbol: String
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 54, height: 72)
                    .clipped()
            } else {
                Image(systemName: symbol).foregroundStyle(.secondary)
            }
        }
        .frame(width: 54, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .task(id: url) {
            image = nil
            guard let url else { return }
            var request = URLRequest(url: url)
            request.setValue(BangumiClient.userAgent, forHTTPHeaderField: "User-Agent")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            image = UIImage(data: data)
        }
    }
}
