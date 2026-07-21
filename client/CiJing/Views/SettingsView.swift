import SwiftUI
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var api: SupabaseAPI
    @AppStorage("dailyReminderEnabled") private var dailyReminder = true
    @AppStorage("autoPronunciationEnabled") private var autoPronunciation = true
    @AppStorage("hapticFeedbackEnabled") private var hapticFeedback = true
    @AppStorage(SpeechVoicePreference.storageKey) private var speechVoiceIdentifier = ""
    @State private var importing = false
    @State private var message: String?

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PageHeader(title: "设置", subtitle: "让学习更适合你的节奏")
                        .padding(.bottom, 18)

                    NavigationLink { ProfileSettingsView() } label: { profileCard }
                        .buttonStyle(.plain)

                    SettingsSectionTitle("学习偏好")
                    SettingsGroup {
                        SettingsToggleRow(icon: "bell", title: "每日学习提醒", subtitle: "每天 20:30", isOn: $dailyReminder)
                        SettingsDivider()
                        SettingsToggleRow(icon: "speaker.wave.2", title: "自动播放发音", subtitle: "打开词条时自动朗读", isOn: $autoPronunciation)
                        SettingsDivider()
                        NavigationLink { SpeechVoiceSettingsView() } label: {
                            SettingsActionRow(icon: "waveform", title: "英文发音声音", subtitle: selectedVoiceName)
                        }.buttonStyle(.plain)
                        SettingsDivider()
                        SettingsToggleRow(icon: "sparkles", title: "触感反馈", subtitle: "答题与完成时轻触反馈", isOn: $hapticFeedback)
                    }

                    SettingsSectionTitle("内容与数据")
                    SettingsGroup {
                        NavigationLink { ReadingPreferenceView() } label: {
                            SettingsActionRow(iconText: "文", title: "短文偏好", subtitle: preferenceSummary)
                        }.buttonStyle(.plain)
                        SettingsDivider()
                        SettingsActionRow(iconText: "云", title: "浏览器同步", subtitle: "刚刚同步 · \(store.words.count) 个词", status: "已连接")
                        SettingsDivider()
                        Button { Task { await importDemo() } } label: {
                            SettingsActionRow(icon: "arrow.down.circle", title: importing ? "正在导入…" : "离线与演示内容", subtitle: "缓存词库并导入体验单词")
                        }.buttonStyle(.plain).disabled(importing)
                    }

                    SettingsSectionTitle("关于与条款")
                    SettingsGroup {
                        SettingsActionRow(icon: "arrow.up.circle", title: "版本更新", subtitle: "当前版本 1.0.0", status: "已是最新")
                        ForEach(Array(LegalDocument.allCases.enumerated()), id: \.element.id) { index, document in
                            SettingsDivider()
                            NavigationLink { LegalDocumentView(document: document) } label: {
                                SettingsActionRow(iconText: document.mark, title: document.rawValue, subtitle: document.subtitle)
                            }.buttonStyle(.plain)
                        }
                        SettingsDivider()
                        Button { message = "帮助与反馈中心即将开放。" } label: {
                            SettingsActionRow(iconText: "?", title: "帮助与反馈", subtitle: "常见问题与意见反馈")
                        }.buttonStyle(.plain)
                    }

                    Button(role: .destructive) { Task { await api.signOut() } } label: {
                        Text("退出登录").font(CiJingTypography.rowTitle).frame(maxWidth: .infinity).padding(.vertical, 16)
                    }
                    .background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 17))
                    .padding(.top, 20)

                    Text("词鲸背单词 1.0.0 · © 2026")
                        .font(CiJingTypography.supporting).foregroundStyle(CiJingTheme.secondary.opacity(0.72))
                        .frame(maxWidth: .infinity).padding(.vertical, 22)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 100)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { if store.profile == nil { await store.refreshAll() } }
        .alert("提示", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("知道了") { message = nil }
        } message: { Text(message ?? "") }
    }

    private var profileCard: some View {
        HStack(spacing: 13) {
            Text(profileInitial)
                .font(.title3.bold()).foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(LinearGradient(colors: [Color(red: 247 / 255, green: 207 / 255, blue: 169 / 255), CiJingTheme.warm], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 4) {
                Text(profileName).font(.system(size: 17, weight: .bold)).foregroundStyle(CiJingTheme.ink).lineLimit(1)
                Text("编辑头像、昵称与账户安全").font(.system(size: 13)).foregroundStyle(Color(red: 119 / 255, green: 107 / 255, blue: 128 / 255))
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(CiJingTheme.purple)
        }
        .padding(17)
        .background(LinearGradient(colors: [Color(red: 239 / 255, green: 226 / 255, blue: 251 / 255), Color(red: 227 / 255, green: 209 / 255, blue: 242 / 255)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color(red: 220 / 255, green: 203 / 255, blue: 236 / 255)))
    }

    private var profileName: String {
        let value = store.profile?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value! : api.currentEmail
    }
    private var profileInitial: String { String(profileName.prefix(1)).uppercased() }
    private var preferenceSummary: String {
        guard let profile = store.profile else { return "故事 · 适中 · 中篇" }
        return "\(ReadingOptions.label(for: profile.preferredStyle)) · \(ReadingOptions.label(for: profile.preferredDifficulty)) · 中篇"
    }
    private var selectedVoiceName: String {
        guard !speechVoiceIdentifier.isEmpty,
              let voice = AVSpeechSynthesisVoice(identifier: speechVoiceIdentifier) else {
            return "跟随系统（美式英语）"
        }
        return "\(voice.name) · \(voice.language)"
    }

    private func importDemo() async {
        importing = true
        await store.importDemoWords()
        importing = false
        message = store.errorMessage ?? "演示词库已导入。"
        store.errorMessage = nil
    }
}

private struct SpeechVoiceSettingsView: View {
    @AppStorage(SpeechVoicePreference.storageKey) private var selectedIdentifier = ""
    @StateObject private var speech = SpeechService()

    private var voices: [AVSpeechSynthesisVoice] { SpeechVoicePreference.englishVoices }

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("选择英文声音").font(.system(size: 24, weight: .bold, design: .rounded))
                        Text("发音由苹果系统在本机合成，不会把朗读内容发送给大模型。可用声音取决于当前设备已安装的系统语音。")
                            .font(.system(size: 13)).foregroundStyle(CiJingTheme.secondary).lineSpacing(4)
                    }

                    VStack(spacing: 0) {
                        voiceRow(identifier: "", title: "跟随系统", subtitle: "默认美式英语声音")
                        ForEach(voices, id: \.identifier) { voice in
                            SettingsDivider()
                            voiceRow(identifier: voice.identifier, title: voice.name, subtitle: voiceSubtitle(voice))
                        }
                    }
                    .background(Color(red: 249 / 255, green: 245 / 255, blue: 253 / 255).opacity(0.93), in: RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(CiJingTheme.line.opacity(0.82)))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                }
                .padding(18)
            }
        }
        .navigationTitle("英文发音")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { speech.stop() }
    }

    private func voiceRow(identifier: String, title: String, subtitle: String) -> some View {
        Button {
            selectedIdentifier = identifier
            speech.speak("Resilient learners grow stronger every day.")
        } label: {
            HStack(spacing: 12) {
                SettingsIcon(systemName: "speaker.wave.2.fill")
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(CiJingTypography.rowTitle).foregroundStyle(CiJingTheme.ink)
                    Text(subtitle).font(CiJingTypography.supporting).foregroundStyle(CiJingTheme.secondary)
                }
                Spacer()
                Image(systemName: selectedIdentifier == identifier ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20)).foregroundStyle(selectedIdentifier == identifier ? CiJingTheme.purple : CiJingTheme.line)
            }
            .padding(.horizontal, 15).frame(minHeight: 61).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedIdentifier == identifier ? .isSelected : [])
    }

    private func voiceSubtitle(_ voice: AVSpeechSynthesisVoice) -> String {
        let locale = Locale.current.localizedString(forIdentifier: voice.language) ?? voice.language
        let gender: String
        switch voice.gender {
        case .male: gender = "男声"
        case .female: gender = "女声"
        default: gender = "系统声音"
        }
        return "\(locale) · \(gender)"
    }
}

private struct SettingsSectionTitle: View {
    let value: String
    init(_ value: String) { self.value = value }
    var body: some View { Text(value).font(CiJingTypography.label).foregroundStyle(CiJingTheme.secondary).padding(.horizontal, 4).padding(.top, 22).padding(.bottom, 9) }
}

private struct SettingsGroup<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(spacing: 0) { content }
            .background(Color(red: 249 / 255, green: 245 / 255, blue: 253 / 255).opacity(0.93), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(CiJingTheme.line.opacity(0.82)))
            .clipShape(RoundedRectangle(cornerRadius: 22))
    }
}

private struct SettingsDivider: View {
    var body: some View { Divider().overlay(CiJingTheme.line).padding(.leading, 58) }
}

private struct SettingsToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(systemName: icon)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(CiJingTypography.rowTitle).foregroundStyle(CiJingTheme.ink)
                Text(subtitle).font(CiJingTypography.supporting).foregroundStyle(CiJingTheme.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().tint(CiJingTheme.purple)
        }.padding(.horizontal, 15).frame(minHeight: 68)
    }
}

private struct SettingsActionRow: View {
    var icon: String? = nil
    var iconText: String? = nil
    let title: String
    let subtitle: String
    var status: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let icon { SettingsIcon(systemName: icon) }
            else { SettingsIcon(text: iconText ?? "·") }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(CiJingTypography.rowTitle).foregroundStyle(CiJingTheme.ink)
                Text(subtitle).font(CiJingTypography.supporting).foregroundStyle(CiJingTheme.secondary).lineLimit(2)
            }
            Spacer()
            if let status { Text(status).font(CiJingTypography.label).foregroundStyle(CiJingTheme.success) }
            else { Image(systemName: "chevron.right").font(.caption).foregroundStyle(CiJingTheme.secondary.opacity(0.65)) }
        }.padding(.horizontal, 15).frame(minHeight: 68).contentShape(Rectangle())
    }
}

private struct SettingsIcon: View {
    var systemName: String? = nil
    var text: String? = nil
    var body: some View {
        Group {
            if let systemName { Image(systemName: systemName).font(.system(size: 16, weight: .medium)) }
            else { Text(text ?? "").font(.system(size: 13, weight: .bold)) }
        }
        .foregroundStyle(CiJingTheme.purple)
        .frame(width: 36, height: 36)
        .background(CiJingTheme.purpleSoft, in: RoundedRectangle(cornerRadius: 11))
    }
}

private struct ProfileSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var api: SupabaseAPI
    @State private var draft: Profile?
    @State private var message: String?
    @State private var saving = false

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 10) {
                        Text(initial).font(.system(size: 31, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 82, height: 82)
                            .background(LinearGradient(colors: [Color(red: 247 / 255, green: 207 / 255, blue: 169 / 255), CiJingTheme.warm], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 28))
                        Text(draft?.displayName?.isEmpty == false ? draft!.displayName! : "学习者").font(.title2.bold())
                        Text("编辑昵称与学习目标，让词鲸背单词更适合你的学习节奏。 ").font(.caption).foregroundStyle(CiJingTheme.secondary)
                    }.frame(maxWidth: .infinity).padding(24).background(LinearGradient(colors: [Color(red: 243 / 255, green: 232 / 255, blue: 1), Color(red: 223 / 255, green: 202 / 255, blue: 239 / 255)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22))

                    if let draft {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("基本资料").font(.caption).foregroundStyle(CiJingTheme.secondary)
                            TextField("昵称", text: Binding(get: { draft.displayName ?? "" }, set: { self.draft?.displayName = $0 }))
                                .padding(13).background(CiJingTheme.purpleSoft.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                            Stepper("每日新词  \(draft.dailyNewGoal)", value: Binding(get: { draft.dailyNewGoal }, set: { self.draft?.dailyNewGoal = $0 }), in: 1...30)
                            Stepper("每日复习  \(draft.dailyReviewGoal)", value: Binding(get: { draft.dailyReviewGoal }, set: { self.draft?.dailyReviewGoal = $0 }), in: 5...80, step: 5)
                        }.cijingCard()
                        Button { save() } label: { Text(saving ? "正在保存…" : "保存修改") }.buttonStyle(PrimaryButtonStyle()).disabled(saving)
                    } else {
                        ProgressView("正在加载资料…").padding(40)
                    }
                    Text("登录邮箱：\(api.currentEmail)").font(.system(size: 13)).foregroundStyle(CiJingTheme.secondary)
                }.padding(18)
            }
        }
        .navigationTitle("个人资料").navigationBarTitleDisplayMode(.inline)
        .task { if store.profile == nil { await store.refreshAll() }; draft = store.profile }
        .alert("个人资料", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("知道了") {} } message: { Text(message ?? "") }
    }

    private var initial: String { String((draft?.displayName?.isEmpty == false ? draft!.displayName! : api.currentEmail).prefix(1)).uppercased() }
    private func save() {
        guard let draft else { return }
        saving = true
        Task { defer { saving = false }; do { try await store.saveProfile(draft); message = "修改已保存。" } catch { message = error.localizedDescription } }
    }
}

private struct ReadingPreferenceView: View {
    @EnvironmentObject private var store: AppStore
    @State private var message: String?
    var body: some View {
        ZStack {
            PaperBackground()
            Form {
                if store.profile != nil {
                    Section("短文形式") { Picker("形式", selection: binding(\.preferredStyle, fallback: "story")) { ForEach(ReadingOptions.styles, id: \.0) { Text($0.1).tag($0.0) } } }
                    Section("默认难度") { Picker("难度", selection: binding(\.preferredDifficulty, fallback: "intermediate")) { ForEach(ReadingOptions.difficulties, id: \.0) { Text($0.1).tag($0.0) } } }
                    Button("保存偏好") { save() }.buttonStyle(PrimaryButtonStyle())
                } else { ProgressView("正在加载…") }
            }.scrollContentBackground(.hidden)
        }.navigationTitle("短文偏好").navigationBarTitleDisplayMode(.inline)
            .alert("短文偏好", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("知道了") {} } message: { Text(message ?? "") }
    }
    private func binding(_ path: WritableKeyPath<Profile, String>, fallback: String) -> Binding<String> { Binding(get: { store.profile?[keyPath: path] ?? fallback }, set: { store.profile?[keyPath: path] = $0 }) }
    private func save() { guard let profile = store.profile else { return }; Task { do { try await store.saveProfile(profile); message = "偏好已保存。" } catch { message = error.localizedDescription } } }
}

private enum LegalDocument: String, CaseIterable, Identifiable {
    case privacy = "隐私政策"
    case terms = "用户协议"
    case collection = "个人信息收集清单"
    case sharing = "第三方信息共享清单"
    var id: String { rawValue }
    var mark: String { switch self { case .privacy: "隐"; case .terms: "约"; case .collection: "单"; case .sharing: "享" } }
    var subtitle: String { switch self { case .privacy: "了解我们如何保护你的数据"; case .terms: "使用词鲸背单词前请仔细阅读"; case .collection: "查看信息类型、用途与范围"; case .sharing: "查看 SDK 与共享说明" } }
}

private struct LegalDocumentView: View {
    let document: LegalDocument
    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("更新日期：2026 年 7 月 20 日\n生效日期：2026 年 7 月 20 日").font(.caption2).foregroundStyle(CiJingTheme.secondary).lineSpacing(4)
                    VStack(alignment: .leading, spacing: 18) {
                        Text(document.rawValue).font(.system(size: 23, weight: .bold, design: .rounded))
                        Divider()
                        LegalSection(title: "1. 我们如何处理信息", copy: firstCopy)
                        Divider()
                        LegalSection(title: "2. 你的权利与选择", copy: secondCopy)
                        Divider()
                        LegalSection(title: "联系我们", copy: "如有疑问，可通过“设置－帮助与反馈”联系我们。")
                    }.cijingCard(padding: 22)
                }.padding(18)
            }
        }.navigationTitle(document.rawValue).navigationBarTitleDisplayMode(.inline)
    }
    private var firstCopy: String { document == .privacy ? "我们遵循最小必要原则处理收藏单词、学习进度与偏好设置。" : document.subtitle + "。" }
    private var secondCopy: String { "你可以管理、导出或申请删除自己的学习数据。AI 生成内容仅用于语言学习。" }
}

private struct LegalSection: View {
    let title: String
    let copy: String
    var body: some View { VStack(alignment: .leading, spacing: 8) { Text(title).font(.subheadline.bold()); Text(copy).font(.system(size: 12)).foregroundStyle(Color(red: 110 / 255, green: 101 / 255, blue: 115 / 255)).lineSpacing(6) } }
}

#if DEBUG
private struct DeveloperSettingsView: View {
    @State private var status: String?
    var body: some View {
        Form {
            Section("根目录 .env 生成配置") {
                LabeledContent("Supabase URL", value: AppConfig.supabaseURL.absoluteString)
                LabeledContent("Publishable key", value: maskedKey)
                Button("测试当前连接") { Task { await testConnection() } }
                if let status { Text(status).font(.caption) }
            }
            Section { Text("修改根目录 .env 后运行 make config，再重新构建 App。").font(.caption).foregroundStyle(.secondary) }
        }
        .navigationTitle("Supabase 连接").navigationBarTitleDisplayMode(.inline)
    }
    private var maskedKey: String {
        let key = AppConfig.supabasePublishableKey
        return key.count > 10 ? "\(key.prefix(6))••••\(key.suffix(4))" : "已配置"
    }
    private func testConnection() async {
        var request = URLRequest(url: AppConfig.supabaseURL.appending(path: "rest/v1/"))
        request.setValue(AppConfig.supabasePublishableKey, forHTTPHeaderField: "apikey")
        do { let (_, response) = try await URLSession.shared.data(for: request); status = (response as? HTTPURLResponse).map { (200..<500).contains($0.statusCode) } == true ? "连接正常" : "连接失败" }
        catch { status = error.localizedDescription }
    }
}
#endif
