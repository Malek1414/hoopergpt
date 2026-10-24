import SwiftUI

// A game: the two teams picked before filming, and what the Mac counted by
// the time you stopped. Kept on the phone (Documents/games.json) so the
// Account tab can show every game afterwards.

struct GameRecord: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let home: Team          // snapshot, so later roster edits keep old games right
    let away: Team
    var duration: TimeInterval = 0
    var final: GameState?   // the Mac's last state.json, nil if it was not reachable
}

enum GameStore {
    private static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("games.json")
    }

    static func load() -> [GameRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([GameRecord].self, from: data)) ?? []
    }

    static func add(_ game: GameRecord) {
        let all = [game] + load()
        if let data = try? JSONEncoder().encode(all) { try? data.write(to: url) }
    }
}

// MARK: - game setup, shown before the first frame is filmed

struct GameSetupView: View {
    var actionTitle = "Start Filming"
    let start: () -> Void
    let cancel: () -> Void
    @State private var home = TeamStore.home
    @State private var away = TeamStore.away
    @State private var path: [Side] = []

    enum Side: Hashable { case home, away }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section("Home") { teamRow(home, side: .home) }
                Section {
                    Text("vs")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .accessibilityHidden(true)
                }
                .listSectionSpacing(0)
                Section("Away") { teamRow(away, side: .away) }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("New Game")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                }
            }
            .navigationDestination(for: Side.self) { side in
                TeamPicker(selected: side == .home ? home.id : away.id,
                           title: side == .home ? "Home" : "Away") { team in
                    if side == .home { home = team } else { away = team }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                PrimaryButton(title: actionTitle) {
                    TeamStore.homeID = home.id
                    TeamStore.awayID = away.id
                    start()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(Color(.systemGroupedBackground))
            }
            #if DEBUG
            // Screenshots: `-debugPicker YES` opens the home team picker.
            .onAppear { if UserDefaults.standard.bool(forKey: "debugPicker"), path.isEmpty { path = [.home] } }
            #endif
        }
        .presentationDetents([.large])
    }

    private func teamRow(_ team: Team, side: Side) -> some View {
        NavigationLink(value: side) {
            HStack(spacing: 16) {
                TeamBadge(team: team, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(team.name)
                        .font(.title2.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(team.players.isEmpty ? "No players" : "\(team.players.count) players")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
        }
    }
}

/// Choose one of your teams, edit one with the info button or a swipe, or make a new one.
private struct TeamPicker: View {
    let selected: UUID
    let title: String
    let pick: (Team) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var teams = TeamStore.all()
    @State private var editing: Team?

    var body: some View {
        List {
            if !teams.isEmpty {
                Section {
                    ForEach(teams) { team in
                        HStack(spacing: 14) {
                            Button {
                                pick(team)
                                dismiss()
                            } label: {
                                HStack(spacing: 14) {
                                    TeamBadge(team: team, size: 36)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(team.name).foregroundStyle(.primary)
                                        Text("\(team.players.count) players")
                                            .font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if team.id == selected {
                                        Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.tint)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Button { editing = team } label: {
                                Image(systemName: "info.circle").font(.title3)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Edit \(team.name)")
                        }
                        .swipeActions {
                            Button("Edit") { editing = team }.tint(.gray)
                        }
                    }
                }
            }
            Section {
                Button {
                    editing = Team(name: "", color: TeamStore.palette[teams.count % TeamStore.palette.count])
                } label: {
                    Label("New Team", systemImage: "plus")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { team in
            let isNew = !teams.contains { $0.id == team.id }
            TeamDetailView(team: team) { saved in
                teams = TeamStore.all()
                editing = nil
                // A team made here is the one you wanted: take it.
                if isNew, let saved {
                    pick(saved)
                    dismiss()
                } else if let saved, saved.id == selected {
                    pick(saved)
                }
            }
        }
    }
}

// MARK: - one finished game, pushed from the Account tab

struct GameDetailView: View {
    let game: GameRecord

    private var scores: (Int, Int)? {
        guard let t = game.final?.teams, t.count == 2 else { return nil }
        return (t[0].score, t[1].score)
    }

    var body: some View {
        List {
            Section {
                header
                    .listRowInsets(EdgeInsets(top: 20, leading: 16, bottom: 20, trailing: 16))
            }
            if let state = game.final, state.teams.count == 2 {
                Section("Box Score") {
                    StatsBlock(state: state, home: game.home, away: game.away)
                        .padding(.vertical, 8)
                }
            } else {
                Section {
                    ContentUnavailableView("No Stats", systemImage: "chart.bar",
                                           description: Text("The Mac was not reachable when this game ended."))
                }
            }
            Section {
                LabeledContent("Date", value: game.date.formatted(date: .long, time: .shortened))
                LabeledContent("Filmed", value: Duration.seconds(game.duration)
                    .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated)))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("\(game.home.name) vs \(game.away.name)")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Apple Sports style: badges and names on the outside, big scores inside.
    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            side(game.home)
            Spacer(minLength: 4)
            score(scores?.0, winning: scores.map { $0.0 > $0.1 } ?? false)
            Text("Final")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44)
            score(scores?.1, winning: scores.map { $0.1 > $0.0 } ?? false)
            Spacer(minLength: 4)
            side(game.away)
        }
    }

    private func side(_ team: Team) -> some View {
        VStack(spacing: 8) {
            TeamBadge(team: team, size: 48)
            Text(team.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 68)
    }

    private func score(_ value: Int?, winning: Bool) -> some View {
        // Scores never give way: on an SE the names shrink first.
        Text(value.map(String.init) ?? "-")
            .font(.system(size: 40, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(winning || scores == nil ? .primary : .secondary)
            .lineLimit(1)
            .fixedSize()
            .layoutPriority(1)
    }
}
