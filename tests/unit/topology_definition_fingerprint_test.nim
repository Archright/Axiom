## Unit test for WP4-d-1 definitionFingerprint additive discriminator.
##
## Problem (WP4-d): nim-stew's `func getBitsBE` and `template getBitsBE`
## share the same SorterNodeId (`modulePath::functionName`), so the
## topology scanner produced colliding IDs and a false self-dependency.
##
## WP4-d-0 measured that the declaration-text digest separates the two.
## WP4-d-1 materializes that as an additive `definitionFingerprint`
## field that does NOT alter SorterNodeId (ScopeIdentity remains
## `modulePath::functionName`, an external-contract invariant).
##
## This suite asserts:
##   1. func/template with different arity produce DIFFERENT
##      definitionFingerprint (discriminator works).
##   2. func/template with DIFFERENT signatures still produce the SAME
##      nodeId (SorterNodeId immutability — outside contract preserved).

import std/[unittest, strutils]
import core/topology/topology_engine
import core/sorter/sorter_core

suite "WP4-d-1 definitionFingerprint discriminator":

  test "func getBitsBE and template getBitsBE get different fingerprints, same nodeId":
    ## Mimics the nim-stew collision: same module, same functionName,
    ## different kind + arity.
    let symbols = scanTopologySource("stew/bits.nim", """
func getBitsBE*(value: uint64; startBit, length: int): int =
  discard

template getBitsBE*(value: uint64; length: int): int =
  discard
""")
    ## Only function-kind declarations are captured (let/var/type skipped).
    check symbols.len == 2
    let funcSym = symbols[0]
    let tmplSym = symbols[1]
    check funcSym.nodeType == "func"
    check tmplSym.nodeType == "template"

    ## Discriminator: different signature -> different digest.
    check funcSym.definitionFingerprint != tmplSym.definitionFingerprint
    check funcSym.definitionFingerprint.len == 64  # sha256 hex
    check tmplSym.definitionFingerprint.len == 64

    ## SorterNodeId invariance: same module::functionName => same nodeId.
    check sorterNodeIdString(funcSym.nodeId) == "stew/bits.nim::getBitsBE"
    check sorterNodeIdString(tmplSym.nodeId) == "stew/bits.nim::getBitsBE"
    check funcSym.nodeId == tmplSym.nodeId

  test "identical signature yields identical fingerprint (determinism)":
    ## Same module, name, kind, arity -> deterministic same digest.
    let a = scanTopologySource("stew/bits.nim", """
func getBitsBE*(value: uint64; startBit, length: int): int =
  discard
""")
    let b = scanTopologySource("stew/bits.nim", """
func getBitsBE*(value: uint64; startBit, length: int): int =
  discard
""")
    check a.len == 1
    check b.len == 1
    check a[0].definitionFingerprint == b[0].definitionFingerprint

  test "different modulePath yields different fingerprint":
    let a = scanTopologySource("stew/bits.nim", "func getBitsBE*(value: uint64): int =\n  discard\n")
    let b = scanTopologySource("stew/bits2.nim", "func getBitsBE*(value: uint64): int =\n  discard\n")
    check a.len == 1
    check b.len == 1
    check a[0].definitionFingerprint != b[0].definitionFingerprint
    ## nodeId still carries module, so it differs too — but fingerprint
    ## independently discriminates, which is the new capability.
