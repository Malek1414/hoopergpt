import SwiftUI

// App shell: onboarding once, then four tabs behind a custom menu bar.
// The camera stays alive under the other tabs so a recording survives a
// look at the score.

enum AppTab: Int, CaseIterable {
    case film, watch, live, account

    var title: String {
        switch self {
        case .film: return "Film"
        case .watch: return "Watch"
        case .live: return "Live"
        case .account: return "Account"
        }
    }
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
        .onChange(of: tab, initial: true) {
            AppDelegate.allow(tab == .watch ? .allButUpsideDown : .portrait)
        }
    }

    private var shell: some View {
        GeometryReader { geo in
            ZStack {
                Color.ink.ignoresSafeArea()
                if geo.size.width > geo.size.height {
                    // Sideways (Watch only): full screen, like any video app.
                    // Turning the phone upright brings the menu back.
                    content
                } else {
                    content
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            // Half the home-indicator inset: the labels sit just
                            // above it instead of floating a whole inset higher.
                            MenuBar(tab: $tab)
                                .padding(.bottom, -geo.safeAreaInsets.bottom * 0.5)
                        }
                }
            }
        }
    }

    private var content: some View {
        ZStack {
            // Kept mounted: tearing it down would stop a running recording.
            ContentView(pan: pan, showGuide: $showGuide)
                .opacity(tab == .film ? 1 : 0)
                .allowsHitTesting(tab == .film)
            switch tab {
            case .film: EmptyView()
            case .watch: WatchView()
            case .live: GoLiveView()
            case .account: AccountView(pan: pan) {
                showGuide = true
                tab = .film
            }
            }
        }
    }
}

// MARK: - menu bar

struct MenuBar: View {
    @Binding var tab: AppTab
    @Namespace private var marker

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { item in
                Button {
                    withAnimation(.spring(duration: 0.3)) { tab = item }
                } label: {
                    VStack(spacing: 6) {
                        Text(item.title)
                            .font(.wide(14, tab == item ? 800 : 600))
                            .foregroundColor(tab == item ? .white : .muted)
                        ZStack {
                            if tab == item {
                                Capsule().fill(Color.white)
                                    .matchedGeometryEffect(id: "marker", in: marker)
                            }
                        }
                        .frame(width: 18, height: 3)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .background(Color.ink.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Color.hairline).frame(height: 1) }
    }
}
