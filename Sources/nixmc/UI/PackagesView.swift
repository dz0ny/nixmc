import SwiftUI

/// Cart-style editor for the config's Homebrew apps (casks) and CLI tools
/// (brews). Installed entries can be dropped into the cart for removal;
/// typing a name that isn't installed offers to add it. Confirming builds a
/// single change request naming the exact lists, handed back to the chat
/// input (the user reviews, then sends — the agent does the actual edit).
struct PackagesView: View {
    let casks: [String]
    let brews: [String]
    /// Called with the constructed prompt when the user confirms the cart.
    let onInsert: (String) -> Void
    /// The shared chat composer, so a freehand request can be sent without
    /// leaving the packages pane.
    let composer: ComposerBar

    /// Which config list an entry belongs to.
    private enum Kind { case app, cli }

    @State private var removeCasks: Set<String> = []
    @State private var removeBrews: Set<String> = []
    @State private var addApps: Set<String> = []
    @State private var addBrews: Set<String> = []
    @State private var search = ""

    @State private var popular: [PopularPackage] = []
    @State private var popularError: String?
    @State private var loadingPopular = false

    private var query: String { search.trimmingCharacters(in: .whitespaces) }
    private var shownCasks: [String] { filtered(casks) }
    private var shownBrews: [String] { filtered(brews) }

    private var cartCount: Int {
        removeCasks.count + removeBrews.count + addApps.count + addBrews.count
    }

    /// True when the query names something not already installed — the cue to
    /// offer adding it rather than only filtering.
    private var canAdd: Bool {
        guard !query.isEmpty else { return false }
        let all = casks + brews + Array(addApps) + Array(addBrews)
        return !all.contains { $0.caseInsensitiveCompare(query) == .orderedSame }
    }

    private func filtered(_ names: [String]) -> [String] {
        guard !query.isEmpty else { return names }
        return names.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    /// Popular packages not already installed or already sitting in the add
    /// cart, filtered by the current search text.
    private var shownPopular: [PopularPackage] {
        let installed = Set(casks + brews).union(addApps).union(addBrews)
        let candidates = popular.filter { !installed.contains($0.name) }
        guard !query.isEmpty else { return candidates }
        return candidates.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private func loadPopular() {
        loadingPopular = true
        popularError = nil
        Task {
            do {
                let items = try await HomebrewPopular.fetch()
                await MainActor.run {
                    popular = items
                    loadingPopular = false
                }
            } catch {
                await MainActor.run {
                    popularError = error.localizedDescription
                    loadingPopular = false
                }
            }
        }
    }

    /// e.g. `Add "gimp" to the casks list and remove "slack", "zoom" from the
    /// casks list in .nixmc/homebrew/data.json`
    private var prompt: String {
        var parts: [String] = []
        if !addApps.isEmpty { parts.append("add " + quoted(addApps) + " to the casks list") }
        if !addBrews.isEmpty { parts.append("add " + quoted(addBrews) + " to the brews list") }
        if !removeCasks.isEmpty { parts.append("remove " + quoted(removeCasks) + " from the casks list") }
        if !removeBrews.isEmpty { parts.append("remove " + quoted(removeBrews) + " from the brews list") }
        guard !parts.isEmpty else { return "" }
        let body = parts.joined(separator: ", ").capitalizingFirstLetter()
        return body + " in .nixmc/homebrew/data.json"
    }

    private func quoted(_ names: Set<String>) -> String {
        names.sorted().map { "\"\($0)\"" }.joined(separator: ", ")
    }

    private func clearCart() {
        removeCasks = []; removeBrews = []; addApps = []; addBrews = []
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if canAdd { addSuggestion }
                    popularSection
                    group("Apps", icon: "macwindow", names: shownCasks, remove: $removeCasks)
                    group("CLI Tools", icon: "terminal", names: shownBrews, remove: $removeBrews)
                    if shownCasks.isEmpty && shownBrews.isEmpty && shownPopular.isEmpty && !canAdd {
                        Text("Nothing matches “\(query)”.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 30)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
            Divider().opacity(0.5)
            composer
        }
        .tint(Theme.accent)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { if popular.isEmpty { loadPopular() } }
    }

    /// Trending casks/formulae from Homebrew's public install-count
    /// analytics — a quick way to add something well-known without knowing
    /// its exact package name.
    @ViewBuilder
    private var popularSection: some View {
        if loadingPopular && popular.isEmpty {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Loading popular packages…").font(.caption).foregroundStyle(.secondary)
            }
        } else if let popularError, popular.isEmpty {
            HStack(spacing: 6) {
                Text("Couldn't load popular packages: \(popularError)")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Retry", action: loadPopular).font(.caption).buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
            }
        } else if !shownPopular.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Label("Popular", systemImage: "flame")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        loadPopular()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .rotationEffect(.degrees(loadingPopular ? 360 : 0))
                            .animation(loadingPopular ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default,
                                       value: loadingPopular)
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .disabled(loadingPopular)
                    .help("Refresh popular packages")
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 8)],
                          alignment: .leading, spacing: 8) {
                    ForEach(shownPopular) { item in
                        popularRow(item)
                    }
                }
            }
        }
    }

    /// A suggested-but-not-installed entry from the popular list. Clicking
    /// adds it straight into the add cart, mirroring `addSuggestion`.
    private func popularRow(_ item: PopularPackage) -> some View {
        Button {
            switch item.kind {
            case .app: addApps.insert(item.name)
            case .cli: addBrews.insert(item.name)
            }
        } label: {
            HStack(spacing: 8) {
                Text(item.name).font(.callout).foregroundStyle(Color.primary).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "plus.circle")
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Theme.accent.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Theme.accent.opacity(0.15)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Add \(item.name)")
    }

    private var header: some View {
        HStack(spacing: 12) {
            BrandMark(size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text("Packages").font(.headline)
                Text("Search to add, click to remove — build a change request.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search or add…", text: $search)
                    .textFieldStyle(.plain)
                    .frame(width: 170)
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08)))
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    /// Offered when the query doesn't match anything installed.
    private var addSuggestion: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus.circle.fill")
                .font(.title2).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("“\(query)” isn't installed").font(.callout.weight(.medium))
                Text("Add it to your config?").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Add app") { addApps.insert(query); search = "" }
                .buttonStyle(.brandCompact)
            Button("Add CLI tool") { addBrews.insert(query); search = "" }
                .buttonStyle(.bordered)
        }
        .padding(12)
        .background(Theme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius)
            .strokeBorder(Theme.accent.opacity(0.18), lineWidth: 1))
    }

    @ViewBuilder
    private func group(_ title: String, icon: String, names: [String],
                       remove: Binding<Set<String>>) -> some View {
        if !names.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("\(title) (\(names.count))", systemImage: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 8)],
                          alignment: .leading, spacing: 8) {
                    ForEach(names, id: \.self) { name in
                        packageRow(name, remove: remove)
                    }
                }
            }
        }
    }

    /// A single installed entry. Clicking toggles it into/out of the remove
    /// cart; carted entries dim and strike through with an undo affordance.
    private func packageRow(_ name: String, remove: Binding<Set<String>>) -> some View {
        let carted = remove.wrappedValue.contains(name)
        return Button {
            if carted { remove.wrappedValue.remove(name) }
            else { remove.wrappedValue.insert(name) }
        } label: {
            HStack(spacing: 8) {
                Text(name)
                    .font(.callout)
                    .strikethrough(carted, color: .secondary)
                    .foregroundStyle(carted ? Color.secondary : Color.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: carted ? "arrow.uturn.backward" : "trash")
                    .font(.caption)
                    .foregroundStyle(carted ? Color.secondary : Color.red.opacity(0.75))
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(
                (carted ? Color.red.opacity(0.06) : Color.primary.opacity(0.03)),
                in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(carted ? Color.red.opacity(0.25) : Color.primary.opacity(0.07)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(carted ? "Undo removal of \(name)" : "Remove \(name)")
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if cartCount == 0 {
                Text("Cart is empty — search to add or click a package to remove.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            } else {
                Text(prompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Button("Clear", action: clearCart)
                    .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                Button("Apply \(cartCount)") { onInsert(prompt) }
                    .buttonStyle(.brandCompact)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

private extension String {
    func capitalizingFirstLetter() -> String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
