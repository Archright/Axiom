## scaffold_feature_test.nim
## Gherkin-aware scaffolding tool for Axiom feature tests.
##
## Usage:
##   nim c -r tools/scaffold_feature_test.nim <feature_name> [--force]
##
## Parses tests/features/<name>.feature and generates
## tests/gateway/<name>_feature_test.nim with meaningful stubs
## derived from Scenario names and Given/When/Then steps.

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils]
import tools/generate_test_skeletons
export generate_test_skeletons

const
  FeatureDir = "tests/features"
  OutputDir  = "tests/gateway"
  Suffix     = "_feature_test.nim"

type
  StepKind = enum
    skGiven, skWhen, skThen, skAnd, skBut

  Step = object
    kind: StepKind
    text: string

  Scenario = object
    name: string
    tags: seq[string]
    steps: seq[Step]

  Feature = object
    name: string
    featureTags: seq[string]
    scenarios: seq[Scenario]
    backgroundSteps: seq[Step]

# ─── Name Conversion ──────────────────────────────────────────────

proc capitalize*(s: string): string =
  ## Capitalize first character.
  if s.len == 0: return s
  result = s
  result[0] = result[0].toUpperAscii()

proc sanitizeIdentifier(word: string): string =
  ## Remove all non-alphanumeric characters from a word.
  result = ""
  for ch in word:
    if ch in {'a'..'z', 'A'..'Z', '0'..'9'}:
      result.add(ch)

proc stepToProcName*(kind: StepKind, text: string): string =
  ## "Given" + "the user is logged in" → "givenTheUserIsLoggedIn"
  ## Strips quotes and punctuation, joins words in camelCase.
  var cleaned = text
  # Remove quotes for cleaner proc names
  cleaned = cleaned.replace("\"", " ")
  cleaned = cleaned.replace("'", " ")
  # Replace hyphens with spaces so they become word boundaries
  cleaned = cleaned.replace("-", " ")
  # Remove punctuation that breaks identifiers
  for ch in [',', '.', ':', ';', '(', ')', '!', '?', '[', ']', '{', '}', '/', '\\', '=', '>', '<', '+', '*', '&', '|', '~', '`', '@', '#', '$', '%', '^']:
    cleaned = cleaned.replace($ch, " ")

  let words = cleaned.splitWhitespace()
  let prefix = case kind
    of skGiven: "given"
    of skWhen:  "when"
    of skThen:  "then"
    of skAnd:   "and"
    of skBut:   "but"

  result = prefix
  for i, word in words:
    # Skip common stop words to keep names concise
    let lower = word.toLowerAscii()
    if lower in ["a", "an", "the", "is", "are", "of", "to", "in"]:
      continue
    let sanitized = sanitizeIdentifier(word)
    if sanitized.len == 0:
      continue
    result.add(sanitized.toLowerAscii().capitalize())

  # Fallback: if all words were filtered, use "unnamed"
  if result == prefix:
    result.add("Step")

# ─── Parsing ──────────────────────────────────────────────────────

proc parseStepKind(text: string): StepKind =
  let lower = text.toLowerAscii()
  if lower.startsWith("given"): return skGiven
  if lower.startsWith("when"):  return skWhen
  if lower.startsWith("then"):  return skThen
  if lower.startsWith("and"):   return skAnd
  if lower.startsWith("but"):   return skBut
  # Fallback — should not happen with valid Gherkin
  return skAnd

proc extractStepText(line: string): string =
  ## Extract step text after the keyword. "Given the foo" → "the foo"
  let stripped = line.strip()
  for keyword in ["Given ", "When ", "Then ", "And ", "But ",
                  "given ", "when ", "then ", "and ", "but "]:
    if stripped.startsWith(keyword):
      return stripped[keyword.len .. ^1].strip()
  return stripped

proc extractTagsFromLine(line: string): seq[string] =
  ## Extract @tag tokens from a line.
  result = @[]
  for word in line.strip().splitWhitespace():
    if word.startsWith("@") and word.len > 1:
      result.add(word)

proc indentLevel(line: string): int =
  ## Count leading spaces (2-space indentation assumed).
  result = 0
  for ch in line:
    if ch == ' ': inc result
    else: break

proc isStepKeyword(line: string): bool =
  let stripped = line.strip()
  for keyword in ["Given ", "When ", "Then ", "And ", "But ",
                  "given ", "when ", "then ", "and ", "but "]:
    if stripped.startsWith(keyword):
      return true
  return false

proc parseFeature*(filePath: string): Feature =
  ## Parse a .feature file into a Feature structure.
  result = Feature(name: "", featureTags: @[], scenarios: @[], backgroundSteps: @[])

  let content = readFile(filePath)
  var pendingTags: seq[string] = @[]
  var inBackground = false
  var inScenario = false
  var inDocString = false
  var inExamples = false
  var currentScenario = Scenario(name: "", tags: @[], steps: @[])

  for rawLine in content.splitLines():
    let line = rawLine
    let stripped = line.strip()

    # Skip empty lines
    if stripped.len == 0:
      continue

    # Handle doc strings (""") — toggle, skip content
    if stripped == "\"\"\"":
      inDocString = not inDocString
      continue
    if inDocString:
      continue

    # Skip comments
    if stripped.startsWith("#"):
      continue

    # Feature: line
    if stripped.startsWith("Feature:"):
      # Save pending tags
      result.featureTags = pendingTags
      pendingTags = @[]
      result.name = stripped["Feature:".len .. ^1].strip()
      inBackground = false
      inScenario = false
      inExamples = false
      continue

    # Before Feature: — collect tags
    if result.name.len == 0:
      if stripped.startsWith("@"):
        pendingTags.add(extractTagsFromLine(stripped))
      continue

    # Tags — accumulate for next Scenario/Scenario Outline
    if stripped.startsWith("@"):
      pendingTags.add(extractTagsFromLine(stripped))
      continue

    # Background:
    if stripped.startsWith("Background:"):
      # Save current scenario if pending
      if inScenario and currentScenario.name.len > 0:
        result.scenarios.add(currentScenario)
        currentScenario = Scenario(name: "", tags: @[], steps: @[])
      inBackground = true
      inScenario = false
      inExamples = false
      continue

    # Scenario Outline: (treated as Scenario for scaffolding)
    if stripped.startsWith("Scenario Outline:"):
      if inScenario and currentScenario.name.len > 0:
        result.scenarios.add(currentScenario)
      currentScenario = Scenario(name: "", tags: pendingTags, steps: @[])
      pendingTags = @[]
      currentScenario.name = stripped["Scenario Outline:".len .. ^1].strip()
      inBackground = false
      inScenario = true
      inExamples = false
      continue

    # Scenario:
    if stripped.startsWith("Scenario:"):
      if inScenario and currentScenario.name.len > 0:
        result.scenarios.add(currentScenario)
      currentScenario = Scenario(name: "", tags: pendingTags, steps: @[])
      pendingTags = @[]
      currentScenario.name = stripped["Scenario:".len .. ^1].strip()
      inBackground = false
      inScenario = true
      inExamples = false
      continue

    # Examples: section — skip table rows
    if stripped.startsWith("Examples:"):
      inExamples = true
      continue

    # Skip Examples table rows (lines starting with |)
    if inExamples and stripped.startsWith("|"):
      continue

    # Table rows outside Examples (e.g., step tables) — skip
    if stripped.startsWith("|"):
      continue

    # Steps
    if isStepKeyword(stripped):
      inExamples = false
      let step = Step(
        kind: parseStepKind(stripped),
        text: extractStepText(stripped)
      )
      if inBackground:
        result.backgroundSteps.add(step)
      elif inScenario:
        currentScenario.steps.add(step)
      continue

  # Flush last scenario
  if inScenario and currentScenario.name.len > 0:
    result.scenarios.add(currentScenario)

# ─── Generation ────────────────────────────────────────────────────

proc generateTest*(feature: Feature, featureName: string): string =
  ## Generate the feature test .nim file content.
  let featureFile = FeatureDir / (featureName & ".feature")

  result = "## " & feature.name & " Feature Test\n"
  result.add("## Covers: " & featureFile & "\n")
  result.add("## Auto-generated by tools/scaffold_feature_test.nim\n")
  result.add("## DO NOT EDIT — re-run scaffold to regenerate.\n")
  result.add("\n")
  result.add("import std/unittest\n")
  result.add("# REQUIRED: import the module(s) under test before running\n")
  result.add("\n")

  result.add("suite \"Feature: " & feature.name & "\":\n")

  for scenario in feature.scenarios:
    result.add("\n")
    result.add("  test \"" & scenario.name & "\":\n")

    # Background steps as comments (if any)
    if feature.backgroundSteps.len > 0:
      result.add("    # ── Background ──\n")
      for step in feature.backgroundSteps:
        let kindStr = case step.kind
          of skGiven: "Given"
          of skWhen:  "When"
          of skThen:  "Then"
          of skAnd:   "And"
          of skBut:   "But"
        result.add("    # " & kindStr & " " & step.text & "\n")
      result.add("    #\n")

    # Scenario steps — generate compilable test skeletons per step type
    # axiom:theater-fix — replaces always-fail stub with real doAssert placeholders for Then/And(Then) steps
    var prevKind = skGiven
    for step in scenario.steps:
      let effectiveKind = case step.kind
        of skAnd, skBut: prevKind
        else: step.kind
      if step.kind notin [skAnd, skBut]:
        prevKind = step.kind

      let kindStr = case step.kind
        of skGiven: "Given"
        of skWhen:  "When"
        of skThen:  "Then"
        of skAnd:   "And"
        of skBut:   "But"

      result.add("    # Step: " & kindStr & " " & step.text & "\n")
      result.add("    # ── Action: " & kindStr & " ──\n")

      case effectiveKind
        of skGiven:
          # Variable initialization / state setup — comment-only until imports resolved
          result.add(
            "    # var <variable>: <Type> = <initialValue>\n" &
            "    #     ^-- Initialize the subject or fixture described above.\n"
          )
        of skWhen:
          # Function/method invocation — comment-only until target known
          result.add(
            "    # let <resultVar> = <targetFunction>(<args>)\n" &
            "    #       ^-- Call the action described above.\n"
          )
        of skThen:
          # Real assertion — derive an identifier from this step and emit an
          # executable `doAssert` that the developer wires to the SUT output.
          let ident = stepToProcName(skThen, step.text)
          result.add(
            "    # Assert: " & step.text & "\n" &
            "    doAssert " & ident & ", \"Then: " & step.text & "\"\n" &
            "    #        ^-- evaluate the real condition for the step above\n"
          )
        of skAnd, skBut:
          # Inherits action from previous step
          case prevKind
            of skGiven, skAnd, skBut:
              # Continuation of setup — emit a real fixture declaration for the developer to wire.
              let ident = stepToProcName(skAnd, step.text)
              result.add(
                "    # Continue setup: " & step.text & "\n" &
                "    let " & ident & " = <fixtureValue>\n" &
                "    #             ^-- wire the fixture value for the setup above\n"
              )
            of skWhen:
              # Continuation of action — emit a real result capture for the developer to wire.
              let ident = stepToProcName(skAnd, step.text)
              result.add(
                "    # Continue action: " & step.text & "\n" &
                "    let " & ident & " = <actionResult>\n" &
                "    #             ^-- wire the action result for the continuation above\n"
              )
            of skThen:
              # Continuation of assertion — emit a second real `doAssert`.
              let ident = stepToProcName(skAnd, step.text)
              result.add(
                "    # Also assert: " & step.text & "\n" &
                "    doAssert " & ident & ", \"And/But: " & step.text & "\"\n" &
                "    #        ^-- evaluate the real condition for the step above\n"
              )

# ─── Main ─────────────────────────────────────────────────────────

proc main() {.raises: [IOError, OSError].} =
  let args = commandLineParams()

  var featureName = ""
  var force = false

  for arg in args:
    if arg == "--force" or arg == "-f":
      force = true
    elif arg == "--help" or arg == "-h":
      echo "Usage: scaffold_feature_test <feature_name> [--force]"
      echo ""
      echo "Parses tests/features/<name>.feature and generates"
      echo "tests/gateway/<name>_feature_test.nim with meaningful stubs."
      echo ""
      echo "Options:"
      echo "  --force, -f  Overwrite existing test file"
      echo "  --help,  -h  Show this help"
      quit(0)
    else:
      featureName = arg

  if featureName.len == 0:
    echo "Error: feature name required."
    echo "Usage: scaffold_feature_test <feature_name> [--force]"
    quit(1)

  let featurePath = FeatureDir / (featureName & ".feature")
  if not fileExists(featurePath):
    echo "Error: feature file not found: " & featurePath
    quit(1)

  let outputPath = OutputDir / (featureName & Suffix)
  if fileExists(outputPath) and not force:
    echo "Error: output file already exists: " & outputPath
    echo "Use --force to overwrite."
    quit(1)

  let feature = parseFeature(featurePath)

  if feature.scenarios.len == 0:
    echo "Warning: no scenarios found in " & featurePath

  let output = generateTest(feature, featureName)

  createDir(OutputDir)
  writeFile(outputPath, output)

  # Count total steps across all scenarios
  var totalSteps = feature.backgroundSteps.len
  for s in feature.scenarios:
    totalSteps += s.steps.len

  echo "Generated " & outputPath &
    " with " & $feature.scenarios.len & " scenarios, " &
    $totalSteps & " steps"

when isMainModule:
  main()
