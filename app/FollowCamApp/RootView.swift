import SwiftUI

// App shell: onboarding once, then the system tab bar with four tabs.
// TabView keeps every visited tab mounted, so the camera (and a running
// recording) survives a look at the score.

enum AppTab: Int, CaseIterable {
    case film, watch, live, account
}

struct RootView: View {
    @AppStorage("onboarding.v2.done") private var onboarded = false
    // Screenshots: launch with `-debugTab 1` to open a tab directly.
    #if DEBUG
    @State private var tab = AppTab(rawValue: UserDefaults.standard.integer(forKey: "debugTab")) ?? .film
    #else
    @State private var tab = AppTab.film
    #endif
    @StateObject private var pan = PanController()
    @State private var showGuide = false

    var body: some View {
        Group {
            if onboarded {
                shell
            } else {
                OnboardingView {
                    onboarded = true
                    showGuide = true
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(.pla)
        .onChange(of: tab, initial: true) {
            AppDelegate.allow(tab == .watch ? .allButUpsideDown : .portrait)
        }
    }

    private var shell: some View {
        GeometryReader { geo in
            // Sideways happens on Watch only: the video gets the whole screen,
            // turning the phone upright brings the tab bar back.
            let sideways = geo.size.width > geo.size.height
            TabView(selection: $tab) {
                ContentView(pan: pan, showGuide: $showGuide)
                    .tabItem { Label("Film", systemImage: "video.fill") }
                    .tag(AppTab.film)
                WatchView()
                    .toolbar(sideways ? .hidden : .visible, for: .tabBar)
                    .tabItem { Label("Watch", systemImage: "play.rectangle.fill") }
                    .tag(AppTab.watch)
                GoLiveView()
                    .tabItem { Label("Live", systemImage: "dot.radiowaves.left.and.right") }
                    .tag(AppTab.live)
                AccountView(pan: pan) {
                    tab = .film
                    showGuide = true
                }
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
                .tag(AppTab.account)
            }
            .tint(.pla)
        }
    }
}
