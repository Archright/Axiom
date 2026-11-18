import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## Rotation/closure pin facts — pure predicates over deriver-format line-sets.
##
## SSOT for the pin/closure parsing primitives and the ④ new-anchor (H2)
## judgment shared by the merge-admission controller (`ax merge`,
## src/cli/merge_cli.nim — annotateNewAnchor fact annotation + the Pass 2.75
## deny) and the rotation preflight checker
## (tools/ci/rotation_pin_anchor_check.nim). ONE compiled implementation —
## the PR-head H2 judgment and the landing predicate cannot drift. Same split
## as change_graph_facts.nim / change_graph_validate.nim: this module owns the
## pure admission facts; each consumer owns its CLI/job surface + fixtures.
##
## Line-set format: `<mode> <type> <sha>\t<path>` (git ls-tree / deriver emit,
## byte-sorted). Pin files are JSON(C) trusted_writer_set documents
## (whole-line and inline `//` comments allowed — see stripJsoncComments).

import std/[algorithm, json, options, sets, strutils]
import core/results
import core/crypto/hash_kernel
import core/trusted/axiom_pragmas_lite

# ---------------------------------------------------------------------------
# Pin identity constants (ADR-0025 §7/§13)
# ---------------------------------------------------------------------------

const
  ## The pin file — the B-side anchor, read relative to the workspace cwd
  ## (the B checkout in the verdict job).
  RotationPinBPath* = "config/trusted_writer_set.json"
  ## The derived closure document (DEBT#558 split): path → {mode,type,sha}
  ## records live OUTSIDE the App-protected writer set. The root key is the
  ## SAME RotationPinKey so every existing line-set consumer keeps working.
  RotationClosurePath* = "config/trusted_checker_closure.json"
  ## Companion basename resolved next to any explicit pin path.
  RotationClosureBasename* = "trusted_checker_closure.json"
  ## trusted_writer_set.json key carrying the closure pin. Absent in the
  ## split layout; present = the legacy single-document layout. Absent with
  ## no pathSetDigest either = the genesis state (ADR-0025 §7 1회).
  RotationPinKey* = "trustedCheckerTreeClosure"
  ## Split-layout discriminator + canonical path-set digest field.
  RotationPathSetDigestKey* = "pathSetDigest"
  ## Domain/version prefix of the canonical path-set digest (the byte
  ## contract is domain "\n" then each path + NUL, byte-sorted).
  RotationPathSetDigestDomain* = "axiom.trusted-checker-closure.path-set.v1"
  ## Standalone closure document schema.
  RotationClosureSchemaVersion* = "axiom.trusted-checker-closure.v1"

# ---------------------------------------------------------------------------
# Nil-safe JSON member access
# ---------------------------------------------------------------------------
# All JsonNode access is nil/kind-guarded so the funcs stay `{.raises: [].}`.

func jv(n: JsonNode; key: string): JsonNode {.raises: [].} =
  ## nil-safe object member access (missing key / non-object → nil).
  if n.isNil or n.kind != JObject:
    return nil
  let v = n.getOrDefault(key)
  if v.isNil or v.kind == JNull:
    nil
  else:
    v

# ---------------------------------------------------------------------------
# Rotation/closure parsing primitives — pure core
# ---------------------------------------------------------------------------
# These consume the deriver-format closure line-files and the JSON(C) pin
# documents at the merge-admission collector AND the preflight checker.
# All file/env/API access stays at each consumer's I/O boundary; these funcs
# are the pure, testable core.

func stripJsoncComments*(text: string): string {.raises: [].} =
  ## Minimal JSONC comment strip: removes `//`-to-EOL comments that are NOT
  ## inside a double-quoted string (escape-aware). The pin files carry
  ## whole-line `//` comments (config/trusted_writer_set.json); the state
  ## machine keeps the strip correct for inline comments too.
  var inStr = false
  var i = 0
  while i < text.len:
    let c = text[i]
    if inStr:
      result.add(c)
      if c == '\\' and i + 1 < text.len:
        result.add(text[i + 1])
        inc i
      elif c == '"':
        inStr = false
    else:
      if c == '"':
        inStr = true
        result.add(c)
      elif c == '/' and i + 1 < text.len and text[i + 1] == '/':
        while i < text.len and text[i] notin {'\r', '\n'}:
          inc i
        dec i
      else:
        result.add(c)
    inc i

func parseDerivedSet*(text: string): Result[HashSet[string], string] {.raises: [].} =
  ## Deriver-format linetext → line-set (byte-equality membership). Empty
  ## lines are skipped (a trailing newline is natural); a non-empty line that
  ## is not `<mode> <type> <sha>\t<path>` is a contract violation — fail-closed
  ## (a silently-dropped line would weaken the closure equality).
  var lines = initHashSet[string]()
  for ln in text.splitLines():
    if ln.len == 0:
      continue
    let ti = ln.rfind('\t')
    if ti < 1 or ti == ln.len - 1:
      return err("malformed derived line '" & ln &
        "' (expected '<mode> <type> <sha>\\t<path>')")
    lines.incl(ln)
  ok(lines)

func pinClosureLineSet*(pin: JsonNode): Result[Option[HashSet[string]], string] {.raises: [].} =
  ## Extract the trustedCheckerTreeClosure pin from a parsed
  ## trusted_writer_set JSON node into a deriver-format line-set
  ## (`<mode> <type> <sha>\t<path>`, byte-comparable with the deriver emit).
  ## ok(none) = key ABSENT — the genesis state (ADR-0025 §7). err = the pin is
  ## present but malformed (fail-closed).
  if pin.isNil or pin.kind != JObject:
    return err("trusted_writer_set.json is not a JSON object")
  let key = pin.getOrDefault(RotationPinKey)
  if key.isNil or key.kind == JNull:
    return ok(none(HashSet[string]))
  if key.kind != JObject:
    return err(RotationPinKey & " is not an object")
  var lines = initHashSet[string]()
  for path, entry in key.pairs:
    if entry.kind != JObject:
      return err(RotationPinKey & " entry '" & path & "' is not an object (fail-closed)")
    # std/json getOrDefault returns NIL (not JNull) for missing keys — the
    # file's nil-safe jv helper is used.
    let mode = jv(entry, "mode")
    let typ = jv(entry, "type")
    let sha = jv(entry, "sha")
    if mode.isNil or typ.isNil or sha.isNil or
       mode.kind != JString or typ.kind != JString or sha.kind != JString or
       mode.getStr.len == 0 or typ.getStr.len == 0 or sha.getStr.len == 0:
      return err(RotationPinKey & " entry '" & path &
        "' missing mode/type/sha (fail-closed)")
    lines.incl(mode.getStr & " " & typ.getStr & " " & sha.getStr & "\t" & path)
  ok(some(lines))

func closurePathFromLine*(line: string): string {.raises: [].} =
  ## `<mode> <type> <sha>\t<path>` → the path (after the last tab).
  let i = line.rfind('\t')
  if i < 0: "" else: line[i + 1 .. ^1]

# ---------------------------------------------------------------------------
# Split-layout resolution + canonical path-set digest (DEBT#558)
# ---------------------------------------------------------------------------
# The immutable anchors (trustedWriterWorkflow / trustedAdmissionWorkflowSha /
# pathSetDigest) stay in the App-protected writer set; the mutable closure
# records move to config/trusted_checker_closure.json. Consumers resolve BOTH
# layouts through resolvePinClosure — one implementation, no drift.

func isSplitLayout*(pin: JsonNode): bool {.raises: [], axiomDecision(
  id = "DECISION-0829",
  reason = "DEBT#558 trust-epoch split: pathSetDigest is the layout discriminator so a missing closure document in the split layout fails closed instead of reading as genesis",
  adr = "docs/adr/0042-trust-epoch-closure-split.md",
  introduced = "v104"
).} =
  ## The split layout is declared by the presence of pathSetDigest. This is
  ## the only discriminator that separates "genesis (no anchor yet)" from
  ## "split layout whose closure document is missing" — the latter must
  ## fail-closed, never read as genesis.
  let d = jv(pin, RotationPathSetDigestKey)
  not d.isNil and d.kind == JString

func closureCompanionPath*(pinPath: string): string {.raises: [].} =
  ## Sibling closure document for an explicit pin path:
  ## `config/trusted_writer_set.json` → `config/trusted_checker_closure.json`.
  let i = pinPath.rfind('/')
  if i < 0: RotationClosureBasename
  else: pinPath[0 ..< i] & "/" & RotationClosureBasename

func validClosurePath*(path: string): bool {.raises: [], axiomDecision(
  id = "DECISION-0829",
  reason = "DEBT#558 trust-epoch split: repo-relative POSIX path contract; absolute/traversal/duplicate paths must never enter the anchored path set",
  adr = "docs/adr/0042-trust-epoch-closure-split.md",
  introduced = "v104"
).} =
  ## Repo-relative POSIX path: non-empty, not absolute, no control characters
  ## (the tab-delimited line grammar cannot represent them — closurePathFromLine
  ## splits on the last tab, so a tab inside a path would truncate it), no
  ## empty / "." / ".." segments. A path that fails this is a contract
  ## violation (fail-closed) — it can never be a git tree path.
  if path.len == 0 or path[0] == '/':
    return false
  for c in path:
    if ord(c) < 0x20 or ord(c) == 0x7f:
      return false
  for seg in path.split('/'):
    if seg.len == 0 or seg == "." or seg == "..":
      return false
  true

func pathSetDigest*(lines: HashSet[string]): Result[string, string] {.
    raises: [], axiomDecision(
  id = "DECISION-0829",
  reason = "DEBT#558 trust-epoch split: single canonical path-set digest implementation (domain + NUL-separated byte-sorted paths) shared by preflight, landing, reanchor, and the epoch gate",
  adr = "docs/adr/0042-trust-epoch-closure-split.md",
  introduced = "v104"
).} =
  ## Canonical path-set digest — the value stored in
  ## trusted_writer_set.json.pathSetDigest:
  ##
  ##   domain = "axiom.trusted-checker-closure.path-set.v1"
  ##   preimage = domain "\n" p1 "\0" p2 "\0" ... pn "\0"
  ##   digest = domain ":" sha256Hex(preimage)
  ##
  ## p1..pn are the byte-sorted unique paths. NUL is legal in no git path, so
  ## it is the unambiguous separator. Fail-closed: empty set, malformed line,
  ## invalid path, duplicate path (a duplicate JSON key yields two lines for
  ## one path — the digest refuses it rather than silently collapsing).
  if lines.len == 0:
    return err("empty closure path set (fail-closed)")
  var
    paths: seq[string]
    seen = initHashSet[string]()
  for ln in lines:
    let p = closurePathFromLine(ln)
    if not validClosurePath(p):
      return err("invalid closure path '" & p & "' (fail-closed)")
    if p in seen:
      return err("duplicate closure path '" & p & "' (fail-closed)")
    seen.incl(p)
    paths.add(p)
  paths.sort()
  var pre = RotationPathSetDigestDomain
  pre.add('\n')
  for p in paths:
    pre.add(p)
    pre.add('\0')
  ok(RotationPathSetDigestDomain & ":" & sha256Hex(pre))

func resolvePinClosure*(pin, closureDoc: JsonNode):
    Result[Option[HashSet[string]], string] {.raises: [], axiomDecision(
  id = "DECISION-0829",
  reason = "DEBT#558 trust-epoch split: one closure-source resolution order for legacy/split/composite layouts; ambiguous layouts and a missing split closure document fail closed",
  adr = "docs/adr/0042-trust-epoch-closure-split.md",
  introduced = "v104"
).} =
  ## Canonical closure-source resolution for every consumer (preflight
  ## checker, merge_cli landing, reanchor_pin, epoch gate):
  ##   * pin carries RotationPinKey (legacy layout) → use it;
  ##   * closureDoc carries RotationPinKey (split layout) → use it;
  ##   * both carry it → equal line-sets are accepted (a composite document
  ##     may carry both), differing ones are ambiguous → fail-closed;
  ##   * neither, but pathSetDigest is present (split layout declared) → the
  ##     closure document is REQUIRED → fail-closed (never read as genesis);
  ##   * neither and no digest → genesis (ADR-0025 §7 1회).
  if pin.isNil or pin.kind != JObject:
    return err("trusted_writer_set document is not a JSON object")
  if not closureDoc.isNil and closureDoc.kind != JObject:
    return err(RotationClosurePath & " is not a JSON object (fail-closed)")
  let legacy = pinClosureLineSet(pin)
  if legacy.isErr:
    return err(legacy.err)
  let hasLegacy = legacy.get.isSome
  var split: Result[Option[HashSet[string]], string]
  var hasSplit = false
  if not closureDoc.isNil:
    split = pinClosureLineSet(closureDoc)
    if split.isErr:
      return err(RotationClosurePath & ": " & split.err)
    hasSplit = split.get.isSome
  if hasLegacy and hasSplit:
    if legacy.get.get != split.get.get:
      return err("ambiguous closure layout: " & RotationPinKey &
        " present in both the pin document and " & RotationClosurePath &
        " with differing line-sets (fail-closed)")
    return ok(legacy.get)
  if hasLegacy:
    return ok(legacy.get)
  if hasSplit:
    return ok(split.get)
  if isSplitLayout(pin):
    return err("split pin layout (" & RotationPathSetDigestKey &
      " present) but closure records are absent from both the pin document" &
      " and " & RotationClosurePath & " (fail-closed)")
  ok(none(HashSet[string]))

func closureDocSchemaOk*(doc: JsonNode): Result[bool, string] {.raises: [], axiomDecision(
  id = "DECISION-0829",
  reason = "DEBT#558 trust-epoch split: standalone closure documents must declare the known schemaVersion; unknown versions are fail-closed",
  adr = "docs/adr/0042-trust-epoch-closure-split.md",
  introduced = "v104"
).} =
  ## Standalone closure document schema: schemaVersion is REQUIRED and must
  ## be the known version (unknown version = fail-closed, never best-effort).
  if doc.isNil or doc.kind != JObject:
    return err(RotationClosurePath & " is not a JSON object (fail-closed)")
  let s = jv(doc, "schemaVersion")
  if s.isNil or s.kind != JString or s.getStr.len == 0:
    return err(RotationClosurePath & " schemaVersion missing (fail-closed)")
  if s.getStr != RotationClosureSchemaVersion:
    return err(RotationClosurePath & " schemaVersion '" & s.getStr &
      "' != '" & RotationClosureSchemaVersion & "' (unknown version — fail-closed)")
  ok(true)

func pathSetDigestVerdict*(pin: JsonNode; lines: Option[HashSet[string]]): Result[bool, string] {.raises: [], axiomDecision(
  id = "DECISION-0829",
  reason = "DEBT#558 trust-epoch split: the declared pathSetDigest must equal the canonical digest of the resolved closure records; legacy documents without the field are exempt",
  adr = "docs/adr/0042-trust-epoch-closure-split.md",
  introduced = "v104"
).} =
  ## Split-layout digest judgment. ok(true) when the layout is legacy (no
  ## pathSetDigest field) or the declared digest equals digest(lines).
  ## ok(false) = the declared digest does not match the closure path set.
  ## err = malformed digest field / invalid closure paths (input violation).
  if pin.isNil or pin.kind != JObject:
    return err("pin document is not a JSON object")
  let d = jv(pin, RotationPathSetDigestKey)
  if d.isNil:
    return ok(true)
  if d.kind != JString or d.getStr.len == 0:
    return err(RotationPathSetDigestKey & " is not a non-empty string (fail-closed)")
  let expected = d.getStr
  let prefix = RotationPathSetDigestDomain & ":"
  if not expected.startsWith(prefix):
    return err(RotationPathSetDigestKey & " has an unknown version/domain '" &
      expected & "' (fail-closed)")
  let hex = expected[prefix.len .. ^1]
  if hex.len != 64:
    return err(RotationPathSetDigestKey & " is not a 64-hex sha256 (fail-closed)")
  for c in hex:
    if c notin {'0'..'9', 'a'..'f'}:
      return err(RotationPathSetDigestKey & " is not a 64-hex sha256 (fail-closed)")
  if lines.isNone or lines.get.len == 0:
    return ok(false)
  let computed = pathSetDigest(lines.get)
  if computed.isErr:
    return err(computed.err)
  ok(computed.get == expected)

# ---------------------------------------------------------------------------
# ④ New-anchor judgment (H2 / Pass 2.75) — the single implementation
# ---------------------------------------------------------------------------

func newAnchorVerdict*(derivedH: HashSet[string];
                       pinH, pinB: Option[HashSet[string]]):
    tuple[ok: bool; code, reason: string] {.raises: [].} =
  ## Does the H-side pin anchor exactly H? ok iff pin@H is present and
  ## line-set(pin@H) == set(derived H) — the exact Pass 2.75 (H2) condition
  ## `newAnchorOk = pinH.isSome and pinH.get == derivedH`. On failure,
  ## (code, reason) is the ladder-selected annotation the verdict consumes
  ## VERBATIM: ROT_GENESIS_INVALID iff pin@B has no closure key (the one-time
  ## genesis exception cannot be established), else ROT_NEW_PIN. ok=true →
  ## code/reason are "" (a ④ fact annotation exists only for a failure —
  ## every-path FACT, never a deny here; the single ④ policy deny site is
  ## Pass 2.75 in MergeAdmissible).
  result.ok = pinH.isSome and pinH.get == derivedH
  if result.ok:
    return
  if pinB.isNone:
    result.code = "ROT_GENESIS_INVALID"
    result.reason = "genesis pin anchor invalid: pin@H missing or line-set(pin@H) != set(derived H) — " &
      "the one-time genesis exception cannot be established (fail-closed)"
  else:
    result.code = "ROT_NEW_PIN"
    result.reason = "pin anchor invalid: line-set(pin@H) != set(derived H) — " &
      "the pin must anchor exactly H (fail-closed)"

{.pop.}
