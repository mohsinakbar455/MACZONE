#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ruby -rjson -e '
  report = JSON.parse(File.read("build/tests/launch-report.json"))
  visible = report.fetch("visibleWorkspaceCount")
  accessory = report.fetch("activationPolicy") == 1
  puts "Launch: #{visible} visible workspace(s); accessory=#{accessory}"
  abort "FAIL: launch must never show a workspace or Dock icon" unless visible == 0 && accessory
  checks = report.fetch("controllerChecks")
  failed = checks.select { |_, passed| !passed }.keys
  abort "FAIL: #{failed.join(", ")}" unless failed.empty? && checks.length == 8
  previews = report.fetch("layoutPreviewChecks")
  abort "FAIL: layout preview timing #{previews}" unless previews.length == 7 && previews.values.all?
  puts "PASS: #{previews.length}/#{previews.length} layout shortcut and two-second preview checks"
  puts "PASS: quiet launch and #{checks.length}/#{checks.length} unified-window lifecycle checks"
'
