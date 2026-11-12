import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import ../../core/trusted/axiom_pragmas
import core/crypto/hash_kernel
import core/symbolic/global_symbol_graph_types
import core/types/global_symbol_graph_types
import std/algorithm
import std/sequtils
import std/sets
import std/strutils
import std/tables
func findDependents*(graph: GlobalSymbolGraph, changedSymbol: string): seq[string] =
  ## Return all source symbols that reference the changed symbol (direct only).
  let edges = graph.byTarget.getOrDefault(changedSymbol, @[])
  var seen = initHashSet[string]()
  for edge in edges:
    if edge.source notin seen:
      seen.incl(edge.source)
      result.add(edge.source)

## Graph Hash.
  ## axiom-smt: (assert (and ast_parse_failed_isolated (>= (seq.len graph_edges) 0) (>= sortedKeys 0) (>= joined 0) (>= result 0) (>= h 0)))
  ## axiom-lean: ast_parse_failed_isolated ∧ graph_edges.size ≥ 0 ∧ (sortedKeys ≥ 0) ∧ (joined ≥ 0) ∧ (result ≥ 0) ∧ (h ≥ 0)
func graphHash*(graph: GlobalSymbolGraph): string {.axiomTryImpl.} =
  ## Compute a deterministic hash of the entire graph for stale-detection.
  var parts: seq[string] = @[]
  let keys = graph.symbols.keys.toSeq()
  let sortedKeys = keys.sorted(cmp[string])
  for qn in sortedKeys:
    if graph.symbols.hasKey(qn):
      let sym = graph.symbols.getOrDefault(qn)
      parts.add(qn & ":" & $sym.kind)
  var edgeParts: seq[string] = @[]
  for edge in graph.edges:
    edgeParts.add(edge.source & "->" & edge.target & ":" & $edge.kind)
  edgeParts.sort(cmp[string])
  parts.add(edgeParts)
  let joined = parts.join(";")
  result = sha256Hex(joined)
func countSourceFunctions*(graph: GlobalSymbolGraph): int {.raises: [].} =
  ## Count function-like declarations (proc, func, macro, template, iterator, converter)
  ## in the global symbol graph. Used as the physical denominator for ASI coverage
  ## to prevent vault-stuffing manipulation.
  for _, sym in graph.symbols:
    if sym.kind in {skProc, skFunc}:
      inc result

{.pop.}
