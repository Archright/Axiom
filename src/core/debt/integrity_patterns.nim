## src/core/debt/integrity_patterns.nim — StaticEvidenceCollector (Phase 3)
##
## A single lexical scanner that detects 7 product-integrity patterns in Nim
## source text and emits PatternObservation[] + IntegrityPolicyEvaluation[].
##
## Key design: detection is strictly separated from judgment.
##   pattern detected → PatternObservation (evidence, NOT debt)
##   pattern + context  → IntegrityPolicyEvaluation (verdict, NOT debt)
##   pattern → DebtObservation (for evidence journal, NOT debt creation)
##
## This is LEXICAL Level-1+Level-2 surface detection — keyword scanning on
## stripped source lines. It does NOT perform AST analysis or CFG traversal.
##
## Public API:
##   staticCollector          — construct an eckStatic EvidenceCollector
##   detectIntegrityPatterns  — scan source text for integrity-pattern keywords
##   evaluateIntegrityPolicy  — deterministic policy predicate → verdict
##   toDebtObservation        — map observation → okAstPattern DebtObservation

import core/trusted/layer_declaration
axiomLayer "domain"

import std/[strutils, options]
import checksums/sha2
import core/types/debt_types
import core/axiom_pragmas
import core/debt/debt_identity

# ---------------------------------------------------------------------------
# Centralized keyword → pattern mapping (const for policy-hash reference)
# ---------------------------------------------------------------------------
# Order matters: more specific multi-word entries first so they are
# matched before their shorter substrings.

const IntegrityKeywordTable*: seq[(string, ObservedIntegrityPattern)] = @[
  ("github-workflow skip", oipSkip),
  ("certified exempt",    oipExemption),
  ("manual override",     oipManualOverride),
  ("shadow execution",    oipUncertifiedPath),
  ("best-effort",         oipUncertifiedPath),
  ("bypass",              oipBypass),
  ("AXIOM_BYPASS",        oipBypass),
  ("EMERGENCY_NO_VERIFY", oipBypass),
  ("skip",                oipSkip),
  ("skipped",             oipSkip),
  ("exemption",           oipExemption),
  ("exempt",              oipExemption),
  ("fallback",            oipFallback),
  ("noncanonical",        oipNonCanonical),
  ("manual_override",     oipManualOverride),
  ("uncertified",         oipUncertifiedPath),
]

# ---------------------------------------------------------------------------
# Pure helpers
# ---------------------------------------------------------------------------

{.push raises: [].}

func stripLineComment*(line: string): string =
  ## Strip a Nim line comment (# ...) preserving # inside strings/chars.
  var inStr = false
  var inCh = false
  var escaped = false
  var i = 0
  while i < line.len:
    let c = line[i]
    if escaped:
      escaped = false
      inc i
      continue
    case c
    of '\\':
      if inStr or inCh:
        escaped = true
    of '"':
      if not inCh:
        inStr = not inStr
    of '\'':
      if not inStr:
        inCh = not inCh
    of '#':
      if not inStr and not inCh:
        return line[0 ..< i]
    else:
      discard
    inc i
  line

func keywordForLine*(line: string): Option[ObservedIntegrityPattern] {.axiomDecision(
  id = "DECISION-0654",
  reason = "Map a stripped source line to an ObservedIntegrityPattern via the centralized keyword table",
  adr = "docs/adr/0001-fail-closed-result-type.md",
  introduced = "v33"
).} =
  ## Map a stripped source line to an ObservedIntegrityPattern via the
  ## centralized keyword table. First match wins (table order).
  let lower = line.toLowerAscii()
  for entry in IntegrityKeywordTable:
    if lower.contains(entry[0].toLowerAscii()):
      return some(entry[1])
  none(ObservedIntegrityPattern)

func staticCollector*(detectorVersion, ruleSetHash: string): EvidenceCollector =
  ## Construct a static (lexical) EvidenceCollector.
  ## detectorId is fixed so every run from the same binary shares identity.
  result = EvidenceCollector(
    kind: eckStatic,
    detectorId: "static_evidence_collector_v1",
    detectorVersion: detectorVersion,
    ruleSetHash: ruleSetHash,
  )

func detectIntegrityPatterns*(source: string; collector: EvidenceCollector): seq[PatternObservation] =
  ## Lexical Level-1+Level-2 scanner: iterate source lines, strip comments,
  ## skip blanks, map keywords → PatternObservation.
  ##
  ## Does NOT parse AST or CFG — purely lexical keyword matching.
  let subj = collector.ruleSetHash
  var idx = 0
  for rawLine in source.splitLines:
    let stripped = stripLineComment(rawLine).strip()
    if stripped.len == 0:
      continue
    let kwOpt = keywordForLine(stripped)
    if kwOpt.isNone:
      inc idx
      continue
    let pat = kwOpt.get()
    let semId = $pat
    result.add(PatternObservation(
      id: sha256Ref("pattern:", subj & "\x1e" & semId & "\x1e" & $idx),
      kind: okAstPattern,
      pattern: pat,
      subject: subj,
      semanticIdentity: semId,
      payload: stripped,
      source: collector.detectorId & "/" & $pat,
      evidenceIds: @[],
    ))
    inc idx

func evaluateIntegrityPolicy*(p: PatternObservation; declared: bool; assuranceTier: string; evidenceIds: seq[string]): IntegrityPolicyEvaluation =
  ## Deterministic policy predicate: pattern + context + evidence → verdict.
  ##
  ## Rules (first match wins):
  ##   1. declared AND assuranceTier preserved (non-empty, not "none")
  ##      → ipvAcceptable
  ##   2. evidenceIds.len == 0 → ipvUnverified
  ##   3. p.pattern in {oipBypass,oipSkip,oipUncertifiedPath,oipManualOverride}
  ##      AND NOT declared → ipvViolation
  ##   4. otherwise → ipvWarning
  ##
  ## A detected pattern NEVER automatically becomes a Debt here.

  let hardPatterns = {oipBypass, oipSkip, oipUncertifiedPath, oipManualOverride}

  if declared and assuranceTier.len > 0 and assuranceTier != "none":
    return IntegrityPolicyEvaluation(
      decisionId: sha256Ref("policy:", p.subject & "\x1e" & p.payload & "\x1e" & $ipvAcceptable),
      policyDigest: sha256Ref("policy_digest:", assuranceTier & "/declared"),
      candidateId: computeCandidateId(p.subject, p.semanticIdentity),
      pattern: p.pattern,
      verdict: ipvAcceptable,
      evidenceIds: evidenceIds,
      rationale: "Declared under preserved assurance tier " & assuranceTier,
    )

  if evidenceIds.len == 0:
    return IntegrityPolicyEvaluation(
      decisionId: sha256Ref("policy:", p.subject & "\x1e" & p.payload & "\x1e" & $ipvUnverified),
      policyDigest: sha256Ref("policy_digest:", "no-evidence"),
      candidateId: computeCandidateId(p.subject, p.semanticIdentity),
      pattern: p.pattern,
      verdict: ipvUnverified,
      evidenceIds: @[],
      rationale: "No evidence available to judge this pattern",
    )

  if p.pattern in hardPatterns and not declared:
    return IntegrityPolicyEvaluation(
      decisionId: sha256Ref("policy:", p.subject & "\x1e" & p.payload & "\x1e" & $ipvViolation),
      policyDigest: sha256Ref("policy_digest:", "hard-pattern-undeclared"),
      candidateId: computeCandidateId(p.subject, p.semanticIdentity),
      pattern: p.pattern,
      verdict: ipvViolation,
      evidenceIds: evidenceIds,
      rationale: "Hard integrity pattern without declaration",
    )

  # Fallback: warning
  IntegrityPolicyEvaluation(
    decisionId: sha256Ref("policy:", p.subject & "\x1e" & p.payload & "\x1e" & $ipvWarning),
    policyDigest: sha256Ref("policy_digest:", "warning-fallback"),
    candidateId: computeCandidateId(p.subject, p.semanticIdentity),
    pattern: p.pattern,
    verdict: ipvWarning,
    evidenceIds: evidenceIds,
    rationale: "Pattern observed; severity below violation threshold",
  )

func toDebtObservation*(p: PatternObservation; snapshotId: string; observedAt, toolchainContext: string): DebtObservation =
  ## Map a PatternObservation into an okAstPattern DebtObservation for
  ## appending to the evidence journal later.
  ##
  ## This does NOT create a Debt — it creates an Observation record that
  ## can be stored alongside other evidence. Promotion to Debt requires
  ## a separate policy decision (禁止 #1).
  DebtObservation(
    observationId: sha256Ref("debt_obs:", p.id),
    kind: okAstPattern,
    subject: p.subject,
    semanticIdentity: p.semanticIdentity,
    snapshotId: snapshotId,
    source: p.source,
    payload: p.payload,
    observedAt: observedAt,
    toolchainContext: toolchainContext,
  )

{.pop.}
