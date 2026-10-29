#!/bin/sh
# Install the daily Inform job for the upstream sync (launchd, label com.soyoxymor0n.mmf-upstream-check).
#
# Writes ~/Library/LaunchAgents/com.soyoxymor0n.mmf-upstream-check.plist with the absolute paths of
# the checkout this script runs from, then loads it into your user session. The job runs
# tools/upstream-sync/inform.sh every day at 09:00. It stores no secrets.
# Logs go to ~/Library/Logs/mmf-upstream-check.log.
#
# Usage:
#   sh tools/upstream-sync/install_inform_job.sh           install and load the job
#   sh tools/upstream-sync/install_inform_job.sh --print   print the plist, change nothing
#
# Remove it with tools/upstream-sync/uninstall_inform_job.sh.
set -eu

LABEL=com.soyoxymor0n.mmf-upstream-check
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)
TEMPLATE="$SCRIPT_DIR/$LABEL.plist.template"
WRAPPER="$SCRIPT_DIR/inform.sh"
LOG="$HOME/Library/Logs/mmf-upstream-check.log"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

# Render the template into the file given as $1. plutil escapes the XML for us.
render() {
  cp "$TEMPLATE" "$1"
  plutil -replace ProgramArguments.1 -string "$WRAPPER" "$1"
  plutil -replace WorkingDirectory -string "$REPO_ROOT" "$1"
  plutil -replace StandardOutPath -string "$LOG" "$1"
  plutil -replace StandardErrorPath -string "$LOG" "$1"
  plutil -lint "$1" > /dev/null
}

if [ "${1:-}" = "--print" ]; then
  TMP_PRINT=$(mktemp "${TMPDIR:-/tmp}/$LABEL.XXXXXX")
  render "$TMP_PRINT"
  cat "$TMP_PRINT"
  rm -f "$TMP_PRINT"
  exit 0
fi

mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
TMP_PLIST="$PLIST.tmp"
render "$TMP_PLIST"
chmod 644 "$TMP_PLIST"
mv -f "$TMP_PLIST" "$PLIST"

UID_NUM=$(id -u)
launchctl bootout "gui/$UID_NUM/$LABEL" 2> /dev/null || true
launchctl bootstrap "gui/$UID_NUM" "$PLIST"

echo "Installed $LABEL"
echo "  plist: $PLIST"
echo "  runs:  $WRAPPER every day at 09:00"
echo "  log:   $LOG"
echo "Check:       launchctl print gui/$UID_NUM/$LABEL | head -20"
echo "Run it now:  launchctl kickstart gui/$UID_NUM/$LABEL"
