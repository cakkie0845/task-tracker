import SwiftUI

struct TaskBoardView: View {
    @EnvironmentObject private var store: TaskStore
    @State private var editorContext: EditorContext?
    @State private var taskPendingDeletion: TaskItem?
    @State private var isLongTermExpanded = true

    var body: some View {
        NavigationStack {
            List {
                taskSection(
                    title: "长期任务",
                    subtitle: "完成后可归档到 TaskBank",
                    symbol: "infinity",
                    tint: .indigo,
                    tasks: store.longTermTasks,
                    area: .longTerm
                )

                taskSection(
                    title: "每日任务",
                    subtitle: "跨日后按规则归档或返回长期区",
                    symbol: "sun.max.fill",
                    tint: .orange,
                    tasks: store.dailyTasks,
                    area: .daily
                )
            }
            .listStyle(.insetGrouped)
            .scrollIndicators(.visible)
            .navigationTitle("Task")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editorContext = EditorContext(task: nil, defaultArea: .daily)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新建任务")
                }
            }
            .sheet(item: $editorContext) { context in
                TaskEditorView(task: context.task, defaultArea: context.defaultArea)
                    .environmentObject(store)
            }
            .confirmationDialog(
                "删除“\(taskPendingDeletion?.title ?? "")”？",
                isPresented: Binding(
                    get: { taskPendingDeletion != nil },
                    set: { if !$0 { taskPendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除任务", role: .destructive) {
                    if let taskPendingDeletion {
                        store.deleteTask(taskPendingDeletion)
                    }
                    taskPendingDeletion = nil
                }
                Button("取消", role: .cancel) {
                    taskPendingDeletion = nil
                }
            }
        }
    }

    @ViewBuilder
    private func taskSection(
        title: String,
        subtitle: String,
        symbol: String,
        tint: Color,
        tasks: [TaskItem],
        area: TaskArea
    ) -> some View {
        Section {
            if area == .longTerm && !isLongTermExpanded {
                Button {
                    withAnimation { isLongTermExpanded = true }
                } label: {
                    Label("长期任务已收起，轻点展开", systemImage: "chevron.down")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            } else if tasks.isEmpty {
                Button {
                    editorContext = EditorContext(task: nil, defaultArea: area)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(tint)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("还没有\(title)")
                                .foregroundStyle(.primary)
                            Text("轻点添加第一项")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            } else {
                ForEach(tasks) { task in
                    TaskCardView(
                        task: task,
                        onOpen: {
                            editorContext = EditorContext(task: task, defaultArea: task.area)
                        },
                        onToggleState: {
                            store.toggleState(task)
                        }
                    )
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                taskPendingDeletion = task
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                store.togglePin(task)
                            } label: {
                                Label(
                                    task.isPinned ? "取消置顶" : "置顶",
                                    systemImage: task.isPinned ? "pin.slash" : "pin"
                                )
                            }
                            .tint(.orange)

                            Button {
                                editorContext = EditorContext(task: task, defaultArea: task.area)
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            .tint(.indigo)
                        }
                        .contextMenu {
                            Button {
                                store.moveTask(
                                    task,
                                    to: task.area == .longTerm ? .daily : .longTerm
                                )
                            } label: {
                                Label(
                                    task.area == .longTerm ? "移动到每日任务" : "移动到长期任务",
                                    systemImage: task.area == .longTerm
                                        ? "sun.max.fill"
                                        : "infinity"
                                )
                            }
                            Button {
                                store.togglePin(task)
                            } label: {
                                Label(
                                    task.isPinned ? "取消置顶" : "置顶",
                                    systemImage: task.isPinned ? "pin.slash" : "pin"
                                )
                            }
                            Button {
                                editorContext = EditorContext(task: task, defaultArea: task.area)
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                        }
                }
            }
        } header: {
            HStack(spacing: 10) {
                if area == .longTerm {
                    Button {
                        withAnimation { isLongTermExpanded.toggle() }
                    } label: {
                        HStack(spacing: 10) {
                            sectionHeading(title: title, subtitle: subtitle, symbol: symbol, tint: tint)
                            Image(systemName: isLongTermExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isLongTermExpanded ? "收起长期任务" : "展开长期任务")
                } else {
                    sectionHeading(title: title, subtitle: subtitle, symbol: symbol, tint: tint)
                }
                Spacer()
                Text("\(tasks.count)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                if area == .longTerm {
                    let accomplishedCount = tasks.filter { $0.state == .accomplished }.count
                    Button {
                        store.archiveAccomplishedLongTermTasks()
                    } label: {
                        Image(systemName: "archivebox.fill")
                            .font(.title3)
                            .foregroundStyle(accomplishedCount == 0 ? Color.secondary : tint)
                    }
                    .buttonStyle(.plain)
                    .disabled(accomplishedCount == 0)
                    .accessibilityLabel("归档已完成的长期任务")
                    .accessibilityValue("\(accomplishedCount) 个可归档")
                }
                Button {
                    editorContext = EditorContext(task: nil, defaultArea: area)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(tint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("添加\(title)")
            }
            .padding(.bottom, 4)
        }
    }

    private func sectionHeading(
        title: String,
        subtitle: String,
        symbol: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .textCase(nil)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        }
    }
}

private struct EditorContext: Identifiable {
    let id = UUID()
    let task: TaskItem?
    let defaultArea: TaskArea
}
