import SwiftUI

@main
struct CiJingApp: App {
    @StateObject private var api: SupabaseAPI
    @StateObject private var store: AppStore

    init() {
        let api = SupabaseAPI()
        let store = AppStore(api: api)
        if ProcessInfo.processInfo.arguments.contains("-ui-preview") { store.loadPreviewData() }
        _api = StateObject(wrappedValue: api)
        _store = StateObject(wrappedValue: store)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(api)
                .environmentObject(store)
                .tint(CiJingTheme.purple)
        }
    }
}
