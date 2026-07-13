import SwiftUI

/// Detail pane for an update proposal: header with Apply/Dismiss and the
/// build-verification badge, then the same file-tree + diff browser the diff
/// sheets use, plus the selected agent's "what changed" summary in its Overview.
struct UpdateProposalView: View {
    @EnvironmentObject var app: AppState
    let proposal: UpdateProposal

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let error = app.proposalActionError {
                errorBanner(error)
                Divider()
            }
            if proposal.buildStatus == .failed, let tail = proposal.buildLogTail, !tail.isEmpty {
                buildFailNote(tail)
                Divider()
            }
            DiffBrowser(diff: app.proposalDiffText,
                        summary: app.summary,
                        summarizing: app.summarizing,
                        onRegenerate: { app.regenerateSummary() },
                        treeMinWidth: 200, paneMinWidth: 380)
                .id(proposal.id)   // reset file selection when switching proposals
        }
        .tint(Theme.accent)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(proposal.title).font(.headline).lineLimit(1)
                Text("Proposed \(proposal.createdAt.formatted(.relative(presentation: .named)))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            buildBadge
            Spacer()
            Button("Dismiss") { app.dismissProposal(proposal) }
                .disabled(app.busy)
                .help("Discard this proposal (worktree and branch are removed)")
            Button { app.applyProposal(proposal) } label: {
                Label("Stage for review", systemImage: "tray.and.arrow.down.fill")
            }
            .buttonStyle(.brand)
            .disabled(app.busy)
            .help("Stage this update as pending changes; review it, then Build & Apply to activate it")
        }
        .padding(14)
    }

    private var buildBadge: some View {
        let (text, symbol, tint): (String, String, Color) = {
            switch proposal.buildStatus {
            case .ok: return ("Build verified", "checkmark.seal.fill", .green)
            case .failed: return ("Build failed", "xmark.seal.fill", .red)
            case .unverified: return ("Not verified", "clock", .secondary)
            }
        }()
        return HStack(spacing: 4) {
            Image(systemName: symbol).font(.caption2)
            Text(text).font(.caption.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(tint.opacity(0.12), in: Capsule())
    }

    private func errorBanner(_ error: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn't stage this update").font(.callout.weight(.semibold))
                Text("\(error)\nResolve or apply your pending changes first, or dismiss this proposal and run a fresh check.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.orange.opacity(0.08))
    }

    private func buildFailNote(_ tail: [String]) -> some View {
        DisclosureGroup {
            Terminal(lines: tail)
                .frame(minHeight: 90, maxHeight: 220)
                .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                .padding(.top, 8)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "xmark.seal.fill").foregroundStyle(.red).font(.caption)
                Text("Verification build failed — you can still apply and fix from there")
                    .font(.caption.weight(.semibold))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color.red.opacity(0.05))
    }
}
