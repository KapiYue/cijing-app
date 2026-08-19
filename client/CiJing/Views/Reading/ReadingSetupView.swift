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
    @State private var generating = false
    @State private var generationPhase = 0
    private let onFinish: (() -> Void)?

    init(onFinish: (() -> Void)? = nil) { self.onFinish = onFinish }

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
                    if let existing = previousReading { duplicateNotice(existing) }
                    Button { Task { await generate(regenerate: previousReading != nil) } } label: {
                        HStack { Text(previousReading == nil ? "生成个性化短文" : "仍要生成新的一篇"); Spacer(); Image(systemName: "wand.and.stars") }
                    }
                        .buttonStyle(PrimaryButtonStyle()).disabled(selectedIDs.count < 3 || generating)
                    if previousReading == nil {
                        Text("换个主题、文体、难度或目标词，就会生成一篇全新的短文。")
                            .font(.caption2).foregroundStyle(CiJingTheme.secondary)
                    }
                }
                .padding(20)
                // 从「探索 → 生成短文」进来时底部 Tab 栏是浮在内容之上的（走
                // 「开启今日学习」的 cover 才会隐藏它）。不留出这段空间，最下面
                // 的生成按钮会被 Tab 栏盖死且滚不出来。
                .padding(.bottom, 112)
            }
            if generating {
                ReadingGenerationView(phase: generationPhase, terms: targets.filter { selectedIDs.contains($0.id) }.map(\.term))
                    .transition(.opacity)
                    .zIndex(2)
            }
        }.toolbar {
            // 本页有两种打开方式，出口不一样：
            //   * fullScreenCover（首页「开启今日学习」、阅读页）——没有返回按钮，
            //     「取消」是唯一出口，必须有；
            //   * NavigationLink 推入（探索 → 生成短文）——系统已经给了「返回」，
            //     再挂一个「取消」就是两个并排的返回键，纯属多余。
            // 判据用 `onFinish` 是否为 nil：cover 的两个调用点都传了它（用来收起
            // 自己），push 的调用点 `ReadingSetupView()` 没传。
            //
            // ⚠️ **不要改用 `@Environment(\.isPresented)`**，试过了，不行：
            // NavigationStack 推进来的目标页它同样返回 true，区分不出模态和 push，
            // 结果是「取消」照样两个都显示。
            if onFinish != nil {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
            }
        }
            .task {
                if ProcessInfo.processInfo.arguments.contains("-ui-preview") {
                    targets = store.words
                } else {
                    targets = await store.loadTargets(limit: 14)
                }
                selectedIDs = Set(targets.prefix(10).map(\.id))
            }
            .task(id: generating) {
                guard generating else { return }
                while !Task.isCancelled && generating {
                    try? await Task.sleep(for: .milliseconds(1450))
                    if !Task.isCancelled && generating { generationPhase = (generationPhase + 1) % 3 }
                }
            }
            .fullScreenCover(item: $reading) { selectedReading in
                NavigationStack { ReadingSessionView(reading: selectedReading, onFinish: finishFlow) }
            }
    }

    private func optionSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View { VStack(alignment: .leading, spacing: 11) { Text(title).font(.headline); content() }.cijingCard() }

    /// 当前这套设置是否已经生成过。相同组合在服务端会命中缓存、拿回同一篇，
    /// 与其事后解释「这是旧的那篇」，不如生成前就把选择权交回用户。
    private var previousReading: ReadingSession? {
        store.recentReadings.first {
            $0.theme == theme && $0.style == style && $0.difficulty == difficulty
                && Set($0.targetWordIds) == selectedIDs
        }
    }

    private func duplicateNotice(_ existing: ReadingSession) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Label("这套设置你已经生成过", systemImage: "clock.arrow.circlepath")
                .font(.subheadline.bold())
            Text("《\(existing.title)》——主题、文体、难度和目标词都与那次相同。继续读那篇不会重复占用词库；也可以坚持生成一篇全新的。")
                .font(.caption)
                .foregroundStyle(CiJingTheme.secondary)
                .lineSpacing(3)
            Button { reading = existing } label: {
                HStack { Text("继续读《\(existing.title)》").lineLimit(1); Spacer(); Image(systemName: "arrow.right") }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .cijingCard()
    }

    private func generate(regenerate: Bool = false) async {
        generationPhase = 0
        generating = true
        defer { generating = false }
        do { reading = try await store.generateReading(targets: targets.filter { selectedIDs.contains($0.id) }, theme: theme, style: style, difficulty: difficulty, regenerate: regenerate) }
        catch { errorMessage = error.localizedDescription }
    }

    private func finishFlow() {
        if let onFinish { onFinish() }
        else { dismiss() }
    }
}

private struct OptionChip: View { let title: String; var icon: String?; let selected: Bool; let action: () -> Void; var body: some View { Button(action: action) { HStack(spacing: 5) { if let icon { Image(systemName: icon) }; Text(title) }.font(.caption.bold()).frame(maxWidth: .infinity).padding(.vertical, 9).foregroundStyle(selected ? .white : CiJingTheme.secondary).background(selected ? CiJingTheme.green : CiJingTheme.paper, in: RoundedRectangle(cornerRadius: 11)) }.buttonStyle(.plain) } }

private struct ReadingGenerationView: View {
    let phase: Int
    let terms: [String]
    @State private var orbiting = false

    private let messages = ["正在挑选你的单词", "正在构思故事情节", "快好了再等一下下"]
    private let icons = ["text.badge.checkmark", "wand.and.stars", "book.pages"]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [CiJingTheme.surfaceElevated, CiJingTheme.canvas],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ).ignoresSafeArea()

            Circle().fill(CiJingTheme.purple.opacity(0.12)).frame(width: 310, height: 310).blur(radius: 18).offset(x: 150, y: -270)
            Circle().fill(CiJingTheme.surface.opacity(0.55)).frame(width: 260, height: 260).blur(radius: 24).offset(x: -150, y: 300)

            VStack(spacing: 26) {
                ZStack {
                    Circle().stroke(CiJingTheme.purple.opacity(0.16), lineWidth: 2).frame(width: 126, height: 126)
                    Circle().trim(from: 0.06, to: 0.72)
                        .stroke(CiJingTheme.purple, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .frame(width: 126, height: 126)
                        .rotationEffect(.degrees(orbiting ? 360 : 0))
                    RoundedRectangle(cornerRadius: 25)
                        .fill(CiJingTheme.surface.opacity(0.9))
                        .frame(width: 82, height: 82)
                        .shadow(color: CiJingTheme.purple.opacity(0.16), radius: 18, y: 8)
                    Image(systemName: icons[phase])
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(CiJingTheme.purple)
                        .contentTransition(.symbolEffect(.replace))
                }

                VStack(spacing: 10) {
                    Text("正在为你写一篇")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(CiJingTheme.secondary)
                    Text("只属于你的短文")
                        .font(.system(size: 31, weight: .bold, design: .rounded))
                        .foregroundStyle(CiJingTheme.ink)
                }

                VStack(spacing: 14) {
                    Text(messages[phase])
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(CiJingTheme.purpleDark)
                        .contentTransition(.numericText())
                        .id(phase)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    HStack(spacing: 8) {
                        ForEach(messages.indices, id: \.self) { index in
                            Capsule().fill(index == phase ? CiJingTheme.purple : CiJingTheme.purple.opacity(0.16))
                                .frame(width: index == phase ? 30 : 9, height: 9)
                                .animation(.easeInOut(duration: 0.25), value: phase)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 11) {
                    Text("本篇会自然融入")
                        .font(.caption.bold()).foregroundStyle(CiJingTheme.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(Array(terms.prefix(8)), id: \.self) { term in
                                Text(term).font(.caption.bold()).foregroundStyle(CiJingTheme.purpleDark)
                                    .padding(.horizontal, 10).padding(.vertical, 7)
                                    .background(CiJingTheme.purpleSoft, in: Capsule())
                            }
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: 340, alignment: .leading)
                .background(CiJingTheme.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 20))

                Text("相同选词与设置会优先复用缓存，通常只需一点点时间")
                    .font(.caption2).foregroundStyle(CiJingTheme.secondary)
            }
            .padding(24)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { orbiting = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(messages[phase])
    }
}
