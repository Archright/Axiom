import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

## Gate Daemon Protocol Types
##
## Defines the wire protocol for communication between the orchestrator
## (client) and the gate daemon (server). Uses line-based JSON over
## Unix domain sockets for simplicity and debuggability.
##
## Protocol flow:
##   1. Client connects to `.axiom/cache/gate-daemon.sock`
##   2. Client sends JSON request terminated by newline
##   3. Server sends JSON response terminated by newline
##   4. Client closes connection (or sends another request)
##
## SSOT: These types are shared between server and client.

import std/[json, tables]

const
  DaemonSocketPath* = ".axiom/cache/gate-daemon.sock"
  DaemonPidPath* = ".axiom/cache/gate-daemon.pid"
  DaemonProtocolVersion* = 2
  DaemonMaxRequestSize* = 64 * 1024  ## 64KB max request
  DaemonConnectTimeoutMs* = 10       ## 10ms fail-fast (CPU context switch margin)
  DaemonRequestTimeoutMs* = 5000     ## 5s per-request timeout

type
  DaemonMethod* = enum
    dmPing = "ping"
    dmCheckCache = "check_cache"
    dmPersistResult = "persist_result"
    dmInvalidate = "invalidate"
    dmShutdown = "shutdown"

  DaemonRequest* = object
    ## Client → Server request.
    version*: int            ## Protocol version (parsed from wire "v"; 0 if absent)
    mthd*: string           ## DaemonMethod as string (renamed from 'method' — Nim keyword)
    requestId*: string     ## Client-generated correlation ID
    gateId*: string        ## Gate ID (for check_cache / persist_result)
    subtreeRoot*: string   ## Merkle subtree root hash (CAS key)
    identity*: string      ## Opaque composite lock hash — consumed verbatim, never computed/rekeyed by daemon
    epoch*: int            ## Gate epoch (for staleness check)
    result*: bool          ## Gate result (for persist_result)
    failCategory*: string  ## Failure category (for persist_result on failure)
    failReason*: string    ## Failure reason (for persist_result on failure)

  DaemonResponse* = object
    ## Server → Client response.
    version*: int            ## Protocol version (parsed from wire "v"; 0 if absent)
    ok*: bool              ## true if request succeeded
    cached*: bool          ## true if cache hit (for check_cache)
    result*: bool          ## cached gate result (for check_cache)
    reason*: string        ## failure reason (for check_cache on cache-miss-fail)
    failCategory*: string  ## failure category (for check_cache on cache-miss-fail)
    revision*: int         ## current MemoDb revision (for diagnostics)
    message*: string       ## human-readable message (for ping / errors)

  CacheEntry* = object
    ## In-memory cache entry (replaces disk-based gate_history.jsonl).
    gateId*: string
    subtreeRoot*: string     ## Merkle subtree root (content-addressed key)
    identity*: string        ## Opaque composite lock hash — verbatim cache key, consume-only
    result*: bool            ## true = PASS, false = FAIL
    epoch*: int              ## epoch when result was recorded
    failCategory*: string    ## fcTransient, fcPermanent, etc.
    failReason*: string      ## human-readable failure reason
    timestamp*: int64        ## Unix timestamp (for TTL/eviction)
    revision*: int           ## MemoDb revision when recorded

  MemoDb* = object
    ## Salsa-style in-memory memoization database.
    ## Replaces disk-based gate_memo reads with O(1) table lookups.
    ## Revision increments on every mutation (enables staleness detection).
    entries*: Table[string, CacheEntry]  ## key = opaque composite identity (verbatim, consume-only)
    revision*: int
    hitCount*: int64
    missCount*: int64
    persistCount*: int64

# ══════════════════════════════════════════════════════════════════════════════
# Protocol Serialization
# ══════════════════════════════════════════════════════════════════════════════

func cacheKey*(gateId, subtreeRoot: string): string {.raises: [].} =
  ## Compute the node key for SalsaMemoDb red-green tracking (gate+subtree).
  ## Key format: "gateId|subtreeRoot". NOT used for daemon cache identity —
  ## MemoDb keys verbatim on the client-supplied composite identity.
  gateId & "|" & subtreeRoot

func encodeRequest*(req: DaemonRequest): string {.raises: [].} =
  ## Serialize a request to JSON line.
  var j = newJObject()
  j["v"] = newJInt(DaemonProtocolVersion)
  j["method"] = newJString(req.mthd)
  if req.requestId.len > 0: j["requestId"] = newJString(req.requestId)
  if req.gateId.len > 0: j["gateId"] = newJString(req.gateId)
  if req.subtreeRoot.len > 0: j["subtreeRoot"] = newJString(req.subtreeRoot)
  if req.identity.len > 0: j["identity"] = newJString(req.identity)
  if req.epoch != 0: j["epoch"] = newJInt(req.epoch)
  if req.result: j["result"] = newJBool(req.result)
  if req.failCategory.len > 0: j["failCategory"] = newJString(req.failCategory)
  if req.failReason.len > 0: j["failReason"] = newJString(req.failReason)
  $j & "\n"

func encodeResponse*(resp: DaemonResponse): string {.raises: [].} =
  ## Serialize a response to JSON line.
  var j = newJObject()
  j["v"] = newJInt(DaemonProtocolVersion)
  j["ok"] = newJBool(resp.ok)
  if resp.cached: j["cached"] = newJBool(resp.cached)
  if resp.result: j["result"] = newJBool(resp.result)
  if resp.reason.len > 0: j["reason"] = newJString(resp.reason)
  if resp.failCategory.len > 0: j["failCategory"] = newJString(resp.failCategory)
  if resp.revision != 0: j["revision"] = newJInt(resp.revision)
  if resp.message.len > 0: j["message"] = newJString(resp.message)
  $j & "\n"

proc decodeRequest*(line: string): DaemonRequest {.raises: [CatchableError].} =
  ## Parse a JSON line into a DaemonRequest. Returns empty request on parse error.
  try:
    let j = parseJson(line)
    result.version = j{"v"}.getInt(0)
    result.mthd = j{"method"}.getStr("")
    result.requestId = j{"requestId"}.getStr("")
    result.gateId = j{"gateId"}.getStr("")
    result.subtreeRoot = j{"subtreeRoot"}.getStr("")
    result.identity = j{"identity"}.getStr("")
    result.epoch = j{"epoch"}.getInt(0)
    result.result = j{"result"}.getBool(false)
    result.failCategory = j{"failCategory"}.getStr("")
    result.failReason = j{"failReason"}.getStr("")
  except CatchableError:
    discard  # Return default (empty) request  # axiom:best-effort(ioboundary catch)

proc decodeResponse*(line: string): DaemonResponse {.raises: [CatchableError].} =
  ## Parse a JSON line into a DaemonResponse. Returns error response on parse error.
  try:
    let j = parseJson(line)
    result.version = j{"v"}.getInt(0)
    result.ok = j{"ok"}.getBool(false)
    result.cached = j{"cached"}.getBool(false)
    result.result = j{"result"}.getBool(false)
    result.reason = j{"reason"}.getStr("")
    result.failCategory = j{"failCategory"}.getStr("")
    result.revision = j{"revision"}.getInt(0)
    result.message = j{"message"}.getStr("")
  except CatchableError:
    result.ok = false
    result.message = "invalid JSON response"

# ══════════════════════════════════════════════════════════════════════════════
# MemoDb Operations
# ══════════════════════════════════════════════════════════════════════════════

func initMemoDb*(): MemoDb {.raises: [].} =
  ## Create an empty MemoDb.
  MemoDb(entries: initTable[string, CacheEntry](), revision: 0,
         hitCount: 0, missCount: 0, persistCount: 0)

func lookup*(db: var MemoDb, identity: string): CacheEntry {.raises: [].} =
  ## O(1) cache lookup by composite identity (verbatim, consume-only).
  ## Returns empty entry on miss (result=false, epoch=0).
  if identity in db.entries:
    inc db.hitCount
    return db.entries.getOrDefault(identity)
  inc db.missCount
  CacheEntry()  # default: result=false, epoch=0

func persist*(db: var MemoDb, entry: CacheEntry) {.raises: [].} =
  ## Insert or update a cache entry keyed verbatim on its composite identity.
  ## Increments revision.
  inc db.revision
  inc db.persistCount
  var e = entry
  e.revision = db.revision
  db.entries[e.identity] = e

func invalidate*(db: var MemoDb, gateId: string): int {.raises: [].} =
  ## Remove all entries for a gate. Returns count of removed entries.
  var toRemove: seq[string]
  for key, entry in db.entries:
    if entry.gateId == gateId:
      toRemove.add(key)
  for key in toRemove:
    db.entries.del(key)
  inc db.revision
  toRemove.len

func stats*(db: MemoDb): tuple[entries: int, revision: int, hits: int64, misses: int64, persists: int64] {.raises: [].} =
  (db.entries.len, db.revision, db.hitCount, db.missCount, db.persistCount)
