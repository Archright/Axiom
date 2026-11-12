## semantic_query_types.nim — Semantic Query Contract + Declared Input Model
##
## Verification-auditor gate = static snapshot audit (NOT a base/head transition).
## Its verdict-path semantic inputs are six typed digests plus the SelectionRule
## digest. The query model (approved plan):
##
##   Query = f(SnapshotDigest, TestClosureDigest, BaselineDigest,
##             LockDigest, PolicyDigest, GateImplDigest, SelectionRuleDigest)
##
## Commit/branch/path/time are provenance-only (provable), not verdict inputs.
##
## Precedent: src/verification/canonical_cache.nim WorkUnitFingerprint
## (raw-32-byte concat then hex) and
## src/core/trusted/scope_identity.nim canonicalScopeDigest (combineHashes).

import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import std/[algorithm, strutils]
import core/crypto/hash_kernel

# ---------------------------------------------------------------------------
# Byte utility (follows computeWorkUnitFingerprint raw-32-byte-concat pattern)
# ---------------------------------------------------------------------------

const hexVal: array[256, byte] = block:
  var t: array[256, byte]
  for i in 0 ..< 256: t[i] = 0
  for i in 0 ..< 10: t[i + ord('0')] = byte(i)
  for i in 0 ..< 6:
    t[i + ord('a')] = byte(10 + i)
    t[i + ord('A')] = byte(10 + i)
  t

func hexToBytes*(hex: string): seq[byte] {.raises: [].} =
  ## Decode a hex string to raw bytes. Returns empty seq on odd length.
  if hex.len mod 2 != 0: return @[]
  result = newSeq[byte](hex.len div 2)
  for i in 0 ..< hex.len div 2:
    result[i] = (hexVal[ord(hex[i * 2])] shl 4) or hexVal[ord(hex[i * 2 + 1])]

# ---------------------------------------------------------------------------
# Distinct digest types (SHA-256 hex, distinct string)
# ---------------------------------------------------------------------------

type
  SnapshotDigest* = distinct string
    ## SHA-256 hex digest of the live working-tree snapshot.
  TestClosureDigest* = distinct string
    ## SHA-256 hex digest of the test closure (tests/gateway/*.nim +
    ## tests/features/*.feature).
  BaselineDigest* = distinct string
    ## SHA-256 hex digest of data/verification_auditor_baseline.json content.
  LockDigest* = distinct string
    ## SHA-256 hex digest of topology.lock content.
  PolicyDigest* = distinct string
    ## SHA-256 hex digest of the policy config (config/gates.json etc.).
  GateImplDigest* = distinct string
    ## SHA-256 hex digest of the gate implementation binary/source.
  QueryID* = distinct string
    ## SHA-256 hex digest of the canonical query component concatenation.
  GateId* = distinct string
    ## Gate identifier (provenance metadata, NOT a query-identity component).

# ---------------------------------------------------------------------------
# Constructors
# ---------------------------------------------------------------------------

func newSnapshotDigest*(hex: string): SnapshotDigest = SnapshotDigest(hex)
func newTestClosureDigest*(hex: string): TestClosureDigest = TestClosureDigest(hex)
func newBaselineDigest*(hex: string): BaselineDigest = BaselineDigest(hex)
func newLockDigest*(hex: string): LockDigest = LockDigest(hex)
func newPolicyDigest*(hex: string): PolicyDigest = PolicyDigest(hex)
func newGateImplDigest*(hex: string): GateImplDigest = GateImplDigest(hex)
func newQueryID*(hex: string): QueryID = QueryID(hex)
func newGateId*(id: string): GateId = GateId(id)

# ---------------------------------------------------------------------------
# `$` for distinct string types
# ---------------------------------------------------------------------------

func `$`*(d: SnapshotDigest): string {.raises: [].} = string(d)
func `$`*(d: TestClosureDigest): string {.raises: [].} = string(d)
func `$`*(d: BaselineDigest): string {.raises: [].} = string(d)
func `$`*(d: LockDigest): string {.raises: [].} = string(d)
func `$`*(d: PolicyDigest): string {.raises: [].} = string(d)
func `$`*(d: GateImplDigest): string {.raises: [].} = string(d)
func `$`*(d: QueryID): string {.raises: [].} = string(d)
func `$`*(d: GateId): string {.raises: [].} = string(d)

# ---------------------------------------------------------------------------
# Equality for distinct string types (compiler does not inherit ==)
# ---------------------------------------------------------------------------

func `==`*(a, b: SnapshotDigest): bool {.raises: [].} = string(a) == string(b)
func `==`*(a, b: TestClosureDigest): bool {.raises: [].} = string(a) == string(b)
func `==`*(a, b: BaselineDigest): bool {.raises: [].} = string(a) == string(b)
func `==`*(a, b: LockDigest): bool {.raises: [].} = string(a) == string(b)
func `==`*(a, b: PolicyDigest): bool {.raises: [].} = string(a) == string(b)
func `==`*(a, b: GateImplDigest): bool {.raises: [].} = string(a) == string(b)
func `==`*(a, b: QueryID): bool {.raises: [].} = string(a) == string(b)
func `==`*(a, b: GateId): bool {.raises: [].} = string(a) == string(b)

func `!=`*(a, b: SnapshotDigest): bool {.raises: [].} = string(a) != string(b)
func `!=`*(a, b: TestClosureDigest): bool {.raises: [].} = string(a) != string(b)
func `!=`*(a, b: BaselineDigest): bool {.raises: [].} = string(a) != string(b)
func `!=`*(a, b: LockDigest): bool {.raises: [].} = string(a) != string(b)
func `!=`*(a, b: PolicyDigest): bool {.raises: [].} = string(a) != string(b)
func `!=`*(a, b: GateImplDigest): bool {.raises: [].} = string(a) != string(b)
func `!=`*(a, b: QueryID): bool {.raises: [].} = string(a) != string(b)
func `!=`*(a, b: GateId): bool {.raises: [].} = string(a) != string(b)

# ---------------------------------------------------------------------------
# Selection rule — the selection rule ITSELF is a semantic input (approved
# plan): its canonical digest is a component of the query identity.
# ---------------------------------------------------------------------------

type
  SymlinkPolicy* = enum
    spFollowRegularFiles  ## Follow symlinks resolving to regular files
                         ## (hash target content); do not follow directory
                         ## symlinks.

  SelectionRule* = object
    includeDirs*: seq[string]  ## Directories to walk (e.g. @["src", "tests/features", "tests/gateway"]).
    skipDirs*: seq[string]     ## Directory names to skip (part of the selection rule).
    symlinkPolicy*: SymlinkPolicy
    version*: int

func selectionRuleDigest*(rule: SelectionRule): string {.raises: [].} =
  ## Canonical digest of a SelectionRule. Order-sensitive; sorts dir lists
  ## so the digest is independent of source ordering.
  let inc = rule.includeDirs.sorted.join(",")
  let skip = rule.skipDirs.sorted.join(",")
  let data = $rule.symlinkPolicy.int & ":" & inc & ":" & skip & ":" & $rule.version
  hash_kernel.sha256Hex(data)

# ---------------------------------------------------------------------------
# Semantic query object
# ---------------------------------------------------------------------------

type
  SemanticQuery* = object
    gateId*: GateId
    snapshot*: SnapshotDigest
    testClosure*: TestClosureDigest
    baseline*: BaselineDigest
    lock*: LockDigest
    policy*: PolicyDigest
    gateImpl*: GateImplDigest
    selectionRuleVersion*: string  ## Human-readable version tag for the rule.
    selectionRuleDigest*: string   ## Canonical digest of the SelectionRule (query-identity component).

func provisionalQueryID*(query: SemanticQuery): QueryID {.raises: [].} =
  ## Compute QueryID = SHA256 of canonical component concatenation.
  ##
  ## Components (raw 32-byte each, boundary-preserving):
  ##   snapshot, testClosure, baseline, lock, policy, gateImpl,
  ##   selectionRuleDigest — each decoded from hex to raw bytes,
  ##   concatenated in this order, then SHA-256'd and hex-encoded.
  ##
  ## GateId and selectionRuleVersion are NOT included: GateId is
  ## provenance (not a verdict-path input) and selectionRuleVersion
  ## is redundant with selectionRuleDigest (which embeds the version).
  let raw = hexToBytes(string(query.snapshot)) &
            hexToBytes(string(query.testClosure)) &
            hexToBytes(string(query.baseline)) &
            hexToBytes(string(query.lock)) &
            hexToBytes(string(query.policy)) &
            hexToBytes(string(query.gateImpl)) &
            hexToBytes(query.selectionRuleDigest)
  QueryID(hash_kernel.sha256Hex(cast[string](raw)))

{.pop.}
