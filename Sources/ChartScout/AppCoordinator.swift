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
    private var cancellables = Set<AnyCancellable>()

    init() {
        hotKey.onPress = { [weak self] in Task { @MainActor in self?.startCapture() } }
        hotKey.register(shortcut: settings.shortcut)
        settings.$shortcut.sink { [weak self] choice in self?.hotKey.register(shortcut: choice) }.store(in: &cancellables)
    }

    func requestPermissions() {
        PermissionState.requestScreenRecording()
        PermissionState.requestAccessibility()
        permissions = .current()
    }

    func startCapture() {
        guard permissions.screenRecording else {
            status = "Screen Recording permission is required"
            overlay.showError(status)
            return
        }
        guard settings.hasAPIKey else {
            status = "Add an API key in Settings first"
            overlay.showError(status)
            return
        }
        do {
            status = "Capturing Chrome…"
            let image = try capture.captureActiveChromeChart()
            overlay.showMetadata(image: image, initial: .init(symbol: "", timeframe: "")) { [weak self] metadata in
                self?.analyze(image: image, metadata: metadata)
            }
            Task { await detectMetadata(for: image) }
        } catch {
            status = error.localizedDescription
            overlay.showError(status)
        }
    }

    private func detectMetadata(for image: NSImage) async {
        guard let imageData = image.pngData() else { return }
        do {
            let result = try await VisionAnalysisService(settings: settings).readMetadata(imageData: imageData)
            overlay.updateMetadata(result)
        } catch {
            status = "Could not read chart metadata; enter it manually."
        }
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
        Task {
            do {
                let recommendation = try await VisionAnalysisService(settings: settings).analyze(imageData: imageData, metadata: metadata)
                journalStore.add(.init(id: UUID(), createdAt: .now, metadata: metadata, recommendation: recommendation, imageData: imageData, outcomeNote: ""))
                overlay.showRecommendation(recommendation)
                status = "Analysis complete"
            } catch {
                status = error.localizedDescription
                overlay.showError(status, retry: { [weak self] in self?.analyze(image: image, metadata: metadata) })
            }
        }
    }
}
