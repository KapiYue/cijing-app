import SwiftUI

struct ReadingHubView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingSetup = false

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("把你的词，写进一个世界")
                            .font(.system(size: 29, weight: .bold, design: .serif))
                        Text("AI 会平衡新词、复习词和薄弱词，生成自然连贯的个性化阅读。")
                            .foregroundStyle(CiJingTheme.secondary)
                    }
                    Button { showingSetup = true } label: {
                        HStack { VStack(alignment: .leading) { Text("生成今日短文").font(.headline); Text("选择主题、风格和难度").font(.caption).opacity(0.75) }; Spacer(); Image(systemName: "wand.and.stars").font(.title2) }
                    }.buttonStyle(PrimaryButtonStyle())
                    if store.recentReadings.isEmpty {
                        ContentUnavailableView("还没有 AI 阅读", systemImage: "text.book.closed", description: Text("先收藏至少 3 个词，然后生成第一篇短文。"))
                            .frame(height: 280)
                    } else {
                        Text("阅读历史").font(.headline).padding(.top, 6)
                        ForEach(store.recentReadings) { reading in
                            NavigationLink { ReadingSessionView(reading: reading) } label: { ReadingHistoryRow(reading: reading) }.buttonStyle(.plain)
                        }
                    }
                }.padding(18)
            }
        }.navigationTitle("AI 阅读").navigationBarTitleDisplayMode(.inline)
            .task { if store.recentReadings.isEmpty { await store.refreshAll() } }
            .fullScreenCover(isPresented: $showingSetup) { NavigationStack { ReadingSetupView() } }
    }
}

private struct ReadingHistoryRow: View {
    let reading: ReadingSession
    var body: some View {
        HStack(spacing: 13) {
            VStack { Image(systemName: reading.completedAt == nil ? "bookmark" : "checkmark").font(.headline); Text("\(reading.estimatedMinutes)m").font(.caption2) }
                .foregroundStyle(reading.completedAt == nil ? CiJingTheme.warm : CiJingTheme.green).frame(width: 46, height: 58).background(CiJingTheme.paper, in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 5) { Text(reading.title).font(.headline).foregroundStyle(CiJingTheme.ink); Text(reading.subtitle ?? "个性化英语阅读").font(.caption).foregroundStyle(CiJingTheme.secondary).lineLimit(1); HStack { Text(ReadingOptions.label(for: reading.theme)); Text("·"); Text(ReadingOptions.label(for: reading.difficulty)); Text("· \(reading.targetTerms.count) 词") }.font(.caption2).foregroundStyle(CiJingTheme.secondary) }
            Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }.cijingCard()
    }
}

enum ReadingOptions {
    static let themes = [("daily_life", "日常生活", "cup.and.saucer"), ("travel", "旅行", "airplane"), ("business", "商业", "briefcase"), ("technology", "科技", "cpu"), ("campus", "校园", "graduationcap"), ("workplace", "职场", "building.2"), ("news", "新闻", "newspaper"), ("psychology", "心理学", "brain.head.profile"), ("movies", "电影", "film"), ("sports", "体育", "figure.run")]
    static let styles = [("story", "故事"), ("article", "文章"), ("dialogue", "对话"), ("news", "新闻风")]
    static let difficulties = [("beginner", "入门"), ("elementary", "初级"), ("intermediate", "中级"), ("upper_intermediate", "中高级"), ("advanced", "高级")]
    static func label(for value: String) -> String { themes.first { $0.0 == value }?.1 ?? styles.first { $0.0 == value }?.1 ?? difficulties.first { $0.0 == value }?.1 ?? value }
}

