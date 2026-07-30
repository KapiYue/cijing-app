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
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var store: AppStore
    @State private var selection: AppTab = .home
    @State private var tabBarHidden = false

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-ui-tab"), arguments.indices.contains(index + 1),
           let tab = AppTab.allCases.first(where: { $0.launchValue == arguments[index + 1] }) {
            _selection = State(initialValue: tab)
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            tabContent

            if !tabBarHidden {
                tabBar
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .environment(\.appTabBarHidden, $tabBarHidden)
        .tint(CiJingTheme.purple)
        .animation(.easeInOut(duration: 0.2), value: tabBarHidden)
        .onChange(of: selection) { _, _ in Task { await refreshSelectedTab() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshSelectedTab() } }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selection {
        case .home: NavigationStack { HomeView() }
        case .library: NavigationStack { WordLibraryView() }
        case .lookup: NavigationStack { LookupView() }
        case .settings: NavigationStack { SettingsView() }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 5) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selection = tab }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: selection == tab ? tab.selectedIcon : tab.icon)
                            .font(.system(size: 21, weight: .semibold))
                            .symbolEffect(.bounce, value: selection == tab)
                        Text(tab.title).font(.system(size: 12, weight: selection == tab ? .bold : .semibold))
                    }
                    .foregroundStyle(selection == tab ? CiJingTheme.purpleDark : CiJingTheme.secondary)
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
        .background(CiJingTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 25, style: .continuous).stroke(CiJingTheme.line))
        .shadow(color: CiJingTheme.purpleDark.opacity(0.14), radius: 12, y: 5)
    }

    private func refreshSelectedTab() async {
        switch selection {
        case .library: await store.refreshLibrary()
        case .home: await store.refreshAll()
        case .lookup, .settings: break
        }
    }
}
