import core/trusted/layer_declaration
axiomLayer "trusted.core.effect-types"

{.push raises: [].}
## Effect System types for Axiom's 3-Layer JSON parsing defense.
## ============================================================
## Layer 1: UnsafeJsonEffect — {.forbids: [UnsafeJsonEffect].} blocks parseJson in core
## Layer 2: OpaqueJsonString — distinct string type gates pureParseJson access
## Layer 3: AST nnkCast detection — gate_safety_macro.nim blocks cast bypass
##
## See: docs/spec/correctness_by_construction.md
## ============================================================

type
  UnsafeJsonEffect* = object
    ## Effect tag for unsafe JSON parsing (std/json.parseJson).
    ## Any function that calls parseJson inherits this tag.
    ## Core layer functions use {.forbids: [UnsafeJsonEffect].} to block it.

  OpaqueJsonString* = distinct string
    ## Distinct string type that gates access to pureParseJson.
    ## Only created via toOpaqueJson() — prevents raw string from bypassing.
func toOpaqueJson*(s: string): OpaqueJsonString {.inline.} =
  ## Convert string to OpaqueJsonString.
  ## This is the ONLY entry point for JSON parsing in core layer.
  OpaqueJsonString(s)
func fromOpaqueJson*(s: OpaqueJsonString): string {.inline.} =
  ## Extract string from OpaqueJsonString (for serialization).
  string(s)
proc `$`*(s: OpaqueJsonString): string {.inline.} = string(s)
