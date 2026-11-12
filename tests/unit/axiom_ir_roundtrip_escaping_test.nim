## Round-trip and bounded-termination contract for the core IR text codec.
##
## `SLIT(payload)` carries no length prefix and no quoting. When the serializer
## emitted the payload raw and the parser scanned to the first `)`, any payload
## containing `)` terminated itself early; the leftover text was then re-read as
## IR syntax, and the `irCase` branch loop — which had no progress guard — spun
## at a fixed offset forever. That loop is what hung `ax prove` at 100 % CPU.
##
## This suite pins three properties so the defect cannot return silently:
##   1. adversarial payloads survive serialize → deserialize unchanged;
##   2. the registry round-trip identity documented at axiom_ir.nim:1036 holds;
##   3. every registry entry deserializes within a bounded time (termination).

import core/trusted/layer_declaration
{.push raises: [].}

import std/[strutils, times]
import cli/main
import core/axiom_pragmas
import core/trusted/axiom_ir

# Real payloads from the tree. Both contain `)`; neither may be edited to suit
# the codec, because the codec has to carry them.
const
  PayloadBitVecSort = "(_ BitVec 64)"             # ir_to_smt_chunk2.nim:10
  PayloadBudgetMsg = " external symbols (budget = 12)"  # gate_rules_architecture.nim:325

# A per-entry budget of this many milliseconds cannot be met by an
# infinite loop and is ~5 orders of magnitude above the observed cost of a
# well-formed entry, so it fires on the pathology rather than on machine load.
const PerEntryBudgetMs = 250

proc wrapStringLit(payload: string): string =
  ## A FUNC whose body is `CASE(L(0){0=>SLIT(payload)})` — the exact nesting that
  ## hung: the truncated payload used to leave the case loop facing a foreign
  ## token that no arm could consume.
  let lit = IRExpr(kind: irStringLit, stringVal: payload)
  let body = IRExpr(kind: irCase,
                    caseScrutinee: IRExpr(kind: irLit, litVal: 0),
                    caseBranches: @[CaseBranch(pattern: 0, body: lit)])
  serializeIRFuncDef(IRFuncDef(name: "f", retType: irTypeString(), body: body))

proc decodedPayload(text: string): string =
  ## The SLIT payload recovered from `text`, or "" when the parse did not
  ## produce the expected shape. A sentinel (name.len == 0) is deliberately not
  ## a failure signal here — returning "" is enough to fail the equality assert.
  let f = deserializeIRFuncDef(text)
  if f.name == "" or f.body == nil or f.body.kind != irCase: return ""
  if f.body.caseBranches.len != 1: return ""
  let litBranch = f.body.caseBranches[0].body
  if litBranch == nil or litBranch.kind != irStringLit: return ""
  litBranch.stringVal

proc main() =
  var passed = 0
  var failed = 0
  var failures: seq[string] = @[]

  template check(name: string, body: untyped) =
    block:
      try:
        body
        inc passed
        echo "  PASS: " & name
      except CatchableError, AssertionDefect:
        inc failed
        failures.add(name)
        echo "  FAIL: " & name & " - " & getCurrentExceptionMsg()

  # -------------------------------------------------------------------------
  echo "=== adversarial SLIT payloads ==="
  # -------------------------------------------------------------------------
  let adversarial = ["", ")", "(", ")", "))", "()", "(_ BitVec 64)",
                     " external symbols (budget = 12)", "a)b)c)d",
                     "\\", "\\\\", "\\)", "a\\b)c", "SLIT(", "L(0)",
                     "CASE(L(0){0=>SLIT(x)})", " leading and trailing ",
                     "\n", "NIL", "a\nb)c"]
  for payload in adversarial:
    let text = wrapStringLit(payload)
    let recovered = decodedPayload(text)
    check "payload round-trips: " & payload.escape:
      assert recovered == payload,
        "decoded " & recovered.escape & " != original " & payload.escape &
        " (text=" & text.escape & ")"
    check "payload re-serializes identically: " & payload.escape:
      let f = deserializeIRFuncDef(text)
      assert f.name.len > 0, "sentinel — the payload did not survive escaping"
      assert serializeIRFuncDef(f) == text, "not byte-stable for " & text.escape

  # The two live payloads, named so a regression points at the source of truth.
  check "live payload ir_to_smt_chunk2 survives":
    assert decodedPayload(wrapStringLit(PayloadBitVecSort)) == PayloadBitVecSort
  check "live payload gate_rules_architecture survives":
    assert decodedPayload(wrapStringLit(PayloadBudgetMsg)) == PayloadBudgetMsg

  # -------------------------------------------------------------------------
  echo "=== malformed input fails closed, never hangs, never yields a nil body ==="
  # -------------------------------------------------------------------------
  let malformed = [
    "FUNC(f():STR=CASE(L(0){0=>SLIT(a)b)})",       # unterminated SLIT + stray ')'
    "FUNC(f():STR=CASE(L(0){0=>SLIT(a)b)}))",      # trailing junk after the case
    "FUNC(f():STR=CASE(L(0){0=>))",                # case loop faces a bare ')'
    "FUNC(f():STR=CASE(L(0){0=>SLIT((_ BitVec 64))}),rec=false)",  # the historic hang
    "FUNC(f():BV64=ENUM(E,[,x],),rec=false)",
    "FUNC(f([):BV64=L(0),rec=false)",
    "GARBAGE",
    "FUNC(",
    "FUNC(f():BV64=CAST(L(0),BV64->BV64),rec=false)",
    "FUNC(f():LIST(BV64)=CALL(x,[,,]),rec=false)"
  ]
  for text in malformed:
    let started = getTime()
    let f = deserializeIRFuncDef(text)
    let elapsedMs = inNanoseconds(getTime() - started) div 1_000_000
    check "malformed terminates and is a sentinel: " & text.escape:
      assert elapsedMs < PerEntryBudgetMs, "took " & $elapsedMs & "ms"
      assert f.name.len == 0 or f.body != nil,
        "returned a named funcDef with a nil body — callers dereference it unchecked"

  # -------------------------------------------------------------------------
  echo "=== registry-wide round-trip identity (axiom_ir.nim:1036 contract) ==="
  # -------------------------------------------------------------------------
  generateAxiomInit()
  initRegistryLookup()

  var opaque = 0
  var parseable = 0
  var deserialized = 0
  var sentinel = 0
  var reSerializeStable = 0
  var maxMs = 0'i64
  var totalMs = 0'i64

  for entry in runtimeAxiomRegistry:
    if entry.irSerialized == "__opaque__" or entry.irSerialized.len == 0:
      inc opaque
      continue
    inc parseable

    let started = getTime()
    let f = deserializeIRFuncDef(entry.irSerialized)
    let elapsedMs = inNanoseconds(getTime() - started) div 1_000_000
    inc totalMs
    if elapsedMs > maxMs: maxMs = elapsedMs

    check "registry entry terminates: " & entry.name:
      assert elapsedMs < PerEntryBudgetMs, "took " & $elapsedMs & "ms"
    if f.name.len == 0:
      inc sentinel
      echo "    sentinel: " & entry.name
      continue
    inc deserialized

    let first = serializeIRFuncDef(f)
    let second = deserializeIRFuncDef(first)
    check "registry entry re-serializes identically: " & entry.name:
      assert second.name.len > 0, "re-deserialization produced the sentinel"
      assert serializeIRFuncDef(second) == first,
        "deserialize(serialize(deserialize(s))) != deserialize(s)"

    # The identity the docstring at axiom_ir.nim:1036 promises. Compared on the
    # canonical text, which is the only total order available for a tree.
    if serializeIRFuncDef(second) == first: inc reSerializeStable

  echo "registry: ", runtimeAxiomRegistry.len, " total, ", opaque,
       " opaque/unmaterialised, ", parseable, " parseable"
  echo "deserialized=", deserialized, " sentinel=", sentinel,
       " roundTripStable=", reSerializeStable,
       " maxEntryMs=", maxMs, " totalMs=", totalMs

  check "every parseable registry entry deserializes":
    assert sentinel == 0, $sentinel & " registry entries fell back to the sentinel"
  check "round-trip identity holds for every registry entry":
    assert reSerializeStable == parseable,
      $reSerializeStable & "/" & $parseable & " entries are round-trip stable"

  echo ""
  echo "passed=", passed, " failed=", failed
  for f in failures: echo "  FAILED: ", f
  if failed > 0: quit(1)

main()
{.pop.}