import SwiftUI

struct WatchLaterView: View {
    @EnvironmentObject private var store: WatchLaterStore
    @State private var expandedCategories = Set(WatchCategory.allCases)
    @State private var searchCategory: WatchCategory?
    @State private var selectedItem: WatchItem?
    @State private var statusItem: WatchItem?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    ForEach(WatchCategory.allCases) { category in
                        categorySection(category)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
            .background(AppTheme.subtleBackground)
            .navigationTitle("BookMark")
            .sheet(item: $searchCategory) { category in
                WatchSearchView(category: category)
                    .environmentObject(store)
            }
            .sheet(item: $selectedItem) { item in
                WatchDetailView(subjectID: item.subjectID)
                    .environmentObject(store)
            }
            .sheet(item: $statusItem) { item in
                WatchStatusSheet(subjectID: item.subjectID)
                    .environmentObject(store)
            }
            .alert("本地列表错误", isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )) {
                Button("知道了", role: .cancel) { store.errorMessage = nil }
            } message: {
                Text(store.errorMessage ?? "")
            }
        }
    }

    private func categorySection(_ category: WatchCategory) -> some View {
        let items = store.items(in: category)
        let isExpanded = expandedCategories.contains(category)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isExpanded {
                            expandedCategories.remove(category)
                        } else {
                            expandedCategories.insert(category)
                        }
                    }
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: category.symbol)
                            .foregroundStyle(AppTheme.accent)
                        Text(category.title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("\(items.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(isExpanded ? "收起" : "展开")\(category.title)列表")

                Button {
                    searchCategory = category
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(AppTheme.accent)
                }
                .accessibilityLabel("添加\(category.title)作品")
            }

            if isExpanded {
                if items.isEmpty {
                    Button {
                        searchCategory = category
                    } label: {
                        Label("搜索作品并添加到 \(category.title)", systemImage: "magnifyingglass")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 18)
                    }
                    .buttonStyle(.plain)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                        ForEach(items) { item in
                            WatchGridCard(
                                item: item,
                                onOpen: { selectedItem = item },
                                onStatus: { statusItem = item }
                            )
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct WatchGridCard: View {
    let item: WatchItem
    let onOpen: () -> Void
    let onStatus: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Button(action: onOpen) {
                    WatchCoverView(item: item)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("查看作品：\(item.title)")

                Button(action: onStatus) {
                    Image(systemName: item.status.symbol)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(statusColor, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .padding(5)
                .accessibilityLabel("\(item.status.title(for: item.category))，更改状态")
            }

            Button(action: onOpen) {
                Text(item.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .planned: .indigo
        case .inProgress: .orange
        case .finished: .green
        case .onHold: .gray
        case .dropped: .red
        }
    }
}

struct WatchCoverView: View {
    @EnvironmentObject private var store: WatchLaterStore
    let item: WatchItem
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Rectangle().fill(.quaternary)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else {
                    Image(systemName: item.category.symbol)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .task(id: item.subjectID) {
            image = await store.cover(for: item)
        }
    }
}

private struct WatchStatusSheet: View {
    @EnvironmentObject private var store: WatchLaterStore
    @Environment(\.dismiss) private var dismiss
    let subjectID: Int

    var body: some View {
        NavigationStack {
            if let item = store.item(for: subjectID) {
                VStack(spacing: 12) {
                    ForEach(WatchStatus.allCases) { status in
                        Button {
                            if store.setStatus(status, for: subjectID) {
                                dismiss()
                            }
                        } label: {
                            HStack {
                                Label(status.title(for: item.category), systemImage: status.symbol)
                                Spacer()
                                if item.status == status {
                                    Image(systemName: "checkmark")
                                }
                            }
                            .font(.headline)
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
                .padding()
                .navigationTitle("\(item.category.title) 状态")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .presentationDetents([.height(390)])
    }
}

private struct WatchDetailView: View {
    @EnvironmentObject private var store: WatchLaterStore
    @Environment(\.dismiss) private var dismiss
    @State private var showsDeleteConfirmation = false
    @State private var showsCollectionEditor = false
    let subjectID: Int

    var body: some View {
        NavigationStack {
            if let item = store.item(for: subjectID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        WatchCoverView(item: item)
                            .frame(width: 180)
                            .frame(maxWidth: .infinity)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(.title2.weight(.bold))
                            if let subtitle = item.subtitle {
                                Text(subtitle).foregroundStyle(.secondary)
                            }
                            Text(item.status.title(for: item.category))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.accent)
                        }

                        detailSection(item.category.creditTitle, value: item.credits)
                        detailSection("描述", value: item.summary)
                        collectionSection(item)

                        Link(destination: item.bangumiURL) {
                            Label("在 Bangumi 查看来源", systemImage: "arrow.up.right.square")
                        }
                        .font(.subheadline)

                        Button("从本地列表移除", role: .destructive) {
                            showsDeleteConfirmation = true
                        }
                        .padding(.top, 12)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
                .navigationTitle(item.category.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") { dismiss() }
                    }
                }
                .confirmationDialog("移除“\(item.title)”？", isPresented: $showsDeleteConfirmation) {
                    Button("移除作品", role: .destructive) {
                        store.remove(subjectID)
                        dismiss()
                    }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text("仅移除本地记录，不影响 Bangumi。")
                }
                .sheet(isPresented: $showsCollectionEditor) {
                    WatchCollectionEditor(subjectID: subjectID)
                        .environmentObject(store)
                }
            }
        }
    }

    private func collectionSection(_ item: WatchItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("收藏信息").font(.headline)
                Spacer()
                Button("编辑") { showsCollectionEditor = true }
            }
            LabeledContent("评分", value: item.rating == 0 ? "未评分" : "\(item.rating) / 10")
            LabeledContent("标签", value: item.tags.isEmpty ? "未填写" : item.tags.joined(separator: "、"))
            LabeledContent("私密收藏", value: item.isPrivate ? "是" : "否")
            if item.category == .comics {
                LabeledContent("已读话数", value: "\(item.episodeProgress)")
                LabeledContent("已读卷数", value: "\(item.volumeProgress)")
            }
            detailSection("评价", value: item.comment)
        }
    }

    private func detailSection(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(value.isEmpty ? "暂无资料" : value)
                .font(.body)
                .foregroundStyle(value.isEmpty ? .secondary : .primary)
        }
    }
}

private struct WatchCollectionEditor: View {
    @EnvironmentObject private var store: WatchLaterStore
    @Environment(\.dismiss) private var dismiss

    let subjectID: Int
    @State private var rating = 0
    @State private var comment = ""
    @State private var tagsText = ""
    @State private var episodeText = "0"
    @State private var volumeText = "0"
    @State private var isPrivate = false
    @State private var didLoad = false
    @State private var validationError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("评分与评价") {
                    Picker("评分", selection: $rating) {
                        Text("未评分").tag(0)
                        ForEach(1...10, id: \.self) { score in
                            Text("\(score) 分").tag(score)
                        }
                    }
                    TextEditor(text: $comment)
                        .frame(minHeight: 100)
                        .accessibilityLabel("评价")
                }

                Section {
                    TextField("用逗号分隔多个标签", text: $tagsText)
                } header: {
                    Text("标签")
                } footer: {
                    Text("与 Bangumi 一致，单个标签不能包含空格。")
                }

                if store.item(for: subjectID)?.category == .comics {
                    Section("书籍进度") {
                        TextField("已读话数", text: $episodeText)
                            .keyboardType(.numberPad)
                        TextField("已读卷数", text: $volumeText)
                            .keyboardType(.numberPad)
                    }
                }

                Section {
                    Toggle("私密收藏", isOn: $isPrivate)
                } footer: {
                    Text("目前只记录在本机，未来接入 Bangumi 账号时才会用于同步；不会在本机隐藏作品。")
                }
            }
            .navigationTitle("编辑收藏信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                }
            }
            .onAppear(perform: load)
            .alert("无法保存收藏信息", isPresented: Binding(
                get: { validationError != nil },
                set: { if !$0 { validationError = nil } }
            )) {
                Button("知道了", role: .cancel) { validationError = nil }
            } message: {
                Text(validationError ?? "")
            }
        }
    }

    private func load() {
        guard !didLoad, let item = store.item(for: subjectID) else { return }
        didLoad = true
        rating = item.rating
        comment = item.comment
        tagsText = item.tags.joined(separator: "，")
        episodeText = String(item.episodeProgress)
        volumeText = String(item.volumeProgress)
        isPrivate = item.isPrivate
    }

    private func save() {
        guard let item = store.item(for: subjectID) else { return }
        let tags = tagsText.split(whereSeparator: { $0 == "," || $0 == "，" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard tags.allSatisfy({ !$0.contains(where: \.isWhitespace) }) else {
            validationError = "单个标签不能包含空格，请用逗号分隔标签。"
            return
        }

        var details = WatchCollectionDetails(item: item)
        details.rating = rating
        details.comment = comment
        details.tags = tags
        details.isPrivate = isPrivate
        if item.category == .comics {
            guard let episodes = Int(episodeText), episodes >= 0,
                  let volumes = Int(volumeText), volumes >= 0 else {
                validationError = "已读话数和卷数须为非负整数。"
                return
            }
            details.episodeProgress = episodes
            details.volumeProgress = volumes
        }
        if store.updateCollection(details, for: subjectID) {
            dismiss()
        } else {
            validationError = store.errorMessage ?? "保存失败，请重试。"
            store.errorMessage = nil
        }
    }
}
