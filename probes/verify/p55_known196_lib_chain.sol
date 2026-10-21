// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;
/* ===ARENA-MANIFEST===
{ "deploy": { "contract": "C", "args": [] }, "entry": { "function": "run", "args": [] },
  "feature": "known-196-nested-library-call-chain",
  "note": "known gap #196: a 3-deep using-for library call chain must not collide temporaries. solc returns 7." }
===END-ARENA-MANIFEST=== */
library M {
    function add(uint a, uint b) internal pure returns (uint) {
        return a + b;
    }

    function sub(uint a, uint b) internal pure returns (uint) {
        return a - b;
    }

    function mul(uint a, uint b) internal pure returns (uint) {
        return a * b;
    }
}

contract C {
    using M for uint256;

    function run() external pure returns (uint) {
        uint x = 1;
        return x.add(1).add(2).add(3);
    }
}
