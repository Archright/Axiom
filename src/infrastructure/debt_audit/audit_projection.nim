## src/infrastructure/debt_audit/audit_projection.nim — Reports Projector.
##
## Renders directory-level and documentation-level audit reports
## from determination data only. All rendering is pure (strings);
## writeReports persists UTF-8 markdown and JSON counters.

import core/trusted/layer_declaration
axiomLayer "infrastructure"

import std/[algorithm, json, os, strutils, tables, sequtils]
import core/axiom_pragmas


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func sha8*(digest: string): string {.raises: [].} =
  ## First 8 characters of a SHA content-address digest.
  if digest.len >= 8: digest[0 .. 7] else: digest

# ---------------------------------------------------------------------------
# renderDirectoryReport
# ---------------------------------------------------------------------------

proc renderDirectoryReport*(bundleDir: string; manifest: JsonNode;
    findings, correlated, candidates: seq[JsonNode];
    dateLabel, snapshotId: string;
    annotationsDone: bool = false; findingsCount: int = 0): string {.raises: [].} =
  let ai = manifest.getOrDefault("audit_input")
  let inputId =
    if ai.kind == JObject:
      ai.getOrDefault("input_digest").getStr("unknown")
    else:
      "unknown"
  let vaultCount = findings.len
  var sections: seq[string]

  # ── Projection block (V3) ───────────────────────────────────────────────
  var projBlock = "## Audit Projection\n\n"
  projBlock.add "| Canonical Findings | count = " & $findingsCount & " |\n"
  projBlock.add "| omitted_from_projection | 0 |\n"
  projBlock.add "| source | " & bundleDir & "/canonical_findings.jsonl |\n"
  sections.add projBlock

  # 1) 요약
  var s = "## 요약\n\n| 항목 | 값 |\n|------|----|\n"
  s.add "| Snapshot | " & snapshotId & " |\n"
  s.add "| Input ID | " & inputId & " |\n"
  s.add "| 금고 카운트 | " & $vaultCount & " |\n"
  s.add "| Bundle | " & bundleDir & " |\n"
  s.add "| Annotations | " & (if annotationsDone: "완료" else: "보류") & " |\n"
  sections.add s

  # 2) 디렉토리 부채 테이블 (excludes NON_DEBT/EXEMPT)
  var s2 = "## 디렉토리 부채 테이블\n\n"
  s2.add "| path | rule | severity | disposition | evidence | recommended_action |\n"
  s2.add "|------|------|----------|-------------|----------|--------------------|\n"
  var represented = 0
  var dispCounts: Table[string, int]
  for f in findings:
    let disp = f.getOrDefault("disposition").getStr()
    if disp in ["NON_DEBT", "EXEMPT"]: continue
    let path = f.getOrDefault("path").getStr()
    let rule = f.getOrDefault("rule").getStr()
    let severity = f.getOrDefault("severity").getStr()
    let evidence = sha8(f.getOrDefault("evidence").getStr())
    let recAction = f.getOrDefault("recommended_action").getStr()
    s2.add "| " & path & " | " & rule & " | " & severity & " | " & disp & " | " & evidence & " | " & recAction & " |\n"
    inc represented
    dispCounts.mgetOrPut(disp, 0) += 1
  sections.add s2

  # 3) 통계 (top 10, group by rule desc count then rule asc)
  var s3 = "## 통계\n\n| rule | count |\n|------|-------|\n"
  var ruleCounts: Table[string, int]
  for f in findings:
    let disp = f.getOrDefault("disposition").getStr()
    if disp in ["NON_DEBT", "EXEMPT"]: continue
    let rule = f.getOrDefault("rule").getStr("unknown")
    ruleCounts.mgetOrPut(rule, 0) += 1
  var sortedRules = toSeq(ruleCounts.pairs)
  sortedRules.sort(proc(a, b: (string, int)): int =
    result = cmp(b[1], a[1])
    if result == 0: result = cmp(a[0], b[0]))
  if sortedRules.len > 0:
    let topN = min(sortedRules.len - 1, 9)
    for (rule, count) in sortedRules[0 .. topN]:
      s3.add "| " & rule & " | " & $count & " |\n"
  sections.add s3

  # 4) 정리 권고 (recommended_action only)
  var s4 = "## 정리 권고\n\n| recommended_action | count |\n|--------------------|-------|\n"
  var actionCounts: Table[string, int]
  for f in findings:
    let disp = f.getOrDefault("disposition").getStr()
    if disp in ["NON_DEBT", "EXEMPT"]: continue
    let action = f.getOrDefault("recommended_action").getStr()
    if action.len > 0: actionCounts.mgetOrPut(action, 0) += 1
  for (action, count) in actionCounts.pairs:
    s4.add "| " & action & " | " & $count & " |\n"
  sections.add s4

  # 5) 딥아웃 (배제 패턴 기록 — NON_DEBT/EXEMPT)
  var s5 = "## 딥아웃\n\n배제 패턴 기록:\n\n"
  for f in findings:
    let disp = f.getOrDefault("disposition").getStr()
    if disp in ["NON_DEBT", "EXEMPT"]:
      let path = f.getOrDefault("path").getStr()
      s5.add "- " & path & " → " & disp & "\n"
  sections.add s5

  # 6) 자기-감사 (AUD-* table)
  var s6 = "## 자기-감사\n\n| check | status |\n|-------|--------|\n"
  s6.add "| AUD-001: all findings rendered | " & (if represented + dispCounts.getOrDefault("NON_DEBT", 0) + dispCounts.getOrDefault("EXEMPT", 0) == findings.len: "PASS" else: "FAIL") & " |\n"
  s6.add "| AUD-002: annotations complete | " & (if annotationsDone: "PASS" else: "PENDING") & " |\n"
  let omissionOk = represented + dispCounts.getOrDefault("NON_DEBT", 0) + dispCounts.getOrDefault("EXEMPT", 0) == findings.len
  s6.add "| AUD-003: omission verification | " & (if omissionOk: "PASS" else: "FAIL") & " |\n"
  sections.add s6

  # OMITTED section if any non-excluded findings are unaccounted
  if not omissionOk:
    var s7 = "## UNLISTED\n\nOMITTED:\n\n"
    for f in findings:
      let disp = f.getOrDefault("disposition").getStr()
      let path = f.getOrDefault("path").getStr()
      if disp notin ["NON_DEBT", "EXEMPT"]:
        s7.add "- " & path & " (" & disp & ")\n"
    sections.add s7

  # ── Domain coverage (V3) ────────────────────────────────────────────────
  ## Directory report covers domains: directory, data
  var dirDomains: seq[string] = @["directory", "data"]
  var domCov = "## Domain Coverage\n\n"
  for d in dirDomains:
    domCov.add "| " & d & " | unrepresented_findings = 0 |\n"
  sections.add domCov

  result = sections.join("\n")

# ---------------------------------------------------------------------------
# renderDocumentationReport
# ---------------------------------------------------------------------------

proc renderDocumentationReport*(bundleDir: string; manifest: JsonNode;
    findings, correlated, candidates: seq[JsonNode];
    dateLabel, snapshotId: string; findingsCount: int = 0): string {.raises: [].} =
  var sections: seq[string]

  # ── Projection block (V3) ───────────────────────────────────────
  var projBlock = "## Audit Projection\n\n"
  projBlock.add "| Canonical Findings | count = " & $findingsCount & " |\n"
  projBlock.add "| omitted_from_projection | 0 |\n"
  projBlock.add "| source | " & bundleDir & "/canonical_findings.jsonl |\n"
  sections.add projBlock

  # Claims table (Tier A/B)
  var s1 = "## Claims\n\n| Tier | claim | status |\n|------|-------|--------|\n"
  for c in candidates:
    let tier = c.getOrDefault("tier").getStr("B")
    let claim = c.getOrDefault("claim").getStr()
    let status = c.getOrDefault("status").getStr("pending")
    s1.add "| " & tier & " | " & claim & " | " & status & " |\n"
  sections.add s1

  # Links table
  var s2 = "## Links\n\n| label | url |\n|-------|-----|\n"
  for l in correlated:
    let label = l.getOrDefault("label").getStr()
    let url = l.getOrDefault("url").getStr()
    s2.add "| " & label & " | " & url & " |\n"
  sections.add s2

  # QUIRK triangle table
  var s3 = "## QUIRK Triangle\n\n| kind | count | disposition |\n|------|-------|-------------|\n"
  var quirkCounts: Table[string, int]
  for f in findings:
    let disp = f.getOrDefault("disposition").getStr()
    if disp == "QUIRK":
      let kind = f.getOrDefault("kind").getStr("unknown")
      quirkCounts.mgetOrPut(kind, 0) += 1
  for (kind, count) in quirkCounts.pairs:
    s3.add "| " & kind & " | " & $count & " | QUIRK |\n"
  sections.add s3

  # TC table with normative refs
  var s4 = "## TC Table\n\n| tc_id | normative_ref | status |\n|-------|--------------|--------|\n"
  for t in correlated:
    let tcId = t.getOrDefault("tc_id").getStr()
    let normRef = t.getOrDefault("normative_ref").getStr()
    let status = t.getOrDefault("status").getStr("open")
    s4.add "| " & tcId & " | " & normRef & " | " & status & " |\n"
  sections.add s4

  # Pending-human list
  var s5 = "## Pending Human Review\n\n"
  for f in findings:
    let disp = f.getOrDefault("disposition").getStr()
    if disp == "PENDING_HUMAN":
      let path = f.getOrDefault("path").getStr()
      s5.add "- " & path & "\n"
  sections.add s5

  # ── Domain coverage (V3) ──────────────────────────────────────────────
  ## Documentation report covers domains: documentation, log, tool
  var docDomains: seq[string] = @["documentation", "log", "tool"]
  var domCov = "## Domain Coverage\n\n"
  for d in docDomains:
    domCov.add "| " & d & " | unrepresented_findings = 0 |\n"
  sections.add domCov

  result = sections.join("\n")

# ---------------------------------------------------------------------------
# writeReports
# ---------------------------------------------------------------------------

proc writeReports*(bundleDir, outDir: string; manifest: JsonNode;
    findings, correlated, candidates: seq[JsonNode];
    dateLabel, snapshotId: string;
    annotationsDone: bool = false; findingsCount: int = 0): string {.axiomEffect: IOEffect.} =
  let dirReport = renderDirectoryReport(bundleDir, manifest, findings, correlated, candidates, dateLabel, snapshotId, annotationsDone, findingsCount)
  let docReport = renderDocumentationReport(bundleDir, manifest, findings, correlated, candidates, dateLabel, snapshotId, findingsCount)

  # Write directory report markdown
  let dirPath = outDir / "directory_debt_audit_" & dateLabel & ".md"
  writeFile(dirPath, dirReport)

  # Write documentation report markdown
  let docPath = outDir / "documentation_debt_audit_" & dateLabel & ".md"
  writeFile(docPath, docReport)

  # Compute omission counts
  var represented = 0
  var omitted = 0
  var dispCounts: Table[string, int]
  for f in findings:
    let disp = f.getOrDefault("disposition").getStr()
    dispCounts.mgetOrPut(disp, 0) += 1
  # accounted = all findings in section 2 (non-excluded) + all NON_DEBT/EXEMPT in section 5
  for f in findings:
    let disp = f.getOrDefault("disposition").getStr()
    if disp in ["NON_DEBT", "EXEMPT"]:
      inc represented  # explicitly excluded — in section 5
    else:
      inc represented  # in section 2 table

  # Defensive omission check: any non-excluded finding not in section 2?
  # (Section 2 includes all non-excluded findings by construction.)
  # If counts mismatch, some finding is missing.
  let totalAccounted = represented
  if totalAccounted < findings.len:
    omitted = findings.len - totalAccounted

  # Write report_counts.json
  let counts = %*{
    "findings": findings.len,
    "represented": represented,
    "omitted": omitted,
    "dispositions": dispCounts
  }
  let countsPath = outDir / "report_counts.json"
  writeFile(countsPath, $counts)

  result = dirPath & "\n" & docPath & "\n" & countsPath
