## epoch_transaction_gate.nim — CI quantization: epoch promotion transaction 4-way binding (S0-c)
##
## The epoch promotion transaction is ONE atomic unit (approved plan S0):
##     SliceCatalog (SSOT) + Epoch Manifest + SliceEngine mapping (callee 3종)
##     + productionExecutionPin  ← same commit (minimum: same PR); any drift =
##     fail-closed. All four 1-way inconsistency scenarios (Catalog↔Manifest,
##     Manifest↔Engine, Manifest↔Pin, Engine↔Pin) were measured fail-open
##     before this gate; the only fail-closed point was the TWS pair, and only
##     post-merge (mint step 2a). PR-time atomicity is now enforced HERE.
##
## Judgment, 3 layers (ALL fail-closed; emitted reason codes
## EPOCH_TRANSACTION_INCOMPLETE / EPOCH_TRANSACTION_INCONSISTENT):
##   1. diff (PR time): closure-group rule — the binding targets form TWO
##      closure groups (declared in the catalog, single authority):
##        G1 slice-state closure = SliceCatalog + Manifest slice fields
##           (implementedSlices / notYetImplementedSlices)
##        G2 engine-pin closure  = SliceEngine mapping (callee 3종)
##           + productionExecutionPin record (TWS) + Manifest
##           productionExecutionPin field
##      A changed group must be closed in its entirety: a promotion updates
##      {catalog, manifest slice fields} together. The engine/pin update rule
##      is SPLIT by the pin's binding target (minimal closure-semantics
##      correction, 2026-09-29 — the pre-split "an engine/pin update advances
##      {blob, TWS record, manifest pin field} together" rule had NO legal
##      transaction for a NON-pinned engine change: measured A/B/C deadlock —
##      pin value unchanged → layer-1 G2 incomplete; pin value changed →
##      layer-3 TWS-atomicity violation, since the pin is bound to the
##      admission-check.yml blob which did not move):
##        G2a — PINNED engine (admission-check.yml, the pin's blob target):
##          a change must advance {TWS record path, manifest pin VALUE} in the
##          same commit (unchanged rule — layer 3 head leg re-verifies the
##          3-way equality at HEAD).
##        G2b — NON-pinned engines (certificate-mint.yml /
##          runner-pool-acceptance.yml): a change must be claimed by a slice
##          promotion inside the same PR (path 1 — the manifest's
##          implementedSlices gains a slice whose catalog engineFiles contain
##          the changed file; catalog false→true pairing is enforced by G1)
##          OR satisfy the implemented-scope repair path (path 2, added
##          2026-09-29 by closure-semantics correction — epoch N+5 복구 B;
##          judgment: I-4 펜스는 notYet 범위 — implemented slice의 엔진 수리는
##          I-4 위반이 아니다; 수리를 승격과만 결속시키는 것은 false negative):
##          engine change + epoch 정의 불변 (catalog slice fields · manifest
##          slice fields · TWS · pin 전부 무터치 — 단, 2026-10-09 귀속 정정:
##          핀 엔진 admission-check.yml이 동일 diff에 있으면 TWS/pin 변경은
##          G2a 의무 쌍으로 귀속되어 epoch 정의 접촉으로 세지 않는다; 카탈로그·
##          슬라이스 필드 접촉은 여전히 FAIL) + layer 2/3 PASS (현행 유지)
##          + scope-게이트 표면 비감소 (b — `scope_*` if: 조건 수와
##          `[slice-engine]` 스텝 수가 base 대비 감소 금지 — 게이트
##          제거/무력화 차단, 기계 검사) + PR 본문의 implemented-scope 선언
##          (c — human check). TWS/pin touch NOT required (no value binding
##          exists for these files) — an engine change outside promotion
##          scope, or failing path-2, or touching the epoch definition
##          without promotion = FAIL (I-4 strengthening).
##          Job-level scope surface (2026-10-20 추가 — 스텝 카운터의 사각지대
##          폐쇄): condition (b)의 기계 검사는 `steps.slice-engine.outputs.scope_*`
##          (스텝 수준)만 세고 job-level 게이트(`needs.<job>.outputs.scope_*`)는
##          세지 않았다. runner-pool-acceptance.yml의 SL-09 레인 게이트는
##          job-level이므로, 그 게이트를 삭제/무력화해도 카운터가 불변 → 래칫이
##          통과하는 구멍이었다. 이제 job-level `if:` 조건 수를 별도 카운터로
##          함께 산출·비감소 판정에 포함한다 (기존 카운터·판정 계약은 불변 —
##          추가 카운터는 비감소 조건의 추가 합집합 항일 뿐).
##      TWS field split (2026-10-10 — closure-semantics correction; the
##      manifestFieldState principle applied to the pin record): the TWS
##      path carries TWO independently-bound fields. A
##      trustedCheckerTreeClosure re-anchor (a closure member changed in the
##      same PR → the derived closure refresh) with the pin VALUE
##      trustedAdmissionWorkflowSha unchanged advances NEITHER leg of the
##      layer-3 3-way equality, so it is NOT a pin change: it passes layer 1
##      with a loud NOTE while layers 2/3 still verify the record at HEAD,
##      and the closure CONTENT equality (TWS == derived closure at H) stays
##      owned by the merge-time rotation check. Unreadable/unparsable TWS at
##      either revision classifies as BOTH fields changed (fail-closed —
##      every pairing requirement then applies). A pin-VALUE move keeps the
##      full G2a pairing obligation.
##      Single updates stay fail-closed as before: a TWS pin-VALUE change
##      alone, pin alone, catalog alone, manifest alone, and admission-check
##      alone (without its TWS/pin pair) are all still rejected. Partial
##      update inside a group =
##      FAIL (measured: the N+1 SL-08 catalog+manifest-only promotion was
##      rejected by the pre-fix all-four rule with 2×
##      EPOCH_TRANSACTION_INCOMPLETE).
##      Introduction exemption: if the base tree has NO epoch manifest yet
##      (this exact S0-c introduction transaction), layer 1 passes with a
##      loud note — the binding is enforced from the next commit onward
##      (registered-ahead 관례, config/repository_surface.json v17/v19/v20).
##   2. content: manifest.implementedSlices == catalog implemented projection
##      == engine firing set (양방향 등식 — symmetric differences both empty).
##      Engine firing set = implemented slices whose declared step-name
##      patterns are actually found in the callee workflow `- name:` lines
##      (pre-promotion step presence is NOT quantization state — epoch N+1 is
##      not active yet). Coverage invariant: implementedSlices ∪
##      notYetImplementedSlices == the whole catalog, disjoint, all ids known.
##   3. pin: pin-record consistency is judged at BOTH revisions — one leg per
##      revision (the measured S0-c defect was judging the HEAD pin against
##      the BASE record: a legitimate transaction MUST advance the pin record
##      and the engine blob in the same commit, so HEAD pin != base pin BY
##      CONSTRUCTION — that mode rejected the only legal transaction while
##      the static mode passed it; now both modes require the same 3-party
##      equality at HEAD, plus base consistency at base):
##      (a) base leg — TWS pin record == git blob sha(admission-check.yml)
##          @base: "the base binding was not broken" (original meaning,
##          preserved at the original revision). base = origin/main is always
##          gate-consistent → any base drift FAILS, fail-closed, no
##          introduction exemption.
##      (b) head leg — manifest.productionExecutionPin (working tree = head
##          checkout) == TWS == blob @HEAD (3-way): "the new state this PR
##          ships is self-consistent" — the same 3-party equality the static
##          mode enforces.
##      INTERPRETATION RULE (org ruleset pin is outside the repo and cannot
##      be queried from here): the repo-observable record of the
##      productionExecutionPin is config/trusted_writer_set.json field
##      trustedAdmissionWorkflowSha (content-addressed git blob sha of
##      admission-check.yml, ADR-0022 §5 — the ATOMICITY pair): the TWS value
##      MUST equal the git blob sha of the admission workflow at the same
##      revision (engine↔pin alignment, fail-closed when git works).
##
## Layers 2 reads the WORKING TREE (the gate runs from a checkout of head —
## the push snapshot / PR branch); layer 1 compares OIDs via git. Layer 3
## reads the manifest from the working tree but TWS / engine blob via git
## OIDs — deterministic at both the base and the head revision.
##
## Two invocation modes (same binary):
##   epoch_transaction_gate
##       → static self-check only (layers 2+3 vs the current tree; layer 1
##         not applicable — GATES_FAST / pre-push thin wiring).
##   epoch_transaction_gate --diff <base> <head>
##       → full 3-layer judgment at PR time (base = merge-base(origin/main,
##         HEAD), head = "HEAD" — same pattern as check-repository-surface).
##
## Determinism: no timestamps, no randomness, no network; all sets sorted.
## Exit: 0 = consistent, 1 = drift (fail closed), 2 = usage/env error.

import core/trusted/layer_declaration
axiomLayer "tools"
import core/trusted/axiom_pragmas_lite

import gate/slice_catalog
import std/[os, osproc, strutils, sequtils, sets, json, parseopt, algorithm]

{.push raises: [].}

const
  ManifestSchemaNote = "5-field schema: ciEpochId, implementedSlices[], " &
                       "notYetImplementedSlices[], productionExecutionPin, mode"
  ValidModes = ["ci-migration", "normal"]
  ReasonIncomplete = "EPOCH_TRANSACTION_INCOMPLETE"
  ReasonInconsistent = "EPOCH_TRANSACTION_INCONSISTENT"

# ═══════════════════════════════════════════════════════════════════════════
# Helpers (proof_reconcile_gate conventions)
# ═══════════════════════════════════════════════════════════════════════════

func jsonStr(node: JsonNode, key: string): string =
  ## Field value as string; "" for missing/non-string leaves (callers treat
  ## empty as absent — fail-closed via explicit emptiness checks).
  if node == nil or node.kind != JObject:
    return ""
  var v: JsonNode
  try:
    v = node[key]
  except CatchableError:
    return ""
  if v == nil or v.kind != JString:
    return ""
  result = v.str

func jsonStrArray(node: JsonNode, key: string): seq[string] =
  ## Field value as sorted seq of strings; empty when absent/not an array.
  if node == nil or node.kind != JObject:
    return @[]
  var v: JsonNode
  try:
    v = node[key]
  except CatchableError:
    return @[]
  if v == nil or v.kind != JArray:
    return @[]
  for i in 0 ..< v.len:
    let item = v[i]
    if item.kind == JString:
      result.add(item.str)
  result.sort()

proc execGit(args: string): tuple[outp: string, code: int] {.axiomEffect: IoEffect.} =
  ## repo-standard external git invocation; FAIL (code != 0) propagates to
  ## callers. Never read from env/network.
  try:
    let r = execCmdEx("git " & args)
    result = (r.output, r.exitCode)
  except CatchableError:
    result = ("", -1)

proc stripJsonc(raw: string): string =
  ## Full-line `//` documentation comment strip (config/trusted_writer_set.json
  ## convention — same as verify_trusted_writer_set.sh / admission D9 draft).
  var lines = raw.splitLines()
  for i in 0 ..< lines.len:
    let stripped = lines[i].strip(leading = true)
    if stripped.startsWith("//"):
      lines[i] = ""
  result = lines.join("\n")

proc parseJsoncFile(path: string): tuple[node: JsonNode, ok: bool] =
  ## Parse a possibly-JSONC file from the working tree.
  var raw = ""
  try:
    raw = readFile(path)
  except CatchableError:
    return (nil, false)
  if raw.len == 0:
    return (nil, false)
  try:
    result = (parseJson(stripJsonc(raw)), true)
  except CatchableError:
    result = (nil, false)

proc gitShowFile(oid, path: string): tuple[bytes: string, code: int] {.axiomEffect: IoEffect.} =
  ## `git show <oid>:<path>` — file bytes at a git revision (base reads).
  let r = execGit("show " & oid & ":" & quoteShell(path))
  result = (r.outp, r.code)

proc gitBlobSha(oid, path: string): tuple[sha: string, code: int] {.axiomEffect: IoEffect.} =
  ## `git rev-parse <oid>:<path>` — content-addressed blob sha (TWS pairing).
  let r = execGit("rev-parse " & oid & ":" & quoteShell(path))
  result = (r.outp, r.code)

# ═══════════════════════════════════════════════════════════════════════════
# Layer 2 — catalog ↔ manifest ↔ engine firing equality
# ═══════════════════════════════════════════════════════════════════════════

func sortedCatalogIds(): seq[string] =
  for s in SliceCatalog:
    result.add(s.id)
  result.sort()

func catalogImplementedIds(): seq[string] =
  for s in SliceCatalog:
    if s.implemented:
      result.add(s.id)
  result.sort()

func catalogIdsUniquenessFailures(): seq[string] =
  ## Catalog invariant: ids unique (a duplicate would make the manifest
  ## equality checks ambiguous).
  var seen: HashSet[string]
  for s in SliceCatalog:
    if s.id in seen:
      result.add("duplicate catalog slice id: " & s.id)
    seen.incl(s.id)

func symmetricDiff(a, b: seq[string]): seq[string] =
  ## Sorted symmetric difference — both directions, "양방향 등식".
  let sa = a.toHashSet()
  let sb = b.toHashSet()
  for x in a:
    if x notin sb:
      result.add("only in A: " & x)
  for x in b:
    if x notin sa:
      result.add("only in B: " & x)
  result.sort()

func engineStepLine(line, pattern: string): bool =
  ## A `- name:` line whose step name contains the pattern (case-sensitive).
  let stripped = line.strip()
  if not stripped.startsWith("- name:"):
    return false
  result = stripped.contains(pattern)

proc engineFires(sl: EpochSlice, engineRoot: string): tuple[found: bool, evidence: string] {.axiomEffect: IoEffect.} =
  ## Does slice `sl` have ≥1 declared step pattern in its engine files?
  ## Step-name lines only (`- name:`); comments cannot false-positive.
  for f in sl.engineFiles:
    let path = engineRoot / EngineMappingDir / f
    var raw = ""
    try:
      raw = readFile(path)
    except CatchableError:
      continue  # missing engine file → not found (fail-closed)
    for line in raw.splitLines():
      for step in sl.verificationSteps:
        if engineStepLine(line, step.stepNamePattern):
          return (true, f & " :: " & step.stepNamePattern)
  result = (false, "")

proc manifestFailures(headRoot: string): seq[string] {.axiomEffect: IoEffect.} =
  ## Layer 2 — full content consistency judgment (working tree = head).
  let manifestPath = headRoot / EpochManifestPath
  let (manifest, parsedOk) = parseJsoncFile(manifestPath)
  if not parsedOk:
    result.add("epoch manifest unreadable/unparsable: " & EpochManifestPath &
               " (" & ManifestSchemaNote & ")")
    return

  # ── schema: 5 fields, valid types/values ──
  let ciEpochId = jsonStr(manifest, "ciEpochId")
  let implemented = jsonStrArray(manifest, "implementedSlices")
  let notYet = jsonStrArray(manifest, "notYetImplementedSlices")
  let pin = jsonStr(manifest, "productionExecutionPin")
  let mode = jsonStr(manifest, "mode")
  if ciEpochId.len == 0:
    result.add("manifest ciEpochId missing/empty")
  if pin.len == 0:
    result.add("manifest productionExecutionPin missing/empty")
  elif not (pin.len == 40 and pin.allCharsInSet({'0' .. '9', 'a' .. 'f'})):
    result.add("manifest productionExecutionPin not a 40-hex OID: '" & pin & "'")
  if mode notin ValidModes:
    result.add("manifest mode invalid: '" & mode & "' (expected ci-migration|normal)")

  # ── catalog self-invariants ──
  result.add(catalogIdsUniquenessFailures())
  let allIds = sortedCatalogIds()

  # ── coverage: implemented ∪ notYet == catalog, disjoint, all known ──
  let implSet = implemented.toHashSet()
  let notYetSet = notYet.toHashSet()
  for x in implemented:
    if x notin allIds:
      result.add("manifest implementedSlices unknown slice id: " & x)
  for x in notYet:
    if x notin allIds:
      result.add("manifest notYetImplementedSlices unknown slice id: " & x)
  for x in implSet * notYetSet:
    result.add("slice in BOTH implementedSlices and notYetImplementedSlices: " & x)
  let covered = (implSet + notYetSet)
  for x in allIds:
    if x notin covered:
      result.add("slice in NEITHER list (catalog coverage gap): " & x)

  # ── 3-way equality: catalog ↔ manifest ↔ engine firing ──
  let catalogImpl = catalogImplementedIds()
  let diffCM = symmetricDiff(catalogImpl, implemented)
  for d in diffCM:
    result.add("catalog↔manifest implemented mismatch (" & d & ") — " &
               ReasonInconsistent)

  var firingSet: seq[string]
  for s in SliceCatalog:
    if not s.implemented:
      continue
    let (found, evidence) = engineFires(s, headRoot)
    if not found:
      result.add("implemented slice " & s.id & " has NO firing step in engine files (" &
                 s.engineFiles.join(",") & ") — manifest↔engine gap: " &
                 ReasonInconsistent)
    else:
      firingSet.add(s.id & "@" & evidence)
  firingSet.sort()
  # engine firing set == implemented set (양방향 등식 — the gate's third set).
  let firingIds = firingSet.mapIt(it.split("@")[0]).sorted()
  # firingIds ⊆ implementation; equality holds iff every implemented slice
  # fired above. Report the symmetric difference explicitly for the audit:
  let diffMF = symmetricDiff(implemented, firingIds)
  for d in diffMF:
    result.add("manifest↔engine firing mismatch (" & d & ") — " &
               ReasonInconsistent)

# ═══════════════════════════════════════════════════════════════════════════
# Layer 3 — productionExecutionPin ↔ pin record (base consistency @base +
#           new-state 3-way consistency @HEAD — each leg at its OWN revision)
# ═══════════════════════════════════════════════════════════════════════════

proc pinRecordAt(oid: string): tuple[twsPin: string, blobSha: string,
                                     fails: seq[string]] {.axiomEffect: IoEffect.} =
  ## TWS pin record (trustedAdmissionWorkflowSha) at git revision `oid`,
  ## plus the content-addressed git blob sha of admission-check.yml at the
  ## SAME revision (the ADR-0022 §5 ATOMICITY pair). fail-closed: unreadable
  ## / unparsable / missing field / unresolvable blob → failures (+ empty
  ## pin when the record itself is unavailable).
  let (twsBytes, twsCode) = gitShowFile(oid, ProductionPinRecordPath)
  if twsCode != 0:
    return ("", "", @["pin record unreadable (" & ProductionPinRecordPath &
                      " @ " & oid & ") — cannot interpret productionExecutionPin " &
                      "(fail-closed)"])
  var tws: JsonNode
  try:
    tws = parseJson(stripJsonc(twsBytes))
  except CatchableError:
    return ("", "", @["pin record unparsable: " & ProductionPinRecordPath &
                      " @ " & oid])
  let twsPin = jsonStr(tws, ProductionPinRecordField)
  if twsPin.len == 0:
    return ("", "", @["pin record missing field '" & ProductionPinRecordField &
                      "' @" & oid])
  let (blobRaw, blobCode) = gitBlobSha(oid, EngineMappingDir & "/admission-check.yml")
  if blobCode != 0:
    return (twsPin, "", @["cannot resolve git blob sha of " & EngineMappingDir &
                          "/admission-check.yml @" & oid & " (fail-closed)"])
  result = (twsPin, blobRaw.strip(), @[])

proc pinFailures(manifest: JsonNode, baseOid, headOid: string): seq[string] {.axiomEffect: IoEffect.} =
  ## Layer 3 — TWO independent consistency legs, each judged at its own
  ## revision. A legitimate transaction MUST advance the pin record and the
  ## engine blob in the same commit (TWS atomic pair + 4-way atomicity), so
  ## HEAD pin != base pin BY CONSTRUCTION — judging the HEAD pin against the
  ## base record (the measured S0-c defect) rejected the only legal
  ## transaction in --diff mode while static mode passed it. Both modes now
  ## demand the same 3-party equality at HEAD; --diff additionally verifies
  ## base consistency at base.
  ##   base leg (baseOid != "") — TWS pin record == git blob sha of
  ##     admission-check.yml @base: "the base binding was not broken"
  ##     (original meaning, preserved at the original revision). base =
  ##     origin/main is always gate-consistent → any base drift FAILS
  ##     (fail-closed; no introduction exemption — a missing/unreadable base
  ##     record is a failure too).
  ##   head leg — manifest.productionExecutionPin (working tree = head
  ##     checkout) == TWS @head == blob @head (3-way): "the new state this
  ##     PR ships is self-consistent" — the same 3-party equality the static
  ##     mode enforces (the PR-time projection of the mint's run-time step-2a
  ##     TWS@B check, verified at the revision the commit ships).
  ## Static mode: baseOid = "" → base leg skipped; headOid = "HEAD".
  let manifestPin = jsonStr(manifest, "productionExecutionPin")
  if baseOid.len > 0:
    let (bTws, bBlob, bFails) = pinRecordAt(baseOid)
    result.add(bFails)
    if bFails.len == 0 and bTws != bBlob:
      result.add("base-state engine↔pin gap: git blob sha(" & EngineMappingDir &
                 "/admission-check.yml)='" & bBlob & "' != TWS '" & bTws &
                 "' @ " & baseOid & " (base binding broken — TWS ATOMICITY " &
                 "violated): " & ReasonInconsistent)
  let (hTws, hBlob, hFails) = pinRecordAt(headOid)
  result.add(hFails)
  if hFails.len == 0:
    if manifestPin != hTws:
      result.add("pin mismatch: manifest.productionExecutionPin='" & manifestPin &
                 "' != HEAD TWS " & ProductionPinRecordField & "='" & hTws &
                 "' (manifest↔pin gap): " & ReasonInconsistent)
    if hTws != hBlob:
      result.add("engine↔pin gap: git blob sha(" & EngineMappingDir &
                 "/admission-check.yml)='" & hBlob & "' != TWS '" & hTws &
                 "' @ " & headOid & " (TWS ATOMICITY violated): " &
                 ReasonInconsistent)

# ═══════════════════════════════════════════════════════════════════════════
# Layer 1 — diff: 4-way atomicity at PR time
# ═══════════════════════════════════════════════════════════════════════════

proc changedPaths(base, head: string): tuple[paths: HashSet[string], code: int] {.axiomEffect: IoEffect.} =
  ## `git diff --name-status <base> <head>` → changed path set (renames count
  ## both sides). code != 0 → usage/env error (fail-closed).
  let (outp, code) = execGit("diff --name-status " & base & " " & head)
  if code != 0:
    return (result.paths, code)
  for line in outp.splitLines():
    if line.strip().len == 0:
      continue
    let parts = line.split('\t')
    if parts.len < 2:
      continue
    for i in 1 ..< parts.len:
      result.paths.incl(parts[i])
  result.code = 0

proc manifestFieldState(base, head: string): tuple[sliceFieldsChanged,
                                                     pinFieldChanged: bool] {.axiomEffect: IoEffect.} =
  ## Field-level classification of an epoch manifest change between base and
  ## head git OIDs: which binding FIELDS actually differ? A manifest edit may
  ## touch the slice fields (G1) or the pin field (G2) — or neither (schema
  ## bookkeeping such as ciEpochId/mode, which layers 2/3 still schema-check).
  ## Fail-closed: unreadable or unparsable manifest at either revision → both
  ## fields reported changed (the strictest classification — every pairing
  ## requirement then applies and the partial-update judgment fails).
  let (bBytes, bCode) = gitShowFile(base, EpochManifestPath)
  let (hBytes, hCode) = gitShowFile(head, EpochManifestPath)
  if bCode != 0 or hCode != 0:
    return (true, true)
  var bN, hN: JsonNode
  try:
    bN = parseJson(bBytes)
    hN = parseJson(hBytes)
  except CatchableError:
    return (true, true)
  if bN == nil or hN == nil or bN.kind != JObject or hN.kind != JObject:
    return (true, true)
  result.sliceFieldsChanged =
    jsonStrArray(bN, "implementedSlices") != jsonStrArray(hN, "implementedSlices") or
    jsonStrArray(bN, "notYetImplementedSlices") != jsonStrArray(hN, "notYetImplementedSlices")
  result.pinFieldChanged = jsonStr(bN, "productionExecutionPin") != jsonStr(hN, "productionExecutionPin")

proc twsFieldSnapshot(oid: string): tuple[pin, closure: string, ok: bool] {.axiomEffect: IoEffect.} =
  ## Canonical TWS field snapshots at a git revision: the pin VALUE
  ## (trustedAdmissionWorkflowSha) and the closure identity (sorted
  ## "mode sha path" lines of trustedCheckerTreeClosure — the same member
  ## identity the derived closure carries). ok=false → fail-closed.
  let (twsBytes, twsCode) = gitShowFile(oid, ProductionPinRecordPath)
  if twsCode != 0:
    return
  var tws: JsonNode
  try:
    tws = parseJson(stripJsonc(twsBytes))
  except CatchableError:
    return
  if tws == nil or tws.kind != JObject:
    return
  result.pin = jsonStr(tws, ProductionPinRecordField)
  let cl = tws{"trustedCheckerTreeClosure"}
  if cl == nil or cl.kind != JObject:
    return
  var lines: seq[string]
  for path, entry in cl:
    if entry == nil or entry.kind != JObject:
      return
    let mode = jsonStr(entry, "mode")
    let sha = jsonStr(entry, "sha")
    if mode.len == 0 or sha.len == 0:
      return
    lines.add(mode & " " & sha & " " & path)
  lines.sort()
  result.closure = lines.join("\n")
  result.ok = true

proc twsFieldState(base, head: string): tuple[pinValueChanged,
                                              closureChanged: bool] {.axiomEffect: IoEffect.} =
  ## Field-level classification of a TWS change between base and head git
  ## OIDs — the manifestFieldState principle applied to the pin record's
  ## TWO independently-bound fields (see header "TWS field split"). A
  ## trustedCheckerTreeClosure re-anchor with the pin VALUE unchanged is a
  ## closure re-anchor, not a pin change. Fail-closed: unreadable,
  ## unparsable, or schema-incomplete TWS at either revision → BOTH fields
  ## reported changed (the strictest classification — every pairing
  ## requirement then applies and the partial-update judgment fails).
  let b = twsFieldSnapshot(base)
  let h = twsFieldSnapshot(head)
  if not b.ok or not h.ok:
    return (true, true)
  result = (b.pin != h.pin, b.closure != h.closure)

proc engineFileClaimedByPromotion(engineFile, base, head: string): bool {.axiomEffect: IoEffect.} =
  ## G2b — is a NON-pinned engine mapping change claimed by a slice promotion
  ## inside the same PR? Promotion = the manifest's implementedSlices GAINS at
  ## least one slice whose catalog engineFiles contain the changed file (the
  ## catalog implemented false→true pairing itself is enforced by G1).
  ## Reads both manifests as git OIDs (deterministic); the engineFiles come
  ## from the compiled SliceCatalog (head revision — the gate is built from
  ## the head checkout). Unreadable/unparsable manifest = fail-closed (false).
  let (bBytes, bCode) = gitShowFile(base, EpochManifestPath)
  let (hBytes, hCode) = gitShowFile(head, EpochManifestPath)
  if bCode != 0 or hCode != 0:
    return false
  var bN, hN: JsonNode
  try:
    bN = parseJson(bBytes)
    hN = parseJson(hBytes)
  except CatchableError:
    return false
  if bN == nil or hN == nil or bN.kind != JObject or hN.kind != JObject:
    return false
  let baseImpl = jsonStrArray(bN, "implementedSlices")
  let headImpl = jsonStrArray(hN, "implementedSlices")
  for id in headImpl:
    if id in baseImpl:
      continue
    for s in SliceCatalog:
      if s.id == id and engineFile in s.engineFiles:
        return true
  false

func jobScopeCondsIn(line: string): int =
  ## Occurrences of a JOB-LEVEL scope gate reference
  ## (`needs.<job>.outputs.scope_`) inside one line.
  ##
  ## Why this counter exists (2026-10-20): the step-level counter
  ## (`steps.slice-engine.outputs.scope_`) is blind to job-level scope gates.
  ## In runner-pool-acceptance.yml the SL-09 lane gates are job-level
  ## (`needs.<job>.outputs.scope_sl09`), so a repair could DROP such a
  ## conjunct (or replace it with an always-true expression) and the
  ## step-level surface would stay unchanged — the ratchet would stay green
  ## while the gate silently disappeared. The job-level surface is the
  ## dominant one (6 job-level gates vs 5 step-level conditions in that
  ## engine), so it is counted explicitly.
  ##
  ## Only `if:` lines are counted: a *consumer* of a scope output (e.g. an
  ## env binding in an aggregate job) is not a gate, and counting it would
  ## make the counter fail on a legitimate consumer removal (false positive
  ## on non-weakening refactors).
  var i = 0
  while true:
    let idx = line.find("needs.", i)
    if idx < 0:
      return result
    let restStart = idx + "needs.".len
    let dot = line.find(".", restStart)
    if dot < 0:
      return result
    if dot + 1 < line.len and line[dot + 1 .. ^1].startsWith("outputs.scope_"):
      inc result
    i = restStart

func scopeGateCounts(fileBytes: string): tuple[scopeConds: int, engineSteps: int, jobScopeConds: int] {.raises: [].} =
  ## Path-2 condition (b): the `scope_` gate surface of a non-pinned engine
  ## file. scopeConds = occurrences of `steps.slice-engine.outputs.scope_`
  ## (the gate-consuming `if:` conditions); engineSteps = occurrences of the
  ## `[slice-engine]` step declarations; jobScopeConds = occurrences of
  ## JOB-LEVEL scope gate references (`needs.<job>.outputs.scope_`) on `if:`
  ## lines. Deterministic, comment-proof (step-name lines + gate-consumption
  ## lines only).
  for line in fileBytes.splitLines():
    if line.contains("steps.slice-engine.outputs.scope_"):
      inc result.scopeConds
    if line.strip().startsWith("- name:") and line.contains("[slice-engine]"):
      inc result.engineSteps
    if line.strip().startsWith("if:"):
      result.jobScopeConds += jobScopeCondsIn(line)

proc engineRepairScopeCounts(engineFile, base, head: string): tuple[ok: bool, detail: string] {.axiomEffect: IoEffect.} =
  ## Path-2 condition (b) — mechanical non-decreasing check over the changed
  ## non-pinned engine file at both revisions (git OIDs, deterministic).
  ## A repair must never shrink the gate surface (gate removal/weakening is
  ## blocked); unreadable file at either revision = fail-closed.
  let (bBytes, bCode) = gitShowFile(base, EngineMappingDir / engineFile)
  let (hBytes, hCode) = gitShowFile(head, EngineMappingDir / engineFile)
  if bCode != 0 or hCode != 0:
    return (false, engineFile & " unreadable at base/head (fail-closed)")
  let b = scopeGateCounts(bBytes)
  let h = scopeGateCounts(hBytes)
  if h.scopeConds < b.scopeConds or h.engineSteps < b.engineSteps or
     h.jobScopeConds < b.jobScopeConds:
    return (false, engineFile & " scope-gate surface DECREASED (scope_conds " &
      $b.scopeConds & "→" & $h.scopeConds & ", [slice-engine] steps " &
      $b.engineSteps & "→" & $h.engineSteps & ", job-level scope_conds " &
      $b.jobScopeConds & "→" & $h.jobScopeConds & ") — gate removal/weakening blocked")
  result = (true, engineFile & " scope-gate surface non-decreasing (scope_conds " &
    $b.scopeConds & "→" & $h.scopeConds & ", [slice-engine] steps " &
    $b.engineSteps & "→" & $h.engineSteps & ", job-level scope_conds " &
    $b.jobScopeConds & "→" & $h.jobScopeConds & ")")

proc diffFailures(base, head: string): seq[string] {.axiomEffect: IoEffect.} =
  ## Layer 1. Closure-group rule (see header). G1 = {SliceCatalog, Manifest
  ## slice fields}: a promotion must pair the catalog's implemented flag with
  ## the manifest's epoch-state record in the same commit (layer 2 re-verifies
  ## the same equality at HEAD). G2 = {SliceEngine mapping, pin record,
  ## Manifest pin field}: an engine change must pair the workflow blob with
  ## BOTH pin records in the same commit (TWS atomicity; layer 3 head leg
  ## re-verifies the 3-way equality at HEAD). Partial update inside either
  ## group = EPOCH_TRANSACTION_INCOMPLETE (fail-closed).
  let (changed, code) = changedPaths(base, head)
  if code != 0:
    result.add("git diff --name-status " & base & " " & head &
               " failed (usage/env error)")
    return

  # Introduction exemption: base has no epoch manifest yet → the binding
  # starts at the next commit (registered-ahead 관례). Loud note, no FAIL.
  let (mbManifest, mbCode) = gitShowFile(base, EpochManifestPath)
  if mbCode != 0 or mbManifest.len == 0:
    echo "  NOTE  (diff) base @" & base & " has no " & EpochManifestPath &
         " — introduction transaction (S0-c); 4-way binding enforced from the next epoch commit onward"
    return

  let catalogChanged = (EpochSliceCatalogPath in changed)
  let manifestChanged = (EpochManifestPath in changed)
  var engineChanged = false
  for f in EngineMappingFiles:
    if (EngineMappingDir / f) in changed:
      engineChanged = true
  let pinChanged = (ProductionPinRecordPath in changed)

  # Field-level manifest classification — a manifest edit belongs to G1, G2,
  # or neither depending on WHICH field changed (not on the path alone).
  let (sliceFieldsChanged, pinFieldChanged) =
    if manifestChanged: manifestFieldState(base, head) else: (false, false)

  # Field-level TWS classification — the manifestFieldState principle
  # applied to the pin record: a trustedCheckerTreeClosure re-anchor with
  # the pin VALUE unchanged is NOT a pin change (header "TWS field split").
  let (twsPinValueChanged, twsClosureChanged) =
    if pinChanged: twsFieldState(base, head) else: (false, false)
  let closureReanchor = twsClosureChanged and not twsPinValueChanged

  let sliceStateChanged = catalogChanged or sliceFieldsChanged
  let enginePinChanged = engineChanged or twsPinValueChanged or pinFieldChanged
  if not sliceStateChanged and not enginePinChanged and not closureReanchor:
    echo "  NOTE  (diff) no epoch binding target changed between " & base & " and " & head
    return
  if closureReanchor and not enginePinChanged and not sliceStateChanged:
    echo "  NOTE  (diff) TWS trustedCheckerTreeClosure re-anchor only (pin value " &
         ProductionPinRecordField & " unchanged — not a pin change; layers 2/3 " &
         "verify the record at HEAD, closure content equality is the " &
         "merge-time rotation check's authority)"

  if sliceStateChanged:
    # G1 — promotion must pair the SSOT with its epoch-state record.
    if not catalogChanged:
      result.add("epoch binding partial update: SliceCatalog (" &
                 EpochSliceCatalogPath & ") unchanged while manifest slice " &
                 "fields changed: " & ReasonIncomplete)
    if not sliceFieldsChanged:
      result.add("epoch binding partial update: manifest slice fields unchanged " &
                 "(implementedSlices/notYetImplementedSlices) while SliceCatalog " &
                 "changed: " & ReasonIncomplete)
  if enginePinChanged:
    # G2 — engine/pin closure, split by the pin's binding target (minimal
    # closure-semantics correction — see the header for the measured A/B/C
    # deadlock the split resolves):
    #   G2a — the PINNED engine (admission-check.yml, the pin's blob target):
    #     a change must advance {TWS record path, manifest pin VALUE} in the
    #     same commit (the original rule, preserved verbatim — layer 3 head
    #     leg re-verifies the 3-way equality at HEAD).
    #   G2b — NON-pinned engines (certificate-mint.yml /
    #     runner-pool-acceptance.yml): a change must be claimed by a slice
    #     promotion inside the same PR (manifest gained slice whose catalog
    #     engineFiles contain the file). TWS/pin touch NOT required (no value
    #     binding exists) — engine change outside promotion scope = FAIL.
    if not engineChanged:
      result.add("epoch binding partial update: SliceEngine mapping files unchanged " &
                 "(" & EngineMappingFiles.join(", ") & ") while pin record/manifest " &
                 "pin field changed: " & ReasonIncomplete)
    if (EngineMappingDir / "admission-check.yml") in changed:
      if not pinChanged:
        result.add("epoch binding partial update: productionExecutionPin record (" &
                   ProductionPinRecordPath & ") unchanged while engine mapping " &
                   "changed: " & ReasonIncomplete)
      if not pinFieldChanged:
        result.add("epoch binding partial update: manifest productionExecutionPin " &
                   "unchanged while engine mapping/pin record changed: " & ReasonIncomplete)
    for engineFile in EngineMappingFiles:
      if engineFile == "admission-check.yml":
        continue
      if (EngineMappingDir / engineFile) in changed and
          not engineFileClaimedByPromotion(engineFile, base, head):
        # G2b path 2 (implemented-scope repair — 2026-09-29, epoch N+5 복구
        # B): a NON-promotion engine change is legal iff (i) the epoch
        # DEFINITION is untouched — catalog slice fields · manifest slice
        # fields · TWS · pin all unchanged (an engine edit together with any
        # of those = an attempt to change the epoch definition without
        # promotion → FAIL, unchanged from path 1) — and (ii) the scope-gate
        # surface is non-decreasing (b, mechanical; human declaration (c) is
        # the PR body's implemented-scope statement, judged by reviewers).
        # G2a attribution correction (2026-10-09): when the PINNED engine
        # (admission-check.yml) is itself in this diff, the TWS/pin changes
        # are its MANDATED G2a pairing — a legal rotation carries them by
        # construction (a diff with admission-check.yml and NO pin change
        # already fails G2a above). Counting them here as "epoch definition
        # touched" made {pinned rotation + non-pinned engine change}
        # unsatisfiable within one PR — the same false-negative shape the
        # 2026-09-29 split resolved. Catalog/slice-field changes remain
        # epoch-definition touches (promotion-scope sneaking stays blocked);
        # the engine change itself is still adjudicated by the non-decreasing
        # scope-gate surface below + layers 2/3 at HEAD.
        let pinnedEngineRotated = (EngineMappingDir / "admission-check.yml") in changed
        let epochDefTouched = catalogChanged or sliceFieldsChanged or
                              (pinChanged and not pinnedEngineRotated) or
                              (pinFieldChanged and not pinnedEngineRotated)
        if epochDefTouched:
          result.add("epoch binding partial update: " & engineFile & " changed outside " &
                     "promotion scope — no slice promoted inside this PR (catalog " &
                     "false→true + manifest notYet→implemented) lists " & engineFile &
                     " in its engineFiles, AND the epoch definition (catalog/manifest " &
                     "slice fields/TWS/pin) is touched: " & ReasonIncomplete)
        else:
          let (repairOk, repairDetail) = engineRepairScopeCounts(engineFile, base, head)
          if repairOk:
            echo "  NOTE  (diff) " & engineFile & " changed — implemented-scope repair " &
                 "path 2 (" & repairDetail & "; PR body must declare implemented-scope " &
                 "repair [human check c])"
          else:
            result.add("epoch binding partial update: " & engineFile & " changed outside " &
                       "promotion scope AND implemented-scope repair path-2 condition " &
                       "failed (" & repairDetail & "): " & ReasonIncomplete)

# ═══════════════════════════════════════════════════════════════════════════
# Runner
# ═══════════════════════════════════════════════════════════════════════════

proc printHelp() =
  echo "epoch_transaction_gate — CI epoch promotion transaction 4-way binding (S0-c)"
  echo ""
  echo "Usage:"
  echo "  epoch_transaction_gate [--diff <base> <head>]"
  echo ""
  echo "  no args             static self-check only (layers 2+3 vs current tree,"
  echo "                      layer 1 not applicable — GATES_FAST / pre-push)"
  echo "  --diff <base> <head>  full 3-layer PR-time judgment (base ="
  echo "                      merge-base(origin/main, HEAD), head = HEAD —"
  echo "                      check-repository-surface pattern)"
  echo ""
  echo "Binding targets (single authority: src/gate/slice_catalog.nim):"
  echo "  SliceCatalog        src/gate/slice_catalog.nim"
  echo "  Epoch Manifest      config/policy/epoch_manifest.json"
  echo "  SliceEngine mapping .github/workflows/{admission-check,certificate-mint,runner-pool-acceptance}.yml"
  echo "  productionExecutionPin record — repo-observable interpretation:"
  echo "                      config/trusted_writer_set.json trustedAdmissionWorkflowSha"
  echo "                      (org-ruleset pin is outside the repo; this is the"
  echo "                      documented repo-side anchor, ADR-0022 §5; --diff"
  echo "                      judges base consistency @base AND new-state"
  echo "                      3-way equality @HEAD — one leg per revision)"
  echo ""
  echo "Exit: 0 = consistent, 1 = incomplete/inconsistent (fail-closed), 2 = usage error."

proc main() {.axiomEffect: IoEffect.} =
  var base = ""
  var head = ""
  var pending = ""
  var p = initOptParser(commandLineParams())
  while true:
    p.next()
    case p.kind
    of cmdEnd:
      break
    of cmdLongOption, cmdShortOption:
      if p.val.len > 0:
        pending = ""
        case p.key
        of "diff":
          base = p.val
        else:
          printHelp()
          quit(2)
      else:
        if p.key notin ["diff"]:
          printHelp()
          quit(2)
        pending = p.key
    of cmdArgument:
      case pending
      of "diff":
        if base.len == 0:
          base = p.key
        else:
          head = p.key
      else:
        printHelp()
        quit(2)
      if base.len > 0 and head.len > 0:
        pending = ""
  if (base.len == 0) != (head.len == 0):
    printHelp()
    quit(2)

  echo ""
  echo "════════════════════════════════════════════════════════════"
  echo "  EPOCH TRANSACTION GATE (SliceCatalog+Manifest+Engine+Pin)"
  echo "════════════════════════════════════════════════════════════"

  var fails: seq[string]
  if base.len > 0:
    echo "  MODE: --diff " & base & " " & head
    fails.add(diffFailures(base, head))
  else:
    echo "  MODE: static self-check (no base for layer 1)"
    echo "  NOTE  (diff) layer 1 skipped — no base OID (run --diff at PR time)"

  # Layers 2+3 evaluate the WORKING TREE (= head checkout). CWD fallback:
  # relative file reads (repo root) keep the gate deterministic even when
  # getCurrentDir fails.
  var headRoot = "."
  try:
    headRoot = getCurrentDir()
  except OSError:
    headRoot = "."
  fails.add(manifestFailures(headRoot))

  # Layer 3 — pin binding (two legs, one per revision). Static mode: no base
  # exists → head leg only (TWS@HEAD == blob@HEAD == manifest pin — the
  # self-consistency the static pre-push / GATES_FAST judgment requires).
  # --diff mode: base leg (TWS@base == blob@base) + the same head leg.
  var manifest: JsonNode
  let (mNode, mOk) = parseJsoncFile(headRoot / EpochManifestPath)
  if mOk:
    manifest = mNode
  else:
    manifest = %*{}
  if base.len == 0:
    echo "  NOTE  (pin) static mode: head leg only — 3-way equality judged @HEAD (current tree)"
    fails.add(pinFailures(manifest, "", "HEAD"))
  else:
    echo "  NOTE  (pin) --diff mode: base leg @base + head leg (3-way) @HEAD"
    fails.add(pinFailures(manifest, base, head))

  if fails.len == 0:
    echo "  PASS  catalog↔manifest↔engine 3-way equality (양방향 등식)"
    echo "  PASS  pin consistency — base leg @base + new-state 3-way equality @HEAD"
    echo ""
    echo "  EXIT 0: epoch promotion transaction binding consistent — fail-closed PASS."
    quit(0)
  echo "  FAIL  " & $fails.len & " epoch transaction violation(s):"
  for f in fails:
    echo "        - " & f
  echo ""
  echo "  EXIT 1: epoch binding incomplete/inconsistent — fail closed."
  quit(1)

when isMainModule:
  main()