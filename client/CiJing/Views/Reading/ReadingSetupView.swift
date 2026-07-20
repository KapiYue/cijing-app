import SwiftUI

struct ReadingSetupView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var targets: [Word] = []
    @State private var selectedIDs = Set<UUID>()
    @State private var theme = "daily_life"
    @State private var style = "story"
    @State private var difficulty = "intermediate"
    @State private var reading: ReadingSession?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) { Text("定制这一次阅读").font(.system(size: 29, weight: .bold, design: .serif)); Text("我们已优先选择薄弱词、到期旧词和少量新词。你也可以手动调整。 ").foregroundStyle(CiJingTheme.secondary) }
                    optionSection(title: "主题") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92))], spacing: 9) {
                            ForEach(ReadingOptions.themes, id: \.0) { item in OptionChip(title: item.1, icon: item.2, selected: theme == item.0) { theme = item.0 } }
                        }
                    }
                    optionSection(title: "文体") { HStack { ForEach(ReadingOptions.styles, id: \.0) { item in OptionChip(title: item.1, selected: style == item.0) { style = item.0 } } } }
                    optionSection(title: "难度") { Picker("难度", selection: $difficulty) { ForEach(ReadingOptions.difficulties, id: \.0) { Text($0.1).tag($0.0) } }.pickerStyle(.segmented) }
                    optionSection(title: "目标词 · \(selectedIDs.count)") {
                        if targets.isEmpty { ProgressView("正在安排词汇…").frame(maxWidth: .infinity).padding() }
                        else { LazyVGrid(columns: [GridItem(.adaptive(minimum: 105))], spacing: 9) { ForEach(targets) { word in Button { if selectedIDs.contains(word.id) { if selectedIDs.count > 3 { selectedIDs.remove(word.id) } } else { selectedIDs.insert(word.id) } } label: { HStack(spacing: 5) { Circle().fill(word.status.color).frame(width: 6, height: 6); Text(word.term).lineLimit(1); if selectedIDs.contains(word.id) { Image(systemName: "checkmark") } }.font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 9).frame(maxWidth: .infinity).background(selectedIDs.contains(word.id) ? CiJingTheme.lightGreen : CiJingTheme.paper, in: RoundedRectangle(cornerRadius: 11)).foregroundStyle(CiJingTheme.ink) }.buttonStyle(.plain) } } }
                    }
                    if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(CiJingTheme.danger) }
                    Button { Task { await generate() } } label: { HStack { if store.isLoading { ProgressView().tint(.white) }; Text(store.isLoading ? "正在写作…" : "生成个性化短文"); Spacer(); Image(systemName: "wand.and.stars") } }
                        .buttonStyle(PrimaryButtonStyle()).disabled(selectedIDs.count < 3 || store.isLoading)
                    Text("已生成的相同组合会优先使用缓存；点击短文内“换一篇”才会请求新的内容。")
                        .font(.caption2).foregroundStyle(CiJingTheme.secondary)
                }.padding(20)
            }
        }.toolbar { ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } } }
            .task { targets = await store.loadTargets(limit: 14); selectedIDs = Set(targets.prefix(10).map(\.id)) }
            .fullScreenCover(item: $reading) { selectedReading in
                NavigationStack { ReadingSessionView(reading: selectedReading) }
            }
    }

    private func optionSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View { VStack(alignment: .leading, spacing: 11) { Text(title).font(.headline); content() }.cijingCard() }
    private func generate() async { do { reading = try await store.generateReading(targets: targets.filter { selectedIDs.contains($0.id) }, theme: theme, style: style, difficulty: difficulty) } catch { errorMessage = error.localizedDescription } }
}

private struct OptionChip: View { let title: String; var icon: String?; let selected: Bool; let action: () -> Void; var body: some View { Button(action: action) { HStack(spacing: 5) { if let icon { Image(systemName: icon) }; Text(title) }.font(.caption.bold()).frame(maxWidth: .infinity).padding(.vertical, 9).foregroundStyle(selected ? .white : CiJingTheme.secondary).background(selected ? CiJingTheme.green : CiJingTheme.paper, in: RoundedRectangle(cornerRadius: 11)) }.buttonStyle(.plain) } }
