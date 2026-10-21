// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;
/* ===ARENA-MANIFEST===
{ "deploy": { "contract": "C", "args": [] }, "entry": { "function": "run", "args": [] },
  "feature": "known-201-d-emit-builtin-narrow",
  "note": "known gap #201 group D: emit EB(abi.encode(a+b)) with uint8 200+100 must Panic 0x11." }
===END-ARENA-MANIFEST=== */
contract C {
    event EB(bytes data);

    function run() external returns (uint) {
        uint8 a = 200;
        uint8 b = 100;
        emit EB(abi.encode(a + b));
        return 1;
    }
}
