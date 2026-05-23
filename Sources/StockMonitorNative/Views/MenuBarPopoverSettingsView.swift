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
        ScrollView {
            VStack(spacing: 8) {
                globalSettings
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
