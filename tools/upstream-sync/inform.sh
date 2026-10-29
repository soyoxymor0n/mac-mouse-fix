#!/bin/sh
# Inform job: run sync_check.py and show a macOS notification when upstream has new commits or tags.
#
# launchd starts this once a day (see install_inform_job.sh). Output goes to the job log,
# ~/Library/Logs/mmf-upstream-check.log. Stores no secrets.
#
# Test hooks: MMF_UPSTREAM_PYTHON and MMF_UPSTREAM_OSASCRIPT override the interpreter and osascript.
set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PYTHON=${MMF_UPSTREAM_PYTHON:-python3}
OSASCRIPT=${MMF_UPSTREAM_OSASCRIPT:-/usr/bin/osascript}

OUT=$(mktemp "${TMPDIR:-/tmp}/mmf-upstream-check.XXXXXX") || exit 2
trap 'rm -f "$OUT"' EXIT

echo "$(date '+%Y-%m-%d %H:%M:%S') sync_check start"
"$PYTHON" "$SCRIPT_DIR/sync_check.py" > "$OUT" 2>&1
RC=$?
cat "$OUT"
echo "$(date '+%Y-%m-%d %H:%M:%S') sync_check exit $RC"

# Exit 1 means new commits and/or tags. Exit 0 means nothing new. Exit 2 is logged only.
if [ "$RC" -eq 1 ]; then
  COMMITS=$(sed -n 's/^New commits on upstream\/master: //p' "$OUT")
  TAGS=$(sed -n 's/^New tags on upstream\/master: //p' "$OUT")
  MSG="Upstream Mac Mouse Fix: ${COMMITS:-0} new commit(s), ${TAGS:-0} new tag(s). Run tools/upstream-sync/evaluate.py."
  "$OSASCRIPT" -e "display notification \"$MSG\" with title \"Mac Mouse Fix upstream\"" || echo "notification failed"
fi

exit "$RC"
