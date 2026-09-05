#!/bin/bash
# Double-click launcher for macOS. Keep the Terminal window open while you
# work; closing it stops the app.
cd "$(dirname "$0")" || exit 1
if ! command -v Rscript >/dev/null 2>&1; then
  for candidate in /usr/local/bin /opt/homebrew/bin /Library/Frameworks/R.framework/Resources/bin; do
    if [ -x "$candidate/Rscript" ]; then PATH="$candidate:$PATH"; break; fi
  done
fi
if ! command -v Rscript >/dev/null 2>&1; then
  echo "Could not find R. Install R first (see README.md), then run this file again."
  read -r -p "Press Enter to close. "
  exit 1
fi
echo "Starting omicsDesk. Keep this window open while you work; close it to stop."
Rscript START.R
