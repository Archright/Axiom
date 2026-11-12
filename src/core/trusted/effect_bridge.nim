{.push raises: [].}
import core/trusted/layer_declaration
axiomLayer "trusted.core.effect-bridge"

## Effect Bridge: `{.tags.}` ↔ `{.axiomEffect.}` interop
## ============================================================
## Bridges Nim's native effect system ({.tags.}/{.forbids.}) with
## the Axiom custom pragma ({.axiomEffect.}).
##
## Why both?
##   - {.axiomEffect.} is nimtry-visible (AST extraction for audit)
##   - {.tags.}/{.forbids.} is compiler-tracked (propagation + blocking)
##   - Bridging them gives compile-time enforcement AND audit visibility
##
## Usage pattern:
##   proc readIo*() {.axiomIo, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
##     discard
##
##   func pureCalc*() {.axiomPure, axiomEffect: Pure, forbids: [AxiomIOEffect].} =
##     discard
##
## - `axiomIo` / `axiomPure`: nimtry-extractable marker pragmas
## - `axiomEffect`: existing Axiom custom pragma (backward compatible)
## - `tags` / `forbids`: Nim-native compile-time enforcement
##
## The `verifyEffectConsistency` macro provides gradual migration warnings.
## ============================================================

import std/macros

# ─── Native Effect Tag ────────────────────────────────────────────────────────

type
  AxiomEffectKind* = enum
    Pure, IOEffect
  AxiomIOEffect* = object of IOEffect
    ## Nim-native effect tag for Axiom I/O routines.
    ## Inherits from IOEffect so tags: [AxiomIOEffect] covers all standard
    ## I/O sub-effects (ReadIOEffect, WriteIOEffect, ExecIOEffect, etc.)
    ## when combined with IOEffect in the tags list.
    ##
    ## Pairs with {.axiomEffect: IOEffect.} from axiom_pragmas.
    ##
    ## {.forbids: [AxiomIOEffect].} on a proc blocks calling any proc
    ## that has {.tags: [AxiomIOEffect].} — enforced at compile time.
    ##
    ## This is the Nim-native equivalent of axiomEffect's IOEffect marker.
    ## Using BOTH gives you audit visibility (nimtry) + compiler enforcement.

  MutateContextEffect* = object of RootEffect
    ## Nim-native effect tag for PipelineContext mutation operations.
    ## Use on procs that modify PipelineContext fields.
    ## {.tags: [MutateContextEffect].} marks a proc as context-mutating.
    ## {.forbids: [MutateContextEffect].} blocks calling such procs from pure functions.
    ##
    ## This prevents the "var PipelineContext" effect contamination problem:
    ## - Pure functions use read-only handles (noSideEffect)
    ## - Mutation procs are explicitly tagged (MutateContextEffect)
    ## - Compile-time enforcement prevents accidental purity violations

  TrustPersistenceClass* = object of RootEffect
    ## **Annotation-only** marker for trust-persistence semantics (I7 Wave7A).
    ## This tag is a *declared fact* ("this routine participates in trust
    ## persistence"), NOT a provenance computation. Provenance is computed by
    ## the `effect_queries` reverse BFS (TrustCommit callable closure C), which
    ## is the source of truth for I7-2 / I7-4. Nim compiler tag propagation is
    ## deliberately NOT relied upon for correctness (see trust_authority_spec).
    ##
    ## Place on trust-persistence leaf routines so scanners/auditors can find
    ## them; do NOT treat presence here as authority. Boundary = TrustCommit
    ## closure, never a naming/module membership check.

# ─── Convenience Marker Pragmas ───────────────────────────────────────────────
#
# These are lightweight {pragma.} markers — AST-visible to nimtry for
# extracting effect classification. They serve as single-name identifiers
# that the verification macro and nimtry scanners can search for.
#
# Combined usage pattern (all three on every proc):
#   proc/io:    {.axiomIo, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].}
#   func/pure:  {.axiomPure, axiomEffect: Pure, forbids: [AxiomIOEffect].}

template axiomIo*() {.pragma.}
  ## Marker pragma: "this proc performs I/O."
  ## Use alongside {.axiomEffect: IOEffect.} and {.tags: [AxiomIOEffect, IOEffect, RootEffect].}
  ## nimtry scans for this pragma to classify I/O procs.

template axiomPure*() {.pragma.}
  ## Marker pragma: "this proc is logically pure."
  ## Use alongside {.axiomEffect: Pure.} and {.forbids: [AxiomIOEffect].}
  ## nimtry scans for this pragma to classify pure procs.

template axiomEffect*(effectType: AxiomEffectKind) {.pragma.}
  ## Axiom-specific effect classification marker.
  ## Replaces string-based / comment-based effect hints with a first-class
  ## compiler pragma that nimtry can extract from AST deterministically.
  ##
  ## Supported effect types:
  ##   {.axiomEffect: Pure.}     → routine is logically pure
  ##   {.axiomEffect: IOEffect.} → routine performs I/O or FFI side effects
  ##
  ## Usage:
  ##   proc parseWithCache*(filePath: string): TSNode
  ##       {.axiomEffect: IOEffect.} = ...
  ##
  ## Context7 grounds: Nim Manual custom pragma support; nimtry already walks
  ## nnkPragma nodes (extractPragmasV4 in nimtry_extract_part3_part2.nim).

# ─── Compile-time Consistency Validator ───────────────────────────────────────

macro verifyEffectConsistency*(body: untyped): untyped =
  ## Strict enforcement tool: scan a block for effect pragma consistency.
  ## With -d:axiomStrict: violations are compile ERRORS.
  ## Without -d:axiomStrict: violations are warnings (gradual migration).
  ##
  ## Checks:
  ##   - proc/func with {.axiomEffect: IOEffect.} but MISSING {.tags: [AxiomIOEffect].}
  ##     → error (strict) / warning (gradual)
  ##   - proc/func with {.axiomEffect: Pure.} but MISSING {.forbids: [AxiomIOEffect].}
  ##     → error (strict) / warning (gradual)
  ##
  ## Usage:
  ##   verifyEffectConsistency:
  ##     proc foo*() {.axiomEffect: IOEffect.} = ...  # error/warning: missing tags
  ##     proc bar*() {.axiomIo, axiomEffect: IOEffect.} = ...  # OK
  ##
  result = newStmtList()

  func hasAxiomEffectKind(pragmas: NimNode, kindName: string): bool =
    ## Check if {.axiomEffect: <kindName>.} is present.
    for p in pragmas:
      if p.kind == nnkExprColonExpr and p.len >= 2:
        if p[0].kind == nnkIdent and p[0].strVal == "axiomEffect":
          if p[1].kind == nnkIdent and p[1].strVal == kindName:
            return true
    false

  func hasEffectTag(pragmas: NimNode, tagType: string): bool =
    ## Check if {.tags: [TagType].} or {.forbids: [TagType].} contains the type.
    for p in pragmas:
      if p.kind == nnkExprColonExpr and p.len >= 2:
        let pragmaName = if p[0].kind == nnkIdent: p[0].strVal else: ""
        if pragmaName in ["tags", "forbids"]:
          if p[1].kind == nnkBracket:
            for tag in p[1]:
              if tag.kind == nnkIdent and tag.strVal == tagType:
                return true
    false

  func getPragmaExpr(prc: NimNode): NimNode =
    ## Extract the pragma expression node from a proc definition.
    if prc.kind in {nnkProcDef, nnkFuncDef}:
      let name = prc[0]
      if name.kind == nnkPragmaExpr:
        return name[1]
    nil

  func checkProc(prc: NimNode) =
    ## Check a single proc/func definition for consistency.
    if prc.kind notin {nnkProcDef, nnkFuncDef}: return

    let pragmas = prc.getPragmaExpr()
    if pragmas.isNil: return

    let procName = $prc.name

    # Check: IOEffect without tags: [AxiomIOEffect]
    if hasAxiomEffectKind(pragmas, "IOEffect") and
       not hasEffectTag(pragmas, "AxiomIOEffect"):
      when defined(axiomStrict):
        error("[EffectBridge] '" & procName &
              "' has {.axiomEffect: IOEffect.} but missing {.tags: [AxiomIOEffect].}. " &
              "Add {.tags: [AxiomIOEffect].} for compile-time enforcement. " &
              "See src/core/trusted/effect_bridge.nim", prc)
      else:
        warning("[EffectBridge] '" & procName &
                "' has {.axiomEffect: IOEffect.} but missing {.tags: [AxiomIOEffect].}. " &
                "Add {.tags: [AxiomIOEffect].} for compile-time enforcement. " &
                "See src/core/trusted/effect_bridge.nim", prc)

    # Check: Pure without forbids: [AxiomIOEffect]
    if hasAxiomEffectKind(pragmas, "Pure") and
       not hasEffectTag(pragmas, "AxiomIOEffect"):
      when defined(axiomStrict):
        error("[EffectBridge] '" & procName &
              "' has {.axiomEffect: Pure.} but missing {.forbids: [AxiomIOEffect].}. " &
              "Add {.forbids: [AxiomIOEffect].} for compile-time enforcement. " &
              "See src/core/trusted/effect_bridge.nim", prc)
      else:
        warning("[EffectBridge] '" & procName &
                "' has {.axiomEffect: Pure.} but missing {.forbids: [AxiomIOEffect].}. " &
                "Add {.forbids: [AxiomIOEffect].} for compile-time enforcement. " &
                "See src/core/trusted/effect_bridge.nim", prc)

  # Walk the body and check every proc/func
  for child in body:
    case child.kind
    of nnkProcDef, nnkFuncDef:
      checkProc(child)
    of nnkStmtList:
      for sub in child:
        if sub.kind in {nnkProcDef, nnkFuncDef}:
          checkProc(sub)
    else:
      discard

  result = body
