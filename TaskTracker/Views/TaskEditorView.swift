import SwiftUI

struct TaskEditorView: View {
    @EnvironmentObject private var store: TaskStore
    @Environment(\.dismiss) private var dismiss

    private let task: TaskItem?
    @State private var title: String
    @State private var taskDescription: String
    @State private var importance: Importance
    @State private var urgency: Urgency
    @State private var area: TaskArea
    @State private var showsDeleteConfirmation = false

    init(task: TaskItem?, defaultArea: TaskArea) {
        self.task = task
        _title = State(initialValue: task?.title ?? "")
        _taskDescription = State(initialValue: task?.taskDescription ?? "")
        _importance = State(initialValue: task?.importance ?? .medium)
        _urgency = State(initialValue: task?.urgency ?? .urgent)
        _area = State(initialValue: task?.area ?? defaultArea)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("任务内容") {
                    TextField("标题", text: $title)
                        .textInputAutocapitalization(.sentences)

                    TextEditor(text: $taskDescription)
                        .frame(minHeight: 110)
                        .overlay(alignment: .topLeading) {
                            if taskDescription.isEmpty {
                                Text("描述（可选）")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                Section {
                    Picker("任务区域", selection: $area) {
                        ForEach(TaskArea.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("任务区域")
                } footer: {
                    Text(area == .daily ? "每日任务会在跨日时归档到 Task Bank。" : "长期任务会一直保留，直到你移动或删除它。")
                }

                Section("重要性") {
                    Picker("重要性", selection: $importance) {
                        ForEach(Importance.allCases) { item in
                            Label {
                                Text(item.title)
                            } icon: {
                                Image(systemName: "circle.fill")
                                    .foregroundStyle(item.color)
                            }
                            .tag(item)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("紧急性") {
                    Picker("紧急性", selection: $urgency) {
                        ForEach(Urgency.allCases) { item in
                            Label {
                                Text(item.title)
                            } icon: {
                                Image(systemName: "circle.fill")
                                    .foregroundStyle(item.color)
                            }
                            .tag(item)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                if task != nil {
                    Section {
                        Button("删除任务", role: .destructive) {
                            showsDeleteConfirmation = true
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(task == nil ? "新建任务" : "编辑任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(trimmedTitle.isEmpty)
                }
            }
            .confirmationDialog(
                "删除“\(task?.title ?? "")”？",
                isPresented: $showsDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("删除任务", role: .destructive) {
                    if let task { store.deleteTask(task) }
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            }
        }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard !trimmedTitle.isEmpty else { return }
        if let task {
            store.updateTask(
                task,
                title: trimmedTitle,
                description: taskDescription,
                importance: importance,
                urgency: urgency,
                area: area
            )
        } else {
            store.addTask(
                title: trimmedTitle,
                description: taskDescription,
                importance: importance,
                urgency: urgency,
                area: area
            )
        }
        dismiss()
    }
}
