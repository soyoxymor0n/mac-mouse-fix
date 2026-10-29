# Upstream sync: Inform, Evaluate and Apply

Tools for issue #1 of this fork: keep informed about upstream Mac Mouse Fix
(`noah-nuebling/mac-mouse-fix`), judge the impact of its changes, and apply them
in one step.

- `sync_check.py` (Inform): reports new upstream commits and tags since the last sync.
- `evaluate.py` (Evaluate): trial-merges `upstream/master` into the fork branches and reports conflicts, risk-path changes and the upstream commit log. It changes nothing.
- `apply.py` (Apply): merges, checks, builds and pushes the sync in one command. It refuses or stops when anything fails, and pushes nothing in that case.
- `inform.sh`, `install_inform_job.sh`, `uninstall_inform_job.sh`, `com.soyoxymor0n.mmf-upstream-check.plist.template`: the daily local launchd job that runs `sync_check.py` and shows a macOS notification.
- `last-synced`: the upstream commit the fork has merged up to. Only a confirmed sync changes it.

All scripts use only the Python standard library. Run them from the repository
root. `sync_check.py` and `evaluate.py` never change a branch, the index, a working
tree, or `last-synced`. `apply.py` changes the fork branches on `origin` and
writes `last-synced`, as described below.

## Setup

- Remote: `upstream` must point to `https://github.com/noah-nuebling/mac-mouse-fix.git`.
  If it is missing, add it with `git remote add upstream https://github.com/noah-nuebling/mac-mouse-fix.git`.
  The scripts stop with exit 2 and print this command when the remote is missing.
- Remote: `origin` must be your fork (`soyoxymor0n/mac-mouse-fix-ng`). `apply.py` pushes to it.
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

## apply.py (Apply)

```sh
python3 tools/upstream-sync/apply.py --dry-run   # merge, check and build; push nothing
python3 tools/upstream-sync/apply.py             # the sync
```

`--dry-run` does everything except the pushes. It moves no branch and does not
write `last-synced`. It prints what would be pushed. Use it first.

What it does, in order. Nothing is pushed until every step has passed.

1. Refuses (exit 2) if the working tree has tracked changes, if `upstream` or `origin` is missing, if `master` is not an ancestor of `upstream/master`, or if one of the fork branches is checked out in any worktree. Nothing changes.
2. Fetches `upstream/master` and the fork branches from `origin`. Only remote-tracking refs change.
3. Fast-forwards `master` to `upstream/master` (ff-only).
4. Merges `master` into `per-app-remaps` and `fork-setup`. Then merges the new `per-app-remaps`, `fork-setup` and `master` into `personal`. At the first conflict it runs `git merge --abort`, prints the conflicting files, and exits 1.
5. Refuses (exit 2) if `origin` has a commit that a new branch tip does not contain, so every push is a fast-forward.
6. Grep checks (exit 1 on failure):
   - `SUFeedURL` is absent from `App/SupportFiles/Info.plist` on `fork-setup` and `personal`. `master` and `per-app-remaps` keep upstream's key on purpose.
   - `com.nuebling` is absent from every file that differs from `upstream/master` on `fork-setup` and `personal`. The legacy launchd path `com.nuebling.mousefix.helper.plist` in `Shared/HelperServices/HelperServices.m` is allowed on purpose.
7. Builds the `App` and `Helper` schemes (`xcodebuild -configuration Debug CODE_SIGNING_ALLOWED=NO`) at each tip that is pushed, and at `personal`. Derived data goes to a temp folder outside the repo. On a build failure it exits 1, keeps the full log and prints its path.
8. Pushes `master`, `per-app-remaps`, `fork-setup` and `personal` to `origin` (fast-forward only, no force). After each push the local branch moves to the same commit. Then it writes `last-synced` and prints what changed.

Merges and builds run in a temporary worktree under the system temp directory.
The temp worktree is removed at the end, also on failure. Your checkout keeps its HEAD,
its branch and its files. The one file it writes is `last-synced`, which is not committed.
Commit it on your own branch. The printed commands show how. Until that commit exists,
the next run refuses because the tree is not clean.

Exit codes:

| Code | Meaning |
|------|---------|
| 0 | Synced, already synced, or the dry run passed. |
| 1 | Stopped before pushing: merge conflict, failed grep check, or failed build. |
| 2 | Refused or error, for example a dirty tree or a missing remote. A failed push also exits 2. Branches pushed before it stay on `origin`, so run apply again after fixing the cause. |

Test hook: the environment variable `MMF_UPSTREAM_SYNC_BUILD_CMD` replaces the
`xcodebuild` call with a shell command. The scripts used it for tests with a
throwaway fixture repo.

After a sync, build and test the app. The merge check is textual only, and a clean
merge can still break the build or the remap behavior.

## Inform job (launchd)

A local launchd job, not a GitHub Action. It runs `inform.sh` every day at 09:00.
`inform.sh` runs `sync_check.py`. When that reports new commits or tags, it shows a
macOS notification. Errors are written to the log only.

Install from the checkout the job should use (writes the plist with this checkout's absolute paths and loads it):

```sh
sh tools/upstream-sync/install_inform_job.sh
```

Print the plist without installing anything:

```sh
sh tools/upstream-sync/install_inform_job.sh --print
```

Uninstall (unloads the job and deletes its plist; the log is kept):

```sh
sh tools/upstream-sync/uninstall_inform_job.sh
```

Other commands:

```sh
launchctl print gui/$(id -u)/com.soyoxymor0n.mmf-upstream-check | head -20   # status
launchctl kickstart gui/$(id -u)/com.soyoxymor0n.mmf-upstream-check          # run now
```

Files: the plist is `~/Library/LaunchAgents/com.soyoxymor0n.mmf-upstream-check.plist`
and the log is `~/Library/Logs/mmf-upstream-check.log`. The job stores no secrets.
If the checkout moves, uninstall and install again. If no notification appears,
check System Settings, Notifications, for Script Editor.

## Limits

- The Inform job and `evaluate.py` cover `master`, `per-app-remaps` and `fork-setup`. `apply.py` also updates `personal`. `beta` is never touched.
- The trial merge checks textual conflicts only. `apply.py` builds the App and Helper schemes, but it does not run the tests or the app.
- There is no GitHub Actions workflow for the sync.
