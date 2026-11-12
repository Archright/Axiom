import std/strutils
import core/trusted/layer_declaration
axiomLayer "trusted.core.layer-rules"

## Layer Rules — SSOT for architectural layer definitions
## Extracted from gate_consts.nim to break core→gate dependency.
## gate_consts.nim re-exports these symbols for backward compatibility.

{.push raises: [].}

## ── RL-14.4 import normalization contract (numbered, authoritative) ───────
## 1. 소스 경로: repo-relative, `/` separators, leading `./` removed, `..`
##    resolved, `.nim` KEPT → e.g. `core/audit/sad_gate.nim`. Absolute paths
##    are reduced through their last `/src/` component first. This is the
##    exact form `architecture_policy.lock:27` (allowed_core_to_verification)
##    and the soc_queries.nim DIP-whitelist comparison use.
## 2. import 대상: canonical target = the token with `src/` prefix and
##    trailing `.nim` removed → e.g. `import src/engine/profiler` →
##    `engine/profiler`.
## 3. Asymmetry is INTENTIONAL: a source keeps `.nim` because it is a FILE
##    identity matched exactly against policy-lock entries; a target drops
##    `.nim` because it is a MODULE identity matched by prefix against
##    LayerRules.
## 4. 별칭(`as`) 제거: `a as x` → `a`. The alias is a local binding, not
##    identity.
## 5. `except` 목록 제거: `a except y, z` → `a`.
## 6. bracket 전개: `std/[a, b]` → `std/a`, `std/b` (and `pkg/[...]`
##    likewise) — a one-to-many transform, therefore it lives in
##    expandImportTargets, not in the string→string normalizeImportPath.
## 7. pseudo-directory: `std/*`, `pkg/*`, and single-segment bare names
##    (`system`, `net`, ...) are out of RL-14.4 scope — they are not
##    layer-owned. They normalize literally and LayerRules' allowed list /
##    default-allow matches them; they are never by themselves a violation
##    reason. (A bare name that IS a same-directory module is resolved by the
##    compile-time caller — see resolveSameDirModule in layer_enforcement.nim.)
## 8. 문자열 import `"path/mod"`: strip quotes, then normalize.
## 9. 상대경로 `../`: resolved against the source file's directory BEFORE
##    comparing (resolveImportTarget). A leading `..` that survives
##    resolution must NOT silently default-allow — rule 10 applies.
## 10. fail-closed: any import form the extractor cannot interpret (unknown
##     node shape, unresolvable path, malformed/ambiguous bracket) is treated
##     as a violation, not as allowed. resolveImportTarget signals it with an
##     empty result; isAllowedImport returns false so callers can report
##     UNPARSED_IMPORT.

func normalizeImportPath*(path: string): string {.raises: [].} =
  ## Canonicalize ONE import-target token — contract rules 2, 4, 5, 7, 8.
  ## Bracket expansion is rule 6 and lives in expandImportTargets; a bracket
  ## token reaching this func passes through unexpanded.
  var p = path.replace("\\", "/").strip()
  # rule 8: string import — strip one pair of surrounding quotes
  if p.len >= 2 and ((p[0] == '"' and p[^1] == '"') or
                     (p[0] == '\'' and p[^1] == '\'')):
    p = p[1 .. ^2].strip()
  # rules 4/5: alias and except-list are not identity (defensive — the
  # statement parser normally cuts them before this func is called)
  let excIdx = p.find(" except ")
  if excIdx >= 0:
    p = p[0 ..< excIdx].strip()
  let asIdx = p.find(" as ")
  if asIdx >= 0:
    p = p[0 ..< asIdx].strip()
  while p.startsWith("./"):
    p = p[2 .. ^1]
  var segs: seq[string] = @[]
  for s in p.split('/'):
    if s == "..":
      if segs.len > 0 and segs[^1] != "..":
        segs.setLen(segs.len - 1)
      else:
        segs.add(s)
    elif s == ".":
      discard
    else:
      segs.add(s)
  p = segs.join("/")
  if p.startsWith("/"):
    # absolute form: reduce to the rooted repo-relative form below /src/
    let srcIdx = p.rfind("/src/")
    if srcIdx >= 0:
      p = p[(srcIdx + 1) .. ^1]
  if p.startsWith("src/"):
    p = p[4 .. ^1]
  if p.endsWith(".nim"):
    p = p[0 .. ^5]
  result = p

func normalizeSourcePathRooted*(path: string): string {.raises: [].} =
  ## Rule 1 intermediate form: repo-relative source path that KEEPS the
  ## leading `src/` component — the bookkeeping form `../` resolution needs,
  ## because the real on-disk depth of a src-tree file includes that segment.
  var p = path.replace("\\", "/").strip()
  if p.len >= 2 and ((p[0] == '"' and p[^1] == '"') or
                     (p[0] == '\'' and p[^1] == '\'')):
    p = p[1 .. ^2].strip()
  while p.startsWith("./"):
    p = p[2 .. ^1]
  var segs: seq[string] = @[]
  for s in p.split('/'):
    if s == "..":
      if segs.len > 0 and segs[^1] != "..":
        segs.setLen(segs.len - 1)
      else:
        segs.add(s)
    elif s == ".":
      discard
    else:
      segs.add(s)
  p = segs.join("/")
  if p.startsWith("/"):
    let srcIdx = p.rfind("/src/")
    if srcIdx >= 0:
      p = p[(srcIdx + 1) .. ^1]
  result = p

func normalizeSourcePath*(path: string): string {.raises: [].} =
  ## Contract rule 1 — canonical SOURCE identity: repo-relative, `/`
  ## separators, leading `./` removed, `..` resolved, `.nim` KEPT, leading
  ## `src/` dropped. `src/core/audit/sad_gate.nim` and
  ## `<root>/src/core/audit/sad_gate.nim` both normalize to
  ## `core/audit/sad_gate.nim`. Rule 3 asymmetry: unlike normalizeImportPath,
  ## the `.nim` suffix is KEPT.
  result = normalizeSourcePathRooted(path)
  if result.startsWith("src/"):
    result = result[4 .. ^1]

func expandImportTargets*(raw: string): seq[string] {.raises: [].} =
  ## Contract rule 6 — bracket expansion of one raw import token:
  ## `std/[a, b]` → `@["std/a", "std/b"]`; `pkg/[x]` → `@["pkg/x"]`.
  ## Non-bracket tokens pass through as a single-element result. A malformed
  ## bracket form (no closing `]`, empty member) yields `@[]` — an
  ## uninterpretable form is fail-closed (contract rule 10).
  let openIdx = raw.find('[')
  if openIdx < 0:
    return @[raw]
  if not raw.endsWith("]"):
    return @[]
  let prefix = raw[0 ..< openIdx]
  let inner = raw[(openIdx + 1) .. ^2]
  result = @[]
  for piece in inner.split(','):
    let t = piece.strip()
    if t.len == 0:
      return @[]
    result.add(prefix & t)

func resolveImportTarget*(srcFile, rawTarget: string): seq[string] {.raises: [].} =
  ## Contract rules 2, 4–6, 8–10 for ONE raw import token: bracket
  ## expansion → canonicalization → `../` resolution against the source
  ## file's directory. Returns the canonical target(s); an EMPTY result means
  ## the form is uninterpretable (rule 10 fail-closed → violation; callers
  ## report UNPARSED_IMPORT).
  var resolved: seq[string] = @[]
  for raw in expandImportTargets(rawTarget):
    if raw.len == 0:
      return @[]
    let canonical = normalizeImportPath(raw)
    if canonical.len == 0:
      return @[]
    if not canonical.startsWith("../"):
      resolved.add(canonical)
      continue
    # rule 9: resolve surviving leading ".." against the source's directory
    let base = normalizeSourcePathRooted(srcFile)
    let cut = base.rfind('/')
    var dirSegs: seq[string] = @[]
    if cut >= 0:
      dirSegs = base[0 ..< cut].split('/')
    var rest = canonical
    var unresolvable = false
    while rest.startsWith("../"):
      if dirSegs.len == 0:
        # escapes the repo root — cannot resolve (rule 10, never default-allow)
        unresolvable = true
        break
      dirSegs.setLen(dirSegs.len - 1)
      rest = rest[3 .. ^1]
    if unresolvable:
      return @[]
    resolved.add(normalizeImportPath(dirSegs.join("/") & "/" & rest))
  return resolved

type
  LayerRule* = object
    source*: string              ## Source layer path prefix (e.g., "src/core/")
    allowedImports*: seq[string] ## Allowed import path prefixes
    forbiddenImports*: seq[string] ## Forbidden import path prefixes

  DebtBudget* = object
    metric*: string              ## Metric name (e.g., "import_lint_violations")
    baseline*: int               ## Current baseline value
    weeklyReductionPct*: float   ## Target weekly reduction percentage
    targetDate*: string          ## Target completion date

# === Structural Enforcement Rules (v3) ===
#
# Closed rule table (DEBT#287): exactly ONE rule per layer. isAllowedImport
# matches rules by inferLayer(rule.source) with first-match-wins, so per-layer
# uniqueness is what keeps every rule reachable — the previous table carried 7
# unreachable (shadowed) rules: src/engine/, src/frontend/, src/sieve/,
# src/personas/, src/infrastructure/, src/generated/ were all shadowed by
# src/verification/ (all infer to "infrastructure"), and src/mcp/ was shadowed
# by src/cli/ (both inferred "presentation"). src/mcp/ is now its own layer
# ("mcp") so its rule is live with 0 verdict flips across the 8725-edge graph.
#
# Verdict-neutrality note: files under src/engine/, src/frontend/, src/sieve/,
# src/personas/, src/infrastructure/, src/generated/ were already adjudicated
# by the src/verification/ rule (first infrastructure match) — removing the
# shadowed duplicates preserves the adjudicated graph byte-for-byte.

const
  LayerRules*: array[6, LayerRule] = [
    LayerRule(
      source: "src/core/",
      allowedImports: @["core/"],
      # RL-14.4 (docs/agents/core_rules.md:231) forbids core→verification|cli|mcp|ui|gate.
      # verification/ and ui/ were missing until 2026-10-11 (DEBT#490, KNOWN GAP pinned by
      # tests/negative/layer_gate/forbidden_{verification,ui}); their absence let the
      # default-allow branch pass those imports. engine/ and frontend/ are extra SoC
      # restrictions of this table, not part of RL-14.4's five.
      # Approved grandfathered crossings live per (file, target) in
      # src/gate/architecture_policy.lock `core_to_verification_pairs` and are injected
      # by the gate — this table must stay the single direction SSOT and must not read
      # src/gate/** (docs/agents/architecture.md:88).
      forbiddenImports: @["cli/", "gate/", "engine/", "frontend/", "mcp/", "verification/", "ui/"]
    ),
    LayerRule(
      source: "src/verification/",
      # Governs every infrastructure-path file: src/verification/, src/engine/,
      # src/frontend/, src/infrastructure/, src/personas/, src/generated/,
      # src/sieve/, src/shared_types/, src/engine.nim.
      allowedImports: @["core/", "verification/", "gate/", "infrastructure/", "cli/selection_state"],
      forbiddenImports: @["mcp/"]
    ),
    LayerRule(
      source: "src/gate/",
      allowedImports: @["core/", "gate/", "infrastructure/", "shared_types/", "cli/cli_types",
        "verification/canonical_json"],
      forbiddenImports: @["mcp/", "engine/", "verification/"]
    ),
    LayerRule(
      source: "src/cli/",
      # Governs every presentation-path file: src/cli/, src/ui/, src/api/,
      # src/api.nim, src/bin/.
      allowedImports: @["core/", "verification/", "engine/", "gate/", "infrastructure/", "cli/", "ui/"],
      forbiddenImports: @[]
    ),
    LayerRule(
      source: "tools/",
      allowedImports: @["shared_types/", "core/", "cli/shared/",
        "verification/lean_repl_bridge", "verification/router",
        "verification/symbolic_test_synth", "verification/cert_promotion",
        # Verification-analysis measurement tools (replay/reuse/cross-check):
        "verification/observed_audit_contract", "verification/semantic_query_types",
        "verification/verification_dependency", "verification/producer_identity",
        "verification/observation_pipeline", "verification/verification_query_engine",
        "verification/repo_snapshot_digest",
        "verification/selection/",
        "verification/accounting/",
        # INV-9 forbidden-claim sentence scanner — certificate-integrity static
        # scan consumed by tools/ci/check_inv9_forbidden_claims.nim
        # (certification_continuity_contract.md §5 INV-9; ADR-0030 U2).
        "verification/forbidden_claim_scan",
        # Plan 1 — measurement tools apply the run-level verdict
        # (verification_decision_authority.evaluateRunOutcome) to
        # reconstructed raw state (phase_x0 trajectory path).
        "verification/obligation/verification_decision_authority",
        "engine/profiler",
        "gate/gate_types", "gate/topology_spec", "gate/helper_spec",
        "gate/proof_unit_catalog", "gate/slice_catalog",
        "gate/framework/topology_types"],
      forbiddenImports: @["gate/", "engine/", "verification/"]
    ),
    LayerRule(
      source: "src/mcp/",
      allowedImports: @["core/", "verification/", "infrastructure/", "mcp/", "personas/"],
      forbiddenImports: @["cli/", "gate/"]
    )
  ]

  DebtBudgets*: array[4, DebtBudget] = [
    DebtBudget(metric: "import_lint_violations", baseline: 36,
               weeklyReductionPct: 5.0, targetDate: "2026-08-01"),
    DebtBudget(metric: "layer_violations", baseline: 8,
               weeklyReductionPct: 5.0, targetDate: "2026-08-01"),
    DebtBudget(metric: "effect_violations", baseline: 80,
               weeklyReductionPct: 5.0, targetDate: "2026-09-01"),
    DebtBudget(metric: "nimtry_violations", baseline: 704,
               weeklyReductionPct: 5.0, targetDate: "2026-12-01")
  ]

{.pop.}
