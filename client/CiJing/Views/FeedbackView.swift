import SwiftUI
import UIKit

/// 随反馈一起提交的运行环境。用户不用自己写「我是 iPhone 13、17.4、1.0.1」——
/// 那三样正是定位问题必需、而用户最容易漏写或写错的。
enum FeedbackEnvironment {
    static var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    static var osVersion: String { "iOS \(UIDevice.current.systemVersion)" }

    /// 机型标识（如 `iPhone14,5`）。`UIDevice.model` 只会返回笼统的 "iPhone"，
    /// 区分不出具体型号，对排查屏幕尺寸和性能相关的问题没用。
    static var device: String {
        var info = utsname()
        uname(&info)
        let identifier = withUnsafePointer(to: &info.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: pointer.pointee)) {
                String(cString: $0)
            }
        }
        return identifier.isEmpty ? UIDevice.current.model : identifier
    }

    static var summary: String { "\(device) · \(osVersion) · 词鲸 \(appVersion)" }
}

/// 把 ISO8601 时间串显示成「8月18日 17:11」。服务端时间字段在模型里一律是 String
/// （见 Models.swift 里 Word 的处理），这里只做展示层转换。
private func feedbackDisplayDate(_ raw: String) -> String {
    let parsers: [ISO8601DateFormatter] = {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return [withFraction, ISO8601DateFormatter()]
    }()
    guard let date = parsers.compactMap({ $0.date(from: raw) }).first else { return raw }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "M月d日 HH:mm"
    return formatter.string(from: date)
}

// MARK: - 提交反馈

struct FeedbackComposeView: View {
    @EnvironmentObject private var api: SupabaseAPI
    @Environment(\.dismiss) private var dismiss

    @State private var category: FeedbackCategory = .bug
    @State private var content = ""
    @State private var contact = ""
    @State private var submitting = false
    @State private var submitted = false
    @State private var errorMessage: String?
    @FocusState private var contentFocused: Bool

    private let limit = 300

    private var trimmed: String { content.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSubmit: Bool { !trimmed.isEmpty && !submitting }

    var body: some View {
        ZStack {
            PaperBackground()
            if submitted { successView } else { formView }
        }
        .navigationTitle("意见反馈")
        .hidesAppTabBar()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { FeedbackHistoryView() } label: {
                    Label("反馈历史", systemImage: "clock.arrow.circlepath")
                }
            }
        }
        .alert("提交失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var formView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("这条反馈关于").font(CiJingTypography.rowTitle)
                    categoryPicker
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cijingCard(padding: 18)

                VStack(alignment: .leading, spacing: 8) {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $content)
                            .focused($contentFocused)
                            .font(CiJingTypography.body)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 168)
                            // 服务端有 300 字的 check 约束，这里就地截断，别让用户
                            // 写完一大段才被数据库拒掉。
                            .onChange(of: content) { _, newValue in
                                if newValue.count > limit { content = String(newValue.prefix(limit)) }
                            }
                        if content.isEmpty {
                            Text(category.placeholder)
                                .font(CiJingTypography.body)
                                .foregroundStyle(CiJingTheme.secondary.opacity(0.7))
                                .lineSpacing(4)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                    HStack {
                        Spacer()
                        Text("\(content.count)/\(limit)")
                            .font(CiJingTypography.supporting)
                            .foregroundStyle(content.count >= limit ? CiJingTheme.danger : CiJingTheme.secondary)
                    }
                }
                .cijingCard(padding: 14)

                VStack(alignment: .leading, spacing: 8) {
                    Text("回信方式（选填）").font(CiJingTypography.rowTitle)
                    TextField(api.currentEmail, text: $contact)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(CiJingTypography.body)
                        .padding(.vertical, 10).padding(.horizontal, 12)
                        .background(CiJingTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 12))
                    Text("留空就按你的登录邮箱回复。请勿填写密码、验证码或访问令牌。")
                        .font(CiJingTypography.supporting)
                        .foregroundStyle(CiJingTheme.secondary)
                        .lineSpacing(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cijingCard(padding: 18)

            }
            .padding(18)
            .padding(.bottom, 80)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button { Task { await submit() } } label: {
                Text(submitting ? "正在提交…" : "提交")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1 : 0.5)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }

    private var categoryPicker: some View {
        FlowLayout(spacing: 8) {
            ForEach(FeedbackCategory.allCases) { item in
                let selected = item == category
                Button {
                    category = item
                } label: {
                    Label(item.title, systemImage: item.icon)
                        .font(CiJingTypography.label)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(
                            selected ? CiJingTheme.purpleSoft : CiJingTheme.surfaceMuted,
                            in: Capsule()
                        )
                        .overlay(Capsule().stroke(selected ? CiJingTheme.purple.opacity(0.6) : .clear))
                        .foregroundStyle(selected ? CiJingTheme.purpleDark : CiJingTheme.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var successView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 54))
                .foregroundStyle(CiJingTheme.success)
            Text("已收到，谢谢你").font(.system(size: 22, weight: .bold, design: .rounded))
            Text("我们会逐条看。需要回复时会通过你留的方式联系你，进展也可以在「反馈历史」里查看。")
                .font(CiJingTypography.body)
                .foregroundStyle(CiJingTheme.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
            NavigationLink { FeedbackHistoryView() } label: {
                Text("查看反馈历史").frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            Button("返回") { dismiss() }
                .font(CiJingTypography.rowTitle)
                .foregroundStyle(CiJingTheme.secondary)
        }
        .padding(28)
        .frame(maxWidth: 340)
    }

    private func submit() async {
        guard canSubmit else { return }
        contentFocused = false
        submitting = true
        defer { submitting = false }
        let trimmedContact = contact.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = FeedbackDraft(
            category: category,
            content: trimmed,
            contact: trimmedContact.isEmpty ? nil : trimmedContact,
            appVersion: FeedbackEnvironment.appVersion,
            device: FeedbackEnvironment.device,
            osVersion: FeedbackEnvironment.osVersion
        )
        do {
            _ = try await api.submitFeedback(draft)
            submitted = true
        } catch {
            // 取消不是故障，静默即可——与 SupabaseAPI 里对取消的处理保持一致。
            guard !isCancellationError(error) else { return }
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - 反馈历史

struct FeedbackHistoryView: View {
    @EnvironmentObject private var api: SupabaseAPI
    @State private var items: [FeedbackItem] = []
    @State private var loading = true
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            PaperBackground()
            if loading {
                ProgressView()
            } else if let errorMessage {
                emptyState(icon: "exclamationmark.triangle", title: "没能加载", detail: errorMessage)
            } else if items.isEmpty {
                emptyState(icon: "tray", title: "还没有反馈", detail: "你提交过的反馈会出现在这里，包括我们的回复。")
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(items) { item in card(item) }
                    }
                    .padding(18)
                    .padding(.bottom, 40)
                }
                .refreshable { await load() }
            }
        }
        .navigationTitle("反馈历史")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func card(_ item: FeedbackItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(item.category.title, systemImage: item.category.icon)
                    .font(CiJingTypography.label)
                    .foregroundStyle(CiJingTheme.purpleDark)
                Spacer()
                Text(item.status.title)
                    .font(CiJingTypography.supporting)
                    .foregroundStyle(statusColor(item.status))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(statusColor(item.status).opacity(0.12), in: Capsule())
            }
            Text(item.content)
                .font(CiJingTypography.body)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(feedbackDisplayDate(item.createdAt))
                .font(CiJingTypography.supporting)
                .foregroundStyle(CiJingTheme.secondary)
            if let reply = item.reply, !reply.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("词鲸回复").font(CiJingTypography.label).foregroundStyle(CiJingTheme.success)
                    Text(reply).font(CiJingTypography.body).lineSpacing(4)
                    if let repliedAt = item.repliedAt {
                        Text(feedbackDisplayDate(repliedAt))
                            .font(CiJingTypography.supporting)
                            .foregroundStyle(CiJingTheme.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(CiJingTheme.successSoft, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .cijingCard(padding: 18)
    }

    private func statusColor(_ status: FeedbackStatus) -> Color {
        switch status {
        case .open: CiJingTheme.secondary
        case .inProgress: CiJingTheme.warm
        case .resolved: CiJingTheme.success
        }
    }

    private func emptyState(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 38)).foregroundStyle(CiJingTheme.secondary.opacity(0.6))
            Text(title).font(.system(size: 19, weight: .bold, design: .rounded))
            Text(detail)
                .font(CiJingTypography.body)
                .foregroundStyle(CiJingTheme.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .padding(32)
    }

    private func load() async {
        errorMessage = nil
        do {
            items = try await api.feedbackHistory()
        } catch {
            guard !isCancellationError(error) else { return }
            errorMessage = error.localizedDescription
        }
        loading = false
    }
}

// MARK: - 分类标签的自动换行布局

/// 五个分类标签在窄屏上放不下一行。`Layout` 比手写分组稳，宽度变化时自己重排。
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let rows = arrange(subviews: subviews, width: width)
        let height = rows.reduce(CGFloat.zero) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        var x: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !current.indices.isEmpty && x + size.width > width {
                rows.append(current)
                current = Row()
                x = 0
            }
            current.indices.append(index)
            current.height = max(current.height, size.height)
            x += size.width + spacing
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
