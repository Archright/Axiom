import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## semantic_set_derivation.nim — the SINGLE derivation authority for the
## judgment key's semantic set (contract component ⑤, scheme v3).
##
## Core formula (docs/spec/test_judgment_cas_contract.md §4 v1.0.3):
##
##   S = TreeUniverse(R) − N
##   검증(포함-증인): W ⊆ S ∧ W ∩ N = ∅   ← 위반 = 도출 FAIL
##   분할 검증: S ∪ N == TreeUniverse (각 경로가 정확히 한쪽에만)
##
## R is the TESTED tree (the probe anchor OID the admission workflow hands
## over via AXIOM_JUDGMENT_CAS_TESTED_TREE_OID). TreeUniverse(R) is the full
## recursive git ls-tree of R; N is the single certified no-effect exclusion
## table (absorbing src/gate/proof_unit_catalog.nim CertifiedNoEffect
## Prefixes/Extensions/RootNames + the impact_closure_selector
## isCertifiedNoEffect carve-outs, one table); S is everything else.
##
## Normalization (contract §4.1 — user-corrected, non-negotiable):
##   1. LOSSLESS ELEMENTS: no `path:sha256` line format (a newline in a path
##      would be ambiguous). The canonical element is the RAW
##      `git ls-tree -r -z <testedTree>` NUL record —
##      `<mode> <type> <oid>\t<path>` — so the file type (blob/tree/commit,
##      including symlinks 120000 and gitlinks 160000) and the mode
##      (100644/100755/120000/160000) are bound to the path by construction.
##      Sorting is byte order over the whole record (LC_ALL=C semantics —
##      Nim's system.cmp on strings is memcmp order, locale-free). The set
##      digest is sha256 over the sorted NUL-terminated record stream.
##   2. GIT-OBJECT DERIVATION: file content identity comes ONLY from the
##      ls-tree blob OIDs (the git object store). The working directory is
##      never read by this module. A tree-outside input that wants to affect
##      the key must bind through another key member (env/recipe/toolchain —
##      they exist) or the derivation refuses (fail-closed).
##   3. RELATIVE COMPLETENESS: W ⊆ S proves only "no KNOWN input is
##      excluded". The exclusion table's every rule carries its no-effect
##      ground (무영향 근거, mandatory non-empty), the partition check is
##      machine-asserted (S ∪ N == universe, no overlap, no gap), and the
##      residual risks (dynamic paths, undiscovered inputs) are REGISTERED —
##      in this header and the contract — never claimed deleted.
##
## The probe anchor (b-probe-tree, 4 propositions — contract §4.1):
##   p1 해석 가능  — the tree OID must resolve in the CALLER's git object
##                  store (probeTreeResolvable / the ls-tree itself).
##   p2 키 비참여  — the OID never enters the key: the closure carries the
##                  S digest, not the tree OID (structural — the type is the
##                  contract; see judgment_cas.JudgmentClosure).
##   p3 provenance 일치 — the plan's decision file records the probe OID it
##                  derived from; the attest stage cross-checks it against
##                  the CURRENT probe OID (one admission run = one tree).
##   p4 검증 불가 → EXECUTED — an unresolvable/malformed probe is never a
##                  REUSED basis: the derivation errs and the plan falls
##                  back to the original execution (judgment_cas).
##
## Residual risk register (relative completeness — deletions are NOT claimed):
##   RR-1 staticRead through a computed path whose site is not in
##        ComputedStaticReadSites (a new dynamic compile-time read would be
##        invisible). Drift guard: tests/unit/test_judgment_set_derivation.nim
##        T6 re-scans the tree and fails when a site/target is undeclared.
##   RR-2 runtime file reads outside the declared witness set W (a test
##        binary reading an excluded-class file at RUN time). W is the
##        declared known-input set; unknown runtime reads are not proven
##        no-effect — they are carried as risk, not certainty.
##   RR-3 generated files (src/generated/**) are tree members of S — a build
##        that regenerates them without a commit changes nothing here
##        (ls-tree sees committed bytes only), but an uncommitted regeneration
##        diverges workdir from tree; the other closure members (①–④, ⑥–⑨)
##        measure the workdir and would advance instead.
##   RR-4 submodules (gitlink 160000) are single elements — their own trees
##        are NOT recursed (git ls-tree -r stops at gitlinks); a mutated
##        submodule CONTENT at the same OID-sha is invisible (the recorded
##        sha is the gitlink's pinned commit, which is the correct identity).

import std/[algorithm, osproc, streams, strutils]
import core/axiom_pragmas
import core/crypto/hash_kernel
import core/results

axiomIoBoundary()

# ---------------------------------------------------------------------------
# The single exclusion table N — absorbed, with mandatory no-effect grounds
# ---------------------------------------------------------------------------

type
  NoEffectRule* = object
    ## One exclusion rule + its mandatory no-effect ground (무영향 근거).
    ## An empty ground is a contract violation of this module (asserted by
    ## validateExclusionTable, called on every derivation).
    pattern*: string
    ground*: string

const NoEffectPrefixRules*: array[6, NoEffectRule] = [
  NoEffectRule(pattern: ".github/",
    ground: "workflow topology metadata — consumed by the GitHub Actions " &
      "runner, never compiled into or executed by the judged test binaries " &
      "(absorbed: proof_unit_catalog.CertifiedNoEffectPrefixes)"),
  NoEffectRule(pattern: ".githooks/",
    ground: "local enforcement hook installers — developer-machine " &
      "convenience, not a verification input (absorbed: " &
      "proof_unit_catalog.CertifiedNoEffectPrefixes)"),
  NoEffectRule(pattern: ".opencode/",
    ground: "agent session configuration — tooling workspace state " &
      "(absorbed: proof_unit_catalog.CertifiedNoEffectPrefixes)"),
  NoEffectRule(pattern: ".axiom/",
    ground: "local staging/cache root — regenerated runtime state, no " &
      "source identity (absorbed: proof_unit_catalog.CertifiedNoEffectPrefixes)"),
  NoEffectRule(pattern: ".config/",
    ground: "editor/tool configuration — machine-local preference " &
      "(absorbed: proof_unit_catalog.CertifiedNoEffectPrefixes)"),
  NoEffectRule(pattern: ".cursorrules",
    ground: "editor rules file — machine-local preference (absorbed: " &
      "proof_unit_catalog.CertifiedNoEffectPrefixes)")]

const NoEffectExtensionRules*: array[16, NoEffectRule] = [
  # docs/evidence key-invariance rides on THIS .md rule alone (there is no
  # docs/evidence prefix rule): a non-.md artifact under docs/evidence/ (e.g.
  # a future .json) default-includes (S) and ADVANCES the judgment key.
  NoEffectRule(pattern: ".md",
    ground: "prose documents — EXCEPT the normative faces and computed " &
      "staticRead targets carved out below (docs/spec, docs/agents, " &
      "config/templates, AGENTS.md, docs/DEBT_REGISTRY.md): non-normative " &
      "documentation bytes cannot change a compiled binary or a test " &
      "execution (absorbed: proof_unit_catalog.CertifiedNoEffectExtensions)"),
  NoEffectRule(pattern: ".png",
    ground: "image asset — never a compile or test input (absorbed: " &
      "proof_unit_catalog.CertifiedNoEffectExtensions)"),
  NoEffectRule(pattern: ".svg",
    ground: "image asset — never a compile or test input (absorbed: " &
      "proof_unit_catalog.CertifiedNoEffectExtensions)"),
  NoEffectRule(pattern: ".jpg",
    ground: "image asset — never a compile or test input (absorbed: " &
      "proof_unit_catalog.CertifiedNoEffectExtensions)"),
  NoEffectRule(pattern: ".jpeg",
    ground: "image asset — never a compile or test input (absorbed: " &
      "proof_unit_catalog.CertifiedNoEffectExtensions)"),
  NoEffectRule(pattern: ".gif",
    ground: "image asset — never a compile or test input (absorbed: " &
      "proof_unit_catalog.CertifiedNoEffectExtensions)"),
  NoEffectRule(pattern: ".ico",
    ground: "image asset — never a compile or test input (absorbed: " &
      "proof_unit_catalog.CertifiedNoEffectExtensions)"),
  NoEffectRule(pattern: ".webp",
    ground: "image asset — never a compile or test input (absorbed: " &
      "proof_unit_catalog.CertifiedNoEffectExtensions)"),
  NoEffectRule(pattern: ".lock",
    ground: "dependency lockfile class — nimble.lock is carved out below " &
      "(it IS a recipe member ⑦); other .lock files are package-manager " &
      "state, not verification inputs (absorbed: " &
      "proof_unit_catalog.CertifiedNoEffectExtensions)"),
  NoEffectRule(pattern: ".nix",
    ground: "environment declaration — machine provisioning, not a " &
      "verification input (absorbed: proof_unit_catalog.CertifiedNoEffectExtensions)"),
  NoEffectRule(pattern: ".dockerignore",
    ground: "container build metadata — image packaging only (absorbed: " &
      "proof_unit_catalog.CertifiedNoEffectExtensions)"),
  NoEffectRule(pattern: ".gitignore",
    ground: "VCS filter metadata — affects git plumbing, not compilation " &
      "or test semantics (absorbed: proof_unit_catalog.CertifiedNoEffectExtensions)"),
  NoEffectRule(pattern: ".gitattributes",
    ground: "VCS attribute metadata — LFS/plumbing only (absorbed: " &
      "proof_unit_catalog.CertifiedNoEffectExtensions)"),
  NoEffectRule(pattern: ".editorconfig",
    ground: "editor formatting preference — no compile or test effect " &
      "(absorbed: proof_unit_catalog.CertifiedNoEffectExtensions)"),
  NoEffectRule(pattern: ".envrc",
    ground: "direnv environment file — machine-local shell environment, " &
      "never a verification input (absorbed: " &
      "proof_unit_catalog.CertifiedNoEffectExtensions)"),
  NoEffectRule(pattern: ".git",
    ground: "git metadata suffix (e.g. packed refs) — VCS plumbing, not a " &
      "verification input (absorbed: proof_unit_catalog.CertifiedNoEffectExtensions)")]

const NoEffectRootNameRules*: array[3, NoEffectRule] = [
  NoEffectRule(pattern: "license",
    ground: "legal text at repo root — never a verification input (absorbed: " &
      "proof_unit_catalog.CertifiedNoEffectRootNames)"),
  NoEffectRule(pattern: "copying",
    ground: "legal text at repo root — never a verification input (absorbed: " &
      "proof_unit_catalog.CertifiedNoEffectRootNames)"),
  NoEffectRule(pattern: "readme",
    ground: "orientation prose at repo root — never a verification input " &
      "(absorbed: proof_unit_catalog.CertifiedNoEffectRootNames)")]

const NormativePrefixes*: array[4, string] = [
  "docs/spec/",
  "docs/agents/",
  "config/policy/",
  "config/templates/"]

const NormativeExactPaths*: array[3, string] = [
  "AGENTS.md",
  "docs/DEBT_REGISTRY.md",
  "nimble.lock"]

func normativeGround*(path: string): string {.raises: [].} =
  ## The mandatory ground each carve-out carries (why the path can NEVER be
  ## excluded — the W∩N=∅ enforcement makes an accidental widening here a
  ## derivation failure instead of a silent blind spot).
  for p in NormativePrefixes:
    if path.startsWith(p):
      return case p
        of "docs/spec/":
          "normative contract face — proof_unit_consistency_gate scan root " &
          "and computed staticRead target face (spec_binding_macro): " &
          "배제 금지 (contract v1.0.3 §4.1)"
        of "docs/agents/":
          "normative agent-constitution face — embedded via " &
          "src/policy/embedded_agents_docs.nim and a gate scan root: 배제 금지"
        of "config/policy/":
          "policy threshold/state SSOT face — policy bytes are verifier " &
          "semantics: 배제 금지"
        of "config/templates/":
          "computed staticRead targets (subagent_orchestrator plan " &
          "templates compiled into the binary): 배제 금지"
        else: ""
  for p in NormativeExactPaths:
    if path == p:
      return case p
        of "AGENTS.md":
          "constitution SSOT — embedded at compile time via " &
          "src/policy/embedded_agents_docs.nim: 배제 금지"
        of "docs/DEBT_REGISTRY.md":
          "W1 edge — make check-debt reads it (impact_closure_selector " &
          "isCertifiedNoEffect carve-out 흡수): 배제 금지"
        of "nimble.lock":
          "judgment recipe member ⑦ — the .lock exclusion class must not " &
          "swallow a known input (W∩N=∅): 배제 금지"
        else: ""
  ""

func isNormativePath*(path: string): bool {.raises: [].} =
  ## True when the path is a normative face / known-input carve-out — it can
  ## never be classified into N (배제 금지).
  normativeGround(path).len > 0

func isCertifiedNoEffectPath*(path: string): bool {.raises: [].} =
  ## The single N-table predicate — absorbed from
  ## src/gate/proof_unit_catalog.nim (CertifiedNoEffectPrefixes/Extensions/
  ## RootNames) + the impact_closure_selector.isCertifiedNoEffect carve-outs
  ## (docs/DEBT_REGISTRY.md, docs/agents/**), with the normative faces
  ## forced-semantic FIRST (배제 금지). One table, one authority — this module.
  if isNormativePath(path):
    return false
  for rule in NoEffectPrefixRules:
    if path.startsWith(rule.pattern):
      return true
  let lower = path.toLowerAscii()
  for rule in NoEffectExtensionRules:
    if lower.endsWith(rule.pattern):
      return true
  if lower in ["license", "copying", "readme"]:
    return true
  false

# ---------------------------------------------------------------------------
# Computed staticRead declarations — the k12 blind-spot closure (T6 guard)
# ---------------------------------------------------------------------------

const ComputedStaticReadTargets*: array[30, string] = [
  "AGENTS.md",
  "axiom.nimble",
  "config/gates.manifest.toml",
  "config/gates.waiver.toml",
  "config/policy/contract_layer.schema.json",
  "config/policy/examples_allowlist_anchor.json",
  "config/policy/examples_budget_drift_info.json",
  "config/policy/examples_evidence_envelope.json",
  "config/policy/policy_dispositions.json",
  "config/policy/policy_layer.schema.json",
  "config/templates/bad_plan_missing_stage.md",
  "config/templates/bad_plan_no_tasks.md",
  "config/templates/good_plan.md",
  "data/command_policy.json",
  "data/debt_budgets.json",
  "data/feature_manifest.json",
  "data/i18n/ko.json",
  "data/policy_manifest.json",
  "data/stateless_whitelist.json",
  "docs/DEBT_REGISTRY.md",
  "docs/agents/architecture.md",
  "docs/agents/rules_workflow.md",
  "docs/spec/spec_registry.json",
  "docs/spec/three_tier_contract_architecture.md",
  "lean-toolchain",
  "proofs/lean-toolchain",
  "proofs/proof_witness.json",
  "src/core/domain_layout.json",
  "src/gate/manifest.d/_index.json",
  "tools/ci/nim_theater_allowlist.json"]
  ## The resolved repo-relative targets of every LITERAL (or statically
  ## pattern-resolvable) `staticRead` in the tree — the compile-input face.
  ## These are forced-semantic inputs of the key: a byte change to any of
  ## them must advance the key (T3) — the k12 blind spot of a pure
  ## no-effect-class digest. (merge_cli.nim is NOT here: its
  ## staticRead(currentSourcePath()) is a computed site, declared in SITES.)
  ## Drift guard: T6 asserts the tree's literal staticRead population never
  ## exceeds this declaration.

const ComputedStaticReadSites*: array[23, string] = [
  "src/cli/merge_cli.nim",
  "src/cli/version.nim",
  "src/core/audit/theater_linter.nim",
  "src/core/context/run_context.nim",
  "src/core/contracts/spec_binding_macro.nim",
  "src/core/registry_macro.nim",
  "src/core/release/version_derive.nim",
  "src/core/test_support/feature_macro.nim",
  "src/core/trusted/architecture_invariants.nim",
  "src/core/trusted/axiom_import_sandbox.nim",
  "src/core/trusted/axiom_pragmas_macros.nim",
  "src/core/trusted/compile_time_manifest.nim",
  "src/core/trusted/compile_time_source_scanner.nim",
  "src/core/trusted/effect_inference_engine.nim",
  "src/core/trusted/layer_enforcement.nim",
  "src/core/trusted/test_quality_guard.nim",
  "src/core/verified_axioms/axiom_catalog_validator.nim",
  "src/gate/all_gate_runners.nim",
  "src/gate/runners/anti_theater_gate.nim",
  "src/gate/runners/external_cli_smoke.nim",
  "src/gate/static_gate_scanner.nim",
  "src/verification/obligation/canonical_verification.nim",
  "tools/refactor/tcb_pbt_generator.nim"]
  ## Files hosting COMPUTED staticRead calls (the target is built from
  ## currentSourcePath()/caller arguments and is not statically
  ## enumerable here). T6 fails when the tree grows a computed site that is
  ## not declared. The scanned-source targets of these sites (.nim module
  ## bytes) are tree members of S by class — no exclusion applies.

func validateExclusionTable*: string {.raises: [].} =
  ## "" = the declared tables are self-consistent; otherwise the reason.
  ## (a) every rule carries a non-empty ground (무영향 근거 필수),
  ## (b) no computed staticRead target is excluded by the table (the k12
  ##     guard is structural, not aspirational),
  ## (c) the declarations are sorted + duplicate-free (determinism).
  for rule in NoEffectPrefixRules:
    if rule.ground.len == 0:
      return "semantic_set_derivation: exclusion rule '" & rule.pattern &
        "' carries no no-effect ground (fail-closed)"
  for rule in NoEffectExtensionRules:
    if rule.ground.len == 0:
      return "semantic_set_derivation: exclusion rule '" & rule.pattern &
        "' carries no no-effect ground (fail-closed)"
  for rule in NoEffectRootNameRules:
    if rule.ground.len == 0:
      return "semantic_set_derivation: exclusion rule '" & rule.pattern &
        "' carries no no-effect ground (fail-closed)"
  var last = ""
  for t in ComputedStaticReadTargets:
    if isCertifiedNoEffectPath(t):
      return "semantic_set_derivation: computed staticRead target '" & t &
        "' is excluded by the no-effect table — the k12 guard is violated (fail-closed)"
    if t == last or (last.len > 0 and t < last):
      return "semantic_set_derivation: ComputedStaticReadTargets not sorted/deduped at '" &
        t & "' (fail-closed)"
    last = t
  last = ""
  for s in ComputedStaticReadSites:
    if s == last or (last.len > 0 and s < last):
      return "semantic_set_derivation: ComputedStaticReadSites not sorted/deduped at '" &
        s & "' (fail-closed)"
    last = s
  ""

# ---------------------------------------------------------------------------
# Pure core — canonical elements, classification, partition, digest
# ---------------------------------------------------------------------------

type
  TreeElement* = object
    ## One canonical element of TreeUniverse(R) — the RAW ls-tree record
    ## parts (lossless: type + mode + oid + git-original path).
    mode*: string   ## "100644" | "100755" | "120000" | "160000" ("040000" tree)
    kind*: string   ## "blob" | "tree" | "commit"
    oid*: string    ## 40-hex git object name
    path*: string   ## the git-original path (verbatim, -z unquoted)

func elementRecord*(e: TreeElement): string {.raises: [].} =
  ## The canonical record bytes — exactly what `git ls-tree` emits (minus
  ## the NUL): `<mode> <type> <oid>\t<path>`.
  e.mode & " " & e.kind & " " & e.oid & "\t" & e.path

func parseLsTreeZ*(output: string): Result[seq[TreeElement], string] {.
    raises: [].} =
  ## Parse the raw `git ls-tree -r -z` byte stream into canonical elements.
  ## Fail-closed: a malformed record (bad mode/type/oid, empty path, DUPLICATE
  ## path) is an error, never a skipped line — the universe must be complete
  ## for the partition to mean anything.
  var elements: seq[TreeElement] = @[]
  var seen: seq[string] = @[]
  var start = 0
  var i = 0
  while i <= output.len:
    if i == output.len or output[i] == '\0':
      let record = output[start ..< i]
      start = i + 1
      if record.len == 0:
        if i == output.len:
          break
        return err("semantic_set_derivation: empty ls-tree record (fail-closed)")
      let tab = record.find('\t')
      if tab < 0:
        return err("semantic_set_derivation: ls-tree record has no meta/path tab: '" &
          record & "' (fail-closed)")
      let meta = record[0 ..< tab].split(' ')
      if meta.len != 3:
        return err("semantic_set_derivation: ls-tree meta is not 3 fields: '" &
          record & "' (fail-closed)")
      if meta[0] notin ["100644", "100755", "120000", "160000", "040000"]:
        return err("semantic_set_derivation: ls-tree mode '" & meta[0] &
          "' unknown (fail-closed)")
      if meta[1] notin ["blob", "tree", "commit"]:
        return err("semantic_set_derivation: ls-tree type '" & meta[1] &
          "' unknown (fail-closed)")
      if meta[2].len != 40:
        return err("semantic_set_derivation: ls-tree oid is not 40 hex: '" &
          record & "' (fail-closed)")
      for c in meta[2]:
        if c notin {'0'..'9', 'a'..'f'}:
          return err("semantic_set_derivation: ls-tree oid is not lowercase hex: '" &
            record & "' (fail-closed)")
      let path = record[tab + 1 .. ^1]
      if path.len == 0:
        return err("semantic_set_derivation: ls-tree record has an empty path (fail-closed)")
      if path.startsWith('/'):
        return err("semantic_set_derivation: ls-tree path is absolute: '" &
          path & "' (fail-closed)")
      for p in seen:
        if p == path:
          return err("semantic_set_derivation: duplicate tree path '" & path &
            "' (fail-closed)")
      seen.add(path)
      elements.add(TreeElement(mode: meta[0], kind: meta[1], oid: meta[2],
        path: path))
    inc i
  ok(elements)

func classifyPath*(path: string): string {.raises: [].} =
  ## "semantic" | "excluded" — the partition of one path. Normative faces are
  ## semantic by fiat (배제 금지); everything the absorbed N-table matches is
  ## excluded; the rest is semantic (default-include).
  if isCertifiedNoEffectPath(path): "excluded" else: "semantic"

func semanticDigestFromRecords*(elements: seq[TreeElement]): string {.
    raises: [].} =
  ## sha256 over the sorted NUL-terminated ls-tree record stream of the
  ## SEMANTIC members (S). Sorting is whole-record byte order (LC_ALL=C
  ## semantics); NUL termination preserves the record boundary — the lossless
  ## canonical serialization (contract §4.1 normalization 1).
  var records: seq[string] = @[]
  for e in elements:
    records.add(elementRecord(e))
  records.sort()
  var stream = ""
  for r in records:
    stream.add(r)
    stream.add('\0')
  sha256Hex(stream)

# ---------------------------------------------------------------------------
# I/O boundary — git-object-only derivation (fail-closed)
# ---------------------------------------------------------------------------

func isHexLen*(s: string; n: int): bool {.raises: [].} =
  if s.len != n:
    return false
  for c in s:
    if c notin {'0'..'9', 'a'..'f'}:
      return false
  true

proc runGitOrErr*(repoRoot: string; args: string): Result[string, string] {.
  raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## One git subprocess, RAW byte capture — argv-spawned (`startProcess`, no
  ## shell), stdout/stderr merged into one stream, exit code fail-closed.
  ## `args` is a whitespace-tokenized command line; both call sites validate
  ## the tree OID as 40-hex BEFORE this proc ever sees it, so tokenization is
  ## injective. stdlib `execCmdEx` is line-oriented (readLine + an
  ## unconditional `"\n"` re-append) and fabricates a trailing newline after
  ## the `-z` NUL stream — fatal for the lossless record encoding (docs/spec/
  ## nim_2_2_10_stdlib_quirks.md Q-012). Text git commands are unaffected,
  ## but this boundary is raw for EVERY call — one capture semantics, no
  ## mixed modes.
  var argv: seq[string] = @[]
  for tok in args.split(' '):
    if tok.len > 0:
      argv.add(tok)
  var p: Process
  try:
    p = startProcess("git", workingDir = repoRoot, args = argv,
      options = {poUsePath, poStdErrToStdOut})
  except CatchableError as e:
    return err("semantic_set_derivation: git spawn failed (fail-closed): " & e.msg)
  var outp = ""
  try:
    outp = p.outputStream.readAll()
  except CatchableError as e:
    try: p.close()
    except CatchableError: discard # axiom:best-effort(capture already failed; close is resource hygiene, the derivation errs regardless)
    return err("semantic_set_derivation: git capture failed (fail-closed): " & e.msg)
  let code = p.waitForExit()
  p.close()
  if code != 0:
    return err("semantic_set_derivation: git " & args & " failed (fail-closed, exit " &
      $code & "): " & outp)
  ok(outp)

proc probeTreeResolvable*(repoRoot: string; treeOid: string): Result[bool, string] {.
  raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Probe proposition p1 — the tree OID resolves in the CALLER's object
  ## store. A malformed OID is an err (the caller treats any probe failure as
  ## "검증 불가" → never REUSED, p4).
  if not isHexLen(treeOid, 40):
    return err("semantic_set_derivation: probe tree OID is not 40-hex: '" &
      treeOid & "' (fail-closed)")
  let r = runGitOrErr(repoRoot, "rev-parse --verify --quiet " & treeOid & "^{tree}")
  if r.isErr:
    return err(r.error)
  ok(true)

proc listTreeUniverse*(repoRoot: string; treeOid: string): Result[seq[TreeElement], string] {.
  raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## TreeUniverse(R) — the full recursive ls-tree of the tested tree, from
  ## the git object store ONLY (the working directory is never read).
  if not isHexLen(treeOid, 40):
    return err("semantic_set_derivation: tested tree OID is not 40-hex (fail-closed)")
  let r = runGitOrErr(repoRoot, "ls-tree -r --full-tree -z " & treeOid)
  if r.isErr:
    return err(r.error)
  parseLsTreeZ(r.get)

type
  SemanticSetDerivation* = object
    ## The full derivation outcome — the S digest plus the partition counts
    ## the machine-asserted completeness rests on.
    semanticDigest*: string   ## ⑤ v3 — sha256 over the sorted S record stream
    universeCount*: int       ## |TreeUniverse(R)|
    semanticCount*: int       ## |S|
    excludedCount*: int       ## |N|
    probeTreeOid*: string     ## the probe anchor (out-of-key; provenance only)

proc verifyPartition*(elements: seq[TreeElement]): Result[tuple[semantic: seq[TreeElement],
    excluded: int], string] {.raises: [].} =
  ## 분할 검증 — S ∪ N == TreeUniverse with each path on exactly one side.
  ## Classification is a total function, so the machine assertion is: every
  ## element lands in exactly one class (by construction) and the counts sum
  ## to the universe; the parse layer already rejected duplicate paths, so
  ## overlap is impossible — this proc makes the completeness explicit and
  ## keeps the semantic members in tree order (sorted downstream).
  var semantic: seq[TreeElement] = @[]
  var excluded = 0
  for e in elements:
    case classifyPath(e.path)
    of "excluded": inc excluded
    else: semantic.add(e)
  if semantic.len + excluded != elements.len:
    return err("semantic_set_derivation: partition does not cover the universe " &
      "(S=" & $semantic.len & " N=" & $excluded & " universe=" & $elements.len &
      ") (fail-closed)")
  ok((semantic, excluded))

proc verifyInclusionWitness*(elements: seq[TreeElement];
    witnesses: openArray[string]): Result[bool, string] {.raises: [].} =
  ## 포함-증인 검증 — W ⊆ S ∧ W ∩ N = ∅. Every known input must (a) exist in
  ## the tested tree and (b) classify semantic (never excluded). ANY violation
  ## is a derivation FAIL (the caller falls back to execution — fail-closed),
  ## because an excluded known input would mean the key silently ignores a
  ## real input.
  for w in witnesses:
    var present = false
    var excluded = false
    for e in elements:
      if e.path == w:
        present = true
        excluded = classifyPath(w) == "excluded"
        break
    if not present:
      return err("semantic_set_derivation: known input missing from the tested tree (fail-closed): " & w)
    if excluded:
      return err("semantic_set_derivation: known input '" & w &
        "' is excluded by the no-effect table — W ∩ N ≠ ∅ (fail-closed)")
  ok(true)

proc deriveSemanticSet*(repoRoot: string; treeOid: string;
    witnesses: openArray[string]): Result[SemanticSetDerivation, string] {.
  raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## The full derivation: table self-check → TreeUniverse(R) from git objects
  ## → partition verification → inclusion-witness verification → S digest.
  ## Every step fail-closed; the working directory is never read.
  let tableProblem = validateExclusionTable()
  if tableProblem.len > 0:
    return err(tableProblem)
  let universe =
    try: listTreeUniverse(repoRoot, treeOid)
    except CatchableError as e:
      return err("semantic_set_derivation: universe listing raised (fail-closed): " & e.msg)
  if universe.isErr:
    return err(universe.error)
  if universe.get.len == 0:
    return err("semantic_set_derivation: the tested tree has an empty universe (fail-closed)")
  let partition = verifyPartition(universe.get)
  if partition.isErr:
    return err(partition.error)
  let witness = verifyInclusionWitness(universe.get, witnesses)
  if witness.isErr:
    return err(witness.error)
  ok(SemanticSetDerivation(
    semanticDigest: semanticDigestFromRecords(partition.get.semantic),
    universeCount: universe.get.len,
    semanticCount: partition.get.semantic.len,
    excludedCount: partition.get.excluded,
    probeTreeOid: treeOid))

{.pop.}
