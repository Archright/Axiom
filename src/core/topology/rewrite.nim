## Topology Import Rewriter — Pure content transformation rules.
## Uses deterministic string replacement; AST-based rewriting is available
## in infrastructure/topology_executor.nim for callers that need it.

import core/trusted/layer_declaration
axiomLayer "domain"
import std/strutils
import core/topology/topology_types
{.push raises: [].}
# axiomIoBoundary
export topology_types

type
  ImportRewriteRule* = object
    oldPath*: string
    newPath*: string

func rewriteContentImports*(content: string;
                            rules: openArray[ImportRewriteRule]): string {.raises: [].} =
  ## Pure: rewrite imports in source content according to rules.
  result = content
  for rule in rules:
    result = result.replace(rule.oldPath, rule.newPath)

func makeImportRewriteRule*(oldPath, newPath: string): ImportRewriteRule {.raises: [].} =
  result = ImportRewriteRule(oldPath: oldPath, newPath: newPath)

func buildImportRewriteRules*(plan: Plan): seq[ImportRewriteRule] {.raises: [].} =
  ## Convert a Plan into a sequence of ImportRewriteRules.
  result = @[]
  for m in plan.moves:
    let oldModuleName = topologyExtractFilename(m.fromPath).replace(".nim", "")
    let newModuleName = topologyExtractFilename(m.toPath).replace(".nim", "")
    result.add(ImportRewriteRule(oldPath: m.fromPath, newPath: m.toPath))
    if oldModuleName != newModuleName:
      result.add(ImportRewriteRule(oldPath: oldModuleName, newPath: newModuleName))

{.pop}
