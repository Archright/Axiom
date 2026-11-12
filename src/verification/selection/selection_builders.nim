import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Pure selection builders shared by the S2 parity tool (tools/selection_report.nim)
## and its determinism tests. Kept in the domain layer so the CLI tool stays a
## thin I/O shell over pure, testable construction logic.

import std/[algorithm, json, sequtils, strutils, tables, sets]
import core/crypto/hash_kernel
import core/types/canonical_change_set
import core/types/graph_artifact
import core/types/selection_derivation
import core/types/execution_plan
import core/trusted/scope_identity

type
  DiffStatusEntry* = object
    path*: string
    status*: string
    blobHash*: string

## Fixed policy digest for the S2 local/CI parity machinery.
## Documents the diff-interpretation policy applied by buildCanonicalChangeSet:
## rename-sensitive per git status, generated files flagged, line-level mode.
const SelectionPolicyDigest* = "policy:S2-local-ci-parity-v1"

func buildCanonicalChangeSet*(baseCommit, headCommit: string;
                              mergeBase: seq[string];
                              changedFiles: seq[DiffStatusEntry]): CanonicalChangeSet =
  ## Build a CanonicalChangeSet from git diff data.
  ## Diff interpretation policy: rename-sensitive per git status,
  ## generated-files flagged when path starts with src/generated/.
  ## Input ordering is incidental: the canonical diff is sorted by path
  ## (then status) so digest is order-independent.
  let sortedFiles = changedFiles.sorted(
    proc(a, b: DiffStatusEntry): int =
      let byPath = cmp(a.path, b.path)
      if byPath != 0: byPath else: cmp(a.status, b.status))
  var canonicalDiff = ""
  for cf in sortedFiles:
    canonicalDiff &= cf.path & "\t" & cf.status & "\t" & cf.blobHash & "\n"
  let diffDigest = sha256Hex(canonicalDiff)
  var flags: set[DiffInterpretationFlag]
  for cf in sortedFiles:
    if cf.status in @["R", "C"]:
      flags.incl(difRenameDetected)
    if cf.path.startsWith("src/generated/"):
      flags.incl(difGeneratedFileHandling)
    if cf.status == "C":
      flags.incl(difCopyDetected)
  flags.incl(difLineLevelMode)
  CanonicalChangeSet(
    baseCommit: baseCommit,
    headCommit: headCommit,
    mergeBase: mergeBase,
    canonicalDiffDigest: diffDigest,
    diffInterpretationPolicy: DiffInterpretationPolicy(flags: flags))

func computeStructureDigest*(symbolDeps: Table[string, seq[string]]): string =
  ## Canonical structure digest from edge tables: sorted "from|to" edges, SHA-256.
  var edges: seq[string]
  for src, deps in symbolDeps:
    let sortedDeps = deps.sorted(cmp)
    for dep in sortedDeps:
      edges.add(src & "|" & dep)
  edges.sort(cmp)
  sha256Hex(edges.join(";"))

func buildGraphArtifact*(symbolDeps, symbolDependents: Table[string, seq[string]];
                         builderVersion = "2"): GraphArtifact =
  ## Build a GraphArtifact from symbol dependency edge tables.
  ## unresolvedEdges is empty here; topology analysis supplies them upstream.
  let structureDigest = computeStructureDigest(symbolDeps)
  let constructionInputs = sha256Hex(
    structureDigest & "|" & $symbolDeps.len & "|" & $symbolDependents.len)
  let interpPolicyDigest = sha256Hex(SelectionPolicyDigest)
  GraphArtifact(
    structureDigest: structureDigest,
    constructionInputsDigest: constructionInputs,
    interpretationPolicyDigest: interpPolicyDigest,
    unresolvedEdges: @[],
    builderVersion: builderVersion)

func deriveChangedSymbolSeeds*(changedFiles: seq[DiffStatusEntry];
                               fileSymbols: Table[string, seq[string]];
                               universeSet: HashSet[string]): (seq[string], seq[string]) =
  ## Map changed files to their symbols via the fileSymbols reverse map.
  ## Returns (changedSymbolSeeds, unmappedDiffStatusEntrys), both sorted.
  var seeds = initHashSet[string]()
  var unmapped = initHashSet[string]()
  for cf in changedFiles:
    if cf.path in fileSymbols:
      for sym in fileSymbols.getOrDefault(cf.path, @[]):
        if sym in universeSet:
          seeds.incl(sym)
    else:
      unmapped.incl(cf.path)
  (toSeq(seeds).sorted(cmp), toSeq(unmapped).sorted(cmp))

func computeUniverseDigest*(kernelSymbols: seq[string]; kernelTotal, vksTotal: int): string =
  ## Deterministic universe digest over parsed scope data (canonicalScopeDigest).
  let scopeInput = CanonicalScopeInput(
    kernelSymbols: kernelSymbols,
    kernelExemptSymbols: @[],
    kernelTotal: kernelTotal,
    vksTotal: vksTotal,
    profileIdentity: SelectionPolicyDigest,
    protocolVersion: "3")
  canonicalScopeDigest(scopeInput)

func selectionStatusToString*(status: SelectionStatus): string =
  case status
  of ssValid: "VALID"
  of ssFallbackRequired: "FALLBACK_REQUIRED"
  of ssError: "ERROR"

func universeModeToString*(mode: UniverseMode): string =
  case mode
  of umFull: "FULL"
  of umSelected: "SELECTED"

{.pop.}
