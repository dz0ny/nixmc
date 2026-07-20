import Foundation

/// Git-native history: a commit per apply, revert for rollback.
enum Git {
    struct Commit: Identifiable, Sendable {
        let id: String       // short hash
        let subject: String
        let date: Date
    }

    static func commitAll(_ message: String, in repo: URL) throws {
        _ = try Shell.run("/usr/bin/git", ["add", "-A"], cwd: repo)
        // `-c commit.gpgsign=false`: if the user signs commits, gpg pops an
        // interactive pinentry prompt with no tty here, hanging the commit (and,
        // on the main actor, the whole app). History commits are internal, so
        // never sign them.
        let r = try Shell.run("/usr/bin/git",
                              ["-c", "commit.gpgsign=false", "commit", "-q", "-m", message],
                              cwd: repo)
        // A no-op commit (nothing staged) is fine; only surface real failures.
        if !r.ok && !r.stdout.contains("nothing to commit") && !r.stderr.contains("nothing to commit") {
            throw NixmcError.command("git commit failed: \(r.stderr.isEmpty ? r.stdout : r.stderr)")
        }
    }

    static func log(in repo: URL, limit: Int = 50) -> [Commit] {
        guard let r = try? Shell.run("/usr/bin/git",
                                     ["log", "--pretty=%h\u{1f}%s\u{1f}%ct", "-n", "\(limit)"], cwd: repo),
              r.ok else { return [] }
        return r.stdout.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\u{1f}", maxSplits: 2)
            guard parts.count == 3, let epoch = TimeInterval(parts[2]) else { return nil }
            return Commit(id: String(parts[0]), subject: String(parts[1]),
                          date: Date(timeIntervalSince1970: epoch))
        }
    }

    /// Full patch for a commit (`git show`), for the diff viewer.
    static func show(_ hash: String, in repo: URL) -> String {
        guard let r = try? Shell.run("/usr/bin/git",
                                     ["show", "--no-color", "--stat", "--patch", hash], cwd: repo)
        else { return "Failed to load diff." }
        return r.ok ? r.stdout : (r.stderr.isEmpty ? r.stdout : r.stderr)
    }

    /// True when the working tree has uncommitted changes (tracked or new).
    static func hasChanges(in repo: URL) -> Bool {
        guard let r = try? Shell.run("/usr/bin/git", ["status", "--porcelain"], cwd: repo), r.ok
        else { return false }
        return !r.trimmedOut.isEmpty
    }

    /// Uncommitted changes vs HEAD, including untracked files, as a unified
    /// diff for the viewer. Non-mutating (uses `--no-index` for new files).
    static func workingDiff(in repo: URL) -> String {
        var out = ""
        if let r = try? Shell.run("/usr/bin/git",
                                  ["diff", "--stat", "--patch", "HEAD"], cwd: repo) {
            out += r.stdout
        }
        if let u = try? Shell.run("/usr/bin/git",
                                  ["ls-files", "-o", "--exclude-standard"], cwd: repo), u.ok {
            for f in u.stdout.split(separator: "\n") {
                // --no-index returns exit 1 with the patch on stdout; ignore the code.
                if let d = try? Shell.run("/usr/bin/git",
                                          ["diff", "--no-index", "/dev/null", String(f)], cwd: repo) {
                    out += d.stdout
                }
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "No uncommitted changes." : out
    }

    /// Drop all uncommitted changes (tracked and untracked) by stashing them,
    /// not hard-resetting — a mistaken drop stays recoverable with
    /// `git stash pop` until the stash is cleared.
    static func stashChanges(in repo: URL) throws {
        let r = try Shell.run("/usr/bin/git",
                              ["stash", "push", "--include-untracked", "-m",
                               "nixmc: dropped uncommitted changes"], cwd: repo)
        if !r.ok {
            throw NixmcError.command("git stash failed: \(r.stderr.isEmpty ? r.stdout : r.stderr)")
        }
    }

    /// Resolve a ref to its full sha. Nil when the ref doesn't exist.
    static func revParse(_ ref: String, in repo: URL) -> String? {
        guard let r = try? Shell.run("/usr/bin/git", ["rev-parse", "--verify", ref], cwd: repo),
              r.ok, !r.trimmedOut.isEmpty else { return nil }
        return r.trimmedOut
    }

    /// Create a linked worktree at `path` on a new branch cut from `base`.
    static func worktreeAdd(at path: URL, branch: String, from base: String, in repo: URL) throws {
        let r = try Shell.run("/usr/bin/git",
                              ["worktree", "add", "-b", branch, path.path, base], cwd: repo)
        if !r.ok {
            throw NixmcError.command("git worktree add failed: \(r.stderr.isEmpty ? r.stdout : r.stderr)")
        }
    }

    /// Remove a linked worktree, discarding whatever it holds. Best-effort.
    static func worktreeRemove(_ path: URL, in repo: URL) {
        _ = try? Shell.run("/usr/bin/git", ["worktree", "remove", "--force", path.path], cwd: repo)
    }

    /// Drop stale worktree bookkeeping (entries whose directory is gone). Best-effort.
    static func worktreePrune(in repo: URL) {
        _ = try? Shell.run("/usr/bin/git", ["worktree", "prune"], cwd: repo)
    }

    /// Force-delete a local branch. Best-effort — fails harmlessly if the branch
    /// is still checked out somewhere (remove its worktree first).
    static func deleteBranch(_ name: String, in repo: URL) {
        _ = try? Shell.run("/usr/bin/git", ["branch", "-D", name], cwd: repo)
    }

    /// Local branch names under a prefix (e.g. "nixmc/update/").
    static func localBranches(prefix: String, in repo: URL) -> [String] {
        guard let r = try? Shell.run("/usr/bin/git",
                                     ["for-each-ref", "--format=%(refname:short)",
                                      "refs/heads/\(prefix)"], cwd: repo), r.ok else { return [] }
        return r.stdout.split(separator: "\n").map(String.init)
    }

    /// Patch between two commits for the diff viewer. Deliberately NOT `git show`:
    /// its header embeds the sha/date, and the byte-identical diff string is what
    /// keys both proposal dedupe and the Summarizer cache.
    static func diff(_ base: String, _ tip: String, in repo: URL) -> String {
        guard let r = try? Shell.run("/usr/bin/git",
                                     ["diff", "--no-color", "--stat", "--patch",
                                      "\(base)..\(tip)"], cwd: repo)
        else { return "Failed to load diff." }
        return r.ok ? r.stdout : (r.stderr.isEmpty ? r.stdout : r.stderr)
    }

    /// Apply a commit's changes to the working tree without committing, so the
    /// normal pending-changes flow takes over. On conflict the pick is aborted
    /// (restoring the tree, keeping unrelated local edits) and the error thrown.
    static func cherryPickNoCommit(_ sha: String, in repo: URL) throws {
        let r = try Shell.run("/usr/bin/git",
                              ["-c", "commit.gpgsign=false", "cherry-pick", "-n", sha], cwd: repo)
        if !r.ok {
            _ = try? Shell.run("/usr/bin/git", ["cherry-pick", "--abort"], cwd: repo)
            throw NixmcError.command("cherry-pick failed: \(r.stderr.isEmpty ? r.stdout : r.stderr)")
        }
    }

    // MARK: remote sync

    /// Turns loose remote input into a real clone URL. The common case for a
    /// dotfiles repo is a bare GitHub handle (`you/dotfiles`), so that expands
    /// to a `git@`/`https://` GitHub URL; anything already URL-shaped (scheme,
    /// `git@host:`, `ssh://`, a local path) is passed through untouched.
    ///
    /// Accepted GitHub shorthands: `you/dotfiles`, `@you/dotfiles`,
    /// `github.com/you/dotfiles`, `https://github.com/you/dotfiles(.git)`.
    static func normalizeRemote(_ input: String, ssh: Bool = true) -> String {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return "" }

        // Already a full remote (scheme://, scp-style git@host:path, or a path).
        if s.contains("://") || s.hasPrefix("/") || s.hasPrefix("~") { return s }
        if s.hasPrefix("git@") || s.contains(":") && !s.contains("github.com/") { return s }

        // Strip a leading GitHub host / @, leaving `owner/repo`.
        s = s.replacingOccurrences(of: "github.com/", with: "")
        if s.hasPrefix("@") { s.removeFirst() }
        if s.hasSuffix(".git") { s = String(s.dropLast(4)) }

        // Expand only clean `owner/repo` handles; leave anything else as typed.
        let parts = s.split(separator: "/")
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty }) else { return input.trimmingCharacters(in: .whitespacesAndNewlines) }
        let handle = "\(parts[0])/\(parts[1])"
        return ssh ? "git@github.com:\(handle).git" : "https://github.com/\(handle).git"
    }

    /// URL of `origin`, if the repo has one (e.g. a user-cloned dotfiles repo).
    static func remoteURL(in repo: URL) -> String? {
        guard let r = try? Shell.run("/usr/bin/git", ["remote", "get-url", "origin"], cwd: repo),
              r.ok, !r.trimmedOut.isEmpty else { return nil }
        return r.trimmedOut
    }

    /// Point `origin` at `url`, adding the remote when the repo has none.
    static func setRemote(_ url: String, in repo: URL) throws {
        let sub = remoteURL(in: repo) == nil ? "add" : "set-url"
        let r = try Shell.run("/usr/bin/git", ["remote", sub, "origin", url], cwd: repo)
        if !r.ok {
            throw NixmcError.command("git remote \(sub) failed: \(r.stderr.isEmpty ? r.stdout : r.stderr)")
        }
    }

    /// Push the current branch to `origin`, setting the upstream on first push.
    /// `GIT_TERMINAL_PROMPT=0`: with no tty a credential prompt must fail fast
    /// (surfaced in the step log) instead of hanging the push forever.
    static func push(in repo: URL) throws {
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        let r = try Shell.run("/usr/bin/git", ["push", "-u", "origin", "HEAD"],
                              cwd: repo, env: env)
        if !r.ok {
            throw NixmcError.command("git push failed: \(r.stderr.isEmpty ? r.stdout : r.stderr)")
        }
    }

    /// Fast-forward the current branch from its configured upstream. This never
    /// creates a merge commit; divergent histories must be resolved explicitly.
    static func pull(in repo: URL) throws {
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        let r = try Shell.run("/usr/bin/git", ["pull", "--ff-only"], cwd: repo, env: env)
        if !r.ok {
            throw NixmcError.command("git pull failed: \(r.stderr.isEmpty ? r.stdout : r.stderr)")
        }
    }

    /// Roll back a specific commit (creates a new revert commit).
    static func revert(_ hash: String, in repo: URL) throws {
        // See commitAll: never sign — a pinentry prompt would hang with no tty.
        let r = try Shell.run("/usr/bin/git",
                              ["-c", "commit.gpgsign=false", "revert", "--no-edit", hash],
                              cwd: repo)
        if !r.ok {
            throw NixmcError.command("git revert failed: \(r.stderr.isEmpty ? r.stdout : r.stderr)")
        }
    }
}
