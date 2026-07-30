import SwiftUI

struct RootView: View {
    @EnvironmentObject private var api: SupabaseAPI
    @EnvironmentObject private var store: AppStore
    private var isUIPreview: Bool { ProcessInfo.processInfo.arguments.contains("-ui-preview") }
    private var previewFlow: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-ui-flow"), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    var body: some View {
        Group {
            if isUIPreview, let previewFlow { previewDestination(previewFlow) }
            else if api.isSignedIn || isUIPreview { MainTabView().transition(.opacity) }
            else { AuthView().transition(.opacity) }
        }
        .foregroundStyle(CiJingTheme.ink)
        .preferredColorScheme(preferredColorScheme)
        .animation(.easeInOut(duration: 0.25), value: api.isSignedIn)
    }

    private var preferredColorScheme: ColorScheme? {
        guard api.isSignedIn else { return nil }
        return AppAppearance.selection(for: store.preferredAppearance).colorScheme
    }

    @ViewBuilder
    private func previewDestination(_ flow: String) -> some View {
        switch flow {
        case "reading-setup":
            NavigationStack { ReadingSetupView() }
        case "reading":
            if let reading = store.recentReadings.first { NavigationStack { ReadingSessionView(reading: reading) } }
        case "practice":
            if let reading = store.recentReadings.first { NavigationStack { PracticeSessionView(reading: reading) } }
        case "shadowing":
            if let reading = store.recentReadings.first { NavigationStack { ShadowingView(reading: reading) } }
        case "progress":
            NavigationStack { LearningProgressView() }
        default:
            MainTabView()
        }
    }
}
