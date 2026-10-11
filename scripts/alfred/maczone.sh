#!/bin/zsh
set -eu

case "${1:-cycle}" in
  cycle) command_url='maczone://cycle' ;;
  [1-6]) command_url="maczone://layout/$1" ;;
  settings) command_url='maczone://settings' ;;
  *) print -u2 'Use: maczone.sh [cycle | 1–6 | settings]'; exit 2 ;;
esac

if [[ ! -d /Applications/MACZONE.app ]]; then
  print -u2 'Install MACZONE in /Applications first.'
  exit 1
fi

# LaunchServices starts MACZONE if needed; -g preserves the focused app so
# MACZONE chooses its display. No simulated key press or GUI scripting.
exec /usr/bin/open -g -a /Applications/MACZONE.app "$command_url"
