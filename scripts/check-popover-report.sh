#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ruby -rjson -e '
  r = JSON.parse(File.read(ARGV.fetch(0, "build/tests/popover-report.json")))
  c, s = r.fetch("content"), r.fetch("visibleScreen")
  top = c.fetch("y") + c.fetch("height")
  allowed_top = s.fetch("y") + s.fetch("height")
  inside = c["x"] >= s["x"] && c["x"] + c["width"] <= s["x"] + s["width"] && c["y"] >= s["y"] && top <= allowed_top + 1
  puts "Popup content top=#{top}; usable screen top=#{allowed_top}; fully on screen=#{inside}"
  abort "FAIL: menu-bar popup content is clipped off screen" unless inside
  puts "PASS: entire menu-bar popup fits below the menu bar"
' "$@"
