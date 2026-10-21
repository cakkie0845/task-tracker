# Task Tracker

一个完全在 iPhone / iPad 本地运行的 SwiftUI 任务管理器。首版按照 `task_tracker_documentation.rtf` 实现。

## 已实现

- 本地 JSON 持久化，不依赖账号、服务器或网络
- 每个任务包含标题、描述、完成状态、重要性、紧急性和任务区域
- 长期任务可设置或留空截止时间；卡片按“日期，周几，时间”显示
- 每日任务也可设置或留空截止时间；仅保存和显示时间（如 `17:30`），不包含日期或周几
- 任务卡片右侧可切换完成状态：绿色勾表示已完成，浅灰色实心圆表示未完成
- 新建、编辑、删除任务；任务可在“每日”和“长期”区域间移动
- 长按任务卡片可在“每日”和“长期”区域间移动
- 长期任务在上方并可收起；每日任务在下方，任务较多时可滚动浏览
- 两个区域均可置顶任意数量的任务；在任务上右滑或长按可置顶／取消置顶
- 重要性颜色：高度重要（红）、中等重要（黄）、不重要（绿）
- 紧急性颜色：特急（紫）、紧急（橙）、不急（蓝）
- 每日任务在手机本地时间凌晨 4:00 更新；若应用当时未运行，会在下次打开或进入前台时补做更新。从长期区移入每日区但尚未完成的任务会返回长期区
- 长期任务区域可一次归档所有已完成任务，未完成任务保持不动
- Task Bank 分为长期任务和每日任务；有每日归档时自动展开最近的年 → 月 → 周，再点日期查看任务
- 每日归档在月、周、天行的「⋯」中批量删除或导出 UTF-8 CSV；长按任一归档任务卡片可单项导出或删除，长期归档顶部还可批量操作
- 针对跨日归档、范围删除和 CSV 导出提供单元测试

## 用 VS Code 测试：从零开始

你可以一直在 VS Code 中编写代码和启动测试。Task Tracker 是原生 iOS App，因此电脑上仍需安装 Xcode：VS Code 会调用 Xcode 提供的 iOS 编译器和模拟器。

### 第一次运行前

1. 确认你使用的是 Mac，已安装 VS Code、Xcode 16 或更新版本，以及一个 iOS 模拟器运行时。如果从未打开过 Xcode，先打开一次并完成它要求的初始设置。
2. 在 VS Code 中选择「文件 → 打开文件夹…」，打开整个 `/Users/wang/tasktracker` 文件夹。不要只打开某个 `.swift` 文件。左侧文件列表应能看到 `TaskTracker`、`TaskTrackerTests` 和 `.vscode` 文件夹。
3. 在 VS Code 中选择「终端 → 新建终端」，输入 `xcodebuild -version` 并回车。看到 Xcode 版本号，就说明编译工具已准备好。

### 运行自动测试

1. 按 `⌘⇧P` 打开 VS Code 命令面板。
2. 输入 `Tasks: Run Task` 并选中它。如果 VS Code 使用中文界面，可以搜索「运行任务」。
3. 选择 `Task Tracker: 运行测试`。
4. 底部终端会自动出现。首次运行需要编译 App 并启动 iPhone 模拟器，可能比后续运行慢。等到终端出现「自动测试通过。」即表示成功。

当前自动测试会检查任务状态、长期任务归档、跨区域移动后的跨日规则、每日任务归档、按月份批量删除，以及 CSV 导出内容。如果测试失败，VS Code 终端会显示错误信息，任务也会以非零退出码结束。

你也可以直接在 VS Code 终端中输入：

```sh
./Scripts/dev.sh test
```

### 在模拟器中手动测试界面

仍按 `⌘⇧P` → `Tasks: Run Task`，这次选择 `Task Tracker: 运行 iOS 模拟器版`。任务会构建 App、打开 iPhone 模拟器、安装并启动 Task Tracker。看到「已在 iPhone 模拟器启动 Task Tracker。」后，就可以在模拟器中点按界面，例如新建、编辑、删除任务，或打开 Task Bank。

在 VS Code 终端中执行相同操作的命令是：

```sh
./Scripts/dev.sh run
```

如果只想检查代码能否编译，按 `⌘⇧B`，或者运行任务 `Task Tracker: 构建 iOS 模拟器版`。构建不会执行自动测试，也不会打开 App。

### 常见问题

- 终端提示找不到 `xcodebuild`，或 `xcodebuild -version` 未显示版本号：检查 Xcode 是否已安装并完成首次启动设置。
- 提示 `No available iPhone Simulator`：在 Xcode 中安装一个 iOS 模拟器运行时，然后重试。
- 想指定模拟器机型：在启动 VS Code 的环境中设置 `TASKTRACKER_SIMULATOR_NAME`，值必须与已安装模拟器的名称完全一致，例如 `iPhone 16 Pro`。不设置时，任务优先选已启动的 iPhone 模拟器，否则选第一个可用的 iPhone 模拟器。
- 想在真机运行：真机需要 Apple 代码签名。可以用 Xcode 打开 `TaskTracker.xcodeproj` 配置签名；日常编辑仍可回到 VS Code。

编译结果保存在项目的 `.build/DerivedData` 文件夹中，不需要手动修改。

本地数据保存在应用沙盒的 `Application Support/TaskTracker/task-data.json`。卸载 App 会同时删除这份本地数据；重要历史记录可以先在 Task Bank 中导出 CSV。
# task-tracker
