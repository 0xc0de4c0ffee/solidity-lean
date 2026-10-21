// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;
/* ===ARENA-MANIFEST===
{ "deploy": { "contract": "C", "args": [] }, "entry": { "function": "run", "args": [] },
  "feature": "known-198-library-enum-literal-arg",
  "note": "known gap #198: an enum literal passed to an internal library fn. solc returns 1." }
===END-ARENA-MANIFEST=== */
library Lib {
    enum Mode { Off, Slow, Fast }

    function isOff(Mode m) internal pure returns (bool) {
        return m == Mode.Off;
    }
}

contract C {
    function run() external pure returns (uint) {
        return Lib.isOff(Lib.Mode.Off) ? 1 : 0;
    }
}
