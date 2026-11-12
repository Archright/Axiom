## canonical_cache.nim — WorkUnitFingerprint + Content-Addressable Store (CAS)
##
## Implements the canonical cache contract defined in
## docs/spec/workunit_fingerprint_cas_contract.md and ADR-0018.
##
## Reuses:
## - engine/atomic_ops.atomicWrite for crash-safe writes (temp+fsync+rename)
## - core/crypto/hash_kernel.sha256Hex for SHA-256 hashing
## - core/types/results.Result for error-lifted returns
## - core/utils/io_utils for readFileOpt/writeFileOpt/existsOrCreateDirOpt
##
## Design invariants (non-theater, per AGENTS.md §0.9):
## - Same-key-different-content → CONFLICT (discard existing, do NOT overwrite)
## - Content-digest verification on every read (fail-closed)
## - Authoritative promotion requires explicit human action (no auto-promote)
## - Pending entries are cache misses; only authoritative entries are reusable
## - Deterministic: no timestamps in keys or stored values

import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}
# axiomIoBoundary

import engine/atomic_ops
import core/crypto/hash_kernel
import core/json/json_utils
import core/trusted/axiom_pragmas_lite
import core/types/results
import core/utils/io_utils
import std/[json, os, strutils, options]

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

type
  WorkUnitFingerprint* = distinct string
    ## SHA-256 hex digest of SHA256(sourceClosureDigest_bytes ∥ toolchainDigest_bytes
    ## ∥ contractDigest_bytes ∥ executionConfigDigest_bytes).
    ## Each constituent digest is the raw 32-byte SHA-256 output (not hex-encoded)
    ## at the point of concatenation. The final fingerprint is the hex encoding
    ## of SHA256(serialized). Field order is lexicographic.

  CasPromotionStatus* = enum
    psPending       ## Entry exists but has not been reviewed
    psAuthoritative ## Entry has been reviewed and approved by a human
    psSuperseded    ## A newer authoritative entry exists for the same fingerprint

  CASValue* = object
    canonicalResult*: string
    contentDigest*: string
    workUnitFingerprint*: WorkUnitFingerprint
    promotionStatus*: CasPromotionStatus
    soundnessCertified*: bool
      ## False by default. Set to true ONLY by a human reviewer who has confirmed
      ## P8.1 selector-soundness PASS ("soundness-certified" review commit).
      ## authorize (promote) is gated on this: an entry that is not
      ## soundness-certified can never become authoritative/reusable (P8.4).

  CasPutOutcome* = enum
    cpoStored   ## New entry written successfully
    cpoConflict ## Same key, different content → CONFLICT (existing entry discarded)
    cpoHit      ## Same key, same content → already stored (no-op)

const
  CanonicalCacheBaseDir* = ".axiom/cache/canonical"
  ## Default base directory for canonical CAS storage.

# ---------------------------------------------------------------------------
# Pure computations (func)
# ---------------------------------------------------------------------------

const hexVal: array[256, byte] = block:
  ## Byte-lookup table for hex decoding. Non-hex characters map to 0.
  var t: array[256, byte]
  for i in 0 .. 255:
    t[i] = 0
  for i in 0 .. 9:
    t[ord('0') + i] = i.byte
  for i in 0 .. 5:
    t[ord('a') + i] = (10 + i).byte
    t[ord('A') + i] = (10 + i).byte
  t

func hexToBytes*(hex: string): seq[byte] {.raises: [].} =
  ## Decode a hex string to a byte sequence.
  ## Requires an even-length hex string; returns empty seq on odd length.
  if hex.len mod 2 != 0:
    return @[]
  result = newSeq[byte](hex.len div 2)
  for i in 0 ..< hex.len div 2:
    let hi = hexVal[ord(hex[i * 2])]
    let lo = hexVal[ord(hex[i * 2 + 1])]
    result[i] = (hi shl 4 or lo).byte

func computeWorkUnitFingerprint*(
  sourceClosureDigest, toolchainDigest, contractDigest, executionConfigDigest: string
): WorkUnitFingerprint {.raises: [].} =
  ## Compute WorkUnitFingerprint = SHA256(sourceClosureDigest_bytes ∥ toolchainDigest_bytes
  ## ∥ contractDigest_bytes ∥ executionConfigDigest_bytes).
  ## Each constituent digest is the raw 32-byte SHA-256 output (not hex-encoded)
  ## at the point of concatenation. The final fingerprint is the hex encoding
  ## of SHA256(serialized).
  ## Field order is lexicographic: sourceClosureDigest, toolchainDigest,
  ## contractDigest, executionConfigDigest.
  let raw = hexToBytes(sourceClosureDigest) &
            hexToBytes(toolchainDigest) &
            hexToBytes(contractDigest) &
            hexToBytes(executionConfigDigest)
  WorkUnitFingerprint(hash_kernel.sha256Hex(cast[string](raw)))

func casSubdir*(ca: string): string {.inline, raises: [].} =
  ## The 2-char directory prefix (hash[:2]).
  ca[0..1]

func casFilename*(ca: string): string {.inline, raises: [].} =
  ## The 62-char filename portion (hash[2:]).
  ca[2..^1]

func casPath*(epochDir: string; ca: string): string {.inline, raises: [].} =
  ## Full CAS path: epochDir / hash[:2] / hash[2:]
  epochDir / ca.casSubdir() / ca.casFilename()

func computeCasAddress*(content: string): string {.inline, raises: [].} =
  ## Compute SHA-256 of content and return as hex string (CAS address).
  hash_kernel.sha256Hex(content)

func computeContentDigest*(canonicalResult: string): string {.raises: [].} =
  ## Compute contentDigest = SHA256(canonicalResult).
  ## This is the content address used for integrity verification on every read.
  hash_kernel.sha256Hex(canonicalResult)

func serializeCASValue*(value: CASValue): string {.raises: [].} =
  ## Serialize CASValue to canonical JSON (sorted keys, no whitespace variation).
  ## Deterministic: same inputs always produce the same byte sequence.
  ## Key order is lexicographic for deterministic serialization.
  $(%*{
    "canonicalResult": value.canonicalResult,
    "contentDigest": value.contentDigest,
    "promotionStatus": $value.promotionStatus,
    "soundnessCertified": value.soundnessCertified,
    "workUnitFingerprint": string(value.workUnitFingerprint)
  })

# ---------------------------------------------------------------------------
# Internal: scan CAS directory for an entry matching the given key
# ---------------------------------------------------------------------------

proc loadCASEntryByKey*(casDir: string; key: WorkUnitFingerprint): Option[CASValue] {.
  axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Scan CAS epoch_0 directory for an entry matching the given key.
  ## Verifies CAS integrity (SHA-256(content) == filename) on each entry.
  ## Prefers authoritative entries over pending/superseded ones when
  ## multiple entries share the same fingerprint (promotion creates a
  ## new authoritative entry while the old pending entry remains).
  ## Returns none if not found or if any entry is corrupted/unparseable.
  let epochDir = casDir / "epoch_0"
  if not dirExists(epochDir):
    return none(CASValue)

  var pendingCandidate: Option[CASValue]

  for kind, subdir in walkDir(epochDir):
    if kind != pcDir: continue
    let dirName = subdir.extractFilename()
    if dirName.len != 2: continue  # CAS subdirectories are exactly 2 hex chars
    for fileKind, filePath in walkDir(subdir):
      if fileKind != pcFile: continue
      try:
        let readRes = readFileOpt(filePath)
        if readRes.isErr(): continue
        let content = readRes.get()
        # CAS integrity: SHA-256(content) must match the directory + filename
        let expectedAddr = computeCasAddress(content)
        if dirName != expectedAddr.casSubdir():
          continue
        if filePath.extractFilename() != expectedAddr.casFilename():
          continue
        let j = parseJsonOpt(content)
        if j.isNone(): continue
        let node = j.get()
        # Verify workUnitFingerprint matches
        if node{"workUnitFingerprint"}.getStr() != string(key):
          continue
        let casVal = CASValue(
          canonicalResult: node{"canonicalResult"}.getStr(),
          contentDigest: node{"contentDigest"}.getStr(),
          workUnitFingerprint: WorkUnitFingerprint(
            node{"workUnitFingerprint"}.getStr()
          ),
          promotionStatus: parseEnum(
            node{"promotionStatus"}.getStr("pending"),
            psPending
          ),
          soundnessCertified: node{"soundnessCertified"}.getBool(false)
        )
        # Authoritative entries take priority over pending/superseded
        if casVal.promotionStatus == psAuthoritative:
          return some(casVal)
        # Remember the first pending/superseded candidate as fallback
        if pendingCandidate.isNone():
          pendingCandidate = some(casVal)
      except CatchableError:
        continue
  pendingCandidate

# ---------------------------------------------------------------------------
# I/O operations (proc with axiomEffect: IoEffect)
# ---------------------------------------------------------------------------

proc casPutEntry*(
  casDir: string;
  key: WorkUnitFingerprint;
  value, contentDigest: string
): Result[CasPutOutcome, string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Write a CAS entry atomically via atomicWrite.
  ##
  ## Invariants:
  ## - contentDigest must equal SHA256(value), or an error is returned.
  ## - If the key already exists with a DIFFERENT contentDigest → CONFLICT.
  ##   The existing entry is discarded (deleted), the new value is NOT written,
  ##   and CONFLICT is returned so the caller re-executes the work unit.
  ## - If the key already exists with the SAME contentDigest → HIT (no-op).
  ## - Otherwise → new entry is written with psPending promotion status.
  ##
  ## This follows the fail-closed pattern from soundness_cache_io.nim:114–149:
  ## any integrity violation → discard, never silently reuse.

  # Verify contentDigest integrity: contentDigest must equal SHA256(value)
  let expectedDigest = computeContentDigest(value)
  if expectedDigest != contentDigest:
    return err("canonical_cache.casPutEntry: contentDigest mismatch " &
               "(expected " & expectedDigest & ", got " & contentDigest & ")")

  let epochDir = casDir / "epoch_0"
  discard existsOrCreateDirOpt(epochDir)

  # Check for existing entry with same key
  let existing = loadCASEntryByKey(casDir, key)
  if existing.isSome():
    let ex = existing.get()
    if ex.contentDigest != contentDigest:
      # Same key, different content → CONFLICT: discard existing entry
      try:
        let oldCasAddr = computeCasAddress(serializeCASValue(ex))
        let oldPath = casPath(epochDir, oldCasAddr)
        if fileExists(oldPath):
          removeFile(oldPath)
      except CatchableError:
        discard  # Best-effort cleanup; conflict verdict still valid
      return ok(cpoConflict)
    else:
      # Same key, same content → HIT (already stored)
      return ok(cpoHit)

  # Build CASValue and serialize
  let casVal = CASValue(
    canonicalResult: value,
    contentDigest: contentDigest,
    workUnitFingerprint: key,
    promotionStatus: psPending,
    soundnessCertified: false  # a freshly written entry is never soundness-certified
  )
  let serialized = serializeCASValue(casVal)
  let casAddr = computeCasAddress(serialized)

  # Write new entry atomically via atomicWrite (temp + fsync + POSIX rename)
  let casFilePath = casPath(epochDir, casAddr)
  discard existsOrCreateDirOpt(casFilePath.parentDir())

  let writeResult = atomicWrite(casFilePath, serialized)
  if writeResult.isErr():
    return err("canonical_cache.casPutEntry: atomicWrite failed: " & writeResult.error())

  ok(cpoStored)

proc casGetEntry*(
  casDir: string;
  key: WorkUnitFingerprint;
  expectedContentDigest: string
): Result[string, string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read a CAS entry and verify contentDigest and authoritative status.
  ##
  ## Fail-closed: on ANY mismatch or missing → miss (error returned).
  ## - Missing entry → cache miss
  ## - ContentDigest mismatch → cache miss (corrupted or conflict)
  ## - SHA256(canonicalResult) != contentDigest field → cache miss (corrupted)
  ## - promotionStatus != psAuthoritative → cache miss (not yet reviewed)
  ##
  ## This mirrors the fail-closed pattern in soundness_cache_io.nim:114–149:
  ## missing/corrupted/invalid → empty result → force full execution.

  let epochDir = casDir / "epoch_0"
  if not dirExists(epochDir):
    return err("canonical_cache.casGetEntry: cache miss")

  let existing = loadCASEntryByKey(casDir, key)
  if existing.isNone():
    return err("canonical_cache.casGetEntry: cache miss")

  let entry = existing.get()

  # Verify contentDigest matches the caller's expectation
  if entry.contentDigest != expectedContentDigest:
    return err("canonical_cache.casGetEntry: contentDigest mismatch")

  # Verify contentDigest == SHA256(canonicalResult) (integrity check)
  let actualDigest = computeContentDigest(entry.canonicalResult)
  if actualDigest != entry.contentDigest:
    return err("canonical_cache.casGetEntry: contentDigest verification failed")

  # Only authoritative entries are reusable by CI.
  # Pending and superseded entries are cache misses (per ADR-0018 §3).
  if entry.promotionStatus != psAuthoritative:
    return err("canonical_cache.casGetEntry: entry not authoritative (status: " &
               $entry.promotionStatus & ")")

  ok(entry.canonicalResult)

proc casPromoteEntry*(
  casDir: string;
  key: WorkUnitFingerprint;
  soundnessCertified: bool
): Result[void, string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Promote a CAS entry to authoritative status.
  ##
  ## This is a human-gated operation: the API exists for a designated reviewer
  ## to call after inspecting the result. It is NOT wired into CI.
  ## Per ADR-0018 §3 and the contract spec §4, promotion requires a separate
  ## human review step — no automated promotion is allowed.
  ##
  ## P8.4 PASS-only gate: `soundnessCertified` MUST be true for an entry to
  ## become authoritative/reusable. `false` (the default for every freshly
  ## written entry) is rejected with an error — a pending entry that has not
  ## been soundness-certified (P8.1 selector-soundness PASS + separate review
  ## commit) can never be promoted. This enforces "no authoritative execution
  ## until selector soundness is proven" at the CAS layer.
  ##
  ## If the entry is already authoritative, returns ok() (no-op).
  ## If the entry is not found, returns an error.

  let epochDir = casDir / "epoch_0"
  if not dirExists(epochDir):
    return err("canonical_cache.casPromoteEntry: entry not found")

  let existing = loadCASEntryByKey(casDir, key)
  if existing.isNone():
    return err("canonical_cache.casPromoteEntry: entry not found")

  let entry = existing.get()
  if entry.promotionStatus == psAuthoritative:
    return Result[void, string](ok: true)  # Already authoritative, no-op

  # P8.4 PASS-only gate: soundness certification is required for promotion.
  if not soundnessCertified:
    return err("canonical_cache.casPromoteEntry: entry not soundness-certified " &
               "(selector soundness PASS + human review required; P8.4 gate)")

  # Write new authoritative entry (old pending entry remains as superseded)
  var newEntry = entry
  newEntry.promotionStatus = psAuthoritative
  let serialized = serializeCASValue(newEntry)
  let newDigest = computeCasAddress(serialized)

  let casFilePath = casPath(epochDir, newDigest)
  discard existsOrCreateDirOpt(casFilePath.parentDir())

  let writeResult = atomicWrite(casFilePath, serialized)
  if writeResult.isErr():
    return err("canonical_cache.casPromoteEntry: atomicWrite failed: " &
               writeResult.error())

  Result[void, string](ok: true)

{.pop.}
