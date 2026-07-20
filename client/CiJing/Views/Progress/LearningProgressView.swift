import SwiftUI

struct LearningProgressView: View {
    @EnvironmentObject private var store: AppStore
    private var maxDaily: Int { max(1, store.activity.prefix(7).map { $0.reviewedCount + $0.learnedCount + $0.practiceCount }.max() ?? 1) }

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) { Text("积累会慢慢长出来").font(.system(size: 29, weight: .bold, design: .serif)); Text("记忆强度来自持续的重遇，而不是一次记住。").foregroundStyle(CiJingTheme.secondary) }
                    HStack { ProgressStatCard(value: store.plan.learnedCount, title: "已学习", icon: "books.vertical", tint: CiJingTheme.green); ProgressStatCard(value: store.plan.masteredCount, title: "已掌握", icon: "checkmark.seal", tint: .teal); ProgressStatCard(value: store.plan.streakDays, title: "连续天数", icon: "flame", tint: .orange) }
                    activityChart
                    statusDistribution
                    if !store.weakWords.isEmpty { weakList }
                }.padding(18)
            }
        }.navigationTitle("学习进度").navigationBarTitleDisplayMode(.inline).task { if store.words.isEmpty { await store.refreshAll() } }
    }

    private var activityChart: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack { Text("最近 7 天").font(.headline); Spacer(); Text("练习与复习次数").font(.caption).foregroundStyle(CiJingTheme.secondary) }
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(Array(store.activity.prefix(7).reversed())) { day in
                    let count = day.reviewedCount + day.learnedCount + day.practiceCount
                    VStack(spacing: 6) { Text("\(count)").font(.caption2).foregroundStyle(CiJingTheme.secondary); RoundedRectangle(cornerRadius: 5).fill(count > 0 ? CiJingTheme.green : Color.gray.opacity(0.15)).frame(height: max(5, CGFloat(count) / CGFloat(maxDaily) * 100)); Text(shortDate(day.activityDate)).font(.caption2).foregroundStyle(CiJingTheme.secondary) }.frame(maxWidth: .infinity)
                }
                if store.activity.isEmpty { Text("完成一次学习后，这里会显示你的节奏。").font(.caption).foregroundStyle(CiJingTheme.secondary).frame(maxWidth: .infinity, minHeight: 110) }
            }.frame(height: 135, alignment: .bottom)
        }.cijingCard()
    }

    private var statusDistribution: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("词库状态").font(.headline)
            ForEach(WordStatus.allCases.filter { $0 != .ignored }) { status in
                let count = store.words.filter { $0.status == status }.count
                HStack { Label(status.title, systemImage: status.icon).font(.subheadline).foregroundStyle(status.color).frame(width: 90, alignment: .leading); GeometryReader { proxy in ZStack(alignment: .leading) { Capsule().fill(Color.gray.opacity(0.1)); Capsule().fill(status.color.opacity(0.75)).frame(width: proxy.size.width * CGFloat(count) / CGFloat(max(1, store.words.count))) } }.frame(height: 8); Text("\(count)").font(.caption.bold()).frame(width: 28, alignment: .trailing) }
            }
        }.cijingCard()
    }

    private var weakList: some View {
        VStack(alignment: .leading, spacing: 10) { Text("优先改善").font(.headline); ForEach(store.weakWords.prefix(5)) { word in NavigationLink { WordDetailView(word: word) } label: { HStack { VStack(alignment: .leading) { Text(word.term).font(.headline); Text(word.displayMeaning).font(.caption).foregroundStyle(CiJingTheme.secondary).lineLimit(1) }; Spacer(); Text("错 \(word.errorCount) 次").font(.caption).foregroundStyle(.red); Image(systemName: "chevron.right").foregroundStyle(.tertiary) }.padding(.vertical, 5) }.buttonStyle(.plain) } }.cijingCard()
    }
    private func shortDate(_ value: String) -> String { let parts = value.split(separator: "-"); return parts.count == 3 ? "\(parts[1])/\(parts[2])" : value }
}

private struct ProgressStatCard: View { let value: Int; let title, icon: String; let tint: Color; var body: some View { VStack(alignment: .leading, spacing: 8) { Image(systemName: icon).foregroundStyle(tint); Text("\(value)").font(.title2.bold()).foregroundStyle(CiJingTheme.ink); Text(title).font(.caption2).foregroundStyle(CiJingTheme.secondary) }.frame(maxWidth: .infinity, alignment: .leading).cijingCard() } }
