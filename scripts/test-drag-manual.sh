#!/usr/bin/env bash
# Adapted from the diagnosing-bugs skill's human-in-the-loop template.
# Never writes settings or manipulates windows; the operator supplies evidence.
set -euo pipefail

capture() {
  local target="$1" question="$2" answer
  printf '\n>>> %s\n' "$question"
  read -r -p '    > ' answer
  printf -v "$target" '%s' "$answer"
}

capture maczone_ready 'Does this exact final MACZONE build say Accessibility connected, with window management enabled? (y/n)'
if [ "$maczone_ready" != y ]; then
  printf 'BLOCKED: This process needs its Accessibility grant before drag testing.\n'
  exit 2
fi
printf '\nUse an empty disposable window, not a document being edited. Do not rebuild MACZONE during this check.\n'
printf 'Use the configured Snap key (default Shift) and Span key (default Option).\n'
capture maczone_reveal 'Start moving the window by its titlebar, then hold Snap. Do zones appear and highlight beneath the pointer? (y/n)'
capture maczone_drop 'Release the mouse while holding Snap. Does the window land in the highlighted zone? (y/n)'
capture maczone_cancel 'Drag again with Snap, then release Snap before releasing the mouse. Does the overlay disappear without applying the old zone? (y/n)'
capture maczone_span 'While dragging with Snap, add Span and cross several zones, then move back and release Span. Does the rectangular selection expand, shrink, and return to one zone? (y/n)'
capture maczone_inactive 'With another app focused, begin dragging the disposable inactive window and hold Snap. Does that window reveal zones and snap correctly? (y/n)'
capture maczone_observation 'If anything failed, describe exactly what you saw (or none). Do not include window titles or private content.'
printf '\nREVEAL=%s\nDROP=%s\nCANCEL=%s\nSPAN=%s\nINACTIVE=%s\nOBSERVATION=%s\n' "$maczone_reveal" "$maczone_drop" "$maczone_cancel" "$maczone_span" "$maczone_inactive" "$maczone_observation"
if [ "$maczone_reveal" = y ] && [ "$maczone_drop" = y ] && [ "$maczone_cancel" = y ] && [ "$maczone_span" = y ] && [ "$maczone_inactive" = y ]; then
  printf 'PASS: operator confirmed these five live drag checks.\n'
else
  printf 'FAIL: at least one live drag check needs investigation.\n'
  exit 1
fi
