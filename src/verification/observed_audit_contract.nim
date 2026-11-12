## observed_audit_contract.nim — Observed Audit Contract
##
## Observation-only model of the verification-auditor verdict.
## PROVISIONAL. Reads/explains the verdict; does NOT change it.
##
## Ties classification to confirmed auditor semantics:
##   SubjectSnapshot from walkDirRec("src") *.nim;
##   Baseline from data/verification_auditor_baseline.json;
##   GatePolicy from config/gates.json;
##   GateImplementation from the gate binary identity.
##
## Precedent: verification_dependency.nim (ReadClass / VerificationDependencyKind),
## observation_pipeline.nim (ObservationStatus / resolve),
## semantic_query_types.nim (distinct digest types).

import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import std/[os, strutils, json, re, algorithm]
import verification/verification_dependency
import verification/observation_pipeline
import verification/semantic_query_types
import core/crypto/hash_kernel
import core/trusted/axiom_pragmas_lite
import ci/verification_probe

# ---------------------------------------------------------------------------
# ObservedAuditInput — provisional enum (semantic inputs only)
# ---------------------------------------------------------------------------
# Lock/mode/maxJobs are PROVENANCE — do not include as semantic inputs.

type
  ObservedAuditInput* = enum
    oaiSubjectSnapshot  ## walkDirRec("src") *.nim content walk
    oaiBaseline         ## data/verification_auditor_baseline.json
    oaiGatePolicy       ## config/gates.json
    oaiGateImplementation  ## gate binary identity (sha256)
    oaiToolchain        ## toolchain version string

func `$`*(input: ObservedAuditInput): string {.raises: [].} =
  case input
  of oaiSubjectSnapshot: "subject_snapshot"
  of oaiBaseline: "baseline"
  of oaiGatePolicy: "gate_policy"
  of oaiGateImplementation: "gate_implementation"
  of oaiToolchain: "toolchain"

# ---------------------------------------------------------------------------
# Adapter: ProbeReadClass -> ReadClass (1:1 for all 15 mirrored values)
# Do NOT change probe semantics. Do NOT add new ReadClass values.
# ---------------------------------------------------------------------------

func probeReadClassToReadClass*(prc: ProbeReadClass): ReadClass {.raises: [].} =
  case prc
  of prcModuleContent:    rcModuleContent
  of prcModuleExistence:  rcModuleExistence
  of prcTestGateway:      rcTestGateway
  of prcManualFeature:    rcManualFeature
  of prcBaseline:         rcBaseline
  of prcLockFile:         rcLockFile
  of prcPolicy:           rcPolicy
  of prcCommitId:         rcCommitId
  of prcTimestamp:        rcTimestamp
  of prcHistory:          rcHistory
  of prcGateOutput:       rcGateOutput
  of prcEnvVar:           rcEnvVar
  of prcCwd:              rcCwd
  of prcCompilerSubprocess: rcCompilerSubprocess
  of prcOther:            rcOther

# ---------------------------------------------------------------------------
# ObservedAuditContract — observation-only contract object
# ---------------------------------------------------------------------------

type
  ObservedAuditContract* = object
    subjectSnapshot*: SnapshotDigest
    baseline*: BaselineDigest
    gatePolicy*: PolicyDigest
    gateImplementation*: GateImplDigest
    toolchain*: string
    couplingFlags*: seq[string]
    provisional*: bool

func newObservedAuditContract*(
  subjectSnapshot: SnapshotDigest;
  baseline: BaselineDigest;
  gatePolicy: PolicyDigest;
  gateImplementation: GateImplDigest;
  toolchain: string;
  couplingFlags: seq[string] = @[];
  provisional: bool = true
): ObservedAuditContract {.raises: [].} =
  ObservedAuditContract(
    subjectSnapshot: subjectSnapshot,
    baseline: baseline,
    gatePolicy: gatePolicy,
    gateImplementation: gateImplementation,
    toolchain: toolchain,
    couplingFlags: couplingFlags,
    provisional: provisional
  )

# ---------------------------------------------------------------------------
# ObservedAuditResult — observation-only result object
# ---------------------------------------------------------------------------

type
  ObservedAuditResult* = object
    observedDomainCount*: int
    expectedDomainCount*: int
    verdict*: string
    couplingFlags*: seq[string]
    observationStatus*: ObservationStatus

func newObservedAuditResult*(
  observedDomainCount: int;
  expectedDomainCount: int;
  verdict: string;
  couplingFlags: seq[string] = @[];
  observationStatus: ObservationStatus = osComplete
): ObservedAuditResult {.raises: [].} =
  ObservedAuditResult(
    observedDomainCount: observedDomainCount,
    expectedDomainCount: expectedDomainCount,
    verdict: verdict,
    couplingFlags: couplingFlags,
    observationStatus: observationStatus
  )

# ---------------------------------------------------------------------------
# Resolve — FAIL-CLOSED: if any dependency is osUnknown/osUnclassified/
# osIncomplete, the result's observationStatus must reflect that and
# reuse is prohibited. Unknown → fail-closed.
# ---------------------------------------------------------------------------

func resolve*(r: ObservedAuditResult): DependencyResolution {.raises: [].} =
  if r.observationStatus in {osUnknown, osUnclassified, osIncomplete}:
    drFailClosed
  elif r.observationStatus == osComplete and r.verdict == "PASS":
    drDeclared
  else:
    drRecompute

# ---------------------------------------------------------------------------
# Classification helpers — tie to confirmed auditor semantics
# ---------------------------------------------------------------------------

func isReusable*(r: ObservedAuditResult): bool {.raises: [].} =
  ## True iff the result passes fail-closed reuse check.
  resolve(r) == drDeclared

func classifyInput*(input: ObservedAuditInput): VerificationDependencyKind {.raises: [].} =
  case input
  of oaiSubjectSnapshot: dkSemantic
  of oaiBaseline:        dkSemantic
  of oaiGatePolicy:     dkSemantic
  of oaiGateImplementation: dkSemantic
  of oaiToolchain:      dkProvenance

# ---------------------------------------------------------------------------
# I/O helpers — read actual data from the confirmed source paths
# ---------------------------------------------------------------------------

{.pop.}

proc readBaseline*(repoRoot: string): BaselineDigest {.
  axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect],
  raises: [OSError, IOError, CatchableError].} =
  ## Read data/verification_auditor_baseline.json and return its SHA-256 digest.
  let path = repoRoot / "data" / "verification_auditor_baseline.json"
  if not fileExists(path):
    return newBaselineDigest(hash_kernel.sha256Hex(""))
  let content = readFile(path)
  newBaselineDigest(hash_kernel.sha256Hex(content))

proc readPolicy*(repoRoot: string): PolicyDigest {.
  axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect],
  raises: [OSError, IOError, CatchableError].} =
  ## Read config/gates.json and return its SHA-256 digest.
  let path = repoRoot / "config" / "gates.json"
  if not fileExists(path):
    return newPolicyDigest(hash_kernel.sha256Hex(""))
  let content = readFile(path)
  newPolicyDigest(hash_kernel.sha256Hex(content))

proc computeSubjectSnapshot*(repoRoot: string; includeDirs: seq[string] = @["src"]): SnapshotDigest {.
  axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect],
  raises: [OSError, IOError, CatchableError].} =
  ## Walk the live source tree (*.nim files) and produce a SHA-256 digest
  ## over concatenated file contents — mirrors auditDirectory("src") semantics.
  var contents: seq[string] = @[]
  for dir in includeDirs:
    let fullDir = repoRoot / dir
    if not dirExists(fullDir): continue
    for path in walkDirRec(fullDir):
      if path.endsWith(".nim"):
        try:
          contents.add(readFile(path))
        except CatchableError:
          discard  # axiom:best-effort(best-effort read - does not affect verdict)
  if contents.len == 0:
    return newSnapshotDigest(hash_kernel.sha256Hex(""))
  contents.sort()
  newSnapshotDigest(hash_kernel.sha256Hex(contents.join("\n")))

proc computeGateImplementationDigest*(binaryPath: string): GateImplDigest {.
  axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect],
  raises: [OSError, IOError, CatchableError].} =
  ## Hash the gate implementation binary to produce the GateImplDigest.
  if not fileExists(binaryPath):
    return newGateImplDigest(hash_kernel.sha256Hex(""))
  let content = readFile(binaryPath)
  newGateImplDigest(hash_kernel.sha256Hex(content))

proc detectSelfCalibration*(repoRoot: string): bool {.
  axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect],
  raises: [OSError, IOError, CatchableError].} =
  ## Observe whether data/verification_auditor_baseline.json exists
  ## and is writable — a proxy for self-calibration coupling.
  ## Returns true when baseline exists and appears authoritative.
  let baselinePath = repoRoot / "data" / "verification_auditor_baseline.json"
  if fileExists(baselinePath):
    try:
      let content = readFile(baselinePath)
      let parsed = parseJson(content)
      if parsed.hasKey("domain_count"):
        return true
    except CatchableError:
      discard  # axiom:best-effort(best-effort read - does not affect verdict)
  false

func buildObservedAuditResult*(
  observedDomainCount: int;
  expectedDomainCount: int;
  couplingFlags: seq[string] = @[];
  observationStatus: ObservationStatus = osComplete
): ObservedAuditResult {.raises: [].} =
  ## Construct an ObservedAuditResult with a derived verdict.
  let verdict = if observedDomainCount == expectedDomainCount: "PASS" else: "FAIL"
  ObservedAuditResult(
    observedDomainCount: observedDomainCount,
    expectedDomainCount: expectedDomainCount,
    verdict: verdict,
    couplingFlags: couplingFlags,
    observationStatus: observationStatus
  )