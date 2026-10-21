#!/usr/bin/env bash
# spec_hunt_bg.sh — run divergence checks in the background, in parallel.
#
# Each input is adjudicated in its own process (solc + Forge + Lean are all
# subprocess-isolated), so --jobs changes wall-clock only, never the verdict.
# Per-input JSON, stderr and a verdict file are kept for triage.
#
#   scripts/spec_hunt_bg.sh start probes/*.sol                    # files or dirs
#   scripts/spec_hunt_bg.sh start --jobs 4 --timeout 600 probes/  # tune
#   scripts/spec_hunt_bg.sh status [NAME]                        # progress + verdicts
#   scripts/spec_hunt_bg.sh tail NAME                            # follow the driver log
#   scripts/spec_hunt_bg.sh wait NAME                            # block until done
#   scripts/spec_hunt_bg.sh list                                 # all runs
#   scripts/spec_hunt_bg.sh stop NAME                            # kill a run
#
# Inputs:
#   *.sol  single-file submission with an ===ARENA-MANIFEST=== block
#   dir    directory-format submission (src/, test/, foundry.toml, claim.json)
#
# Speed knobs (see docs/SPEC_HUNT_WORKBENCH.md):
#   CONTEST_CACHE_DIR   opt-in solc-AST / importer / EVM-oracle disk cache
#   scripts/build_fast_runtime.sh   attest the native Lean runner
#   --jobs N            fan out independent probes (default 4)
#
# Exit codes: 0 = all inputs adjudicated (even if some found divergences),
# 1 = at least one input failed to adjudicate, 2 = usage error.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELF="$ROOT/scripts/$(basename "${BASH_SOURCE[0]}")"
# shellcheck source=scripts/spec_hunt_env.sh
. "$ROOT/scripts/spec_hunt_env.sh"

RUNS_DIR="${SPEC_HUNT_RUNS:-$ROOT/tmp/spec-hunt-runs}"

usage() {
  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

latest_run() {
  # Newest run directory by mtime; optional NAME filter.
  local filter="${1:-}"
  local dirs
  dirs=$(find "$RUNS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
         | grep -E "/${filter:-[^/]+}-[0-9]{8}-[0-9]{6}$" || true)
  [[ -n "$dirs" ]] || return 1
  ls -dt $dirs 2>/dev/null | head -1
}

resolve_run() {
  # Accept an explicit path, an exact run name, or a NAME prefix.
  local q="${1:-}"
  if [[ -z "$q" ]]; then
    latest_run "" && return 0
    echo "no runs under $RUNS_DIR" >&2
    return 1
  fi
  if [[ -d "$q" && -f "$q/pid" ]]; then printf '%s\n' "$q"; return 0; fi
  if [[ -d "$RUNS_DIR/$q" && -f "$RUNS_DIR/$q/pid" ]]; then
    printf '%s\n' "$RUNS_DIR/$q"; return 0
  fi
  latest_run "$q" && return 0
  echo "no matching run: $q" >&2
  return 1
}

cmd_start() {
  local jobs=4 timeout=400 name="run"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --jobs|-j) jobs="${2:?--jobs needs a value}"; shift 2 ;;
      --timeout|-t) timeout="${2:?--timeout needs a value}"; shift 2 ;;
      --name|-n) name="${2:?--name needs a value}"; shift 2 ;;
      --) shift; break ;;
      -*) echo "unknown flag: $1" >&2; usage ;;
      *) break ;;
    esac
  done
  [[ $# -gt 0 ]] || usage

  local inputs=()
  local p
  for p in "$@"; do
    [[ -e "$p" ]] || { echo "input not found: $p" >&2; return 2; }
    case "$p" in
      *.sol) [[ -d "$p" ]] || { inputs+=("$p"); continue; } ;;
    esac
    [[ -d "$p" ]] || { echo "input is neither a .sol file nor a directory: $p" >&2; return 2; }
    inputs+=("$p")
  done
  [[ ${#inputs[@]} -gt 0 ]] || usage

  local stamp run_dir
  stamp=$(date +%Y%m%d-%H%M%S)
  run_dir="$RUNS_DIR/$name-$stamp"
  mkdir -p "$run_dir/logs"
  printf '%s\n' "${inputs[@]}" > "$run_dir/inputs.txt"

  # Detach: caffeinate keeps the machine awake for long builds/adjudications.
  nohup caffeinate -i bash "$SELF" _drive "$run_dir" "$jobs" "$timeout" "${inputs[@]}" \
    > "$run_dir/driver.log" 2>&1 &
  echo $! > "$run_dir/pid"

  echo "started  $run_dir"
  echo "inputs   ${#inputs[@]}   jobs=$jobs timeout=${timeout}s"
  echo "pid      $(cat "$run_dir/pid")"
  echo "follow   scripts/spec_hunt_bg.sh tail $(basename "$run_dir")"
}

cmd_drive() {
  local run_dir="$1" jobs="$2" timeout="$3"; shift 3
  cd "$ROOT"   # so `python3 -m contest...` resolves from any caller cwd
  echo "spec-hunt run: $(basename "$run_dir")"
  echo "jobs=$jobs timeout=${timeout}s cache=${CONTEST_CACHE_DIR:-<disabled>}"
  echo "solc=$SOLC"
  echo "started $(date)"
  printf '%s\0' "$@" \
    | xargs -0 -n 1 -P "$jobs" bash "$SELF" _one "$run_dir" "$timeout"
  echo "finished $(date)"
}

cmd_one() {
  local run_dir="$1" timeout="$2" input="$3"
  local tag
  tag="$(basename "$input")-$(printf '%s' "$input" | shasum -a 1 | cut -c1-8)"
  local out="$run_dir/logs/$tag.json" err="$run_dir/logs/$tag.err"
  local verdict="$run_dir/logs/$tag.verdict"
  local rc=0

  if [[ -d "$input" ]]; then
    python3 -m contest.adjudicate "$input" --timeout "$timeout" --json \
      > "$out" 2> "$err" || rc=$?
  else
    python3 -m contest.manifest "$input" --timeout "$timeout" --json \
      > "$out" 2> "$err" || rc=$?
  fi

  # rc 1 is the CLI's "adjudicated, not a qualifying divergence" signal.
  if [[ -s "$out" ]] && jq -e '.verdict' "$out" >/dev/null 2>&1; then
    jq -r '.verdict' "$out" > "$verdict"
    printf '%-28s %-16s %s\n' "$(jq -r '.verdict' "$out")" \
      "$(jq -r '.lane // "-"' "$out")" "$input" >> "$run_dir/summary.tsv"
  else
    printf 'ERROR(%s)' "$rc" > "$verdict"
    printf '%-28s %-16s %s\n' "ERROR($rc)" "-" "$input" >> "$run_dir/summary.tsv"
  fi
  return 0
}

cmd_status() {
  local run_dir; run_dir=$(resolve_run "${1:-}") || return 1
  local pid alive="no"
  pid=$(cat "$run_dir/pid" 2>/dev/null || echo "")
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then alive="yes"; fi
  local total done
  total=$(wc -l < "$run_dir/inputs.txt" | tr -d ' ')
  done=$(find "$run_dir/logs" -name '*.verdict' | wc -l | tr -d ' ')

  echo "run      $(basename "$run_dir")"
  echo "state    $([[ $alive == yes ]] && echo RUNNING || echo FINISHED)  ($done/$total)"
  if [[ -f "$run_dir/summary.tsv" ]]; then
    echo "--- verdicts ---"
    sort "$run_dir/summary.tsv" | awk '{c[$1]++} END {for (v in c) printf "%-28s %d\n", v, c[v]}' | sort
    echo "--- inputs ---"
    sort "$run_dir/summary.tsv"
  else
    echo "(no completed inputs yet — see driver.log)"
  fi
}

cmd_tail() {
  local run_dir; run_dir=$(resolve_run "${1:-}") || return 1
  echo "== driver: $run_dir/driver.log  (Ctrl-C detaches; the run keeps going)"
  tail -n "${2:-40}" -f "$run_dir/driver.log"
}

cmd_wait() {
  local run_dir; run_dir=$(resolve_run "${1:-}") || return 1
  local pid; pid=$(cat "$run_dir/pid")
  while kill -0 "$pid" 2>/dev/null; do sleep 5; done
  cmd_status "$run_dir"
}

cmd_stop() {
  local run_dir; run_dir=$(resolve_run "${1:-}") || return 1
  local pid; pid=$(cat "$run_dir/pid")
  if kill -0 "$pid" 2>/dev/null; then
    kill -TERM "$pid" 2>/dev/null || true
    echo "stopped $(basename "$run_dir") (pid $pid)"
  else
    echo "already finished: $(basename "$run_dir")"
  fi
}

cmd_list() {
  [[ -d "$RUNS_DIR" ]] || { echo "no runs yet"; return 0; }
  for d in $(ls -dt "$RUNS_DIR"/*/ 2>/dev/null); do
    d="${d%/}"; [[ -f "$d/pid" ]] || continue
    local pid state total done
    pid=$(cat "$d/pid")
    state="FINISHED"; kill -0 "$pid" 2>/dev/null && state="RUNNING"
    total=$(wc -l < "$d/inputs.txt" | tr -d ' ')
    done=$(find "$d/logs" -name '*.verdict' 2>/dev/null | wc -l | tr -d ' ')
    printf '%-9s %-34s %s/%s\n' "$state" "$(basename "$d")" "$done" "$total"
  done
}

case "${1:-}" in
  start)  shift; cmd_start "$@" ;;
  _drive) shift; cmd_drive "$@" ;;
  _one)   shift; cmd_one "$@" ;;
  status) shift; cmd_status "$@" ;;
  tail)   shift; cmd_tail "$@" ;;
  wait)   shift; cmd_wait "$@" ;;
  stop)   shift; cmd_stop "$@" ;;
  list|ls) cmd_list ;;
  -h|--help|"") usage ;;
  *) echo "unknown command: $1" >&2; usage ;;
esac
