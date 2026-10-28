# Upstream sync: Inform and Evaluate

Tools for issue #1 of this fork: keep informed about upstream Mac Mouse Fix
(`noah-nuebling/mac-mouse-fix`) and judge the impact of its changes before
anything is merged.

- `sync_check.py` (Inform): reports new upstream commits and tags since the last sync.
- `evaluate.py` (Evaluate): trial-merges `upstream/master` into the fork branches and reports conflicts, risk-path changes and the upstream commit log.
- `last-synced`: the upstream commit the fork has merged up to. Only a confirmed sync changes it.

Both scripts use only the Python standard library. Run them from the repository
root. Neither script changes a branch, the index, a working tree, or `last-synced`.

## Apply step: not implemented

The Apply step (fast-forward `master` from `upstream/master`, merge it into the
other fork branches, build, push) is **not implemented**. It stays a manual step
that the owner runs after reading the evaluation.

After a sync you have confirmed, update the sync point and commit it with the
sync:

```sh
git rev-parse upstream/master > tools/upstream-sync/last-synced
```

## Setup

- Remote: `upstream` must point to `https://github.com/noah-nuebling/mac-mouse-fix.git`.
  If it is missing, add it with `git remote add upstream https://github.com/noah-nuebling/mac-mouse-fix.git`.
  The scripts stop with exit 2 and print this command when the remote is missing.
- `last-synced` must hold a commit SHA. It was created once with the merge base:
  `git merge-base master upstream/master > tools/upstream-sync/last-synced`.
- Git must support `git merge-tree --write-tree --name-only --no-messages -z`.
  Tested with git 2.56. If the installed git lacks these options, `evaluate.py`
  stops with exit 2 and says the trial merge is not possible.

## sync_check.py (Inform)

```sh
python3 tools/upstream-sync/sync_check.py
```

What it does:

1. Fetches `upstream/master` into `refs/remotes/upstream/master`. No local branch or tag is touched.
2. Lists the upstream tags with `git ls-remote --tags`. No local tags are created.
3. Compares both with `last-synced`.

Output:

- `Last synced` and `Upstream master`: the commit lines (short hash and subject).
- `New commits on upstream/master`: commits in `last-synced..upstream/master`, oldest first.
- `New tags on upstream/master`: tags whose commit is on `upstream/master` and not yet included in `last-synced`.
- `Upstream tags not on upstream/master (ignored)`: tags that exist only on other upstream branches. For example, the 2.2.x releases come from the upstream `version-2` line, so they are never reported as new. Check those by hand if you need them.

Exit codes:

| Code | Meaning |
|------|---------|
| 0 | Nothing new since the last sync. |
| 1 | New commits and/or new tags. Run `evaluate.py` next. |
| 2 | Error: remote missing, network failure, or `last-synced` missing or invalid. |

## evaluate.py (Evaluate)

```sh
python3 tools/upstream-sync/evaluate.py                 # master, per-app-remaps, fork-setup
python3 tools/upstream-sync/evaluate.py --no-fetch      # use the already fetched upstream/master
python3 tools/upstream-sync/evaluate.py --max-commits 5 fork-setup
```

For each branch it fetches (unless `--no-fetch`) and reports:

- `tip` and `merge base` with `upstream/master`.
- `trial merge`: `clean`, or `CONFLICTS` with the conflicting file names. The merge is done with `git merge-tree --write-tree`, so the branch, the index and the working tree are not touched. Git may write new tree objects to the object database.
- `risk paths changed`: files changed upstream since the merge base that match the risk paths below, with their status letter (`M`, `A`, `D`). Review these even when the merge is clean.
- `upstream files changed` and `upstream commits since merge base`, with the commit log (limited by `--max-commits`, default 30).
- A summary table with the conflict, risk-file and commit counts.

Risk paths (directories end with `/`):

- `Helper/Core/Remap/`
- `Helper/Core/Modifiers/`
- `Helper/Core/Coordinate/SwitchMaster.swift`
- `Shared/Constants.h`
- `App/UI/Main/Tabs/ButtonTab/RemapTable/`

Exit codes:

| Code | Meaning |
|------|---------|
| 0 | Every checked branch merges cleanly with `upstream/master`. |
| 1 | At least one checked branch has conflicts. |
| 2 | Error: remote or branch missing, fetch failed, or git cannot run the trial merge. |

## Limits

- Only `master`, `per-app-remaps` and `fork-setup` are evaluated. `personal` and `beta` are not.
- The trial merge checks textual conflicts only. A clean merge can still break the build or the remap behavior, so build and test after a sync.
- Scheduling is not set up. There is no GitHub Actions workflow. Run the scripts by hand, or wire them into a local `launchd` job later.
