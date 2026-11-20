import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

## Admission evidence export — certificate body · canonical projection · set digest.
##
## Implements docs/spec/admission_evidence_export_contract.md:
##   E1  body export (byte-identical) + identity-based lookup (§2.2a)
##   E2  destination inventory exact match
##   E3  v3 export projection (certificateFile/Sha256/recomputedStatus/
##       theoremIdentity/axiomObservation)
##   E4  certificateSetDigest over raw body hashes + canonical projection
##   E5  verdict/record binding fields are produced by the CLI JSON output
##
## Authority: status/tier is the existing engine projection
## (`certificateEvidenceFromJson → tierFromEvidence → tierToCertStatus`).
## This module never re-implements that judgment, and never trusts a status
## string without recomputing it from the body.
##
## Lookup fact (§2.2a): the runtime manifest's `irHash` is the IR pipeline
## digest, while a certificate file's CAS key is the body's `irHash`
## (sha256 of modulePath & functionName & sourceCode) or `subjectId`. The two
## hash spaces differ, so lookup is by exact (modulePath, functionName), and
## an ambiguous or inconsistent binding fails closed.

import std/[algorithm, json, os, strutils, tables, sets]

import core/axiom_pragmas
import core/crypto/hash_kernel
import core/types/certificate_types
import core/types/verification_tier
import verification/canonical_json
import verification/certificate_verifier
import verification/kernel_reexecution

const
  ExportManifestName* = "vault-manifest.json"
  ExportInventoryName* = "vault-certificates.txt"
  ExportSchema* = "axiom.admission.vault-manifest.v3"
  ExportSetSchema* = "axiom.admission.cert-set.v1"
  ExportVerifySchema* = "axiom.cert-verify-export.v1"

type
  ManifestEntryV3* = object
    modulePath*: string
    functionName*: string
    status*: string
    solverMethod*: string
    lastVerifiedAt*: string
    irHash*: string

  BodyRef = object
    file: string
    raw: string
    node: JsonNode

  ExportOutcome* = object
    ok*: bool
    codes*: seq[string]
    detail*: string
    digest*: string
    certCount*: int
      ## number of exported certificate bodies
    bodyCount*: int

  VerifyOutcome* = object
    ok*: bool
    reasonCode*: string
    codes*: seq[string]
    detail*: string
    digest*: string
    bodiesPresent*: bool
    entryCount*: int
    closure*: string
    environmentError*: bool
      ## closure requested but journal/replay artifacts are unavailable → exit 2

# ─── JSON helpers (nil-safe; getOrDefault on a nil node derefs) ─────────

func safeStr(node: JsonNode; key: string): string {.raises: [].} =
  if node.isNil or node.kind != JObject: return ""
  let v = node.getOrDefault(key)
  if v.isNil or v.kind != JString: return ""
  v.getStr("")

func hasString(node: JsonNode; key: string): bool {.raises: [].} =
  if node.isNil or node.kind != JObject: return false
  let v = node.getOrDefault(key)
  not v.isNil and v.kind == JString

func fieldOrNull(node: JsonNode; key: string): JsonNode {.raises: [].} =
  if node.isNil or node.kind != JObject: return newJNull()
  let v = node.getOrDefault(key)
  if v.isNil: newJNull() else: v

func objectField(node: JsonNode; key: string): JsonNode {.raises: [].} =
  if node.isNil or node.kind != JObject: return nil
  let v = node.getOrDefault(key)
  if v.isNil or v.kind != JObject: nil else: v

func arrayField(node: JsonNode; key: string): JsonNode {.raises: [].} =
  if node.isNil or node.kind != JObject: return nil
  let v = node.getOrDefault(key)
  if v.isNil or v.kind != JArray: nil else: v

func stringOrNull(s: string): JsonNode =
  if s.len > 0: %s else: newJNull()

# ─── identity / projection helpers ──────────────────────────────────────

func isLowerHex64*(s: string): bool {.raises: [].} =
  if s.len != 64: return false
  for c in s:
    if c notin {'0'..'9', 'a'..'f'}: return false
  true

func certCasKey*(node: JsonNode): string {.raises: [].} =
  ## The certificate's own content-address key: `irHash` for UAP/IR certs,
  ## `subjectId` for subject-continuity certs.
  if node.isNil or node.kind != JObject: return ""
  let ir = safeStr(node, "irHash")
  if ir.len > 0: return ir
  safeStr(node, "subjectId")

func leanEvidencePresent*(node: JsonNode): bool {.raises: [].} =
  ## Lean-dependent claim: either an embedded source or a proposition exists.
  ## Z3-only certificates carry neither (contract §2.4 not-applicable).
  if node.isNil or node.kind != JObject: return false
  safeStr(node, "leanSource").len > 0 or safeStr(node, "leanProposition").len > 0

func axiomObservationStatus*(node: JsonNode): string {.raises: [].} =
  ## observed := mint-time `#print axioms` observation is recorded
  ## (`axiomsUsed` key exists — an empty array is kernel-pure, still observed).
  ## not-observed := Lean-dependent claim without an observation record.
  ## not-applicable := no Lean evidence (Z3-only).
  if not leanEvidencePresent(node): return "not-applicable"
  let arr = node.getOrDefault("axiomsUsed")
  if not arr.isNil and arr.kind == JArray:
    return "observed"
  "not-observed"

func axiomObservationNames*(node: JsonNode): seq[string] {.raises: [].} =
  if node.isNil or node.kind != JObject: return @[]
  let arr = node.getOrDefault("axiomsUsed")
  if arr.isNil or arr.kind != JArray: return @[]
  for item in arr:
    if item.kind == JString:
      result.add(item.getStr(""))

func theoremIdentityOf*(node: JsonNode): string {.raises: [].} =
  ## The declaration observed by the kernel re-execution's `#print axioms`.
  if node.isNil or node.kind != JObject: return ""
  firstDeclaredName(safeStr(node, "leanSource"))

func recomputedStatusOf*(node: JsonNode): string {.raises: [].} =
  ## The single tier authority: existing engine projection, not a reimplementation.
  tierToStatusString(tierFromEvidence(certificateEvidenceFromJson(node)))

# ─── runtime manifest loading ───────────────────────────────────────────

proc loadRuntimeManifest(path: string; outcome: var ExportOutcome):
    seq[ManifestEntryV3] {.raises: [CatchableError].} =
  ## Strict reader (fail-closed). `vault_manifest.loadManifest` silently
  ## degrades to an empty manifest on parse errors; an exporter must not turn
  ## that into an empty PASS, so the raw JSON is validated here.
  if not fileExists(path):
    outcome.codes.add("CERT_INVENTORY_MISMATCH")
    outcome.detail = "runtime manifest not found: " & path
    return @[]
  var root: JsonNode
  try:
    root = parseJson(readFile(path))
  except CatchableError as e:
    outcome.codes.add("CERT_INVENTORY_MISMATCH")
    outcome.detail = "runtime manifest unreadable: " & e.msg
    return @[]
  let entriesNode = arrayField(root, "entries")
  if root.isNil or root.kind != JObject or entriesNode.isNil:
    outcome.codes.add("CERT_INVENTORY_MISMATCH")
    outcome.detail = "runtime manifest is not a {version, entries[]} object"
    return @[]
  for e in entriesNode:
    if e.kind != JObject:
      outcome.codes.add("CERT_INVENTORY_MISMATCH")
      outcome.detail = "runtime manifest entry is not an object"
      return @[]
    result.add ManifestEntryV3(
      modulePath: safeStr(e, "modulePath"),
      functionName: safeStr(e, "functionName"),
      status: safeStr(e, "status"),
      solverMethod: safeStr(e, "solverMethod"),
      lastVerifiedAt: safeStr(e, "lastVerifiedAt"),
      irHash: safeStr(e, "irHash"))

# ─── source vault body scan ─────────────────────────────────────────────

proc scanBodies(vaultDir: string; outcome: var ExportOutcome): seq[BodyRef] {.
    raises: [CatchableError], axiomEffect: IOEffect.} =
  if not dirExists(vaultDir):
    outcome.codes.add("CERT_INVENTORY_MISMATCH")
    outcome.detail = "source vault not found: " & vaultDir
    return @[]
  for kind, path in walkDir(vaultDir):
    if kind != pcFile: continue
    let name = extractFilename(path)
    if not name.endsWith(".json"): continue
    if name == "manifest.json" or name == ExportManifestName: continue
    var raw: string
    try:
      raw = readFile(path)
    except CatchableError:
      continue
    var node: JsonNode
    try:
      node = parseJson(raw)
    except CatchableError:
      continue
    if node.isNil or node.kind != JObject: continue
    result.add BodyRef(file: name, raw: raw, node: node)

# ─── E1–E4 export ───────────────────────────────────────────────────────

proc exportToDir*(vaultDir, outRoot: string;
                  declaredTargets: seq[string] = @[]): ExportOutcome {.
    raises: [CatchableError], axiomEffect: IOEffect.} =
  ## E1–E4 export. Writes `<outRoot>/vault/` only when every check passes.
  ##
  ## `declaredTargets` (contract §2.2b) is the admission claim set: the
  ## `modulePath::functionName` targets of the propositions the run declared.
  ## When supplied, only those manifest entries are part of the exported
  ## certificate set; every other verified row is disclosed under
  ## `outOfScope` but is NOT a claim of this bundle (it is engine-internal
  ## model evidence without a canonical certificate body). Without targets
  ## the whole manifest is exported (legacy unscoped behaviour).
  result = ExportOutcome(ok: false, codes: @[], detail: "", digest: "",
    certCount: 0, bodyCount: 0)
  let vaultOut = outRoot / "vault"
  if dirExists(vaultOut):
    var nonEmpty = false
    for _ in walkDir(vaultOut):
      nonEmpty = true
      break
    if nonEmpty:
      result.codes.add("CERT_INVENTORY_MISMATCH")
      result.detail = "output directory already exists and is not empty: " & vaultOut
      return

  var loadOutcome = ExportOutcome(ok: false)
  let entries = loadRuntimeManifest(vaultDir / "manifest.json", loadOutcome)
  if loadOutcome.codes.len > 0:
    result.codes = loadOutcome.codes
    result.detail = loadOutcome.detail
    return

  var scanOutcome = ExportOutcome(ok: false)
  let bodies = scanBodies(vaultDir, scanOutcome)
  if scanOutcome.codes.len > 0:
    result.codes = scanOutcome.codes
    result.detail = scanOutcome.detail
    return

  var index = initTable[string, seq[int]]()
  for i, b in bodies:
    let mp = safeStr(b.node, "modulePath")
    let fn = safeStr(b.node, "functionName")
    if mp.len == 0 or fn.len == 0: continue
    index.mgetOrPut(mp & "\x1f" & fn, @[]).add i

  # ─── claim scope (contract §2.2b) ──────────────────────────────────────
  # A declared target that the vault does not contain, or that maps to more
  # than one body, is a claim the engine cannot substantiate: fail closed
  # before any file is written. Non-declared verified rows are disclosed,
  # never counted.
  var scopeNode = newJNull()
  var selected = entries
  var outOfScope: seq[JsonNode] = @[]
  if declaredTargets.len > 0:
    var targets: seq[string] = @[]
    for t in declaredTargets:
      let trimmed = t.strip()
      if trimmed.len == 0 or trimmed.find("::") <= 0:
        result.codes.add("CERT_INVENTORY_MISMATCH")
        result.detail = "declared target is not <modulePath>::<functionName>: " & t
        return
      if trimmed notin targets: targets.add trimmed
    targets.sort(proc(a, b: string): int = cmp(a, b))
    var selectedEntries: seq[ManifestEntryV3] = @[]
    for t in targets:
      let sep = t.rfind("::")
      let mp = t[0 ..< sep]
      let fn = t[sep + 2 .. ^1]
      var found = false
      for e in entries:
        if e.modulePath == mp and e.functionName == fn:
          selectedEntries.add e
          found = true
          break
      if not found:
        result.codes.add("CERT_INVENTORY_MISMATCH")
        result.detail = "declared target is absent from the vault manifest: " & t
        return
    let targetSet = targets.toHashSet()
    for e in entries:
      if (e.modulePath & "::" & e.functionName) in targetSet: continue
      if not isVerifiedCertificateStatus(e.status): continue
      var row = newJObject()
      row["modulePath"] = %e.modulePath
      row["functionName"] = %e.functionName
      row["status"] = %e.status
      let cands = index.getOrDefault(e.modulePath & "\x1f" & e.functionName, @[])
      row["certificateFile"] =
        if cands.len == 1: %bodies[cands[0]].file else: newJNull()
      row["reason"] = %"not-declared"
      outOfScope.add row
    outOfScope.sort(proc(a, b: JsonNode): int =
      let ka = safeStr(a, "modulePath") & "\x1f" & safeStr(a, "functionName")
      let kb = safeStr(b, "modulePath") & "\x1f" & safeStr(b, "functionName")
      cmp(ka, kb))
    selected = selectedEntries
    var targetsArr = newJArray()
    for t in targets: targetsArr.add(%t)
    scopeNode = %*{
      "schema": "axiom.admission.cert-scope.v1",
      "targets": targetsArr
    }

  var usedFiles = initHashSet[string]()
  var projections: seq[JsonNode] = @[]
  var digestFiles: seq[string] = @[]
  var digestNodes = initTable[string, JsonNode]()

  for e in selected:
    var entryOut = newJObject()
    entryOut["modulePath"] = %e.modulePath
    entryOut["functionName"] = %e.functionName
    entryOut["status"] = %e.status
    entryOut["solverMethod"] = %e.solverMethod
    entryOut["lastVerifiedAt"] = %e.lastVerifiedAt
    entryOut["irHash"] = %e.irHash
    let verified = isVerifiedCertificateStatus(e.status)
    let cands = index.getOrDefault(e.modulePath & "\x1f" & e.functionName, @[])

    if cands.len > 1:
      result.codes.add("CERT_INVENTORY_MISMATCH")
      result.detail = "ambiguous certificate identity for " & e.modulePath & "::" &
        e.functionName & " (" & $cands.len & " bodies)"
      return
    if cands.len == 0:
      if verified:
        result.codes.add("CERT_BODY_MISSING")
        result.detail = "verified entry has no certificate body: " & e.modulePath &
          "::" & e.functionName & " status=" & e.status
        return
      entryOut["certificateFile"] = newJNull()
      entryOut["certificateSha256"] = newJNull()
      entryOut["recomputedStatus"] = newJNull()
      entryOut["theoremIdentity"] = newJNull()
      var obs = newJObject()
      obs["status"] = %"not-applicable"
      obs["names"] = newJNull()
      entryOut["axiomObservation"] = obs
      projections.add entryOut
      continue

    let b = bodies[cands[0]]
    let cas = certCasKey(b.node)
    if cas.len == 0 or b.file != cas & ".json":
      result.codes.add("CERT_INVENTORY_MISMATCH")
      result.detail = "certificate CAS key does not match its basename: " & b.file &
        " (key='" & cas & "')"
      return
    if usedFiles.contains(b.file):
      result.codes.add("CERT_INVENTORY_MISMATCH")
      result.detail = "certificate file bound to more than one manifest entry: " & b.file
      return
    usedFiles.incl(b.file)
    # Identity binding (the index key already matched; re-assert exact values).
    if safeStr(b.node, "modulePath") != e.modulePath or
        safeStr(b.node, "functionName") != e.functionName:
      result.codes.add("CERT_INVENTORY_MISMATCH")
      result.detail = "certificate identity does not match manifest entry: " & b.file
      return

    let sha = sha256Hex(b.raw)
    let recomputed = recomputedStatusOf(b.node)
    if verified and recomputed != e.status:
      result.codes.add("CERT_STATUS_MISMATCH")
      result.detail = "recomputed status " & recomputed & " != manifest status " &
        e.status & " for " & e.modulePath & "::" & e.functionName
      return
    if verified and leanEvidencePresent(b.node) and
        axiomObservationStatus(b.node) != "observed":
      result.codes.add("AXIOM_OBSERVATION_MISSING")
      result.detail = "Lean-dependent verified entry has no axiom observation: " &
        e.modulePath & "::" & e.functionName
      return

    let theorem = theoremIdentityOf(b.node)
    let obsStatus = axiomObservationStatus(b.node)
    let obsNames = axiomObservationNames(b.node)
    entryOut["certificateFile"] = %b.file
    entryOut["certificateSha256"] = %sha
    entryOut["recomputedStatus"] = %recomputed
    entryOut["theoremIdentity"] = stringOrNull(theorem)
    var obs = newJObject()
    obs["status"] = %obsStatus
    if obsStatus == "observed":
      var namesArr = newJArray()
      for n in obsNames: namesArr.add(%n)
      obs["names"] = namesArr
    else:
      obs["names"] = newJNull()
    entryOut["axiomObservation"] = obs
    projections.add entryOut

    var d = newJObject()
    d["file"] = %b.file
    d["sha256"] = %sha
    d["modulePath"] = %e.modulePath
    d["functionName"] = %e.functionName
    d["status"] = %e.status
    d["recomputedStatus"] = %recomputed
    d["theoremIdentity"] = stringOrNull(theorem)
    d["axiomObservation"] = %obsStatus
    digestNodes[b.file] = d
    digestFiles.add b.file

  # E4 — canonical certificate-set digest, sorted by file bytes.
  digestFiles.sort(proc(a, b: string): int = cmp(a, b))
  var digestArr = newJArray()
  for f in digestFiles:
    digestArr.add digestNodes[f]
  var digestInput = newJObject()
  digestInput["schema"] = %ExportSetSchema
  if scopeNode.kind == JObject:
    digestInput["scope"] = scopeNode
  digestInput["certificates"] = digestArr
  let digest = sha256Hex(canonicalJsonString(digestInput))

  var manifestNode = newJObject()
  manifestNode["schema"] = %ExportSchema
  manifestNode["version"] = %3
  if scopeNode.kind == JObject:
    manifestNode["scope"] = scopeNode
  manifestNode["certificateSetDigest"] = %digest
  var entriesArr = newJArray()
  for p in projections:
    entriesArr.add p
  manifestNode["entries"] = entriesArr
  if outOfScope.len > 0:
    var outArr = newJArray()
    for row in outOfScope: outArr.add row
    manifestNode["outOfScope"] = outArr

  # Write only after all checks passed.
  try:
    createDir(vaultOut)
    for b in bodies:
      if usedFiles.contains(b.file):
        writeFile(vaultOut / b.file, b.raw)
    writeFile(vaultOut / ExportManifestName, canonicalJsonString(manifestNode) & "\n")
    var names = @[ExportManifestName]
    for f in digestFiles: names.add f
    names.add ExportInventoryName
    names.sort(proc(a, b: string): int = cmp(a, b))
    writeFile(vaultOut / ExportInventoryName, names.join("\n") & "\n")
  except CatchableError as e:
    result.codes.add("CERT_INVENTORY_MISMATCH")
    result.detail = "export write failed: " & e.msg
    return

  result.ok = true
  result.digest = digest
  result.certCount = digestFiles.len
  result.bodyCount = digestFiles.len

# ─── verifier ───────────────────────────────────────────────────────────

type ParsedExport = object
  digest: string
  entries: seq[JsonNode]
  scopeNode: JsonNode  ## nil when the bundle carries no scope (legacy whole-vault export)

proc parseExportManifest(bundleDir: string; outcome: var VerifyOutcome): ParsedExport {.
    raises: [CatchableError], axiomEffect: IOEffect.} =
  let path = bundleDir / ExportManifestName
  if not fileExists(path):
    outcome.codes.add("CERT_BODY_MISSING")
    outcome.reasonCode = "CERT_BODY_MISSING"
    outcome.detail = "export manifest not found: " & path
    return
  var root: JsonNode
  try:
    root = parseJson(readFile(path))
  except CatchableError as e:
    outcome.codes.add("CERT_INVENTORY_MISMATCH")
    outcome.reasonCode = "CERT_INVENTORY_MISMATCH"
    outcome.detail = "export manifest unreadable: " & e.msg
    return
  let entriesNode = arrayField(root, "entries")
  if root.isNil or root.kind != JObject or entriesNode.isNil or
      safeStr(root, "schema") != ExportSchema:
    outcome.codes.add("CERT_INVENTORY_MISMATCH")
    outcome.reasonCode = "CERT_INVENTORY_MISMATCH"
    outcome.detail = "export manifest schema mismatch (expected " & ExportSchema & ")"
    return
  result.digest = safeStr(root, "certificateSetDigest")
  let scope = root.getOrDefault("scope")
  if not scope.isNil:
    if scope.kind != JObject or scope.getOrDefault("schema").kind != JString or
        scope["schema"].getStr("") != "axiom.admission.cert-scope.v1" or
        arrayField(scope, "targets").isNil:
      outcome.codes.add("CERT_INVENTORY_MISMATCH")
      outcome.reasonCode = "CERT_INVENTORY_MISMATCH"
      outcome.detail = "export manifest scope block is malformed"
      return
    result.scopeNode = scope
  for e in entriesNode:
    if e.kind != JObject:
      outcome.codes.add("CERT_INVENTORY_MISMATCH")
      outcome.reasonCode = "CERT_INVENTORY_MISMATCH"
      outcome.detail = "export manifest entry is not an object"
      return
    result.entries.add e

proc listBundleFiles(bundleDir: string; outcome: var VerifyOutcome): HashSet[string] {.
    raises: [CatchableError], axiomEffect: IOEffect.} =
  result = initHashSet[string]()
  for kind, path in walkDir(bundleDir):
    let name = extractFilename(path)
    if kind != pcFile:
      outcome.codes.add("CERT_INVENTORY_MISMATCH")
      outcome.reasonCode = "CERT_INVENTORY_MISMATCH"
      outcome.detail = "non-regular file in export set: " & name
      return
    if name == ExportManifestName or name == ExportInventoryName:
      result.incl name
    elif name.endsWith(".json") and name.len > 5 and
        isLowerHex64(name[0 ..< name.len - 5]):
      result.incl name
    else:
      outcome.codes.add("CERT_INVENTORY_MISMATCH")
      outcome.reasonCode = "CERT_INVENTORY_MISMATCH"
      outcome.detail = "unexpected file in export set: " & name
      return

proc readInventory(bundleDir: string; outcome: var VerifyOutcome): seq[string] {.
    raises: [CatchableError], axiomEffect: IOEffect.} =
  let path = bundleDir / ExportInventoryName
  if not fileExists(path):
    outcome.codes.add("CERT_INVENTORY_MISMATCH")
    outcome.reasonCode = "CERT_INVENTORY_MISMATCH"
    outcome.detail = "inventory not found: " & path
    return @[]
  var seen = initHashSet[string]()
  var prev = ""
  for line in readFile(path).splitLines():
    if line.len == 0: continue
    if seen.contains(line):
      outcome.codes.add("CERT_INVENTORY_MISMATCH")
      outcome.reasonCode = "CERT_INVENTORY_MISMATCH"
      outcome.detail = "duplicate inventory entry: " & line
      return @[]
    if prev.len > 0 and cmp(prev, line) >= 0:
      outcome.codes.add("CERT_INVENTORY_MISMATCH")
      outcome.reasonCode = "CERT_INVENTORY_MISMATCH"
      outcome.detail = "inventory is not sorted: " & prev & " >= " & line
      return @[]
    seen.incl line
    result.add line
    prev = line

proc verifyBundle*(bundleDir: string; closureMode: bool = false;
                   projectRoot: string = "";
                   declaredTargets: seq[string] = @[]): VerifyOutcome {.
    raises: [CatchableError], axiomEffect: IOEffect.} =
  ## Contract §3.1 priority order. The first failing pass is the reasonCode;
  ## later passes are not evaluated (targeted negative controls need a
  ## deterministic code, not the first incidental digest error).
  result = VerifyOutcome(ok: false, reasonCode: "", codes: @[], detail: "",
    digest: "", bodiesPresent: false, entryCount: 0, closure: "not-claimed",
    environmentError: false)

  var parsed = parseExportManifest(bundleDir, result)
  if result.reasonCode.len > 0: return
  result.entryCount = parsed.entries.len
  result.digest = parsed.digest

  # Pass 1 — inventory exact match (files vs manifest references vs inventory).
  var files = listBundleFiles(bundleDir, result)
  if result.reasonCode.len > 0: return
  var inventory = readInventory(bundleDir, result)
  if result.reasonCode.len > 0: return
  var invSet = initHashSet[string]()
  for line in inventory: invSet.incl line
  if invSet != files:
    result.codes.add("CERT_INVENTORY_MISMATCH")
    result.reasonCode = "CERT_INVENTORY_MISMATCH"
    result.detail = "inventory does not match export set"
    return
  var referenced = initHashSet[string]()
  for e in parsed.entries:
    let f = e.getOrDefault("certificateFile")
    if f.isNil or f.kind == JNull: continue
    if f.kind != JString:
      result.codes.add("CERT_INVENTORY_MISMATCH")
      result.reasonCode = "CERT_INVENTORY_MISMATCH"
      result.detail = "certificateFile is not a string/null"
      return
    let name = f.getStr("")
    if not files.contains(name):
      result.codes.add("CERT_INVENTORY_MISMATCH")
      result.reasonCode = "CERT_INVENTORY_MISMATCH"
      result.detail = "manifest references a missing body: " & name
      return
    if referenced.contains(name):
      result.codes.add("CERT_INVENTORY_MISMATCH")
      result.reasonCode = "CERT_INVENTORY_MISMATCH"
      result.detail = "body referenced by more than one entry: " & name
      return
    referenced.incl name
  for name in files:
    if name == ExportManifestName or name == ExportInventoryName: continue
    if not referenced.contains(name):
      result.codes.add("CERT_INVENTORY_MISMATCH")
      result.reasonCode = "CERT_INVENTORY_MISMATCH"
      result.detail = "body is not referenced by the manifest: " & name
      return

  # Pass 1a — claim scope (contract §2.2b). When the consumer knows the
  # declared proposition set, the bundle must claim exactly that set; a
  # bundle that silently narrows or widens the claim fails closed. Every
  # declared target must resolve to a body-backed verified entry.
  var effectiveScope: seq[string] = @[]
  if not parsed.scopeNode.isNil:
    for t in arrayField(parsed.scopeNode, "targets"):
      if t.kind != JString or t.getStr("").len == 0:
        result.codes.add("CERT_INVENTORY_MISMATCH")
        result.reasonCode = "CERT_INVENTORY_MISMATCH"
        result.detail = "scope target is not a non-empty string"
        return
      effectiveScope.add t.getStr("")
  if declaredTargets.len > 0:
    var expected: seq[string] = @[]
    for t in declaredTargets:
      let trimmed = t.strip()
      if trimmed.len == 0 or trimmed.find("::") <= 0:
        result.codes.add("CERT_INVENTORY_MISMATCH")
        result.reasonCode = "CERT_INVENTORY_MISMATCH"
        result.detail = "declared target is not <modulePath>::<functionName>: " & t
        return
      if trimmed notin expected: expected.add trimmed
    expected.sort(proc(a, b: string): int = cmp(a, b))
    var actual = effectiveScope
    actual.sort(proc(a, b: string): int = cmp(a, b))
    if actual != expected:
      result.codes.add("CERT_SCOPE_MISMATCH")
      result.reasonCode = "CERT_SCOPE_MISMATCH"
      result.detail = "bundle scope does not equal the declared target set"
      return
    for t in expected:
      let sep = t.rfind("::")
      let mp = t[0 ..< sep]
      let fn = t[sep + 2 .. ^1]
      var entry: JsonNode = nil
      for e in parsed.entries:
        if safeStr(e, "modulePath") == mp and safeStr(e, "functionName") == fn:
          entry = e
          break
      if entry.isNil:
        result.codes.add("CERT_SCOPE_MISMATCH")
        result.reasonCode = "CERT_SCOPE_MISMATCH"
        result.detail = "declared target is absent from the bundle: " & t
        return
      if not isVerifiedCertificateStatus(safeStr(entry, "status")):
        result.codes.add("CERT_STATUS_MISMATCH")
        result.reasonCode = "CERT_STATUS_MISMATCH"
        result.detail = "declared target is not a verified claim: " & t
        return

  var verifiedEntries: seq[JsonNode] = @[]

  # Pass 2 — verified entries require a body.
  for e in parsed.entries:
    let status = safeStr(e, "status")
    if isVerifiedCertificateStatus(status):
      verifiedEntries.add e
      let f = e.getOrDefault("certificateFile")
      if f.isNil or f.kind == JNull or f.getStr("").len == 0:
        result.codes.add("CERT_BODY_MISSING")
        result.reasonCode = "CERT_BODY_MISSING"
        result.detail = "verified entry without certificate body: " &
          safeStr(e, "modulePath") & "::" & safeStr(e, "functionName")
        return
  result.bodiesPresent = true

  # Pass 3 — raw body bytes hash.
  var bodyCache = initTable[string, tuple[raw: string; node: JsonNode]]()
  for e in parsed.entries:
    let f = e.getOrDefault("certificateFile")
    if f.isNil or f.kind == JNull: continue
    let name = f.getStr("")
    if bodyCache.hasKey(name): continue
    let raw = readFile(bundleDir / name)
    var node: JsonNode
    try:
      node = parseJson(raw)
    except CatchableError:
      result.codes.add("CERT_INVENTORY_MISMATCH")
      result.reasonCode = "CERT_INVENTORY_MISMATCH"
      result.detail = "certificate body is not valid JSON: " & name
      return
    if node.isNil or node.kind != JObject:
      result.codes.add("CERT_INVENTORY_MISMATCH")
      result.reasonCode = "CERT_INVENTORY_MISMATCH"
      result.detail = "certificate body is not a JSON object: " & name
      return
    bodyCache[name] = (raw: raw, node: node)
    let recorded = safeStr(e, "certificateSha256")
    if recorded.len == 0 or recorded != sha256Hex(raw):
      result.codes.add("CERT_DIGEST_MISMATCH")
      result.reasonCode = "CERT_DIGEST_MISMATCH"
      result.detail = "certificate body hash mismatch: " & name
      return

  # Pass 4 — status/tier projection + recorded projection consistency.
  for e in parsed.entries:
    let name = safeStr(e, "certificateFile")
    if name.len == 0:
      if hasString(e, "recomputedStatus") or hasString(e, "certificateSha256"):
        result.codes.add("CERT_PROJECTION_MISMATCH")
        result.reasonCode = "CERT_PROJECTION_MISMATCH"
        result.detail = "entry without body carries a body projection"
        return
      continue
    if not bodyCache.hasKey(name): continue
    let node = bodyCache[name].node
    let recomputed = recomputedStatusOf(node)
    let recorded = safeStr(e, "recomputedStatus")
    if recorded != recomputed:
      result.codes.add("CERT_STATUS_MISMATCH")
      result.reasonCode = "CERT_STATUS_MISMATCH"
      result.detail = "recomputedStatus mismatch for " & name & ": recorded='" &
        recorded & "' recomputed='" & recomputed & "'"
      return
    let status = safeStr(e, "status")
    if isVerifiedCertificateStatus(status) and status != recomputed:
      result.codes.add("CERT_STATUS_MISMATCH")
      result.reasonCode = "CERT_STATUS_MISMATCH"
      result.detail = "verified status " & status & " != recomputed " & recomputed &
        " for " & name
      return
    let recordedTheorem = e.getOrDefault("theoremIdentity")
    let theorem = theoremIdentityOf(node)
    let theoremMatches =
      if recordedTheorem.isNil or recordedTheorem.kind == JNull:
        theorem.len == 0
      else:
        recordedTheorem.kind == JString and recordedTheorem.getStr("") == theorem
    if not theoremMatches:
      result.codes.add("CERT_PROJECTION_MISMATCH")
      result.reasonCode = "CERT_PROJECTION_MISMATCH"
      result.detail = "theoremIdentity projection mismatch for " & name
      return

  # Pass 5 — engine closure (producer-only; consumer checks the recorded binding).
  if closureMode:
    result.closure = "executed"
    for e in verifiedEntries:
      let name = safeStr(e, "certificateFile")
      let res = verifyCertificateClosure(bundleDir / name, projectRoot)
      case res.status
      of ccsPass:
        discard
      of ccsJournalBindingAbsent, ccsJournalRequired:
        result.codes.add("CERT_INTEGRITY_FAILED")
        result.reasonCode = "CERT_INTEGRITY_FAILED"
        result.environmentError = true
        result.detail = "closure unavailable for " & name & ": " & res.detail
        return
      else:
        result.codes.add("CERT_INTEGRITY_FAILED")
        result.reasonCode = "CERT_INTEGRITY_FAILED"
        result.detail = "closure failed for " & name & ": " & res.detail
        return

  # Pass 6 — axiom observation policy.
  for e in verifiedEntries:
    let name = safeStr(e, "certificateFile")
    if not bodyCache.hasKey(name): continue
    let node = bodyCache[name].node
    let recorded = objectField(e, "axiomObservation")
    let recordedStatus = if recorded.isNil: "" else: safeStr(recorded, "status")
    let recomputed = axiomObservationStatus(node)
    if recordedStatus != recomputed:
      result.codes.add("AXIOM_OBSERVATION_MISSING")
      result.reasonCode = "AXIOM_OBSERVATION_MISSING"
      result.detail = "axiomObservation projection mismatch for " & name & ": recorded='" &
        recordedStatus & "' recomputed='" & recomputed & "'"
      return
    if leanEvidencePresent(node) and recomputed != "observed":
      result.codes.add("AXIOM_OBSERVATION_MISSING")
      result.reasonCode = "AXIOM_OBSERVATION_MISSING"
      result.detail = "Lean-dependent verified entry has no axiom observation: " & name
      return
    if not recorded.isNil and recomputed == "observed":
      let recNames = recorded.getOrDefault("names")
      let names = axiomObservationNames(node)
      var matches = not recNames.isNil and recNames.kind == JArray and
        recNames.len == names.len
      if matches:
        for i in 0 ..< names.len:
          if recNames[i].kind != JString or recNames[i].getStr("") != names[i]:
            matches = false
            break
      if not matches:
        result.codes.add("CERT_PROJECTION_MISMATCH")
        result.reasonCode = "CERT_PROJECTION_MISMATCH"
        result.detail = "axiomObservation names projection mismatch for " & name
        return

  # Pass 7 — certificate-set digest.
  if result.digest.len == 0:
    result.codes.add("CERT_SET_DIGEST_ABSENT")
    result.reasonCode = "CERT_SET_DIGEST_ABSENT"
    result.detail = "certificateSetDigest is absent"
    return
  var digestNodes = initTable[string, JsonNode]()
  for e in parsed.entries:
    let name = safeStr(e, "certificateFile")
    if name.len == 0: continue
    var d = newJObject()
    d["file"] = %name
    d["sha256"] = fieldOrNull(e, "certificateSha256")
    d["modulePath"] = fieldOrNull(e, "modulePath")
    d["functionName"] = fieldOrNull(e, "functionName")
    d["status"] = fieldOrNull(e, "status")
    d["recomputedStatus"] = fieldOrNull(e, "recomputedStatus")
    d["theoremIdentity"] = fieldOrNull(e, "theoremIdentity")
    let obs = objectField(e, "axiomObservation")
    d["axiomObservation"] = if obs.isNil: newJNull() else: fieldOrNull(obs, "status")
    digestNodes[name] = d
  var digestFiles: seq[string] = @[]
  for name in digestNodes.keys: digestFiles.add name
  digestFiles.sort(proc(a, b: string): int = cmp(a, b))
  var digestArr = newJArray()
  for f in digestFiles: digestArr.add digestNodes[f]
  var digestInput = newJObject()
  digestInput["schema"] = %ExportSetSchema
  if not parsed.scopeNode.isNil:
    digestInput["scope"] = parsed.scopeNode
  digestInput["certificates"] = digestArr
  let recomputedDigest = sha256Hex(canonicalJsonString(digestInput))
  if recomputedDigest != result.digest:
    result.codes.add("CERT_SET_DIGEST_MISMATCH")
    result.reasonCode = "CERT_SET_DIGEST_MISMATCH"
    result.detail = "certificateSetDigest mismatch: recorded='" & result.digest &
      "' recomputed='" & recomputedDigest & "'"
    return

  result.digest = recomputedDigest
  result.ok = true

# ─── CLI surfaces ───────────────────────────────────────────────────────

proc loadProposalTargets(path: string; targets: var seq[string]): string {.
    raises: [CatchableError].} =
  ## Reads the admission proposals artifact and returns its declared
  ## `propositions[].target` set (`modulePath::functionName`). Fail-closed:
  ## an unreadable file, a non-array propositions field, or an empty target
  ## set is an error the caller must report (never a silent unscoped export).
  if not fileExists(path):
    return "proposals file not found: " & path
  var root: JsonNode
  try:
    root = parseJson(readFile(path))
  except CatchableError as e:
    return "proposals file unreadable: " & e.msg
  let props = arrayField(root, "propositions")
  if props.isNil:
    return "proposals file has no propositions[] array"
  for p in props:
    if p.kind != JObject: continue
    let t = safeStr(p, "target")
    if t.len == 0: continue
    if t.find("::") <= 0:
      return "proposals target is not <modulePath>::<functionName>: " & t
    if t notin targets: targets.add t
  if targets.len == 0:
    return "proposals file declares no targets"
  ""

func defaultVaultDir(): string {.raises: [].} =
  let state = getEnv("AXIOM_STATE_DIR", "")
  if state.len > 0: state / "build" / "certificates"
  else: "build" / "certificates"

proc runCertExportCli*(args: seq[string]): int {.
    raises: [CatchableError], axiomEffect: IOEffect.} =
  ## `ax cert export --vault <dir> --out <artifact-root> [--json]`
  var vaultDir = ""
  var outRoot = ""
  var asJson = false
  var targets: seq[string] = @[]
  var i = 0
  while i < args.len:
    if args[i] == "--vault" and i + 1 < args.len:
      vaultDir = args[i + 1]
      inc i
    elif args[i] == "--out" and i + 1 < args.len:
      outRoot = args[i + 1]
      inc i
    elif args[i] == "--proposals" and i + 1 < args.len:
      let err = loadProposalTargets(args[i + 1], targets)
      if err.len > 0:
        echo "[cert] Export: FAIL — CERT_INVENTORY_MISMATCH: " & err
        return 2
      inc i
    elif args[i] == "--target" and i + 1 < args.len:
      let t = args[i + 1].strip()
      if t.len == 0 or t.find("::") <= 0:
        echo "[cert] Export: FAIL — CERT_INVENTORY_MISMATCH: declared target is not <modulePath>::<functionName>: " & args[i + 1]
        return 2
      if t notin targets: targets.add t
      inc i
    elif args[i] == "--json":
      asJson = true
    else:
      echo "Usage: ax cert export [--vault <dir>] --out <artifact-root> [--proposals <file> | --target <module::function> ...] [--json]"
      return 2
    inc i
  if outRoot.len == 0:
    echo "Usage: ax cert export [--vault <dir>] --out <artifact-root> [--proposals <file> | --target <module::function> ...] [--json]"
    return 2
  if vaultDir.len == 0: vaultDir = defaultVaultDir()

  let outcome = exportToDir(vaultDir, outRoot, targets)
  if asJson:
    var j = newJObject()
    j["schema"] = %"axiom.cert-export.v1"
    j["verdict"] = %(if outcome.ok: "PASS" else: "FAIL")
    j["certificateSetDigest"] = stringOrNull(outcome.digest)
    j["certificateCount"] = %outcome.certCount
    var diags = newJArray()
    for c in outcome.codes: diags.add(%c)
    j["diagnostics"] = diags
    echo $j
  elif outcome.ok:
    echo "[cert] Export: PASS — " & $outcome.certCount & " certificate(s), digest " &
      outcome.digest
  else:
    echo "[cert] Export: FAIL — " & outcome.codes.join(", ") & ": " & outcome.detail
  if outcome.ok: 0 else: 1

proc runCertVerifyExportCli*(args: seq[string]): int {.
    raises: [CatchableError], axiomEffect: IOEffect.} =
  ## `ax cert verify-export --bundle <artifact-root>/vault [--closure --project <subject>] [--json]`
  var bundleDir = ""
  var projectRoot = ""
  var closureMode = false
  var asJson = false
  var targets: seq[string] = @[]
  var i = 0
  while i < args.len:
    if args[i] == "--bundle" and i + 1 < args.len:
      bundleDir = args[i + 1]
      inc i
    elif args[i] == "--project" and i + 1 < args.len:
      projectRoot = args[i + 1]
      inc i
    elif args[i] == "--proposals" and i + 1 < args.len:
      let err = loadProposalTargets(args[i + 1], targets)
      if err.len > 0:
        echo "[cert] Verify-export: FAIL — CERT_INVENTORY_MISMATCH: " & err
        return 2
      inc i
    elif args[i] == "--target" and i + 1 < args.len:
      let t = args[i + 1].strip()
      if t.len == 0 or t.find("::") <= 0:
        echo "[cert] Verify-export: FAIL — CERT_INVENTORY_MISMATCH: declared target is not <modulePath>::<functionName>: " & args[i + 1]
        return 2
      if t notin targets: targets.add t
      inc i
    elif args[i] == "--closure":
      closureMode = true
    elif args[i] == "--json":
      asJson = true
    else:
      echo "Usage: ax cert verify-export --bundle <dir> [--closure --project <dir>] [--proposals <file> | --target <module::function> ...] [--json]"
      return 2
    inc i
  if bundleDir.len == 0:
    echo "Usage: ax cert verify-export --bundle <dir> [--closure --project <dir>] [--proposals <file> | --target <module::function> ...] [--json]"
    return 2

  let outcome = verifyBundle(bundleDir, closureMode, projectRoot, targets)
  if asJson:
    var j = newJObject()
    j["schema"] = %ExportVerifySchema
    j["verdict"] = %(if outcome.ok: "PASS" else: "FAIL")
    j["reasonCode"] = stringOrNull(outcome.reasonCode)
    var codes = newJArray()
    for c in outcome.codes: codes.add(%c)
    j["codes"] = codes
    j["certificateSetDigest"] = stringOrNull(outcome.digest)
    j["certificateBodiesPresent"] = %outcome.bodiesPresent
    j["entryCount"] = %outcome.entryCount
    j["closure"] = %outcome.closure
    echo $j
  elif outcome.ok:
    echo "[cert] Verify-export: PASS — " & $outcome.entryCount & " entries, digest " &
      outcome.digest & " (closure=" & outcome.closure & ")"
  else:
    echo "[cert] Verify-export: FAIL — " & outcome.reasonCode & ": " & outcome.detail
  if outcome.ok: 0
  elif outcome.environmentError: 2
  else: 1

{.pop.}