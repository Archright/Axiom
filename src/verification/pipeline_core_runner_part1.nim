import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}
import core/axiom_pragmas
import core/utils/constants
import core/domain_types
import core/json/json_utils
import core/logic/pipeline_fingerprint_engine
import core/pipeline_core_types
import core/results
import core/utils/file_utils
import core/utils/io_utils
import core/utils/text_utils
import std/json
import std/options
import std/os
import std/strutils
import std/times
import infrastructure/logging_facade
# @axiom-hint: lean="bddDir.length ≥ 0" smt="(assert (and (>= (str.len bddDir) 0)))"
proc deriveReproductionDir(bddDir: string): string {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let normalized = normalizePathSeparators(bddDir)
  if normalized.endsWith("/features"):
    return joinPath(parentDir(bddDir), "reproduction")
  joinPath(parentDir(bddDir), "reproduction")

# @axiom-hint: lean="path.length ≥ 0" smt="(assert (and (>= (str.len path) 0)))"
proc ensureDirectoryTree*(path: string) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if path.len == 0 or dirExists(path):
    return
  let parent = parentDir(path)
  if parent.len > 0 and parent != path and not dirExists(parent):
    ensureDirectoryTree(parent)
  discard existsOrCreateDirOpt(path)

# @axiom-hint: lean="language.length ≥ 0" smt="(assert (and (>= (str.len language) 0)))"
func pocFileExtension(language: string): string {.raises: [CatchableError].} =
  let normalized = language.toLowerAscii()
  if normalized == "nim":
    ".nim"
  elif normalized == "cpp" or normalized == "c++":
    ".cpp"
  else:
    ".c"

## Write Reproduction Artifact.
# @axiom-hint: lean="external_io_isolated" smt="(assert (and external_io_isolated))"
proc writeReproductionArtifact*(
  req: UniversalPipelineRequest;
  hit: Option[AnnotatedHit];
  pocSnippet: string
): Result[string, AxiomError] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if hit.isNone() or pocSnippet.strip().len == 0:
    return ok("")
  try:
    let reproDir = deriveReproductionDir(req.bddDir)
    ensureDirectoryTree(reproDir)
    let fileName =
      sanitizeToken(req.functionName) & "_" &
      sanitizeToken($hit.get().hit.kind) & "_repro" &
      pocFileExtension(req.language)
    let filePath = joinPath(reproDir, fileName)
    if not writeFileSafe(filePath, pocSnippet):
      return err(axiomErrFileSystemError)
    ok(normalizePathSeparators(filePath))
  except CatchableError:
    err(axiomErrFileSystemError)

## Promotion Snapshot Path.
func promotionSnapshotPath(req: UniversalPipelineRequest): string {.raises: [].} =
  joinPath(req.proofVaultDir, sanitizeToken(req.functionName) & "_promotion_snapshot.json")

## Write Promotion Snapshot.
# @axiom-hint: lean="(node ≥ 0)" smt="(assert (and (>= node 0)))"
proc writePromotionSnapshot*(
  req: UniversalPipelineRequest;
  hit: Option[AnnotatedHit];
  activeInvariant: string;
  evolutionReasoning: string;
  proofArtifactPath: string
): Result[string, AxiomError] {.raises: [], axiomEffect: IOEffect, tags: [RootEffect, TimeEffect, AxiomIOEffect, IOEffect].} =
  if activeInvariant.strip().len == 0:
    return ok("")
  try:
    ensureDirectoryTree(req.proofVaultDir)
    let snapshotPath = promotionSnapshotPath(req)
    var node = newJObject()
    node[schemaVersionKey] = newJString("axiom.uap.promoted-invariant.v1")
    node[modulePathKey] = newJString(req.modulePath)
    node[functionNameKey] = newJString(req.functionName)
    node["activeInvariant"] = newJString(activeInvariant)
    node[evolutionReasoningKey] = newJString(evolutionReasoning)
    node["sourceProofArtifactPath"] = newJString(proofArtifactPath)
    if hit.isSome():
      node["kind"] = newJString($hit.get().hit.kind)
      node["violatedProperty"] = newJString(hit.get().violatedProperty)
    node["updatedAt"] = newJString(now().utc().format("yyyy-MM-dd'T'HH:mm:ss.fff'Z'"))
    if not writePrettyJsonFile(snapshotPath, node):
      logError("pipeline_core_runner_part1", "Failed to write snapshot to " & snapshotPath)
    ok(normalizePath(snapshotPath))
  except CatchableError:
    err(axiomErrFileSystemError)
{.pop.}
