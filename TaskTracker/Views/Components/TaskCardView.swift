import SwiftUI

struct TaskCardView: View {
    let task: TaskItem
    var showsArea = false
    var onOpen: (() -> Void)? = nil
    var onToggleState: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let onOpen {
                Button(action: onOpen) {
                    taskDetails
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开任务：\(task.title)")
            } else {
                taskDetails
            }

            if let onToggleState {
                Button(action: onToggleState) {
                    TaskStateIndicator(state: task.state)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    task.state == .accomplished ? "标记为未完成" : "标记为已完成"
                )
            } else {
                TaskStateIndicator(state: task.state)
                    .accessibilityLabel(task.state.title)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
    }

    private var taskDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(task.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if task.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("已置顶")
                }

                if showsArea {
                    Text(task.area.shortTitle)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                }
            }

            if !task.taskDescription.isEmpty {
                Text(task.taskDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if task.area == .longTerm, let deadline = task.deadline {
                Label(TaskDeadlineFormatter.string(from: deadline), systemImage: "calendar.badge.clock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if task.area == .daily, let deadline = task.dailyDeadlineTime {
                Label(deadline.displayString, systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                TaskTagView(
                    title: task.importance.title,
                    symbol: task.importance.symbol,
                    color: task.importance.color
                )
                TaskTagView(
                    title: task.urgency.title,
                    symbol: task.urgency.symbol,
                    color: task.urgency.color
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct TaskStateIndicator: View {
    let state: TaskState

    var body: some View {
        ZStack {
            if state == .accomplished {
                Circle()
                    .fill(.green)
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Circle()
                    .fill(.gray.opacity(0.32))
            }
        }
        .frame(width: 28, height: 28)
        .contentShape(Circle())
    }
}
