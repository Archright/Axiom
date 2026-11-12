## proof_reconcile_gate.nim — A3 skip-자체 검증 (Decision Record ↔ executed 재확인)
##
## Post-execution reconciliation for the A2 select job
## (.github/workflows/runner-pool-acceptance.yml). GitHub treats a SKIPPED job
## as Success — so "the job was skipped" is NOT itself the success condition;
## "why it was skipped (Decision Record) and executed == selected (recheck)"
## is (this is the A3 core). The gate makes that recheck fail-closed and
## deterministic.
##
## Invocation modes (same binary):
##   proof_reconcile_gate
##       → static self-check only: the W2↔ci-bootstrap / W8↔gateway-shard
##         projection invariant against ProofUnitCatalog (pre-push /
##         GATES_FAST wiring — no CI artifacts exist at push time).
##   proof_reconcile_gate --decision-dir <dir> --executed-dir <dir>
##       → static self-check + runtime reconciliation (the reconcile CI job).
##   proof_reconcile_gate --decision-dir <dir> --executed-dir <dir>
##                        --oracle-evidence <path> --derived-h <path>
##       → the above + oracle-evidence re-verification (Phase 2c — B-trusted
##         consumer): the gate RE-DERIVES every axis claim of the B oracle's
##         oracle-evidence.json against the substrate it sees and fails closed
##         on any absence/undecidability/mismatch (0 미선언 금지). The two new
##         args are a pair and are reconcile-mode-only; giving neither keeps
##         the legacy behavior byte-identical.
##
## Runtime judgment (fail-closed — missing/unparseable/absent = FAIL):
##   1. decision.json present, parses, schema == axiom/ci-select-decision/v1,
##      mode ∈ {none, selected, full}.
##   2. executed-*.json bind to the decision: their decisionHash must equal
##      sha256(decision.json bytes) (recomputed here over the downloaded
##      artifact); mode field must equal the decision mode; job/shard fields
##      must match their artifact name.
##   3. executed == selected, exact set equality (실행多了/不足 모두 FAIL):
##        mode=none        → zero executed records
##        mode=selected    → exactly decision.executableWorkUnits × shards
##        mode=full        → {W2, W8} × shards 0..7 (full L2, A1.3), and the
##                           envelope's projection must equal that fixed matrix.
##
## Determinism: no timestamps, no randomness, no network; all sets sorted.
## Exit: 0 = consistent, 1 = drift detected (fail closed), 2 = usage/env error.
##
## ── Oracle-evidence re-verification (Phase 2c) ──────────────────────────────
## The B worktree oracle emits oracle-evidence.json as an independent derivation
## record of the same execution surface this gate guards (schema
## axiom/oracle-evidence/v1). This gate is its B-trusted FAIL-CLOSED consumer:
## every axis claim is recomputed HERE and compared. Expected layout:
##
##   { "schema": "axiom/oracle-evidence/v1",
##     "derivationDigest": "<64hex = sha256 of the canonical document minus the
##                           derivationDigest field; object keys sorted at every
##                           depth; compact separators; array order preserved>",
##     "axes": {
##       "gateScanRoots":    { "roots": [<sorted>], "changed": {root: bool} },
##       "envHashInputs":    { "members": [<sorted>], "changed": {member: bool} },
##       "identity":         { "lockfileDigest": "<64hex = sha256(nimble.lock)>" },
##       "embedSet":         { "members": [<sorted>], "changed": {member: bool} },
##       "executionClosure": { "digest": "<64hex = sha256(byte-sorted derived-H
##                              lines, '\n'-joined, trailing newline dropped)>" } } }
##
## Check chain (any failure → exit 1 with a cause-naming diagnostic):
##   a. file read/parse, schema, all 5 axes present.
##   b. derivationDigest recomputed (canonical document minus the field itself)
##      and compared — reuse of the :213-216 digest-recompute pattern (repo-
##      standard sha256sum; std/sha2 unavailable behind the checksums gap).
##   c. static 4-axis re-derivation: gateScanRoots roots must equal the gate's
##      canonical scan roots and embedSet members must equal the gate's embed
##      surface (see consts); every claimed Δ (plus envHashInputs' claimed
##      members) must equal the gate's own git diff --name-only <base>..<head>
##      re-derivation over the decision envelope's base/head; identity
##      lockfileDigest must equal sha256(nimble.lock) at the working directory
##      (repo root in CI).
##   d. executionClosure.digest must equal sha256 of the byte-sorted lines of
##      --derived-h, the org gate closure job artifact (admission-check.yml
##      consumes the same derived-closure/derived-H.txt; AXIOM_DERIVED_H_PATH
##      precedent).
## Canonical JSON escaping is minimal (jq-compatible): `"` `\` and C controls
## escaped, everything else — including raw UTF-8 bytes — verbatim. Evidence
## strings are ASCII paths/digests in practice.

import core/trusted/layer_declaration
axiomLayer "tools"
import core/trusted/axiom_pragmas_lite

import gate/proof_unit_catalog
import std/[os, osproc, strutils, sequtils, sets, json, parseopt, algorithm, sugar, tempfiles]

{.push raises: [].}

const
  DecisionSchema   = "axiom/ci-select-decision/v1"
  ExecutedSchema   = "axiom/ci-executed/v1"
  BootstrapJob     = "ci-bootstrap"
  ShardJob         = "gateway-shard"
  BootstrapJobFile = "executed-ci-bootstrap.json"
  ShardFilePrefix  = "executed-shard-"
  # K=8 fixed partition (ADR-0023 Amendment A1.8); must stay in lockstep with
  # the workflow matrix [0..7] and the selector's CIJobShardCount — POLICY 다이얼 금지.
  ExpectedShards   = [0, 1, 2, 3, 4, 5, 6, 7]
  DecisionFileName = "decision.json"

  # ── Phase 2c: oracle-evidence contract (B-trusted consumer) ──
  OracleEvidenceSchema = "axiom/oracle-evidence/v1"
  # Sorted; all five must be present in evidence "axes".
  OracleEvidenceAxes = ["embedSet", "envHashInputs", "executionClosure",
                        "gateScanRoots", "identity"]
  # The gate's own canonical gate-scan roots — the oracle's gateScanRoots axis
  # must claim EXACTLY this set (widening/narrowing = FAIL), and each root's Δ
  # is re-derived here over decision base/head.
  GateScanRoots = ["config/policy", "docs/agents", "docs/spec"]
  # The embed surface this gate treats as embedded derivation inputs — the
  # oracle's embedSet axis must claim EXACTLY these members (sorted).
  EmbedSetMembers = ["AGENTS.md", "docs/agents/architecture.md",
                     "docs/agents/rules_workflow.md"]

# ═══════════════════════════════════════════════════════════════════════════
# Static: catalog ↔ projection invariant
# ═══════════════════════════════════════════════════════════════════════════

func catalogProjectionFailures(): seq[string] =
  ## The runtime projection table (W2↔ci-bootstrap, W8↔gateway-shard) must not
  ## drift from the single editing authority. Fail-closed on rename.
  var sawW2 = false
  var sawW8 = false
  for u in ProofUnitCatalog:
    if u.id == "W2":
      sawW2 = true
      if u.name != BootstrapJob:
        result.add("catalog W2.name drift: '" & u.name & "' != '" & BootstrapJob &
                   "' (A3 projection W2↔ci-bootstrap)")
    if u.id == "W8":
      sawW8 = true
      if u.name != "test-gateway":
        result.add("catalog W8.name drift: '" & u.name & "' != 'test-gateway' " &
                   "(A3 projection W8↔gateway-shard)")
  if not sawW2:
    result.add("catalog W2 missing — A3 projection invariant underivable")
  if not sawW8:
    result.add("catalog W8 missing — A3 projection invariant underivable")

# ═══════════════════════════════════════════════════════════════════════════
# Helpers
# ═══════════════════════════════════════════════════════════════════════════

func jsonStr(node: JsonNode, key: string): string =
  ## Field value as string; "" for missing/non-string leaves (callers treat
  ## empty as absent — fail-closed via explicit emptiness checks below).
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
  ## Field value as a sorted seq of strings; empty when absent/not an array.
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

func jsonIntArray(node: JsonNode, key: string): seq[int] =
  ## Field value as a sorted seq of ints; empty when absent/not an array.
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
    if item.kind == JInt:
      result.add(int(item.num))
  result.sort()

# ── Phase 2c: canonical-form / strict-read helpers (fail-closed) ──

func canonEscape(s: string): string =
  ## Minimal JSON string escaping, jq-compatible: `"` `\` and C controls are
  ## escaped; everything else — including raw UTF-8 bytes ≥ 0x80 — passes
  ## through verbatim (so a jq -S -c producer and this gate agree byte-for-byte
  ## on the canonical form; evidence strings are ASCII paths/digests anyway).
  result = newStringOfCap(s.len + 2)
  for c in s:
    case c
    of '"': result.add("\\\"")
    of '\\': result.add("\\\\")
    of '\b': result.add("\\b")
    of '\f': result.add("\\f")
    of '\n': result.add("\\n")
    of '\r': result.add("\\r")
    of '\t': result.add("\\t")
    else:
      if ord(c) <= 0x1F:  # remaining C controls → \uXXXX (jq-compatible hex)
        result.add("\\u" & toHex(ord(c), 4))
      else:               # printable + raw UTF-8 bytes pass through verbatim
        result.add(c)

func canonicalJson(node: JsonNode): string =
  ## Compact JSON with object keys sorted lexicographically at EVERY depth and
  ## array order preserved — the byte form the producer must have hashed for
  ## derivationDigest (equivalent to jq -S -c modulo the escaping above).
  case node.kind
  of JObject:
    result.add("{")
    var entries: seq[(string, JsonNode)]
    for k, v in node.pairs:
      entries.add((k, v))
    for i, e in entries.sortedByIt(it[0]):
      if i > 0:
        result.add(",")
      result.add("\"")
      result.add(canonEscape(e[0]))
      result.add("\":")
      result.add(canonicalJson(e[1]))
    result.add("}")
  of JArray:
    result.add("[")
    for i in 0 ..< node.len:
      if i > 0:
        result.add(",")
      result.add(canonicalJson(node[i]))
    result.add("]")
  of JString:
    result.add("\"")
    result.add(canonEscape(node.str))
    result.add("\"")
  of JInt:
    result.add($node.num)
  of JFloat:
    result.add($node.fnum)
  of JBool:
    result.add($node.bval)
  of JNull:
    result.add("null")

func isHexN(s: string; n: int): bool =
  if s.len != n:
    return false
  for ch in s:
    if ch notin {'0' .. '9', 'a' .. 'f', 'A' .. 'F'}:
      return false
  result = true

func isHex40(s: string): bool =
  ## git object OID (decision base/head).
  isHexN(s, 40)

func isHex64(s: string): bool =
  ## sha256 hex digest (derivationDigest / lockfileDigest / closure digest).
  isHexN(s, 64)

func jsonStrArrayChecked(node: JsonNode, key: string): tuple[items: seq[string]; valid: bool] =
  ## Strict string-array reader: valid=false when absent / not an array / any
  ## item is not a string (callers fail closed on malformed instead of silently
  ## dropping items — 0 미선언 금지).
  if node == nil or node.kind != JObject:
    return (@[], false)
  var v: JsonNode
  try:
    v = node[key]
  except CatchableError:
    return (@[], false)
  if v == nil or v.kind != JArray:
    return (@[], false)
  for i in 0 ..< v.len:
    if v[i].kind != JString:
      return (@[], false)
    result.items.add(v[i].str)
  result.items.sort()
  result.valid = true

func jsonBoolMapChecked(node: JsonNode, key: string): tuple[entries: seq[(string, bool)]; valid: bool] =
  ## Strict bool-map reader: the object value under `key` as sorted (k, v)
  ## pairs; valid=false when absent / not an object / any value is not a JSON
  ## bool (fail-closed on schema violation, never a silent default).
  if node == nil or node.kind != JObject:
    return (@[], false)
  var v: JsonNode
  try:
    v = node[key]
  except CatchableError:
    return (@[], false)
  if v == nil or v.kind != JObject:
    return (@[], false)
  for k, val in v.pairs:
    if val == nil or val.kind != JBool:
      return (@[], false)
    result.entries.add((k, val.bval))
  result.entries.sort()
  result.valid = true

func isUnderRoot(path, root: string): bool =
  ## path is inside root (or is the root itself); root has no trailing slash.
  if path == root:
    return true
  path.startsWith(root & "/")

func deltaIn(changed: seq[string]; root: string): bool =
  ## Δ presence: any changed path under `root`.
  for p in changed:
    if isUnderRoot(p, root):
      return true

proc sha256OfFile(path: string): string {.axiomEffect: IoEffect.} =
  ## sha256 hex of a file's bytes via the repo-standard external tool
  ## (selector.computeFingerprint uses the same sha256sum — std/sha2 is
  ## unavailable behind the checksums/sha2 dependency gap). FAIL (empty) when
  ## the tool is missing — fail closed, never a weaker hash.
  var outp = ""
  var code = -1
  try:
    (outp, code) = execCmdEx("sha256sum " & quoteShell(path))
  except CatchableError:
    return ""
  if code != 0:
    return ""
  let parts = outp.strip().split(' ')
  if parts.len == 0 or parts[0].len != 64:
    return ""
  result = parts[0]

proc sha256OfBytes(bytes: string): string {.axiomEffect: IoEffect.} =
  ## sha256 hex over canonical byte content via a scratch file (repo-standard
  ## sha256sum; scratch path/name never enters the digest, so the verdict stays
  ## deterministic). FAIL (empty) when the tool is missing/unusable.
  var tmpPath = ""
  try:
    let (f, p) = createTempFile("ax-evidence-", ".tmp")
    tmpPath = p
    f.write(bytes)
    f.close()
  except CatchableError:
    if tmpPath.len > 0:
      try: removeFile(tmpPath)
      except CatchableError: discard # axiom:best-effort(cleanup failure on error path: original failure already returned via "")
    return ""
  result = sha256OfFile(tmpPath)
  try: removeFile(tmpPath)
  except CatchableError: discard # axiom:best-effort(post-hash temp file cleanup failure: result already computed, non-fatal)

# ═══════════════════════════════════════════════════════════════════════════
# Runtime: decision ↔ executed reconciliation
# ═══════════════════════════════════════════════════════════════════════════

proc executedFilesIn(dir: string): seq[string] =
  ## Sorted basenames of executed-*.json files under `dir` (missing dir → empty).
  if not dirExists(dir):
    return @[]
  try:
    for entry in walkDir(dir):
      if entry.kind == pcFile:
        let base = extractFilename(entry.path)
        if base.startsWith("executed-") and base.endsWith(".json"):
          result.add(base)
  except OSError:
    discard  # unreadable dir → no files → any expected file fails as 不足 (fail-closed)
  result.sort()

proc decodeShardFromName(base: string): int =
  ## shard index parsed from "executed-shard-<n>.json"; -1 when malformed.
  let prefix = ShardFilePrefix
  if not base.startsWith(prefix) or not base.endsWith(".json"):
    return -1
  # "executed-shard-0.json": digits live in [prefix.len ..< len - ".json".len)
  let mid = base[prefix.len ..< base.len - ".json".len]
  result = -1
  for ch in mid:
    if ch notin {'0' .. '9'}:
      return -1
    result = if result < 0: ord(ch) - ord('0') else: result * 10 + (ord(ch) - ord('0'))

proc runtimeFailures(decisionDir, executedDir: string): seq[string] =
  let decisionPath = decisionDir / DecisionFileName
  var decisionBytes = ""
  var decReadErr = ""
  try:
    decisionBytes = readFile(decisionPath)
  except CatchableError as e:
    decReadErr = e.msg
  if decReadErr.len > 0:
    result.add("unreadable decision record: " & decisionPath & " (" &
               decReadErr & ") (A3: no decision → cannot reconcile → FAIL)")
    return
  if decisionBytes.len == 0:
    result.add("missing decision record: " & decisionPath &
               " (A3: no decision → cannot reconcile → FAIL)")
    return

  var decision: JsonNode
  try:
    decision = parseJson(decisionBytes)
  except CatchableError:
    result.add("decision.json parse error: " & decisionPath)
    return

  let mode = jsonStr(decision, "mode")
  if jsonStr(decision, "schema") != DecisionSchema:
    result.add("decision schema mismatch: '" & jsonStr(decision, "schema") & "'")
  if mode notin ["none", "selected", "full"]:
    result.add("decision mode invalid: '" & mode & "'")
    return

  # (1) decisionHash: recompute sha256 of the downloaded decision.json bytes
  #     and bind every executed record to it (stale/foreign execution → FAIL).
  let decisionHash = sha256OfFile(decisionPath)
  if decisionHash.len == 0:
    result.add("sha256sum unavailable/failed — decisionHash cannot be recomputed (FAIL-closed)")
    return

  # (2) expected projection from the decision envelope.
  let executable = jsonStrArray(decision, "executableWorkUnits")
  let shardsExpected = jsonIntArray(decision, "shards")

  if mode == "full":
    # Full L2 is the A1.3 fixed surface: {W2, W8} × shards 0..7. Re-derive
    # independently from the gate's own ExpectedShards so a stale envelope can
    # never silently shrink a full run; a disagreeing envelope is itself a FAIL.
    let fullExecutable = @["W2", "W8"]
    if executable != fullExecutable:
      result.add("mode=full but envelope executableWorkUnits != [W2, W8]: " &
                 executable.join(","))
    if shardsExpected != @ExpectedShards:
      result.add("mode=full but envelope shards != 0..7: " &
                 shardsExpected.mapIt($it).join(","))

  # (3) executed record set.
  let executed = executedFilesIn(executedDir)
  var expectedFiles: seq[string]
  var expectedShardSet: HashSet[int]
  if "W2" in executable:
    expectedFiles.add(BootstrapJobFile)
  if "W8" in executable:
    for s in shardsExpected:
      expectedShardSet.incl(s)
      expectedFiles.add(ShardFilePrefix & $s & ".json")
  expectedFiles.sort()

  if mode == "none":
    if executed.len > 0:
      result.add("mode=none but " & $executed.len & " executed record(s) present: " &
                 executed.join(", ") & " (실행多了 — nothing should have run)")
    return

  # exact set equality: missing expected (=不足) and unexpected files (=多了)
  for f in expectedFiles:
    if f notin executed:
      result.add("missing executed record (不足): " & f)
  for f in executed:
    if f notin expectedFiles:
      result.add("unexpected executed record (실행多了): " & f)

  # (4) per-file binding checks.
  for f in executed:
    let path = executedDir / f
    var raw = ""
    var recReadErr = ""
    try:
      raw = readFile(path)
    except CatchableError as e:
      recReadErr = e.msg
    if recReadErr.len > 0:
      result.add("unreadable executed record: " & f & " (" & recReadErr & ")")
      continue
    if raw.len == 0:
      result.add("empty executed record: " & f)
      continue
    var rec: JsonNode
    try:
      rec = parseJson(raw)
    except CatchableError:
      result.add("executed record parse error: " & f)
      continue
    if jsonStr(rec, "schema") != ExecutedSchema:
      result.add("executed schema mismatch: " & f)
    if jsonStr(rec, "decisionHash") != decisionHash:
      result.add("decisionHash mismatch in " & f & ": '" &
                 jsonStr(rec, "decisionHash") & "' != '" & decisionHash & "'")
    if jsonStr(rec, "mode") != mode:
      result.add("mode mismatch in " & f & ": '" & jsonStr(rec, "mode") &
                 "' != decision '" & mode & "'")
    # filename ↔ declaration self-consistency + work-unit claim.
    if f == BootstrapJobFile:
      if jsonStr(rec, "job") != BootstrapJob:
        result.add("job/name mismatch in " & f & ": '" & jsonStr(rec, "job") & "'")
      if jsonStrArray(rec, "workUnits") != @["W2"]:
        result.add("workUnits claim mismatch in " & f)
    else:
      let shard = decodeShardFromName(f)
      if jsonStr(rec, "job") != ShardJob:
        result.add("job/name mismatch in " & f & ": '" & jsonStr(rec, "job") & "'")
      var declaredShard = -999
      if rec != nil and rec.kind == JObject:
        var sv: JsonNode
        try:
          sv = rec["shard"]
        except CatchableError:
          sv = nil
        if sv != nil and sv.kind == JInt:
          declaredShard = int(sv.num)
      if shard < 0 or declaredShard != shard:
        result.add("shard/name mismatch in " & f &
                   " (name=" & $shard & ", declared=" & $declaredShard & ")")
      if shard notin expectedShardSet:
        result.add("shard " & $shard & " executed but not in decision.shards")
      let units = jsonStrArray(rec, "workUnits")
      if units != @["W8"]:
        result.add("workUnits claim mismatch in " & f)

# ═══════════════════════════════════════════════════════════════════════════
# Runtime: oracle-evidence re-verification (Phase 2c — B-trusted consumer)
# ═══════════════════════════════════════════════════════════════════════════

type ChangedPathSet = object
  paths: seq[string]
  error: string

proc gitChangedPaths(base, head: string): ChangedPathSet {.axiomEffect: IoEffect.} =
  ## Δ = `git diff --name-only <base> <head>` (two-dot — the same determination
  ## the selector uses for changedFiles, impact_closure_selector.nim:333).
  ## Fail-closed: any git error (OID missing from a shallow checkout, not a
  ## repo, …) leaves error set → axis deltas cannot be re-derived → FAIL
  ## (0 미선언 금지). Caller validates 40-hex before this, so quoting is safe.
  var outp = ""
  var code = -1
  try:
    (outp, code) = execCmdEx("git diff --name-only " & quoteShell(base) & " " &
                             quoteShell(head), {poStdErrToStdOut})
  except CatchableError as e:
    result.error = "git diff unavailable: " & e.msg
    return
  if code != 0:
    result.error = "git diff --name-only " & base & ".." & head & " failed (exit " &
                   $code & "): " & outp.strip()
    return
  for line in outp.splitLines():
    let p = line.strip()
    if p.len > 0:
      result.paths.add(p)
  result.paths.sort()

proc checkDeltaMap(axis: JsonNode; axisName: string; members: seq[string];
                   changed: seq[string]; fails: var seq[string]) =
  ## An axis's `changed` map must be EXACTLY {member: bool} for every claimed
  ## member (missing key = 0 미선언, extra key = widening — both FAIL) and
  ## every value must equal the gate's own Δ re-derivation over git diff
  ## base..head. `members` is the caller-validated sorted claimed member list.
  let (map, mapValid) = jsonBoolMapChecked(axis, "changed")
  if not mapValid:
    fails.add("axis " & axisName & ": changed map malformed (must be an object " &
              "mapping every member to a JSON boolean)")
    return
  var mapKeys: seq[string]
  for (k, _) in map:
    mapKeys.add(k)
  if mapKeys != members:
    var missing: seq[string]
    for m in members:
      if m notin mapKeys:
        missing.add(m)
    var extra: seq[string]
    for k in mapKeys:
      if k notin members:
        extra.add(k)
    var detail: seq[string]
    if missing.len > 0:
      detail.add("missing " & missing.join(","))
    if extra.len > 0:
      detail.add("extra " & extra.join(","))
    fails.add("axis " & axisName & ": changed keys ≠ members (" & detail.join("; ") &
              ") (0 미선언 금지)")
    return
  for (k, v) in map:
    let actual = deltaIn(changed, k)
    if v != actual:
      fails.add("axis " & axisName & ": Δ mismatch for '" & k & "': claimed " &
                $v & " but re-derived " & $actual & " (git diff base..head)")

proc oracleEvidenceFailures(evidencePath, derivedHPath, base, head: string): seq[string] =
  ## Fail-closed re-verification of the B oracle's oracle-evidence.json:
  ##   a. read/parse, schema, all 5 axes present
  ##   b. derivationDigest recomputed over the canonical document (itself minus
  ##      the derivationDigest field; keys sorted; compact) and compared
  ##   c. static 4-axis re-derivation: gateScanRoots/embedSet sets pinned by
  ##      this gate, envHashInputs members claimed, all Δ against git diff
  ##      base..head + identity lockfileDigest against sha256(nimble.lock)
  ##   d. executionClosure.digest vs sha256 of byte-sorted --derived-h lines
  ## Absence, unreadability, undecidability or any mismatch → diagnostic + FAIL
  ## (0 미선언 금지 — absence is never silent).

  # a. file / schema / axes
  var raw = ""
  try:
    raw = readFile(evidencePath)
  except CatchableError as e:
    return @["unreadable oracle-evidence: " & evidencePath & " (" & e.msg &
             ") (FAIL-closed — absence is not silence)"]
  if raw.len == 0:
    return @["empty oracle-evidence: " & evidencePath & " (FAIL-closed)"]
  var doc: JsonNode
  try:
    doc = parseJson(raw)
  except CatchableError:
    return @["oracle-evidence parse error: " & evidencePath]
  if jsonStr(doc, "schema") != OracleEvidenceSchema:
    result.add("oracle-evidence schema mismatch: '" & jsonStr(doc, "schema") &
               "' != '" & OracleEvidenceSchema & "'")
  var axes: JsonNode
  try:
    axes = doc["axes"]
  except CatchableError:
    axes = nil
  if axes == nil or axes.kind != JObject:
    result.add("oracle-evidence missing axes object (5 axes required)")
    return
  var seenAxes = 0
  for ax in OracleEvidenceAxes:
    var v: JsonNode
    try:
      v = axes[ax]
    except CatchableError:
      v = nil
    if v == nil or v.kind != JObject:
      result.add("oracle-evidence missing axis: " & ax)
    else:
      inc seenAxes
  if seenAxes != OracleEvidenceAxes.len:
    return  # axis set broken — per-axis re-derivation cannot be trusted

  # b. derivationDigest — recompute over the canonical document minus itself
  let claimedDigest = jsonStr(doc, "derivationDigest")
  if not isHex64(claimedDigest):
    result.add("oracle-evidence derivationDigest missing/malformed: '" &
               claimedDigest & "'")
  else:
    var canon = newJObject()
    for k, v in doc.pairs:
      if k != "derivationDigest":
        canon[k] = v
    let recomputed = sha256OfBytes(canonicalJson(canon))
    if recomputed.len == 0:
      result.add("sha256sum unavailable/failed — derivationDigest cannot be " &
                 "recomputed (FAIL-closed)")
    elif recomputed != claimedDigest:
      result.add("oracle-evidence derivationDigest mismatch: claimed '" &
                 claimedDigest & "' != recomputed '" & recomputed &
                 "' (sha256 of canonical document minus derivationDigest)")

  # c. Δ substrate: base/head from the decision envelope (validated 40-hex OIDs)
  if not isHex40(base) or not isHex40(head):
    result.add("decision base/head unusable for Δ re-derivation (base='" & base &
               "', head='" & head & "') — 0 미선언 금지")
    return
  let changed = gitChangedPaths(base, head)
  if changed.error.len > 0:
    result.add("Δ 판정 불가: " & changed.error &
               " — oracle-evidence axes cannot be re-derived (FAIL-closed)")
    return

  # c1. gateScanRoots — exactly the gate's canonical scan roots, Δ per root
  proc jsonAxis(node: JsonNode; key: string): JsonNode =
    ## Safe key lookup — axis presence was validated above, so nil never occurs
    ## on the documented schema; the guard keeps the raises:[] contract.
    try:
      result = node[key]
    except CatchableError:
      result = nil

  let gsr = jsonAxis(axes, "gateScanRoots")
  let (gsrRoots, gsrValid) = jsonStrArrayChecked(gsr, "roots")
  if not gsrValid:
    result.add("axis gateScanRoots: roots malformed (must be an array of strings)")
  elif gsrRoots != GateScanRoots:
    result.add("axis gateScanRoots: roots ≠ [" & GateScanRoots.join(", ") &
               "]: " & gsrRoots.join(", "))
  else:
    checkDeltaMap(gsr, "gateScanRoots", gsrRoots, changed.paths, result)

  # c2. envHashInputs — non-empty claimed members, Δ per member
  let ehi = jsonAxis(axes, "envHashInputs")
  let (ehiMembers, ehiValid) = jsonStrArrayChecked(ehi, "members")
  if not ehiValid:
    result.add("axis envHashInputs: members malformed (must be an array of strings)")
  elif ehiMembers.len == 0:
    result.add("axis envHashInputs: members empty (0 미선언 금지)")
  else:
    checkDeltaMap(ehi, "envHashInputs", ehiMembers, changed.paths, result)

  # c3. identity — lockfileDigest == sha256(nimble.lock) at the working dir
  let idn = jsonAxis(axes, "identity")
  let claimedLock = jsonStr(idn, "lockfileDigest")
  if not isHex64(claimedLock):
    result.add("axis identity: lockfileDigest missing/malformed: '" &
               claimedLock & "'")
  else:
    let recomputedLock = sha256OfFile("nimble.lock")
    if recomputedLock.len == 0:
      result.add("axis identity: nimble.lock unreadable or sha256sum unavailable" &
                 " — lockfileDigest cannot be recomputed (FAIL-closed)")
    elif recomputedLock != claimedLock:
      result.add("axis identity: lockfileDigest mismatch: claimed '" &
                 claimedLock & "' != recomputed '" & recomputedLock &
                 "' (sha256(nimble.lock))")

  # c4. embedSet — exactly the gate's embed surface, Δ per member
  let emb = jsonAxis(axes, "embedSet")
  let (embMembers, embValid) = jsonStrArrayChecked(emb, "members")
  if not embValid:
    result.add("axis embedSet: members malformed (must be an array of strings)")
  elif embMembers != EmbedSetMembers:
    result.add("axis embedSet: members ≠ [" & EmbedSetMembers.join(", ") &
               "]: " & embMembers.join(", "))
  else:
    checkDeltaMap(emb, "embedSet", embMembers, changed.paths, result)

  # d. executionClosure — digest == sha256(byte-sorted derived-H lines)
  let exc = jsonAxis(axes, "executionClosure")
  let claimedClosure = jsonStr(exc, "digest")
  if not isHex64(claimedClosure):
    result.add("axis executionClosure: digest missing/malformed: '" &
               claimedClosure & "'")
  var derivedRaw = ""
  try:
    derivedRaw = readFile(derivedHPath)
  except CatchableError as e:
    result.add("unreadable derived-H: " & derivedHPath & " (" & e.msg &
               ") (FAIL-closed)")
  if derivedRaw.len == 0:
    result.add("empty derived-H: " & derivedHPath &
               " — closure digest cannot be recomputed (0 미선언 금지)")
  else:
    # canonical closure text: byte-sorted lines joined with '\n' (deriver
    # format '<mode> <type> <sha>\t<path>'; a single trailing newline — the
    # line-file convention — is normalized away so the hash is stable).
    var lines: seq[string]
    for ln in derivedRaw.splitLines():
      lines.add(ln)
    if lines.len > 0 and lines[^1] == "":
      lines.setLen(lines.len - 1)
    lines.sort()
    if lines.len == 0:
      result.add("derived-H has no lines: " & derivedHPath & " (0 미선언 금지)")
    else:
      let recomputedClosure = sha256OfBytes(lines.join("\n"))
      if recomputedClosure.len == 0:
        result.add("sha256sum unavailable/failed — executionClosure.digest " &
                   "cannot be recomputed (FAIL-closed)")
      elif recomputedClosure != claimedClosure:
        result.add("axis executionClosure: digest mismatch: claimed '" &
                   claimedClosure & "' != recomputed '" & recomputedClosure &
                   "' (sha256 of byte-sorted derived-H lines)")

# ═══════════════════════════════════════════════════════════════════════════
# Runner
# ═══════════════════════════════════════════════════════════════════════════

proc printHelp() =
  echo "proof_reconcile_gate — A3 skip-자체 검증 (decision ↔ executed 재확인)"
  echo ""
  echo "Usage:"
  echo "  proof_reconcile_gate [--decision-dir <dir> --executed-dir <dir>"
  echo "                       [--oracle-evidence <path> --derived-h <path>]]"
  echo ""
  echo "  no dirs              static self-check only (catalog projection, pre-push)"
  echo "  --decision-dir       directory containing decision.json (select artifact)"
  echo "  --executed-dir       directory containing executed-*.json (execution facts)"
  echo "  --oracle-evidence    oracle-evidence.json from the B-trusted oracle"
  echo "                       (Phase 2c re-verification; reconcile-mode only)"
  echo "  --derived-h          derived-H.txt from the org gate derived-closure"
  echo "                       artifact (must be given together with --oracle-evidence)"
  echo ""
  echo "Exit: 0 = consistent, 1 = drift (fail-closed), 2 = usage error."

proc main() {.axiomEffect: IoEffect.} =
  var decisionDir = ""
  var executedDir = ""
  var oracleEvidence = ""
  var derivedH = ""
  # parseopt quirk: `--opt value` (space form) yields the option with an empty
  # val and the value as a subsequent cmdArgument; `--opt=value` yields val
  # inline. Track the pending option key for the space form (same convention
  # the selector's cmdArgument fallback relies on).
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
        of "decision-dir":
          decisionDir = p.val
        of "executed-dir":
          executedDir = p.val
        of "oracle-evidence":
          oracleEvidence = p.val
        of "derived-h":
          derivedH = p.val
        else:
          printHelp()
          quit(2)
      else:
        # space form: value arrives as the next cmdArgument
        if p.key notin ["decision-dir", "executed-dir", "oracle-evidence", "derived-h"]:
          printHelp()
          quit(2)
        pending = p.key
    of cmdArgument:
      case pending
      of "decision-dir":
        decisionDir = p.key
      of "executed-dir":
        executedDir = p.key
      of "oracle-evidence":
        oracleEvidence = p.key
      of "derived-h":
        derivedH = p.key
      else:
        printHelp()
        quit(2)
      pending = ""

  echo ""
  echo "════════════════════════════════════════════════════════════"
  echo "  A3 PROOF RECONCILE GATE (Decision Record ↔ executed 재확인)"
  echo "════════════════════════════════════════════════════════════"

  let staticFails = catalogProjectionFailures()
  if staticFails.len == 0:
    echo "  PASS  (static) catalog ↔ A3 projection invariant (W2↔ci-bootstrap, W8↔gateway-shard)"
  else:
    echo "  FAIL  (static) catalog ↔ A3 projection invariant"
    for f in staticFails:
      echo "        - " & f

  var runtimeFails: seq[string] = @[]
  if decisionDir.len > 0 or executedDir.len > 0:
    if decisionDir.len == 0 or executedDir.len == 0:
      echo "  FAIL  usage: --decision-dir and --executed-dir must be given together"
      quit(2)
    runtimeFails = runtimeFailures(decisionDir, executedDir)
    if runtimeFails.len == 0:
      echo "  PASS  (runtime) executed == selected (exact set) + decisionHash bound"
    else:
      echo "  FAIL  (runtime) executed ≠ selected / binding broken"
      for f in runtimeFails:
        echo "        - " & f

  var oracleFails: seq[string] = @[]
  if oracleEvidence.len > 0 or derivedH.len > 0:
    # Phase 2c args are reconcile-mode-only and always a pair (partial wiring
    # is a usage error, not a silent skip — 0 미선언 금지).
    if decisionDir.len == 0 or executedDir.len == 0:
      echo "  FAIL  usage: --oracle-evidence/--derived-h are reconcile-mode args" &
           " (need --decision-dir and --executed-dir)"
      quit(2)
    if oracleEvidence.len == 0 or derivedH.len == 0:
      echo "  FAIL  usage: --oracle-evidence and --derived-h must be given together"
      quit(2)
    # Δ 판정용 base/head는 decision envelope에서 온다 (재읽기 — 결정론적).
    var base = ""
    var head = ""
    var decRaw = ""
    try:
      decRaw = readFile(decisionDir / DecisionFileName)
    except CatchableError:
      decRaw = ""
    var decisionForOracle: JsonNode
    if decRaw.len > 0:
      try:
        decisionForOracle = parseJson(decRaw)
      except CatchableError:
        decisionForOracle = nil
    else:
      decisionForOracle = nil
    if decisionForOracle == nil:
      oracleFails.add("cannot re-derive oracle axes: decision.json unreadable/" &
                      "unparseable (0 미선언 금지)")
    else:
      base = jsonStr(decisionForOracle, "base")
      head = jsonStr(decisionForOracle, "head")
      oracleFails = oracleEvidenceFailures(oracleEvidence, derivedH, base, head)
    if oracleFails.len == 0:
      echo "  PASS  (oracle) oracle-evidence v1 re-verified — schema, derivationDigest," &
           " gateScanRoots/envHashInputs/identity/embedSet Δ, executionClosure"
    else:
      echo "  FAIL  (oracle) oracle-evidence re-verification (B-trusted consumer)"
      for f in oracleFails:
        echo "        - " & f

  let total = staticFails.len + runtimeFails.len + oracleFails.len
  if total == 0:
    echo ""
    echo "  EXIT 0: decision record and executed surface reconcile — A3 skip-자체 검증 PASS."
    quit(0)
  echo ""
  echo "  EXIT 1: " & $total & " reconciliation violation(s) — fail closed."
  quit(1)

when isMainModule:
  main()
