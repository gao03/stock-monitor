import AppKit
import SwiftUI

@MainActor
final class StatusBarController {
    private let appState: AppState
    private let statusItem: NSStatusItem
    private let panelSize = NSSize(width: 360, height: 360)
    private var panel: StatusPanel?
    private var popoverPresentationID = UUID()
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var titleUpdateTasks: [Task<Void, Never>] = []

    init(appState: AppState) {
        self.appState = appState
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    }

    func start() {
        configureStatusItem()
        configurePanel()
        updateTitle()
        appState.startRefreshing()
        startTitleUpdates()
    }

    func stop() {
        stopTitleUpdates()
        closePanel()
        removeEventMonitors()
        appState.stopRefreshing()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func startTitleUpdates() {
        stopTitleUpdates()
        titleUpdateTasks = [
            Task { [weak self] in
                guard let self else { return }
                for await _ in self.appState.$quotes.values {
                    if Task.isCancelled { return }
                    self.updateTitle()
                }
            },
            Task { [weak self] in
                guard let self else { return }
                for await _ in self.appState.$stocks.values {
                    if Task.isCancelled { return }
                    self.updateTitle()
                }
            },
            Task { [weak self] in
                guard let self else { return }
                for await _ in self.appState.$settings.values {
                    if Task.isCancelled { return }
                    self.updateTitle()
                }
            }
        ]
    }

    private func stopTitleUpdates() {
        titleUpdateTasks.forEach { $0.cancel() }
        titleUpdateTasks = []
    }

    private func updateTitle() {
        let titleStocks = appState.stocks.filter(\.showInTitle)
        let visibleItems = titleStocks.prefix(6).map { stock -> TitleItem in
            guard let quote = appState.quotes[stock.symbol.cacheKey] else {
                return TitleItem(text: "--", color: titleSecondaryColor)
            }
            return TitleItem(
                text: quote.price.formattedPrice,
                color: titleColor(for: quote.changePercent)
            )
        }

        guard !visibleItems.isEmpty else {
            statusItem.button?.attributedTitle = statusTitle(
                rows: [
                    [TitleItem(text: "Stock", color: titleNeutralColor)],
                    [TitleItem(text: "Monitor", color: titleSecondaryColor)]
                ]
            )
            return
        }

        if visibleItems.count == 1 {
            statusItem.button?.attributedTitle = statusTitle(rows: [[visibleItems[0]], []])
            return
        }

        let firstRowCount = min(3, max(1, (visibleItems.count + 1) / 2))
        var firstRow = Array(visibleItems.prefix(firstRowCount))
        var secondRow = Array(visibleItems.dropFirst(firstRowCount))
        if secondRow.isEmpty, firstRow.count > 1 {
            secondRow = Array(firstRow.dropFirst())
            firstRow = Array(firstRow.prefix(1))
        }
        statusItem.button?.attributedTitle = statusTitle(rows: [firstRow, secondRow])
    }

    private func statusTitle(rows: [[TitleItem]]) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.minimumLineHeight = 10.8
        paragraph.maximumLineHeight = 10.8
        paragraph.lineSpacing = 1.2

        let result = NSMutableAttributedString()
        for (rowIndex, row) in rows.enumerated() {
            if rowIndex > 0 {
                result.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: paragraph]))
            }
            for (itemIndex, item) in row.enumerated() {
                if itemIndex > 0 {
                    result.append(NSAttributedString(string: "  ", attributes: [.paragraphStyle: paragraph]))
                }
                result.append(
                    NSAttributedString(
                        string: item.text,
                        attributes: [
                            .foregroundColor: item.color,
                            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .light),
                            .paragraphStyle: paragraph,
                            .baselineOffset: -5
                        ]
                    )
                )
            }
        }
        return result
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp])
        button.imagePosition = .noImage

        if let cell = button.cell as? NSButtonCell {
            cell.alignment = .center
            cell.lineBreakMode = .byTruncatingTail
            cell.wraps = true
        }
    }

    private func configurePanel() {
        let panel = StatusPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .default
        panel.collectionBehavior = [.moveToActiveSpace, .transient, .ignoresCycle]
        self.panel = panel
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if panel?.isVisible == true {
            closePanel()
            return
        }
        showPanel()
    }

    private func showPanel() {
        guard let panel, let button = statusItem.button else { return }
        popoverPresentationID = UUID()
        panel.contentViewController = nil
        panel.contentViewController = NSHostingController(rootView: makePopoverView())
        panel.setFrame(panelFrame(relativeTo: button), display: true)
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.setIsVisible(true)
        panel.makeKeyAndOrderFront(nil)
        installEventMonitors()
    }

    private func closePanel() {
        panel?.orderOut(nil)
        panel?.contentViewController = nil
        removeEventMonitors()
    }

    private func panelFrame(relativeTo button: NSStatusBarButton) -> NSRect {
        guard let buttonWindow = button.window else {
            return NSRect(origin: .zero, size: panelSize)
        }

        let buttonWindowFrame = buttonWindow.frame
        let screen = NSScreen.screens.first { $0.frame.intersects(buttonWindowFrame) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? buttonWindow.screen?.visibleFrame ?? buttonWindowFrame

        let x = min(
            max(buttonWindowFrame.midX - panelSize.width / 2, visibleFrame.minX + 8),
            visibleFrame.maxX - panelSize.width - 8
        )
        let y = buttonWindowFrame.minY - panelSize.height - 2
        return NSRect(x: x, y: y, width: panelSize.width, height: panelSize.height)
    }

    private func makePopoverView() -> MenuBarPopoverView {
        MenuBarPopoverView(
            presentationID: popoverPresentationID,
            appState: appState,
            refresh: { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    await self.appState.refreshOnce()
                }
            },
            quit: {
                NSApp.terminate(nil)
            },
            openStock: { symbol in
                NSWorkspace.shared.open(XueqiuURLBuilder.url(for: symbol))
            }
        )
    }

    private func installEventMonitors() {
        removeEventMonitors()
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            if !self.isEventWindowPartOfPopover(event.window, panel: panel) {
                self.closePanel()
            }
            return event
        }
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.closePanel()
            }
        }
    }

    private func isEventWindowPartOfPopover(_ eventWindow: NSWindow?, panel: NSWindow) -> Bool {
        guard let eventWindow else { return false }
        if eventWindow === panel { return true }
        if eventWindow === statusItem.button?.window { return true }
        if eventWindow === panel.attachedSheet { return true }
        if panel.childWindows?.contains(where: { $0 === eventWindow }) == true { return true }

        var parent = eventWindow.parent
        while let currentParent = parent {
            if currentParent === panel { return true }
            parent = currentParent.parent
        }

        var sheetParent = eventWindow.sheetParent
        while let currentSheetParent = sheetParent {
            if currentSheetParent === panel { return true }
            sheetParent = currentSheetParent.sheetParent
        }

        return false
    }

    private func removeEventMonitors() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
    }

    private func titleColor(for changePercent: Decimal) -> NSColor {
        switch appState.settings.statusBarTextColorMode {
        case .black:
            return .black
        case .redUpGreenDown:
            if changePercent > 0 { return .systemRed }
            if changePercent < 0 { return .systemGreen }
        case .greenUpRedDown:
            if changePercent > 0 { return .systemGreen }
            if changePercent < 0 { return .systemRed }
        }
        return .labelColor
    }

    private var titleNeutralColor: NSColor {
        appState.settings.statusBarTextColorMode == .black ? .black : .labelColor
    }

    private var titleSecondaryColor: NSColor {
        appState.settings.statusBarTextColorMode == .black ? .black : .secondaryLabelColor
    }

    private struct TitleItem {
        let text: String
        let color: NSColor
    }
}

private final class StatusPanel: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
