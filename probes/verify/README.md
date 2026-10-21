# Re-verification probes for rows still marked `found`

These single-file probes replay the exact divergence shapes of older
`DIVERGENCE-LOG.md` rows that were still marked `found` / `queued` /
`UNBLOCKED`. They all adjudicate to **`NO_DIVERGENCE`** on `main` @ `16843fd`
(the WS1/WS2 batches fixed the corresponding rows; the log statuses are
historical).

Run them all:

```sh
. scripts/spec_hunt_env.sh
scripts/spec_hunt_bg.sh start --jobs 5 --name verify probes/verify/*.sol
scripts/spec_hunt_bg.sh wait verify
```

| Probe | Row | Trigger | Model observable |
|---|---|---|---|
| `p49_known193_return.sol` | #193 | `keccak256(abi.encodePacked(a+b))`, `uint8 a=200,b=100` | `revert|panic:17` (match) |
| `p50_known201_assign_abiencode.sol` | #201 A | assignment-RHS `z = abi.encode(a+b)` | `revert|panic:17` (match) |
| `p51_known201_vardecl_abiencode.sol` | #201 B | vardecl-init `bytes memory z = abi.encode(a+b)` | `revert|panic:17` (match) |
| `p52_known201_require_length.sol` | #201 C | `require(abi.encode(a+b).length > 0)` | `revert|panic:17` (match) |
| `p53_known201_emit_builtin.sol` | #201 D | `emit EB(abi.encode(a+b))` | `revert|panic:17` (match) |
| `p54_known204_push_regrow.sol` | #204 | dangling write past length survives `pop()` + `push()` | `success|w:5` (match) |
| `p55_known196_lib_chain.sol` | #196 | `x.add(1).add(2).add(3)` (3-deep using-for chain) | `success|w:7` (match) |
| `p56_known198_lib_enum_literal.sol` | #198 | `Lib.isOff(Lib.Mode.Off)` | `success|w:1` (match) |
| `p57_known198_lib_enum_conv.sol` | #198 | `Lib.isOff(Lib.Mode(0))` | `success|w:1` (match) |
| `p58_known202_storage_bytes_revert.sol` | #202 | bare storage `bytes` as a custom-error arg | `revert|custom:Bad:b:0xaabb` (match) |

Each manifest carries a `note` with the solc+EVM expectation, so the file is
self-documenting when opened in isolation.
