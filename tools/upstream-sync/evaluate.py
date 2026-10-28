#!/usr/bin/env python3
"""Evaluate: trial-merge upstream/master into the fork branches without changing them.

For each branch (default: master, per-app-remaps, fork-setup) it reports:
  - the conflicting files of a trial merge (git merge-tree --write-tree),
  - files changed upstream since the merge base that match the risk paths,
  - the upstream commit log since the merge base.

No branch, index or working tree is changed. Nothing is committed or pushed.
Git may add tree and blob objects to the object database, which is harmless.

Exit codes:
  0  every checked branch merges cleanly with upstream/master
  1  at least one checked branch conflicts with upstream/master
  2  error (remote or branch missing, fetch failed, git too old for merge-tree)

Standard library only. Imports helpers from sync_check.py in the same directory.
"""

import argparse
import sys
from typing import Dict, List, Tuple

from sync_check import (
    UPSTREAM_REF,
    CheckError,
    fetch_upstream_master,
    git,
    git_checked,
    require_remote,
    resolve_commit,
)

DEFAULT_BRANCHES = ("master", "per-app-remaps", "fork-setup")

# Risk paths in the remap engine and remap UI. Entries ending with "/" match a directory.
RISK_PATHS = (
    "Helper/Core/Remap/",
    "Helper/Core/Modifiers/",
    "Helper/Core/Coordinate/SwitchMaster.swift",
    "Shared/Constants.h",
    "App/UI/Main/Tabs/ButtonTab/RemapTable/",
)

MERGE_TREE_FLAGS = ("--write-tree", "--name-only", "--no-messages", "-z")

EXIT_CLEAN = 0
EXIT_CONFLICTS = 1
EXIT_ERROR = 2


def is_risk_path(path: str) -> bool:
    return any(path.startswith(p) if p.endswith("/") else path == p for p in RISK_PATHS)


def check_merge_tree_support() -> None:
    """Stop early if this git cannot run the trial merge. Merging upstream into itself is always clean."""
    rc, _, err = git("merge-tree", *MERGE_TREE_FLAGS, UPSTREAM_REF, UPSTREAM_REF)
    if rc != 0:
        raise CheckError(
            "this git cannot run `git merge-tree " + " ".join(MERGE_TREE_FLAGS) + "` "
            f"(exit {rc}), so the trial merge check is not possible. Install a newer git. {err}"
        )


def merge_base(a: str, b: str) -> str:
    rc, out, _ = git("merge-base", a, b)
    if rc != 0 or not out.strip():
        raise CheckError(f"no merge base between {a} and {b}")
    return out.strip()


def upstream_changes(base: str) -> List[Tuple[str, str]]:
    """(status, path) for every file that differs between base and upstream/master."""
    tokens = git_checked("diff", "--name-status", "--no-renames", "-z", base, UPSTREAM_REF).split("\0")
    return [(tokens[i], tokens[i + 1]) for i in range(0, len(tokens) - 1, 2)]


def evaluate_branch(branch: str) -> Dict:
    tip = resolve_commit(f"refs/heads/{branch}", f"branch {branch}")
    base = merge_base(tip, UPSTREAM_REF)

    # Exit 0: clean. Exit 1: conflicts, one file per NUL-terminated line after the tree id.
    rc, out, err = git("merge-tree", *MERGE_TREE_FLAGS, tip, UPSTREAM_REF)
    if rc == 0:
        conflicts: List[str] = []
    elif rc == 1:
        conflicts = [name for name in out.split("\0")[1:] if name]
    else:
        raise CheckError(f"trial merge of {branch} failed (exit {rc}): {err}")

    changes = upstream_changes(base)
    commits = git_checked("log", "--reverse", "--format=%h %s", f"{base}..{UPSTREAM_REF}").splitlines()
    return {
        "branch": branch,
        "tip": tip,
        "base": base,
        "conflicts": conflicts,
        "changes": changes,
        "risk": [(status, path) for status, path in changes if is_risk_path(path)],
        "commits": commits,
    }


def print_report(results: List[Dict], max_commits: int) -> None:
    for r in results:
        print(f"== {r['branch']} ==")
        print(f"  tip:                  {r['tip'][:10]}")
        print(f"  merge base:           {r['base'][:10]}")
        if r["conflicts"]:
            print(f"  trial merge:          CONFLICTS in {len(r['conflicts'])} file(s)")
            for path in r["conflicts"]:
                print(f"    conflict: {path}")
        else:
            print("  trial merge:          clean")
        print(f"  risk paths changed:   {len(r['risk'])}")
        for status, path in r["risk"]:
            print(f"    {status} {path}")
        print(f"  upstream files changed since merge base: {len(r['changes'])}")
        print(f"  upstream commits since merge base:       {len(r['commits'])}")
        for line in r["commits"][:max_commits]:
            print(f"    {line}")
        if len(r["commits"]) > max_commits:
            print(f"    ... {len(r['commits']) - max_commits} more (use --max-commits)")
        print()

    print("Summary")
    print(f"  {'branch':<16}{'conflicts':>10}{'risk files':>12}{'upstream commits':>18}")
    for r in results:
        print(f"  {r['branch']:<16}{len(r['conflicts']):>10}{len(r['risk']):>12}{len(r['commits']):>18}")
    print()
    print("Nothing was merged, built or pushed. The Apply step is manual (see README.md).")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Trial-merge upstream/master into fork branches without changing them."
    )
    parser.add_argument(
        "branches",
        nargs="*",
        default=list(DEFAULT_BRANCHES),
        help="branches to check (default: master per-app-remaps fork-setup)",
    )
    parser.add_argument(
        "--no-fetch", action="store_true", help="do not fetch upstream; use the local upstream/master"
    )
    parser.add_argument(
        "--max-commits", type=int, default=30, help="upstream commits to list per branch (default: 30)"
    )
    args = parser.parse_args()

    try:
        require_remote()
        if not args.no_fetch:
            fetch_upstream_master()
        resolve_commit(UPSTREAM_REF, "upstream master")
        check_merge_tree_support()
        results = [evaluate_branch(branch) for branch in args.branches]
    except CheckError as exc:
        print(f"evaluate: error: {exc}", file=sys.stderr)
        return EXIT_ERROR

    print_report(results, args.max_commits)
    return EXIT_CONFLICTS if any(r["conflicts"] for r in results) else EXIT_CLEAN


if __name__ == "__main__":
    sys.exit(main())
