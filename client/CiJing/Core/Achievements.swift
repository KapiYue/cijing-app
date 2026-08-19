import SwiftUI

/// 成就的级别。四档，同一枚徽章原地升级。
enum AchievementTier: Int, CaseIterable {
    case bronze = 1, silver, gold, platinum

    var title: String {
        switch self {
        case .bronze: "铜章"
        case .silver: "银章"
        case .gold: "金章"
        case .platinum: "铂金章"
        }
    }

    var color: Color {
        switch self {
        case .bronze: Color(red: 0.80, green: 0.50, blue: 0.20)
        case .silver: Color(red: 0.55, green: 0.58, blue: 0.62)
        case .gold: Color(red: 0.85, green: 0.65, blue: 0.13)
        case .platinum: CiJingTheme.purple
        }
    }
}

/// 一条成就线：一个可量化的指标，四个门槛，每档一个名字。
///
/// 等级不落库——它永远由当前数据推导。落库的只有解锁时刻（`achievements` 表），
/// 用来保证弹窗在跨级那一刻只出现一次。
struct AchievementTrack: Identifiable {
    let id: String
    let name: String
    let icon: String
    /// 四个门槛，递增，分别对应铜/银/金/铂金。
    let thresholds: [Int]
    /// 每档的称号，与 `thresholds` 一一对应。
    let titles: [String]
    /// 达成这一档需要做什么，用于弹窗副标题。
    let requirement: (Int) -> String

    /// 当前值对应的档位；未达铜章门槛时为 nil。
    func tier(for value: Int) -> AchievementTier? {
        var reached: AchievementTier?
        for (index, threshold) in thresholds.enumerated() where value >= threshold {
            reached = AchievementTier(rawValue: index + 1)
        }
        return reached
    }

    func title(for tier: AchievementTier) -> String { titles[tier.rawValue - 1] }
    func threshold(for tier: AchievementTier) -> Int { thresholds[tier.rawValue - 1] }

    /// 距离下一档还差多少；已满级返回 nil。
    func next(after tier: AchievementTier?) -> (tier: AchievementTier, threshold: Int)? {
        let nextRaw = (tier?.rawValue ?? 0) + 1
        guard let nextTier = AchievementTier(rawValue: nextRaw) else { return nil }
        return (nextTier, thresholds[nextRaw - 1])
    }
}

enum AchievementCatalog {
    /// 三条线：连续天数、阅读篇数、词汇量。
    ///
    /// 前两条覆盖「每天都来」和「今天继续学」；`mastered` 覆盖「学到了什么」——
    /// 前两条衡量的都是行为，只有它衡量结果，缺了这一条，用户再怎么坚持也看不到
    /// 词汇量本身在涨。
    ///
    /// 三条线的当前值全部来自 `get_daily_plan` 已有的返回字段，**没有一条需要新的
    /// 后端改动**。正确率那条要聚合 `practice_attempts`，得单开一份迁移，留到下一版。
    static let streak = AchievementTrack(
        id: "streak",
        name: "连续学习",
        icon: "flame.fill",
        thresholds: [1, 7, 30, 100],
        titles: ["初来乍到", "七日成习", "月度常客", "百日不辍"],
        requirement: { days in days == 1 ? "完成第一天的学习" : "连续 \(days) 天完成学习" }
    )

    static let reading = AchievementTrack(
        id: "reading",
        name: "阅读篇数",
        icon: "book.fill",
        thresholds: [1, 10, 50, 200],
        titles: ["开卷有益", "十篇入门", "五十篇有成", "两百篇通读"],
        requirement: { count in count == 1 ? "读完第一篇个性化短文" : "累计读完 \(count) 篇短文" }
    )

    /// 用「已掌握」而不是「已收藏」：收藏只是把词放进来，涨得快也太廉价，
    /// 挂成就会变成鼓励囤词。`mastered` 要真的复习到位才会置位，才配得上徽章。
    ///
    /// 门槛比另外两条稀疏（10 / 50 / 200 / 500），因为掌握一个词的代价远高于
    /// 读完一篇短文或来一天。审核演示账号当前是 66，正好落在银章档，
    /// 铜银两级看得到、金铂两级够得着。
    static let mastered = AchievementTrack(
        id: "mastered",
        name: "词汇量",
        icon: "checkmark.seal.fill",
        thresholds: [10, 50, 200, 500],
        titles: ["初识十词", "五十词在握", "两百词傍身", "五百词成城"],
        requirement: { count in "累计掌握 \(count) 个单词" }
    )

    static let all: [AchievementTrack] = [streak, reading, mastered]

    /// 从今日计划里取每条线的当前值。连续天数用的是 `completed = true` 的口径，
    /// 与练习总结页的完成判定一致（见 202608170003 迁移）。
    static func value(for track: AchievementTrack, plan: DailyPlan) -> Int {
        switch track.id {
        case streak.id: plan.streakDays
        case reading.id: plan.readingTotal
        case mastered.id: plan.masteredCount
        default: 0
        }
    }
}

/// 一次刚刚发生的解锁，用于驱动弹窗。
struct AchievementUnlock: Identifiable {
    let track: AchievementTrack
    let tier: AchievementTier
    var id: String { "\(track.id)-\(tier.rawValue)" }

    var title: String { track.title(for: tier) }
    var requirement: String { track.requirement(track.threshold(for: tier)) }
}

/// 成就常驻展示位，练习总结页与「学习成就」页共用。
///
/// 在此之前成就唯一的露面机会是跨级那一瞬间的弹窗（`badgeOverlay`）——用户看不到
/// 自己有哪几条线、各自到了哪一档、离下一档还差多少，徽章拿到手就消失了。
struct AchievementBoard: View {
    let plan: DailyPlan
    /// 总结页里它是众多卡片之一，需要标题；独立页里标题已经在导航栏上了。
    var showsHeading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsHeading { Label("成就", systemImage: "rosette").font(.headline) }
            ForEach(AchievementCatalog.all) { track in
                AchievementProgressRow(track: track, value: AchievementCatalog.value(for: track, plan: plan))
            }
            Text("徽章只在跨级时弹一次，这里随时可以回来看进度")
                .font(.caption2).foregroundStyle(CiJingTheme.secondary)
        }.cijingCard()
    }
}

/// 独立的成就页。首页「连续 N 天」那枚 pill 点进来，不必先学完一轮才看得到。
struct AchievementsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("你已经走到这里")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        Text("每条线都按数值分四档，同一枚徽章会原地升级。等级由你的真实数据推导，不会因为换设备而丢。")
                            .font(CiJingTypography.body).foregroundStyle(CiJingTheme.secondary).lineSpacing(5)
                    }.cijingCard(padding: 22)

                    AchievementBoard(plan: store.plan, showsHeading: false)
                }
                .padding(18)
                .padding(.bottom, 90)
            }
            .refreshable { await store.refreshAll() }
        }
        .navigationTitle("学习成就")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 一条成就线的当前进度：已达档位 + 距下一档还差多少。
private struct AchievementProgressRow: View {
    let track: AchievementTrack
    let value: Int

    var body: some View {
        let tier = track.tier(for: value)
        let next = track.next(after: tier)
        // 进度条量的是「当前档到下一档」这一段，不是从零开始——否则铂金前夜看着
        // 才走了一半，反而像退步了。满级时填满。
        let floorValue = tier.map { track.threshold(for: $0) } ?? 0
        let progress: Double = {
            guard let next else { return 1 }
            let span = Double(next.threshold - floorValue)
            guard span > 0 else { return 1 }
            return min(1, max(0, Double(value - floorValue) / span))
        }()

        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                Image(systemName: track.icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tier?.color ?? CiJingTheme.secondary)
                    .frame(width: 28, height: 28)
                    .background((tier?.color ?? CiJingTheme.secondary).opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.name).font(.subheadline.bold()).foregroundStyle(CiJingTheme.ink)
                    Text(tier.map { "\(track.title(for: $0)) · \($0.title)" } ?? "还未解锁")
                        .font(.caption).foregroundStyle(tier == nil ? CiJingTheme.secondary : (tier?.color ?? CiJingTheme.secondary))
                }
                Spacer()
                Text("\(value)").font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(CiJingTheme.ink)
            }

            ProgressView(value: progress)
                .tint(tier?.color ?? CiJingTheme.purple)

            Text(next.map { "距 \(track.title(for: $0.tier)) 还差 \(max(0, $0.threshold - value))" } ?? "已满级")
                .font(.caption2).foregroundStyle(CiJingTheme.secondary)
        }
    }
}
