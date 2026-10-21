// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;
/* ===ARENA-MANIFEST===
{ "deploy": { "contract": "C", "args": [] }, "entry": { "function": "run", "args": [] },
  "feature": "known-201-a-assignment-abiencode-narrow",
  "note": "known gap #201 group A: assignment-RHS abi.encode(a+b) with uint8 200+100 must Panic 0x11." }
===END-ARENA-MANIFEST=== */
contract C {
    bytes z;

    function run() external returns (bytes memory) {
        uint8 a = 200;
        uint8 b = 100;
        z = abi.encode(a + b);
        return z;
    }
}
