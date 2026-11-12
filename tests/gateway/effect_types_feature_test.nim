{.push raises: [CatchableError].}

## Effect Types Feature Test.
## See tests/features/effect_types.feature for the specification.
##
## Validates the effect system types compile and are distinct.

import std/[os, osproc, strutils, unittest]

import ../../src/core/trusted/effect_types

{.push warning[BareExcept]:off.}
suite "effect types — compile-time safety":

  test "OpaqueJsonString is a distinct string":
    let s: OpaqueJsonString = "test".OpaqueJsonString
    check $s == "test"

  test "OpaqueJsonString round-trips through distinct conversion":
    let raw = "{\"key\": \"value\"}"
    let opaque = raw.OpaqueJsonString
    check string(opaque) == raw

  test "parseJson blocked at compile time on OpaqueJsonString":
    ## Verify that std/json.parseJson cannot accept OpaqueJsonString.
    ## Since OpaqueJsonString is a distinct string, the compiler rejects
    ## passing it to parseJson(string) at compile time.
    let src = """
import std/json
import effect_types
let o: OpaqueJsonString = "{}".OpaqueJsonString
let j = parseJson(o)
"""
    let (output, code) = execCmdEx(
      "nim check --hints:off --warnings:off -p:src/core/trusted --eval:" & quoteShell(src),
      options = {poStdErrToStdOut}
    )
    check code != 0
    check ("type mismatch" in output) or ("expression" in output) or ("Error" in output)

  test "pureParseJson accepts OpaqueJsonString (the sanctioned path)":
    ## The only sanctioned parse entry for OpaqueJsonString is pureParseJson
    ## via the overload in json_parse_guard.nim.
    let src = """
import json_parse_guard
import effect_types
let o: OpaqueJsonString = "{}".OpaqueJsonString
let j = pureParseJson(o)
"""
    let (output, code) = execCmdEx(
      "nim check --hints:off --warnings:off -p:src/core/trusted -p:src/core/pure --eval:" & quoteShell(src),
      options = {poStdErrToStdOut}
    )
    check code == 0
    if code != 0:
      echo "pureParseJson(OpaqueJsonString) compile failed: ", output
{.pop.}
