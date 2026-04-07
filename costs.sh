#!/usr/bin/env bash
# Cost report for bot cycles.
# Usage:
#   ./costs.sh              # Summary of all recorded cycles
#   ./costs.sh today        # Today only
#   ./costs.sh 2026-03-31   # Specific date
#   ./costs.sh week         # Last 7 days
#   ./costs.sh backfill     # Backfill costs.jsonl from bot.log

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COSTS_FILE="$SCRIPT_DIR/data/costs.jsonl"
BOT_LOG="$SCRIPT_DIR/data/bot.log"

if [ "${1:-}" = "backfill" ]; then
  echo "Backfilling costs.jsonl from bot.log..."
  grep '"type":"result"' "$BOT_LOG" 2>/dev/null | python3 -c "
import json, sys
from datetime import datetime, timezone
for line in sys.stdin:
    r = json.loads(line.strip())
    u = r.get('usage', {})
    m = r.get('modelUsage', {})
    entry = {
        'timestamp': datetime.now(timezone.utc).isoformat(),
        'label': '',
        'session_id': r.get('session_id', ''),
        'num_turns': r.get('num_turns', 0),
        'duration_ms': r.get('duration_ms', 0),
        'cost_usd': r.get('total_cost_usd', 0),
        'input_tokens': u.get('input_tokens', 0),
        'output_tokens': u.get('output_tokens', 0),
        'cache_read_tokens': u.get('cache_read_input_tokens', 0),
        'cache_write_tokens': u.get('cache_creation_input_tokens', 0),
        'model': next(iter(m.keys()), ''),
        'is_error': r.get('is_error', False),
        'no_work': 'NO_WORK_FOUND' in r.get('result', ''),
    }
    print(json.dumps(entry))
" >> "$COSTS_FILE"
  echo "Done. $(wc -l < "$COSTS_FILE") total entries."
  exit 0
fi

if [ ! -f "$COSTS_FILE" ]; then
  echo "No costs.jsonl found. Run './costs.sh backfill' to populate from bot.log."
  exit 1
fi

FILTER="${1:-all}"

COSTS_FILE="$COSTS_FILE" python3 - "$FILTER" << 'PYEOF'
import json, os, sys
from datetime import datetime, timedelta, timezone

filter_arg = sys.argv[1]
today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
costs_file = os.environ["COSTS_FILE"]

entries = []
with open(costs_file) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            entries.append(json.loads(line))
        except json.JSONDecodeError:
            continue

if filter_arg == "today":
    entries = [e for e in entries if e["timestamp"][:10] == today]
elif filter_arg == "week":
    week_ago = (datetime.now(timezone.utc) - timedelta(days=7)).strftime("%Y-%m-%d")
    entries = [e for e in entries if e["timestamp"][:10] >= week_ago]
elif filter_arg != "all":
    entries = [e for e in entries if e["timestamp"][:10] == filter_arg]

if not entries:
    print("No cycles found for the given filter.")
    sys.exit(0)

print(f"{'#':>3}  {'Date':>10}  {'Turns':>5}  {'Duration':>8}  {'Output':>8}  {'Cost':>8}  {'Label'}")
print("-" * 75)

total_cost = 0
total_turns = 0
total_dur = 0
total_out = 0
by_date = {}

for i, e in enumerate(entries, 1):
    cost = e.get("cost_usd", 0)
    turns = e.get("num_turns", 0)
    dur = e.get("duration_ms", 0) / 1000
    out = e.get("output_tokens", 0)
    date = e["timestamp"][:10]
    label = e.get("label", "")
    no_work = " (idle)" if e.get("no_work") else ""

    total_cost += cost
    total_turns += turns
    total_dur += dur
    total_out += out
    by_date.setdefault(date, {"cost": 0, "cycles": 0})
    by_date[date]["cost"] += cost
    by_date[date]["cycles"] += 1

    print(f"{i:>3}  {date}  {turns:>5}  {dur:>7.0f}s  {out:>8,}  ${cost:>7.2f}  {label}{no_work}")

print("-" * 75)
print(f"{'':>3}  {'TOTAL':>10}  {total_turns:>5}  {total_dur:>7.0f}s  {total_out:>8,}  ${total_cost:>7.2f}")
print()

if len(by_date) > 1:
    print("Daily summary:")
    for date in sorted(by_date.keys()):
        d = by_date[date]
        print(f"  {date}  {d['cycles']:>3} cycles  ${d['cost']:>7.2f}")
    print()

print(f"Cycles: {len(entries)}  |  Cost: ${total_cost:.2f}  |  Time: {total_dur/60:.0f}min  |  Avg: ${total_cost/len(entries):.2f}/cycle")
PYEOF
