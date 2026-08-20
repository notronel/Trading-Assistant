import SwiftUI

struct MenuContentView: View {
    @ObservedObject var coordinator: AppCoordinator
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ChartScout")
                    .font(.headline)
                Spacer()
                Button(action: coordinator.showSettings) {
                    Label("Settings", systemImage: "gearshape")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .help("Open ChartScout settings")
            }
            Text(coordinator.status).font(.caption).foregroundStyle(.secondary)
            Button("Analyze active Chrome chart", action: coordinator.startCapture).keyboardShortcut(" ", modifiers: [.command, .shift])
            Button("Open journal") { openWindow(id: "journal") }
            Divider()
            Text("Informational analysis only — not financial advice.").font(.caption2).foregroundStyle(.secondary)
            Button("Quit ChartScout") { NSApplication.shared.terminate(nil) }
        }.padding().frame(width: 270)
    }
}

struct SettingsView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var apiKey = ""
    @State private var saved = false
    var body: some View {
        Form {
            Section("Permissions") {
                LabeledContent("Screen Recording", value: coordinator.permissions.screenRecording ? "Allowed" : "Required")
                LabeledContent("Accessibility", value: coordinator.permissions.accessibility ? "Allowed" : "Required")
                Button("Request permissions") { coordinator.requestPermissions() }
                Button("Open Screen Recording Settings", action: PermissionState.openScreenRecordingSettings)
                Button("Refresh permission status", action: coordinator.refreshPermissions)
            }
            Section("Analysis") {
                SecureField("OpenAI API key", text: $apiKey)
                TextField("Model", text: Binding(
                    get: { coordinator.settings.model },
                    set: { coordinator.settings.model = $0 }
                ))
                Button("Save API key") { try? coordinator.settings.saveAPIKey(apiKey); saved = true }
                if saved { Text("Saved securely in Keychain.").font(.caption).foregroundStyle(.green) }
            }
            Section("Shortcut") {
                Picker("Analyze active Chrome chart", selection: Binding(
                    get: { coordinator.settings.shortcut },
                    set: { coordinator.settings.shortcut = $0 }
                )) {
                    ForEach(ShortcutChoice.allCases) { Text($0.title).tag($0) }
                }
            }
            Section { Text("Charts are sent to the selected cloud model only when you activate analysis. Recommendations are advisory, may misread visual data, and do not place orders.").font(.caption).foregroundStyle(.secondary) }
        }.padding().frame(width: 460)
    }
}

struct JournalView: View {
    @ObservedObject var store: JournalStore
    var body: some View {
        List {
            ForEach(store.entries) { entry in
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(entry.metadata.symbol) · \(entry.metadata.timeframe) · \(entry.recommendation.bias.title)").font(.headline)
                    Text(entry.createdAt, format: .dateTime.month().day().hour().minute())
                    Text(entry.recommendation.rationale).font(.caption).foregroundStyle(.secondary)
                    TextField("Outcome note", text: Binding(get: { entry.outcomeNote }, set: { store.update(entry, note: $0) }))
                }.padding(.vertical, 4)
            }.onDelete(perform: store.delete)
        }.toolbar { Button("Delete all", role: .destructive, action: store.deleteAll).disabled(store.entries.isEmpty) }
        .overlay { if store.entries.isEmpty { ContentUnavailableView("No saved analyses", systemImage: "book.closed", description: Text("Completed analyses will appear here.")) } }
        .frame(minWidth: 620, minHeight: 420)
    }
}
