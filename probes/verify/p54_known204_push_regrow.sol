// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;
/* ===ARENA-MANIFEST===
{ "deploy": { "contract": "C", "args": [] }, "entry": { "function": "run", "args": [] },
  "feature": "known-204-push-does-not-clear-regrown-slot",
  "note": "known gap #204: a dangling write past the length must survive pop+push (push only bumps length). solc returns 5." }
===END-ARENA-MANIFEST=== */
struct S {
    uint a;
}

contract C {
    S[] arr;

    constructor() {
        arr.push();
        arr[0].a = 1;
        arr.push();
        arr[1].a = 2;
    }

    function run() external returns (uint) {
        uint i = 1;
        S storage p = arr[i];
        arr.pop();
        p.a = 5;
        arr.push();
        return arr[i].a;
    }
}
