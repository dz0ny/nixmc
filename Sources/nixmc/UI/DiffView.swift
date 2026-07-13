import SwiftUI

// MARK: - Model

/// One file's slice of a unified diff (plus a synthetic "Overview" entry that
/// holds the commit header + stat block).
struct DiffFile: Identifiable {
    let id: String
    let path: String     // full repo-relative path ("" for overview)
    let name: String     // last component / "Overview"
    let body: String
    let added: Int
    let removed: Int
}

enum DiffParser {
    static let overviewID = "__overview__"

    static func parse(_ diff: String) -> [DiffFile] {
        let lines = diff.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var files: [DiffFile] = []
        var header: [String] = []
        var current: [String] = []
        var currentPath: String?

        func flush() {
            guard let path = currentPath else { return }
            files.append(makeFile(path: path, body: current))
            current = []
        }

        for line in lines {
            if line.hasPrefix("diff --git ") {
                if currentPath == nil { header = current; current = [] } else { flush() }
                currentPath = parsePath(from: line)   // rough; refined in makeFile
            }
            current.append(line)
        }
        if currentPath == nil { header = current } else { flush() }

        var result: [DiffFile] = []
        let headerText = header.joined(separator: "\n").trimmingCharacters(in: .newlines)
        if !headerText.isEmpty {
            result.append(DiffFile(id: overviewID, path: "", name: "Overview",
                                   body: headerText, added: 0, removed: 0))
        }
        result.append(contentsOf: files)
        return result
    }

    private static func parsePath(from line: String) -> String {
        // Rough fallback used only if a block has no +++/--- lines.
        if let range = line.range(of: " b/") { return String(line[range.upperBound...]) }
        return line.replacingOccurrences(of: "diff --git ", with: "")
    }

    /// Strip git's side prefix (`a/`, `b/`, `1/`, `2/`, `w/`, `i/`, …) — the
    /// first path segment — leaving the real repo-relative path.
    private static func stripPrefix(_ s: String) -> String {
        if s == "/dev/null" { return s }
        if let slash = s.firstIndex(of: "/") { return String(s[s.index(after: slash)...]) }
        return s
    }

    private static func makeFile(path fallback: String, body: [String]) -> DiffFile {
        var added = 0, removed = 0
        var newPath: String?
        var oldPath: String?
        for l in body {
            if l.hasPrefix("+++ ") {
                newPath = stripPrefix(String(l.dropFirst(4)).split(separator: "\t").first.map(String.init) ?? "")
            } else if l.hasPrefix("--- ") {
                oldPath = stripPrefix(String(l.dropFirst(4)).split(separator: "\t").first.map(String.init) ?? "")
            } else if l.hasPrefix("+") && !l.hasPrefix("+++") { added += 1 }
            else if l.hasPrefix("-") && !l.hasPrefix("---") { removed += 1 }
        }
        // Prefer the new path; fall back to old (deletions) then the git line.
        let resolved = [newPath, oldPath].compactMap { $0 }.first { $0 != "/dev/null" }
            ?? stripPrefix(fallback)
        return DiffFile(id: resolved, path: resolved,
                        name: resolved.split(separator: "/").last.map(String.init) ?? resolved,
                        body: body.joined(separator: "\n"), added: added, removed: removed)
    }
}

/// A node in the changed-files tree.
final class DiffNode: Identifiable {
    let id: String
    let name: String
    var file: DiffFile?
    var children: [DiffNode]?
    init(id: String, name: String, file: DiffFile? = nil, children: [DiffNode]? = nil) {
        self.id = id; self.name = name; self.file = file; self.children = children
    }
}

enum DiffTree {
    /// Build a directory tree from file paths (overview excluded).
    static func build(_ files: [DiffFile]) -> [DiffNode] {
        let root = DiffNode(id: "", name: "")
        root.children = []
        for f in files where f.id != DiffParser.overviewID {
            var node = root
            let parts = f.path.split(separator: "/").map(String.init)
            for (i, part) in parts.enumerated() {
                let isLeaf = i == parts.count - 1
                let childID = (node.id.isEmpty ? "" : node.id + "/") + part
                if let existing = node.children?.first(where: { $0.id == childID }) {
                    node = existing
                } else {
                    let child = DiffNode(id: childID, name: part,
                                         file: isLeaf ? f : nil,
                                         children: isLeaf ? nil : [])
                    node.children?.append(child)
                    node = child
                }
            }
        }
        return collapse(root.children ?? [])
    }

    /// Collapse single-child directory chains (e.g. `.nixmc/homebrew`) for brevity.
    private static func collapse(_ nodes: [DiffNode]) -> [DiffNode] {
        nodes.map { node -> DiffNode in
            guard var kids = node.children else { return node }
            kids = collapse(kids)
            node.children = kids
            if node.file == nil, kids.count == 1, kids[0].children != nil {
                let only = kids[0]
                return DiffNode(id: only.id, name: node.name + "/" + only.name,
                                file: only.file, children: only.children)
            }
            return node
        }
    }
}

// MARK: - View

struct DiffView: View {
    let title: String
    let diff: String
    /// AI-generated plain-English summary of the diff (nil until produced).
    var summary: String? = nil
    /// True while the selected agent is still generating the summary.
    var summarizing: Bool = false
    /// Re-run the summary, bypassing the cache.
    var onRegenerate: () -> Void = {}
    let onClose: () -> Void

    private var files: [DiffFile] { DiffParser.parse(diff) }
    private var totalAdded: Int { files.reduce(0) { $0 + $1.added } }
    private var totalRemoved: Int { files.reduce(0) { $0 + $1.removed } }
    private var changedCount: Int { files.filter { $0.id != DiffParser.overviewID }.count }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            DiffBrowser(diff: diff, summary: summary, summarizing: summarizing,
                        onRegenerate: onRegenerate)
        }
        .tint(Theme.accent)
        .frame(minWidth: 940, minHeight: 580)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass").foregroundStyle(Theme.accent)
            Text(title).font(.headline).lineLimit(1)
            StatBadges(added: totalAdded, removed: totalRemoved)
            Spacer()
            Text("\(changedCount) file\(changedCount == 1 ? "" : "s")")
                .font(.caption).foregroundStyle(.secondary)
            Button("Done", action: onClose).keyboardShortcut(.defaultAction)
        }
        .padding(14)
    }
}

/// The file-tree + diff-pane split, shared by the diff sheets (via `DiffView`)
/// and the update-proposal detail pane (which embeds it in a narrower column).
struct DiffBrowser: View {
    let diff: String
    var summary: String? = nil
    var summarizing: Bool = false
    var onRegenerate: () -> Void = {}
    var treeMinWidth: CGFloat = 230
    var paneMinWidth: CGFloat = 480

    @State private var selectedID: String?
    @State private var wrap = true

    private var files: [DiffFile] { DiffParser.parse(diff) }
    private var tree: [DiffNode] { DiffTree.build(files) }
    private var selected: DiffFile? {
        files.first { $0.id == selectedID } ?? files.first
    }
    private var totalAdded: Int { files.reduce(0) { $0 + $1.added } }
    private var totalRemoved: Int { files.reduce(0) { $0 + $1.removed } }

    var body: some View {
        HSplitView {
            fileTree.frame(minWidth: treeMinWidth, idealWidth: treeMinWidth + 40, maxWidth: 380)
            diffPane.frame(minWidth: paneMinWidth)
        }
        .onAppear { if selectedID == nil { selectedID = files.first?.id } }
    }

    private var fileTree: some View {
        List(selection: $selectedID) {
            ForEach(files.filter { $0.id == DiffParser.overviewID }) { f in
                Label("Overview", systemImage: "text.alignleft").tag(f.id)
            }
            Section("Changed files") {
                OutlineGroup(tree, children: \.children) { node in
                    if let f = node.file {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text").foregroundStyle(Theme.accent.opacity(0.8))
                            Text(node.name).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 6)
                            StatBadges(added: f.added, removed: f.removed, compact: true)
                        }
                        .font(.callout)
                        .tag(f.id)
                    } else {
                        Label(node.name, systemImage: "folder").font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder private var diffPane: some View {
        if selected?.id == DiffParser.overviewID {
            OverviewPane(files: changedFiles, added: totalAdded, removed: totalRemoved,
                         summary: summary, summarizing: summarizing,
                         onRegenerate: onRegenerate) { id in
                selectedID = id
            }
        } else {
            fileDiffPane
        }
    }

    private var changedFiles: [DiffFile] {
        files.filter { $0.id != DiffParser.overviewID }
    }

    private var fileDiffPane: some View {
        VStack(spacing: 0) {
            if let f = selected {
                HStack(spacing: 8) {
                    Text(f.path).font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Toggle(isOn: $wrap) { Text("Wrap").font(.caption) }
                        .toggleStyle(.switch).controlSize(.mini)
                }
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(.regularMaterial)
                Divider()
            }
            ScrollView(wrap ? .vertical : [.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(diffLines.enumerated()), id: \.offset) { _, line in
                        DiffLineRow(line: line, wrap: wrap)
                    }
                }
                .padding(.vertical, 6)
                .frame(maxWidth: wrap ? .infinity : nil, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private var diffLines: [Substring] {
        let raw = (selected?.body ?? "").split(separator: "\n", omittingEmptySubsequences: false)
        // Overview keeps everything; per-file views drop git's noisy header.
        guard selected?.id != DiffParser.overviewID else { return raw }
        return raw.filter { !Self.isNoise($0) }
    }

    /// Git file-header lines we hide from the per-file diff (path is in the bar above).
    private static func isNoise(_ line: Substring) -> Bool {
        line.hasPrefix("diff --git ") || line.hasPrefix("index ")
            || line.hasPrefix("new file mode ") || line.hasPrefix("deleted file mode ")
            || line.hasPrefix("old mode ") || line.hasPrefix("new mode ")
            || line.hasPrefix("similarity index ") || line.hasPrefix("dissimilarity index ")
            || line.hasPrefix("rename from ") || line.hasPrefix("rename to ")
            || line.hasPrefix("copy from ") || line.hasPrefix("copy to ")
            || line.hasPrefix("--- ") || line.hasPrefix("+++ ")
    }
}

// MARK: - Row & badges

/// A single monospaced diff line with a colored gutter bar. Wraps when enabled.
private struct DiffLineRow: View {
    let line: Substring
    let wrap: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(gutter).frame(width: 3)
            Text(line.isEmpty ? " " : String(line))
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(color)
                .textSelection(.enabled)
                .fixedSize(horizontal: !wrap, vertical: true)
                .frame(maxWidth: wrap ? .infinity : nil, alignment: .leading)
                .padding(.leading, 10).padding(.trailing, 12).padding(.vertical, 1)
        }
        .frame(maxWidth: wrap ? .infinity : nil, alignment: .leading)
        .background(background)
    }

    private var isAdd: Bool { line.hasPrefix("+") && !line.hasPrefix("+++") }
    private var isDel: Bool { line.hasPrefix("-") && !line.hasPrefix("---") }
    private var isHunk: Bool { line.hasPrefix("@@") }
    private var isMeta: Bool {
        line.hasPrefix("diff ") || line.hasPrefix("index ") || line.hasPrefix("commit ")
            || line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("@@")
    }

    private var color: Color {
        if line.hasPrefix("+++") || line.hasPrefix("---") { return .secondary }
        if isHunk { return .cyan }
        if isAdd { return Color(red: 0.2, green: 0.7, blue: 0.35) }
        if isDel { return Color(red: 0.85, green: 0.3, blue: 0.3) }
        if line.hasPrefix("diff ") || line.hasPrefix("commit ") || line.hasPrefix("index ") { return .orange }
        return .primary
    }
    private var gutter: Color {
        if isAdd { return .green.opacity(0.8) }
        if isDel { return .red.opacity(0.8) }
        if isHunk { return .cyan.opacity(0.6) }
        return .clear
    }
    private var background: Color {
        if isAdd { return Color.green.opacity(0.10) }
        if isDel { return Color.red.opacity(0.10) }
        if isHunk { return Color.cyan.opacity(0.06) }
        if isMeta { return Color.primary.opacity(0.03) }
        return .clear
    }
}

// MARK: - Overview

/// A parsed change summary: one clickable row per file with a proportional
/// add/remove bar. Replaces dumping git's raw `--stat` text.
struct OverviewPane: View {
    let files: [DiffFile]
    let added: Int
    let removed: Int
    var summary: String? = nil
    var summarizing: Bool = false
    var onRegenerate: () -> Void = {}
    let onSelect: (String) -> Void

    private var maxTotal: Int { max(1, files.map { $0.added + $0.removed }.max() ?? 1) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                heading
                summaryCard
                VStack(spacing: 2) {
                    ForEach(files) { f in row(f) }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var heading: some View {
        HStack(spacing: 10) {
            Text("\(files.count) file\(files.count == 1 ? "" : "s") changed")
                .font(.system(.title3, design: .rounded).weight(.semibold))
            StatBadges(added: added, removed: removed)
            Spacer()
        }
    }

    /// AI-written description of what changed, generated by the selected agent and cached.
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "sparkles").foregroundStyle(Theme.accent)
                Text("What changed").font(.callout.weight(.semibold))
                Spacer()
                if summarizing {
                    ProgressView().controlSize(.small)
                } else if summary != nil {
                    Button(action: onRegenerate) {
                        Image(systemName: "arrow.clockwise").font(.caption)
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("Regenerate summary")
                }
            }
            if let summary, !summary.isEmpty {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } else if summarizing {
                Text("Generating a description with the selected agent…")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text("No summary yet.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius)
            .strokeBorder(Theme.accent.opacity(0.18), lineWidth: 1))
    }

    private func row(_ f: DiffFile) -> some View {
        Button { onSelect(f.id) } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc.text").foregroundStyle(Theme.accent.opacity(0.8))
                    .frame(width: 16)
                pathText(f.path)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 12)
                Text("\(f.added + f.removed)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
                ChangeBar(added: f.added, removed: f.removed, scale: maxTotal)
                    .frame(width: 120)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Dim the directory, emphasize the filename.
    private func pathText(_ path: String) -> some View {
        let parts = path.split(separator: "/")
        let name = parts.last.map(String.init) ?? path
        let dir = parts.dropLast().joined(separator: "/")
        return (Text(dir.isEmpty ? "" : dir + "/").foregroundStyle(.secondary)
                + Text(name).foregroundStyle(.primary))
            .font(.system(.callout, design: .monospaced))
    }
}

/// A git-style histogram bar: green additions then red deletions, scaled to
/// the largest file in the set.
struct ChangeBar: View {
    let added: Int
    let removed: Int
    let scale: Int

    var body: some View {
        GeometryReader { geo in
            let total = added + removed
            let frac = CGFloat(total) / CGFloat(max(1, scale))
            let width = max(total > 0 ? 3 : 0, geo.size.width * frac)
            let addW = total > 0 ? width * CGFloat(added) / CGFloat(total) : 0
            HStack(spacing: 1) {
                Rectangle().fill(Color.green).frame(width: addW)
                Rectangle().fill(Color.red).frame(width: width - addW)
                Spacer(minLength: 0)
            }
            .clipShape(Capsule())
            .frame(height: 7)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 14)
    }
}

/// Compact +N / −N change badges.
struct StatBadges: View {
    let added: Int
    let removed: Int
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            if added > 0 { badge("+\(added)", .green) }
            if removed > 0 { badge("−\(removed)", .red) }
        }
    }

    private func badge(_ text: String, _ tint: Color) -> some View {
        Text(text)
            .font(.system(size: compact ? 10 : 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(tint)
            .padding(.horizontal, compact ? 5 : 6).padding(.vertical, compact ? 1 : 2)
            .background(tint.opacity(0.14), in: Capsule())
    }
}
