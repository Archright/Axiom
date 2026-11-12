import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## Feature Macro — Compile-Time Gherkin Parser (Phase 2)
##
## Reads .feature files at compile time via staticRead, parses Gherkin syntax,
## and emits Nim test code through a compile-time mapping table.
##
## Design:
##   - staticRead(path) → string → Gherkin AST (compileTime)
##   - TestStep object: (keyword, text, line)
##   - CompileTime mapping: {step_text: proc_name}
##   - Line-numbered error messages via {.error.} pragma
##
## Anchor: currentSourcePath() for path resolution (Context7 verified)

import std/[macros, strutils, sequtils, tables]

type
  StepKeyword* = enum
    skGiven = "Given"
    skWhen  = "When"
    skThen  = "Then"
    skAnd   = "And"
    skBut   = "But"

  TestStep* = object
    keyword*: StepKeyword
    text*: string
    line*: int          ## 1-based line number in .feature file

  Scenario* = object
    name*: string
    tags*: seq[string]
    line*: int
    steps*: seq[TestStep]

  Feature* = object
    name*: string
    description*: seq[string]
    tags*: seq[string]
    background*: seq[TestStep]
    scenarios*: seq[Scenario]

  StepMapping* = Table[string, string]
    ## Maps step text (normalized) → Nim proc name

# ── Compile-Time Parser ──────────────────────────────────────────────────────

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func parseStepKeyword(text: string): StepKeyword =
  ## Parse the keyword prefix from a step line.
  let trimmed = text.strip()
  if trimmed.startsWith("Given"): skGiven
  elif trimmed.startsWith("When"): skWhen
  elif trimmed.startsWith("Then"): skThen
  elif trimmed.startsWith("And"): skAnd
  elif trimmed.startsWith("But"): skBut
  else: skGiven  # fallback

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func normalizeStepText(text: string): string =
  ## Strip keyword prefix and normalize whitespace.
  result = text.strip()
  for kw in ["Given ", "When ", "Then ", "And ", "But "]:
    if result.startsWith(kw):
      result = result[kw.len .. ^1].strip()
      break
  # Normalize multiple spaces to single
  while "  " in result:
    result = result.replace("  ", " ")

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func parseFeature*(content: string; sourcePath: string = ""): Feature =
  ## Parse Gherkin content into a Feature AST.
  ## All at compile time — no IO, pure string transformation.
  result = Feature()
  var currentScenario: Scenario
  var inBackground = false
  var inScenario = false
  var lineNum = 0
  var pendingTags: seq[string] = @[]  ## Tags buffered for next Scenario

  for line in content.splitLines():
    inc lineNum
    let trimmed = line.strip()

    # Skip empty lines and comments
    if trimmed.len == 0 or trimmed.startsWith("#"):
      continue

    # Tags — buffer for next declaration
    if trimmed.startsWith("@"):
      let tags = trimmed.splitWhitespace()
      pendingTags.add(tags)
      continue

    # Feature declaration — consume pending tags
    if trimmed.startsWith("Feature:"):
      result.name = trimmed["Feature:".len .. ^1].strip()
      result.tags.add(pendingTags)
      pendingTags = @[]
      continue

    # Background
    if trimmed.startsWith("Background:"):
      inBackground = true
      inScenario = false
      pendingTags = @[]  # discard tags on Background
      continue

    # Scenario — consume pending tags
    if trimmed.startsWith("Scenario:") or trimmed.startsWith("Scenario Outline:"):
      # Flush previous scenario
      if inScenario and currentScenario.name.len > 0:
        result.scenarios.add(currentScenario)
      let prefix = if trimmed.startsWith("Scenario Outline:"): "Scenario Outline:".len else: "Scenario:".len
      currentScenario = Scenario(
        name: trimmed[prefix .. ^1].strip(),
        tags: pendingTags,
        line: lineNum
      )
      pendingTags = @[]
      inBackground = false
      inScenario = true
      continue

    # Steps (Given/When/Then/And/But)
    let isStep = trimmed.startsWith("Given ") or trimmed.startsWith("When ") or
                 trimmed.startsWith("Then ") or trimmed.startsWith("And ") or
                 trimmed.startsWith("But ")
    if isStep:
      let step = TestStep(
        keyword: parseStepKeyword(trimmed),
        text: normalizeStepText(trimmed),
        line: lineNum
      )
      if inBackground:
        result.background.add(step)
      elif inScenario:
        currentScenario.steps.add(step)
      continue

    # Description lines (only at top level, before any scenario)
    if not inScenario and not inBackground:
      if result.scenarios.len == 0 and trimmed.len > 0:
        result.description.add(trimmed)

  # Flush last scenario
  if inScenario and currentScenario.name.len > 0:
    result.scenarios.add(currentScenario)

# ── Step Mapping Utilities ───────────────────────────────────────────────────

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func matchStep*(step: TestStep; mapping: StepMapping): string =
  ## Look up the Nim proc name for a step. Returns "" if unmapped.
  let normalized = step.text.toLowerAscii()
  mapping.getOrDefault(normalized, "")

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func registerStep*(mapping: var StepMapping; stepText: string; procName: string) =
  ## Register a step text → proc name mapping.
  mapping[stepText.toLowerAscii()] = procName

# ── Code Generation (Macro Layer) ────────────────────────────────────────────

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
macro featureTest*(featurePath: static[string]; mapping: static[StepMapping]; body: untyped = newEmptyNode()): untyped =
  ## Generate test suites from a .feature file at compile time.
  ##
  ## featurePath: relative path from the CALLING file's directory
  ## mapping: compile-time table of step text → proc name
  ##
  ## Emits: suite "FeatureName" with test blocks for each Scenario.
  ## Each step in a scenario calls its mapped proc.
  ## Unmapped steps emit {.error.} with line number.

  # Extract caller file from lineinfo (format: "file.nim(line, col)")
  let infoStr = body.lineinfo
  let parenPos = infoStr.find('(')
  let callerPath = if parenPos > 0: infoStr[0 ..< parenPos] else: infoStr
  let srcDir = callerPath[0 ..< callerPath.rfind('/')]
  let absPath = srcDir & "/" & featurePath
  let content = staticRead(absPath)
  let feature = parseFeature(content, absPath)

  result = newStmtList()

  # Emit suite block
  let suiteName = newStrLitNode(feature.name)
  var suiteBody = newStmtList()

  for scenario in feature.scenarios:
    let testName = newStrLitNode(scenario.name)
    var testBody = newStmtList()

    # Emit background steps first
    for step in feature.background:
      let procName = matchStep(step, mapping)
      if procName.len == 0:
        error(featurePath & "(" & $step.line & "): unmapped background step: " & step.text)
      testBody.add(newCall(ident(procName)))

    # Emit scenario steps
    for step in scenario.steps:
      let procName = matchStep(step, mapping)
      if procName.len == 0:
        error(featurePath & "(" & $step.line & "): unmapped step: " & step.text)
      testBody.add(newCall(ident(procName)))

    suiteBody.add(
      nnkCommand.newTree(
        ident("test"),
        testName,
        testBody
      )
    )

  result.add(
    nnkCommand.newTree(
      ident("suite"),
      suiteName,
      suiteBody
    )
  )

# ── Convenience: auto-generate suite from single feature file ────────────────

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
macro featureSuite*(featurePath: static[string]; body: untyped): untyped =
  ## DSL for defining step mappings inline, then generating tests.
  ##
  ## Usage:
  ##   featureSuite "features/pbt_integrity.feature":
  ##     step "a PBT engine with seed-based deterministic generation":
  ##       setupPbtEngine()
  ##     step "200 DAGs are generated with up to 20 nodes":
  ##       generateDags(200, 20)
  ##     step "every generated DAG must have hasCycle == false":
  ##       verifyAcyclic()
  ##
  ## Each `step` block maps a Gherkin step text to inline Nim code.

  # Extract caller file from lineinfo (format: "file.nim(line, col)")
  let infoStr = body.lineinfo
  let parenPos = infoStr.find('(')
  let callerPath = if parenPos > 0: infoStr[0 ..< parenPos] else: infoStr
  let srcDir = callerPath[0 ..< callerPath.rfind('/')]
  let absPath = srcDir & "/" & featurePath
  let content = staticRead(absPath)
  let feature = parseFeature(content, absPath)

  # Build mapping from body's `step` commands
  var mapping = initTable[string, seq[NimNode]]()
  for stmt in body:
    if stmt.kind == nnkCommand and stmt[0].strVal == "step":
      let stepText = stmt[1].strVal.toLowerAscii()
      let stepBody = stmt[2]
      mapping[stepText] = @[stepBody]

  result = newStmtList()
  let suiteName = newStrLitNode(feature.name)
  var suiteBody = newStmtList()

  for scenario in feature.scenarios:
    let testName = newStrLitNode(scenario.name)
    var testBody = newStmtList()

    # Background steps
    for step in feature.background:
      let key = step.text.toLowerAscii()
      if key in mapping:
        for node in mapping[key]:
          testBody.add(node)
      else:
        error(featurePath & "(" & $step.line & "): unmapped background step: " & step.text)

    # Scenario steps
    for step in scenario.steps:
      let key = step.text.toLowerAscii()
      if key in mapping:
        for node in mapping[key]:
          testBody.add(node)
      else:
        error(featurePath & "(" & $step.line & "): unmapped step: " & step.text)

    suiteBody.add(
      nnkCommand.newTree(ident("test"), testName, testBody)
    )

  result.add(
    nnkCommand.newTree(ident("suite"), suiteName, suiteBody)
  )
