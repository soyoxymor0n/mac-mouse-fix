#!/bin/sh
# Remove the Inform job installed by install_inform_job.sh (label com.soyoxymor0n.mmf-upstream-check).
# Unloads the job and deletes its plist. The log is kept.
set -eu

LABEL=com.soyoxymor0n.mmf-upstream-check
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
UID_NUM=$(id -u)

launchctl bootout "gui/$UID_NUM/$LABEL" 2> /dev/null || true
rm -f "$PLIST"

echo "Removed $LABEL (plist: $PLIST)."
echo "The log is kept at $HOME/Library/Logs/mmf-upstream-check.log."
