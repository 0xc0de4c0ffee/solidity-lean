// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;
/* ===ARENA-MANIFEST===
{ "deploy": { "contract": "C", "args": [] }, "entry": { "function": "run", "args": [] },
  "feature": "known-202-storage-bytes-revert-arg",
  "note": "known gap #202: bare storage bytes as a custom-error argument at the revert boundary. solc reverts Bad(0xaabb)." }
===END-ARENA-MANIFEST=== */
error Bad(bytes payload);

contract C {
    bytes b;

    function run() external {
        b = hex"aabb";
        revert Bad(b);
    }
}
