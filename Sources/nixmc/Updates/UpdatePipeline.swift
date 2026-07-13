import CryptoKit
import Foundation

/// The weekly update job: run `nix flake update` in an isolated worktree,
/// commit, build-verify, and hand back a proposal. Side effects only — the
/// pipeline never writes proposals.json (AppState owns store I/O on the main
/// actor) and never touches the `busy` gate (everything runs in the worktree).
enum UpdatePipeline {
    enum Outcome {
        case noChanges
        case duplicate
        case created(UpdateProposal)
        case failed(String)
    }

    static func run(repo: URL, host: String, existing: [UpdateProposal],
                    onLine: @escaping (String) -> Void) async -> Outcome {
        // Reap leftovers from a previous run that quit mid-check.
        cleanupOrphans(repo: repo, known: existing)

        guard let base = Git.revParse("HEAD", in: repo) else {
            return .failed("could not resolve HEAD in \(repo.path)")
        }

        let id = UpdatesStorage.makeID()
        let branch = UpdatesStorage.branchPrefix + id
        let dir = UpdatesStorage.worktreeDir(id: id)

        onLine("Creating worktree \(dir.path) on \(branch)…")
        do {
            try Git.worktreeAdd(at: dir, branch: branch, from: base, in: repo)
        } catch {
            return .failed("worktree add failed: \(error.localizedDescription)")
        }
        // On any exit path below that isn't `.created`, tear the worktree down.
        func discard() { discardArtifacts(worktree: dir, branch: branch, repo: repo) }

        onLine("Running nix flake update…")
        let code = await Shell.streamLogin("nix flake update", cwd: dir, onLine: onLine)
        guard code == 0 else {
            discard()
            return .failed("nix flake update exited with \(code) (offline?)")
        }

        guard Git.hasChanges(in: dir) else {
            discard()
            onLine("All flake inputs already up to date.")
            return .noChanges
        }

        // Draft a commit title from the working diff before committing.
        let fallback = "Update flake inputs (\(id))"
        let title = await Summarizer.commitMessage(for: Git.workingDiff(in: dir), cwd: dir) ?? fallback
        do {
            try Git.commitAll(title, in: dir)
        } catch {
            discard()
            return .failed("commit failed: \(error.localizedDescription)")
        }
        guard let tip = Git.revParse("HEAD", in: dir), tip != base else {
            discard()
            return .failed("update commit did not materialize")
        }

        // Dedupe by diff content before paying for a verify build. The diff is
        // read via Git.diff so it's byte-identical to what the viewer loads.
        let branchDiff = Git.diff(base, tip, in: repo)
        let diffHash = sha256(branchDiff)
        if existing.contains(where: { $0.diffHash == diffHash }) {
            discard()
            onLine("Identical update already proposed — skipping.")
            return .duplicate
        }

        onLine("Verifying with darwin-rebuild build…")
        var logTail: [String] = []
        let buildOK = await DarwinRebuild.build(flakeDir: dir, host: host) { line in
            logTail.append(line)
            if logTail.count > 40 { logTail.removeFirst(logTail.count - 40) }
            onLine(line)
        }
        // build runs --no-link, but stay defensive about a stray result symlink
        // so it can never end up inside a future commit.
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("result"))

        // Pre-warm the summary cache with the exact diff string the viewer will
        // hash, so opening the proposal shows "What changed" instantly.
        onLine("Generating change summary…")
        _ = await Summarizer.summarize(branchDiff, cwd: repo)

        let proposal = UpdateProposal(
            id: id,
            createdAt: Date(),
            branch: branch,
            baseCommit: base,
            tipCommit: tip,
            diffHash: diffHash,
            title: title,
            buildStatus: buildOK ? .ok : .failed,
            buildLogTail: buildOK ? nil : logTail,
            worktreePath: dir.path)
        onLine(buildOK ? "Proposal ready (build verified)." : "Proposal ready (build FAILED — see log).")
        return .created(proposal)
    }

    /// Remove a proposal's worktree and branch. Order matters: git refuses to
    /// delete a branch that is still checked out in a worktree.
    static func discardArtifacts(of p: UpdateProposal, repo: URL) {
        discardArtifacts(worktree: URL(fileURLWithPath: p.worktreePath), branch: p.branch, repo: repo)
    }

    private static func discardArtifacts(worktree: URL, branch: String, repo: URL) {
        Git.worktreeRemove(worktree, in: repo)
        try? FileManager.default.removeItem(at: worktree)
        Git.deleteBranch(branch, in: repo)
        Git.worktreePrune(in: repo)
    }

    /// Crash recovery: drop worktree directories and nixmc/update/* branches
    /// that no known proposal references (e.g. the app quit mid-check).
    static func cleanupOrphans(repo: URL, known: [UpdateProposal]) {
        Git.worktreePrune(in: repo)

        let knownIDs = Set(known.map(\.id))
        let fm = FileManager.default
        if let entries = try? fm.contentsOfDirectory(at: UpdatesStorage.rootDir,
                                                     includingPropertiesForKeys: [.isDirectoryKey]) {
            for entry in entries {
                guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                      !knownIDs.contains(entry.lastPathComponent) else { continue }
                Git.worktreeRemove(entry, in: repo)
                try? fm.removeItem(at: entry)
            }
        }

        let knownBranches = Set(known.map(\.branch))
        for branch in Git.localBranches(prefix: UpdatesStorage.branchPrefix, in: repo)
        where !knownBranches.contains(branch) {
            Git.deleteBranch(branch, in: repo)
        }
        Git.worktreePrune(in: repo)
    }

    private static func sha256(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
