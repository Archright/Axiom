import core/trusted/layer_declaration
axiomLayer "trusted.core.pragmas-lite"

## axiom_pragmas_lite.nim — Lightweight pragma/type definitions for leaf files.
##
## Import this instead of axiom_pragmas when you only need:
##   - Custom pragma templates (axiom, axiomEffect, axiomProp, etc.)
##   - Type definitions (AxiomEffectKind, PropertyKind)
##   - AST inspection helpers (hasAxiomPragma, extractAxiomStrings)
##
## This eliminates ~800 lines of IR conversion, effect analysis, and macro
## logic that most leaf files never use.
##
## axiom_pragmas.nim re-exports this module, so importing axiom_pragmas
## still provides all symbols below — no downstream changes required.

{.push raises: [].}

import std/macros
import effect_bridge
export effect_bridge

# ─── Custom Pragma Definitions ────────────────────────────────────────────────

template axiom*(val: untyped = "") {.pragma.}
  ## First-class pragma for formal verification annotations.
  ## Detected in AST via nnkPragma > nnkExprColonExpr > nnkIdent("axiom").
  ## Replaces @axiom-hint comment parsing — deterministic, compiler-guaranteed.
  ##
  ## Usage:
  ##   proc calculateDepth(nodes: seq[Node]): int
  ##       {.axiom: [smt("assert (>= depth 0)"), lean("depth >= 0")].} =
  ##     ...

# ─── AST Inspection Helpers ───────────────────────────────────────────────────

func hasAxiomPragma*(node: NimNode): bool =
  ## Check if a proc/func has {.axiom.} annotation.
  ## Scans nnkPragma children for nnkIdent("axiom").
  if node.kind notin {nnkProcDef, nnkFuncDef, nnkTemplateDef}:
    return false
  let pragma = node.pragma
  if pragma.kind == nnkEmpty:
    return false
  for child in pragma:
    if child.kind == nnkIdent and child.strVal == "axiom":
      return true
    if child.kind == nnkExprColonExpr and child[0].kind == nnkIdent and child[0].strVal == "axiom":
      return true
  return false

func extractAxiomStrings*(node: NimNode): tuple[smt, lean: string] =
  ## Extract smt() and lean() string values from {.axiom: [...].}
  ## Returns empty strings if not found.
  result = ("", "")
  let pragma = node.pragma
  if pragma.kind == nnkEmpty:
    return
  for child in pragma:
    if child.kind == nnkExprColonExpr and child[0].kind == nnkIdent and child[0].strVal == "axiom":
      # child[1] should be nnkBracket containing nnkExprColonExpr or nnkCall
      if child[1].kind == nnkBracket:
        for arg in child[1]:
          if arg.kind in {nnkCall, nnkExprColonExpr}:
            let name = if arg[0].kind == nnkIdent: arg[0].strVal else: ""
            let val = if arg[1].kind == nnkStrLit: arg[1].strVal else: ""
            if name == "smt": result.smt = val
            elif name == "lean": result.lean = val

# ─── Effect & Property Type Definitions ───────────────────────────────────────

template axiomGcsafe*() {.pragma.}
  ## Axiom-specific gcsafe marker.
  ## Only valid when architecture_policy.lock [gcsafe_approvals] contains the file hash.
  ## nimtry enforces: axiomGcsafe without lock entry = violation.
  ##
  ## Usage:
  ##   {.cast(gcsafe).}:
  ##     {.axiomGcsafe.}:
  ##       bridge.leanstralCall = leanstralGateway
  ##
  ## This replaces raw cast(gcsafe) with an auditable, architect-approved marker.

type
  PropertyKind* = enum
    ## Algebraic property classification for the `axiomProp` custom pragma.
    ## Used by compile-time source scanner to generate property verification code.
    pkCommutative,    ## f(a, b) == f(b, a)
    pkAssociative,    ## f(f(a, b), c) == f(a, f(b, c))
    pkIdempotent,     ## f(a, a) == a
    pkIdentity,       ## f(a, identity) == a
    pkInverse,        ## f(a, inverse(a)) == identity
    pkDistributive,   ## f(a, g(b, c)) == g(f(a, b), f(a, c))
    pkMonotonic,      ## a <= b implies f(a) <= f(b)
    pkConfluent       ## all reduction paths converge to same result

# ─── Effect & Property Pragma Templates ───────────────────────────────────────

template axiomProp*(props: varargs[PropertyKind]) {.pragma.}
  ## Algebraic property annotation for compile-time verification.
  ## The compile-time source scanner extracts these from AST and generates
  ## verification code that runs at compile time (Zero-Artifact).
  ##
  ## Usage:
  ##   proc mergeState*(a, b: State): State {.axiomProp: [pkCommutative, pkAssociative].} =
  ##     ...

template refines*(path: string = "") {.pragma.}
  ## First-class pragma marking a proc/func whose signature must
  ## match the corresponding definition in the shadow (func-ified) file.

template axiomIoHint*(reason: string) =
  ## Self-documenting compile-time hint explaining why a proc uses I/O.
  ## Place inside procs that carry `{.axiomEffect: IOEffect.}` so developers
  ## see a human-readable reason instead of having to trace call chains.

template axiomIoBoundary*() =
  ## Module-level declaration: this file is an I/O boundary.
  ## All procs in this module may perform I/O. nimtry PURITY checks
  ## are short-circuited for files containing this pragma.
  ## Pairs with {.axiomEffect: IOEffect.} on individual proc.
  discard

# ─── Debt Pragma Templates ───────────────────────────────────────────────────

template axiomDebt*(id: static[string], kind: static[string] = "debt", category: static[string] = "", impact: static[string] = "Medium") {.pragma.}
  ## Debt or quirk tracking pragma.
  ##
  ## Usage (DEBT#NNN is a placeholder — a cited id MUST exist in
  ## data/debt_registry.json; illustrative ids with no registry entry are
  ## ghost references and are treated as theater per AGENTS.md §0.9):
  ##   proc myProc() {.axiomDebt: "DEBT#NNN", kind: "quirk", category: "compiler", impact: "Low".} =
  ##   proc myProc() {.axiomDebt: "DEBT#NNN", category: "structural", impact: "High".} =
  ##
  ## `kind`: "debt" (default) | "quirk" | "theater" | "fixme"
  ## `impact`: "Critical" | "High" | "Medium" | "Low" (default: "Medium")

template axiomDecision*(id = "", reason = "", adr = "", introduced = "") {.pragma.}
  ## AST annotation binding a symbol to a decision record (ADR).
  ## Compile-time only — no runtime effect.
  ##
  ## Usage (plain — binds to an ADR with no inline metadata):
  ##   proc verifyReceipt*(r: ProofReceipt): bool {.axiomDecision.} =
  ##
  ## Usage (named fields — AGENTS.md §0.10 mandates id/reason/adr/introduced):
  ##   proc verifyReceipt*(r: ProofReceipt): bool {.axiomDecision(
  ##     id = "DECISION-NNNN",
  ##     reason = "Atomic receipt serialization for cross-process integrity",
  ##     adr = "docs/adr/0001-fail-closed-result-type.md",
  ##     introduced = "v27").} =
  ##
  ## Note: the named fields use `=` (not `:`) — in Nim, pragma-template
  ## arguments are keyword-assigned with `=`, so `{.axiomDecision(id: "x").}`
  ## does not compile but `{.axiomDecision(id = "x").}` does.
  ## (Full ADR narrative is tracked in decisions_graph.json / docs/adr/.)

{.pop.}
