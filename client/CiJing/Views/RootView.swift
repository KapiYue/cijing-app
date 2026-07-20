import SwiftUI

struct RootView: View {
    @EnvironmentObject private var api: SupabaseAPI
    private var isUIPreview: Bool { ProcessInfo.processInfo.arguments.contains("-ui-preview") }
    var body: some View {
        Group {
            if api.isSignedIn || isUIPreview { MainTabView().transition(.opacity) }
            else { AuthView().transition(.opacity) }
        }
        .animation(.easeInOut(duration: 0.25), value: api.isSignedIn)
    }
}
