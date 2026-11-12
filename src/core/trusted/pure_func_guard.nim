{.push raises: [].}
## Phase 2B: Syntactic Guard — Compile-time purity enforcement for {.axiom.} funcs.
##
## NOTE: As of IR Pipeline integration (v31), all AST node kinds are handled
## by the IR pipeline's semantic validation. This module's forbidden-node set
## is intentionally empty — all constructs pass through.
##
## The `walkAndGuard` function is a no-op and is retained for backward
## compatibility. Core purity enforcement now lives in the IR pipeline.
##
## AGENTS.md §0.2: Ideal (compile-time), Elegant (AST walk), Fundamental (whitelist),
##                 Deterministic (identical AST → identical verdict).

import core/trusted/layer_declaration
axiomLayer "domain"
import std/macros

# ── Forbidden Node Kinds ──────────────────────────────────────────────────────
# Whitelist approach: only these node kinds trigger a compile error.
const forbiddenNodeKinds*: set[NimNodeKind] = {}

# ── Display Names ─────────────────────────────────────────────────────────────
func nodeKindDisplayName(kind: NimNodeKind): string {.inline, raises: [].} =
  ## Human-readable display name for a forbidden node kind.
  case kind
  of nnkWhileStmt: "while"
  of nnkForStmt: "for"
  else: $kind

# ── Recursive AST Walker ──────────────────────────────────────────────────────
func walkAndGuard*(body: NimNode, funcName: string) {.compileTime.} =
  ## Recursively walk AST body and raise CompileError on forbidden nodes.
  ## Whitelist approach: only rejects known-bad node kinds.
  ## All allowed constructs (let, if, call, infix, recursion) pass through.
  if body.kind in forbiddenNodeKinds:
    error("AXIOM_VIOLATION: func '" & funcName & "' contains '" &
          nodeKindDisplayName(body.kind) &
          "' — {.axiom.} requires pure functional style", body)
  for child in body:
    walkAndGuard(child, funcName)

# ── Public Macro ──────────────────────────────────────────────────────────────
macro pureFuncGuard*(body: untyped): untyped =
  ## Compile-time guard: walks the body AST and rejects non-pure constructs.
  ##
  ## Usage (block guard):
  ##   func myFunc(x: int): int {.axiom.} =
  ##     pureFuncGuard:
  ##       let y = x + 1
  ##       y
  ##
  ## Usage (definition pragma):
  ##   func myFunc(x: int): int {.pureFuncGuard.} =
  ##     let y = x + 1
  ##     y
  ##
  ## Usage (in axiomImpl — integrated guard):
  ##   func myFunc(x: int): int {.axiomImpl.} =
  ##     let y = x + 1
  ##     y
  ##
  ## Note: All node kinds are now permitted by this guard.
  ## Semantic validation is handled by the IR pipeline.
  if body.kind in {nnkFuncDef, nnkProcDef}:
    # Definition mode: extract name and check body
    let funcName = $body[0]
    walkAndGuard(body[^1], funcName)
  else:
    # Block mode: walk the raw statement list
    walkAndGuard(body, "<func>")
  result = body
