#!/usr/bin/env python3
"""Apply: sync the fork branches with upstream/master in one command.

Steps. Nothing is pushed until every check has passed.
  1. Refuse if the working tree has tracked changes, if the upstream or origin remote is
     missing, or if a fork branch that this script moves is checked out in a worktree.
  2. Fetch upstream/master and the fork branches from origin (remote-tracking refs only).
  3. Fast-forward master to upstream/master (ff-only).
  4. Merge master into per-app-remaps and fork-setup, then merge the new per-app-remaps,
     fork-setup and master into personal. Stop at the first conflict.
  5. Check that each new branch tip contains origin's tip (fast-forward push only).
  6. Grep checks on fork-setup and personal: SUFeedURL is absent from
     App/SupportFiles/Info.plist, and com.nuebling is absent from the files the fork changes.
  7. Build the App and Helper schemes (CODE_SIGNING_ALLOWED=NO) at each tip that is pushed,
     and at the personal tip.
  8. Push master, per-app-remaps, fork-setup and personal to origin (fast-forward only).
     After each push, move the local branch to the pushed commit. Then write last-synced.

Merges and builds run in a temporary git worktree under the system temp directory. The
checkout you run this from keeps its HEAD, branches and files. The one exception is
tools/upstream-sync/last-synced, which is written at the end. It is not committed. Commit it
on your own branch.

--dry-run does steps 1 to 7 and prints what would be pushed. It pushes nothing, moves no
branch, and does not write last-synced.

Exit codes:
  0  synced, already synced, or dry run passed
  1  stopped before pushing: merge conflict, failed grep check, or failed build
  2  refused or error: see the message. A refusal changes nothing. A failed push also exits 2:
     branches pushed before it stay on origin, so run apply again after fixing the cause.

Test hook: MMF_UPSTREAM_SYNC_BUILD_CMD replaces the xcodebuild call. It runs with sh -c, with
the temporary worktree as cwd and MMF_SYNC_SCHEME, MMF_SYNC_TIP and MMF_SYNC_DERIVED_DATA set.

Standard library only. Imports helpers from sync_check.py in the same directory.
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from sync_check import (
    LAST_SYNCED_FILE,
    NETWORK_TIMEOUT,
    UPSTREAM_REF,
    CheckError,
    fetch_upstream_master,
    git,
    git_checked,
    is_ancestor,
    require_remote,
    resolve_commit,
)

REMOTE_ORIGIN = "origin"
LAST_SYNCED_FILE_REL = "tools/upstream-sync/last-synced"
# Order matters: each branch is pushed after the ones before it.
FORK_BRANCHES = ("master", "per-app-remaps", "fork-setup", "personal")
# Branches with fork-only changes. Only these get the grep checks.
# master and per-app-remaps keep upstream's SUFeedURL and identifiers on purpose.
CHECKED_BRANCHES = ("fork-setup", "personal")
INFO_PLIST = "App/SupportFiles/Info.plist"
# com.nuebling identifiers that stay on purpose. This is the legacy launchd plist path
# that HelperServices.m removes from old installs.
LEGACY_UPSTREAM_IDS = ("com.nuebling.mousefix.helper.plist",)
XCODE_PROJECT = "Mouse Fix.xcodeproj"
BUILD_SCHEMES = ("App", "Helper")
BUILD_CMD_ENV = "MMF_UPSTREAM_SYNC_BUILD_CMD"

EXIT_OK = 0
EXIT_STOPPED = 1
EXIT_REFUSED = 2


class StopApply(Exception):
    """A check, merge or build failed. Nothing has been pushed. Callers exit with EXIT_STOPPED."""


def git_at(cwd: Path, *args: str, timeout: Optional[float] = None) -> Tuple[int, str, str]:
    """Run git in cwd (a worktree). Returns (returncode, stdout, stderr)."""
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0")
    proc = subprocess.run(
        ["git", "-C", str(cwd), *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        timeout=timeout,
    )
    return (
        proc.returncode,
        proc.stdout.decode("utf-8", "replace"),
        proc.stderr.decode("utf-8", "replace").strip(),
    )


def git_at_checked(cwd: Path, *args: str) -> str:
    rc, out, err = git_at(cwd, *args)
    if rc != 0:
        raise CheckError(f"git {' '.join(args)} failed (exit {rc}): {err or 'no output'}")
    return out


def check_origin_configured() -> None:
    if REMOTE_ORIGIN not in git_checked("remote").split():
        raise CheckError(
            f'git remote "{REMOTE_ORIGIN}" is not configured. Add it with:\n'
            f"  git remote add {REMOTE_ORIGIN} <url of your fork>"
        )


def check_clean_tree() -> None:
    out = git_checked("status", "--porcelain", "--untracked-files=no")
    if out.strip():
        changed = "\n".join("  " + line for line in out.splitlines())
        raise CheckError(
            "the working tree has uncommitted changes. Commit or stash them, then run apply again. "
            "If the only change is tools/upstream-sync/last-synced from the previous sync, commit that file.\n"
            + changed
        )


def check_not_checked_out(branches: Tuple[str, ...]) -> None:
    """A branch that is checked out in any worktree cannot be moved without touching that checkout."""
    out = git_checked("worktree", "list", "--porcelain")
    path = ""
    for line in out.splitlines():
        if line.startswith("worktree "):
            path = line[len("worktree "):]
        elif line.startswith("branch refs/heads/"):
            name = line[len("branch refs/heads/"):]
            if name in branches:
                raise CheckError(
                    f"branch {name} is checked out in {path}. Apply moves this branch, so check out "
                    "another branch in that worktree first, then run apply again."
                )


def fetch_origin_branches() -> None:
    refspecs = [f"+refs/heads/{b}:refs/remotes/{REMOTE_ORIGIN}/{b}" for b in FORK_BRANCHES]
    git_checked("fetch", "--no-tags", "--quiet", REMOTE_ORIGIN, *refspecs, timeout=NETWORK_TIMEOUT)


def merge_into(worktree: Path, branch: str, tip: str, sources: List[Tuple[str, str]]) -> str:
    """Merge each (name, commit) into tip in the temporary worktree. Returns the new tip.

    On a conflict the merge is aborted and StopApply is raised. The conflicting files are listed.
    """
    git_at_checked(worktree, "checkout", "--quiet", "--detach", tip)
    for name, sha in sources:
        rc, _, err = git_at(worktree, "merge", "--no-edit", "-m", f"Sync: merge {name} into {branch}", sha)
        if rc == 0:
            continue
        _, conflicted, _ = git_at(worktree, "diff", "--name-only", "-z", "--diff-filter=U")
        files = [f for f in conflicted.split("\0") if f]
        git_at(worktree, "merge", "--abort")
        if files:
            listing = "\n".join(f"  conflict: {f}" for f in files)
            raise StopApply(
                f"merging {name} into {branch} conflicts in {len(files)} file(s):\n{listing}\n"
                "The merge was aborted. Nothing was pushed. Resolve this by hand, then run apply again."
            )
        raise StopApply(
            f"merging {name} into {branch} failed: {err or 'no output'}. "
            "The merge was aborted. Nothing was pushed."
        )
    return git_at_checked(worktree, "rev-parse", "HEAD").strip()


def changed_paths(a: str, b: str) -> List[str]:
    """Paths that differ between two commits. Renames count as delete plus add."""
    out = git_checked("diff", "--name-only", "--no-renames", "-z", a, b)
    return [p for p in out.split("\0") if p]


def fork_checks(upstream: str, new: Dict[str, str]) -> List[str]:
    """Return a list of problems. An empty list means every check passed."""
    problems: List[str] = []
    for branch in CHECKED_BRANCHES:
        tip = new[branch]

        rc, _, _ = git("cat-file", "-e", f"{tip}:{INFO_PLIST}")
        if rc != 0:
            problems.append(f"{branch}: {INFO_PLIST} does not exist, so the SUFeedURL check cannot run")
        else:
            rc, _, err = git("grep", "-q", "-F", "SUFeedURL", tip, "--", INFO_PLIST)
            if rc == 0:
                problems.append(f"{branch}: SUFeedURL is present in {INFO_PLIST}")
            elif rc != 1:
                problems.append(f"{branch}: grep for SUFeedURL failed (exit {rc}): {err}")

        # Fork-owned files are the files that differ from upstream/master. For personal this
        # includes the per-app-remaps changes, so that branch is covered too.
        paths = changed_paths(upstream, tip)
        if not paths:
            continue
        rc, out, err = git("grep", "-n", "-F", "com.nuebling", tip, "--", *[":(literal)" + p for p in paths])
        if rc == 1:
            continue
        if rc != 0:
            problems.append(f"{branch}: grep for com.nuebling failed (exit {rc}): {err}")
            continue
        for line in out.splitlines():
            if any(legacy in line for legacy in LEGACY_UPSTREAM_IDS):
                continue
            problems.append(f"{branch}: com.nuebling in a fork-owned file: {line[:200]}")
    return problems


def keep_log(log: Path) -> Path:
    """Copy a failed build log out of the temporary directory, which is deleted at the end."""
    fd, name = tempfile.mkstemp(prefix="mmf-upstream-apply-build-", suffix=".log")
    os.close(fd)
    shutil.copyfile(str(log), name)
    return Path(name)


def build_tip(worktree: Path, tmp: Path, derived: Path, label: str, tip: str) -> None:
    git_at_checked(worktree, "checkout", "--quiet", "--detach", tip)
    override = os.environ.get(BUILD_CMD_ENV)
    for scheme in BUILD_SCHEMES:
        print(f"  building scheme {scheme} at {label} ({tip[:10]})")
        log = tmp / f"build-{label}-{scheme}.log"
        env = dict(
            os.environ,
            MMF_SYNC_SCHEME=scheme,
            MMF_SYNC_TIP=tip,
            MMF_SYNC_DERIVED_DATA=str(derived),
        )
        if override:
            argv = ["/bin/sh", "-c", override]
        else:
            argv = [
                "xcodebuild",
                "-project", XCODE_PROJECT,
                "-scheme", scheme,
                "-configuration", "Debug",
                "-derivedDataPath", str(derived),
                "CODE_SIGNING_ALLOWED=NO",
                "build",
            ]
        with log.open("wb") as fh:
            rc = subprocess.run(argv, cwd=str(worktree), stdout=fh, stderr=subprocess.STDOUT, env=env).returncode
        if rc != 0:
            kept = keep_log(log)
            tail = "\n".join(log.read_text(errors="replace").splitlines()[-30:])
            raise StopApply(
                f"build of scheme {scheme} at {label} failed (exit {rc}). Nothing was pushed.\n"
                f"Full log: {kept}\nLast lines:\n{tail}"
            )


def remove_worktree(worktree: Path) -> None:
    if worktree.exists():
        rc, _, _ = git("worktree", "remove", "--force", str(worktree))
        if rc != 0:
            shutil.rmtree(str(worktree), ignore_errors=True)
    git("worktree", "prune")


def read_last_synced() -> str:
    if not LAST_SYNCED_FILE.is_file():
        return ""
    words = LAST_SYNCED_FILE.read_text().split()
    return words[0] if words else ""


def print_upstream_commits(old: str, upstream: str) -> None:
    lines = git_checked("log", "--reverse", "--format=%h %s", f"{old}..{upstream}").splitlines()
    print(f"Upstream commits to merge: {len(lines)}")
    for line in lines:
        print(f"  {line}")


def apply(dry_run: bool) -> int:
    # 1. Preconditions. Nothing has changed yet.
    require_remote()
    check_origin_configured()
    check_clean_tree()
    for branch in FORK_BRANCHES:
        resolve_commit(f"refs/heads/{branch}", f"branch {branch}")
    check_not_checked_out(FORK_BRANCHES)

    # 2. Fetch. Only remote-tracking refs change.
    print("Fetching upstream/master and origin fork branches")
    fetch_upstream_master()
    upstream = resolve_commit(UPSTREAM_REF, "upstream master")
    fetch_origin_branches()
    old = {b: resolve_commit(f"refs/heads/{b}", f"branch {b}") for b in FORK_BRANCHES}
    origin = {b: resolve_commit(f"refs/remotes/{REMOTE_ORIGIN}/{b}", f"{REMOTE_ORIGIN}/{b}") for b in FORK_BRANCHES}
    if not is_ancestor(old["master"], upstream):
        raise CheckError(
            "master is not an ancestor of upstream/master, so it cannot be fast-forwarded. "
            "The fork's master has commits that upstream does not have, or upstream rewrote its history. "
            "Nothing was changed."
        )

    # All merges and builds happen in a temporary worktree, outside the repository.
    tmp = Path(tempfile.mkdtemp(prefix="mmf-upstream-apply-"))
    worktree = tmp / "worktree"
    derived = tmp / "DerivedData"
    try:
        git_checked("worktree", "add", "--detach", "--quiet", str(worktree), old["master"])

        # 3 and 4. Fast-forward master, then merge.
        print_upstream_commits(old["master"], upstream)
        new: Dict[str, str] = {"master": upstream}
        print("Merging master into per-app-remaps and fork-setup")
        new["per-app-remaps"] = merge_into(worktree, "per-app-remaps", old["per-app-remaps"], [("master", upstream)])
        new["fork-setup"] = merge_into(worktree, "fork-setup", old["fork-setup"], [("master", upstream)])
        print("Merging master, per-app-remaps and fork-setup into personal")
        new["personal"] = merge_into(
            worktree,
            "personal",
            old["personal"],
            [("master", upstream), ("per-app-remaps", new["per-app-remaps"]), ("fork-setup", new["fork-setup"])],
        )

        # 5. Every new tip must contain origin's tip, so the push is a fast-forward.
        for branch in FORK_BRANCHES:
            if not is_ancestor(origin[branch], new[branch]):
                raise CheckError(
                    f"origin/{branch} has commits that the new {branch} does not contain. "
                    f"Fetch them into local {branch} (fast-forward), then run apply again. Nothing was pushed."
                )

        pushes = [b for b in FORK_BRANCHES if new[b] != origin[b]]

        # 6. Grep checks. Always run, so a broken state is reported even when nothing is pushed.
        print("Grep checks: SUFeedURL and com.nuebling in fork-owned files")
        problems = fork_checks(upstream, new)
        if problems:
            raise StopApply("grep checks failed. Nothing was pushed:\n" + "\n".join("  " + p for p in problems))

        # 7. Builds. Every tip that gets pushed, plus personal.
        if pushes:
            build_order = [b for b in FORK_BRANCHES if b in pushes or b == "personal"]
            print("Building App and Helper (CODE_SIGNING_ALLOWED=NO)")
            for branch in build_order:
                build_tip(worktree, tmp, derived, branch, new[branch])

        if dry_run:
            print()
            print("Dry run. Would push (fast-forward, nothing pushed):")
            for branch in FORK_BRANCHES:
                print(f"  {branch:<16}{origin[branch][:10]} -> {new[branch][:10]}" if branch in pushes
                      else f"  {branch:<16}unchanged on origin")
            print("No branch was moved and last-synced was not written.")
            return EXIT_OK

        # 8. Push, then move the local branch to the pushed commit. The local branch
        # is only updated after its push succeeds, so a failed push leaves them consistent.
        for branch in FORK_BRANCHES:
            if branch in pushes:
                print(f"Pushing {branch} to {REMOTE_ORIGIN}")
                rc, _, err = git("push", "--quiet", REMOTE_ORIGIN, f"{new[branch]}:refs/heads/{branch}", timeout=NETWORK_TIMEOUT)
                if rc != 0:
                    raise CheckError(
                        f"push of {branch} failed (exit {rc}): {err}. Branches pushed before it are "
                        "already on origin. Run apply again after fixing the cause."
                    )
            if new[branch] != old[branch]:
                git_checked("update-ref", f"refs/heads/{branch}", new[branch], old[branch])

        old_sync = read_last_synced()
        LAST_SYNCED_FILE.write_text(upstream + "\n")

        print()
        if pushes:
            print("Synced. Pushed to origin (old -> new):")
            for branch in pushes:
                print(f"  {branch:<16}{origin[branch][:10]} -> {new[branch][:10]}")
        else:
            print("Already synced. Nothing to push.")
        print(f"  last-synced     {old_sync[:10] or 'none'} -> {upstream[:10]}")
        print()
        print("Commit the new sync point on your own branch:")
        print(f"  git add {LAST_SYNCED_FILE_REL}")
        print(f"  git commit -m 'Sync with upstream {upstream[:10]}'")
        return EXIT_OK
    finally:
        remove_worktree(worktree)
        shutil.rmtree(str(tmp), ignore_errors=True)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Sync master, per-app-remaps, fork-setup and personal with upstream/master: "
        "merge, check, build and push in one command."
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="merge, check and build, but push nothing, move no branch and do not write last-synced",
    )
    args = parser.parse_args()
    try:
        return apply(dry_run=args.dry_run)
    except StopApply as exc:
        print(f"apply: stopped: {exc}", file=sys.stderr)
        return EXIT_STOPPED
    except CheckError as exc:
        print(f"apply: error: {exc}", file=sys.stderr)
        return EXIT_REFUSED


if __name__ == "__main__":
    sys.exit(main())
