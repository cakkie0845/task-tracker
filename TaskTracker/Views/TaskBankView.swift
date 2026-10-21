import SwiftUI
import UniformTypeIdentifiers

struct TaskBankView: View {
    @EnvironmentObject private var store: TaskStore
    @State private var pendingDeletion: PendingArchiveDeletion?
    @State private var exportDocument = CSVDocument(text: "")
    @State private var exportFilename = "task-records"
    @State private var showsExporter = false
    @State private var exportErrorMessage: String?
    @State private var expandedYears: Set<Int> = []
    @State private var expandedMonths: Set<String> = []
    @State private var expandedWeeks: Set<String> = []
    @State private var expandedDays: Set<UUID> = []
    @State private var didInitializeExpansion = false

    private var hierarchy: [ArchiveYearGroup] {
        ArchiveHierarchyBuilder.build(from: store.archivedDays)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if store.archivedLongTermTasks.isEmpty {
                        archivePlaceholder("完成长期任务后，点击任务页的归档按钮。")
                    } else {
                        ForEach(store.archivedLongTermTasks) { task in
                            TaskCardView(task: task)
                                .contextMenu {
                                    Button {
                                        exportLongTermTasks([task], filename: "long-term-\(task.id.uuidString)")
                                    } label: {
                                        Label("导出 CSV", systemImage: "square.and.arrow.up")
                                    }
                                    Button(role: .destructive) {
                                        pendingDeletion = PendingArchiveDeletion(
                                            title: "长期任务“\(task.title)”",
                                            target: .longTermTask(task)
                                        )
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                                .accessibilityHint("长按可导出 CSV 或删除")
                        }
                    }
                } header: {
                    HStack {
                        ArchiveSectionHeader(
                            title: "长期任务",
                            symbol: "infinity",
                            tint: .indigo,
                            count: store.archivedLongTermTasks.count
                        )
                        if !store.archivedLongTermTasks.isEmpty {
                            Menu {
                                Button {
                                    exportLongTermTasks(
                                        store.archivedLongTermTasks,
                                        filename: "long-term-tasks"
                                    )
                                } label: {
                                    Label("导出全部 CSV", systemImage: "square.and.arrow.up")
                                }
                                Button(role: .destructive) {
                                    pendingDeletion = PendingArchiveDeletion(
                                        title: "全部长期任务归档",
                                        target: .allLongTerm
                                    )
                                } label: {
                                    Label("删除全部", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.title3)
                            }
                            .accessibilityLabel("长期任务归档操作")
                        }
                    }
                }

                Section {
                    if hierarchy.isEmpty {
                        archivePlaceholder("还没有每日归档。每日任务会在凌晨 4:00 更新后显示在这里，之后可按年 → 月 → 周 → 天展开，并按月、周或天导出和删除。")
                    } else {
                        ForEach(hierarchy) { year in
                            ArchiveGroupRow(
                                title: "\(year.year) 年",
                                symbol: "calendar",
                                tint: .indigo,
                                count: year.taskCount,
                                depth: 0,
                                isExpanded: expandedYears.contains(year.id),
                                onToggle: {
                                    if expandedYears.contains(year.id) {
                                        expandedYears.remove(year.id)
                                    } else {
                                        expandedYears.insert(year.id)
                                    }
                                },
                                onExport: nil,
                                onDelete: nil
                            )
                            if expandedYears.contains(year.id) {
                                ForEach(year.months) { month in
                                    monthGroup(month)
                                }
                            }
                        }
                    }
                } header: {
                    ArchiveSectionHeader(
                        title: "每日任务",
                        symbol: "sun.max.fill",
                        tint: .orange,
                        count: store.archivedDays.reduce(0) { $0 + $1.tasks.count }
                    )
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Task Bank")
            .onAppear {
                if !didInitializeExpansion {
                    expandMostRecentArchive()
                    didInitializeExpansion = true
                }
            }
            .onChange(of: store.archivedDays.map(\.id)) { _, _ in
                expandMostRecentArchive()
            }
            .fileExporter(
                isPresented: $showsExporter,
                document: exportDocument,
                contentType: .commaSeparatedText,
                defaultFilename: exportFilename
            ) { result in
                if case let .failure(error) = result {
                    exportErrorMessage = error.localizedDescription
                }
            }
            .alert(
                "无法导出",
                isPresented: Binding(
                    get: { exportErrorMessage != nil },
                    set: { if !$0 { exportErrorMessage = nil } }
                )
            ) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(exportErrorMessage ?? "")
            }
            .confirmationDialog(
                "删除\(pendingDeletion?.title ?? "这些归档")？",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("永久删除", role: .destructive) {
                    if let pendingDeletion {
                        switch pendingDeletion.target {
                        case let .daily(scope):
                            store.deleteArchive(scope)
                        case let .longTermTask(task):
                            store.deleteArchivedLongTermTask(task)
                        case let .dailyTask(task, day):
                            store.deleteArchivedDailyTask(task, from: day)
                        case .allLongTerm:
                            store.deleteAllArchivedLongTermTasks()
                        }
                    }
                    pendingDeletion = nil
                }
                Button("取消", role: .cancel) {
                    pendingDeletion = nil
                }
            } message: {
                Text(pendingDeletion?.target.confirmationMessage ?? "此操作无法撤销。")
            }
        }
    }

    private func archivePlaceholder(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
    }

    @ViewBuilder
    private func monthGroup(_ month: ArchiveMonthGroup) -> some View {
        ArchiveGroupRow(
            title: month.title,
            symbol: "calendar.circle.fill",
            tint: .indigo,
            count: month.taskCount,
            depth: 1,
            isExpanded: expandedMonths.contains(month.id),
            onToggle: {
                if expandedMonths.contains(month.id) {
                    expandedMonths.remove(month.id)
                } else {
                    expandedMonths.insert(month.id)
                }
            },
            onExport: {
                export(
                    scope: .month(year: month.year, month: month.month),
                    filename: String(format: "tasks-%04d-%02d", month.year, month.month)
                )
            },
            onDelete: {
                pendingDeletion = PendingArchiveDeletion(
                    title: month.title,
                    target: .daily(.month(year: month.year, month: month.month))
                )
            }
        )
        if expandedMonths.contains(month.id) {
            ForEach(month.weeks) { week in
                weekGroup(week)
            }
        }
    }

    @ViewBuilder
    private func weekGroup(_ week: ArchiveWeekGroup) -> some View {
        ArchiveGroupRow(
            title: week.title,
            symbol: "calendar.badge.clock",
            tint: .teal,
            count: week.taskCount,
            depth: 2,
            isExpanded: expandedWeeks.contains(week.id),
            onToggle: {
                if expandedWeeks.contains(week.id) {
                    expandedWeeks.remove(week.id)
                } else {
                    expandedWeeks.insert(week.id)
                }
            },
            onExport: {
                export(
                    scope: .week(year: week.year, month: week.month, weekOfYear: week.weekOfYear),
                    filename: "tasks-\(week.year)-week-\(week.weekOfYear)"
                )
            },
            onDelete: {
                pendingDeletion = PendingArchiveDeletion(
                    title: week.title,
                    target: .daily(.week(year: week.year, month: week.month, weekOfYear: week.weekOfYear))
                )
            }
        )
        if expandedWeeks.contains(week.id) {
            ForEach(week.days) { day in
                dayGroup(day)
            }
        }
    }

    @ViewBuilder
    private func dayGroup(_ day: ArchiveDayGroup) -> some View {
        ArchiveGroupRow(
            title: day.title,
            symbol: "calendar.day.timeline.left",
            tint: .orange,
            count: day.taskCount,
            depth: 3,
            isExpanded: expandedDays.contains(day.id),
            onToggle: {
                if expandedDays.contains(day.id) {
                    expandedDays.remove(day.id)
                } else {
                    expandedDays.insert(day.id)
                }
            },
            onExport: {
                export(
                    scope: .day(day.archive.date),
                    filename: "tasks-\(day.filenameDate)"
                )
            },
            onDelete: {
                pendingDeletion = PendingArchiveDeletion(
                    title: day.title,
                    target: .daily(.day(day.archive.date))
                )
            }
        )
        if expandedDays.contains(day.id) {
            ForEach(day.archive.tasks) { task in
                TaskCardView(task: task, showsArea: false)
                    .padding(.leading, 66)
                    .contextMenu {
                        Button {
                            exportDocument = CSVDocument(
                                text: store.csvForArchivedDailyTask(task, on: day.archive.date)
                            )
                            exportFilename = "task-\(day.filenameDate)-\(task.id.uuidString)"
                            showsExporter = true
                        } label: {
                            Label("导出 CSV", systemImage: "square.and.arrow.up")
                        }
                        Button(role: .destructive) {
                            pendingDeletion = PendingArchiveDeletion(
                                title: "每日任务“\(task.title)”",
                                target: .dailyTask(task, day.archive)
                            )
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                    .accessibilityHint("长按可导出 CSV 或删除")
            }
        }
    }

    private func export(scope: ArchiveScope, filename: String) {
        exportDocument = CSVDocument(text: store.csv(in: scope))
        exportFilename = filename
        showsExporter = true
    }

    private func exportLongTermTasks(_ tasks: [TaskItem], filename: String) {
        exportDocument = CSVDocument(text: store.csvForArchivedLongTermTasks(tasks))
        exportFilename = filename
        showsExporter = true
    }

    private func expandMostRecentArchive() {
        guard let year = hierarchy.first,
              let month = year.months.first,
              let week = month.weeks.first else { return }
        expandedYears.insert(year.id)
        expandedMonths.insert(month.id)
        expandedWeeks.insert(week.id)
    }
}

private struct ArchiveSectionHeader: View {
    let title: String
    let symbol: String
    let tint: Color
    let count: Int

    var body: some View {
        HStack {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(tint)
                .textCase(nil)
            Spacer()
            CountBadge(count: count)
        }
    }
}

private struct ArchiveGroupRow: View {
    let title: String
    let symbol: String
    let tint: Color
    let count: Int
    let depth: Int
    let isExpanded: Bool
    let onToggle: () -> Void
    let onExport: (() -> Void)?
    let onDelete: (() -> Void)?

    var body: some View {
        HStack(spacing: 9) {
            Button(action: onToggle) {
                HStack(spacing: 9) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                    Image(systemName: symbol)
                        .foregroundStyle(tint)
                        .frame(width: 22)
                    Text(title)
                        .foregroundStyle(.primary)
                    Spacer()
                    CountBadge(count: count)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title)，\(count) 个任务，\(isExpanded ? "收起" : "展开")")

            if let onExport, let onDelete {
                Menu {
                    Button(action: onExport) {
                        Label("导出 CSV", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive, action: onDelete) {
                        Label("批量删除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 36)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("\(title)的导出和删除操作")
            }
        }
        .padding(.leading, CGFloat(depth * 16))
        .padding(.vertical, 3)
    }
}

private struct CountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.caption2.monospacedDigit().weight(.bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
            .accessibilityLabel("\(count) 个任务")
    }
}

private struct PendingArchiveDeletion: Identifiable {
    let id = UUID()
    let title: String
    let target: ArchiveDeletionTarget
}

private enum ArchiveDeletionTarget {
    case daily(ArchiveScope)
    case longTermTask(TaskItem)
    case dailyTask(TaskItem, ArchivedDay)
    case allLongTerm

    var confirmationMessage: String {
        switch self {
        case .longTermTask, .dailyTask:
            return "此操作会永久删除这项归档任务，且无法撤销。"
        case .daily, .allLongTerm:
            return "此操作会永久删除该范围内的所有任务，且无法撤销。"
        }
    }
}

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    let text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
