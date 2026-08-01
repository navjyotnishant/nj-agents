#!/usr/bin/env bash
#
# test-nj-run.sh — behavioural checks for the run harness (bin/nj-run).
#
# Author: Navjyot Nishant
# Created: 2026-08-01
# Last updated: 2026-08-01
# Description: Asserts §T10 cost, §T11 determinism/quarantine, §T12 log/scrub.
#
# No LLM, no network, free — safe for CI. Run: tests/test-nj-run.sh

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NJ="$HERE/../bin/nj-run"
pass=0; fail=0

ok()   { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  FAIL %s\n' "$1"; printf '       %s\n' "${2:-}"; fail=$((fail + 1)); }
check(){ [ "$2" = "$3" ] && ok "$1" || bad "$1" "expected '$3', got '$2'"; }

echo "Testing bin/nj-run ..."

# --- §T11 determinism -------------------------------------------------------
# The point of the clause: the same inputs must always produce the same verdict.
# Recording dimensions in a DIFFERENT order must not change the aggregate, or a
# gate's result depends on which subagent happened to finish first.
run_verdicts() {
  eval "$("$NJ" init --commit deadbeef)" >/dev/null
  for pair in "$@"; do
    "$NJ" verdict --dimension "${pair%%:*}" --value "${pair##*:}" >/dev/null 2>&1
  done
  "$NJ" aggregate
  rm -rf "$NJ_RUN_DIR"
}
a="$(run_verdicts specs:PASS lint:WARN authz:PASS)"
b="$(run_verdicts authz:PASS specs:PASS lint:WARN)"
c="$(run_verdicts lint:WARN authz:PASS specs:PASS)"
check "aggregation is order-independent (§T11)" "$a|$b|$c" "WARN|WARN|WARN"

# The check above cannot fail on its own, and that is worth stating: the manifest
# writer already stores keys sorted, so `aggregate` sees sorted input no matter
# what order the dimensions arrived in. Removing the sort from the reduce leaves
# it green.
#
# So assert the property directly, against a manifest written OUT of order. This
# is the check that actually bites if someone "simplifies" sorted(v) away.
eval "$("$NJ" init --commit deadbeef)" >/dev/null
python3 - "$NJ_RUN_DIR/manifest.json" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as fh: m = json.load(fh)
# Insertion order deliberately not alphabetical; json.dump without sort_keys
# preserves it, reproducing what a completion-order-dependent writer would emit.
m["verdicts"] = {"zeta": "PASS", "alpha": "WARN", "mid": "PASS"}
with open(path, "w") as fh: json.dump(m, fh, indent=2)
PY
unsorted_result="$("$NJ" aggregate)"
python3 - "$NJ_RUN_DIR/manifest.json" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as fh: m = json.load(fh)
m["verdicts"] = {"alpha": "WARN", "mid": "PASS", "zeta": "PASS"}
with open(path, "w") as fh: json.dump(m, fh, indent=2)
PY
sorted_result="$("$NJ" aggregate)"
check "same verdict set, either key order, same result (§T11)" \
  "$unsorted_result" "$sorted_result"
rm -rf "$NJ_RUN_DIR"

# Severity actually dominates — otherwise the check above passes trivially.
check "BLOCK dominates WARN"  "$(run_verdicts a:WARN b:BLOCK)" "BLOCK"
check "WARN dominates PASS"   "$(run_verdicts a:PASS b:WARN)"  "WARN"

# --- §U empty input ---------------------------------------------------------
check "no dimensions is a PASS (§U)" "$(run_verdicts)" "PASS"
check "all-SKIP is a PASS (§U)"      "$(run_verdicts a:SKIP b:SKIP)" "PASS"

# --- §T11 quarantine --------------------------------------------------------
# "Four of five shards passing is not a pass." A failed subagent must not be
# aggregated away by the surviving dimensions reporting PASS.
eval "$("$NJ" init --commit deadbeef)" >/dev/null
id="$("$NJ" spawn sharded-runner)"
"$NJ" join "$id" --status failed >/dev/null 2>&1
"$NJ" verdict --dimension specs --value PASS >/dev/null 2>&1
check "a failed subagent blocks, never silently shrinks (§T11)" "$("$NJ" aggregate)" "BLOCK"
rm -rf "$NJ_RUN_DIR"

# --- §T10 cost accumulates --------------------------------------------------
eval "$("$NJ" init --commit deadbeef)" >/dev/null
"$NJ" cost --skill /e2e-run --tokens 100 --calls 1 >/dev/null 2>&1
"$NJ" cost --skill /e2e-run --tokens 250 --calls 2 >/dev/null 2>&1
total="$("$NJ" report | awk '/^  cost/ {print $2}')"
check "cost accumulates across calls (§T10)" "$total" "350"
rm -rf "$NJ_RUN_DIR"

# --- §T10 budget WARN -------------------------------------------------------
eval "$("$NJ" init --commit deadbeef)" >/dev/null
out="$(NJ_RUN_BUDGET_TOKENS=100 "$NJ" cost --skill /x --tokens 500 --calls 1 2>&1)"
case "$out" in
  *"budget exceeded"*) ok "exceeding a budget reports WARN with the breakdown (§T10)" ;;
  *) bad "exceeding a budget reports WARN" "no warning in: $out" ;;
esac
rm -rf "$NJ_RUN_DIR"

# --- §T12 / §T4 scrub -------------------------------------------------------
# The log is PUBLISHED TEXT. A token in a heartbeat reaches a report with no
# artifact ever moving — that is the leak §T4 describes, and the reason the
# scrub applies to the log even though the export prohibition does not.
eval "$("$NJ" init --commit deadbeef)" >/dev/null
"$NJ" heartbeat "GET /api/orders?token=super_secret_value_123" >/dev/null 2>&1
"$NJ" heartbeat "calling with sk-abcdef1234567890 key" >/dev/null 2>&1
log="$(cat "$NJ_RUN_DIR/run.jsonl")"
case "$log" in
  *super_secret_value_123*) bad "query-param token is masked in the log (§T4)" "leaked" ;;
  *) ok "query-param token is masked in the log (§T4)" ;;
esac
case "$log" in
  *sk-abcdef1234567890*) bad "vendor key is masked in the log (§T4)" "leaked" ;;
  *) ok "vendor key is masked in the log (§T4)" ;;
esac
# Mask, don't delete: the reader must still see a token WAS present.
case "$log" in
  *'***'*) ok "masked rather than deleted — the signal survives" ;;
  *) bad "masked rather than deleted" "no mask marker in log" ;;
esac
rm -rf "$NJ_RUN_DIR"

# --- §T12 structured log ----------------------------------------------------
eval "$("$NJ" init --commit deadbeef)" >/dev/null
"$NJ" phase start build >/dev/null 2>&1
"$NJ" phase end build >/dev/null 2>&1
lines="$(wc -l < "$NJ_RUN_DIR/run.jsonl" | tr -d ' ')"
[ "$lines" -ge 3 ] && ok "log records run_start and phase transitions (§T12)" \
                    || bad "log records phase transitions" "only $lines lines"
# Append-only JSONL: every line must parse alone. A pretty-printed array would
# not survive two concurrent writers.
if python3 -c '
import json, sys
for line in open(sys.argv[1]):
    if line.strip(): json.loads(line)
' "$NJ_RUN_DIR/run.jsonl" 2>/dev/null; then
  ok "every log line is independently valid JSON (§T12)"
else
  bad "every log line is valid JSON" "a line failed to parse"
fi
rm -rf "$NJ_RUN_DIR"

# --- §T4 manifest lives outside the repo ------------------------------------
eval "$("$NJ" init --commit deadbeef)" >/dev/null
repo_root="$(cd "$HERE/.." && pwd)"
case "$NJ_RUN_DIR" in
  "$repo_root"*) bad "run dir is outside the repo tree (§T4)" "inside: $NJ_RUN_DIR" ;;
  *) ok "run dir is outside the repo tree (§T4)" ;;
esac
rm -rf "$NJ_RUN_DIR"

# --- CONVENTIONS.md §5 exit codes -------------------------------------------
# A harness error must never read as PASS.
eval "$("$NJ" init --commit deadbeef)" >/dev/null
"$NJ" verdict --dimension a --value BLOCK >/dev/null 2>&1
"$NJ" finish >/dev/null 2>&1; rc=$?
check "BLOCK exits 1 (§5)" "$rc" "1"
rm -rf "$NJ_RUN_DIR"

eval "$("$NJ" init --commit deadbeef)" >/dev/null
"$NJ" verdict --dimension a --value WARN >/dev/null 2>&1
"$NJ" finish >/dev/null 2>&1; rc=$?
check "WARN exits 0 (§5)" "$rc" "0"
rm -rf "$NJ_RUN_DIR"

# Calling without a run must fail loudly, not invent a second one — two
# half-manifests read as one complete run, which is worse than none.
( unset NJ_RUN_DIR; "$NJ" report >/dev/null 2>&1 ); rc=$?
check "no active run is a harness error, not a silent new run" "$rc" "2"

echo
echo "$pass passed, $fail failed."
[ "$fail" -eq 0 ]
