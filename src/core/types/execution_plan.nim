import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## ExecutionPlan — immutable plan for the executor.
##
## PlanIdentity composes with BaseRunIdentity fields WITHOUT
## modifying run_identity.nim.

import std/[algorithm, json, options, sequtils, strutils]
import core/types/request_id

# ---------------------------------------------------------------------------
# UniverseMode
# ---------------------------------------------------------------------------

type
  UniverseMode* = enum
    umFull      ## full universe execution
    umSelected  ## selected subset execution

# ---------------------------------------------------------------------------
# PlanIdentity — run-level identity that composes with BaseRunIdentity
# ---------------------------------------------------------------------------

type
  PlanIdentity* = object
    selectionDigest*: string
    changeSetDigest*: string
    graphDigest*: string
    universeDigest*: string
    policyDigest*: string
    planDigest*: string

# ---------------------------------------------------------------------------
# ExecutionPlan
# ---------------------------------------------------------------------------

type
  ExecutionPlan* = object
    mode*: UniverseMode
    selectedUnitIds*: seq[string]
    planIdentity*: PlanIdentity
    planDigest*: string
    requests*: seq[RequestId]  ## required requests derived from selection (independent basis)

func toCanonicalJson*(ep: ExecutionPlan): JsonNode {.raises: [].} =
  let sortedIds = ep.selectedUnitIds.sorted(cmp)
  let sortedRequests = ep.requests.sorted(proc(a, b: RequestId): int = cmp(string(a), string(b)))
  %*{
    "mode": $ep.mode,
    "selectedUnitIds": sortedIds,
    "planIdentity": %*{
      "selectionDigest": ep.planIdentity.selectionDigest,
      "changeSetDigest": ep.planIdentity.changeSetDigest,
      "graphDigest": ep.planIdentity.graphDigest,
      "universeDigest": ep.planIdentity.universeDigest,
      "policyDigest": ep.planIdentity.policyDigest,
      "planDigest": ep.planIdentity.planDigest},
    "planDigest": ep.planDigest,
    "requests": sortedRequests.mapIt(it.toString())}

func toJson*(ep: ExecutionPlan): JsonNode {.raises: [].} =
  ep.toCanonicalJson()

func fromJson*(node: JsonNode): Option[ExecutionPlan] {.raises: [].} =
  if node == nil or node.kind != JObject:
    return none(ExecutionPlan)
  let modeStr = node{"mode"}.getStr("")
  if modeStr.len == 0:
    return none(ExecutionPlan)
  let mode = try:
    parseEnum[UniverseMode](modeStr)
  except ValueError:
    return none(ExecutionPlan)
  let selectedUnitIds = if node{"selectedUnitIds"}.kind == JArray:
    node{"selectedUnitIds"}.getElems().mapIt(it.getStr())
  else:
    @[]
  let planIdentityNode = node{"planIdentity"}
  if planIdentityNode.kind != JObject:
    return none(ExecutionPlan)
  let planIdentity = PlanIdentity(
    selectionDigest: planIdentityNode{"selectionDigest"}.getStr(""),
    changeSetDigest: planIdentityNode{"changeSetDigest"}.getStr(""),
    graphDigest: planIdentityNode{"graphDigest"}.getStr(""),
    universeDigest: planIdentityNode{"universeDigest"}.getStr(""),
    policyDigest: planIdentityNode{"policyDigest"}.getStr(""),
    planDigest: planIdentityNode{"planDigest"}.getStr(""))
  let planDigest = node{"planDigest"}.getStr("")
  let requests = if node.hasKey("requests") and node{"requests"}.kind == JArray:
    node{"requests"}.getElems().mapIt(RequestId(it.getStr()))
  else:
    @[]
  some(ExecutionPlan(
    mode: mode,
    selectedUnitIds: selectedUnitIds,
    planIdentity: planIdentity,
    planDigest: planDigest,
    requests: requests))

{.pop.}