import SwiftUI
import AVFoundation

private enum AppLinks {
    static let privacy = URL(string: "https://cijing.joy-coder.com/")!
    static let support = URL(string: "https://cijing.joy-coder.com/support")!
    static let contact = URL(string: "mailto:zdjoey@126.com")!
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var api: SupabaseAPI
    @AppStorage("dailyReminderEnabled") private var dailyReminder = true
    @AppStorage("autoPronunciationEnabled") private var autoPronunciation = true
    @AppStorage("hapticFeedbackEnabled") private var hapticFeedback = true
    @AppStorage(SpeechVoicePreference.storageKey) private var speechVoiceIdentifier = ""
    @State private var importing = false
    @State private var checkingUpdate = false
    @State private var cacheSize = AppCache.formattedSize
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

                    SettingsSectionTitle("隐私与安全")
                    SettingsGroup {
                        ForEach(Array(LegalDocument.allCases.enumerated()), id: \.element.id) { index, document in
                            if index > 0 { SettingsDivider() }
                            NavigationLink { LegalDocumentView(document: document) } label: {
                                SettingsActionRow(iconText: document.mark, title: document.rawValue, subtitle: document.subtitle)
                            }.buttonStyle(.plain)
                        }
                    }

                    SettingsSectionTitle("关于")
                    SettingsGroup {
                        NavigationLink { AboutCiJingView() } label: {
                            SettingsActionRow(icon: "info.circle", title: "关于词鲸", subtitle: "了解产品理念与版本信息")
                        }.buttonStyle(.plain)
                        SettingsDivider()
                        Button { Task { await checkForUpdates() } } label: {
                            SettingsActionRow(icon: "arrow.up.circle", title: checkingUpdate ? "正在检查…" : "检查更新", subtitle: "当前版本 \(AppMetadata.version)")
                        }.buttonStyle(.plain).disabled(checkingUpdate)
                        SettingsDivider()
                        Button { clearCache() } label: {
                            SettingsActionRow(icon: "trash", title: "清理缓存（\(cacheSize)）", subtitle: "释放图片、接口响应和临时文件占用")
                        }.buttonStyle(.plain)
                    }

                    Button(role: .destructive) {
                        Task {
                            await api.signOut()
                            store.clearSessionData()
                        }
                    } label: {
                        Text("退出登录").font(CiJingTypography.rowTitle).frame(maxWidth: .infinity).padding(.vertical, 16)
                    }
                    .background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 17))
                    .padding(.top, 20)

                    Text("词鲸背单词 \(AppMetadata.version) · © 2026")
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
            return "自动优先增强音质（美式英语）"
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

    private func checkForUpdates() async {
        checkingUpdate = true
        defer { checkingUpdate = false }
        do {
            guard var components = URLComponents(string: "https://itunes.apple.com/lookup") else { throw URLError(.badURL) }
            components.queryItems = [
                URLQueryItem(name: "bundleId", value: AppMetadata.bundleIdentifier),
                URLQueryItem(name: "country", value: "cn")
            ]
            guard let url = components.url else { throw URLError(.badURL) }
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse).map({ 200..<300 ~= $0.statusCode }) == true else { throw URLError(.badServerResponse) }
            let result = try JSONDecoder().decode(AppStoreLookupResponse.self, from: data)
            guard let release = result.results.first else {
                message = "当前版本 \(AppMetadata.version)。应用尚未在中国区 App Store 检索到。"
                return
            }
            if release.version.compare(AppMetadata.version, options: .numeric) == .orderedDescending {
                message = "发现新版本 \(release.version)，可前往 App Store 更新。"
            } else {
                message = "当前版本 \(AppMetadata.version) 已是最新版本。"
            }
        } catch {
            message = "暂时无法检查更新，请确认网络连接后重试。"
        }
    }

    private func clearCache() {
        do {
            try AppCache.clear()
            cacheSize = AppCache.formattedSize
            message = "缓存已清理。"
        } catch {
            cacheSize = AppCache.formattedSize
            message = "部分缓存未能清理：\(error.localizedDescription)"
        }
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
                        Text("发音由苹果系统在本机合成，不会把朗读内容发送给大模型。自动模式会优先使用设备已安装的增强或高级美式英语声音。")
                            .font(.system(size: 13)).foregroundStyle(CiJingTheme.secondary).lineSpacing(4)
                    }

                    VStack(spacing: 0) {
                        voiceRow(identifier: "", title: "自动选择最佳声音", subtitle: "优先增强 / 高级美式英语声音")
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
        let quality: String
        switch voice.quality {
        case .premium: quality = "高级"
        case .enhanced: quality = "增强"
        default: quality = "标准"
        }
        return "\(locale) · \(gender) · \(quality)"
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

                    VStack(alignment: .leading, spacing: 4) {
                        Text("账户安全")
                            .font(.caption)
                            .foregroundStyle(CiJingTheme.secondary)
                            .padding(.horizontal, 4)
                        NavigationLink { DeleteAccountView() } label: {
                            SettingsActionRow(icon: "person.crop.circle.badge.minus", title: "删除账号", subtitle: "永久删除账号及全部云端学习数据")
                        }
                        .buttonStyle(.plain)
                        .background(Color(red: 249 / 255, green: 245 / 255, blue: 253 / 255).opacity(0.93), in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(CiJingTheme.line.opacity(0.82)))
                    }
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

private struct DeleteAccountView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var api: SupabaseAPI
    @State private var emailConfirmation = ""
    @State private var deleting = false
    @State private var showingFinalConfirmation = false
    @State private var message: String?

    private var matchesEmail: Bool {
        emailConfirmation.trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedCaseInsensitiveCompare(api.currentEmail) == .orderedSame
    }

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("删除后无法恢复", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                            .foregroundStyle(.red)
                        Text("你的账号、个人资料、词库、复习记录、AI 短文、阅读进度和其他云端学习数据都会被永久删除。")
                            .font(CiJingTypography.body)
                            .foregroundStyle(CiJingTheme.secondary)
                            .lineSpacing(5)
                    }
                    .cijingCard(padding: 20)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("请输入当前登录邮箱以确认")
                            .font(.subheadline.bold())
                        Text(api.currentEmail)
                            .font(.caption)
                            .foregroundStyle(CiJingTheme.secondary)
                        TextField("当前登录邮箱", text: $emailConfirmation)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                            .padding(13)
                            .background(CiJingTheme.purpleSoft.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .cijingCard(padding: 20)

                    Button(role: .destructive) {
                        showingFinalConfirmation = true
                    } label: {
                        HStack {
                            if deleting { ProgressView().tint(.white) }
                            Text(deleting ? "正在删除…" : "永久删除账号")
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(matchesEmail && !deleting ? Color.red : Color.gray.opacity(0.55), in: RoundedRectangle(cornerRadius: 15))
                    }
                    .buttonStyle(.plain)
                    .disabled(!matchesEmail || deleting)

                    Link(destination: AppLinks.support) {
                        Label("删除前需要帮助？访问支持页面", systemImage: "questionmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(CiJingTheme.purple)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(18)
            }
        }
        .navigationTitle("删除账号")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("确定永久删除账号？", isPresented: $showingFinalConfirmation, titleVisibility: .visible) {
            Button("永久删除", role: .destructive) { deleteAccount() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作无法撤销，所有账号及学习数据都将被删除。")
        }
        .alert("删除账号", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("知道了") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private func deleteAccount() {
        deleting = true
        Task {
            do {
                try await api.deleteAccount()
                store.clearSessionData()
            } catch {
                message = "删除失败：\(error.localizedDescription)"
            }
            deleting = false
        }
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
    case legalAndPrivacy = "法律信息及隐私管理"
    case collection = "个人信息收集清单"
    case localSharing = "地方信息数据共享"
    case summary = "隐私政策摘要"
    var id: String { rawValue }
    var mark: String { switch self { case .legalAndPrivacy: "法"; case .collection: "集"; case .localSharing: "享"; case .summary: "摘" } }
    var subtitle: String {
        switch self {
        case .legalAndPrivacy: "管理数据权利并查看法律信息"
        case .collection: "查看信息类型、场景、用途与范围"
        case .localSharing: "了解数据共享对象、目的与边界"
        case .summary: "快速了解我们如何保护你的信息"
        }
    }

    var sections: [(String, String)] {
        switch self {
        case .legalAndPrivacy:
            return [
                ("适用范围", "本说明适用于词鲸背单词 iOS App 与配套浏览器扩展。我们遵循合法、正当、必要和诚信原则处理个人信息。"),
                ("你的数据权利", "你可以访问、更正、删除学习数据，撤回非必要授权，或申请注销账号。设备的麦克风与语音识别权限可随时在系统设置中关闭。"),
                ("数据安全与保存", "账号、词库、复习进度和阅读历史保存在受访问控制保护的云端；不同用户的数据通过行级权限隔离。仅在实现功能所需期限内保存信息。"),
                ("未成年人保护", "未满十四周岁的用户应在监护人同意和指导下使用。若发现未经同意处理了儿童个人信息，我们会及时删除。")
            ]
        case .collection:
            return [
                ("账号信息", "收集邮箱地址，用于注册、登录、找回账号和保障账号安全。"),
                ("学习与内容信息", "收集收藏单词、查询上下文、笔记、复习结果、学习偏好、AI 短文及阅读进度，用于提供词库、个性化阅读和间隔复习。"),
                ("麦克风与语音识别", "仅在你主动使用跟读功能时请求系统权限，用于生成本次朗读的文字和准确度反馈；不会在后台持续录音。"),
                ("设备与诊断信息", "网络请求可能包含 IP 地址、设备系统版本和必要日志，用于保障服务安全与排查故障。第一版不接入广告追踪。")
            ]
        case .localSharing:
            return [
                ("云服务", "学习数据存储和账号认证由 Supabase 提供，仅为完成登录、同步和数据保存而处理必要信息。"),
                ("AI 内容生成", "生成词义解释或个性化短文时，会向 OpenRouter 传输必要的目标单词及相关上下文；不会传输你的密码。"),
                ("系统能力", "朗读使用苹果设备的语音合成能力；跟读识别由系统语音识别能力提供，具体处理方式同时受设备系统设置约束。"),
                ("地方或公共机构", "除非法律法规要求、司法或行政机关依法提出，或为保护用户与公众的重大合法权益，我们不会向地方机构共享个人信息。")
            ]
        case .summary:
            return [
                ("我们收集什么", "仅收集账号登录、词库同步、AI 学习、复习记录和你主动开启的跟读功能所必需的信息。"),
                ("我们为什么收集", "用于跨端同步词库、生成个性化短文、安排复习计划、提供发音与跟读反馈，以及保障服务安全。"),
                ("你可以做什么", "你可以关闭麦克风或语音识别权限，清理本机缓存，并联系我们访问、更正、导出或删除个人信息。"),
                ("重要承诺", "我们不出售个人信息，不使用第三方广告追踪 SDK，不会把密码或无关个人资料发送给 AI 服务。")
            ]
        }
    }
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
                        ForEach(Array(document.sections.enumerated()), id: \.offset) { index, section in
                            Divider()
                            LegalSection(title: "\(index + 1). \(section.0)", copy: section.1)
                        }
                        Divider()
                        VStack(alignment: .leading, spacing: 11) {
                            Text("联系我们").font(.subheadline.bold())
                            Text("如需行使个人信息权利、申请删除数据或反馈隐私问题，可通过以下渠道联系我们。")
                                .font(.system(size: 12)).foregroundStyle(Color(red: 110 / 255, green: 101 / 255, blue: 115 / 255)).lineSpacing(6)
                            Link("隐私政策网页", destination: AppLinks.privacy)
                            Link("支持与帮助", destination: AppLinks.support)
                            Link("zdjoey@126.com", destination: AppLinks.contact)
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(CiJingTheme.purple)
                    }.cijingCard(padding: 22)
                }.padding(18)
            }
        }.navigationTitle(document.rawValue).navigationBarTitleDisplayMode(.inline)
    }
}

private struct LegalSection: View {
    let title: String
    let copy: String
    var body: some View { VStack(alignment: .leading, spacing: 8) { Text(title).font(.subheadline.bold()); Text(copy).font(.system(size: 12)).foregroundStyle(Color(red: 110 / 255, green: 101 / 255, blue: 115 / 255)).lineSpacing(6) } }
}

private struct AboutCiJingView: View {
    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 12) {
                        Image(systemName: "books.vertical.fill")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 82, height: 82)
                            .background(LinearGradient(colors: [CiJingTheme.purple, CiJingTheme.purpleDark], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 27))
                        Text("词鲸背单词").font(.title2.bold())
                        Text("版本 \(AppMetadata.version)（\(AppMetadata.build)）")
                            .font(.caption).foregroundStyle(CiJingTheme.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .cijingCard(padding: 24)

                    VStack(alignment: .leading, spacing: 14) {
                        Text("在真实语境里，把遇见的单词变成真正会用的语言。")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                        Text("词鲸把跨端查词、个人词库、AI 分级短文与间隔复习连成一个学习闭环。每一次收藏都会成为下一次阅读和练习的素材。")
                            .font(CiJingTypography.body).foregroundStyle(CiJingTheme.secondary).lineSpacing(5)
                        Link(destination: URL(string: "https://github.com/KapiYue/cijing-app")!) {
                            Label("访问 GitHub 项目", systemImage: "arrow.up.right.square")
                                .font(.subheadline.bold()).foregroundStyle(CiJingTheme.purple)
                        }
                    }.cijingCard(padding: 22)

                    VStack(spacing: 0) {
                        Link(destination: AppLinks.privacy) {
                            SettingsActionRow(icon: "hand.raised", title: "隐私政策", subtitle: "cijing.joy-coder.com")
                        }
                        SettingsDivider()
                        Link(destination: AppLinks.support) {
                            SettingsActionRow(icon: "questionmark.circle", title: "支持与帮助", subtitle: "常见问题与账号删除说明")
                        }
                        SettingsDivider()
                        Link(destination: AppLinks.contact) {
                            SettingsActionRow(icon: "envelope", title: "联系我们", subtitle: "zdjoey@126.com")
                        }
                    }
                    .buttonStyle(.plain)
                    .background(Color(red: 249 / 255, green: 245 / 255, blue: 253 / 255).opacity(0.93), in: RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(CiJingTheme.line.opacity(0.82)))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                }.padding(18)
            }
        }
        .navigationTitle("关于词鲸")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private enum AppMetadata {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1" }
    static var bundleIdentifier: String { Bundle.main.bundleIdentifier ?? "com.joy-coder.cijingapp" }
}

private struct AppStoreLookupResponse: Decodable {
    let results: [Release]
    struct Release: Decodable { let version: String }
}

private enum AppCache {
    private static var cacheDirectory: URL? { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first }

    static var byteCount: Int64 {
        let urlCacheBytes = Int64(URLCache.shared.currentDiskUsage + URLCache.shared.currentMemoryUsage)
        guard let cacheDirectory,
              let enumerator = FileManager.default.enumerator(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return urlCacheBytes
        }
        let fileBytes = enumerator.compactMap { item -> Int? in
            guard let url = item as? URL else { return nil }
            return try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        }.reduce(0, +)
        return max(urlCacheBytes, Int64(fileBytes))
    }

    static var formattedSize: String { String(format: "%.2fM", Double(byteCount) / 1_048_576) }

    static func clear() throws {
        URLCache.shared.removeAllCachedResponses()
        guard let cacheDirectory else { return }
        for item in try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: item)
        }
    }
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
