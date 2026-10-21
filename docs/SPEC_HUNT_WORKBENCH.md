# Spec Hunt workbench — check a divergence fast, correctly, in the background

This is the practical loop for the `spec-hunt` branch: pin the toolchain, write a
minimal probe, adjudicate it against **pinned solc 0.8.35 + a real EVM + the Lean
model**, then fan many probes out in a background shell. The authoritative
contest rules remain [contest/README.md](../contest/README.md) and
[contest/SUBMITTING.md](../contest/SUBMITTING.md); this note is the day-to-day
driver.

## 0. One-time setup (already done on this machine)

```sh
# Lean toolchain (pinned by lean-toolchain = leanprover/lean4:v4.28.0)
curl -fsSL https://elan.lean-lang.org/elan-init.sh | sh -s -- -y --default-toolchain none

# Reference compiler: exactly 0.8.35
uv tool install solc-select
solc-select install 0.8.35 && solc-select use 0.8.35

# EVM side (already present)
forge --version        # 1.8.x or any recent stable

# Lean model + witnesses (first build is the expensive one)
. scripts/spec_hunt_env.sh
scripts/spec_hunt_env.sh --check     # fails if solc != 0.8.35 / lake missing
lake build
```

`scripts/spec_hunt_env.sh` exports `SOLC`, `FORGE`, `LAKE`, prepends the elan /
solc-select / Foundry bin dirs, and enables the disk cache. Source it in every
new shell. A **wrong solc silently changes verdicts**, so `--check` is the first
command of any session.

Build variants:

| command | use |
|---|---|
| `lake build` | full gate: semantics + proofs + all witnesses |
| `scripts/fast_inner_gate.sh [Module]` | edit loop: semantic spine + proof laws + one witness |
| `scripts/build_fast_runtime.sh` | attest the native `specHuntRunner` used by adjudication |
| `scripts/compare_forge_solc_interpreter.sh --jobs 10` | replay corpus vs the real EVM |
| `scripts/smoke_replay.sh` | curated Lean-only subset (28 cases) |

## 1. Write the probe (single file, no Forge test)

The cheapest format is a **single `.sol` with an embedded arena manifest** — the
manifest is the measurement recipe, so you do not hand-write a Forge test.
Copy the shape used by [probes/p1_ecrecover.sol](../probes/p1_ecrecover.sol):

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;
/* ===ARENA-MANIFEST===
{ "deploy": { "contract": "C", "args": [] },
  "entry":  { "function": "run", "args": [7] },
  "feature": "short-kebab-name",
  "note": "what solc+EVM do vs what the model does" }
===END-ARENA-MANIFEST=== */
contract C {
    function run(uint256 x) external pure returns (uint256) { ... }
}
```

Optional manifest fields: `env` (`blockNumber`/`blockTimestamp`/`chainId`/
`baseFee`/`prevRandao`/`caller`/`balances`), `storage` (raw slot seeding),
`overAccept: true` (solc-rejects sub-case, lane S), `fuel` (validated but the
adjudicator runs at the cap). Do **not** put `*/` inside the manifest block.

For directory-format submissions (`src/`, `test/`, `foundry.toml`,
`claim.json`) use the same adjudicator; `contest/samples/` has one of each
classification.

## 2. Adjudicate (the only trustworthy check)

```sh
. scripts/spec_hunt_env.sh

# single-file probe
python3 -m contest.manifest probes/p1_ecrecover.sol

# directory submission
python3 -m contest.adjudicate contest/samples/no_divergence
```

The verdict is **measured**, not taken from the claim:

| verdict | lane | meaning |
|---|---|---|
| `NO_DIVERGENCE` | — | both engines agree (control passes) |
| `SOUNDNESS_GAP` | S | solc rejects but the model runs, or both run with different observables |
| `COVERAGE_GAP` | C | solc accepts+runs, the model fails closed |
| `REJECTED_OOS` | — | exclusion register / known-gap fingerprint hit |
| `REJECT_MALFORMED` / `INVALID` | — | broken submission (manifest, args, test) |
| `NEEDS_REVIEW` | — | timeout / resource / ambiguous executable-failure — never auto-qualifies |

`qualifies=true` only for the two gap verdicts. Exit code is `1` for
non-qualifying, non-`NO_DIVERGENCE` outcomes.

### Checking discipline (this is where false positives come from)

1. **Pin first.** `scripts/spec_hunt_env.sh --check`. Re-check after any shell
   restart; a 0.8.27 `solc` on `PATH` will invent divergences.
2. **Minimal trigger, then an isolation table.** Run the suspect shape plus
   sibling shapes that should *not* trigger (different position, explicit cast,
   literal vs variable, block- vs for-init, etc.). A gap is only credible when
   the adjacent controls are `NO_DIVERGENCE`. Record the table in the log entry.
3. **Never trust `declared_observable`.** The EVM side is measured through Forge;
   the Lean side is the rendered post-call state. Read `.evidence` in `--json`.
4. **Dedup before celebrating.** `python3 -m contest.known_gaps` and
   `DIVERGENCE-LOG.md`; a match is `REJECTED_OOS`, not a finding.
5. **Classify the bug honestly**: over-reject vs over-accept vs wrong-value vs
   missing-panic; `-`/accept-only findings are lower priority than replay-reachable
   ones.
6. **Record** the confirmed divergence in `DIVERGENCE-LOG.md` with date, id,
   trigger, mechanism + `file:line`, isolation notes, lane, status.

Where to hunt next: rows marked `found` / `built` / `HELD` in
`DIVERGENCE-LOG.md`, the open candidates in
[docs/semantics-divergence-handoff.md](semantics-divergence-handoff.md), and
whole *families* of lowering arms in
`SolidCore/Solidity/Interface/Expressions.lean` / `Statements.lean` (the
historical bugs cluster by position × construct, e.g. call-in-X, literal-to-Y,
narrow-type cleanup).

## 3. Background + parallel runs

Each adjudication is subprocess-isolated (`solc`, `forge`, `lake env lean` all in
their own temp dirs), so parallelism changes wall-clock only. Use the runner:

```sh
. scripts/spec_hunt_env.sh

# fire-and-detach: every probe in probes/, 4 at a time, 10 min cap each
scripts/spec_hunt_bg.sh start --jobs 4 --timeout 600 --name probes probes/*.sol

scripts/spec_hunt_bg.sh list                 # RUNNING/FINISHED and progress
scripts/spec_hunt_bg.sh status probes        # aggregated verdict table
scripts/spec_hunt_bg.sh tail probes          # follow driver log (Ctrl-C detaches)
scripts/spec_hunt_bg.sh wait probes          # block, then print the table
```

Outputs land in `tmp/spec-hunt-runs/<name>-<stamp>/`:

```
driver.log        # orchestrator log
inputs.txt        # exact input list
logs/<tag>.json   # full report (verdict, lane, evidence)
logs/<tag>.err    # stderr (solc/forge/lean diagnostics)
logs/<tag>.verdict
summary.tsv       # verdict, lane, input
pid
```

Rules of thumb on an 8-core / 8 GB machine: `--jobs 4` for mixed probes, `2–3`
for heavy contracts (compile + anvil + Lean at once); raise `--timeout` rather
than jobs when cases are slow. The runner wraps itself in `caffeinate -i` so a
long build does not die on idle sleep. For raw fan-out without the wrapper:

```sh
find probes -name '*.sol' -print0 \
  | xargs -0 -n1 -P4 python3 -m contest.manifest --json > /dev/null
```

### Faster adjudication

- `export CONTEST_CACHE_DIR="$HOME/.cache/spec-hunt"` (the env script does this).
  Caches: solc ASTs, importer output, and **measured EVM observations** — a
  Lean-only edit reuses the EVM oracle but re-runs Lean and the verdict.
  `CONTEST_DISABLE_CACHE=1` bypasses; imports in a submission bypass caching.
- `scripts/build_fast_runtime.sh` builds and attests `specHuntRunner`; a missing
  or stale attestation silently falls back to plain `lake env lean` (slower).
  Rebuild it after touching semantics. `CONTEST_NATIVE=0` forces the fallback.
- Interactive compiler flags: the statement-lowering module is built at `-O0`
  by default; `lake -KspecHuntLoweringO3=true build` is for profiling only.
- The sample suite parallelizes itself: `CONTEST_SAMPLES_JOBS=8 python3 -m contest.run_samples`.

## 4. Before you claim a fix

```sh
scripts/fast_inner_gate.sh SolidCore.Witness.YourWitness   # fast iteration
lake build                                                 # full green gate
CONTEST_SAMPLES_JOBS=8 python3 -m contest.run_samples       # 85 contest checks
scripts/compare_forge_solc_interpreter.sh --jobs 10        # replay corpus
```

A divergence finding needs a witness; a fix needs the full gate green plus the
regression witness, and the log row updated with the merge commit.
