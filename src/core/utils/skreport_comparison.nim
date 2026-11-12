import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
{.push noSideEffect.}

## Cross-path skReport reproduction comparison — THE single implementation of
## the §6c verdict rules (docs/spec/productization_contract.md).
##
## Given two rust-lane runs — each an (skReport payload, identity sidecar)
## pair produced by the lane at report-production time ("axiom.skreport-
## identity.v2"), optionally carrying re-measured anchors — this module
## returns the §6c verdict. v2 replaced the v1 caller-declared bundles with
## PRODUCTION-TIME binding: the lane (the declared bundle production
## authority) measures the run's actually-consumed objects and digest-chains
## the pair both ways (payload.identityBundleDigest ↔ sidecar.binding.
## payloadSha256), so a compared pair is self-verifying and mispairing or
## single-artifact tampering fails closed. `measured` (when provided by the
## I/O-boundary consumer) is REFUTATION material: a declared anchor that
## diverges from the re-measured world is not_equal, a re-measurement gap is
## an unknown-note — never a silently-passed claim.
##
##   identity axis  — the production-binding digests must recompute on both
##                    sides (else unknown), the v2 schema must hold (declared
##                    schemaVersion, complete required keys, sha256-shaped
##                    digest fields), the two identity sections (structured
##                    rejection record included) must be deeply equal,
##                    claim.symbol must bind targets[0].name on both sides,
##                    and every provided measured anchor must match its
##                    declaration. A missing key is NOT assumed away: an
##                    absent sidecar is a fail-closed unknown, never equal.
##   structure axis — stripVolatile (the §6 single canonicalizer) on both
##                    payloads, compared field-by-field. Exempted from the
##                    structural comparison: `reason` keys at ANY depth (the
##                    reason axis's jurisdiction — a nested string reason leaf
##                    is the real payload shape) and the ROOT
##                    `identityBundleDigest` key only (identity axis's
##                    jurisdiction — a sidecar gap must not poison structure;
##                    audit F1). Documented §6/R3 boundary: stripVolatile
##                    removes volatile-NAMED keys at arbitrary depth, so a
##                    difference living ONLY under a nested volatile-named key
##                    is outside every axis and compares equal — contract-
##                    mandated, pinned by a gateway fixture, latent for honest
##                    lane payloads. Certified scope is one target and
##                    subjectLane "rust" (anything else → unknown).
##   reason axis    — raw "reason" JString leaves compared verbatim, ALL
##                    differing pairs examined (audit F2: a promoted leaf
##                    never conceals a later difference). A divergence is
##                    promoted to equal ONLY by the §6c v2 rejection rule:
##                    both sides carry a structured rejection record that is
##                    deeply equal, each side's recorded rawPath is really
##                    contained in its own leaf, each leaf minus its own
##                    recorded path hashes to the recorded skeleton digest,
##                    AND the pair sits exactly at the certified rejection
##                    leaf (axiomSkReportRejectionReasonLeaf) on both sides
##                    with both bindings recording that same leaf (audit F3
##                    — position/record incoherence fails the promotion
##                    closed). Anything else stays unknown (the v1 measurement
##                    judgment): embedded run-relative paths cannot be
##                    mechanically separated from a genuine error-class
##                    change without that production-time evidence. A
##                    non-string reason tree is malformed → unknown.
##
## Terminal precedence: not_equal > unknown > equal — there is no default
## equal, and malformed input on any axis (malformed identity, non-v1 or
## non-rust document, non-string reason) is an unknown with a mechanical
## note, never a verdict. Originals are never rewritten: the record echoes
## the identity sections, digests both raw payloads canonically, and
## preserves every raw reason string verbatim. No CLI surface, no exit-code
## coupling (§7 table and the exit contract are untouched); the lane keeps
## sole report AND sidecar production authority. equal remains a CONDITIONAL
## verdict (digest-chained, re-verifiable) — not an unhedged certificate of
## reproduction.

import std/[json, strutils]

import core/crypto/hash_kernel
import core/utils/canonical_projection
import core/utils/constants

type
  SkReportRun* = object
    ## One run's comparison input: the RAW skReport payload, the lane's
    ## produced identity sidecar (nil = absent — an all-or-nothing production
    ## gap), and optionally the re-measured anchors taken at the I/O boundary
    ## when the world is still available (an identity-section-shaped tree of
    ## dotted paths; nil = not re-measured — the recorded production-time
    ## measurement then stands, as with tcRecorded provenance).
    payload*: JsonNode
    sidecar*: JsonNode
    measured*: JsonNode

type
  AxisVerdict = enum
    axEqual
    axNotEqual
    axUnknown

  Comparison = object
    identity: AxisVerdict
    structure: AxisVerdict
    reason: AxisVerdict
    notes: seq[string]

const requiredIdentityPaths* = [
  "subject.commit", "subject.modulePath", "subject.moduleSha256",
  "subject.sourceFingerprint",
  "claim.symbol", "claim.specRef", "claim.postSha256",
  "scope.rustTargetsSha256",
  "toolchain.charon", "toolchain.rustc", "toolchain.cargoLockSha256",
  "toolchain.cargoManifestSha256", "toolchain.nim",
]

const identityDigestPaths* = [
  ## Identity keys whose names declare a sha256 digest. Format is validated:
  ## a bundle claiming a "sha256" that is not a real digest shape is malformed.
  "subject.moduleSha256", "subject.sourceFingerprint", "claim.postSha256",
  "scope.rustTargetsSha256", "toolchain.cargoLockSha256",
  "toolchain.cargoManifestSha256",
]

## identityBindingDigest (the §6c v2 production-binding digest) is defined in
## core/utils/canonical_projection.nim — the canonical-form module both the
## lane and this comparator import; this keeps the lane's dependency inside
## the existing closure while the digest stays a single definition.

func sidecarIdentity*(sidecar: JsonNode): JsonNode {.raises: [].} =
  ## The compared identity section of a sidecar (nil-safe).
  if sidecar.isNil: return nil
  sidecar{"identity"}

func axisName(v: AxisVerdict): string {.raises: [].} =
  case v
  of axEqual: "equal"
  of axNotEqual: "not_equal"
  of axUnknown: "unknown"

func terminal(a, b, c: AxisVerdict): string {.raises: [].} =
  if a == axNotEqual or b == axNotEqual or c == axNotEqual: "not_equal"
  elif a == axUnknown or b == axUnknown or c == axUnknown: "unknown"
  else: "equal"

func nodeAt(n: JsonNode; dotted: string): JsonNode {.raises: [].} =
  ## Nil-safe dotted-path lookup ("subject.commit"). Only the FINAL hop may
  ## resolve to a non-object node; an intermediate hop that is nil or not a
  ## JObject means the path does not exist and yields nil — a flat scalar
  ## under "subject" does NOT satisfy "subject.commit".
  result = n
  var start = 0
  while not result.isNil and result.kind == JObject:
    let dot = dotted.find('.', start)
    let key = (if dot < 0: dotted[start ..< dotted.len]
               else: dotted[start ..< dot])
    result = result{key}
    if dot < 0: break
    if result.isNil or result.kind != JObject:
      return nil
    start = dot + 1

func missingIdentityKeys*(id: JsonNode): seq[string] {.raises: [].} =
  ## The §6c required identity keys absent or empty on `id`.
  result = @[]
  if id.isNil or id.kind != JObject:
    return @requiredIdentityPaths
  for path in requiredIdentityPaths:
    let node = nodeAt(id, path)
    if node.isNil or node.kind != JString or node.getStr().len == 0:
      result.add(path)

func isSha256Hex(s: string): bool {.raises: [].} =
  ## The digest shape this repo actually serializes: exactly 64 lowercase hex
  ## characters (the output shape of core/crypto/hash_kernel.sha256Hex).
  if s.len != 64:
    return false
  for c in s:
    if c notin {'0'..'9', 'a'..'f'}:
      return false
  return true

func identitySchemaViolations*(sidecar: JsonNode): seq[string] {.raises: [].} =
  ## Mechanical "axiom.skreport-identity.v2" schema violations beyond key
  ## presence (missingIdentityKeys covers those): a sidecar schemaVersion
  ## that is absent or not the declared constant, and digest-typed identity
  ## keys whose value is not real sha256 hex. A sidecar that violates the
  ## schema is malformed — its declarations cannot be interpreted, so it
  ## fails closed (unknown), never equal.
  result = @[]
  if sidecar.isNil or sidecar.kind != JObject:
    return
  let v = sidecar{"schemaVersion"}
  if v.isNil or v.kind != JString:
    result.add("schemaVersion: missing or not a string")
  elif v.getStr() != axiomSkReportIdentitySchemaVersion:
    result.add("schemaVersion: '" & v.getStr() & "' is not " &
               axiomSkReportIdentitySchemaVersion)
  let id = sidecar{"identity"}
  if id.isNil or id.kind != JObject:
    return
  for path in identityDigestPaths:
    let node = nodeAt(id, path)
    if not node.isNil and node.kind == JString and
        not isSha256Hex(node.getStr()):
      result.add(path & ": not a 64-char lowercase hex sha256")

func collectReasonLeaves(n: JsonNode; acc: var seq[string]) {.raises: [].} =
  ## Every JString under a "reason" key, document order — the verbatim reason
  ## set the record preserves (charon.reason, targets[i].reason, …).
  if n.isNil: return
  case n.kind
  of JObject:
    for k, v in n.pairs:
      if k == "reason" and v.kind == JString:
        acc.add(v.getStr())
      else:
        collectReasonLeaves(v, acc)
  of JArray:
    for v in n.items:
      collectReasonLeaves(v, acc)
  else:
    discard

func reasonLeaves*(report: JsonNode): JsonNode {.raises: [].} =
  ## The verbatim reason strings of a raw payload, document order.
  var acc: seq[string] = @[]
  collectReasonLeaves(report, acc)
  %acc

func firstNonStringReasonPath(n: JsonNode; path: string): string {.raises: [].} =
  ## The path of the first "reason" key whose value is NOT a JString. The
  ## reason axis covers string leaves only, so a non-string reason tree is
  ## malformed input and must fail closed (unknown) — two DIFFERENT malformed
  ## failure payloads must never compare equal just because the tree shape is
  ## outside every axis's jurisdiction.
  if n.isNil: return ""
  case n.kind
  of JObject:
    for k, v in n.pairs:
      let here = (if path.len == 0: k else: path & "." & k)
      if k == "reason" and v.kind != JString:
        return here
      let sub = firstNonStringReasonPath(v, here)
      if sub.len > 0: return sub
  of JArray:
    for i in 0 ..< n.elems.len:
      let sub = firstNonStringReasonPath(n.elems[i],
                                         path & "[" & $i & "]")
      if sub.len > 0: return sub
  else:
    discard
  return ""

func structuralDiff(a, b: JsonNode; path: string; notes: var seq[string]): bool {.
    raises: [].} =
  ## True on the first structural (non-reason) difference. `path` is the
  ## dotted location of `a`/`b` inside the payload ("$" = document root).
  ## Reason keys are the reason axis's jurisdiction at ANY depth (a string
  ## reason leaf may legitimately be nested, e.g. targets[0].reason; a
  ## non-string reason tree is the reason axis's malformed case). The root
  ## `identityBundleDigest` binding key is the identity axis's jurisdiction —
  ## exempt ONLY at the root (audit F1): a same-named key at any other depth
  ## is ordinary payload content and must be compared like any other field,
  ## never silently exempted.
  if a.isNil or b.isNil:
    notes.add("structural: nil node at " & path)
    return true
  if a.kind != b.kind:
    notes.add("structural: kind differs at " & path)
    return true
  case a.kind
  of JObject:
    let root = path == "$"
    for k, v in a.pairs:
      if k == "reason": continue
      if root and k == "identityBundleDigest": continue
      if b{k}.isNil:
        notes.add("structural: key missing on right at " & path & "." & k)
        return true
      if structuralDiff(v, b{k}, path & "." & k, notes):
        return true
    for k, v in b.pairs:
      if k == "reason": continue
      if root and k == "identityBundleDigest": continue
      if a{k}.isNil:
        notes.add("structural: key missing on left at " & path & "." & k)
        return true
  of JArray:
    if a.elems.len != b.elems.len:
      notes.add("structural: array length " & $a.elems.len & " vs " &
                $b.elems.len & " at " & path)
      return true
    for i in 0 ..< a.elems.len:
      if structuralDiff(a.elems[i], b.elems[i], path & "[" & $i & "]", notes):
        return true
  else:
    if $a != $b:
      notes.add("structural: value differs at " & path)
      return true

func firstDifferingSection(leftId, rightId: JsonNode): string {.raises: [].} =
  ## The first top-level identity section whose canonical forms differ — the
  ## mechanical not_equal note names it so the failing control is auditable.
  if leftId.isNil or leftId.kind != JObject or rightId.isNil or
      rightId.kind != JObject:
    return "<bundle>"
  for k, v in leftId.pairs:
    if rightId{k}.isNil or sortedCanonicalJson(v) != sortedCanonicalJson(rightId{k}):
      return k
  for k, v in rightId.pairs:
    if leftId{k}.isNil:
      return k
  "<bundle>"

func payloadDigest(report: JsonNode): string {.raises: [].} =
  ## Canonical fingerprint of the RAW payload (the original-preservation
  ## reference in the record). Volatile keys are NOT stripped here — the
  ## stripped comparison is the structure axis's business.
  if report.isNil or report.kind != JObject:
    return ""
  sha256Hex(sortedCanonicalJson(report))

func claimBindsTarget(report, identity: JsonNode): bool {.raises: [].} =
  let symbol = nodeAt(identity, "claim.symbol")
  if symbol.isNil or symbol.kind != JString: return false
  if report.isNil or report.kind != JObject: return false
  let targets = report{"targets"}
  if targets.isNil or targets.kind != JArray or targets.elems.len < 1:
    return false
  let name = targets.elems[0]{"name"}
  not name.isNil and name.kind == JString and name.getStr() == symbol.getStr()

func measuredDivergences(measured, identity: JsonNode): seq[string] {.raises: [].} =
  ## The provided re-measured anchors that do not match (or cannot find)
  ## their declared identity path — mechanical refutation evidence taken at
  ## the I/O boundary. Two-level walk (section.key), the identity-section
  ## shape; compared by canonical form so numeric and string values both work.
  result = @[]
  if measured.isNil or measured.kind != JObject: return
  if identity.isNil or identity.kind != JObject:
    result.add("measured anchors provided but the identity section is absent")
    return
  for secKey, sec in measured.pairs:
    if sec.isNil or sec.kind != JObject: continue
    for k, v in sec.pairs:
      let path = secKey & "." & k
      let declared = nodeAt(identity, path)
      if declared.isNil:
        result.add(path & ": measured but not declared")
      elif sortedCanonicalJson(declared) != sortedCanonicalJson(v):
        result.add(path & ": declared != re-measured")

func measuredAnchorCount(measured: JsonNode): int {.raises: [].} =
  ## The number of re-measured anchor leaves (section.key pairs) — the count
  ## the equal-confirmation note cites for auditability.
  result = 0
  if measured.isNil or measured.kind != JObject: return
  for secKey, sec in measured.pairs:
    if sec.isNil or sec.kind != JObject: continue
    result += sec.len

func skeletonShaOf(leaf, rawPath: string): string {.raises: [].} =
  ## The §6c v2 rejection skeleton digest: the leaf with ITS recorded
  ## offending path replaced by the shared marker. Not a general normalizer —
  ## the substituted span is the producer-recorded path of this very leaf.
  if rawPath.len == 0 or leaf.len == 0: return ""
  sha256Hex(leaf.replace(rawPath, axiomSkReportSkeletonMarker))

func rejectionPromotionHolds(left, right: SkReportRun;
                             leftLeaf, rightLeaf: string): bool {.raises: [].} =
  ## The §6c v2 reason promotion: a differing leaf pair may be called equal
  ## ONLY when both sides carry a structured rejection record whose logical
  ## identity (rule/index/crate/content/skeleton) is deeply equal, each
  ## side's recorded rawPath is really contained in its own leaf, and each
  ## leaf minus its own recorded path hashes to the recorded skeleton digest
  ## — i.e. the production-time evidence proves the ONLY difference is the
  ## recorded offending path of the same logical rejection. Anything else is
  ## no promotion (the v1 measurement judgment stands: unknown).
  for pair in [(left, leftLeaf), (right, rightLeaf)]:
    let (run, leaf) = pair
    let sidecar = run.sidecar
    if sidecar.isNil or sidecar.kind != JObject: return false
    let rec = sidecar{"identity"}{"rejection"}
    let bindRec = sidecar{"binding"}{"rejection"}
    if rec.isNil or rec.kind != JObject or bindRec.isNil or
        bindRec.kind != JObject:
      return false
    let rawPath = bindRec{"rawPath"}
    if rawPath.isNil or rawPath.kind != JString or rawPath.getStr().len == 0:
      return false
    if not leaf.contains(rawPath.getStr()):
      return false
    let recorded = rec{"skeletonSha256"}
    if recorded.isNil or recorded.kind != JString or
        not isSha256Hex(recorded.getStr()):
      return false
    if skeletonShaOf(leaf, rawPath.getStr()) != recorded.getStr():
      return false
  sortedCanonicalJson(left.sidecar{"identity"}{"rejection"}) ==
    sortedCanonicalJson(right.sidecar{"identity"}{"rejection"})

func walkReasonLeaves(n: JsonNode; path: string; target: int;
                      idx: int): tuple[path: string; next: int] {.raises: [].} =
  ## Document-order walk over the string reason leaves; returns the path of
  ## the `target`-th leaf ("" = absent) and the running leaf counter.
  result = ("", idx)
  if n.isNil: return
  case n.kind
  of JObject:
    for k, v in n.pairs:
      if result.path.len > 0: return
      let here = (if path.len == 0: k else: path & "." & k)
      if k == "reason" and v.kind == JString:
        if result.next == target:
          result.path = here
          return
        inc result.next
      else:
        let sub = walkReasonLeaves(v, here, target, result.next)
        if sub.path.len > 0:
          return sub
        result.next = sub.next
  of JArray:
    for i in 0 ..< n.elems.len:
      if result.path.len > 0: return
      let sub = walkReasonLeaves(n.elems[i], path & "[" & $i & "]",
                                 target, result.next)
      if sub.path.len > 0:
        return sub
      result.next = sub.next
  else:
    discard

func reasonLeafPathAt(report: JsonNode; target: int): string {.raises: [].} =
  ## The document-order path of the `target`-th string reason leaf, in the
  ## binding's recorded grammar ("targets[0].reason"); "" when that leaf does
  ## not exist. The comparison and the lane's reasonLeaf record speak ONE
  ## path grammar, so a promotion can bind the pair to its recorded position.
  walkReasonLeaves(report, "", target, 0).path

func reasonLeafBindingHolds(left, right: SkReportRun;
                            leftPath, rightPath: string): bool {.raises: [].} =
  ## The promotion position precondition (audit F3; contract §6c rule 3 "그
  ## 잎 쌍이 양측 targets[0].reason이고"): the promoted pair must sit at the
  ## certified rejection leaf on BOTH sides, and each side's binding must
  ## record exactly that leaf — an absent, empty, bogus, side-divergent, or
  ## position-incoherent record refuses the promotion (fail closed).
  if leftPath != axiomSkReportRejectionReasonLeaf or
      rightPath != axiomSkReportRejectionReasonLeaf:
    return false
  for run in [left, right]:
    let rl = run.sidecar{"binding"}{"rejection"}{"reasonLeaf"}
    if rl.isNil or rl.kind != JString or
        rl.getStr() != axiomSkReportRejectionReasonLeaf:
      return false
  true

func compareSkReports*(left, right: SkReportRun): JsonNode {.raises: [].} =
  ## §6c verdict record ("axiom.skreport-comparison.v2"). Pure; no I/O; no
  ## default-equal. The record embeds both identity sections, digests of both
  ## raw payloads, and every raw reason string verbatim (originals are never
  ## rewritten — the caller preserves the payload artifacts themselves).
  let leftReport = left.payload
  let rightReport = right.payload
  let leftIdentity = sidecarIdentity(left.sidecar)
  let rightIdentity = sidecarIdentity(right.sidecar)
  var c = Comparison(identity: axEqual, structure: axEqual, reason: axEqual)

  # ── identity axis ──────────────────────────────────────────────────────
  let missingLeft = missingIdentityKeys(leftIdentity)
  let missingRight = missingIdentityKeys(rightIdentity)
  let schemaLeft = identitySchemaViolations(left.sidecar)
  let schemaRight = identitySchemaViolations(right.sidecar)
  if left.sidecar.isNil or right.sidecar.isNil:
    c.identity = axUnknown
    c.notes.add("identity: sidecar absent (" &
                (if left.sidecar.isNil: "left" else: "") &
                (if left.sidecar.isNil and right.sidecar.isNil: "+" else: "") &
                (if right.sidecar.isNil: "right" else: "") &
                ") — an all-or-nothing production gap is fail-closed, never equal")
  # production-binding digests (mechanical recompute — no caller flags)
  for pair in [("left", left), ("right", right)]:
    let (side, run) = pair
    if run.sidecar.isNil or run.sidecar.kind != JObject: continue
    let embedded = run.payload{"identityBundleDigest"}
    if embedded.isNil or embedded.kind != JString:
      c.identity = axUnknown
      c.notes.add("identity: " & side &
                  " payload carries no identityBundleDigest key — the " &
                  "production-time binding is missing")
    elif embedded.getStr() != identityBindingDigest(run.sidecar):
      c.identity = axUnknown
      c.notes.add("identity: " & side &
                  " payload identityBundleDigest does not recompute from " &
                  "its sidecar — the pair is not the produced binding")
    let bound = run.sidecar{"binding"}{"payloadSha256"}
    if bound.isNil or bound.kind != JString:
      c.identity = axUnknown
      c.notes.add("identity: " & side &
                  " sidecar carries no binding.payloadSha256 — the " &
                  "production-time binding is missing")
    elif bound.getStr() != sha256Hex(sortedCanonicalJson(run.payload)):
      c.identity = axUnknown
      c.notes.add("identity: " & side &
                  " sidecar binding.payloadSha256 does not recompute from " &
                  "its payload — the pair is not the produced binding")
  if missingLeft.len > 0 or missingRight.len > 0 or
      schemaLeft.len > 0 or schemaRight.len > 0:
    c.identity = axUnknown
    c.notes.add("identity: required keys missing (left=[" &
                missingLeft.join(", ") & "] right=[" &
                missingRight.join(", ") & "]) — inputs are not assumed to carry identity")
    for v in schemaLeft:
      c.notes.add("identity: left sidecar schema violation — " & v)
    for v in schemaRight:
      c.notes.add("identity: right sidecar schema violation — " & v)
  else:
    # re-measured anchors: refutation evidence when provided
    for pair in [("left", left), ("right", right)]:
      let (side, run) = pair
      let divergences = measuredDivergences(run.measured,
                                            sidecarIdentity(run.sidecar))
      for d in divergences:
        if d.endsWith("measured but not declared"):
          c.identity = axUnknown
        else:
          c.identity = axNotEqual
        c.notes.add("identity: " & side & " re-measurement — " & d)
      if not run.measured.isNil and run.measured.kind == JObject and
          divergences.len == 0:
        c.notes.add("identity: " & side & " re-measurement — all " &
                    $measuredAnchorCount(run.measured) &
                    " anchors match the recorded declarations")
    if c.identity == axEqual:
      if sortedCanonicalJson(leftIdentity) != sortedCanonicalJson(rightIdentity):
        c.identity = axNotEqual
        c.notes.add("identity: bundle section '" &
                    firstDifferingSection(leftIdentity, rightIdentity) &
                    "' differs")
      else:
        for pair in [("left", leftReport, leftIdentity),
                     ("right", rightReport, rightIdentity)]:
          let (side, report, identity) = pair
          if not claimBindsTarget(report, identity):
            c.identity = axUnknown
            c.notes.add("identity: claim.symbol '" &
                        nodeAt(identity, "claim.symbol").getStr() &
                        "' does not bind targets[0].name on " & side)

  # ── structure axis ─────────────────────────────────────────────────────
  var schemaOk = true
  for pair in [("left", leftReport), ("right", rightReport)]:
    let (side, report) = pair
    var docMalformed = false
    let version = (if report.isNil: JsonNode(nil) else: report{schemaVersionKey})
    if report.isNil or report.kind != JObject or version.isNil or
        version.kind != JString or version.getStr() != axiomReportSchemaVersion:
      c.structure = axUnknown
      c.notes.add("structure: " & side & " payload is not an " &
                  axiomReportSchemaVersion & " document")
      docMalformed = true
    let lane = (if report.isNil: JsonNode(nil) else: report{"subjectLane"})
    if lane.isNil or lane.kind != JString or lane.getStr() != "rust":
      c.structure = axUnknown
      c.notes.add("structure: " & side & " subjectLane is not \"rust\" — " &
                  "outside the §6c certified scope")
      docMalformed = true
    if docMalformed:
      schemaOk = false
  if schemaOk:
    for pair in [("left", leftReport), ("right", rightReport)]:
      let (side, report) = pair
      let targets = report{"targets"}
      let n = (if targets.isNil or targets.kind != JArray: -1
               else: targets.elems.len)
      if n != 1:
        c.structure = axUnknown
        c.notes.add("structure: " & side & " targets length " & $n &
                    " — outside the single-target certified scope (§6c)")
    if c.structure == axEqual:
      var notes: seq[string] = @[]
      if structuralDiff(stripVolatile(leftReport), stripVolatile(rightReport),
                        "$", notes):
        c.structure = axNotEqual
        for n in notes:
          c.notes.add(n)

  # ── reason axis (verbatim, on the RAW payloads) ────────────────────────
  if c.structure != axNotEqual:
    for pair in [("left", leftReport), ("right", rightReport)]:
      let (side, report) = pair
      let malformed = firstNonStringReasonPath(report, "")
      if malformed.len > 0:
        c.reason = axUnknown
        c.notes.add("reason: " & side & " has a non-string reason value at " &
                    malformed & " — the reason axis covers string leaves " &
                    "only; malformed input fails closed")
    if c.reason == axEqual:
      let leftReasons = reasonLeaves(leftReport)
      let rightReasons = reasonLeaves(rightReport)
      if leftReasons.elems.len != rightReasons.elems.len:
        c.reason = axUnknown
        c.notes.add("reason: leaf count differs (" & $leftReasons.elems.len &
                    " vs " & $rightReasons.elems.len & ")")
      else:
        # audit F2: EVERY differing pair is examined — a promoted leaf never
        # conceals what comes after it.
        var unpromoted = 0
        for i in 0 ..< leftReasons.elems.len:
          let l = leftReasons.elems[i].getStr()
          let r = rightReasons.elems[i].getStr()
          if l == r: continue
          let leftPath = reasonLeafPathAt(leftReport, i)
          let rightPath = reasonLeafPathAt(rightReport, i)
          if rejectionPromotionHolds(left, right, l, r) and
              reasonLeafBindingHolds(left, right, leftPath, rightPath):
            c.notes.add("reason: leaf[" & $i & "] at " & leftPath &
                        " differs only by the producer-recorded offending " &
                        "path (pair bound to the recorded rejection leaf, " &
                        "skeleton digests match, structured rejection " &
                        "identity equal) — promoted to equal by the §6c v2 " &
                        "rejection rule; both raw reasons preserved below")
          else:
            inc unpromoted
            c.notes.add("reason: leaf[" & $i & "] (" & leftPath & " vs " &
                        rightPath & ") differs — no production-time " &
                        "rejection evidence at the recorded leaf position " &
                        "separates run-relative displacement from an " &
                        "error-class change; preserved verbatim in the record")
        if unpromoted > 0:
          c.reason = axUnknown

  # ── the record ─────────────────────────────────────────────────────────
  func embeddedDigest(report: JsonNode): JsonNode {.raises: [].} =
    let n = (if report.isNil: JsonNode(nil) else: report{"identityBundleDigest"})
    (if n.isNil: newJNull() else: n.copy())
  result = %*{
    "schemaVersion": %axiomSkReportComparisonSchemaVersion,
    "verdict": %terminal(c.identity, c.structure, c.reason),
    "axes": %*{
      "identity": %axisName(c.identity),
      "structure": %axisName(c.structure),
      "reason": %axisName(c.reason),
    },
    "left": %*{
      "payloadDigest": %payloadDigest(leftReport),
      "identityBundleDigest": embeddedDigest(leftReport),
      "identity": %(if leftIdentity.isNil: newJNull() else: leftIdentity.copy()),
    },
    "right": %*{
      "payloadDigest": %payloadDigest(rightReport),
      "identityBundleDigest": embeddedDigest(rightReport),
      "identity": %(if rightIdentity.isNil: newJNull() else: rightIdentity.copy()),
    },
    "reasons": %*{
      "left": %reasonLeaves(leftReport),
      "right": %reasonLeaves(rightReport),
    },
    "notes": %c.notes,
  }

{.pop.}
{.pop.}
