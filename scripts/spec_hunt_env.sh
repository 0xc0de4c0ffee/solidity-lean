#!/usr/bin/env bash
# spec_hunt_env.sh — pin the local Spec Hunt toolchain (source this file).
#
#   . scripts/spec_hunt_env.sh          # export PATH/SOLC/FORGE/LAKE/caches
#   scripts/spec_hunt_env.sh --check    # print resolved versions and verify pins
#
# The repo pins three tools that MUST agree, or verdicts are silently wrong:
#   * Lean      — `lean-toolchain` (leanprover/lean4:v4.28.0), installed by elan
#   * solc      — 0.8.35 exactly (the contest reference compiler)
#   * Foundry   — forge/anvil (EVM side); any recent stable release
#
# Everything is overridable by exporting the variable first, e.g.
#   SOLC=/abs/solc-0.8.35 LAKE=/abs/lake . scripts/spec_hunt_env.sh

_spec_hunt_repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export ELAN_HOME="${ELAN_HOME:-$HOME/.elan}"
export PATH="$ELAN_HOME/bin:$HOME/.local/bin:$HOME/.foundry/bin:$PATH"

# solc-select installs versioned binaries here; the artifact path is stable.
export SOLC="${SOLC:-$HOME/.solc-select/artifacts/solc-0.8.35/solc-0.8.35}"
export FORGE="${FORGE:-$HOME/.foundry/bin/forge}"
export LAKE="${LAKE:-$ELAN_HOME/bin/lake}"

# Opt-in disk caches (solc AST, importer output, measured EVM oracle).
export CONTEST_CACHE_DIR="${CONTEST_CACHE_DIR:-$HOME/.cache/spec-hunt}"
# Parallelism for the sample self-test suite (independent checks).
export CONTEST_SAMPLES_JOBS="${CONTEST_SAMPLES_JOBS:-8}"

spec_hunt_env_check() {
  local root="${1:-$_spec_hunt_repo}" rc=0
  printf '%-10s %s\n' "repo" "$root"

  local lean_tc="?"
  [[ -f "$root/lean-toolchain" ]] && lean_tc="$(tr -d '[:space:]' < "$root/lean-toolchain")"
  local tc_dir
  tc_dir=$(ls -d "$ELAN_HOME"/toolchains/*"${lean_tc##*:}"*/bin 2>/dev/null | head -1 || true)
  if [[ -x "$LAKE" && -n "$tc_dir" ]]; then
    printf '%-10s %s\n' "lean" "$lean_tc (installed)"
  else
    printf '%-10s MISSING: pinned %s — run: elan toolchain install %s\n' \
      "lean" "$lean_tc" "$lean_tc"; rc=1
  fi

  if [[ -x "$SOLC" ]] && "$SOLC" --version 2>/dev/null | grep -q 'Version: 0\.8\.35'; then
    printf '%-10s %s\n' "solc" "0.8.35 ($SOLC)"
  else
    printf '%-10s WRONG/MISSING: need exactly 0.8.35 at %s\n' "solc" "$SOLC"; rc=1
  fi

  if [[ -x "$FORGE" ]]; then
    printf '%-10s %s\n' "forge" "$("$FORGE" --version 2>&1 | head -1)"
  else
    printf '%-10s MISSING (%s)\n' "forge" "$FORGE"; rc=1
  fi

  printf '%-10s %s\n' "cache" "${CONTEST_CACHE_DIR:-<disabled>}"
  if [[ -d "$root/.lake/build" ]]; then
    printf '%-10s %s\n' "build" "present (incremental)"
  else
    printf '%-10s %s\n' "build" "absent (run: lake build)"
  fi
  return "$rc"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  case "${1:-}" in
    --check|-c) spec_hunt_env_check "$_spec_hunt_repo" ;;
    *)
      echo "usage: source $0   # to export the pinned environment" >&2
      echo "       $0 --check    # to verify it" >&2
      exit 2 ;;
  esac
fi
