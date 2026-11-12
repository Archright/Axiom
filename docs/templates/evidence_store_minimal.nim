## Minimal IEvidenceStore implementation
## Copy this file and customize the storage backend.
## axiom:template-implementation — all TODOs replaced with working examples

import std/[json, os, tables, strutils]

# === Inline interface types (copy into your project if needed) ===

type
  EvidenceReceipt* = object
    agentId*: string
    postConditions*: seq[string]
    verificationCommands*: seq[string]
    headHash*: string

  EvidenceStoreBackend* = enum
    BackendMemory   ## In-memory only, no persistence
    BackendFile     ## JSON file on disk
    BackendBoth     ## Memory + file fallback

# === Configurable constants ===

const
  DefaultEvidenceDir* = "data/evidence"
  DefaultEvidenceFile* = "evidence_store.json"
  DefaultMaxReceipts* = 10000

# === State fields: dual-backend support ===

type
  MyEvidenceStore* = object
    ## Example backends: in-memory ring buffer + optional JSON file persistence.
    ## BackendMemory  — ephemeral receipts (process lifetime only)
    ## BackendFile    — persists receipt index to a JSON file
    ## BackendBoth    — both; file used as crash recovery source
    receipts*: seq[EvidenceReceipt]              # In-memory store (ring buffer)
    verified*: OrderedTable[string, bool]        # agentId -> verification result
    backend*: EvidenceStoreBackend               # Selected persistence mode
    evidenceDir*: string                         # Directory for JSON file
    evidenceFile*: string                        # Full path to JSON file
    maxReceipts*: int                            # Max receipts in memory before eviction

proc newMyEvidenceStore*(
  backend: EvidenceStoreBackend = BackendBoth,
  maxReceipts: int = DefaultMaxReceipts
): MyEvidenceStore =
  ## Initialize store with chosen backend and default paths.
  MyEvidenceStore(
    receipts: @[],
    verified: initOrderedTable[string, bool](),
    backend: backend,
    evidenceDir: DefaultEvidenceDir,
    evidenceFile: DefaultEvidenceDir / DefaultEvidenceFile,
    maxReceipts: maxReceipts
  )

proc loadFromFile*(s: var MyEvidenceStore) =
  ## Load persisted receipt IDs from JSON file (used for crash recovery).
  if not fileExists(s.evidenceFile):
    return
  try:
    let content = readFile(s.evidenceFile)
    let j = parseJson(content)
    if j.kind == JObject and "verified" in j:
      for kv in j["verified"].pairs:
        s.verified[kv[0]] = kv[1].getBool
  except:
    discard  # Corrupted file - start fresh

proc persistToFile*(s: MyEvidenceStore) =
  ## Write current verified set to JSON file for durability.
  if s.backend == BackendMemory:
    return  # No persistence requested
  try:
    createDir(s.evidenceDir)
    var j = newJObject()
    let verifiedObj = newJObject()
    for kv in s.verified.pairs:
      verifiedObj[kv[0]] = newJBool(kv[1])
    j["verified"] = verifiedObj
    writeFile(s.evidenceFile, $j)
  except:
    discard  # File system error - in-memory state is still valid

proc store*(s: var MyEvidenceStore, receipt: EvidenceReceipt) =
  ## Store receipt and mark agent as verified. Runs simple post-condition checks.
  ##
  ## Verification steps:
  ##   1. Validate that headHash is non-empty (basic integrity check)
  ##   2. Verify each postCondition has at least one character of content
  ##   3. Record verification result keyed by agentId
  ##   4. Persist to file if configured

  # Basic integrity: headHash must be non-empty
  let hashOk = receipt.headHash.len > 0

  # Post-condition sanity: each condition must be non-empty
  var conditionsOk = true
  for cond in receipt.postConditions:
    if cond.strip().len == 0:
      conditionsOk = false
      break

  let verified = hashOk and conditionsOk
  s.verified[receipt.agentId] = verified

  # Add to in-memory receipt log
  s.receipts.add(receipt)

  # Ring buffer eviction: remove oldest when over capacity
  if s.receipts.len > s.maxReceipts:
    let keep = s.receipts.len - s.maxReceipts
    s.receipts = s.receipts[keep ..< s.receipts.len]

  # Persist to file backend
  persistToFile(s)

proc verify*(s: MyEvidenceStore, agentId: string): bool =
  ## Check if an agent's evidence was previously verified.
  ## Returns false if the agent is unknown or was not verified.
  if agentId notin s.verified:
    return false
  s.verified[agentId]

proc getVerificationResult*(s: MyEvidenceStore, agentId: string): tuple[ok: bool, known: bool] =
  ## Returns (ok, known) where ok = whether verification passed,
  ## and known = whether this agent_id was ever recorded.
  if agentId notin s.verified:
    return (ok: false, known: false)
  (ok: s.verified[agentId], known: true)

proc receiptCount*(s: MyEvidenceStore): int =
  ## Number of receipts currently held in memory.
  s.receipts.len

proc clearVerified*(s: var MyEvidenceStore, agentId: string) =
  ## Remove verification record for an agent (useful for re-verification).
  s.verified.del(agentId)
  persistToFile(s)

# === TEST SKELETON ===

when isMainModule:
  # Test with memory-only backend
  var s = newMyEvidenceStore(backend = BackendMemory, maxReceipts = 5)

  block test_store_and_verify:
    let r = EvidenceReceipt(
      agentId: "test-agent",
      postConditions: @["file created", "hash matched"],
      verificationCommands: @["ls test-file"],
      headHash: "abc123"
    )
    s.store(r)
    assert s.verify("test-agent"), "test-agent should be verified"
    echo "store and verify works"

  block test_unknown_agent:
    assert not s.verify("unknown-agent"), "unknown agent should not exist"
    echo "unknown agent returns false"

  block test_get_verification_result:
    var (ok, known) = s.getVerificationResult("test-agent")
    assert ok, "should be verified"
    assert known, "should be known"
    (ok, known) = s.getVerificationResult("ghost")
    assert not ok
    assert not known
    echo "getVerificationResult works"

  block test_invalid_receipt:
    var s2 = newMyEvidenceStore(backend = BackendMemory)
    let bad = EvidenceReceipt(
      agentId: "bad-agent",
      postConditions: @[],
      verificationCommands: @[],
      headHash: ""  # empty hash fails validation
    )
    s2.store(bad)
    assert not s2.verify("bad-agent"), "empty hash should fail verification"
    echo "invalid receipt rejected"

  block test_ring_buffer_eviction:
    var s3 = newMyEvidenceStore(backend = BackendMemory, maxReceipts = 3)
    for i in 1..5:
      let r = EvidenceReceipt(
        agentId: "agent-" & $i,
        postConditions: @["ok"],
        verificationCommands: @["echo ok"],
        headHash: "hash" & $i
      )
      s3.store(r)
    assert s3.receiptCount() == 3, "should have exactly 3 receipts after eviction"
    assert s3.verify("agent-1") == false, "oldest should have been evicted"
    assert s3.verify("agent-5"), "newest should be present"
    echo "ring buffer eviction works"

  block test_clear_verified:
    var s4 = newMyEvidenceStore(backend = BackendMemory)
    let r = EvidenceReceipt(
      agentId: "clear-me",
      postConditions: @["done"],
      verificationCommands: @["true"],
      headHash: "xyz"
    )
    s4.store(r)
    assert s4.verify("clear-me")
    s4.clearVerified("clear-me")
    assert not s4.verify("clear-me"), "should be cleared"
    echo "clearVerified works"

  echo "All tests passed."
