import core/trusted/layer_declaration
axiomLayer "tools"
## Replay Probe — START gate B comparison vectors (productization_contract.md §6).
##
## Computes, for one captured run, the six replay-comparison vectors:
##   exitCodeProve / exitCodeReport          — observed process exit codes
##   proveProjection / reportProjection      — §6 canonical result projection digest
##   certDigest                              — content digest over all certificate files
##   certIdentityDigest                      — identity fields (modulePath/functionName/
##                                              status/winningStrategy/irHash/fingerprint/
##                                              sourceHash/solverMeta) per certificate
##   provenanceDigest                        — all provenance-valued fields (keys matching
##                                              "provenance" / "*Provenance"), sorted
##
## Canonical projection follows the §6 inclusion/exclusion table:
##   INCLUDED: claim/verdict per function, assuranceTier/verificationTier, proofDigest,
##             policyIdentity/config, input (sourceHash) — i.e. everything except the
##             excluded classes below.
##   EXCLUDED: timestamp/generatedAt/runId/processId, tmp path/absolutePath, randomness,
##             solver-internal traces, execution/performance telemetry (solverElapsedMs,
##             wallElapsedMs, parallelOverheadMs, startedAtMs/endedAtMs/elapsedMs,
##             cacheHitCount, totalWallTimeMs, executionStats/runtimeMeta subtrees).
##
## Usage (from repo root):
##   nim c -r tools/verification/replay_probe.nim -- <prove-state.json> <report-out.json> [certDir]
## Prints one line per vector: `VECTOR <name>=<sha256hex>`.

import std/[algorithm, json, os, strutils]
import checksums/sha2

const
  excludedExact = ["timestamp", "generatedAt", "runId", "processId",
                   "absolutePath", "ts"]
  droppedSubtreeTopKeys = ["executionStats", "runtimeMeta"]

func isExcludedKey(key: string): bool =
  if key in excludedExact:
    return true
  key.endsWith("Ms")

func project(d: JsonNode): JsonNode =
  ## §6 canonical semantic projection (inclusion by default; exclusion list above).
  case d.kind
  of JObject:
    result = newJObject()
    for key, value in d.pairs:
      if isExcludedKey(key):
        continue
      if key in droppedSubtreeTopKeys:
        continue
      result[key] = project(value)
  of JArray:
    result = newJArray()
    for item in d:
      result.add(project(item))
  else:
    result = copy(d)

proc sha256(bytes: string): string =
  var h = initSha_256()
  h.update(bytes)
  $h.digest()

func strCmp(a, b: string): int =
  if a < b: -1
  elif a > b: 1
  else: 0

proc canonicalJson(d: JsonNode): string =
  ## Deterministic serialization: sorted keys, compact separators, single trailing newline.
  var parts: seq[string] = @[]
  proc emit(n: JsonNode) =
    case n.kind
    of JObject:
      parts.add("{")
      var outKeys: seq[string] = @[]
      for k in n.keys:
        outKeys.add(k)
      outKeys.sort(strCmp)
      for j in 0 ..< outKeys.len:
        if j > 0: parts.add(",")
        parts.add("\"" & outKeys[j] & "\":")
        emit(n{outKeys[j]})
      parts.add("}")
    of JArray:
      parts.add("[")
      for j in 0 ..< n.len:
        if j > 0: parts.add(",")
        emit(n[j])
      parts.add("]")
    of JString:
      parts.add(escapeJson(n.getStr()))
    of JInt:
      parts.add($n.getInt())
    of JFloat:
      parts.add($n.getFloat())
    of JBool:
      parts.add($n.getBool())
    of JNull:
      parts.add("null")
    else:
      discard
  emit(d)
  parts.join()

proc projectionDigest*(doc: JsonNode): string =
  sha256(canonicalJson(project(doc)) & "\n")

proc collectProvenance(d: JsonNode; acc: var seq[string]) =
  ## Collect string values of keys named/ending in "provenance" (recursive).
  case d.kind
  of JObject:
    for key, value in d:
      if key == "provenance" or key.endsWith("Provenance"):
        acc.add(canonicalJson(value))
      collectProvenance(value, acc)
  of JArray:
    for item in d:
      collectProvenance(item, acc)
  else:
    discard

proc provenanceDigest*(doc: JsonNode; certDir: string = ""): string =
  var acc: seq[string] = @[]
  collectProvenance(doc, acc)
  if certDir.len > 0 and dirExists(certDir):
    for kind, path in walkDir(certDir):
      if kind == pcFile and path.endsWith(".json"):
        collectProvenance(parseFile(path), acc)
  acc.sort(strCmp)
  sha256(acc.join("\n") & "\n")

proc certFileDigests*(certDir: string): tuple[contentDigest: string, identityDigest: string]  =
  var contentHash = initSha_256()
  var identityHash = initSha_256()
  var names: seq[string] = @[]
  for kind, path in walkDir(certDir):
    if kind == pcFile and path.endsWith(".json"):
      names.add(path)
  names.sort(strCmp)
  for path in names:
    let bytes = readFile(path)
    contentHash.update(bytes)
    let node = parseJson(bytes)
    let identityFields = ["modulePath", "functionName", "status", "winningStrategy",
                          "irHash", "fingerprint", "sourceHash", "solverMeta"]
    let idNode = newJObject()
    for f in identityFields:
      let v = node{f}
      if not v.isNil:
        idNode[f] = v
    identityHash.update(sha256(canonicalJson(idNode) & "\n"))
  (sha256($contentHash.digest()), sha256($identityHash.digest()))

proc failMsg(msg: string) =
  stderr.writeLine("REPLAY-PROBE: " & msg)
  quit(1)

when isMainModule:
  let args = commandLineParams()
  if args.len < 2:
    failMsg("usage: replay_probe <proveState.json> <reportOut.json> [certDir]")
  let proveDoc = parseFile(args[0])
  let reportDoc = parseFile(args[1])
  let certDir = if args.len > 2: args[2] else: "build/certificates"
  let certs = certFileDigests(certDir)
  echo "VECTOR proveProjection=" & projectionDigest(proveDoc)
  echo "VECTOR reportProjection=" & projectionDigest(reportDoc)
  echo "VECTOR certDigest=" & certs.contentDigest
  echo "VECTOR certIdentityDigest=" & certs.identityDigest
  echo "VECTOR proveProvenance=" & provenanceDigest(proveDoc, certDir)
  echo "VECTOR reportProvenance=" & provenanceDigest(reportDoc, certDir)
  let provSt = provenanceDigest(proveDoc, certDir)
  let provRp = provenanceDigest(reportDoc, certDir)
  echo "VECTOR provenanceDigest=" & sha256(provSt & "\n" & provRp & "\n")
  echo "VECTOR schemaVersionProve=" & proveDoc{"schemaVersion"}.getStr("")
  echo "VECTOR schemaVersionReport=" & reportDoc{"schemaVersion"}.getStr("")