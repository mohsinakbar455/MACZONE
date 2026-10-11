#!/usr/bin/env bash
# Adapted from diagnosing-bugs/scripts/hitl-loop.template.sh.
# Human supplies the physical modifier drag; this script performs no UI actions.
set -euo pipefail
cd "$(dirname "$0")/.."
capture() {
  local target="$1" question="$2" answer
  printf '\n>>> %s\n' "$question"
  read -r -p '    > ' answer
  printf -v "$target" '%s' "$answer"
}
capture app_choice 'Which app failed? Enter premiere or aftereffects.'
case "$app_choice" in
  premiere) bundle='com.adobe.PremierePro.26' ;;
  aftereffects) bundle='com.adobe.AfterEffects.application' ;;
  *) printf 'BLOCKED: specify one of the two apps.\n'; exit 2 ;;
esac
capture target_zone 'Which layout and numbered zone are you testing? Do not include project names.'
capture failure 'Drag the outer app titlebar with Snap held and release over that zone. What happens: correct, wrong-frame, jump-back, no-snap, or wrong-window? Leave the result untouched for the geometry capture.'
bash scripts/probe-window-compatibility.sh "$bundle" --geometry
printf '\nAPP=%s\nTARGET=%s\nRESULT=%s\n' "$app_choice" "$target_zone" "$failure"
if [ "$failure" = correct ]; then
  printf 'PASS: this one operator-observed trial landed correctly; repeat to check intermittency.\n'
else
  printf 'FAIL: operator observed an incorrect landing; retain the geometry above.\n'
  exit 1
fi
