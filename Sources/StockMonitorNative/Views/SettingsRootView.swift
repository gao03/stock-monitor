import AppKit
import SwiftUI

struct SettingsRootView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedSection: SettingsSection? = .stocks

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } detail: {
            switch selectedSection ?? .stocks {
            case .stocks:
                StocksSettingsView()
            case .notifications:
                NotificationsSettingsView()
            case .advanced:
                AdvancedSettingsView()
            }
        }
        .frame(minWidth: 860, minHeight: 560)
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case stocks
    case notifications
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stocks: "股票"
        case .notifications: "通知"
        case .advanced: "高级"
        }
    }

    var systemImage: String {
        switch self {
        case .stocks: "chart.line.uptrend.xyaxis"
        case .notifications: "bell.badge"
        case .advanced: "gearshape.2"
        }
    }
}

private struct StocksSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""
    @State private var isAddingStock = false

    private var filteredStocks: [StockConfig] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return appState.stocks }
        return appState.stocks.filter {
            $0.name.localizedCaseInsensitiveContains(keyword) ||
                $0.symbol.code.localizedCaseInsensitiveContains(keyword) ||
                ($0.symbol.market?.displayName.localizedCaseInsensitiveContains(keyword) ?? false)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                StocksToolbar(
                    searchText: $searchText,
                    isAddingStock: $isAddingStock,
                    canDelete: appState.selectedStock != nil,
                    delete: appState.deleteSelectedStock
                )

                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredStocks) { stock in
                            StockListRow(
                                stock: stock,
                                quote: appState.quotes[stock.symbol.cacheKey],
                                isSelected: stock.id == appState.selectedStockID
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                appState.selectedStockID = stock.id
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .scrollContentBackground(.hidden)
                .background(SettingsPalette.listBackground)

                if filteredStocks.isEmpty {
                    EmptyInlineState(title: searchText.isEmpty ? "还没有股票" : "没有匹配结果")
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 18)
                }
            }
            .frame(minWidth: 340, idealWidth: 390, maxWidth: 430)
            .background(SettingsPalette.listBackground)

            Divider()

            if let stock = appState.selectedStock {
                StockDetailView(
                    stock: binding(for: stock),
                    quote: appState.quotes[stock.symbol.cacheKey]
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                EmptyStateView(title: "未选择股票", systemImage: "chart.line.uptrend.xyaxis")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("股票")
        .background(SettingsPalette.windowBackground)
        .sheet(isPresented: $isAddingStock) {
            AddStockSheet()
                .environmentObject(appState)
        }
    }

    private func binding(for stock: StockConfig) -> Binding<StockConfig> {
        Binding(
            get: { appState.stocks.first(where: { $0.id == stock.id }) ?? stock },
            set: { appState.updateSelectedStock($0) }
        )
    }
}

private struct StocksToolbar: View {
    @Binding var searchText: String
    @Binding var isAddingStock: Bool
    let canDelete: Bool
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("搜索", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)

            Spacer(minLength: 8)

            Button {
                isAddingStock = true
            } label: {
                Label("添加", systemImage: "plus")
            }

            Button(role: .destructive) {
                delete()
            } label: {
                Label("删除", systemImage: "trash")
            }
            .disabled(!canDelete)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(SettingsPalette.toolbarBackground)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

private struct StockListRow: View {
    let stock: StockConfig
    let quote: StockQuote?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(stock.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SettingsPalette.primaryText)
                    .lineLimit(1)

                Text(stock.symbol.displayText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(SettingsPalette.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                if let quote {
                    Text(signedPercent(quote.changePercent))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(SettingsPalette.changeColor(for: quote.changePercent))
                        .monospacedDigit()
                    Text(quote.price.formattedPrice)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(SettingsPalette.secondaryText)
                        .monospacedDigit()
                } else {
                    Text("查询中")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SettingsPalette.secondaryText)
                }
            }
            .frame(width: 76, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? SettingsPalette.selectedRowBackground : SettingsPalette.rowBackground)
        )
    }

    private func signedPercent(_ value: Decimal) -> String {
        "\(value > 0 ? "+" : "")\(value.formattedPercent)"
    }
}

private struct StockDetailView: View {
    @Binding var stock: StockConfig
    let quote: StockQuote?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                QuoteSummaryView(stock: stock, quote: quote)

                SettingsGroup(title: "基本信息", systemImage: "tag") {
                    SettingsRow(title: "名称") {
                        TextField("名称", text: $stock.name)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                    }
                    SettingsRow(title: "代码") {
                        TextField("代码", text: $stock.symbol.code)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 160)
                    }
                    SettingsRow(title: "市场") {
                        Picker("", selection: marketBinding) {
                            ForEach(StockMarket.allCases, id: \.self) { market in
                                Text(market.displayName).tag(Optional(market))
                            }
                        }
                        .labelsHidden()
                        .frame(width: 180)
                    }
                }

                SettingsGroup(title: "持仓", systemImage: "briefcase") {
                    SettingsRow(title: "成本") {
                        DecimalField("成本", value: $stock.costPrice)
                            .frame(width: 140)
                    }
                    SettingsRow(title: "数量") {
                        DecimalField("数量", value: $stock.position)
                            .frame(width: 140)
                    }
                    if let quote, stock.position > 0 {
                        SettingsRow(title: "持仓市值") {
                            Text((quote.price * stock.position).formattedPrice)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(SettingsPalette.secondaryText)
                        }
                    }
                }

                SettingsGroup(title: "菜单栏与提醒", systemImage: "bell") {
                    SettingsRow(title: "菜单栏显示") {
                        Toggle("", isOn: showInTitleBinding)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    SettingsRow(title: "启用提醒") {
                        Toggle("", isOn: $stock.alertsEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }
            }
            .frame(maxWidth: 660, alignment: .topLeading)
            .padding(.horizontal, 28)
            .padding(.vertical, 28)
        }
        .scrollContentBackground(.hidden)
        .background(SettingsPalette.detailBackground)
    }

    private var showInTitleBinding: Binding<Bool> {
        Binding(
            get: { stock.showInTitle ?? false },
            set: { stock.showInTitle = $0 }
        )
    }

    private var marketBinding: Binding<StockMarket?> {
        Binding(
            get: { stock.symbol.market },
            set: { stock.symbol.market = $0 }
        )
    }

}

private struct AddStockSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @State private var name = ""
    @State private var code = ""
    @State private var market: StockMarket = .shanghai
    @State private var costPrice = Decimal.zero
    @State private var position = Decimal.zero
    @State private var showInTitle = true
    @State private var alertsEnabled = true

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                SettingsGroup(title: "基本信息", systemImage: "plus.circle") {
                    SettingsRow(title: "名称") {
                        TextField("名称", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }
                    SettingsRow(title: "代码") {
                        TextField("代码", text: $code)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }
                    SettingsRow(title: "市场") {
                        Picker("", selection: $market) {
                            ForEach(StockMarket.allCases, id: \.self) { market in
                                Text(market.displayName).tag(market)
                            }
                        }
                        .labelsHidden()
                    }
                }

                SettingsGroup(title: "持仓", systemImage: "briefcase") {
                    SettingsRow(title: "成本") {
                        DecimalField("成本", value: $costPrice)
                    }
                    SettingsRow(title: "数量") {
                        DecimalField("数量", value: $position)
                    }
                }

                SettingsGroup(title: "行为", systemImage: "menubar.rectangle") {
                    SettingsRow(title: "菜单栏显示") {
                        Toggle("", isOn: $showInTitle)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    SettingsRow(title: "启用提醒") {
                        Toggle("", isOn: $alertsEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }
            }
            .padding(16)
            .background(SettingsPalette.windowBackground)
            Divider()

            HStack {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                Button("添加") {
                    appState.addStock(
                        StockConfig(
                            symbol: StockSymbol(code: code, market: market),
                            name: name.isEmpty ? code : name,
                            costPrice: costPrice,
                            position: position,
                            showInTitle: showInTitle,
                            monitorRules: [],
                            alertsEnabled: alertsEnabled
                        )
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .frame(width: 460, height: 430)
    }
}

private struct RulesSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var newRule = ""

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(title: "监控规则") {
                TextField("规则", text: $newRule)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)

                Button {
                    addRule()
                } label: {
                    Label("添加", systemImage: "plus")
                }
                .disabled(appState.selectedStock == nil || newRule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let stock = appState.selectedStock {
                List {
                    Section(stock.displayName) {
                        ForEach(stock.monitorRules) { rule in
                            RuleRow(rule: rule, stock: stock)
                        }
                        .onDelete { offsets in
                            appState.deleteRules(at: offsets, from: stock)
                        }
                    }
                }
                .listStyle(.inset)
            } else {
                EmptyStateView(title: "未选择股票", systemImage: "slider.horizontal.3")
            }
        }
        .navigationTitle("监控规则")
    }

    private func addRule() {
        guard let stock = appState.selectedStock else { return }
        appState.addRule(MonitorRule(newRule), to: stock)
        newRule = ""
    }
}

private struct RuleRow: View {
    let rule: MonitorRule
    let stock: StockConfig
    private let engine = MonitorRuleEngine()

    var body: some View {
        HStack {
            Text(rule.displayText)
                .font(.body.monospaced())
            Spacer()
            let range = engine.priceRange(for: rule, previousClose: 0, costPrice: stock.costPrice)
            Text(rangeLabel(range))
                .font(.caption)
                .foregroundStyle(SettingsPalette.secondaryText)
        }
        .padding(.vertical, 6)
    }

    private func rangeLabel(_ range: MonitorPriceRange) -> String {
        let hasLowerBound = range.minimum <= MonitorRangeBounds.lower
        let hasUpperBound = range.maximum >= MonitorRangeBounds.upper

        if hasLowerBound && hasUpperBound {
            return "未识别"
        }
        if hasLowerBound {
            return "> \(range.maximum.formattedPrice)"
        }
        if hasUpperBound {
            return "< \(range.minimum.formattedPrice)"
        }
        return "< \(range.minimum.formattedPrice) 或 > \(range.maximum.formattedPrice)"
    }
}

private struct ChannelsSettingsView: View {
    private let channels = [
        ChannelRow(name: "东方财富", status: "已启用", markets: "A 股、港股、美股", kind: "轮询"),
        ChannelRow(name: "新浪财经", status: "已启用", markets: "美股盘前盘后", kind: "补充"),
        ChannelRow(name: "长桥", status: "待接入", markets: "港股、美股", kind: "实时")
    ]

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(title: "行情渠道") {
                Button {
                } label: {
                    Label("测试", systemImage: "bolt")
                }
                .disabled(true)
            }

            Table(channels) {
                TableColumn("渠道", value: \.name)
                TableColumn("状态", value: \.status)
                    .width(90)
                TableColumn("市场", value: \.markets)
                TableColumn("模式", value: \.kind)
                    .width(80)
            }
            .padding()
        }
        .navigationTitle("行情渠道")
    }
}

private struct ChannelRow: Identifiable {
    let id = UUID()
    let name: String
    let status: String
    let markets: String
    let kind: String
}

private struct NotificationsSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("系统通知") {
                Toggle("启用通知", isOn: settingsBinding(\.notificationsEnabled))
                Toggle("播放声音", isOn: settingsBinding(\.soundEnabled))
            }

            Section("频率") {
                Stepper("刷新间隔: \(Int(appState.settings.refreshInterval)) 秒", value: intervalBinding(\.refreshInterval), in: 2...120, step: 1)
                Stepper("规则提醒间隔: \(Int(appState.settings.duplicateAlertInterval / 60)) 分钟", value: minuteBinding(\.duplicateAlertInterval), in: 1...120, step: 1)
                Stepper("回本提醒间隔: \(Int(appState.settings.returnToCostAlertInterval / 3600)) 小时", value: hourBinding(\.returnToCostAlertInterval), in: 1...24, step: 1)
            }
        }
        .formStyle(.grouped)
        .padding()
        .navigationTitle("通知")
    }

    private func settingsBinding(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { appState.settings[keyPath: keyPath] },
            set: {
                var next = appState.settings
                next[keyPath: keyPath] = $0
                appState.updateSettings(next)
            }
        )
    }

    private func intervalBinding(_ keyPath: WritableKeyPath<AppSettings, TimeInterval>) -> Binding<Int> {
        Binding(
            get: { Int(appState.settings[keyPath: keyPath]) },
            set: {
                var next = appState.settings
                next[keyPath: keyPath] = TimeInterval($0)
                appState.updateSettings(next)
            }
        )
    }

    private func minuteBinding(_ keyPath: WritableKeyPath<AppSettings, TimeInterval>) -> Binding<Int> {
        Binding(
            get: { Int(appState.settings[keyPath: keyPath] / 60) },
            set: {
                var next = appState.settings
                next[keyPath: keyPath] = TimeInterval($0 * 60)
                appState.updateSettings(next)
            }
        )
    }

    private func hourBinding(_ keyPath: WritableKeyPath<AppSettings, TimeInterval>) -> Binding<Int> {
        Binding(
            get: { Int(appState.settings[keyPath: keyPath] / 3600) },
            set: {
                var next = appState.settings
                next[keyPath: keyPath] = TimeInterval($0 * 3600)
                appState.updateSettings(next)
            }
        )
    }
}

private struct OperationsSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var filterText = ""

    private var filteredOperations: [OperationRecord] {
        let keyword = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return appState.operations }
        return appState.operations.filter {
            $0.type.displayName.localizedCaseInsensitiveContains(keyword) ||
                ($0.stockCode?.localizedCaseInsensitiveContains(keyword) ?? false) ||
                ($0.stockName?.localizedCaseInsensitiveContains(keyword) ?? false) ||
                $0.detail.localizedCaseInsensitiveContains(keyword)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(title: "操作记录") {
                TextField("筛选", text: $filterText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                Button(role: .destructive) {
                    appState.clearOperations()
                } label: {
                    Label("清空", systemImage: "trash")
                }
                .disabled(appState.operations.isEmpty)
            }

            Table(filteredOperations) {
                TableColumn("时间") { record in
                    Text(record.time.formatted(date: .numeric, time: .standard))
                }
                .width(170)
                TableColumn("类型") { record in
                    Text(record.type.displayName)
                }
                .width(90)
                TableColumn("股票") { record in
                    Text([record.stockCode, record.stockName].compactMap(\.self).joined(separator: " "))
                }
                .width(180)
                TableColumn("描述", value: \.detail)
            }
            .padding()
        }
        .navigationTitle("操作记录")
    }
}

private struct AdvancedSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var storageURL = (try? ApplicationStorage.applicationSupportDirectory()) ?? URL(fileURLWithPath: NSTemporaryDirectory())

    var body: some View {
        Form {
            Section("运行") {
                Toggle("启动后自动刷新", isOn: autoStartBinding)
                Button {
                    Task { await appState.refreshOnce() }
                } label: {
                    Label("立即刷新", systemImage: "arrow.clockwise")
                }
            }

            Section("数据") {
                HStack {
                    Text(storageURL.path)
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        NSWorkspace.shared.open(storageURL)
                    } label: {
                        Label("打开", systemImage: "folder")
                    }
                }
            }

            if let message = appState.lastErrorMessage {
                Section("最近错误") {
                    Text(message)
                        .foregroundStyle(SettingsPalette.secondaryText)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .navigationTitle("高级")
    }

    private var autoStartBinding: Binding<Bool> {
        Binding(
            get: { appState.settings.autoStartMonitoring },
            set: {
                var next = appState.settings
                next.autoStartMonitoring = $0
                appState.updateSettings(next)
            }
        )
    }
}

private struct HeaderBar<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack {
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(SettingsPalette.primaryText)
            Spacer()
            content
        }
        .padding()
        .background(.bar)
    }
}

private struct QuoteSummaryView: View {
    let stock: StockConfig
    let quote: StockQuote?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(stock.displayName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(SettingsPalette.primaryText)
                    Text(stock.symbol.displayText)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(SettingsPalette.secondaryText)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(quote?.price.formattedPrice ?? "查询中")
                        .font(.system(size: 30, weight: .semibold, design: .default))
                        .foregroundStyle(SettingsPalette.primaryText)
                        .monospacedDigit()

                    if let quote {
                        Text("\(quote.changePercent >= 0 ? "+" : "")\(quote.changePercent.formattedPercent)")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundStyle(SettingsPalette.changeColor(for: quote.changePercent))
                            .monospacedDigit()
                    }
                }
            }

            Divider()

            HStack(spacing: 28) {
                SummaryMetric(title: "成本", value: stock.costPrice.formattedPrice)
                SummaryMetric(title: "数量", value: stock.position.plainString)
                SummaryMetric(title: "市值", value: quote.map { ($0.price * stock.position).formattedPrice } ?? "--")
            }
        }
        .padding(.bottom, 4)
    }
}

private struct SummaryMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(SettingsPalette.secondaryText)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(SettingsPalette.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SettingsPalette.primaryText)

            VStack(spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SettingsPalette.groupBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(SettingsPalette.groupBorder)
            }
        }
    }
}

private struct SettingsRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SettingsPalette.secondaryText)
                .frame(width: 88, alignment: .trailing)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

private struct DecimalField: View {
    let title: String
    @Binding var value: Decimal
    @State private var text: String

    init(_ title: String, value: Binding<Decimal>) {
        self.title = title
        self._value = value
        self._text = State(initialValue: value.wrappedValue.plainString)
    }

    var body: some View {
        TextField(title, text: textBinding)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .monospacedDigit()
            .onChange(of: value) { _, newValue in
                let nextText = newValue.plainString
                if decimal(from: text) != newValue {
                    text = nextText
                }
            }
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { text },
            set: { newText in
                text = newText
                if let decimal = decimal(from: newText) {
                    value = decimal
                }
            }
        )
    }

    private func decimal(from string: String) -> Decimal? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "-", trimmed != ".", trimmed != "-." else {
            return nil
        }
        return Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX"))
    }
}

private struct EmptyStateView: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(SettingsPalette.secondaryText)
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(SettingsPalette.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EmptyInlineState: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(SettingsPalette.secondaryText)
    }
}

private enum SettingsPalette {
    static let primaryText = Color(nsColor: .labelColor)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)
    static let tertiaryText = Color(nsColor: .tertiaryLabelColor)
    static let windowBackground = Color(nsColor: .windowBackgroundColor)
    static let detailBackground = Color(nsColor: .windowBackgroundColor)
    static let toolbarBackground = Color(nsColor: .windowBackgroundColor)
    static let listBackground = Color(nsColor: .windowBackgroundColor)
    static let rowBackground = Color.clear
    static let groupBackground = Color(nsColor: .textBackgroundColor)
    static let groupBorder = Color(nsColor: .separatorColor).opacity(0.30)
    static let selectedRowBackground = Color.accentColor.opacity(0.10)

    static func changeColor(for value: Decimal) -> Color {
        if value > 0 { return Color(nsColor: .systemRed) }
        if value < 0 { return Color(nsColor: .systemGreen) }
        return secondaryText
    }
}

private enum MonitorRangeBounds {
    static let lower = Decimal(string: "0.0000000000000000000000000001", locale: Locale(identifier: "en_US_POSIX"))!
    static let upper = Decimal(string: "9999999999999999999999999999", locale: Locale(identifier: "en_US_POSIX"))!
}
