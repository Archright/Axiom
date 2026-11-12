## sync_decisions.nim - Decision Knowledge Graph compiler
## Generates decisions_graph.json from ADR files and code annotations

import std/[json, os, strutils, algorithm], osproc, checksums/sha2

include "src/core/decision_types.nim"

const
  OutputPath = "data/decisions_graph.json"
  ProjectRootAnchor = ".axiom_root"

func stringsToJson(items: seq[string]): JsonNode =
  result = newJArray()
  for item in items:
    result.add(%item)

proc findProjectRoot(): string =
  var dir = getCurrentDir()
  while true:
    if fileExists(dir / ProjectRootAnchor):
      return dir
    if fileExists(dir / "axiom.toml"):
      return dir
    let parent = dir.parentDir()
    if parent == dir:
      quit("ERROR: " & ProjectRootAnchor & " not found. Run from Axiom project directory.")
    dir = parent

proc toRelPath(absPath, projectRoot: string): string =
  if absPath.startsWith(projectRoot):
    let rel = absPath[projectRoot.len .. ^1]
    if rel.startsWith("/"):
      rel[1 .. ^1]
    else:
      rel
  else:
    absPath

proc extractPragmaField(body, key: string): string =
  # Search for key followed by optional whitespace, =, optional whitespace, "
  var idx = 0
  while idx < body.len:
    idx = body.find(key, idx)
    if idx < 0:
      return ""
    # Check that the character before key is not an alphanumeric (avoid partial matches)
    if idx > 0 and body[idx - 1].isAlphaNumeric:
      idx += key.len
      continue
    # Skip past the key
    var pos = idx + key.len
    # Skip whitespace
    while pos < body.len and body[pos] in {' ', '\t'}:
      inc pos
    # Must be '='
    if pos >= body.len or body[pos] != '=':
      idx += key.len
      continue
    inc pos
    # Skip whitespace
    while pos < body.len and body[pos] in {' ', '\t'}:
      inc pos
    # Must be opening quote
    if pos >= body.len or body[pos] != '"':
      idx += key.len
      continue
    inc pos
    let valStart = pos
    while pos < body.len and body[pos] != '"':
      inc pos
    if pos >= body.len:
      return ""
    result = body[valStart ..< pos]
    return
  return ""

proc scanSourceForDecisions(projectRoot: string): seq[DecisionNode] =
  let srcDir = projectRoot / "src"
  if not dirExists(srcDir):
    return @[]
  for file in walkDirRec(srcDir):
    if not file.endsWith(".nim"):
      continue
    let content = readFile(file)
    var i = 0
    while i < content.len:
      let pragmaStart = content.find("{.axiomDecision(", i)
      if pragmaStart < 0:
        break
      let bodyStart = pragmaStart + "{.axiomDecision(".len
      var depth = 1
      var j = bodyStart
      while j < content.len and depth > 0:
        if content[j] == '(':
          inc depth
        elif content[j] == ')':
          dec depth
        inc j
      if depth != 0:
        i = pragmaStart + 1
        continue
      let closeIdx = j - 1
      let body = content[bodyStart ..< closeIdx]
      let id = extractPragmaField(body, "id")
      if id.len > 0 and (id.startsWith("DECISION-") or id.startsWith("ADR-")):
        let reason = extractPragmaField(body, "reason")
        let adr = extractPragmaField(body, "adr")
        let introduced = extractPragmaField(body, "introduced")
        result.add(DecisionNode(
          id: id,
          category: dcArchitecture,
          title: reason,
          rationale: reason,
          files: @[toRelPath(file, projectRoot)],
          dependsOn: @[],
          status: dsAccepted,
          date: introduced
        ))
      i = closeIdx + 1

const
  DecisionSpec* = [
    DecisionNode(
      id: "ADR-0001",
      category: dcSafety,
      title: "Fail-Closed Result Type",
      rationale: "The Axiom integrity engine must guarantee that any verification failure is surfaced, never silently swallowed. Adopt a fail-closed result type pattern across all core modules.",
      files: @["src/core/types/result_types.nim"],
      dependsOn: @[],
      status: dsAccepted,
      date: "2026-03-01"
    ),
    DecisionNode(
      id: "ADR-0002",
      category: dcArchitecture,
      title: "PEG Parser Migration",
      rationale: "Axiom needs a reliable, maintainable parser for its domain-specific configuration formats. Migrate to a PEG parser library with declarative grammar rules generated at build time.",
      files: @["src/core/parser/peg.nim"],
      dependsOn: @[],
      status: dsAccepted,
      date: "2026-03-15"
    ),
    DecisionNode(
      id: "ADR-0003",
      category: dcPerformance,
      title: "DAG Parallel Execution",
      rationale: "Gate execution has linear dependencies but many can execute in parallel. Model gate dependencies as a DAG and schedule independent nodes for concurrent execution using malebolgia.",
      files: @["src/gate/orchestrator/dag_scheduler.nim"],
      dependsOn: @["ADR-0004"],
      status: dsAccepted,
      date: "2026-04-01"
    ),
    DecisionNode(
      id: "ADR-0004",
      category: dcArchitecture,
      title: "SSOT Gate Registry",
      rationale: "Gate metadata was scattered across multiple sources causing drift. Establish src/gate/topology_spec.nim as the single source of truth and generate all downstream artifacts from it.",
      files: @["src/gate/topology_spec.nim", "tools/sync_topology.nim"],
      dependsOn: @[],
      status: dsAccepted,
      date: "2026-04-15"
    ),
    DecisionNode(
      id: "ADR-0005",
      category: dcArchitecture,
      title: "Predicate-Based Gates",
      rationale: "Early gate implementations mixed routing logic with verification logic. Separate gate behavior into predicates (what conditions trigger the gate) and runners (what verification executes).",
      files: @["src/gate/runners/", "src/gate/predicates/"],
      dependsOn: @["ADR-0004"],
      status: dsAccepted,
      date: "2026-05-01"
    ),
    DecisionNode(
      id: "ADR-0006",
      category: dcPerformance,
      title: "CAS Cache Engine",
      rationale: "Running the full gate suite on every commit was too slow. Implement a content-addressable storage cache keyed by SHA-256 hashes of gate inputs to skip unchanged gate executions.",
      files: @["src/gate/cache/cas_cache.nim"],
      dependsOn: @["ADR-0004"],
      status: dsAccepted,
      date: "2026-05-15"
    ),
    DecisionNode(
      id: "ADR-0007",
      category: dcSafety,
      title: "PR Coverage Bot",
      rationale: "Pull requests introducing new code often bypass verification gates. Deploy an automated bot that reviews every pull request for gate coverage recorded in the receipt log.",
      files: @["src/gate/bot/pr_coverage_bot.nim"],
      dependsOn: @["ADR-0006"],
      status: dsAccepted,
      date: "2026-05-15"
    ),
    DecisionNode(
      id: "ADR-0008",
      category: dcSafety,
      title: "Theater Prohibition",
      rationale: "Patterns emerged that created the appearance of rigor without actual guarantees. Formalize the theater prohibition policy — any code claiming a guarantee while guaranteeing nothing is theater.",
      files: @["AGENTS.md", "data/debt_registry.json"],
      dependsOn: @["ADR-0005"],
      status: dsAccepted,
      date: "2026-05-15"
    ),
    DecisionNode(
      id: "ADR-0009",
      category: dcArchitecture,
      title: "Decision Binding Framework",
      rationale: "Stateless agent sessions cannot discover the 'why' behind decisions. Implement a 4-pillar push-based decision narrative system: AST annotation pragma, Decision Knowledge Graph, Context IR 2.0 lazy injection, and a native deterministic linter with grandfathering waivers.",
      files: @["docs/adr/0009-decision-binding-framework.md", "docs/spec/decision_binding_framework.md", "config/decision_binding.waiver.toml", "config/decision_binding.waiver.json", "tools/sync_decisions.nim", "tools/decision_binding_checker.nim"],
      dependsOn: @[],
      status: dsAccepted,
      date: "2026-07-31"
    ),
    DecisionNode(
      id: "ADR-0010",
      category: dcArchitecture,
      title: "CI Baseline Gate & Ephemeral Proof Pipeline",
      rationale: "CI baseline check risked becoming a meaningless gate due to fail-open/fail-closed ambiguity and empty cert directories on clean checkouts. Adopt a single hydrate path, macro I/O isolation, provenance truth separation, baseline exit contract, and volatile local vault to prevent proof regression and theater.",
      files: @["src/cli/baseline_cli.nim", "src/cli/shared/baseline_snapshot_core.nim", "src/verification/certificates/", "docs/spec/hermetic_gate_framework.md"],
      dependsOn: @[],
      status: dsAccepted,
      date: "2026-08-03"
    ),
    DecisionNode(
      id: "ADR-0011",
      category: dcSafety,
      title: "VKD Target Ratchet",
      rationale: "VKD target could be silently under-selected, starving the VKD numerator and inflating apparent coverage. Adopt a monotonic ratchet formula max(cliLimit, ceil(kernelTotal x targetVkd) + 1, kernelTotal) with a kernelTotal floor for full kernel scope, fail-closed degenerate branches, and verifiableOnly+pureOnly certificate selection so every cert counts toward VKD.",
      files: @["src/verification/batch_uap/ir_pipeline_runner.nim", "docs/adr/0011-vkd-target-ratchet.md"],
      dependsOn: @["ADR-0009", "ADR-0010"],
      status: dsAccepted,
      date: "2026-08-06"
    ),
  ]

proc generateDecisionGraph(projectRoot: string): JsonNode =
  var allNodes = @DecisionSpec
  let pragmaNodes = scanSourceForDecisions(projectRoot)
  allNodes.add(pragmaNodes)
  # Deterministic total order: 5 duplicate ids exist (DECISION-0310/0623/0627/
  # 0634/0635), so id-only sort is unstable across filesystem walk orders —
  # observed as cross-environment fingerprint drift on the CX23 runner
  # (run 32928413223). Tie-break on content fields.
  allNodes.sort(proc(a, b: DecisionNode): int =
    # NOTE: Nim's `or` is bitwise OR — using it to chain cmp results destroys
    # sign information (observed as cross-environment drift, run 32930956333).
    block:
      var c = cmp(a.id, b.id)
      if c != 0: return c
      c = cmp(a.title, b.title)
      if c != 0: return c
      c = cmp(a.rationale, b.rationale)
      if c != 0: return c
      c = cmp(a.date, b.date)
      if c != 0: return c
      cmp(system.`$`(a.files), system.`$`(b.files)))
  var buf = ""
  for node in allNodes:
    buf.add(node.id & "|" & $node.category & "|" & node.title & "|" & $node.status & "|" & node.date & ";")
  result = %*{
    "version": 1,
    "fingerprint": $secureHash(Sha_256, buf),
    "generatedBy": "tools/sync_decisions.nim",
    "nodes": newJArray()
  }
  for node in allNodes:
    result["nodes"].add(%*{
      "id": node.id,
      "category": $node.category,
      "title": node.title,
      "rationale": node.rationale,
      "files": stringsToJson(node.files),
      "dependsOn": stringsToJson(node.dependsOn),
      "status": $node.status,
      "date": node.date
    })

proc main() =
  let args = commandLineParams()
  let ciDriftCheck = "--ci-drift-check" in args

  let projectRoot = findProjectRoot()
  let graph = generateDecisionGraph(projectRoot)
  writeFile(OutputPath, graph.pretty())
  echo "[sync_decisions] Generated " & OutputPath & " with " & $graph["nodes"].len & " nodes"

  if ciDriftCheck:
    let exitCode = execCmdEx("git diff --exit-code " & OutputPath).exitCode
    if exitCode != 0:
      quit("[sync_decisions] DRIFT DETECTED: " & OutputPath & " would change. Run 'nim r tools/sync_decisions.nim' locally and commit the results.", 1)
    else:
      echo "[sync_decisions] No drift detected — " & OutputPath & " is in sync"

when isMainModule:
  main()
