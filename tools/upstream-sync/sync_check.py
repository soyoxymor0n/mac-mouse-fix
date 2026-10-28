#!/usr/bin/env python3
"""Inform: report new commits and tags on the upstream Mac Mouse Fix repository.

Fetches upstream/master, lists the upstream tags, and compares both with the last
synced upstream commit stored in last-synced (next to this script).

A tag counts as new when its commit is on upstream/master and is not yet included
in last-synced. Tags that only exist on other upstream branches are ignored.

Exit codes:
  0  nothing new since the last sync
  1  new commits and/or new tags
  2  error (remote missing, network failure, last-synced missing or invalid)

This script never writes last-synced. Only a confirmed sync changes that file.
Standard library only.
"""

import argparse
import os
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

SCRIPT_DIR = Path(__file__).resolve().parent


def _find_repo_root() -> Path:
    try:
        out = subprocess.run(
            ["git", "-C", str(SCRIPT_DIR), "rev-parse", "--show-toplevel"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        ).stdout
        return Path(out.decode("utf-8", "replace").strip())
    except (OSError, subprocess.CalledProcessError):
        return SCRIPT_DIR  # git will report the problem when the first command runs


# git runs from the repository root. `git merge-tree` prints paths relative to the
# current directory, so running it from tools/upstream-sync/ would give "../../" paths.
REPO_ROOT = _find_repo_root()
REMOTE = "upstream"
UPSTREAM_BRANCH = "master"
UPSTREAM_REF = f"refs/remotes/{REMOTE}/{UPSTREAM_BRANCH}"
LAST_SYNCED_FILE = SCRIPT_DIR / "last-synced"
NETWORK_TIMEOUT = 300  # seconds

EXIT_NOTHING_NEW = 0
EXIT_NEW = 1
EXIT_ERROR = 2


class CheckError(Exception):
    """Stops the check. Callers print it to stderr and exit with EXIT_ERROR."""


def git(*args: str, timeout: Optional[float] = None) -> Tuple[int, str, str]:
    """Run git inside this repository. Returns (returncode, stdout, stderr)."""
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0")  # never block on a credential prompt
    try:
        proc = subprocess.run(
            ["git", "-C", str(REPO_ROOT), *args],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        raise CheckError(f"git {args[0]} timed out after {timeout} s")
    except FileNotFoundError:
        raise CheckError("git was not found on PATH")
    return (
        proc.returncode,
        proc.stdout.decode("utf-8", "replace"),
        proc.stderr.decode("utf-8", "replace").strip(),
    )


def git_checked(*args: str, timeout: Optional[float] = None) -> str:
    """Like git(), but raises CheckError on a non-zero exit code."""
    rc, out, err = git(*args, timeout=timeout)
    if rc != 0:
        raise CheckError(f"git {' '.join(args)} failed (exit {rc}): {err or 'no output'}")
    return out


def require_remote() -> None:
    if REMOTE not in git_checked("remote").split():
        raise CheckError(
            f'git remote "{REMOTE}" is not configured. Add it with:\n'
            f"  git remote add {REMOTE} https://github.com/noah-nuebling/mac-mouse-fix.git"
        )


def fetch_upstream_master() -> None:
    """Update refs/remotes/upstream/master. No local branch or tag is touched.

    Callers must run require_remote() first.
    """
    git_checked(
        "fetch",
        "--no-tags",
        "--quiet",
        REMOTE,
        f"+refs/heads/{UPSTREAM_BRANCH}:{UPSTREAM_REF}",
        timeout=NETWORK_TIMEOUT,
    )


def resolve_commit(rev: str, what: str) -> str:
    rc, out, _ = git("rev-parse", "--verify", "--quiet", f"{rev}^{{commit}}")
    if rc != 0:
        raise CheckError(f"{what} does not resolve to a commit: {rev}")
    return out.strip()


def is_ancestor(ancestor: str, descendant: str) -> bool:
    rc, _, err = git("merge-base", "--is-ancestor", ancestor, descendant)
    if rc not in (0, 1):
        raise CheckError(f"git merge-base --is-ancestor failed: {err}")
    return rc == 0


def one_line(rev: str) -> str:
    """Short hash and subject of a commit."""
    return git_checked("log", "-1", "--format=%h %s", rev).strip()


def read_last_synced() -> str:
    if not LAST_SYNCED_FILE.is_file():
        raise CheckError(
            f"{LAST_SYNCED_FILE} does not exist. Create it once with the merge base:\n"
            f"  git merge-base master {UPSTREAM_REF} > {LAST_SYNCED_FILE}"
        )
    words = LAST_SYNCED_FILE.read_text().split()
    if not words:
        raise CheckError(f"{LAST_SYNCED_FILE} is empty")
    return resolve_commit(words[0], LAST_SYNCED_FILE.name)


def list_upstream_tags() -> Dict[str, str]:
    """Return {tag name: commit sha} from the remote. Reads only; no local tags are created."""
    tags: Dict[str, str] = {}
    out = git_checked("ls-remote", "--tags", REMOTE, timeout=NETWORK_TIMEOUT)
    for line in out.splitlines():
        sha, _, ref = line.partition("\t")
        if not ref.startswith("refs/tags/"):
            continue
        name = ref[len("refs/tags/"):]
        if name.endswith("^{}"):
            # Peeled commit of an annotated tag. Listed after the tag object, so it wins.
            tags[name[: -len("^{}")]] = sha
        else:
            tags.setdefault(name, sha)
    return tags


def new_tags(tags: Dict[str, str], last: str) -> Tuple[List[Tuple[str, str]], int]:
    """Return (tags new on upstream/master, number of tags that are not on upstream/master)."""
    new: List[Tuple[str, str]] = []
    ignored = 0
    for name in sorted(tags):
        sha = tags[name]
        rc, _, _ = git("rev-parse", "--verify", "--quiet", f"{sha}^{{commit}}")
        if rc != 0 or not is_ancestor(sha, UPSTREAM_REF):
            ignored += 1
            continue
        if not is_ancestor(sha, last):
            new.append((name, sha))
    return new, ignored


def check() -> int:
    require_remote()
    fetch_upstream_master()
    upstream = resolve_commit(UPSTREAM_REF, "upstream master")
    last = read_last_synced()
    url = git_checked("remote", "get-url", REMOTE).strip()

    print(f"Upstream:        {url}")
    print(f"Last synced:     {one_line(last)}")
    print(f"Upstream master: {one_line(upstream)}")
    if not is_ancestor(last, upstream):
        print("warning: last-synced is not an ancestor of upstream/master. Upstream history may have been rewritten.")

    commits = git_checked("log", "--reverse", "--format=%h %s", f"{last}..{upstream}").splitlines()
    tags_new, tags_ignored = new_tags(list_upstream_tags(), last)

    print()
    print(f"New commits on upstream/master: {len(commits)}")
    for line in commits:
        print(f"  {line}")
    print(f"New tags on upstream/master: {len(tags_new)}")
    for name, sha in tags_new:
        print(f"  {name} ({sha[:10]})")
    print(f"Upstream tags not on upstream/master (ignored): {tags_ignored}")
    print()

    if commits or tags_new:
        print("Result: new upstream changes. Run evaluate.py before syncing.")
        return EXIT_NEW
    print("Result: nothing new since the last sync.")
    return EXIT_NOTHING_NEW


def main() -> int:
    argparse.ArgumentParser(
        description="Report new commits and tags on upstream since the last sync."
    ).parse_args()
    try:
        return check()
    except CheckError as exc:
        print(f"sync_check: error: {exc}", file=sys.stderr)
        return EXIT_ERROR


if __name__ == "__main__":
    sys.exit(main())
