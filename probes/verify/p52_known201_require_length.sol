// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;
/* ===ARENA-MANIFEST===
{ "deploy": { "contract": "C", "args": [] }, "entry": { "function": "run", "args": [] },
  "feature": "known-201-c-require-builtin-length-narrow",
  "note": "known gap #201 group C: require(abi.encode(a+b).length > 0) with uint8 200+100 must Panic 0x11." }
===END-ARENA-MANIFEST=== */
contract C {
    function run() external pure returns (uint) {
        uint8 a = 200;
        uint8 b = 100;
        require(abi.encode(a + b).length > 0);
        return 1;
    }
}
