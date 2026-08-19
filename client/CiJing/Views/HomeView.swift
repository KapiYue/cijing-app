import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var api: SupabaseAPI
    @State private var showingSetup = false
    @State private var notice: String?

    /// 探索卡片的角标。**这里的每一个数都必须来自 `store`**——原先六个角标写的是
    /// `12 题` / `+18%` / `2 词` / `8 min` / `3 篇` 五个硬编码字符串，不随账号变化，
    /// 于是出现过「首页显示短文 1、阅读历史角标写 3 篇」这种当场自相矛盾的画面。
    /// 与 1.0.1 删掉的硬编码徽章是同一类问题，那次漏了这里。
    ///
    /// 推导不出真实值的就**不显示角标**（`nil`），不要为了视觉整齐编一个。
    /// 「跟读训练」的时长依赖具体短文，进首页时算不出来，所以留空。
    ///
    /// 🔴 **角标必须和「点进去看到的东西」同源**，光是「真实数据」还不够。
    /// 初版改造踩了两次：
    ///   * 巩固练习曾接 `plan.reviewDue`，但点进去练的是 `recentReadings.first`
    ///     那篇短文的目标词，跟待复习队列毫无关系；而且 `review_due` 在 SQL 里
    ///     被 `least(…, daily_review_goal)` 截过，本身也不是「总共待复习多少」。
    ///   * 阅读历史曾接 `plan.reading_total`，那是**只数已读完**的
    ///     （`completed_at is not null`）；而阅读历史页列的是 `recentReadings`，
    ///     不论读没读完都在里面。生成了没读完的短文会出现在列表里却不计入角标。
    /// 现在两个都改成与目标页同一个数据源。
    private var exploreItems: [ExploreItem] {
        [
            .init(destination: .readingSetup, title: "生成短文", subtitle: "把弱词写进故事", badge: "AI", icon: "wand.and.stars", tint: CiJingTheme.purple),
            .init(destination: .practice, title: "巩固练习", subtitle: "读完立即练一轮", badge: (store.recentReadings.first?.targetTerms.count).map { "\($0) 词" }, icon: "checkmark.circle", tint: CiJingTheme.rose),
            .init(destination: .progress, title: "学习进度", subtitle: "看见每天的积累", badge: store.plan.streakDays > 0 ? "连续 \(store.plan.streakDays) 天" : nil, icon: "chart.bar", tint: CiJingTheme.success),
            .init(destination: .weakWords, title: "薄弱词", subtitle: "优先攻克易错词", badge: store.plan.weakCount > 0 ? "\(store.plan.weakCount) 词" : nil, icon: "exclamationmark", tint: CiJingTheme.danger),
            .init(destination: .shadowing, title: "跟读训练", subtitle: "逐句听读与纠音", badge: nil, icon: "mic.fill", tint: CiJingTheme.warm),
            // 与阅读历史页列的是同一批（`recentReadings`，服务端 limit 20）。
            // 上限 20 意味着超过之后角标不再增长——但页面本身也只展示这 20 条，
            // 数字与点进去看到的一致，这比显示一个点不开的总数更有用。
            .init(destination: .readingHistory, title: "阅读历史", subtitle: "继续最近的短文", badge: store.recentReadings.isEmpty ? nil : "\(store.recentReadings.count) 篇", icon: "clock.arrow.circlepath", tint: CiJingTheme.blue)
        ]
    }

    var body: some View {
        ZStack {
            PaperBackground()
            if store.hasLoadedAccountData {
                ScrollView {
                    // 🔴 用 VStack 不用 LazyVStack。Lazy 版会把滚出屏幕的行从视图树上
                    // 拆掉，而这里面有通往学习流程的 NavigationLink——来源一旦消失，
                    // SwiftUI 会把推进去的页面连同盖在它上面的 fullScreenCover 一起弹掉。
                    // 首页内容是有界的（固定区块 + 几篇短文），不 Lazy 没有性能问题。
                    VStack(alignment: .leading, spacing: 0) {
                        PageHeader(
                            title: greeting,
                            subtitle: store.plan.completedToday ? "今天也完成了一次小小的抵达" : "把今天收藏的词，读成一个故事",
                            trailing: AnyView(avatar)
                        )
                        .padding(.bottom, 18)

                        if store.plan.completedToday { completedPlanCard } else { startCard }

                        learningSnapshot
                            .padding(.top, 13)

                        SectionHeading(title: "最近的短文", detail: store.recentReadings.isEmpty ? nil : "已保存 \(store.recentReadings.count) 篇")
                            .padding(.top, 25)
                            .padding(.bottom, 13)
                        recentReading

                        // 🔴 **不要再把「探索」包进 `if store.plan.completedToday`。**
                        //
                        // 通往 ReadingSetupView 的 NavigationLink 就在 exploreGrid 里。
                        // 包在这个条件下时，用户进入生成短文之后，只要 store.plan 被刷新
                        // （.task 的 refreshAll()、下拉刷新、或流程内部触发的刷新）让这个
                        // 分支重新求值，NavigationLink 的来源就从视图树上消失，SwiftUI
                        // 随即弹掉推进去的页面——盖在它上面的阅读页、练习页一起塌。
                        // 链路是 HomeView --push--> ReadingSetupView --cover--> ReadingSessionView
                        // --cover--> PracticeSessionView，抽掉最底下一环，上面三层全没。
                        //
                        // 这就是 11.4「学习中突然回到首页」的真正根因（此前误归到 087f884
                        // 修的两个「用户取消」诱因上，那两个是真 bug 但不是这个的原因）。
                        //
                        // 顺带一个产品上的好处：没完成今日学习时本来也该能生成短文、查薄弱词，
                        // 原先要先完成学习才看得到这些入口，本身就说不通。
                        SectionHeading(title: "探索", detail: "换一种方式记住")
                            .padding(.top, 25)
                            .padding(.bottom, 13)
                        exploreGrid

                        tipCard
                            .padding(.top, 14)
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 112)
                }
                .refreshable { await store.refreshAll() }
                .transition(.opacity)
            } else {
                initialLoading
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.hasLoadedAccountData)
        .toolbar(.hidden, for: .navigationBar)
        .task { await store.refreshAll() }
        .fullScreenCover(isPresented: $showingSetup) { NavigationStack { ReadingSetupView(onFinish: { showingSetup = false }) } }
        // 学习流程盖在首页之上，收起时首页从未离开视图层级，上面的 `.task` 不会重跑。
        // 没有这一步，首页就只能靠流程里顺手调的 refreshPlan() 撞对，一旦那次请求
        // 失败或仍在飞行中，卡片会停在旧状态且无法自愈。
        .onChange(of: showingSetup) { _, presented in
            guard !presented else { return }
            Task { await store.refreshAfterLearningFlow() }
        }
        .alert("提示", isPresented: Binding(get: { notice != nil || store.errorMessage != nil }, set: { if !$0 { notice = nil; store.errorMessage = nil } })) {
            Button("知道了") { notice = nil; store.errorMessage = nil }
        } message: { Text(notice ?? store.errorMessage ?? "") }
    }

    private var initialLoading: some View {
        VStack(spacing: 16) {
            OrbitMark()
            ProgressView()
                .controlSize(.large)
                .tint(CiJingTheme.purple)
            Text("正在同步学习记录")
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(CiJingTheme.ink)
            Text("正在读取你的词库、短文和学习进度…")
                .font(CiJingTypography.supporting)
                .foregroundStyle(CiJingTheme.secondary)
        }
        .padding(30)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在同步学习记录")
    }

    private var avatar: some View {
        Text(profileInitial)
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 42, height: 42)
            .background(CiJingTheme.avatarGradient, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
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
        .background(CiJingTheme.featuredGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(CiJingTheme.line))
        .shadow(color: CiJingTheme.shadow.opacity(0.12), radius: 21, y: 10)
    }

    private var completedPlanCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("今日计划").font(.caption).foregroundStyle(CiJingTheme.secondary)
                    Text("学习已完成").font(.system(size: 20, weight: .bold, design: .rounded))
                }
                Spacer()
                // 点进成就页。此前成就只在练习总结页出现，也就是**必须学完一轮**
                // 才看得到自己有哪几条线、到了哪一档——想随手看一眼进度没有入口。
                // 连续天数本身就是其中一条线，从它进去最自然。
                NavigationLink { AchievementsView() } label: {
                    HStack(spacing: 4) {
                        Label("连续 \(store.plan.streakDays) 天", systemImage: "flame.fill")
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                    }
                    .font(.caption.bold())
                    .foregroundStyle(CiJingTheme.warmStrong)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(CiJingTheme.warmSoft, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                PlanMetric(number: "\(store.plan.newSuggested)", label: "新词", tint: CiJingTheme.purpleSoft)
                PlanMetric(number: "\(store.plan.practiceToday)", label: "练习", tint: CiJingTheme.surfaceMuted)
                PlanMetric(number: "\(Int(store.plan.progress * 100))%", label: "完成", tint: CiJingTheme.surfaceElevated)
            }
            VStack(spacing: 8) {
                HStack { Text("今日进度"); Spacer(); Text("100%").bold() }.font(.caption).foregroundStyle(CiJingTheme.secondary)
                ProgressView(value: 1).tint(CiJingTheme.purple)
            }
        }
        .padding(20)
        .background(CiJingTheme.featuredGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(CiJingTheme.line))
    }

    private var exploreGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 11), GridItem(.flexible())], spacing: 11) {
            ForEach(exploreItems) { item in
                NavigationLink { exploreDestination(item.destination) } label: {
                    ExploreCard(item: item)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var learningSnapshot: some View {
        HStack(spacing: 0) {
            SnapshotMetric(value: "\(store.plan.learnedCount)", label: "已学习", icon: "books.vertical.fill")
            SnapshotDivider()
            SnapshotMetric(value: "\(store.plan.masteredCount)", label: "已掌握", icon: "checkmark.seal.fill")
            SnapshotDivider()
            SnapshotMetric(value: "\(store.recentReadings.count)", label: "短文", icon: "text.book.closed.fill")
        }
        .padding(.vertical, 14)
        .background(CiJingTheme.surface.opacity(0.82), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 19).stroke(CiJingTheme.line))
    }

    @ViewBuilder
    private func exploreDestination(_ destination: ExploreDestination) -> some View {
        switch destination {
        case .readingSetup:
            ReadingSetupView()
        case .practice:
            if let reading = store.recentReadings.first {
                PracticeSessionView(reading: reading)
            } else {
                ContentUnavailableView("还没有可练习的短文", systemImage: "text.book.closed", description: Text("先生成并读完一篇短文，再开始巩固练习。"))
            }
        case .progress:
            LearningProgressView()
        case .weakWords:
            WordLibraryView(initialFilter: .weak)
        case .shadowing:
            if let reading = store.recentReadings.first {
                ShadowingView(reading: reading)
            } else {
                ContentUnavailableView("还没有可跟读的短文", systemImage: "mic", description: Text("先生成一篇短文，再进入逐句跟读。"))
            }
        case .readingHistory:
            ReadingHubView()
        }
    }

    private var recentEmpty: some View {
        HStack(spacing: 14) {
            Image(systemName: "book.closed")
                .foregroundStyle(CiJingTheme.warm)
                .frame(width: 40, height: 40)
                .background(CiJingTheme.warmSoft, in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 3) {
                Text("还没有生成短文").font(CiJingTypography.rowTitle).foregroundStyle(CiJingTheme.secondary)
                Text("生成后的短文会长期保存在这里").font(CiJingTypography.supporting).foregroundStyle(CiJingTheme.secondary)
            }
            Spacer()
        }.cijingCard()
    }

    @ViewBuilder private var recentReading: some View {
        if let reading = store.recentReadings.first {
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
        } else {
            recentEmpty
        }
    }

    private var tipCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(store.plan.completedToday ? "🔥" : "💡")
            Text(store.plan.completedToday ? "词库互动火焰已点亮。继续学习，火焰会随着连续天数长大。" : "温馨提示：浏览器扩展收藏的单词会自动出现在词库，并优先安排进今日学习。")
                .font(.system(size: 13)).foregroundStyle(CiJingTheme.secondary).lineSpacing(4)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CiJingTheme.warmSoft, in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(CiJingTheme.warm.opacity(0.25)))
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
    /// 🔴 **必须用 destination 当 id，不能用 `UUID()`。**
    /// `exploreItems` 现在是计算属性（角标要读实时数据），每次求值都会重建数组；
    /// 如果 id 是 `UUID()`，每次求值 ForEach 都认为这是一批全新的行，
    /// 于是把 NavigationLink 连同它推出去的整条学习流程一起拆掉——正是本次修的
    /// 「中途弹回首页」那个 bug 的更严重版本。destination 天然唯一且稳定。
    var id: ExploreDestination { destination }
    let destination: ExploreDestination
    let title: String
    let subtitle: String
    /// 推导不出真实值时为 nil，此时不渲染角标。**不要在这里填占位字符串。**
    let badge: String?
    let icon: String
    let tint: Color
}

private enum ExploreDestination: Hashable {
    case readingSetup, practice, progress, weakWords, shadowing, readingHistory
}

private struct SnapshotMetric: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.caption.bold()).foregroundStyle(CiJingTheme.purple)
                Text(value).font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(CiJingTheme.ink)
            }
            Text(label).font(CiJingTypography.supporting).foregroundStyle(CiJingTheme.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SnapshotDivider: View {
    var body: some View { Rectangle().fill(CiJingTheme.line).frame(width: 1, height: 32) }
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
                    .background(item.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                Spacer()
                if let badge = item.badge {
                    Text(badge).font(.system(size: 11, weight: .heavy)).foregroundStyle(item.tint).padding(.horizontal, 6).padding(.vertical, 4).background(item.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 7))
                }
            }
            Spacer(minLength: 8)
            Text(item.title).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(CiJingTheme.ink)
            Text(item.subtitle).font(CiJingTypography.supporting).foregroundStyle(CiJingTheme.secondary).padding(.top, 3)
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
        .background(LinearGradient(colors: [item.tint.opacity(0.16), CiJingTheme.surfaceElevated], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(item.tint.opacity(0.18)))
    }
}
