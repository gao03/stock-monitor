import SwiftUI

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

struct EditMonitorRuleSheet: View {
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

struct PopoverSettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                statusBarSettings
                quoteChannelSettings
                notificationSettings
                refreshSettings
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .background(PanelPalette.listBackground)
    }

    private var statusBarSettings: some View {
        SettingsModule(title: "状态栏", systemImage: "menubar.rectangle") {
            SettingsSegmentedRow(
                title: "文字颜色",
                systemImage: "paintpalette",
                selection: statusBarTextColorModeBinding,
                options: StatusBarTextColorMode.allCases,
                displayName: \.displayName
            )
        }
    }

    private var quoteChannelSettings: some View {
        SettingsModule(title: "行情渠道", systemImage: "antenna.radiowaves.left.and.right") {
            SettingsToggleRow(title: "启用长桥", systemImage: "bolt.horizontal", isOn: settingsBinding(\.longbridgeEnabled))
            SettingsTextFieldRow(
                title: "OAuth Client ID",
                systemImage: "key",
                placeholder: "your-client-id",
                text: settingsStringBinding(\.longbridgeClientID)
            )
            SettingsSegmentedRow(
                title: "接入区域",
                systemImage: "network",
                selection: longbridgeRegionBinding,
                options: LongbridgeRegion.allCases,
                displayName: \.displayName
            )
            SettingsToggleRow(title: "夜盘行情", systemImage: "moon", isOn: settingsBinding(\.longbridgeEnableOvernight))
        }
    }

    private var notificationSettings: some View {
        SettingsModule(title: "通知", systemImage: "bell.badge") {
            SettingsToggleRow(title: "启用通知", systemImage: "bell", isOn: settingsBinding(\.notificationsEnabled))
            SettingsToggleRow(title: "提示音", systemImage: "speaker.wave.2", isOn: settingsBinding(\.soundEnabled))

            SettingsIncrementRow(
                title: "重复提醒",
                systemImage: "repeat",
                valueText: "\(Int(appState.settings.duplicateAlertInterval / 60)) 分钟",
                canDecrement: appState.settings.duplicateAlertInterval > 60,
                canIncrement: appState.settings.duplicateAlertInterval < 120 * 60,
                decrement: { adjustInterval(\.duplicateAlertInterval, by: -60, range: 60...(120 * 60)) },
                increment: { adjustInterval(\.duplicateAlertInterval, by: 60, range: 60...(120 * 60)) }
            )

            SettingsIncrementRow(
                title: "回本提醒",
                systemImage: "scope",
                valueText: "\(Int(appState.settings.returnToCostAlertInterval / 3600)) 小时",
                canDecrement: appState.settings.returnToCostAlertInterval > 3600,
                canIncrement: appState.settings.returnToCostAlertInterval < 24 * 3600,
                decrement: { adjustInterval(\.returnToCostAlertInterval, by: -3600, range: 3600...(24 * 3600)) },
                increment: { adjustInterval(\.returnToCostAlertInterval, by: 3600, range: 3600...(24 * 3600)) }
            )
        }
    }

    private var refreshSettings: some View {
        SettingsModule(title: "行情", systemImage: "arrow.clockwise") {
            SettingsIncrementRow(
                title: "刷新间隔",
                systemImage: "timer",
                valueText: "\(Int(appState.settings.refreshInterval)) 秒",
                canDecrement: appState.settings.refreshInterval > 2,
                canIncrement: appState.settings.refreshInterval < 60,
                decrement: { adjustInterval(\.refreshInterval, by: -1, range: 2...60) },
                increment: { adjustInterval(\.refreshInterval, by: 1, range: 2...60) }
            )
        }
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

    private func settingsStringBinding(_ keyPath: WritableKeyPath<AppSettings, String>) -> Binding<String> {
        Binding(
            get: { appState.settings[keyPath: keyPath] },
            set: { value in
                var next = appState.settings
                next[keyPath: keyPath] = value
                appState.updateSettings(next)
            }
        )
    }

    private func adjustInterval(
        _ keyPath: WritableKeyPath<AppSettings, TimeInterval>,
        by delta: TimeInterval,
        range: ClosedRange<TimeInterval>
    ) {
        var next = appState.settings
        let value = next[keyPath: keyPath] + delta
        next[keyPath: keyPath] = min(max(value, range.lowerBound), range.upperBound)
        appState.updateSettings(next)
    }

    private var statusBarTextColorModeBinding: Binding<StatusBarTextColorMode> {
        Binding(
            get: { appState.settings.statusBarTextColorMode },
            set: { value in
                var next = appState.settings
                next.statusBarTextColorMode = value
                appState.updateSettings(next)
            }
        )
    }

    private var longbridgeRegionBinding: Binding<LongbridgeRegion> {
        Binding(
            get: { appState.settings.longbridgeRegion },
            set: { value in
                var next = appState.settings
                next.longbridgeRegion = value
                appState.updateSettings(next)
            }
        )
    }

}

private struct SettingsModule<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PanelPalette.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 0) {
                content()
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .settingsSectionBackground()
    }
}

private struct SettingsRowBase<Accessory: View>: View {
    let title: String
    let systemImage: String
    var height: CGFloat = 32
    @ViewBuilder var accessory: () -> Accessory

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

            accessory()
        }
        .frame(height: height)
        .padding(.horizontal, 8)
        .background(PanelPalette.settingRowBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PanelPalette.settingRowSeparator)
                .frame(height: 1)
                .padding(.leading, 32)
        }
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let systemImage: String
    let isOn: Binding<Bool>

    var body: some View {
        SettingsRowBase(title: title, systemImage: systemImage) {
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
    }
}

private struct SettingsTextFieldRow: View {
    let title: String
    let systemImage: String
    let placeholder: String
    let text: Binding<String>

    var body: some View {
        SettingsRowBase(title: title, systemImage: systemImage, height: 34) {
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(PanelPalette.primaryText)
                .padding(.horizontal, 8)
                .frame(width: 156, height: 24)
                .background(PanelPalette.settingControlTrack)
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .stroke(PanelPalette.settingControlBorder, lineWidth: 1)
                }
        }
    }
}

private struct SettingsSegmentedRow<Option: Identifiable & Hashable>: View where Option.ID == String {
    let title: String
    let systemImage: String
    let selection: Binding<Option>
    let options: [Option]
    let displayName: (Option) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 16)
                    .foregroundStyle(PanelPalette.tertiaryText)

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(PanelPalette.primaryText)
                    .lineLimit(1)

                Spacer()
            }

            HStack(spacing: 2) {
                ForEach(options) { option in
                    Button {
                        selection.wrappedValue = option
                    } label: {
                        Text(displayName(option))
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SettingsSegmentButtonStyle(isSelected: selection.wrappedValue == option))
                    .focusable(false)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(2)
            .background(PanelPalette.settingControlTrack)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(PanelPalette.settingControlBorder, lineWidth: 1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(PanelPalette.settingRowBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PanelPalette.settingRowSeparator)
                .frame(height: 1)
                .padding(.leading, 32)
        }
    }
}

private struct SettingsIncrementRow: View {
    let title: String
    let systemImage: String
    let valueText: String
    let canDecrement: Bool
    let canIncrement: Bool
    let decrement: () -> Void
    let increment: () -> Void

    var body: some View {
        SettingsRowBase(title: title, systemImage: systemImage, height: 34) {
            Text(valueText)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(PanelPalette.secondaryText)
                .frame(minWidth: 54, alignment: .trailing)

            HStack(spacing: 1) {
                Button(action: decrement) {
                    Image(systemName: "minus")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 21, height: 20)
                }
                .buttonStyle(SettingsControlButtonStyle(isEnabled: canDecrement))
                .disabled(!canDecrement)
                .focusable(false)

                Button(action: increment) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 21, height: 20)
                }
                .buttonStyle(SettingsControlButtonStyle(isEnabled: canIncrement))
                .disabled(!canIncrement)
                .focusable(false)
            }
            .padding(2)
            .background(PanelPalette.settingControlTrack)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(PanelPalette.settingControlBorder, lineWidth: 1)
            }
        }
    }
}

private struct SettingsSegmentButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 7)
            .frame(height: 22)
            .foregroundStyle(foreground(isPressed: configuration.isPressed))
            .background(background(isPressed: configuration.isPressed))
            .clipShape(Capsule())
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    private func foreground(isPressed: Bool) -> Color {
        let base = isSelected ? PanelPalette.settingControlSelectedText : PanelPalette.secondaryText
        return base.opacity(isPressed ? 0.68 : 0.94)
    }

    private func background(isPressed: Bool) -> Color {
        if isPressed {
            return PanelPalette.settingControlPressed
        }
        return isSelected ? PanelPalette.settingControlSelectedBackground : Color.clear
    }
}

private struct SettingsControlButtonStyle: ButtonStyle {
    let isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground(isPressed: configuration.isPressed))
            .background(background(isPressed: configuration.isPressed))
            .clipShape(Circle())
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }

    private func foreground(isPressed: Bool) -> Color {
        guard isEnabled else { return PanelPalette.tertiaryText.opacity(0.34) }
        return PanelPalette.primaryText.opacity(isPressed ? 0.62 : 0.86)
    }

    private func background(isPressed: Bool) -> Color {
        guard isEnabled else { return Color.clear }
        return isPressed ? PanelPalette.settingControlPressed : Color.clear
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
