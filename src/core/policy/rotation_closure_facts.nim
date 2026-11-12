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

import std/[json, options, sets, strutils]
import core/results

# ---------------------------------------------------------------------------
# Pin identity constants (ADR-0025 §7/§13)
# ---------------------------------------------------------------------------

const
  ## The pin file — the B-side anchor, read relative to the workspace cwd
  ## (the B checkout in the verdict job).
  RotationPinBPath* = "config/trusted_writer_set.json"
  ## trusted_writer_set.json key carrying the closure pin. Absent = the
  ## genesis state (ADR-0025 §7 1회).
  RotationPinKey* = "trustedCheckerTreeClosure"

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
