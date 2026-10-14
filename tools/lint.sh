#!/bin/sh
# Reject Lua 5.1-only constructs and syntax-check every file with Lua 5.0's own
# compiler. luac -p also enforces the 5.0 limits later tools miss: no `#` or `%`
# operators, and at most 32 upvalues per function -- more and the client refuses
# to load the whole file.
set -e
status=0
for f in TaxTheFools/*.lua tests/*.lua; do
  if grep -nE 'string\.match|string\.gmatch|[^a-zA-Z_.]select\(|hooksecurefunc|strsplit|math\.huge|function *\( *self *, *event' "$f"; then
    echo "lint: 5.1-only construct in $f"
    status=1
  fi
  if ! "$LUAC" -p "$f"; then
    echo "lint: luac failed on $f"
    status=1
  fi
done
exit $status
