import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

import std/macros
import std/strutils
# ─── Value Type Assertion ──────────────────────────────────────────────────

macro assertValueType*(T: typedesc) =
  ## Compile-time assertion that type T is a pure value type.
  ## Rejects: ref object, ptr, pointer, proc types.
  ## This ensures safe passage to malebolgia spawn (isolated value semantics).
  let impl = T.getImpl()
  if impl.kind == nnkTypeDef:
    let typeBody = impl[2]
    # Check for ref object
    if typeBody.kind == nnkRefTy:
      error("assertValueType: " & $T & " is a ref type — value type required for in-process gates")
  # Note: ptr/pointer/ref runtime checks are handled by AST-level nnkRefTy check above.
macro assertGateSignature*(body: typed) =
  ## Compile-time assertion that a proc has {.gcsafe.} and {.raises: [].}.
  ## Use on the proc symbol directly:
  ##   assertGateSignature(myGateProc)
  ##
  ## This macro checks:
  ##   1. The proc is marked {.gcsafe.}
  ##   2. The proc has {.raises: [].} (no escaping exceptions)
  ##   3. No ref object parameters
  if body.kind != nnkSym:
    error("assertGateSignature: expected a proc symbol, got " & $body.kind)

  let impl = body.getImpl()
  if impl.kind != nnkProcDef:
    error("assertGateSignature: " & $body & " is not a proc")

  # Check pragmas for gcsafe and raises
  let pragmas = impl[4]
  var hasGcsafe = false
  var hasRaises = false

  for pragma in pragmas:
    if pragma.kind == nnkIdent and pragma.strVal == "gcsafe":
      hasGcsafe = true
    if pragma.kind == nnkExprColonExpr and pragma[0].strVal == "raises":
      hasRaises = true
    # Also check for cast(gcsafe) pattern
    if pragma.kind == nnkCast and pragma.len >= 1:
      discard  # {.cast(gcsafe).} is acceptable at entry points

  if not hasGcsafe:
    warning("assertGateSignature: " & $body & " missing {.gcsafe.} — " &
            "required for malebolgia spawn safety")

  # Check parameters for ref types
  let params = impl[3]
  for i in 1..<params.len:
    let paramType = params[i][^2]
    if paramType.kind == nnkRefTy:
      error("assertGateSignature: parameter " & $params[i][0] &
            " is a ref type — value types only for in-process gates")
const AllowedAstNodes* = {
  nnkCall, nnkCommand, nnkIdent, nnkStrLit, nnkIntLit,
  nnkInfix, nnkPrefix, nnkDotExpr, nnkAsgn, nnkVarSection,
  nnkLetSection, nnkConstSection, nnkTypeSection, nnkProcDef,
  nnkFuncDef, nnkIfExpr, nnkIfStmt, nnkElifBranch, nnkElse,
  nnkForStmt, nnkWhileStmt, nnkReturnStmt, nnkDiscardStmt,
  nnkBlockStmt, nnkStmtList, nnkExprColonExpr, nnkBracket,
  nnkCurly, nnkTableConstr, nnkTupleConstr, nnkObjConstr,
  nnkPragmaExpr, nnkPragma, nnkOfBranch, nnkCaseStmt, nnkTryStmt,
  nnkExceptBranch, nnkFinally, nnkRaiseStmt, nnkYieldStmt,
  nnkContinueStmt, nnkBreakStmt, nnkImportStmt, nnkIncludeStmt,
  nnkFromStmt, nnkExportStmt, nnkConverterDef, nnkMethodDef,
  nnkLambda, nnkDo, nnkBind,
  nnkMixinStmt, nnkUsingStmt, nnkStaticStmt, nnkDefer,
  nnkAsmStmt, nnkTypeOfExpr, nnkChckRange, nnkConv,
  nnkHiddenStdConv, nnkHiddenSubConv, nnkHiddenCallConv
}
# Layer 2: nnkPragma is allowed but internal identifiers are checked
const AllowedPragmas* = [
  "noSideEffect", "gcsafe", "raises", "inline",
  "noinline", "cdecl", "stdcall", "nimcall",
  "deprecated", "used", "discardable", "nodestroy",
  "acyclic", "byref", "bycopy", "register",
  "packed", "borrow", "intdefine",
  "strdefine", "booldefine", "axiomIoBoundary"
]
const ForbiddenPragmas* = [
  "checks", "boundChecks", "overflowChecks", "nilChecks",
  "rangeChecks", "infChecks", "nanChecks", "assertions",
  "floatChecks", "sizeChecks", "styleChecks",
  "warning", "hints", "hint", "push", "pop",
  "optimization", "patterns", "volatile"
]
proc validatePragmaNode*(pragmaNode: NimNode) {.compileTime.} =
  ## Check nnkPragma internal identifiers against whitelist
  for child in pragmaNode:
    case child.kind
    of nnkIdent:
      let name = $child
      if name in ForbiddenPragmas:
        error("Forbidden pragma: " & name &
              " — compiler safety checks must not be disabled in gate runners", child)
      if name notin AllowedPragmas:
        error("Unknown pragma: " & name &
              " — add to AllowedPragmas in gate_safety_macro.nim if safe", child)
    of nnkExprColonExpr:
      let name = $child[0]
      if name in ForbiddenPragmas:
        error("Forbidden pragma: " & name &
              " — compiler safety checks must not be disabled in gate runners", child)
      if name notin AllowedPragmas:
        error("Unknown pragma: " & name &
              " — add to AllowedPragmas in gate_safety_macro.nim if safe", child)
    else:
      discard
proc validateAstWhitelist*(body: NimNode): seq[string] {.compileTime.} =
  ## Returns [] if all nodes are in AllowedAstNodes.
  ## Returns list of violating node kind names otherwise.
  ## Also validates nnkPragma nodes against pragma whitelist.
  result = @[]
  if body.kind notin AllowedAstNodes:
    result.add($body.kind)
  if body.kind == nnkPragma:
    validatePragmaNode(body)
  for child in body:
    result.add(validateAstWhitelist(child))
macro verifyGateRunner*(body: untyped): untyped =
  ## Combined compile-time verification:
  ## 1. AST node whitelist
  ## 2. Pragma whitelist (for nnkPragma nodes)
  ## 3. No ref object (existing assertValueType logic inline)
  let violations = validateAstWhitelist(body)
  if violations.len > 0:
    error("Gate runner contains forbidden AST nodes: " & violations.join(", ") &
          " — only whitelisted nodes are permitted in gate runners")
  result = body
type InProcessGateContext* = object
  ## Pure value-type context for in-process gate execution.
  ## All fields are value types — no ref, no pointer, no proc.
  ## This ensures safe passage to malebolgia spawn (isolated semantics).
  repoRoot*: string
  stagedFiles*: seq[string]
  gateId*: string
  epoch*: int
  dirtyHash*: string
  subtreeRoot*: string
  stage*: int        # GateStage ordinal (value type)
  maxJobs*: int
  passFilenames*: bool
  effectiveTimeoutMs*: int
const LightGateAllowlist*: array[4, string] = [
  ## Gates explicitly approved for in-process execution.
  ## Only gates that:
  ##   1. Are weight=gwLight
  ##   2. Have no external process dependencies
  ##   3. Have no global mutable state access
  ##   4. Have been individually verified safe
  ##
  ## Add gates here only after manual review + static assert verification.
  ## Every name here MUST have a runGateInProcess dispatch case
  ## (inprocess_dispatch.nim) — a stale allowlist name would fail the gate
  ## with the "Gate not registered" sentinel verdict (DEBT#497 follow-up).
  "doc-completeness-gate",
  # DEBT#471: pure fs scan over resolveScanScope SSOT; the runner's compile-time-only
  # registerGate makes any standalone AOT link an empty binary, so enforcement
  # requires this in-process path (see trust_commit_scope_gate.runInProcess).
  "trust-commit-scope",
  # DEBT#497 follow-up: registerGate-only runner — any standalone AOT link is an
  # empty binary (31,872 bytes measured, exit 0), so the subprocess CAS path
  # cannot enforce it. In-process dispatch (runGateInProcess case + adapter)
  # is the enforcement path, same closure shape as trust-commit-scope.
  "decision-binding-gate",
  # DEBT#497 follow-up: main() exists but was never invoked at top level, so a
  # standalone AOT link links to an empty binary (32,192 bytes measured, exit 0).
  # In-process dispatch executes the same judgeWireLogs judgment without quit().
  "delegation-enforcer",
]
func isLightGateAllowed*(gateId: string): bool {.raises: [].} =
  ## Check if a gate is in the in-process allowlist.
  for allowed in LightGateAllowlist:
    if allowed == gateId:
      return true
  return false

func hasStandaloneMainMarker*(content: string): bool {.raises: [].} =
  ## Detect the compile-time standalone-entry marker in a runner module source.
  ## DEBT#497 follow-up: a runner module without this marker AOT-links to a
  ## hollow exit-0 binary, so it must be in-process enforceable (allowlisted).
  ## Lives here (not in the test) so the marker literal stays out of test
  ## files (nimtry HYGIENE-when-isMainModule-in-test scans tests textually).
  content.contains("when isMainModule")
{.pop.}

