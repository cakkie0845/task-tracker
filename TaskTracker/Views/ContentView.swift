import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            TaskBoardView()
                .tabItem {
                    Label("任务", systemImage: "checklist")
                }

            TaskBankView()
                .tabItem {
                    Label("Task Bank", systemImage: "archivebox")
                }
        }
        .tint(AppTheme.accent)
    }
}
