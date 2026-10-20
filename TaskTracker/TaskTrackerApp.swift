import SwiftUI

@main
struct TaskTrackerApp: App {
    @StateObject private var store = TaskStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .onAppear {
                    store.startAutomaticDailyRefresh()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        store.startAutomaticDailyRefresh()
                    } else {
                        store.stopAutomaticDailyRefresh()
                    }
                }
                .alert(
                    "本地数据错误",
                    isPresented: Binding(
                        get: { store.errorMessage != nil },
                        set: { isPresented in
                            if !isPresented { store.errorMessage = nil }
                        }
                    )
                ) {
                    Button("知道了", role: .cancel) {}
                } message: {
                    Text(store.errorMessage ?? "")
                }
        }
    }
}
