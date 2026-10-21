// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;
/* ===ARENA-MANIFEST===
{ "deploy": { "contract": "C", "args": [] }, "entry": { "function": "run", "args": [] },
  "feature": "known-193-keccak-encode-packed-narrow",
  "note": "known gap #193: keccak256(abi.encodePacked(a+b)) with uint8 200+100 must Panic 0x11." }
===END-ARENA-MANIFEST=== */
contract C {
    function run() external pure returns (bytes32) {
        uint8 a = 200;
        uint8 b = 100;
        return keccak256(abi.encodePacked(a + b));
    }
}
