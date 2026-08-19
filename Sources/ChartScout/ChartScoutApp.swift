import SwiftUI

@main
struct ChartScoutApp: App {
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra("ChartScout", systemImage: "scope") {
            MenuContentView(coordinator: coordinator)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(coordinator: coordinator)
        }

        Window("ChartScout Journal", id: "journal") {
            JournalView(store: coordinator.journalStore)
        }
    }
}
