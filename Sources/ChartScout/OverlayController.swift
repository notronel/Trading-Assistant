import AppKit
import SwiftUI

private final class InteractivePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class WindowDragView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

private struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowDragView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private extension View {
    @ViewBuilder
    func chartScoutGlassBackground() -> some View {
        if #available(macOS 27.0, *) {
            glassEffect(.regular, in: .rect(cornerRadius: 16))
        } else {
            background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

@MainActor
final class OverlayController: ObservableObject {
    private let state = OverlayState()
    private var cursorTimer: Timer?
    private lazy var panel: NSPanel = {
        let panel = InteractivePanel(contentRect: .init(x: 0, y: 0, width: 440, height: 240), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .floating; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.ignoresMouseEvents = false
        panel.contentView = NSHostingView(rootView: OverlayView(state: state))
        return panel
    }()
    private lazy var dotPanel: NSPanel = {
        let panel = NSPanel(contentRect: .init(x: 0, y: 0, width: 44, height: 44), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: PulsingDotView())
        return panel
    }()
    init() {
        state.dismiss = { [weak self] in self?.hide() }
        dotPanel.orderFrontRegardless()
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.moveDot() }
        }
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { Task { @MainActor in self?.hide() } }
        }
    }
    func showMetadata(image: NSImage, initial: ChartMetadata, onConfirm: @escaping (ChartMetadata) -> Void) {
        state.mode = .metadata(initial, onConfirm); show(at: NSEvent.mouseLocation)
    }
    func updateMetadata(_ metadata: ChartMetadata) { if case .metadata(_, let completion) = state.mode { state.mode = .metadata(metadata, completion) } }
    func showLoading() { state.mode = .loading; show(at: NSEvent.mouseLocation) }
    func showRecommendation(_ recommendation: TradeRecommendation, onReanalyze: @escaping () -> Void) {
        state.mode = .recommendation(recommendation, onReanalyze)
        show(at: NSEvent.mouseLocation)
    }
    func showError(_ message: String, retry: (() -> Void)? = nil) { state.mode = .error(message, retry); show(at: NSEvent.mouseLocation) }
    func showPermissionRequired(onCheck: @escaping () -> Void) { state.mode = .permissionRequired(onCheck); show(at: NSEvent.mouseLocation) }
    private func show(at point: NSPoint) {
        let wasVisible = panel.isVisible
        panel.orderFrontRegardless()
        panel.makeKey()

        Task { @MainActor [weak self] in
            await Task.yield()
            self?.resizePanelToFit(near: point, preservingPosition: wasVisible)
        }
    }

    private func resizePanelToFit(near point: NSPoint, preservingPosition: Bool) {
        guard let contentView = panel.contentView else { return }

        contentView.layoutSubtreeIfNeeded()
        let visibleFrame = NSScreen.screens.first(where: { $0.frame.contains(point) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? .init(x: 0, y: 0, width: 1_440, height: 900)
        let margin: CGFloat = 16
        let availableSize = NSSize(
            width: max(320, visibleFrame.width - margin * 2),
            height: max(160, visibleFrame.height - margin * 2)
        )
        let fittingSize = contentView.fittingSize
        let panelSize = NSSize(
            width: min(max(fittingSize.width, 440), availableSize.width),
            height: min(max(fittingSize.height, 120), availableSize.height)
        )

        let proposedOrigin: NSPoint
        if preservingPosition {
            proposedOrigin = .init(x: panel.frame.minX, y: panel.frame.maxY - panelSize.height)
        } else {
            proposedOrigin = .init(x: point.x + 14, y: point.y - panelSize.height - 14)
        }
        let origin = NSPoint(
            x: min(max(proposedOrigin.x, visibleFrame.minX + margin), visibleFrame.maxX - panelSize.width - margin),
            y: min(max(proposedOrigin.y, visibleFrame.minY + margin), visibleFrame.maxY - panelSize.height - margin)
        )
        panel.setFrame(.init(origin: origin, size: panelSize), display: true, animate: preservingPosition)
    }

    private func hide() { panel.orderOut(nil) }
    private func moveDot() { let point = NSEvent.mouseLocation; dotPanel.setFrameOrigin(.init(x: point.x + 12, y: point.y - 12)) }
}

struct PulsingDotView: View {
    @State private var pulse = false
    var body: some View {
        Circle().fill(.cyan).frame(width: 9, height: 9).shadow(color: .cyan.opacity(0.9), radius: pulse ? 8 : 2)
            .scaleEffect(pulse ? 1.2 : 0.8).frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) { pulse = true } }
    }
}

@MainActor final class OverlayState: ObservableObject {
    enum Mode { case metadata(ChartMetadata, (ChartMetadata) -> Void), loading, recommendation(TradeRecommendation, () -> Void), error(String, (() -> Void)?), permissionRequired(() -> Void) }
    @Published var mode: Mode = .loading
    var dismiss: () -> Void = {}
}

struct OverlayView: View {
    @ObservedObject var state: OverlayState
    @State private var symbol = ""; @State private var timeframe = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 20)
                    .overlay(WindowDragRegion())
                    .accessibilityHidden(true)
                    .help("Drag to move ChartScout")
                Spacer()
                Button(action: state.dismiss) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Close ChartScout")
            }
            switch state.mode {
            case .loading: ProgressView("Analyzing chart…").frame(width: 300, height: 90)
            case .metadata(let metadata, let confirm):
                Text("Confirm chart context").font(.headline)
                TextField("Contract", text: $symbol).onAppear { symbol = metadata.symbol }.onChange(of: metadata.symbol) { _, value in symbol = value }
                TextField("Timeframe", text: $timeframe).onAppear { timeframe = metadata.timeframe }.onChange(of: metadata.timeframe) { _, value in timeframe = value }
                Button("Analyze chart") { confirm(.init(symbol: symbol, timeframe: timeframe)) }.buttonStyle(.borderedProminent)
            case .recommendation(let recommendation, let reanalyze):
                RecommendationCard(recommendation: recommendation, onReanalyze: reanalyze)
            case .error(let message, let retry):
                Text("ChartScout").font(.headline); Text(message).foregroundStyle(.secondary)
                if let retry { Button("Try again", action: retry) }
            case .permissionRequired(let checkPermission):
                Text("Screen Recording required").font(.headline)
                Text("Allow ChartScout under Screen Recording, then come back here to continue.").foregroundStyle(.secondary)
                HStack {
                    Button("Open System Settings", action: PermissionState.openScreenRecordingSettings)
                    Button("I granted access", action: checkPermission).buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(16)
        .frame(width: 440)
        .fixedSize(horizontal: true, vertical: true)
        .chartScoutGlassBackground()
    }
}

struct RecommendationCard: View {
    let recommendation: TradeRecommendation
    let onReanalyze: () -> Void

    var color: Color { recommendation.bias == .bullish ? .green : .red }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(recommendation.bias.title)
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(color)
                Spacer()
                Text("\(recommendation.confidence)% confidence")
                    .font(.system(size: 14, weight: .bold))
            }
            if recommendation.isLowConfidence {
                Label("Low confidence — verify before acting", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                GridRow { Text("Entry"); Text(recommendation.entryText).bold() }
                GridRow { Text("Stop"); Text(PriceFormatter.string(recommendation.stop)) }
                GridRow { Text("Target 1 / 2"); Text("\(PriceFormatter.string(recommendation.target1)) / \(PriceFormatter.string(recommendation.target2))") }
            }
            .font(.system(size: 14))
            Text(recommendation.pattern)
                .font(.system(size: 14, weight: .bold))
            Text(recommendation.rationale)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Text("Invalidation: \(recommendation.invalidation)")
                .font(.system(size: 14))
                .foregroundStyle(.orange)
            Button("Reanalyze", systemImage: "arrow.clockwise", action: onReanalyze)
                .buttonStyle(.borderedProminent)
        }
    }
}
