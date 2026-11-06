#!/usr/bin/env bash
# One-command check before a deploy or release. Must end with "ALL PASSED".
#   1. Lua syntax of every addon file: luajit -bl rejects Lua 5.3+ syntax but accepts goto and
#      labels, which the client's Lua 5.1 does not, so those are grepped for as well
#   2. the TOC lists exactly the Lua files on disk
#   3. every global, C_ function, Settings and ChatFrameUtil field, Enum path, event and frame
#      method the addon uses exists in the Forever client's UI source, API docs or global strings
#      (tests/audit_globals.py; skipped, and said so in the last line, until
#      `python3 tests/audit_globals.py --fetch` has downloaded them into .cache/)
#   4. the LuaJIT suite: the whole addon under a fake client
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
skipped=""
say() { printf '%s\n' "$*"; }

say "== Lua syntax"
for file in GuildLoginMute/*.lua; do
  if luajit -bl "$file" >/dev/null; then say "  ok    $file"; else say "  FAIL  $file"; fail=1; fi
done
if grep -nE '\bgoto\b|::[A-Za-z_][A-Za-z0-9_]*::' GuildLoginMute/*.lua; then
  say "  FAIL  goto or a label: Lua 5.2 syntax the client does not have"; fail=1
else
  say "  ok    no goto or labels"
fi

say "== TOC file"
listed=$(grep -v '^##' GuildLoginMute/GuildLoginMute.toc | grep -v '^#' | sed '/^$/d' | sort)
present=$(cd GuildLoginMute && ls *.lua | sort)
if [ "$listed" = "$present" ]; then
  say "  ok    TOC lists exactly the Lua files on disk"
else
  say "  FAIL  TOC file list and GuildLoginMute/*.lua differ"; fail=1
fi

say "== every API the addon uses exists in the Forever client"
python3 tests/audit_globals.py
case $? in
  0) ;;
  2) skipped=" (API audit skipped)" ;;
  *) fail=1 ;;
esac

say "== tests/test_addon.lua"
luajit tests/test_addon.lua || fail=1

if [ "$fail" -eq 0 ]; then say "ALL PASSED$skipped"; else say "FAILED"; exit 1; fi
