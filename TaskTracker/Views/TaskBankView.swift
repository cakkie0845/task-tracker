import SwiftUI
import UniformTypeIdentifiers

struct TaskBankView: View {
    @EnvironmentObject private var store: TaskStore
    @State private var pendingDeletion: PendingArchiveDeletion?
    @State private var exportDocument = CSVDocument(text: "")
    @State private var exportFilename = "task-records"
    @State private var showsExporter = false
    @State private var exportErrorMessage: String?

    private var hierarchy: [ArchiveYearGroup] {
        ArchiveHierarchyBuilder.build(from: store.archivedDays)
    }

    var body: some View {
        NavigationStack {
            Group {
                if hierarchy.isEmpty {
                    ContentUnavailableView {
                        Label("Task Bank 还是空的", systemImage: "archivebox")
                    } description: {
                        Text("每日任务跨日后，会自动归档到这里。")
                    }
                } else {
                    List {
                        ForEach(hierarchy) { year in
                            DisclosureGroup {
                                ForEach(year.months) { month in
                                    monthGroup(month)
                                }
                            } label: {
                                HStack {
                                    Label("\(year.year) 年", systemImage: "calendar")
                                        .font(.headline)
                                    Spacer()
                                    CountBadge(count: year.taskCount)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Task Bank")
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
                        store.deleteArchive(pendingDeletion.scope)
                    }
                    pendingDeletion = nil
                }
                Button("取消", role: .cancel) {
                    pendingDeletion = nil
                }
            } message: {
                Text("此操作会删除该范围内的所有任务，且无法撤销。")
            }
        }
    }

    @ViewBuilder
    private func monthGroup(_ month: ArchiveMonthGroup) -> some View {
        DisclosureGroup {
            ForEach(month.weeks) { week in
                weekGroup(week)
            }
        } label: {
            ArchiveLevelLabel(
                title: month.title,
                symbol: "calendar.circle.fill",
                tint: .indigo,
                count: month.taskCount,
                onExport: {
                    export(
                        scope: .month(year: month.year, month: month.month),
                        filename: String(format: "tasks-%04d-%02d", month.year, month.month)
                    )
                },
                onDelete: {
                    pendingDeletion = PendingArchiveDeletion(
                        title: month.title,
                        scope: .month(year: month.year, month: month.month)
                    )
                }
            )
        }
    }

    @ViewBuilder
    private func weekGroup(_ week: ArchiveWeekGroup) -> some View {
        DisclosureGroup {
            ForEach(week.days) { day in
                dayGroup(day)
            }
        } label: {
            ArchiveLevelLabel(
                title: week.title,
                symbol: "calendar.badge.clock",
                tint: .teal,
                count: week.taskCount,
                onExport: {
                    export(
                        scope: .week(year: week.year, month: week.month, weekOfYear: week.weekOfYear),
                        filename: "tasks-\(week.year)-week-\(week.weekOfYear)"
                    )
                },
                onDelete: {
                    pendingDeletion = PendingArchiveDeletion(
                        title: week.title,
                        scope: .week(year: week.year, month: week.month, weekOfYear: week.weekOfYear)
                    )
                }
            )
        }
    }

    @ViewBuilder
    private func dayGroup(_ day: ArchiveDayGroup) -> some View {
        DisclosureGroup {
            ForEach(day.archive.tasks) { task in
                TaskCardView(task: task, showsArea: false)
                    .accessibilityHint("已归档任务")
            }
        } label: {
            ArchiveLevelLabel(
                title: day.title,
                symbol: "calendar.day.timeline.left",
                tint: .orange,
                count: day.taskCount,
                onExport: {
                    export(
                        scope: .day(day.archive.date),
                        filename: "tasks-\(day.filenameDate)"
                    )
                },
                onDelete: {
                    pendingDeletion = PendingArchiveDeletion(
                        title: day.title,
                        scope: .day(day.archive.date)
                    )
                }
            )
        }
    }

    private func export(scope: ArchiveScope, filename: String) {
        exportDocument = CSVDocument(text: store.csv(in: scope))
        exportFilename = filename
        showsExporter = true
    }
}

private struct ArchiveLevelLabel: View {
    let title: String
    let symbol: String
    let tint: Color
    let count: Int
    let onExport: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 22)
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            CountBadge(count: count)
            Menu {
                Button(action: onExport) {
                    Label("导出 CSV", systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive, action: onDelete) {
                    Label("批量删除", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("\(title)更多操作")
        }
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
    let scope: ArchiveScope
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
