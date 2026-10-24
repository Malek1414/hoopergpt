import SwiftUI

// App shell: onboarding once, then three tabs. The camera tab is the old
// single-screen app, unchanged.

struct RootView: View {
    @AppStorage("onboarding.v2.done") private var onboarded = false
    // Screenshots: launch with `-debugTab 1` to open a tab directly.
    #if DEBUG
    @State private var tab = UserDefaults.standard.integer(forKey: "debugTab")
    #else
    @State private var tab = 0
    #endif

    var body: some View {
        if onboarded {
            TabView(selection: $tab) {
                ContentView()
                    .tabItem { Label("Film", systemImage: "video") }
                    .tag(0)
                WatchView()
                    .tabItem { Label("Watch", systemImage: "play.rectangle") }
                    .tag(1)
                GoLiveView()
                    .tabItem { Label("Go live", systemImage: "dot.radiowaves.left.and.right") }
                    .tag(2)
            }
            .tint(.pla)
            .preferredColorScheme(.dark)
        } else {
            OnboardingView { onboarded = true }
        }
    }
}
