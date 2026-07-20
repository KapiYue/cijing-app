import SwiftUI

private enum AppTab: Int, CaseIterable, Identifiable {
    case home, library, lookup, settings

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .home: "首页"
        case .library: "词库"
        case .lookup: "查词"
        case .settings: "设置"
        }
    }
    var icon: String {
        switch self {
        case .home: "house"
        case .library: "books.vertical"
        case .lookup: "magnifyingglass"
        case .settings: "gearshape"
        }
    }
    var launchValue: String {
        switch self {
        case .home: "home"
        case .library: "library"
        case .lookup: "lookup"
        case .settings: "settings"
        }
    }
    var selectedIcon: String {
        switch self {
        case .home: "house.fill"
        case .library: "books.vertical.fill"
        case .lookup: "magnifyingglass"
        case .settings: "gearshape.fill"
        }
    }
}

struct MainTabView: View {
    @State private var selection: AppTab = .home

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-ui-tab"), arguments.indices.contains(index + 1),
           let tab = AppTab.allCases.first(where: { $0.launchValue == arguments[index + 1] }) {
            _selection = State(initialValue: tab)
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selection) {
                NavigationStack { HomeView() }.tag(AppTab.home)
                NavigationStack { WordLibraryView() }.tag(AppTab.library)
                NavigationStack { LookupView() }.tag(AppTab.lookup)
                NavigationStack { SettingsView() }.tag(AppTab.settings)
            }
            .toolbar(.hidden, for: .tabBar)

            tabBar
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
        .tint(CiJingTheme.purple)
    }

    private var tabBar: some View {
        HStack(spacing: 5) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selection = tab }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: selection == tab ? tab.selectedIcon : tab.icon)
                            .font(.system(size: 20, weight: .medium))
                            .symbolEffect(.bounce, value: selection == tab)
                        Text(tab.title).font(.system(size: 10, weight: selection == tab ? .bold : .medium))
                    }
                    .foregroundStyle(selection == tab ? CiJingTheme.purpleDark : Color(red: 129 / 255, green: 123 / 255, blue: 134 / 255))
                    .frame(maxWidth: .infinity, minHeight: 57)
                    .background(selection == tab ? CiJingTheme.purpleSoft : .clear, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(6)
        .frame(height: 70)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .background(Color(red: 245 / 255, green: 239 / 255, blue: 252 / 255).opacity(0.88), in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 25, style: .continuous).stroke(CiJingTheme.line))
        .shadow(color: Color(red: 73 / 255, green: 47 / 255, blue: 99 / 255).opacity(0.2), radius: 19, y: 10)
    }
}
