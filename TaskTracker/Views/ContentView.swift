import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            TaskBoardView()
                .tabItem {
                    Label("Task", systemImage: "checklist")
                }

            WatchLaterView()
                .tabItem {
                    Label("BookMark", systemImage: "bookmark")
                }

            TaskBankView()
                .tabItem {
                    Label("TaskBank", systemImage: "archivebox")
                }
        }
        .tint(AppTheme.accent)
    }
}
