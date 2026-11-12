import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## Context Monad — Compile-time global state migration to PipelineContext
##
## Provides {.withContext.} macro pragma for automatic PipelineContext injection.
## Addresses the "var PipelineContext effect contamination" problem:
## - Read-only access: noSideEffect compatible
## - Mutation access: explicit MutateContextEffect tag
## - TLS resources (z3ManagerPrivate, globalAuditBuffer) are excluded
##
## Architectural constraints:
## - CP2: {.refines.} compatibility — ctx parameter is filtered during comparison
## - CP5: Z3 resources stay in {.threadvar.}, not migrated

import std/macros
import std/tables
import core/gate/static_project_matrix

# ─── Custom Pragma Definition ────────────────────────────────────────────────

template withContext*() {.pragma.}
  ## Marks a proc for automatic PipelineContext injection.
  ## The macro adds `ctx: ptr PipelineContext` as the first parameter
  ## and transforms global variable accesses to context field accesses.

# ─── Compile-Time Registry ───────────────────────────────────────────────────

var contextProcs {.compileTime.}: seq[string]
  ## Registry of procs marked with {.withContext.}

# ─── Global-to-Context Mapping ───────────────────────────────────────────────
#
# Maps global variable names to PipelineContext field names.
# Excludes TLS resources (CP5):
#   - z3ManagerPrivate: stays in {.threadvar.}
#   - globalAuditBuffer: stays in {.threadvar.}

const globalToContextMap* = {
  "runtimeAxiomRegistry": "astCache",      # P0 — maps to existing astCache field
  "registryLookup": "astCache",            # P0 — maps to existing astCache field
  "manifestProvider": "manifestData",      # manifest_provider 내재화
}.toTable

# ─── Read-Only Handle Types ──────────────────────────────────────────────────
#
# For noSideEffect compatibility, use ptr (not var) for read-only access.
# Mutation requires explicit MutateContextEffect tag.

type
  PipelineContextHandle* = ptr PipelineContext
    ## Read-only handle to PipelineContext.
    ## Compatible with noSideEffect procs.

# ─── Macro Implementation ────────────────────────────────────────────────────

macro withContext*(procDef: untyped): untyped =
  ## Transforms a proc declaration to accept PipelineContext as first parameter.
  ##
  ## Before:
  ##   proc foo*(x: int) {.withContext.} = ...
  ##
  ## After:
  ##   proc foo*(ctx: PipelineContextHandle, x: int) = ...
  ##
  ## The proc body is NOT modified — global variable access remains manual.
  ## This is intentional: automatic body transformation is too risky (CP2).
  result = procDef

  let procName = $procDef[0]
  contextProcs.add(procName)

  # Add ctx parameter as first formal parameter
  let ctxParam = newIdentDefs(ident("ctx"), ident("PipelineContextHandle"))
  result[3].insert(1, ctxParam)

# ─── withContextScope Macro ────────────────────────────────────────────────────

# 기존 withContextScope 매크로 옆에 추가
# proc 외부가 아닌 proc 내부에서만 사용 — 클로저 함정 회피
#
# 사용법:
#   proc myFunc(a: int) =
#     withPipelineContext:
#       currentContext.doSomething(a)
#
# 주의: proc 외부에서 사용하면 클로저 변환 발생 (nimcall→closure)

template withPipelineContext*(body: untyped): untyped =
  ## Binds currentContext to the global PipelineContext handle within proc scope.
  ## Use ONLY inside proc bodies — outside procs, closures are generated instead
  ## of nimcall, breaking noSideEffect compatibility.
  let currentContext {.inject.} = getContextHandle()
  body

macro withContextScope*(body: untyped): untyped =
  ## Transforms all named procs/funcs/methods/iterators/converters in a block
  ## to automatically receive `ctx: PipelineContextHandle` as first parameter.
  ## - Skips anonymous routines but recurses into their bodies
  ## - Skips nested named routines (isNested = true)
  ## - Handles parameterless procs (nnkEmpty formalParams)
  ## - Cross-validates name AND type for ctx detection
  proc transformAstRec(node: NimNode, isNested: bool = false): NimNode =
    if node.kind in {nnkProcDef, nnkFuncDef, nnkMethodDef, nnkIteratorDef, nnkConverterDef}:
      # Anonymous routine: don't transform, but recurse into body
      if node[0].kind == nnkEmpty:
        var copy = node.copyNimTree()
        if copy[6].kind != nnkEmpty:
          copy[6] = transformAstRec(copy[6], isNested = true)
        return copy
      # Nested named routine: skip ctx injection (captured via closure), but recurse into body
      if isNested:
        var copy = node.copyNimTree()
        if copy[6].kind != nnkEmpty:
          copy[6] = transformAstRec(copy[6], isNested = true)
        return copy
      result = node.copyNimTree()
      if result[3].kind == nnkFormalParams:
        # Cross-validation: check name AND type
        var hasCtx = false
        for i in 1 ..< result[3].len:
          let identDefs = result[3][i]
          if identDefs.kind == nnkIdentDefs:
            for j in 0 ..< identDefs.len - 2:
              if $identDefs[j] == "ctx" and
                 identDefs[^2].kind == nnkIdent and
                 $identDefs[^2] == "PipelineContextHandle":
                hasCtx = true
        if not hasCtx:
          let ctxParam = newIdentDefs(ident("ctx"), ident("PipelineContextHandle"))
          result[3].insert(1, ctxParam)
      elif result[3].kind == nnkEmpty:
        let ctxParam = newIdentDefs(ident("ctx"), ident("PipelineContextHandle"))
        result[3] = newTree(nnkFormalParams, newEmptyNode(), ctxParam)
      # Recurse into proc body with isNested = true
      if result[6].kind != nnkEmpty:
        result[6] = transformAstRec(result[6], isNested = true)
      return result
    else:
      result = node.copyNimTree()
      for i in 0 ..< result.len:
        result[i] = transformAstRec(result[i], isNested)
      return result
  result = transformAstRec(body)

# ─── Utility: Get Context from BSS Singleton ─────────────────────────────────

proc getContextHandle*(): PipelineContextHandle {.inline.} =
  ## Returns a read-only handle to the global PipelineContext singleton.
  ## Accesses global state — not noSideEffect.
  result = addr globalPipelineCtx

# ─── Refines Compatibility (CP2) ─────────────────────────────────────────────
#
# The {.refines.} macro in axiom_pragmas.nim compares proc signatures
# between implementation and shadow files. When {.withContext.} adds
# the ctx parameter, the comparison must skip it.
#
# This is handled by modifying axiom_pragmas.nim's extractParamTypes
# to filter out the ctx parameter. See axiom_pragmas.nim CP2 fix.
