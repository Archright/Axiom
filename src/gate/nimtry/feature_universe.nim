import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

## Feature Universe Determinism Check
## AGENTS.md §1.7: Spec Binding Gate — feature files must follow naming convention.
## Detects _feature.feature anti-pattern and cardinality mismatches.
##
## Uses std/os.walkDir — deterministic, no external tool dependency.
## Uses std/strutils — no gorge("grep") calls.

import std/os
import std/strutils
import std/algorithm
import gate/tag_parser
import gate/nimtry/nimtry_registry
import gate/architecture_ast_facts
import gate/rule_patterns
import core/gate/architecture_policy
import core/utils/file_utils
import core/utils/repo_root
import core/trusted/axiom_pragmas

type
  FeatureViolation* = object
    rule*: string
    detail*: string
    severity*: string

func toRepoRelative*(path: string; repoRoot: string): string {.raises: [].} =
  ## Convert an absolute path to repo-relative for deterministic violation
  ## details (environment-independent fingerprints).
  let norm = path.replace("\\", "/")
  let root = repoRoot.replace("\\", "/").strip(chars = {'/'}, leading = false)
  if root.len > 0 and norm.startsWith(root & "/"):
    norm[root.len + 1 .. ^1]
  else:
    norm

proc scanFeatureUniverse*(
  featuresDir: string;
  gatewayDir: string = "";
  coverageDir: string = ""
): seq[FeatureViolation] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Scan tests/features/ for naming convention violations.
  ##
  ## Rules enforced:
  ##   FEATURE-duplicate-suffix: _feature.feature file has a clean counterpart
  ##   FEATURE-orphan-suffix:    _feature.feature file has no clean counterpart
  ##   FEATURE-missing-runner:   executable feature has no matching _feature_test.nim
  ##   FEATURE-zombie-runner:    _feature_test.nim has no matching .feature
  ##
  ## ``gatewayDir`` is the landing-lane runner dir (tests/gateway/). When empty,
  ## cardinality checks are skipped (backward-compatible with callers that only
  ## care about the suffix anti-pattern). ``coverageDir`` is the optional
  ## coverage-plane runner dir (tests/gateway_coverage/, plan Phase 3
  ## re-tiering) — runners there satisfy the same 1:1 feature↔runner
  ## cardinality invariant.
  ##
  ## Deterministic: identical input directory state → identical output.

  let repoRoot = try: findRepoRoot() except CatchableError: (try: getCurrentDir() except OSError: ".")

  var suffixFiles: seq[string]

  try:
    for kind, path in walkDir(featuresDir):
      if kind != pcFile:
        continue
      let (_, name, ext) = splitFile(path)
      if ext != ".feature":
        continue
      if name.endsWith("_feature"):
        suffixFiles.add(path)
  except CatchableError:
    return

  suffixFiles.sort(system.cmp[string])

  # Rule 1: _feature.feature anti-pattern
  for path in suffixFiles:
    let (_, name, _) = splitFile(path)
    let cleanName = name[0 ..^ 9]  # remove "_feature" suffix (8 chars + 1 for 0-index)
    let cleanPath = featuresDir / cleanName & ".feature"

    if fileExists(cleanPath):
      result.add(FeatureViolation(
        rule: "FEATURE-duplicate-suffix",
        detail: path & " has clean counterpart " & cleanPath & ". Merge and delete.",
        severity: "error",
      ))
    else:
      result.add(FeatureViolation(
        rule: "FEATURE-orphan-suffix",
        detail: path & " has no clean counterpart. Rename to " & cleanName & ".feature",
        severity: "warning",
      ))

  # Rule 2: Feature↔Test 1:1 cardinality
  if gatewayDir.len == 0:
    return

  # 2a: Collect all executable feature names (skip @manual and @legacy)
  var executableFeatures: seq[string] = @[]
  try:
    for kind, path in walkDir(featuresDir):
      if kind != pcFile:
        continue
      let (_, name, ext) = splitFile(path)
      if ext != ".feature":
        continue

      let content = readFileSafe(path)
      if content.len == 0:
        continue

      let tags = parseFeatureTags(content)
      if isManual(tags) or isLegacy(tags):
        continue

      # @executable or untagged (= default executable) — needs a runner
      executableFeatures.add(name)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

  executableFeatures.sort(system.cmp[string])

  # 2b: Collect all _feature_test.nim names from the gateway universe
  #     (landing lane tests/gateway + coverage plane tests/gateway_coverage)
  var runnerNames: seq[string] = @[]
  try:
    for runnerRoot in [gatewayDir, coverageDir]:
      if runnerRoot.len == 0 or not dirExists(runnerRoot):
        continue
      for kind, path in walkDir(runnerRoot):
        if kind != pcFile:
          continue
        let (_, name, ext) = splitFile(path)
        if ext != ".nim":
          continue
        if name.endsWith("_feature_test"):
          # Strip "_feature_test" suffix (13 chars) to get the feature name
          let featureName = name[0 ..^ 14]
          runnerNames.add(featureName)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

  runnerNames.sort(system.cmp[string])

  # 2c: Detect missing runners (feature exists, runner does not)
  for featureName in executableFeatures:
    let expectedRunner = featureName & "_feature_test.nim"
    let runnerPath = gatewayDir / expectedRunner
    let coverageRunnerPath = coverageDir / expectedRunner
    if not fileExists(runnerPath) and not fileExists(coverageRunnerPath):
      result.add(FeatureViolation(
        rule: "FEATURE-missing-runner",
        detail: toRepoRelative(featuresDir, repoRoot) / featureName & ".feature" &
                " has no matching " & toRepoRelative(runnerPath, repoRoot) &
                (if coverageDir.len > 0: " (nor " & toRepoRelative(coverageRunnerPath, repoRoot) & ")" else: "") &
                ". Add a test runner or tag the feature @manual.",
        severity: "warning",
      ))

  # 2d: Detect zombie runners (runner exists, no matching executable feature)
  for runnerName in runnerNames:
    # Locate the runner's actual home (landing lane or coverage plane)
    let landingRunnerPath = gatewayDir / runnerName & "_feature_test.nim"
    let coverageRunnerPath2 = coverageDir / runnerName & "_feature_test.nim"
    let actualRunnerPath =
      if fileExists(landingRunnerPath): landingRunnerPath
      elif fileExists(coverageRunnerPath2): coverageRunnerPath2
      else: landingRunnerPath

    # Check if there is an executable feature with this name
    var found = false
    for featureName in executableFeatures:
      if featureName == runnerName:
        found = true
        break
    if found:
      continue

    # Also check if the feature exists but is @manual/@legacy (not a true zombie)
    let featurePath = featuresDir / runnerName & ".feature"
    if fileExists(featurePath):
      # Feature exists but is @manual or @legacy — runner is orphaned
      let content = readFileSafe(featurePath)
      var isExempt = false
      try:
        let tags = parseFeatureTags(content)
        isExempt = isManual(tags) or isLegacy(tags)
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)
      if isExempt:
        result.add(FeatureViolation(
          rule: "FEATURE-zombie-runner",
          detail: toRepoRelative(actualRunnerPath, repoRoot) &
                  " has matching " & toRepoRelative(featurePath, repoRoot) &
                  " which is @manual or @legacy. Remove the runner or update tags.",
          severity: "error",
        ))
        continue

    # No matching .feature at all
    result.add(FeatureViolation(
      rule: "FEATURE-zombie-runner",
      detail: toRepoRelative(actualRunnerPath, repoRoot) &
              " has no matching " & toRepoRelative(featurePath, repoRoot) &
              ". Delete the runner or create the missing .feature.",
      severity: "error",
    ))

  result.sort(proc(a, b: FeatureViolation): int =
    system.cmp[string](a.rule, b.rule))

proc checkFeatureCardinality*(
  allFacts: seq[ModuleFacts];
  policy: ArchitecturePolicy
): seq[ArchitectureViolationArtifact] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Nimtry query: enforce 1:1 cardinality between .feature files and
  ## gateway-universe _feature_test.nim runners (landing lane tests/gateway/
  ## + coverage plane tests/gateway_coverage/, plan Phase 3 re-tiering).
  ##
  ## Scans tests/features/, tests/gateway/ and tests/gateway_coverage/ relative to
  ## the current directory. Follows the same filesystem-scanning pattern as
  ## checkWhenIsMainModuleInTests in test_hygiene.nim — allFacts/policy are
  ## unused (filesystem check only).
  let repoRoot = try: findRepoRoot() except CatchableError: (try: getCurrentDir() except OSError: ".")
  let featuresDir = repoRoot / "tests" / "features"
  let gatewayDir = repoRoot / "tests" / "gateway"
  let coverageDir = repoRoot / "tests" / "gateway_coverage"

  if not dirExists(featuresDir):
    return
  if not dirExists(gatewayDir):
    return

  let violations = scanFeatureUniverse(featuresDir, gatewayDir, coverageDir)
  for v in violations:
    # Only forward cardinality violations (not the suffix anti-pattern rules)
    if v.rule == "FEATURE-missing-runner" or v.rule == "FEATURE-zombie-runner":
      result.add(ArchitectureViolationArtifact(
        rule: v.rule,
        detail: v.detail,
        files: @[],
        severity: v.severity
      ))

proc registerFeatureQueries*(queries: var seq[NimtryQuery]) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  # FEATURE: 1:1 cardinality between .feature files and _feature_test.nim runners
  queries.add(NimtryQuery(
    name: "feature-cardinality",
    rule: "FEATURE",
    severity: "warning",
    taxonomy: structural,
    checker: checkFeatureCardinality
  ))

{.pop.}
