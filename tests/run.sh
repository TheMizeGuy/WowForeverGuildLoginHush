#!/usr/bin/env bash
# One-command check before a deploy or release. Must end with "ALL PASSED".
#   1. Lua syntax of every addon file (the client runs Lua 5.1; luajit -bl rejects 5.2+ syntax)
#   2. the TOC lists exactly the Lua files on disk
#   3. every global, C_ function, Enum path, event and frame method the addon uses exists in the
#      Forever client's UI source, API docs or global strings (tests/audit_globals.py; skipped until
#      `python3 tests/audit_globals.py --fetch` has downloaded them into .cache/)
#   4. the LuaJIT suite: the whole addon under a fake client
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
say() { printf '%s\n' "$*"; }

say "== Lua syntax"
for file in GuildLoginMute/*.lua; do
  if luajit -bl "$file" >/dev/null; then say "  ok    $file"; else say "  FAIL  $file"; fail=1; fi
done

say "== TOC file"
listed=$(grep -v '^##' GuildLoginMute/GuildLoginMute.toc | grep -v '^#' | sed '/^$/d' | sort)
present=$(cd GuildLoginMute && ls *.lua | sort)
if [ "$listed" = "$present" ]; then
  say "  ok    TOC lists exactly the Lua files on disk"
else
  say "  FAIL  TOC file list and GuildLoginMute/*.lua differ"; fail=1
fi

say "== every API the addon uses exists in the Forever client"
python3 tests/audit_globals.py || fail=1

say "== tests/test_addon.lua"
luajit tests/test_addon.lua || fail=1

if [ "$fail" -eq 0 ]; then say "ALL PASSED"; else say "FAILED"; exit 1; fi
