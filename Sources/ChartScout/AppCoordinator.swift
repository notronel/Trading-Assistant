import AppKit
import Combine
import SwiftUI

@MainActor
final class AppCoordinator: ObservableObject {
    @Published var status = "Ready"
    @Published var permissions = PermissionState.current()
    let settings = AppSettings()
    let journalStore = JournalStore()
    private let overlay = OverlayController()
    private let hotKey = GlobalHotKey()
    private let capture = ChromeCaptureService()
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    init() {
        hotKey.onPress = { [weak self] in Task { @MainActor in self?.startCapture() } }
        hotKey.register(shortcut: settings.shortcut)
        settings.$shortcut.sink { [weak self] choice in self?.hotKey.register(shortcut: choice) }.store(in: &cancellables)
    }

    func requestPermissions() {
        PermissionState.requestScreenRecording()
        PermissionState.requestAccessibility()
        refreshPermissions()
    }

    func refreshPermissions() {
        permissions = .current()
    }

    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 520),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "ChartScout Settings"
            window.contentView = NSHostingView(rootView: SettingsView(coordinator: self))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }

        status = "Settings opened"
        NSApplication.shared.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
    }

    func startCapture() {
        Task {
            await startCapture(isPermissionRetry: false)
        }
    }

    private func startCapture(isPermissionRetry: Bool) async {
        refreshPermissions()
        guard settings.hasAPIKey else {
            status = "Add an API key in Settings first"
            overlay.showError(status)
            return
        }
        do {
            status = "Capturing Chrome…"
            let image = try await capture.captureActiveChromeChart()
            guard let imageData = image.pngData() else {
                overlay.showError("Could not prepare the captured chart image.")
                return
            }
            let service = VisionAnalysisService(apiKey: settings.apiKey ?? "", model: settings.model)
            overlay.showMetadata(image: image, initial: .init(symbol: "", timeframe: "")) { [weak self] metadata in
                self?.analyze(image: image, metadata: metadata)
            }
            Task { [weak self, service, imageData] in
                let result = try? await service.readMetadata(imageData: imageData)
                guard let result else { return }
                self?.applyDetectedMetadata(result)
            }
        } catch CaptureError.captureFailed {
            if isPermissionRetry {
                status = "macOS is still denying screen capture for this ChartScout build. Remove the old ChartScout entry in Screen & System Audio Recording, add this build again, then quit and reopen ChartScout."
                overlay.showError(status)
            } else {
                status = "Screen Recording permission is required"
                PermissionState.requestScreenRecording()
                overlay.showPermissionRequired { [weak self] in
                    Task {
                        await self?.startCapture(isPermissionRetry: true)
                    }
                }
            }
        } catch {
            status = error.localizedDescription
            overlay.showError(status)
        }
    }

    private func applyDetectedMetadata(_ metadata: ChartMetadata) {
        overlay.updateMetadata(metadata)
    }

    private func analyze(image: NSImage, metadata: ChartMetadata) {
        guard !metadata.symbol.trimmingCharacters(in: .whitespaces).isEmpty,
              !metadata.timeframe.trimmingCharacters(in: .whitespaces).isEmpty,
              let imageData = image.pngData() else {
            overlay.showError("Contract and timeframe are required.")
            return
        }
        overlay.showLoading()
        status = "Analyzing \(metadata.symbol)…"
        let service = VisionAnalysisService(apiKey: settings.apiKey ?? "", model: settings.model)
        Task { [weak self, service, imageData, metadata] in
            do {
                let recommendation = try await service.analyze(imageData: imageData, metadata: metadata)
                guard let self else { return }
                self.completeAnalysis(recommendation, metadata: metadata, imageData: imageData)
            } catch {
                guard let self else { return }
                self.failAnalysis(error.localizedDescription, image: image, metadata: metadata)
            }
        }
    }

    private func completeAnalysis(_ recommendation: TradeRecommendation, metadata: ChartMetadata, imageData: Data) {
        journalStore.add(.init(id: UUID(), createdAt: .now, metadata: metadata, recommendation: recommendation, imageData: imageData, outcomeNote: ""))
        overlay.showRecommendation(recommendation)
        status = "Analysis complete"
    }

    private func failAnalysis(_ message: String, image: NSImage, metadata: ChartMetadata) {
        status = message
        overlay.showError(message, retry: { [weak self, image] in self?.analyze(image: image, metadata: metadata) })
    }
}
