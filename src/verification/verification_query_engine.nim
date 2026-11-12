## verification_query_engine.nim — Deterministic Semantic-Query Verification Engine
##
## Vertical slice: given a repo root + selection rule, computes the full
## SemanticQuery from live on-disk state and provides a fail-closed
## reuse decision API. Reuse is in-memory semantic logic only — no
## persistent cache/CAS store is introduced here.
##
## Reconciliation with observation_pipeline.nim:
##   - decideReuse delegates per-dependency decisions to resolve()
##   - Reuse requires QueryID equality AND all deps resolve to drDeclared
##   - Any Unknown/Incomplete/Unclassified → recompute (fail-closed)
##
## Precedent: semantic_query_types.nim (QueryID digest components),
## verification_dependency.nim (classifyReadClass / resolve),
## observation_pipeline.nim (3-stage typed pipeline).

import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}
# axiomIoBoundary

import core/trusted/axiom_pragmas_lite
import std/[os, strutils, algorithm]
import core/crypto/hash_kernel
import core/types/results
import verification/semantic_query_types
import verification/repo_snapshot_digest
import verification/verification_dependency
import verification/observation_pipeline

# ---------------------------------------------------------------------------
# Reuse decision — in-memory semantic logic only (no persistent store)
# ---------------------------------------------------------------------------

type
  ReuseDecisionKind* = enum
    rdReuse      # Reuse the stored verdict — safe to do so.
    rdRecompute  # Must recompute — fail-closed.

  ReuseDecision* = object
    ## Reuse decision. kind == rdReuse carries the stored verdict;
    ## kind == rdRecompute means recompute is required.
    kind*: ReuseDecisionKind
    verdict*: string  # Only meaningful when kind == rdReuse.

func newReuseDecision*(kind: ReuseDecisionKind; verdict: string = ""): ReuseDecision {.raises: [].} =
  ## Constructor for ReuseDecision.
  ReuseDecision(kind: kind, verdict: verdict)

func reuseDecision*(verdict: string): ReuseDecision {.raises: [].} =
  ## Construct a reuse decision carrying the stored verdict.
  ReuseDecision(kind: rdReuse, verdict: verdict)

func recomputeDecision(): ReuseDecision {.raises: [].} =
  ## Construct a recompute decision (fail-closed).
  ReuseDecision(kind: rdRecompute)

func `$`*(rd: ReuseDecision): string {.raises: [].} =
  ## Human-readable decision name.
  case rd.kind
  of rdReuse:   "Reuse(" & rd.verdict & ")"
  of rdRecompute: "Recompute"

# ---------------------------------------------------------------------------
# Stored verification result — carries the QueryID that was computed
# when the result was generated, plus the verdict.
# ---------------------------------------------------------------------------

type
  StoredVerificationResult* = object
    ## Previously verified result. Carries the QueryID under which
    ## it was produced so that reuse can be gated on QueryID equality.
    queryID*: QueryID
    verdict*: string  # e.g. "PASS" or "FAIL".

func newStoredVerificationResult*(query: SemanticQuery; verdict: string): StoredVerificationResult {.raises: [].} =
  ## Constructor: computes QueryID from the query.
  StoredVerificationResult(queryID: provisionalQueryID(query), verdict: verdict)

# ---------------------------------------------------------------------------
# Pure digest helpers
# ---------------------------------------------------------------------------

func computeContentDigest*(content: string): string {.raises: [].} =
  ## Pure SHA-256 hex digest of a string.
  hash_kernel.sha256Hex(content)

func computeTestClosureDigestFromContents*(contents: seq[string]): TestClosureDigest {.raises: [].} =
  ## Pure: compute TestClosureDigest from sorted file contents.
  var sorted = contents.sorted
  let data = sorted.join("\n")
  TestClosureDigest(hash_kernel.sha256Hex(data))

# ---------------------------------------------------------------------------
# I/O digest helpers (individual components)
# ---------------------------------------------------------------------------

proc computeTestClosureDigest*(repoRoot: string): Result[TestClosureDigest, string] {.
  axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect],
  raises: [CatchableError].} =
  ## I/O: walk tests/gateway/ and compute a deterministic digest
  ## over all *.feature and *.nim file contents.
  let gatewayDir = repoRoot / "tests" / "gateway"
  if not dirExists(gatewayDir):
    return ok(newTestClosureDigest(hash_kernel.sha256Hex("")))

  var entries: seq[string] = @[]
  for relPath in walkDirRec(gatewayDir, relative = true):
    let ext = relPath.splitFile.ext
    if ext notin [".feature", ".nim"]: continue
    # Skip any path component that starts with ".".
    var skip = false
    for part in relPath.split(DirSep):
      if part.startsWith("."): skip = true; break
    if skip: continue

    let absPath = gatewayDir / relPath
    if fileExists(absPath):
      let content = readFile(absPath)
      entries.add(relPath & ":" & content)

  if entries.len == 0:
    return ok(newTestClosureDigest(hash_kernel.sha256Hex("")))

  entries.sort()
  let allEntries = entries.join("\n")
  return ok(newTestClosureDigest(hash_kernel.sha256Hex(allEntries)))

proc computeBaselineDigest*(repoRoot: string): Result[BaselineDigest, string] {.
  axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect],
  raises: [CatchableError].} =
  ## I/O: read data/verification_auditor_baseline.json and hash its bytes.
  let path = repoRoot / "data" / "verification_auditor_baseline.json"
  if not fileExists(path):
    return ok(newBaselineDigest(hash_kernel.sha256Hex("")))
  let content = readFile(path)
  return ok(newBaselineDigest(hash_kernel.sha256Hex(content)))

proc computeLockDigest*(repoRoot: string): Result[LockDigest, string] {.
  axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect],
  raises: [CatchableError].} =
  ## I/O: read topology.lock and hash its bytes.
  let path = repoRoot / "topology.lock"
  if not fileExists(path):
    return ok(newLockDigest(hash_kernel.sha256Hex("")))
  let content = readFile(path)
  return ok(newLockDigest(hash_kernel.sha256Hex(content)))

proc computePolicyDigest*(repoRoot: string): Result[PolicyDigest, string] {.
  axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect],
  raises: [CatchableError].} =
  ## I/O: read config/gates.json and hash its bytes.
  let path = repoRoot / "config" / "gates.json"
  if not fileExists(path):
    return ok(newPolicyDigest(hash_kernel.sha256Hex("")))
  let content = readFile(path)
  return ok(newPolicyDigest(hash_kernel.sha256Hex(content)))

# ---------------------------------------------------------------------------
# Main builder: compute full SemanticQuery from live on-disk state
# ---------------------------------------------------------------------------

proc buildSemanticQuery*(
  repoRoot: string;
  gateImplIdentity: string;
  selectionRule: SelectionRule = DefaultSelectionRule
): Result[SemanticQuery, string] {.
  axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect],
  raises: [CatchableError].} =
  ## Compute the full SemanticQuery from the live on-disk state.
  ##
  ## Components (7, in canonical order used by provisionalQueryID):
  ##   1. snapshot       — computeRepoSnapshotDigest(repoRoot, rule)
  ##   2. testClosure    — hash of tests/gateway/*.feature + *.nim
  ##   3. baseline       — hash of data/verification_auditor_baseline.json
  ##   4. lock           — hash of topology.lock
  ##   5. policy         — hash of config/gates.json
  ##   6. gateImpl       — sha256Hex(gateImplIdentity)
  ##   7. selectionRule  — selectionRuleDigest(selectionRule)
  ##
  ## GateId and selectionRuleVersion are EXCLUDED: GateId is provenance
  ## (not a verdict-path input) and selectionRuleVersion is redundant
  ## with selectionRuleDigest (which embeds the version).

  # 1. Snapshot
  let snapshotRes = computeRepoSnapshotDigest(repoRoot, selectionRule)
  if snapshotRes.ok == false:
    return err("snapshot: " & snapshotRes.err)
  let snapshot = newSnapshotDigest(string(snapshotRes.value))

  # 2. Test closure
  let tcRes = computeTestClosureDigest(repoRoot)
  if tcRes.ok == false:
    return err("testClosure: " & tcRes.err)
  let testClosure = tcRes.value

  # 3. Baseline
  let baseRes = computeBaselineDigest(repoRoot)
  if baseRes.ok == false:
    return err("baseline: " & baseRes.err)
  let baseline = baseRes.value

  # 4. Lock
  let lockRes = computeLockDigest(repoRoot)
  if lockRes.ok == false:
    return err("lock: " & lockRes.err)
  let lock = lockRes.value

  # 5. Policy
  let polRes = computePolicyDigest(repoRoot)
  if polRes.ok == false:
    return err("policy: " & polRes.err)
  let policy = polRes.value

  # 6. GateImpl digest from passed-in identity
  let gateImpl = newGateImplDigest(hash_kernel.sha256Hex(gateImplIdentity))

  # 7. SelectionRule digest
  let selectionRuleDigestVal = selectionRuleDigest(selectionRule)

  # Assemble SemanticQuery.
  # Note: gateId is excluded (provenance); selectionRuleVersion is excluded
  # (redundant with selectionRuleDigest).
  let query = SemanticQuery(
    snapshot: snapshot,
    testClosure: testClosure,
    baseline: baseline,
    lock: lock,
    policy: policy,
    gateImpl: gateImpl,
    selectionRuleDigest: selectionRuleDigestVal
  )

  return ok(query)

# ---------------------------------------------------------------------------
# Reuse decision — fail-closed semantic logic
# ---------------------------------------------------------------------------

func decideReuse*(
  storedResult: StoredVerificationResult;
  currentQuery: SemanticQuery;
  observedDeps: seq[ValidatedDependency]
): ReuseDecision {.raises: [].} =
  ## Fail-closed reuse decision reconciled with observation_pipeline.resolve().
  ##
  ## Reuse is ALLOWED only when ALL of the following hold:
  ##   1. currentQuery's QueryID equals storedResult.queryID (identity match)
  ##   2. Every observed dependency resolves to drDeclared
  ##        (= dkSemantic AND osComplete)
  ## Otherwise RECOMPUTE is forced.
  ##
  ## Reconciliation with resolve():
  ##   - drDeclared  → SEMANTIC + Complete → reusable
  ##   - drRecompute → Incomplete / Unknown / non-SEMANTIC → must recompute
  ##   - drFailClosed → UNCLASSIFIED → fail-closed, no reuse
  ##   decideReuse delegates to resolve() so there is ONE consistent
  ##   semantic decision model — no parallel/contradictory memo subsystem.

  # Gate 1: QueryID must match exactly.
  let currentID = provisionalQueryID(currentQuery)
  if currentID != storedResult.queryID:
    return recomputeDecision()

  # Gate 2: All observed deps must resolve to drDeclared.
  for dep in observedDeps:
    case resolve(dep)
    of drDeclared:   discard
    of drRecompute:  return recomputeDecision()
    of drFailClosed: return recomputeDecision()

  return reuseDecision(storedResult.verdict)

# ---------------------------------------------------------------------------
# Canonical identity — a stable, content-addressed identity for reuse
# ---------------------------------------------------------------------------

type
  CanonicalIdentity* = distinct string
    ## Canonical verification identity derived from
    ## canonicalVerificationIdentity(sq, pi, closureDigest).

func newCanonicalIdentity*(hex: string): CanonicalIdentity {.raises: [].} =
  ## Constructor from a hex string.
  CanonicalIdentity(hex)

func `$`*(c: CanonicalIdentity): string {.raises: [].} = string(c)

func `==`*(a, b: CanonicalIdentity): bool {.raises: [].} = string(a) == string(b)
func `!=`*(a, b: CanonicalIdentity): bool {.raises: [].} = string(a) != string(b)

# ---------------------------------------------------------------------------
# Stored verification result — canonical identity variant
# ---------------------------------------------------------------------------

func newStoredVerificationResultCanonical*(identity: CanonicalIdentity; verdict: string): StoredVerificationResult {.raises: [].} =
  ## Constructor from a CanonicalIdentity and verdict.
  StoredVerificationResult(queryID: QueryID(string(identity)), verdict: verdict)

# ---------------------------------------------------------------------------
# Reuse decision — canonical identity variant
# ---------------------------------------------------------------------------

func decideReuseCanonical*(
  storedResult: StoredVerificationResult;
  currentIdentity: CanonicalIdentity;
  observedDeps: seq[ValidatedDependency]
): ReuseDecision {.raises: [].} =
  ## Fail-closed reuse decision reconciled with observation_pipeline.resolve().
  ##
  ## Reuse is ALLOWED only when ALL of the following hold:
  ##   1. currentIdentity equals the identity embedded in storedResult.queryID
  ##      (canonical identity match — single consistent decision model,
  ##       no parallel/contradictory logic).
  ##   2. Every observed dependency resolves to drDeclared
  ##        (= dkSemantic AND osComplete)
  ## Otherwise RECOMPUTE is forced.
  ##
  ## Gate 1: Canonical identity must match exactly.
  if string(currentIdentity) != string(storedResult.queryID):
    return recomputeDecision()
  ## Gate 2: All observed deps must resolve to drDeclared.
  for dep in observedDeps:
    case resolve(dep)
    of drDeclared:   discard
    of drRecompute:  return recomputeDecision()
    of drFailClosed: return recomputeDecision()
  return reuseDecision(storedResult.verdict)