import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

## Independent SoundnessOracle — symbol-level expected affectedness via two axes.
##
## Axis 1: Catalog-based — reads expectedAffected from symbol_mutation_catalog.json.
## Axis 2: Independent reference — naive file→symbol exact match (no transitive closure).
##
## Contract sentence 1: the oracle is implementation-independent from the selector.
## These functions compute ExpectedAffected(Δ) without sharing closure code with
## the selector. Containment check: ExpectedAffected ⊆ Selected must hold for
## selector soundness (canonical_execution_semantics.md §4.2).

import std/[json, sequtils, strutils, sets, algorithm]
import core/crypto/hash_kernel
import infrastructure/cas_index

# ---------------------------------------------------------------------------
# expectedAffected — catalog axis
# ---------------------------------------------------------------------------

func expectedAffected*(catalog: JsonNode, changedFiles: seq[string]): seq[string] = 
  ## Oracle from symbol_mutation_catalog.json: collect expectedAffected for
  ## matching triggerFiles. Deterministic: sorted results.
  ##
  ## catalog: root JsonNode of symbol_mutation_catalog.json (JSON array)
  ## changedFiles: git diff --name-status output (file paths only)
  ## Returns: seq[string] of VKS symbols (modulePath::functionName) expected affected
  ## by the catalog axis, sorted deterministically.
  if catalog.kind != JArray:
    return @[]  # malformed catalog

  var affected = initHashSet[string]()
  let changedFileSet = toHashSet(changedFiles)

  for entry in catalog.items:
    if entry.kind != JObject:
      continue
    if not entry.hasKey("triggerFile"):
      continue
    let triggerFile = entry["triggerFile"].getStr()
    if triggerFile.len > 0 and triggerFile in changedFileSet:
      if not entry.hasKey("expectedAffected"):
        continue
      let expected = entry["expectedAffected"]
      if expected.kind == JArray:
        for symbolNode in expected.items:
          if symbolNode.kind == JString:
            let symbol = symbolNode.getStr()
            if symbol.len > 0:
              affected.incl(symbol)

  result = toSeq(affected)
  result.sort(cmp)

# ---------------------------------------------------------------------------
# independentReferenceAffected — independent reference axis
# ---------------------------------------------------------------------------

func independentReferenceAffected*(changedFiles: seq[string], universe: seq[string]): seq[string] = 
  ## Independent reference: direct file→symbol exact match (no transitive closure).
  ## Deliberately different algorithm from selector's BFS closure.
  ##
  ## changedFiles: git diff --name-status output (file paths only)
  ## universe: VKS symbols in modulePath::functionName format
  ## Returns: seq[string] of symbols whose sourceFile exactly equals a changed file
  ## (no transitive closure), sorted deterministically.
  ##
  ## Example: changedFiles = @["src/core/foo.nim"], universe = @["src/core/foo.nim::bar", "src/core/baz.nim::qux"]
  ## Returns: @["src/core/foo.nim::bar"] (only symbols with exact sourceFile match)
  var affected = initHashSet[string]()
  let changedFileSet = toHashSet(changedFiles)

  for symbol in universe:
    # Split symbol into modulePath and functionName
    let pos = symbol.find("::")
    if pos >= 0:
      let sourceFile = symbol[0..<pos]
      if sourceFile in changedFileSet:
        affected.incl(symbol)

  result = toSeq(affected)
  result.sort(cmp)

# ---------------------------------------------------------------------------
# checkContainment — ExpectedAffected ⊆ Selected
# ---------------------------------------------------------------------------

func checkContainment*(expectedAffected: seq[string], selected: seq[string]): tuple[ok: bool, missing: seq[string]] = 
  ## Verify soundness containment: ExpectedAffected ⊆ Selected.
  ## Returns (ok, missing) where ok=true iff every expected symbol is selected.
  ##
  ## expectedAffected: oracle output (sorted, no duplicates)
  ## selected: selector output (sorted, no duplicates)
  ## Returns: ok=true if ExpectedAffected ⊆ Selected, missing=list of expected but not selected
  ## Both inputs are assumed to be sorted; output missing is sorted.
  ##
  ## This is the core soundness check: if the selector's Selected set contains
  ## all symbols that the independent oracle expects to be affected, the selector
  ## is sound for this change (modulo the oracle being a conservative lower-bound).

  if expectedAffected.len == 0:
    return (ok: true, missing: @[])

  var selectedSet = initHashSet[string]()
  for s in selected:
    selectedSet.incl(s)

  var missing = initHashSet[string]()
  for symbol in expectedAffected:
    if symbol notin selectedSet:
      missing.incl(symbol)

  (ok: missing.len == 0, missing: toSeq(missing).sorted(cmp))

{.pop.}