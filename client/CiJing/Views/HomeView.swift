import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var api: SupabaseAPI
    @State private var showingSetup = false
    @State private var notice: String?

    private let exploreItems: [ExploreItem] = [
        .init(title: "自由练习", subtitle: "六种模式随心练", badge: "6 种", icon: "arrow.up.right", tint: CiJingTheme.purple, soft: CiJingTheme.purpleSoft),
        .init(title: "闪卡速刷", subtitle: "左右滑快速过词", badge: "12 词", icon: "rectangle.stack", tint: Color(red: 192 / 255, green: 106 / 255, blue: 165 / 255), soft: Color(red: 248 / 255, green: 234 / 255, blue: 244 / 255)),
        .init(title: "语境回顾", subtitle: "回到遇见它的句子", badge: "3 组", icon: "text.quote", tint: Color(red: 84 / 255, green: 173 / 255, blue: 120 / 255), soft: Color(red: 233 / 255, green: 248 / 255, blue: 239 / 255)),
        .init(title: "磨耳朵", subtitle: "免动手的听读复习", badge: "8 min", icon: "headphones", tint: Color(red: 220 / 255, green: 139 / 255, blue: 67 / 255), soft: Color(red: 1, green: 241 / 255, blue: 228 / 255)),
        .init(title: "错题本", subtitle: "逐个攻克易错词", badge: "3 题", icon: "exclamationmark", tint: CiJingTheme.danger, soft: Color(red: 252 / 255, green: 236 / 255, blue: 239 / 255)),
        .init(title: "学习统计", subtitle: "看见每天的进步", badge: "+18%", icon: "chart.bar", tint: Color(red: 173 / 255, green: 99 / 255, blue: 180 / 255), soft: Color(red: 246 / 255, green: 234 / 255, blue: 247 / 255)),
        .init(title: "成就", subtitle: "收藏你的学习时刻", badge: "1 枚", icon: "medal", tint: Color(red: 217 / 255, green: 155 / 255, blue: 55 / 255), soft: Color(red: 1, green: 246 / 255, blue: 223 / 255)),
        .init(title: "AI 角色对话", subtitle: "把新词真正说出来", badge: "NEW", icon: "sparkles", tint: Color(red: 93 / 255, green: 143 / 255, blue: 201 / 255), soft: Color(red: 234 / 255, green: 243 / 255, blue: 251 / 255))
    ]

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    PageHeader(
                        title: greeting,
                        subtitle: store.plan.completedToday ? "今天也完成了一次小小的抵达" : "把今天收藏的词，读成一个故事",
                        trailing: AnyView(avatar)
                    )
                    .padding(.bottom, 18)

                    if store.plan.completedToday { completedPlanCard } else { startCard }

                    SectionHeading(title: store.plan.completedToday ? "探索" : "最近的短文", detail: store.plan.completedToday ? "换一种方式记住" : nil)
                        .padding(.top, 25)
                        .padding(.bottom, 13)

                    if store.plan.completedToday { exploreGrid } else { recentEmpty }

                    if store.plan.completedToday {
                        SectionHeading(title: "最近的短文", detail: store.recentReadings.isEmpty ? nil : "查看全部")
                            .padding(.top, 25)
                            .padding(.bottom, 13)
                    }

                    recentReading
                    tipCard
                        .padding(.top, 14)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 112)
            }
            .refreshable { await store.refreshAll() }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await store.refreshAll() }
        .fullScreenCover(isPresented: $showingSetup) { NavigationStack { ReadingSetupView() } }
        .alert("提示", isPresented: Binding(get: { notice != nil || store.errorMessage != nil }, set: { if !$0 { notice = nil; store.errorMessage = nil } })) {
            Button("知道了") { notice = nil; store.errorMessage = nil }
        } message: { Text(notice ?? store.errorMessage ?? "") }
    }

    private var avatar: some View {
        Text(profileInitial)
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 42, height: 42)
            .background(LinearGradient(colors: [Color(red: 247 / 255, green: 207 / 255, blue: 169 / 255), CiJingTheme.warm], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .shadow(color: CiJingTheme.warm.opacity(0.18), radius: 9, y: 5)
    }

    private var startCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            OrbitMark().padding(.bottom, 18)
            Text("今日留白，等你点亮")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .tracking(-0.8)
            Text("已从浏览器同步 \(store.words.filter { $0.status == .new }.count) 个新词。先认识它们，再让 AI 把单词写进一篇只属于你的短文。")
                .font(CiJingTypography.body)
                .foregroundStyle(CiJingTheme.secondary)
                .lineSpacing(6)
                .padding(.top, 10)
                .padding(.bottom, 22)
            Button {
                if store.words.count < 3 { notice = "请先在词库导入或从浏览器收藏至少 3 个单词。" }
                else { showingSetup = true }
            } label: { Text("开启今日学习") }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(24)
        .background(LinearGradient(colors: [Color(red: 248 / 255, green: 241 / 255, blue: 1), Color(red: 234 / 255, green: 220 / 255, blue: 249 / 255)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color(red: 232 / 255, green: 222 / 255, blue: 242 / 255)))
        .shadow(color: Color(red: 66 / 255, green: 49 / 255, blue: 87 / 255).opacity(0.09), radius: 21, y: 10)
    }

    private var completedPlanCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("今日计划").font(.caption).foregroundStyle(CiJingTheme.secondary)
                    Text("学习已完成").font(.system(size: 20, weight: .bold, design: .rounded))
                }
                Spacer()
                Label("连续 \(store.plan.streakDays) 天", systemImage: "flame.fill")
                    .font(.caption.bold())
                    .foregroundStyle(Color(red: 201 / 255, green: 120 / 255, blue: 50 / 255))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Color(red: 1, green: 241 / 255, blue: 228 / 255), in: RoundedRectangle(cornerRadius: 12))
            }
            HStack(spacing: 8) {
                PlanMetric(number: "\(max(store.plan.learnedCount, store.plan.newSuggested))", label: "新词", tint: Color(red: 238 / 255, green: 228 / 255, blue: 251 / 255))
                PlanMetric(number: "\(store.plan.practiceToday)", label: "练习", tint: Color(red: 243 / 255, green: 232 / 255, blue: 248 / 255))
                PlanMetric(number: "\(Int(store.plan.progress * 100))%", label: "完成", tint: Color(red: 234 / 255, green: 223 / 255, blue: 245 / 255))
            }
            VStack(spacing: 8) {
                HStack { Text("今日进度"); Spacer(); Text("100%").bold() }.font(.caption).foregroundStyle(CiJingTheme.secondary)
                ProgressView(value: 1).tint(CiJingTheme.purple)
            }
        }
        .padding(20)
        .background(LinearGradient(colors: [Color(red: 247 / 255, green: 240 / 255, blue: 1), Color(red: 234 / 255, green: 220 / 255, blue: 248 / 255)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color(red: 223 / 255, green: 207 / 255, blue: 238 / 255)))
    }

    private var exploreGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 11), GridItem(.flexible())], spacing: 11) {
            ForEach(exploreItems) { item in
                Button { notice = "\(item.title)已准备好，完整交互将在后续学习流程中打开。" } label: {
                    ExploreCard(item: item)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var recentEmpty: some View {
        HStack(spacing: 14) {
            Image(systemName: "book.closed")
                .foregroundStyle(CiJingTheme.warm)
                .frame(width: 40, height: 40)
                .background(Color(red: 1, green: 241 / 255, blue: 228 / 255), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 3) {
                Text("还没有完成的短文").font(CiJingTypography.rowTitle).foregroundStyle(CiJingTheme.secondary)
                Text("今天的第一篇，会在这里出现").font(CiJingTypography.supporting).foregroundStyle(CiJingTheme.secondary)
            }
            Spacer()
        }.cijingCard()
    }

    @ViewBuilder private var recentReading: some View {
        if store.plan.completedToday, let reading = store.recentReadings.first {
            NavigationLink { ReadingSessionView(reading: reading) } label: {
                HStack(spacing: 13) {
                    Image(systemName: "book.closed.fill")
                        .foregroundStyle(CiJingTheme.purple)
                        .frame(width: 42, height: 42)
                        .background(CiJingTheme.purpleSoft, in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(reading.title).font(.subheadline.bold()).foregroundStyle(CiJingTheme.ink).lineLimit(1)
                        Text("\(ReadingOptions.label(for: reading.theme)) · \(reading.estimatedMinutes) 分钟 · \(reading.targetTerms.count) 个目标词")
                            .font(CiJingTypography.supporting).foregroundStyle(CiJingTheme.secondary).lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(CiJingTheme.secondary.opacity(0.55))
                }.cijingCard()
            }.buttonStyle(.plain)
        } else if store.plan.completedToday {
            recentEmpty
        }
    }

    private var tipCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(store.plan.completedToday ? "🔥" : "💡")
            Text(store.plan.completedToday ? "词库互动火焰已点亮。继续学习，火焰会随着连续天数长大。" : "温馨提示：浏览器扩展收藏的单词会自动出现在词库，并优先安排进今日学习。")
                .font(.system(size: 13)).foregroundStyle(Color(red: 129 / 255, green: 121 / 255, blue: 134 / 255)).lineSpacing(4)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 1, green: 250 / 255, blue: 245 / 255), in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(Color(red: 250 / 255, green: 236 / 255, blue: 221 / 255)))
    }

    private var profileInitial: String {
        let name = store.profile?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((name?.isEmpty == false ? name! : api.currentEmail).prefix(1)).uppercased()
    }

    private var greeting: String {
        let name = store.profile?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let visibleName = name?.isEmpty == false ? name! : api.currentEmail
        let hour = Calendar.current.component(.hour, from: .now)
        return "\(hour < 11 ? "早上好" : hour < 18 ? "下午好" : "晚上好")，\(visibleName)"
    }
}

private struct OrbitMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 21).fill(CiJingTheme.purpleSoft)
            Ellipse().stroke(CiJingTheme.purple.opacity(0.28)).frame(width: 48, height: 19).rotationEffect(.degrees(-25))
            Ellipse().stroke(CiJingTheme.purple.opacity(0.28)).frame(width: 19, height: 48).rotationEffect(.degrees(-25))
            Circle().fill(CiJingTheme.purple).frame(width: 11, height: 11).overlay(Circle().stroke(.white, lineWidth: 5))
        }.frame(width: 64, height: 64)
    }
}

private struct PlanMetric: View {
    let number: String
    let label: String
    let tint: Color
    var body: some View {
        VStack(spacing: 4) {
            Text(number).font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(CiJingTheme.ink)
            Text(label).font(CiJingTypography.supporting).foregroundStyle(CiJingTheme.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(tint, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct ExploreItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let badge: String
    let icon: String
    let tint: Color
    let soft: Color
}

private struct ExploreCard: View {
    let item: ExploreItem
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Image(systemName: item.icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(item.tint)
                    .frame(width: 34, height: 34)
                    .background(item.soft, in: RoundedRectangle(cornerRadius: 12))
                Spacer()
                Text(item.badge).font(.system(size: 11, weight: .heavy)).foregroundStyle(item.tint).padding(.horizontal, 6).padding(.vertical, 4).background(item.soft, in: RoundedRectangle(cornerRadius: 7))
            }
            Spacer(minLength: 8)
            Text(item.title).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(CiJingTheme.ink)
            Text(item.subtitle).font(CiJingTypography.supporting).foregroundStyle(CiJingTheme.secondary).padding(.top, 3)
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
        .background(LinearGradient(colors: [item.soft.opacity(0.8), item.soft.opacity(0.42)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(item.tint.opacity(0.18)))
    }
}
