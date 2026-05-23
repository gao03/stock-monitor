import AppKit
import SwiftUI

struct MenuBarPopoverView: View {
    @ObservedObject var appState: AppState
    let openSettings: () -> Void
    let refresh: () -> Void
    let quit: () -> Void
    let openStock: (StockSymbol) -> Void

    @State private var ruleTarget: RuleTarget?
    @State private var actionStockID: StockConfig.ID?
    @State private var selectedTab: PopoverTab = .quotes

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()

            PanelPalette.backgroundTint
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Group {
                    switch selectedTab {
                    case .quotes:
                        stockList
                    case .settings:
                        PopoverSettingsView(
                            appState: appState,
                            editRules: { stock in
                                ruleTarget = RuleTarget(stock: stock)
                            },
                            deleteStock: deleteStock
                        )
                    }
                }

                footer
                    .padding(.horizontal, 12)
                    .padding(.top, 5)
                    .padding(.bottom, 5)
                    .background(PanelPalette.footer)
            }
        }
        .frame(width: 360, height: 360)
        .background(Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(PanelPalette.panelBorder, lineWidth: 1)
        }
        .foregroundStyle(PanelPalette.primaryText)
        .sheet(item: $ruleTarget) { target in
            EditMonitorRuleSheet(
                stock: target.stock,
                saveRules: { rules in
                    updateRules(rules, for: target.stock)
                }
            )
        }
    }

    private var stockList: some View {
        ScrollView {
            LazyVStack(spacing: 7) {
                if appState.stocks.isEmpty {
                    EmptyPopoverState()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 72)
                } else {
                    ForEach(appState.stocks) { stock in
                        let isExpanded = actionStockID == stock.id
                        VStack(spacing: 0) {
                            PopoverStockRow(
                                stock: stock,
                                quote: appState.quotes[stock.symbol.cacheKey]
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeOut(duration: 0.12)) {
                                    actionStockID = actionStockID == stock.id ? nil : stock.id
                                }
                            }

                            if isExpanded {
                                PopoverStockActions(
                                    stock: stock,
                                    quote: appState.quotes[stock.symbol.cacheKey],
                                    open: {
                                        openStock(stock.symbol)
                                    },
                                    toggleMenuBar: {
                                        toggleMenuBarDisplay(for: stock)
                                    },
                                    editRules: {
                                        ruleTarget = RuleTarget(stock: stock)
                                    },
                                    deleteStock: {
                                        deleteStock(stock)
                                    }
                                )
                            }
                        }
                        .background {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(PanelPalette.sectionBackground(isExpanded: isExpanded))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(PanelPalette.sectionBorder(isExpanded: isExpanded), lineWidth: 1)
                        }
                        .padding(.horizontal, 8)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .background(PanelPalette.listBackground)
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Text(updateStatus)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(statusColor)
                .lineLimit(1)

            Spacer(minLength: 8)

            footerTabButton(.quotes, title: "行情", systemImage: "chart.line.uptrend.xyaxis")
            footerTabButton(.settings, title: "配置", systemImage: "gearshape")
            footerButton("刷新", systemImage: "arrow.clockwise", action: refresh)
            footerButton("退出", systemImage: "power", action: quit)
        }
    }

    private var updateStatus: String {
        if let lastErrorMessage = appState.lastErrorMessage, !lastErrorMessage.isEmpty {
            return "更新失败: \(lastErrorMessage)"
        }
        if let lastRefresh = appState.lastRefresh {
            return formattedFooterTime(lastRefresh)
        }
        return "等待更新"
    }

    private func formattedFooterTime(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return String(
            format: "%02d:%02d:%02d",
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0
        )
    }

    private var statusColor: Color {
        if appState.lastErrorMessage?.isEmpty == false {
            return PanelPalette.upText.opacity(0.95)
        }
        return PanelPalette.secondaryText
    }

    private func footerTabButton(_ tab: PopoverTab, title: String, systemImage: String) -> some View {
        footerButton(title, systemImage: systemImage, isActive: selectedTab == tab) {
            withAnimation(.easeOut(duration: 0.14)) {
                selectedTab = tab
                actionStockID = nil
            }
        }
    }

    private func footerButton(
        _ title: String,
        systemImage: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(PopoverFooterButtonStyle(isActive: isActive))
        .focusable(false)
        .help(title)
        .accessibilityLabel(Text(title))
    }

    private func toggleMenuBarDisplay(for stock: StockConfig) {
        guard var current = appState.stocks.first(where: { $0.id == stock.id }) else { return }
        current.showInTitle = !(current.showInTitle ?? false)
        appState.updateStock(current)
    }

    private func updateRules(_ rules: [MonitorRule], for stock: StockConfig) {
        guard var current = appState.stocks.first(where: { $0.id == stock.id }) else { return }
        current.monitorRules = rules
        appState.updateStock(current)
    }

    private func deleteStock(_ stock: StockConfig) {
        appState.selectedStockID = stock.id
        appState.deleteSelectedStock()
    }

    private struct RuleTarget: Identifiable {
        let stock: StockConfig
        var id: StockConfig.ID { stock.id }
    }

    private enum PopoverTab {
        case quotes
        case settings
    }
}

private struct MonitorRuleInputParser {
    static func parse(_ text: String) -> (rules: [MonitorRule], invalidRules: [String]) {
        let rawRules = text
            .replacingOccurrences(of: "\n", with: "/")
            .replacingOccurrences(of: "，", with: "/")
            .replacingOccurrences(of: ",", with: "/")
            .replacingOccurrences(of: "、", with: "/")
            .replacingOccurrences(of: ";", with: "/")
            .replacingOccurrences(of: "；", with: "/")
            .split(separator: "/")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let engine = MonitorRuleEngine()
        var seenRules = Set<String>()
        var rules: [MonitorRule] = []
        var invalidRules: [String] = []

        for rawRule in rawRules {
            let rule = MonitorRule(rawRule)
            if engine.isValid(rule: rule) {
                if seenRules.insert(rule.rawValue).inserted {
                    rules.append(rule)
                }
            } else {
                invalidRules.append(rawRule)
            }
        }

        return (rules, invalidRules)
    }
}

private struct EditMonitorRuleSheet: View {
    @Environment(\.dismiss) private var dismiss
    let stock: StockConfig
    let saveRules: ([MonitorRule]) -> Void
    @State private var ruleText: String
    @State private var validationMessage: String?

    init(stock: StockConfig, saveRules: @escaping ([MonitorRule]) -> Void) {
        self.stock = stock
        self.saveRules = saveRules
        _ruleText = State(initialValue: stock.monitorRules.map(\.displayText).joined(separator: " / "))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("编辑监控规则")
                    .font(.headline)
                Text(stock.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("例如 3%、+3%、9+，多个用 / 分隔", text: $ruleText)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onChange(of: ruleText) { _, _ in
                    validationMessage = nil
                }

            VStack(alignment: .leading, spacing: 4) {
                Text("支持：1、3%、+3%、-3%、9+、9-")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let validationMessage {
                    Text(validationMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            HStack {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                Button("保存") {
                    let result = MonitorRuleInputParser.parse(ruleText)
                    if result.invalidRules.isEmpty {
                        saveRules(result.rules)
                        dismiss()
                    } else {
                        validationMessage = "无效规则：\(result.invalidRules.joined(separator: " / "))"
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 340)
    }
}

private struct PopoverSettingsView: View {
    @ObservedObject var appState: AppState
    let editRules: (StockConfig) -> Void
    let deleteStock: (StockConfig) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                globalSettings
                stockSettings
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .background(PanelPalette.listBackground)
    }

    private var globalSettings: some View {
        VStack(alignment: .leading, spacing: 9) {
            SettingsSectionTitle(title: "全局", systemImage: "slider.horizontal.3")

            settingsToggle("启用通知", systemImage: "bell", isOn: settingsBinding(\.notificationsEnabled))
            settingsToggle("提示音", systemImage: "speaker.wave.2", isOn: settingsBinding(\.soundEnabled))

            SettingsStepperRow(
                title: "刷新",
                systemImage: "arrow.clockwise",
                valueText: "\(Int(appState.settings.refreshInterval)) 秒"
            ) {
                Stepper("", value: settingsBinding(\.refreshInterval), in: 2...60, step: 1)
                    .labelsHidden()
            }

            SettingsStepperRow(
                title: "重复提醒",
                systemImage: "bell.badge",
                valueText: "\(Int(appState.settings.duplicateAlertInterval / 60)) 分钟"
            ) {
                Stepper(
                    "",
                    value: settingsBinding(\.duplicateAlertInterval, scale: 60),
                    in: 1...120,
                    step: 1
                )
                .labelsHidden()
            }
        }
        .settingsSectionBackground()
    }

    private var stockSettings: some View {
        VStack(alignment: .leading, spacing: 9) {
            SettingsSectionTitle(title: "股票", systemImage: "chart.line.uptrend.xyaxis")

            if appState.stocks.isEmpty {
                Text("暂无股票")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(PanelPalette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(appState.stocks) { stock in
                    PopoverStockSettingsRow(
                        stock: stock,
                        toggleMenuBar: {
                            update(stock) { $0.showInTitle = !($0.showInTitle ?? false) }
                        },
                        toggleAlerts: {
                            update(stock) { $0.alertsEnabled.toggle() }
                        },
                        editRules: {
                            editRules(stock)
                        },
                        deleteStock: {
                            deleteStock(stock)
                        }
                    )
                }
            }
        }
        .settingsSectionBackground()
    }

    private func settingsToggle(_ title: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 16)
                .foregroundStyle(PanelPalette.tertiaryText)

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(PanelPalette.primaryText)

            Spacer()

            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
        .frame(height: 24)
    }

    private func settingsBinding(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { appState.settings[keyPath: keyPath] },
            set: { value in
                var next = appState.settings
                next[keyPath: keyPath] = value
                appState.updateSettings(next)
            }
        )
    }

    private func settingsBinding(_ keyPath: WritableKeyPath<AppSettings, TimeInterval>, scale: TimeInterval = 1) -> Binding<Double> {
        Binding(
            get: { appState.settings[keyPath: keyPath] / scale },
            set: { value in
                var next = appState.settings
                next[keyPath: keyPath] = value * scale
                appState.updateSettings(next)
            }
        )
    }

    private func update(_ stock: StockConfig, mutate: (inout StockConfig) -> Void) {
        guard var current = appState.stocks.first(where: { $0.id == stock.id }) else { return }
        mutate(&current)
        appState.updateStock(current)
    }
}

private struct PopoverStockSettingsRow: View {
    let stock: StockConfig
    let toggleMenuBar: () -> Void
    let toggleAlerts: () -> Void
    let editRules: () -> Void
    let deleteStock: () -> Void

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(stock.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PanelPalette.primaryText)
                        .lineLimit(1)

                    Text(stock.symbol.code)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(PanelPalette.secondaryText)
                }

                Spacer()

                miniAction(
                    title: (stock.showInTitle ?? false) ? "菜单栏" : "隐藏",
                    systemImage: "menubar.rectangle",
                    action: toggleMenuBar
                )
                miniAction(
                    title: stock.alertsEnabled ? "通知" : "静默",
                    systemImage: stock.alertsEnabled ? "bell" : "bell.slash",
                    action: toggleAlerts
                )
            }

            HStack(spacing: 7) {
                miniAction(title: "规则", systemImage: "slider.horizontal.3", action: editRules)
                miniAction(title: "删除", systemImage: "trash", isDestructive: true, action: deleteStock)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(PanelPalette.settingRowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func miniAction(
        title: String,
        systemImage: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(PopoverMiniButtonStyle(isDestructive: isDestructive))
        .focusable(false)
    }
}

private struct SettingsSectionTitle: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(PanelPalette.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsStepperRow<Control: View>: View {
    let title: String
    let systemImage: String
    let valueText: String
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 16)
                .foregroundStyle(PanelPalette.tertiaryText)

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(PanelPalette.primaryText)

            Spacer()

            Text(valueText)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(PanelPalette.secondaryText)

            control()
        }
        .frame(height: 24)
    }
}

private extension View {
    func settingsSectionBackground() -> some View {
        padding(10)
            .background(PanelPalette.settingSectionBackground)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(PanelPalette.sectionBorder(isExpanded: false), lineWidth: 1)
            }
    }
}

private struct PopoverStockRow: View {
    let stock: StockConfig
    let quote: StockQuote?

    private var quoteName: String {
        guard let quote, !quote.name.isEmpty else { return stock.displayName }
        return quote.name
    }

    private var rulesMetaText: String {
        stock.monitorRules.map(\.displayText).filter { !$0.isEmpty }.joined(separator: " / ")
    }

    private var hasRules: Bool {
        stock.monitorRules.contains { !$0.displayText.isEmpty }
    }

    private var percentText: String {
        guard let quote else { return "--" }
        let prefix = quote.changePercent > 0 ? "+" : ""
        return "\(prefix)\(quote.changePercent.formattedPercent)"
    }

    private var changeColor: Color {
        guard let quote else { return PanelPalette.tertiaryText }
        if quote.changePercent > 0 { return PanelPalette.upText }
        if quote.changePercent < 0 { return PanelPalette.downText }
        return PanelPalette.secondaryText
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(quoteName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PanelPalette.primaryText)
                    .lineLimit(1)

                Text(stock.symbol.code)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(PanelPalette.secondaryText)
                    .lineLimit(1)

                if hasRules {
                    HStack(spacing: 5) {
                        Text("规则")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(PanelPalette.ruleLabelText)
                            .padding(.horizontal, 5)
                            .frame(height: 16)
                            .background(PanelPalette.ruleLabelBackground)
                            .clipShape(Capsule())

                        Text(rulesMetaText)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(PanelPalette.secondaryText)
                            .lineLimit(1)
                    }
                    .foregroundStyle(PanelPalette.secondaryText)
                    .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let quote, quote.ma5 > 0 {
                PopoverQuoteStats(quote: quote)
                    .padding(.top, 2)
            }

            VStack(alignment: .trailing, spacing: 4) {
                Text(quote?.price.formattedPrice ?? "--")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(PanelPalette.primaryText)

                Text(percentText)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(changeColor)
            }
            .frame(width: 86, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

private struct PopoverQuoteStats: View {
    let quote: StockQuote

    var body: some View {
        stat("MA5", quote.ma5)
            .frame(width: 78, alignment: .leading)
    }

    private func stat(_ title: String, _ value: Decimal) -> some View {
        HStack(spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(PanelPalette.tertiaryText)
            Text(value > 0 ? value.formattedPrice : "--")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(PanelPalette.secondaryText)
                .lineLimit(1)
        }
    }
}

private extension StockQuote {
    var hasExpandedIndicators: Bool {
        openPrice > 0 || lowestPrice > 0 || highestPrice > 0 || ma5 > 0 || ma10 > 0 || ma20 > 0
    }
}

private struct PopoverStockActions: View {
    let stock: StockConfig
    let quote: StockQuote?
    let open: () -> Void
    let toggleMenuBar: () -> Void
    let editRules: () -> Void
    let deleteStock: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                actionButton("雪球", systemImage: "safari", action: open)
                actionButton((stock.showInTitle ?? false) ? "隐藏" : "显示", systemImage: "menubar.rectangle", action: toggleMenuBar)
                actionButton("规则", systemImage: "slider.horizontal.3", action: editRules)
                actionButton("删除", systemImage: "trash", role: .destructive, action: deleteStock)
            }

            if let quote, quote.hasExpandedIndicators {
                PopoverExpandedIndicators(quote: quote)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity)
                .lineLimit(1)
        }
        .buttonStyle(PopoverActionButtonStyle(isDestructive: role == .destructive))
        .focusable(false)
        .help(title)
        .accessibilityLabel(Text(title))
    }
}

private struct PopoverExpandedIndicators: View {
    let quote: StockQuote

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                chip("开", quote.openPrice)
                chip("低", quote.lowestPrice)
                chip("高", quote.highestPrice)
            }
            HStack(spacing: 6) {
                chip("MA5", quote.ma5)
                chip("MA10", quote.ma10)
                chip("MA20", quote.ma20)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(_ title: String, _ value: Decimal) -> some View {
        HStack(spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(PanelPalette.tertiaryText)
            Text(value > 0 ? value.formattedPrice : "--")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(PanelPalette.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: 20)
        .background(PanelPalette.indicatorBackground)
        .clipShape(Capsule())
    }
}

private struct EmptyPopoverState: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 24))
                .foregroundStyle(PanelPalette.tertiaryText)

            Text("暂无股票")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(PanelPalette.secondaryText)
        }
    }
}

private struct PopoverFooterButtonStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground(isPressed: configuration.isPressed))
            .background {
                Circle()
                    .fill(background(isPressed: configuration.isPressed))
                    .shadow(color: PanelPalette.footerButtonShadow, radius: 4, x: 0, y: 1)
            }
            .overlay {
                Circle()
                    .stroke(isActive ? PanelPalette.footerButtonActiveBorder : PanelPalette.footerButtonBorder, lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }

    private func foreground(isPressed: Bool) -> Color {
        let base = isActive ? PanelPalette.footerButtonActiveText : PanelPalette.primaryText
        return base.opacity(isPressed ? 0.70 : 0.92)
    }

    private func background(isPressed: Bool) -> Color {
        if isPressed {
            return PanelPalette.footerButtonPressed
        }
        return isActive ? PanelPalette.footerButtonActiveBackground : PanelPalette.footerButtonBackground
    }
}

private struct PopoverMiniButtonStyle: ButtonStyle {
    let isDestructive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 7)
            .frame(height: 23)
            .foregroundStyle(foreground(isPressed: configuration.isPressed))
            .background(configuration.isPressed ? PanelPalette.buttonPressed : PanelPalette.buttonBackground)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(PanelPalette.buttonBorder, lineWidth: 1)
            }
    }

    private func foreground(isPressed: Bool) -> Color {
        let base = isDestructive ? PanelPalette.upText : PanelPalette.primaryText
        return base.opacity(isPressed ? 0.68 : 0.90)
    }
}

private struct PopoverActionButtonStyle: ButtonStyle {
    let isDestructive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 7)
            .frame(height: 24)
            .foregroundStyle(foreground(isPressed: configuration.isPressed))
            .background(configuration.isPressed ? PanelPalette.buttonPressed : PanelPalette.buttonBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(PanelPalette.buttonBorder, lineWidth: 1)
            }
    }

    private func foreground(isPressed: Bool) -> Color {
        let base = isDestructive ? PanelPalette.upText : PanelPalette.primaryText
        return base.opacity(isPressed ? 0.70 : 0.90)
    }
}

private enum PanelPalette {
    static let backgroundTint = adaptive(
        light: NSColor(calibratedRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.34),
        dark: NSColor(calibratedRed: 30.0 / 255.0, green: 30.0 / 255.0, blue: 30.0 / 255.0, alpha: 0.42)
    )
    static let listBackground = Color.clear
    static let footer = adaptive(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.18),
        dark: NSColor(calibratedWhite: 0.0, alpha: 0.14)
    )
    static let separator = adaptive(
        light: NSColor(calibratedWhite: 0.0, alpha: 0.08),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.10)
    )
    static let panelBorder = adaptive(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.64),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.16)
    )
    static let primaryText = Color(nsColor: .labelColor)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)
    static let tertiaryText = Color(nsColor: .tertiaryLabelColor)
    static let upText = Color(nsColor: .systemRed)
    static let downText = Color(nsColor: .systemGreen)
    static let ruleLabelText = adaptive(
        light: NSColor(calibratedWhite: 0.0, alpha: 0.54),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.68)
    )
    static let ruleLabelBackground = adaptive(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.44),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.10)
    )
    static let indicatorBackground = adaptive(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.32),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.08)
    )
    static let settingSectionBackground = adaptive(
        light: NSColor(calibratedWhite: 0.86, alpha: 0.46),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.08)
    )
    static let settingRowBackground = adaptive(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.26),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.06)
    )
    static let buttonBackground = adaptive(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.44),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.12)
    )
    static let buttonPressed = adaptive(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.62),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.20)
    )
    static let buttonBorder = adaptive(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.40),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.10)
    )
    static let footerButtonBackground = adaptive(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.78),
        dark: NSColor(calibratedWhite: 0.0, alpha: 0.38)
    )
    static let footerButtonActiveBackground = adaptive(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.94),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.16)
    )
    static let footerButtonActiveBorder = adaptive(
        light: NSColor(calibratedWhite: 0.0, alpha: 0.18),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.28)
    )
    static let footerButtonActiveText = adaptive(
        light: NSColor(calibratedWhite: 0.0, alpha: 0.92),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.96)
    )
    static let footerButtonPressed = adaptive(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.92),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.13)
    )
    static let footerButtonBorder = adaptive(
        light: NSColor(calibratedWhite: 0.0, alpha: 0.12),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.18)
    )
    static let footerButtonShadow = adaptive(
        light: NSColor(calibratedWhite: 0.0, alpha: 0.18),
        dark: NSColor(calibratedWhite: 0.0, alpha: 0.55)
    )

    static func sectionBackground(isExpanded: Bool) -> Color {
        adaptive(
            light: isExpanded
                ? NSColor(calibratedRed: 0.58, green: 0.70, blue: 0.64, alpha: 0.56)
                : NSColor(calibratedWhite: 0.86, alpha: 0.54),
            dark: isExpanded
                ? NSColor(calibratedRed: 0.10, green: 0.25, blue: 0.18, alpha: 0.64)
                : NSColor(calibratedWhite: 1.0, alpha: 0.10)
        )
    }

    static func sectionBorder(isExpanded: Bool) -> Color {
        adaptive(
            light: isExpanded
                ? NSColor(calibratedWhite: 1.0, alpha: 0.58)
                : NSColor(calibratedWhite: 1.0, alpha: 0.42),
            dark: isExpanded
                ? NSColor(calibratedWhite: 1.0, alpha: 0.13)
                : NSColor(calibratedWhite: 1.0, alpha: 0.10)
        )
    }

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 12
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
        nsView.layer?.cornerRadius = 12
    }
}
