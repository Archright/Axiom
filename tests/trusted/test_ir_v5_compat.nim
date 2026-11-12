## v5 IR backward compatibility tests
## Tests: OLD format deserialization, roundtrip, enum defaults, digest stability

import unittest
import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import core/gate/hash_types

suite "v5 IR backward compatibility":
  test "OLD format string (no pre/post) deserializes correctly":
    # OLD format: no ,pre=...,post=... suffix — pre-v5 serialized IRs
    let oldStr = "FUNC(add([x:BV64,y:BV64]):BV64=BIN(boAdd,V(x:BV64),V(y:BV64)),rec=false)"
    let f = deserializeIRFuncDef(oldStr)
    check f.name == "add"
    check f.params.len == 2
    check f.preConditions.len == 0
    check f.postConditions.len == 0
    check f.isRecursive == false

  test "NEW format with pre/post roundtrips correctly":
    let t = irTypeBitVec64()
    let x = irVar("x", t)
    let y = irVar("y", t)
    let body = irBinOp(boAdd, x, y)
    let f = irFuncDef("add", @[("x", t), ("y", t)], t, body, false)
    let serialized = serializeIRFuncDef(f)
    let deserialized = deserializeIRFuncDef(serialized)
    check deserialized.name == "add"
    check deserialized.params.len == 2
    check deserialized.preConditions.len == 0
    check deserialized.postConditions.len == 0

  test "constraintKind defaults to rkNone for unannotated params":
    let p = IRFuncParam(name: "x", ty: irTypeBitVec64())
    check p.constraintKind == rkNone
    check p.constraint == nil

  test "computeIrDigest is deterministic":
    let t = irTypeBitVec64()
    let x = irVar("x", t)
    let y = irVar("y", t)
    let body = irBinOp(boAdd, x, y)
    let f = irFuncDef("add", @[("x", t), ("y", t)], t, body, false)
    let d1 = computeIrDigest(f)
    let d2 = computeIrDigest(f)
    check d1 == d2
    check d1.len == 64  # SHA-256 hex digest
