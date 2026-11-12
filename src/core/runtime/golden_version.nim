import core/trusted/layer_declaration
axiomLayer "domain"
import core/interfaces/git_operations
import core/crypto/hash_kernel
import core/io/file_utils
import core/trusted/axiom_pragmas
import std/[os, osproc, json, strutils, times]
# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

type
  GoldenManifest* = object
    ## Checksums recorded when golden data was generated.
    generatorCommit*: string         ## Git commit SHA at generation time
    policyHash*: string              ## SHA-256 of architecture policy
    nimCompilerHash*: string         ## SHA-256 of nim compiler binary
    generatedAt*: string             ## ISO 8601 timestamp
    version*: string                 ## Schema version

  GoldenFreshness* = object
    ## Result of freshness validation.
    isFresh*: bool
    mismatches*: seq[string]         ## List of mismatched checksum fields
# ---------------------------------------------------------------------------
# Checksum Computation (compile-time safe via readFile + findExe, no gorge)
# ---------------------------------------------------------------------------

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc computeNimCompilerHash*(): string {.gcsafe, raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## SHA-256 of the nim compiler binary.
  try:
    let nimPath = findExe("nim")
    if nimPath.len == 0: return "unknown"
    let content = readFile(nimPath)
    result = hash_kernel.sha256Hex(content)
  except CatchableError:
    result = "unknown"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc computePolicyHash*(repoRoot: string): string {.gcsafe, raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## SHA-256 of the architecture policy lock file.
  let policyPath = repoRoot / "src" / "gate" / "architecture_policy.lock"
  if fileExists(policyPath):
    try:
      let content = readFile(policyPath)
      result = hash_kernel.sha256Hex(content)
    except CatchableError:
      result = "unknown"
  else:
    result = "not_found"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc computeGateRunnerHash*(repoRoot: string, gateId: string): string {.gcsafe, raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## SHA-256 of a specific gate runner binary.
  let runnerPath = repoRoot / "bin" / gateId
  if fileExists(runnerPath):
    try:
      let content = readFile(runnerPath)
      result = hash_kernel.sha256Hex(content)
    except CatchableError:
      result = "unknown"
  else:
    result = "not_built"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc currentCommit*(): string {.gcsafe, raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Current git HEAD commit SHA.
  try:
    let gitExe = git_operations.findRealGit()
    let (output, exitCode) = git_operations.runGitEx(gitExe, "rev-parse --short HEAD 2>/dev/null")
    result = if exitCode == 0: output.strip() else: "unknown"
  except CatchableError:
    result = "unknown"

# ---------------------------------------------------------------------------
# Golden File I/O
# ---------------------------------------------------------------------------
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc loadGoldenManifest*(goldenPath: string): GoldenManifest {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Load a golden file and extract the manifest checksums.
  let content = readFileSafe(goldenPath)
  let node = parseJson(content)
  GoldenManifest(
    generatorCommit: node{"generatorCommit"}.getStr(""),
    policyHash: node{"policyHash"}.getStr(""),
    nimCompilerHash: node{"nimCompilerHash"}.getStr(""),
    generatedAt: node{"generatedAt"}.getStr(""),
    version: node{"version"}.getStr("1.0")
  )
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc updateGoldenFile*(goldenPath: string, repoRoot: string, gateId: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Regenerate a golden file with current checksums.
  var node: JsonNode
  if fileExists(goldenPath):
    node = parseJson(readFileSafe(goldenPath))
  else:
    node = newJObject()
    node["gateId"] = %gateId
    node["status"] = %"pass"
    node["violations"] = newJArray()
    node["metrics"] = newJObject()

  node["generatorCommit"] = %currentCommit()
  node["policyHash"] = %computePolicyHash(repoRoot)
  node["nimCompilerHash"] = %computeNimCompilerHash()
  node["generatedAt"] = %now().utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'")
  node["version"] = %"1.0"

  writeFile(goldenPath, node.pretty())

# ---------------------------------------------------------------------------
# Freshness Validation
# ---------------------------------------------------------------------------
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc validateGoldenFreshness*(goldenDir: string, repoRoot: string): GoldenFreshness {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Validate all golden files in a directory against current environment.
  ## Returns fresh=true if all checksums match, plus list of mismatches.
  result.isFresh = true
  result.mismatches = @[]

  let currentPolicyHash = computePolicyHash(repoRoot)
  let currentNimHash = computeNimCompilerHash()

  for kind, path in walkDir(goldenDir):
    if kind == pcFile and path.endsWith(".json"):
      try:
        let manifest = loadGoldenManifest(path)
        let filename = path.extractFilename()

        if manifest.policyHash.len > 0 and manifest.policyHash != "unknown" and
           manifest.policyHash != currentPolicyHash:
          result.isFresh = false
          result.mismatches.add(filename & ": policyHash mismatch (expected " &
            currentPolicyHash[0..7] & "... got " & manifest.policyHash[0..7] & "...)")

        if manifest.nimCompilerHash.len > 0 and manifest.nimCompilerHash != "unknown" and
           manifest.nimCompilerHash != currentNimHash:
          result.isFresh = false
          result.mismatches.add(filename & ": nimCompilerHash mismatch")

        if manifest.generatorCommit.len > 0 and
           manifest.generatorCommit != currentCommit():
          result.isFresh = false
          result.mismatches.add(filename & ": generatorCommit drift (golden=" &
            manifest.generatorCommit & " HEAD=" & currentCommit() & ")")
      except JsonParsingError:
        result.isFresh = false
        result.mismatches.add(path.extractFilename() & ": invalid JSON")
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc validateSingleGolden*(goldenPath: string, repoRoot: string): GoldenFreshness {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Validate a single golden file.
  validateGoldenFreshness(goldenPath.parentDir(), repoRoot)
