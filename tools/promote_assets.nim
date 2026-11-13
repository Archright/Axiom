import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [CatchableError].}
import std/[os, strutils, json, algorithm, parseopt, tables, sets, options]
import shared_types/io_bridge

## AssetPromotionBoundary — canonical mutation authority for type_mappings assets.
##
## Independent from CertificatePromotionBoundary (tools/promote_cert.nim). Assets
## (type mappings) are staged by rebuild_assets to build/staging/assets/type_mappings/
## and promoted here through Intent Delta inspection:
##
##     Canonical C + Staging S + PromotionIntent I
##              ↓
##         semantic Δ = diff(C, S)
##              ↓
##         Δ == I ?   (intent-declared add/modify matches Δ)
##              ↓
##         policy validate (forbid unexpected deletion / schema-break / identity-break)
##              ↓
##         authorize → atomic replace (writePrettyJsonFile tmp+rename)
##
## Contract: docs/spec/cert_lifecycle_contracts.md §4. Generators never mutate
## canonical directly; only this boundary promotes validated staging.

const
  CanonicalTypeMapDir = "src" / "verification" / "certificates" / "type_mappings"
  StagingTypeMapBaseDir = "build" / "staging" / "assets" / "type_mappings"
  IntentFileName = "promotion_intent.json"

type
  PromotionIntent* = object
    ## Declared expected asset footprint. `expectedNimTypes` is the canonical set
    ## of type names that MUST exist post-promotion (identity anchor). New/deleted
    ## entries beyond intent are rejected.
    expectedNimTypes*: seq[string]
    reason*: string

## ── Error plumbing ─────────────────────────────────────────────────────────
func errMsg(msg: string): string = "REJECTED: " & msg

## ── Intent loading ─────────────────────────────────────────────────────────
proc loadIntent(intentPath: string): PromotionIntent =
  let opt = parseJsonOpt(readFile(intentPath))
  result.reason = ""
  if opt.isNone:
    return
  let j = opt.get()
  if j.hasKey("expectedNimTypes") and j["expectedNimTypes"].kind == JArray:
    for t in j["expectedNimTypes"]:
      result.expectedNimTypes.add(t.getStr(""))
  if j.hasKey("reason"):
    result.reason = j["reason"].getStr("")

## ── File-set helpers ───────────────────────────────────────────────────────
proc listTypeMapFiles(dir: string): seq[string] =
  result = @[]
  if not dirExists(dir):
    return
  for f in walkFiles(joinPath(dir, "*.json")):
    if f.endsWith(".json"):
      result.add(splitFile(f).name)

## identity is the canonical base name (no extension); identity-breaking changes
## (a different nimType under the same file) are detected via the `nimType` field.
proc loadTypeMap(dir: string; name: string): JsonNode =
  let path = joinPath(dir, name & ".json")
  let opt = readJsonFile(path)
  result = if opt.isSome: opt.get() else: nil

## Build canonical identity map: nimType -> filename-derived identity.
proc buildIdentityMap(dir: string): Table[string, string] =
  for f in listTypeMapFiles(dir):
    let node = loadTypeMap(dir, f)
    if node != nil and node.hasKey("nimType"):
      result[node["nimType"].getStr("")] = f

## ── Immutable-files mapping ────────────────────────────────────────────────
type
  DeltaCategory = enum
    dcIdentical
    dcAdded
    dcModified
    dcDeleted

proc classifyDelta(canonical: Table[string, string]; staging: Table[string, string];
                   nimType: string; canonicalFiles, stagingFiles: Table[string, string]): DeltaCategory =
  let inCanonical = nimType in canonical
  let inStaging = nimType in staging
  if inCanonical and inStaging:
    let cPath = joinPath(CanonicalTypeMapDir, canonical[nimType] & ".json")
    let sPath = joinPath(StagingTypeMapBaseDir, staging[nimType] & ".json")
    let cNode = loadTypeMap(CanonicalTypeMapDir, canonical[nimType])
    let sNode = loadTypeMap(StagingTypeMapBaseDir, staging[nimType])
    if cNode != nil and sNode != nil and cNode.pretty == sNode.pretty:
      result = dcIdentical
    else:
      result = dcModified
  elif inStaging and not inCanonical:
    result = dcAdded
  elif inCanonical and not inStaging:
    result = dcDeleted
  else:
    result = dcIdentical

proc main() =
  var intentArg = ""
  var doApply = false
  for kind, key, val in getopt():
    case kind
    of cmdLongOption, cmdShortOption:
      case key
      of "intent":
        intentArg = val
      of "apply":
        doApply = true
      of "help", "h":
        echo "Usage: promote_assets [OPTIONS]"
        echo ""
        echo "Promotes staged type_mappings from build/staging/assets/ to canonical vault."
        echo "Intent Delta inspection: validates staging against PromotionIntent."
        echo ""
        echo "Options:"
        echo "  --intent <path>   Path to promotion_intent.json (declared expected set)"
        echo "  --apply           Apply promotion (default: validate only / dry-run)"
        echo "  --help, -h        Show this help"
        return
      else: discard
    else: discard

  let projectRoot = getCurrentDir()
  let canonicalDir = joinPath(projectRoot, CanonicalTypeMapDir)
  let stagingDir = joinPath(projectRoot, StagingTypeMapBaseDir)
  if intentArg.len == 0:
    intentArg = joinPath(projectRoot, "config", IntentFileName)
  if not fileExists(intentArg):
    echo errMsg("promotion intent not found: " & intentArg)
    quit(1)

  let intent = loadIntent(intentArg)
  if intent.expectedNimTypes.len == 0:
    echo errMsg("promotion intent declares no expectedNimTypes (identity anchor empty)")
    quit(1)

  ## Load canonical + staging identity maps.
  let canonical = buildIdentityMap(canonicalDir)
  let staging = buildIdentityMap(stagingDir)

  ## ── Intent Delta Inspection ──────────────────────────────────────────
  ## 1. Unexpected deletion: any canonical nimType missing from staging that is
  ##    NOT a declared removal in intent (intent declares the EXPECTED final set →
  ##    anything in canonical absent from both staging and intent = forbidden).
  let intentSet = toHashSet(intent.expectedNimTypes)
  var violations: seq[string] = @[]

  ## Build staging nimType set.
  var stagingNimTypes: HashSet[string]
  for k in keys(staging):
    stagingNimTypes.incl(k)

  ## 1. Forbidden deletions: canonical identity not present in staging AND not
  ##    declared expected in intent → unexpected deletion.
  for nimType, fname in canonical:
    if nimType notin stagingNimTypes and nimType notin intentSet:
      violations.add("forbidden deletion: canonical type '" & nimType & "' absent from staging and not declared — intent=" & IntentFileName)

  ## 2. Intent completeness: every declared expected nimType must be present
  ##    post-promotion (staging). Missing → promotion would tear canonical.
  for t in intent.expectedNimTypes:
    if t notin stagingNimTypes:
      violations.add("intent identity missing in staging: '" & t & "' (declared in intent but not staged)")

  ## 3. Schema-break / identity-break: staged entry must carry required fields
  ##    and stable nimType identity matching its filename-derived identity.
  for nimType, fname in staging:
    let sNode = loadTypeMap(stagingDir, fname)
    if sNode == nil:
      violations.add("schema-break: unreadable staging type_mapping '" & fname & "'")
      continue
    for requiredField in ["nimType", "leanType", "smtSort", "verified"]:
      if not sNode.hasKey(requiredField):
        violations.add("schema-break: staging type_mapping '" & fname & "' missing field '" & requiredField & "'")
    ## identity-break: nimType field must match the identity key.
    if sNode.hasKey("nimType") and sNode["nimType"].getStr("") != nimType:
      violations.add("identity-break: staging '" & fname & "' declares nimType='" &
                     sNode["nimType"].getStr("") & "' but identity key is '" & nimType & "'")
    ## unexpected addition: staged nimType neither in canonical nor in intent.
    if nimType notin canonical and nimType notin intentSet:
      violations.add("unexpected addition: staging type '" & nimType & "' absent from canonical and not declared in intent")

  if violations.len > 0:
    echo errMsg("intent delta inspection failed (" & $violations.len & " violation(s))")
    for v in violations:
      echo "  - " & v
    quit(1)

  ## ── Authorize + atomic promote ───────────────────────────────────────
  if not doApply:
    echo "DRY-RUN: intent delta inspection PASS — canonical types=" & $canonical.len &
         ", staging types=" & $staging.len & ", intent types=" & $intent.expectedNimTypes.len &
         ". Use --apply to promote."
    quit(0)

  if not dirExists(canonicalDir):
    discard existsOrCreateDir(canonicalDir)
  var promoted = 0
  for nimType, fname in staging:
    let sNode = loadTypeMap(stagingDir, fname)
    if sNode == nil:
      continue
    let tpath = joinPath(canonicalDir, fname & ".json")
    if not writePrettyJsonFile(tpath, sNode):
      echo errMsg("atomic write failed for " & tpath)
      quit(1)
    inc promoted
  echo "OK: promoted " & $promoted & " type_mapping(s) to canonical vault (atomic write, intent '" & intent.reason & "')"

when isMainModule:
  main()