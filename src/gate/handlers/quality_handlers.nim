import core/trusted/layer_declaration
axiomLayer "gate"

## quality_handlers.nim — 12 quality gate handlers using predicate composition.
##
## Each handler is a thin wrapper around predicates from ast_predicate.nim.
## Handlers iterate staged files, call relevant predicates, and aggregate results.
##
## Dependency chain (linear fail-closed pipeline):
##   naming-convention → forbidden-except → no-discard-comment → import-style
##   → proc-naming → type-naming → const-naming → var-naming
##   → template-naming → macro-naming → indentation-style → line-length

import gate/gate_registry      # GateContext
import gate/predicates/ast_predicate as pred
import std/[os, strutils]

# ─── Predicate type alias ────────────────────────────────────────────────────

type
  FilePredicate* = proc (filePath: string): bool {.nimcall, gcsafe, raises: [].}

# ─── Helper: check all staged Nim files against a single-file predicate ──────

proc checkAllStaged*(predFn: FilePredicate; ctx: GateContext): bool {.raises: [].} =
  result = false
  for f in ctx.stagedFiles:
    if f.endsWith(".nim") and fileExists(f):
      if predFn(f):
        result = true
        return

# ─── Inline predicate wrappers for config-based checks ───────────────────────

proc pascalCaseViolationCheck(filePath: string): bool {.nimcall, gcsafe, raises: [].} =
  pred.hasNamingViolation(filePath, pred.NamingConfig(style: pred.nsPascalCase))

proc longLineCheck(filePath: string): bool {.nimcall, gcsafe, raises: [].} =
  pred.hasLongLines(filePath, 120)

# ─── Handler 1: Naming Convention Gate ───────────────────────────────────────
# axiom:quality-handler

proc handleNamingConventionGateRunner*(ctx: GateContext): bool {.nimcall, gcsafe, raises: [].} =
  try:
    result = checkAllStaged(pascalCaseViolationCheck, ctx)
  except CatchableError:
    result = true  # Fail gate on error


# ─── Handler 2: Forbidden Except Gate ────────────────────────────────────────
# axiom:quality-handler

proc handleForbiddenExceptGateRunner*(ctx: GateContext): bool {.nimcall, gcsafe, raises: [].} =
  try:
    result = checkAllStaged(pred.hasForbiddenExcept, ctx)
  except CatchableError:
    result = true  # Fail gate on error


# ─── Handler 3: No Discard Without Comment Gate ──────────────────────────────
# axiom:quality-handler

proc handleNoDiscardWithoutCommentGateRunner*(ctx: GateContext): bool {.nimcall, gcsafe, raises: [].} =
  try:
    result = checkAllStaged(pred.hasUndocumentedDiscard, ctx)
  except CatchableError:
    result = true  # Fail gate on error


# ─── Handler 4: Import Style Gate ────────────────────────────────────────────
# axiom:quality-handler

proc handleImportStyleGateRunner*(ctx: GateContext): bool {.nimcall, gcsafe, raises: [].} =
  try:
    let hasWildcard = checkAllStaged(pred.hasWildcardImport, ctx)
    let hasDeep = checkAllStaged(pred.hasDeeplyNestedImport, ctx)
    result = hasWildcard or hasDeep
  except CatchableError:
    result = true  # Fail gate on error


# ─── Handler 5: Proc Naming Gate ─────────────────────────────────────────────
# axiom:quality-handler

proc handleProcNamingGateRunner*(ctx: GateContext): bool {.nimcall, gcsafe, raises: [].} =
  try:
    result = checkAllStaged(pred.hasUnconventionalProcName, ctx)
  except CatchableError:
    result = true  # Fail gate on error


# ─── Handler 6: Type Naming Gate ─────────────────────────────────────────────
# axiom:quality-handler

proc handleTypeNamingGateRunner*(ctx: GateContext): bool {.nimcall, gcsafe, raises: [].} =
  try:
    result = checkAllStaged(pred.hasUnconventionalTypeName, ctx)
  except CatchableError:
    result = true  # Fail gate on error


# ─── Handler 7: Const Naming Gate ────────────────────────────────────────────
# axiom:quality-handler

proc handleConstNamingGateRunner*(ctx: GateContext): bool {.nimcall, gcsafe, raises: [].} =
  try:
    result = checkAllStaged(pred.hasUnconventionalConstName, ctx)
  except CatchableError:
    result = true  # Fail gate on error


# ─── Handler 8: Var Naming Gate ──────────────────────────────────────────────
# axiom:quality-handler

proc handleVarNamingGateRunner*(ctx: GateContext): bool {.nimcall, gcsafe, raises: [].} =
  try:
    result = checkAllStaged(pred.hasUnconventionalVarName, ctx)
  except CatchableError:
    result = true  # Fail gate on error


# ─── Handler 9: Template Naming Gate ─────────────────────────────────────────
# axiom:quality-handler

proc handleTemplateNamingGateRunner*(ctx: GateContext): bool {.nimcall, gcsafe, raises: [].} =
  try:
    result = checkAllStaged(pred.hasUnconventionalTemplateName, ctx)
  except CatchableError:
    result = true  # Fail gate on error


# ─── Handler 10: Macro Naming Gate ───────────────────────────────────────────
# axiom:quality-handler

proc handleMacroNamingGateRunner*(ctx: GateContext): bool {.nimcall, gcsafe, raises: [].} =
  try:
    result = checkAllStaged(pred.hasUnconventionalMacroName, ctx)
  except CatchableError:
    result = true  # Fail gate on error


# ─── Handler 11: Indentation Style Gate ──────────────────────────────────────
# axiom:quality-handler

proc handleIndentationStyleGateRunner*(ctx: GateContext): bool {.nimcall, gcsafe, raises: [].} =
  try:
    result = checkAllStaged(pred.hasInconsistentIndentation, ctx)
  except CatchableError:
    result = true  # Fail gate on error


# ─── Handler 12: Line Length Gate ────────────────────────────────────────────
# axiom:quality-handler

proc handleLineLengthGateRunner*(ctx: GateContext): bool {.nimcall, gcsafe, raises: [].} =
  try:
    result = checkAllStaged(longLineCheck, ctx)
  except CatchableError:
    result = true  # Fail gate on error
