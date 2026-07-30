import SwiftUI

struct WordLibraryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var searchText = ""
    @State private var filter: WordStatus?

    init(initialFilter: WordStatus? = nil) { _filter = State(initialValue: initialFilter) }

    private let visibleStatuses: [WordStatus] = [.new, .learning, .review, .weak]

    private var filtered: [Word] {
        store.words.filter { word in
            (filter == nil || word.status == filter)
                && (searchText.isEmpty
                    || word.term.localizedCaseInsensitiveContains(searchText)
                    || word.displayMeaning.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    PageHeader(
                        title: "词库",
                        subtitle: "来自 Chrome 扩展的收藏",
                        trailing: AnyView(
                            Button { store.words.reverse() } label: {
                                Image(systemName: "arrow.up.arrow.down")
                                    .foregroundStyle(CiJingTheme.ink)
                                    .frame(width: 40, height: 40)
                                    .background(CiJingTheme.surface.opacity(0.82), in: RoundedRectangle(cornerRadius: 14))
                            }.buttonStyle(.plain)
                        )
                    )
                    .padding(.bottom, 17)

                    SearchField(text: $searchText, placeholder: "搜索单词或释义")
                    filters.padding(.top, 10)

                    if store.plan.completedToday { flameCard.padding(.top, 12) }

                    if filtered.isEmpty { emptyState.padding(.top, 42) }
                    else { wordList.padding(.top, 13) }

                    warmTip.padding(.top, 14)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 112)
            }
            .refreshable { await store.refreshLibrary() }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await store.refreshLibrary() }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                LibraryFilterChip(title: "全部", count: store.words.count, color: CiJingTheme.purple, soft: Color(red: 238 / 255, green: 232 / 255, blue: 251 / 255), selected: filter == nil) { filter = nil }
                ForEach(visibleStatuses) { status in
                    LibraryFilterChip(
                        title: status.title.replacingOccurrences(of: "词", with: ""),
                        count: store.words.filter { $0.status == status }.count,
                        color: filterColor(status),
                        soft: filterSoftColor(status),
                        selected: filter == status
                    ) { filter = status }
                }
            }
        }
    }

    private var flameCard: some View {
        HStack(spacing: 10) {
            Text("🔥")
                .frame(width: 37, height: 37)
                .background(Color(red: 1, green: 241 / 255, blue: 228 / 255), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 3) {
                Text("学习火焰已点亮").font(CiJingTypography.label).foregroundStyle(CiJingTheme.ink)
                Text("完成学习后，词库里的单词也更有生命力了").font(CiJingTypography.supporting).foregroundStyle(CiJingTheme.secondary)
            }
            Spacer()
        }
        .padding(13)
        .background(CiJingTheme.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 16))
    }

    private var wordList: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(filtered.enumerated()), id: \.element.id) { index, word in
                NavigationLink { WordDetailView(word: word) } label: { LibraryWordRow(word: word) }
                    .buttonStyle(.plain)
                if index < filtered.count - 1 { Divider().overlay(CiJingTheme.line).padding(.leading, 16) }
            }
        }
        .background(CiJingTheme.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(CiJingTheme.line.opacity(0.78)))
        .shadow(color: CiJingTheme.shadow.opacity(0.1), radius: 20, y: 9)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: searchText.isEmpty ? "text.book.closed" : "magnifyingglass")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(CiJingTheme.purple)
                .frame(width: 74, height: 74)
                .background(CiJingTheme.purpleSoft, in: RoundedRectangle(cornerRadius: 25))
            Text(searchText.isEmpty ? "这里还没有单词" : "没有匹配结果").font(.headline)
            Text(searchText.isEmpty ? "从 Chrome 扩展收藏，或在设置中导入演示词库。" : "换个关键词或筛选条件试试。")
                .font(CiJingTypography.supporting).foregroundStyle(CiJingTheme.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity)
    }

    private var warmTip: some View {
        HStack(alignment: .top, spacing: 9) {
            Text("💡")
            VStack(alignment: .leading, spacing: 3) {
                Text("温馨提示").font(CiJingTypography.label)
                Text("在 Chrome 扩展中收藏的单词会自动同步到这里；完成学习后，复习状态与掌握度也会同步更新。")
                    .font(.system(size: 13)).lineSpacing(3)
            }
        }
        .foregroundStyle(CiJingTheme.secondary)
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CiJingTheme.warmSoft, in: RoundedRectangle(cornerRadius: 15))
    }

    private func filterColor(_ status: WordStatus) -> Color {
        switch status {
        case .new: Color(red: 99 / 255, green: 132 / 255, blue: 205 / 255)
        case .learning: Color(red: 201 / 255, green: 133 / 255, blue: 63 / 255)
        case .review: Color(red: 183 / 255, green: 99 / 255, blue: 157 / 255)
        case .weak: CiJingTheme.danger
        default: CiJingTheme.purple
        }
    }

    private func filterSoftColor(_ status: WordStatus) -> Color {
        switch status {
        case .new: Color(red: 234 / 255, green: 241 / 255, blue: 252 / 255)
        case .learning: Color(red: 1, green: 241 / 255, blue: 223 / 255)
        case .review: Color(red: 247 / 255, green: 233 / 255, blue: 243 / 255)
        case .weak: Color(red: 252 / 255, green: 235 / 255, blue: 238 / 255)
        default: CiJingTheme.purpleSoft
        }
    }
}

private struct LibraryFilterChip: View {
    let title: String
    let count: Int
    let color: Color
    let soft: Color
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Circle().fill(selected ? .white : color).frame(width: 5, height: 5)
                Text("\(title) \(count)")
            }
            .font(CiJingTypography.label)
            .foregroundStyle(selected ? .white : color)
            .padding(.horizontal, 9).padding(.vertical, 8)
            .background(selected ? color : soft, in: RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
    }
}

private struct LibraryWordRow: View {
    let word: Word

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(word.term).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(CiJingTheme.ink)
                    if let phonetic = word.phonetic, !phonetic.isEmpty { Text("/\(phonetic)/").font(.system(size: 11, design: .monospaced)).foregroundStyle(CiJingTheme.secondary) }
                }
                Text("\(word.parts.first?.partOfSpeech ?? "") \(word.displayMeaning)")
                    .font(.system(size: 13)).foregroundStyle(CiJingTheme.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 4) {
                    StatusBadge(title: word.status == .weak ? "薄弱" : word.status.title, status: word.status)
                }
                Text("\(Int(word.strength * 100))% · \(dueLabel)")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(word.status == .weak ? CiJingTheme.danger : CiJingTheme.secondary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 15)
        .contentShape(Rectangle())
    }

    private var dueLabel: String {
        guard let date = ISO8601DateFormatter().date(from: word.dueAt) else { return "待安排" }
        if Calendar.current.isDateInToday(date) { return "今天" }
        if Calendar.current.isDateInTomorrow(date) { return "明天" }
        return date.formatted(.dateTime.month().day())
    }
}

private struct StatusBadge: View {
    let title: String
    let status: WordStatus
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(status == .weak ? CiJingTheme.danger : status == .new ? CiJingTheme.purple : Color(red: 188 / 255, green: 115 / 255, blue: 52 / 255))
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(status == .weak ? Color(red: 252 / 255, green: 236 / 255, blue: 239 / 255) : status == .new ? CiJingTheme.purpleSoft : Color(red: 1, green: 241 / 255, blue: 228 / 255), in: RoundedRectangle(cornerRadius: 8))
    }
}
