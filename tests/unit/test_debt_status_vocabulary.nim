## DEBT#512 — debt status vocabulary has exactly one authority.
##
## data/debt_schema.json definitions.statusEnum.enum is the canonical lifecycle
## vocabulary. The gate must consume it rather than keep a second literal list:
## a reintroduced divergent list (pre-fix: open/closed/deferred/resolved) makes
## the acceptance or rejection tests below fail.

import std/[json, os, unittest]
import gate/runners/debt_integrity_gate

const SchemaRel = "data/debt_schema.json"

let
  repoRoot = getCurrentDir()
  schemaPath = repoRoot / SchemaRel

doAssert fileExists(schemaPath), "run from the repository root: " & repoRoot

proc schemaStatuses(): seq[string] =
  statusVocabulary(parseJson(readFile(schemaPath)))

proc registryContent(status: string): string =
  $(%*{"entries": [%*{"id": "DEBT#999", "severity": "high", "status": status}]})

proc vocabularyDivergences(gate, schema: seq[string]): seq[string] =
  ## Both directions: schema-only values (gate rejects a canonical value) and
  ## gate-only values (gate accepts outside the canonical set). Empty means the
  ## gate vocabulary is closed over the schema vocabulary.
  for value in schema:
    if value notin gate: result.add(value)
  for value in gate:
    if value notin schema: result.add(value)

suite "debt status vocabulary (DEBT#512)":

  test "schema statusEnum is the canonical lifecycle set":
    check schemaStatuses() == @["open", "closed", "accepted", "deferred", "in_progress"]

  test "every schema value is accepted by the gate predicate":
    let canonical = schemaStatuses()
    for status in canonical:
      check matchesStatus(status, canonical)
      check validateDebtRegistryImpl(registryContent(status), canonical).len == 0

  test "non-schema values are rejected":
    let canonical = schemaStatuses()
    for status in ["resolved", "exempted", "Resolved", "OPEN", "in-progress", "", " open"]:
      check not matchesStatus(status, canonical)
      check validateDebtRegistryImpl(registryContent(status), canonical) ==
        @["entry[0].status: invalid"]

  test "gate vocabulary is loaded from the schema, not a second literal":
    let canonical = schemaStatuses()
    let gateVocabulary = loadCanonicalStatuses(repoRoot)
    check gateVocabulary == canonical
    check vocabularyDivergences(gateVocabulary, canonical).len == 0

  test "pre-fix dual vocabulary diverges in both directions (mutation guard)":
    let preFixGateVocabulary = @["open", "closed", "deferred", "resolved"]
    check vocabularyDivergences(preFixGateVocabulary, schemaStatuses()) ==
      @["accepted", "in_progress", "resolved"]