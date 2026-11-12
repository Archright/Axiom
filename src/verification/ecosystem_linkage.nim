import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import ../core/trusted/axiom_pragmas
import core/crypto/hash_kernel
import core/json/json_utils, core/results
import core/json/std_redirect
import core/semantic_types
import core/utils/file_utils
import std/options
import std/os
import std/strutils
import std/tables
import std/times
import verification/semantic_graph, core/frontend_ir
type
  ExternalContract* = object
    qualifiedName*: string
    moduleName*: string
    version*: string
    irFingerprint*: string
    invariants*: seq[InvariantCondition]
    effectConstraints*: seq[EffectConstraint]
    manifestPath*: string

  AxiomManifest* = object
    name*: string
    version*: string
    axiomVersion*: string
    functions*: seq[ExternalContract]

  DependencyTrust* = object
    name*: string
    version*: string
    integrityHash*: string

  ChainOfTrustCertificate* = object
    project*: string
    version*: string
    generatedAt*: string
    dependencies*: seq[DependencyTrust]
# ---------------------------------------------------------------------------
# Manifest I/O
# ---------------------------------------------------------------------------

## Load Axiom Manifest.
proc loadAxiomManifest*(manifestPath: string): AxiomManifest {.raises: [], axiom: ["(assert (and (>= result 0) external_io_isolated))", "(result ≥ 0) ∧ external_io_isolated"], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  result = AxiomManifest()
  if not fileExists(manifestPath):
    return
  try:
    let content = readFileSafe(manifestPath)
    let node = parseJsonOpt(content).get(newJObject())
    if node.hasKey("name"):
      result.name = node["name"].getStr()
    if node.hasKey("version"):
      result.version = node["version"].getStr()
    if node.hasKey("axiomVersion"):
      result.axiomVersion = node["axiomVersion"].getStr()
    if node.hasKey("functions"):
      for fn in node["functions"]:
        var contract = ExternalContract(
          qualifiedName: fn{"qualifiedName"}.getStr(),
          moduleName: result.name,
          version: result.version,
          irFingerprint: fn{"irFingerprint"}.getStr(),
          manifestPath: manifestPath
        )
        if fn.hasKey("invariants"):
          for inv in fn["invariants"]:
            let scopeStr = inv{"scope"}.getStr()
            let scope = case scopeStr
            of "invPre": invPre
            of "invPost": invPost
            of "invLoop": invLoop
            else: invPost
            contract.invariants.add(InvariantCondition(
              predicate: inv{"predicate"}.getStr(),
              scope: scope
            ))
        if fn.hasKey("effectConstraints"):
          for ec in fn["effectConstraints"]:
            let kindStr = ec{"kind"}.getStr()
            let kind = case kindStr
            of "effPure": effPure
            of "effNoSideEffect": effNoSideEffect
            of "effIO": effIO
            of "effNetwork": effNetwork
            of "effFileSystem": effFileSystem
            else: effUnknown
            contract.effectConstraints.add(EffectConstraint(
              kind: kind,
              severity: int(ec{"severity"}.getInt())
            ))
        result.functions.add(contract)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

## Scan External Contracts.
const stdlibContractModules* = ["json", "os", "strutils", "tables", "times", "hashes", "options", "sequtils", "algorithm", "math", "strformat"]
proc resolveStandardLibraryContract*(libName: string; hubUrl: string): Result[ExternalContract, string] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let manifestPath = hubUrl / (libName & ".json")
  if not fileExists(manifestPath):
    return err("resolveStandardLibraryContract: manifest not found: " & manifestPath)
  try:
    let content = readFileSafe(manifestPath)
    let jsonOpt = parseJsonOpt(content)
    if jsonOpt.isNone:
      return err("resolveStandardLibraryContract: failed to parse JSON from " & manifestPath)
    let node = jsonOpt.get()
    let qualifiedName = node{"qualifiedName"}.getStr()
    let moduleName = node{"moduleName"}.getStr()
    let version = node{"version"}.getStr()
    let irFingerprint = node{"irFingerprint"}.getStr()
    result = ok(ExternalContract(
      qualifiedName: qualifiedName,
      moduleName: moduleName,
      version: version,
      irFingerprint: irFingerprint,
      manifestPath: manifestPath
    ))
  except CatchableError:
    result = err("resolveStandardLibraryContract: failed to parse manifest: " & libName)

proc scanExternalContracts*(pkgRoot: string; hubUrl: string = ""): seq[ExternalContract] {.raises: [], axiom: ["(assert (and (= kind pcDir) (> (str.len hubUrl) 0) (>= stdlibContractModules 0)))", "kind = pcDir ∧ hubUrl.length > 0 ∧ (stdlibContractModules ≥ 0)"], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if not dirExists(pkgRoot):
    return
  try:
    for kind, path in walkDir(pkgRoot):
      if kind == pcDir:
        let manifestPath = path / "axiom_manifest.json"
        if fileExists(manifestPath):
          let manifest = loadAxiomManifest(manifestPath)
          for fn in manifest.functions:
            result.add(fn)
    if hubUrl.len > 0:
      for libName in stdlibContractModules:
        let contractRes = resolveStandardLibraryContract(libName, hubUrl)
        if contractRes.isOk():
          result.add(contractRes.get())
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

## Compute Manifest Integrity Hash.
proc computeManifestIntegrityHash*(manifestPath: string): string {.raises: [], axiom: ["(assert (and (>= result 0) external_io_isolated))", "(result ≥ 0) ∧ external_io_isolated"], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    let content = readFileSafe(manifestPath)
    result = sha256Hex(content)
  except CatchableError:
    result = ""

# ---------------------------------------------------------------------------
# Contract comparison
# ---------------------------------------------------------------------------

## Detect Postcondition Weakening.
func detectPostconditionWeakening*(oldInvs, newInvs: seq[InvariantCondition]): bool {.raises: [], axiom: ["(assert (and (= foundEqual true) true false (>= foundEqual 0) (>= newInvs 0) (>= oldInvs 0)))", "foundEqual = true ∧ true ∧ false ∧ (foundEqual ≥ 0) ∧ (newInvs ≥ 0) ∧ (oldInvs ≥ 0)"].} =
  ## Returns true if any old post-condition is missing or weaker in the new set.
  for oldInv in oldInvs:
    if oldInv.scope != invPost:
      continue
    var foundEqual = false
    for newInv in newInvs:
      if newInv.scope == invPost and newInv.predicate == oldInv.predicate:
        foundEqual = true
        break
    if not foundEqual:
      return true
  return false

# ---------------------------------------------------------------------------
# Graph integration
# ---------------------------------------------------------------------------

## Integrate External Nodes.
func integrateExternalNodes*(graph: var SemanticGraph; contracts: seq[ExternalContract]) {.raises: [], axiom: ["(assert (and (>= contracts 0)))", "(contracts ≥ 0)"].} =
  for contract in contracts:
    if graph.nodes.hasKey(contract.qualifiedName):
      continue
    let node = SemanticGraphNode(
      name: contract.qualifiedName.split(".")[^1],
      modulePath: contract.manifestPath,
      qualifiedName: contract.qualifiedName,
      status: snsVerified,
      certificateHash: contract.irFingerprint,
      irFingerprint: contract.irFingerprint,
      ancestors: @[],
      descendants: @[],
      depth: 0,
      impactIndex: 0.0,
      invalidDescendantsCount: 0,
      isExternal: true,
      externalSource: contract.moduleName,
      externalVersion: contract.version
    )
    graph.nodes[contract.qualifiedName] = node
    inc graph.totalNodes
    inc graph.verifiedNodes
    inc graph.externalNodes

## Propagate External Risk.
func propagateExternalRisk*(graph: var SemanticGraph; changedExternalFn: string) {.raises: [], axiom: ["(assert (and (>= (str.len changedExternalFn) 0)))", "changedExternalFn.length ≥ 0"].} =
  if not graph.nodes.hasKey(changedExternalFn):
    return
  setSemanticNodeStatus(graph, changedExternalFn, snsExternalRisk)
  markAffectedNodesPendingByDependency(graph, changedExternalFn)
proc buildChainOfTrustCertificate*(project, version: string; dependencies: seq[DependencyTrust]): ChainOfTrustCertificate {.raises: [], axiom: ["(assert (and (>= result 0)))", "(result ≥ 0)"], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  result = ChainOfTrustCertificate(
    project: project,
    version: version,
    generatedAt: now().utc.format("yyyy-MM-dd'T'HH:mm:ss'.'fff'Z'"),
    dependencies: dependencies
  )

## Verify Chain Of Trust.
proc verifyChainOfTrust*(cert: ChainOfTrustCertificate; pkgRoot: string): tuple[ok: bool; reason: string] {.raises: [], axiom: ["(assert (and (>= (str.len cert_project) 0) (>= (str.len cert_version) 0) (>= (str.len cert_generatedAt) 0) (>= (seq.len cert_dependencies) 0) (>= (str.len pkgRoot) 0)))", "cert_project.length ≥ 0 ∧ cert_version.length ≥ 0 ∧ cert_generatedAt.length ≥ 0 ∧ cert_dependencies.size ≥ 0 ∧ pkgRoot.length ≥ 0"], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  for dep in cert.dependencies:
    let manifestPath = pkgRoot / dep.name / "axiom_manifest.json"
    if not fileExists(manifestPath):
      return (false, "Missing manifest for " & dep.name)
    let actualHash = computeManifestIntegrityHash(manifestPath)
    if actualHash != dep.integrityHash:
      return (false, "Hash mismatch for " & dep.name)
  return (true, "")

## Build Chain Of Trust Json.
func buildChainOfTrustJson*(cert: ChainOfTrustCertificate): JsonNode {.raises: [], axiom: ["(assert (and (>= (str.len cert_project) 0) (>= (str.len cert_version) 0) (>= (str.len cert_generatedAt) 0) (>= (seq.len cert_dependencies) 0) (>= obj 0) (>= result 0)))", "cert_project.length ≥ 0 ∧ cert_version.length ≥ 0 ∧ cert_generatedAt.length ≥ 0 ∧ cert_dependencies.size ≥ 0 ∧ (obj ≥ 0) ∧ (result ≥ 0)"].} =
  result = newJObject()
  result["project"] = %cert.project
  result["version"] = %cert.version
  result["generatedAt"] = %cert.generatedAt
  var deps = newJArray()
  for dep in cert.dependencies:
    var obj = newJObject()
    obj["name"] = %dep.name
    obj["version"] = %dep.version
    obj["integrityHash"] = %dep.integrityHash
    deps.add(obj)
  result["dependencies"] = deps
# ---------------------------------------------------------------------------
# Axiom-Hub PoC interface
# ---------------------------------------------------------------------------

## Resolve Standard Library Contract.
# @axiom-hint: lean="hubUrl.length > 0" smt="(assert (and (> (str.len hubUrl) 0)))"

{.pop.}
