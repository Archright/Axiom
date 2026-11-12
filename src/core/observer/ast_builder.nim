import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## observer/ast_builder.nim — AST memoization
## IdentCache/ConfigRef 1회 생성, 792 파일 재사용.
## I/O boundary: ProjectMap에서 이미 읽힌 데이터만 사용.
##
## Key optimization: quality_gate.nim creates newIdentCache()/newConfigRef()
## per file (792 times). This module creates them ONCE and reuses.

import std/[tables, times]
import compiler/[ast, parser, llstream, idents, options, pathutils]
import core/types/results
import core/utils/axiom_error
import ./types

func countDefs(node: PNode; kind: TNodeKind): int {.raises: [].} =
  if node == nil: return 0
  if node.kind == kind: result = 1
  for i in 0 ..< node.len:
    result += countDefs(node[i], kind)

proc parseFileAST(content: string; filePath: string;
                  cache: IdentCache; config: ConfigRef): Result[PNode, AxiomError] {.
  raises: [].} =
  {.push warning[BareExcept]: off.}
  try:
    if content.len == 0: return err(parseError("empty content: " & filePath))
    var stream = llStreamOpen(content)
    let absFile = AbsoluteFile(filePath)
    var p: Parser
    openParser(p, absFile, stream, cache, config)
    let ast = parseAll(p)
    closeParser(p)
    return ok(ast)
  except CatchableError as e:
    return err(parseError("parseFileAST: " & filePath & ": " & e.msg))
  except Exception as e:
    return err(parseError("parseFileAST (unexpected): " & filePath & ": " & e.msg))
  {.pop.}

proc buildASTCache*(pm: ProjectMap): ASTCache {.raises: [].} =
  ## Build AST cache for entire project.
  ## Creates ONE IdentCache and ONE ConfigRef — shared across all 792 files.
  ## This eliminates ~21,384 redundant compiler object allocations.
  ##
  ## Import extraction is NOT done here — it's handled by import_encapsulation_gate
  ## and logging_policy_gate via string parsing (more reliable for their use cases).
  ## This cache focuses on AST-based proc/func counting for quality metrics.
  let startTime = epochTime()
  result = types.astCache()

  # Single IdentCache + ConfigRef for entire scan
  let identCache = newIdentCache()
  let configRef = newConfigRef()

  for relPath in pm.sortedPaths:
    let entry = pm.files.getOrDefault(relPath)
    if entry.content.len == 0: continue

    let parseRes = parseFileAST(entry.content, entry.path, identCache, configRef)
    if parseRes.isOk:
      let node = parseRes.get
      let procCount = countDefs(node, nkProcDef)
      let funcCount = countDefs(node, nkFuncDef)
      result.entries[relPath] = ASTEntry(
        imports: @[],  # Extracted separately by gate runners via string parsing
        procCount: procCount,
        funcCount: funcCount
      )
      inc result.totalParsed
    else:
      inc result.totalFailed

  result.parseDurationMs = (epochTime() - startTime) * 1000.0

{.pop.}
