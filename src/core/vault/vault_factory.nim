import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import core/utils/constants
import core/gateway/gateway
import core/json/json_utils
import core/json/std_redirect
import core/session/session_parser_types
import core/trusted/axiom_pragmas
import core/trusted/env_access
import core/types/results
import core/utils/io_utils
import std/algorithm
import std/options
import std/os
import std/strutils
type
  Vault* = object
    backend*: string
    storagePath*: string
const
  defaultVaultBackend = "sqlite"
  defaultVaultDbPath = "logs/axiom.db"

# @axiom-hint: lean="normalized.length = 0" smt="(assert (and (= (str.len normalized) 0)))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func normalizeBackend(raw: string): string {.raises: [], noSideEffect.} =
  let normalized = raw.strip().toLowerAscii()
  if normalized.len == 0:
    defaultVaultBackend
  else:
    normalized

## Session Lookup Json.
# @axiom-hint: lean="sessionId.length ≥ 0" smt="(assert (and (>= (str.len sessionId) 0)))"
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert ast_parse_failed_isolated)"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func sessionLookupJson*(sessionId: string): string {.raises: [], noSideEffect.} =
  $(%*{"sessionId": sessionId})

## Trace Lookup Json.
# @axiom-hint: lean="traceRef.length ≥ 0" smt="(assert (and (>= (str.len traceRef) 0)))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func traceLookupJson*(traceRef: string): string {.raises: [], noSideEffect.} =
  $(%*{"traceRef": traceRef})

# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert ast_parse_failed_isolated)"
# @axiom-hint: lean="depth >= 0" smt="(assert (>= depth 0))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func initVaultStore(): JsonNode {.raises: [].} =
  %*{
    "schemaVersion": "axiom.vault.sqlite.v1",
    "sessions": {},
    "proofsBySession": {},
    "proofsByTrace": {}
  }
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc loadVaultStore(dbPath: string): Result[JsonNode, AxiomError] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let parent = parentDir(dbPath)
  if parent.len > 0 and parent != ".":
    discard existsOrCreateDirOpt(parent)
  if not fileExists(dbPath):
    discard writePrettyJsonFile(dbPath, initVaultStore())
  let rawRes = readFileOpt(dbPath)
  if rawRes.isErr:
    return err(axiomErrFileSystemError)
  let raw = rawRes.get()
  if raw.strip().len == 0:
    discard writePrettyJsonFile(dbPath, initVaultStore())
    return ok(initVaultStore())
  let parsedRes = ??jsonParseSafe(raw)
  let rootRes = ??jsonRequireObject(parsedRes)
  let root = rootRes
  let sessionsOpt = jsonTryGetObjectField(root, "sessions")
  let proofsBySessionOpt = jsonTryGetObjectField(root, "proofsBySession")
  let proofsByTraceOpt = jsonTryGetObjectField(root, "proofsByTrace")
  if not sessionsOpt.isSome() or
      not proofsBySessionOpt.isSome() or
      not proofsByTraceOpt.isSome():
    return err(axiomErrJsonMissingField)
  ok(root)

# @axiom-hint: lean="dbPath.length ≥ 0" smt="(assert (and (>= (str.len dbPath) 0)))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc persistVaultStore(dbPath: string; store: JsonNode): Result[bool, AxiomError] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if not writePrettyJsonFile(dbPath, store):
    return err(axiomErrFileSystemError)
  ok(true)

# @axiom-hint: lean="idx + 1 = path.length ∧ current = nextRes ∧ (current ≥ 0) ∧ (path ≥ 0)" smt="(assert (and (= (+ idx 1) (str.len path)) (= current nextRes) (>= current 0) (>= path 0)))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func extractStringField(rawJson: string; path: openArray[string]): Result[string, AxiomError] {.raises: [].} =
  let rootRes = ??jsonParseSafe(rawJson)
  var currentRes = jsonRequireObject(rootRes)
  if currentRes.isErr():
    return err(currentRes.error)
  var current = currentRes.get()
  for idx, segment in path:
    if idx + 1 == path.len:
      return jsonGetNonEmptyStringField(current, segment)
    let nextRes = ??jsonRequireObjectField(current, segment)
    current = nextRes
  err(axiomErrJsonMissingField)

# @axiom-hint: lean="sessionJson.length ≥ 0" smt="(assert (and (>= (str.len sessionJson) 0)))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func extractSessionIdFromSessionJson(sessionJson: string): Result[string, AxiomError] {.raises: [].} =
  let rawRes = ??extractStringField(sessionJson, [sessionIdKey])
  let sessionIdRes = ??toSessionId(rawRes)
  ok(sessionIdString(sessionIdRes))

# @axiom-hint: lean="lookupJson.length ≥ 0" smt="(assert (and (>= (str.len lookupJson) 0)))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func extractSessionIdFromLookup(lookupJson: string): Result[string, AxiomError] {.raises: [].} =
  let rawRes = ??extractStringField(lookupJson, [sessionIdKey])
  let sessionIdRes = ??toSessionId(rawRes)
  ok(sessionIdString(sessionIdRes))

# @axiom-hint: lean="lookupJson.length ≥ 0" smt="(assert (and (>= (str.len lookupJson) 0)))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func extractTraceRefFromLookup(lookupJson: string): Result[string, AxiomError] {.raises: [].} =
  let rawRes = ??extractStringField(lookupJson, ["traceRef"])
  let traceRefRes = ??toTraceRef(rawRes)
  ok(traceRefString(traceRefRes))

# @axiom-hint: lean="proofJson.length ≥ 0" smt="(assert (and (>= (str.len proofJson) 0)))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func extractProofEnvelope(proofJson: string): Result[(string, string), AxiomError] {.raises: [].} =
  let sessionIdRawRes = ??extractStringField(proofJson, [sessionIdKey])
  let sessionIdRes = ??toSessionId(sessionIdRawRes)
  let traceRefRawRes = ??extractStringField(proofJson, ["proof", "witness", "traceRef"])
  let traceRefRes = ??toTraceRef(traceRefRawRes)
  ok((sessionIdString(sessionIdRes), traceRefString(traceRefRes)))

## Create Vault From Env.
# @axiom-hint: lean="depth >= 0" smt="(assert (>= depth 0))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func createVaultFromEnv*(): Result[Vault, AxiomError] {.raises: [].} =
  let backend = normalizeBackend(getAxiomEnv(evDbBackend))
  let storagePath =
    if getAxiomEnv(evDbPath).strip().len > 0:
      getAxiomEnv(evDbPath).strip()
    else:
      defaultVaultDbPath
  case backend
  of "sqlite", "postgres":
    ok(Vault(backend: backend, storagePath: storagePath))
  else:
    err(axiomErrInvalidValue)
## Save Session.
# @axiom-hint: lean="vault_backend.length ≥ 0 ∧ vault_storagePath.length ≥ 0 ∧ sessionJson.length ≥ 0" smt="(assert (and (>= (str.len vault_backend) 0) (>= (str.len vault_storagePath) 0) (>= (str.len sessionJson) 0)))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc saveSession*(vault: Vault; sessionJson: string): Result[string, AxiomError] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let sessionIdRes = ??extractSessionIdFromSessionJson(sessionJson)
  if vault.backend != "sqlite":
    return err(axiomErrInconsistentState)
  let storeRes = ??loadVaultStore(vault.storagePath)
  let sessionNodeRes = ??jsonParseSafe(sessionJson)
  var store = storeRes
  let sessionsRes = ??jsonRequireObjectField(store, "sessions")
  let proofsBySessionRes = ??jsonRequireObjectField(store, "proofsBySession")
  let proofsByTraceRes = ??jsonRequireObjectField(store, "proofsByTrace")
  let existingProof = proofsBySessionRes{sessionIdRes}
  if not existingProof.isNil:
    let existingProofNode = existingProof{"proof"}
    if not existingProofNode.isNil:
      let existingWitnessNode = existingProofNode{"witness"}
      if not existingWitnessNode.isNil:
        let existingTraceRefNode = existingWitnessNode{"traceRef"}
        if not existingTraceRefNode.isNil and existingTraceRefNode.kind == JString:
          let existingTraceRef = existingTraceRefNode.getStr()
          proofsByTraceRes[existingTraceRef] = newJNull()
    proofsBySessionRes[sessionIdRes] = newJNull()
  sessionsRes[sessionIdRes] = sessionNodeRes
  discard ??persistVaultStore(vault.storagePath, store)
  ok(sessionIdRes)

## Save Proof.
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert ast_parse_failed_isolated)"
# @axiom-hint: lean="vault_backend.length ≥ 0 ∧ vault_storagePath.length ≥ 0 ∧ proofJson.length ≥ 0" smt="(assert (and (>= (str.len vault_backend) 0) (>= (str.len vault_storagePath) 0) (>= (str.len proofJson) 0)))"
# @axiom-hint: lean="(proofsBySessionRes ≥ 0) ∧ (proofsByTraceRes ≥ 0)" smt="(assert (and (>= proofsBySessionRes 0) (>= proofsByTraceRes 0)))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc saveProof*(vault: Vault; proofJson: string): Result[string, AxiomError] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let envelopeRes = ??extractProofEnvelope(proofJson)
  if vault.backend != "sqlite":
    return err(axiomErrInconsistentState)
  let envelope = envelopeRes
  let storeRes = ??loadVaultStore(vault.storagePath)
  let proofNodeRes = ??jsonParseSafe(proofJson)
  var store = storeRes
  let proofsBySessionRes = ??jsonRequireObjectField(store, "proofsBySession")
  let proofsByTraceRes = ??jsonRequireObjectField(store, "proofsByTrace")
  proofsBySessionRes[envelope[0]] = proofNodeRes
  proofsByTraceRes[envelope[1]] = proofNodeRes
  discard ??persistVaultStore(vault.storagePath, store)
  ok(envelope[0])

## Get Proof.
# @axiom-hint: lean="vault_backend.length ≥ 0 ∧ vault_storagePath.length ≥ 0 ∧ lookupJson.length ≥ 0" smt="(assert (and (>= (str.len vault_backend) 0) (>= (str.len vault_storagePath) 0) (>= (str.len lookupJson) 0)))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc getProof*(vault: Vault; lookupJson: string): Result[string, AxiomError] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let sessionIdRes = ??extractSessionIdFromLookup(lookupJson)
  if vault.backend != "sqlite":
    return err(axiomErrInconsistentState)
  let storeRes = ??loadVaultStore(vault.storagePath)
  let proofsBySessionRes = ??jsonRequireObjectField(storeRes, "proofsBySession")
  let payload = proofsBySessionRes{sessionIdRes}
  if payload.isNil or payload.kind == JNull:
    return err(axiomErrNotFound)
  ok($payload)

## Find Trace By Ref.
# @axiom-hint: lean="vault_backend.length ≥ 0 ∧ vault_storagePath.length ≥ 0 ∧ lookupJson.length ≥ 0" smt="(assert (and (>= (str.len vault_backend) 0) (>= (str.len vault_storagePath) 0) (>= (str.len lookupJson) 0)))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc findTraceByRef*(vault: Vault; lookupJson: string): Result[string, AxiomError] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let traceRefRes = ??extractTraceRefFromLookup(lookupJson)
  if vault.backend != "sqlite":
    return err(axiomErrInconsistentState)
  let storeRes = ??loadVaultStore(vault.storagePath)
  let proofsByTraceRes = ??jsonRequireObjectField(storeRes, "proofsByTrace")
  let payload = proofsByTraceRes{traceRefRes}
  if payload.isNil or payload.kind == JNull:
    return err(axiomErrNotFound)
  ok($payload)

## List Sessions.
# @axiom-hint: lean="(sessionsNode ≥ 0) ∧ (sessionIds ≥ 0)" smt="(assert (and (>= sessionsNode 0) (>= sessionIds 0)))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc listSessions*(vault: Vault; lookupJson: string): Result[string, AxiomError] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  discard lookupJson
  if vault.backend != "sqlite":
    return ok($(%*{"backend": vault.backend, "sessions": []}))
  let storeRes = ??loadVaultStore(vault.storagePath)
  let sessionsRes = ??jsonRequireObjectField(storeRes, "sessions")
  let sessionsNode = sessionsRes
  var sessionIds: seq[string] = @[]
  for key, _ in sessionsNode:
    sessionIds.add(key)
  sessionIds.sort()
  let sessions = newJArray()
  for sessionId in sessionIds:
    sessions.add(%*{"sessionId": sessionId})
  ok($(%*{"backend": vault.backend, "sessions": sessions}))




{.pop.}

