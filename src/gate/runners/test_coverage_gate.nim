import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## test_coverage_gate.nim — BDD Contract Gate (Tier 0)
##
## Pre-commit gate that enforces the "Intent → Spec → Test → Code" workflow
## by verifying that every .feature file has a corresponding test implementation.
##
## Checks:
##   1. For each .feature file in tests/features/ that has a corresponding
##      staged .nim module, verify at least one test file exists
##   2. Matching rule:
##      tests/features/foo.feature → tests/gateway/foo_feature_test.nim
##                               or tests/unit/foo_test.nim
##
## All output to stderr; stdout reserved for pipeline data.
## Exit code 0 = pass, 1 = fail.

import std/[os, osproc, strutils, sets, json]
import core/utils/formal_text_diff
import core/axiom_pragmas
import infrastructure/logging_facade


# axiomIoBoundary

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const
  FeaturesDir = "tests/features/"
  FeatureExt = ".feature"
  GatewayTestDir = "tests/gateway/"
  UnitTestDir = "tests/unit/"
  # GeneratedTestDir removed in Phase 0 purge (DEBT_REGISTRY §Purge protocol)
  GatewayTestSuffix = "_feature_test.nim"
  UnitTestSuffix = "_test.nim"
  BaselineFile = "data/spec_presence_baseline.json"

# ---------------------------------------------------------------------------
# Baseline (grandfathered modules without test files)
# ---------------------------------------------------------------------------

proc loadBaseline(): HashSet[string] {.axiomEffect: IOEffect.} =
  ## Load grandfathered module names from data/spec_presence_baseline.json.
  ## These modules lack both feature specs and test files; new modules
  ## must have test coverage.
  result = initHashSet[string]()
  if not fileExists(BaselineFile):
    return
  try:
    let content = readFile(BaselineFile)
    let json = parseJson(content)
    if json.hasKey("allowed_modules"):
      for item in json["allowed_modules"]:
        result.incl(item.getStr())
  except CatchableError as e:
    logWarn("test_coverage_gate", "[test-coverage-gate] WARN — could not load baseline: " & e.msg)

# ---------------------------------------------------------------------------
# Git helpers
# ---------------------------------------------------------------------------

proc execGit(args: openArray[string]): string =
  let cmd = "git " & args.join(" ")
  let (output, exitCode) = execCmdEx(cmd)
  if exitCode != 0:
    return ""
  output.strip(leading = false, trailing = true, chars = Whitespace + Newlines)

proc getStagedNimFilesInSrc(): seq[string] =
  ## Get all staged .nim files under src/ directory.
  let raw = execGit(["diff", "--cached", "--name-only", "--diff-filter=ACM"])
  for line in raw.splitLines():
    let trimmed = line.strip()
    if trimmed.startsWith("src/") and trimmed.endsWith(".nim"):
      result.add(trimmed)

# ---------------------------------------------------------------------------
# Feature-to-test mapping
# ---------------------------------------------------------------------------

func getFeatureNamesForStagedModules(stagedSrcFiles: seq[string]): seq[string] =
  ## For each staged src/.nim file, derive the expected feature name.
  for f in stagedSrcFiles:
    let name = f.splitFile().name
    result.add(name)

proc findCorrespondingTests(featureName: string): seq[string] =
  ## Find test files that correspond to a given feature name.
  ## Checks both tests/gateway/ and tests/unit/ directories.

  # Check tests/gateway/foo_feature_test.nim
  let gatewayPath = GatewayTestDir & featureName & GatewayTestSuffix
  if fileExists(gatewayPath):
    result.add(gatewayPath)

  # Check tests/unit/foo_test.nim
  let unitPath = UnitTestDir & featureName & UnitTestSuffix
  if fileExists(unitPath):
    result.add(unitPath)

  # Also check for alternative: tests/gateway/foo_test.nim
  let gatewayAlt = GatewayTestDir & featureName & UnitTestSuffix
  if fileExists(gatewayAlt):
    result.add(gatewayAlt)

  # Check tests/unit/foo_feature_test.nim
  let unitAlt = UnitTestDir & featureName & GatewayTestSuffix
  if fileExists(unitAlt):
    result.add(unitAlt)

  # tests/generated/ removed in Phase 0 purge (DEBT_REGISTRY §Purge protocol)

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

proc main() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  # Get staged src/.nim files to determine which features are "active"
  let stagedSrcFiles = getStagedNimFilesInSrc()
  if stagedSrcFiles.len == 0:
    quit(0)

  # Filter: skip non-logic changes (pragma-only, comment-only, whitespace)
  var logicFiles: seq[string] = @[]
  for modulePath in stagedSrcFiles:
    let diff = execGit(["diff", "--cached", modulePath])
    let kind = classifyChange(diff)
    if kind == ckLogic:
      logicFiles.add(modulePath)
    else:
      logInfo("test_coverage_gate", "[test-coverage-gate] SKIP — " & modulePath & " (" & $kind & ")")

  if logicFiles.len == 0:
    quit(0)

  # Collect feature names from the logic-changed modules
  let relevantFeatures = getFeatureNamesForStagedModules(logicFiles)
  if relevantFeatures.len == 0:
    quit(0)

  # Load grandfathered modules baseline
  let baseline = loadBaseline()

  # Check each relevant feature for corresponding tests
  var missingTests: seq[string] = @[]
  var foundCount = 0
  var baselineSkipped = 0

  for featureName in relevantFeatures:
    # Skip grandfathered modules
    if featureName in baseline:
      baselineSkipped.inc
      continue
    let tests = findCorrespondingTests(featureName)
    if tests.len > 0:
      foundCount.inc
    else:
      missingTests.add(featureName)

  if baselineSkipped > 0:
    logInfo("test_coverage_gate", "[test-coverage-gate] INFO — " & $baselineSkipped &
                     " module(s) grandfathered via baseline")

  # If no missing tests, pass
  if missingTests.len == 0:
    quit(0)

  logError("test_coverage_gate", "[test-coverage-gate] FAIL — " & $missingTests.len & " feature(s) missing test implementation:")
  for feature in missingTests:
    logInfo("test_coverage_gate", "  " & FeaturesDir & feature & FeatureExt)
    logInfo("test_coverage_gate", "    expected: " & GatewayTestDir & feature & GatewayTestSuffix)
    logInfo("test_coverage_gate", "          or: " & UnitTestDir & feature & UnitTestSuffix)
  logInfo("test_coverage_gate", "")
  logInfo("test_coverage_gate", "[test-coverage-gate] Create at least one test file per feature.")
  logInfo("test_coverage_gate", "[test-coverage-gate] Or add to " & BaselineFile & " if grandfathered")
  logInfo("test_coverage_gate", "[test-coverage-gate] See: tests/gateway/ or tests/unit/ for existing examples.")
  quit(1)

when isMainModule:
  main()

{.pop.}
