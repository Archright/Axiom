import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
## Sieve-level AST inspector — I/O-dependent safe wrapper.
## Core types and pure procs live in core/interfaces/ast_inspector.nim.
## This module adds inspectAstNodeSafe which requires parseNimRes (I/O boundary).

import compiler/ast
import core/interfaces/ast_inspector
import core/boundary/results_boundary
import core/parser_utils
import core/types/results                # isErr/get on custom Result

# Re-export core types and procs for backward compatibility
export ast_inspector

proc inspectAstNodeSafe*(sourceCode: string; funcName: string = "";
    unsatVars: seq[string] = @[]): AstInspectionResult =
  ## Safe wrapper: parse source → inspect AST. Returns empty result on parse failure.
  ## Cast justification (I/O boundary): parseNimRes is a proc — it invokes
  ## tree-sitter CLI via temp file (parseWithTreeSitter), which is side-effectful.
  ## The cast is the I/O boundary seal: once parsing succeeds, all downstream
  ## work (inspectAstNodeP) is pure func. No external state mutation escapes.
  ## [SEE: nim_effect_system_quirks.md §9.1]
  var parseRes: Result[PNode, string]
  {.cast(noSideEffect).}:
    parseRes = parseNimRes(sourceCode)
  if parseRes.isErr:
    return AstInspectionResult()
  inspectAstNodeP(parseRes.get(), funcName, unsatVars)

{.pop.}

