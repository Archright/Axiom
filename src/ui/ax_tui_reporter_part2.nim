import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}

import ../core/trusted/axiom_pragmas
import cli/cli_types
import cli/report_format
import cli/report_layout
import cli/report_render
import core/utils/constants
import std/json
import std/strformat
import std/strutils
import std/terminal
import std/unicode
import ui/ax_tui_reporter_part1
import ui/notion_semantic_mapper
proc detectEngineName*(entry: JsonNode): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  result = "unknown"
  let sp = entry{"semanticProof"}
  if not sp.isNil and sp.kind == JObject:
    let up = sp{"universalPipeline"}
    if not up.isNil and up.kind == JObject:
      let prov = up{"provenance"}
      if not prov.isNil and prov.kind == JObject:
        let eng = prov{"engine"}
        if not eng.isNil and eng.kind == JString:
          return eng.getStr()
    let eng = sp{"engine"}
    if not eng.isNil and eng.kind == JString:
      return eng.getStr()

  ## axiom-smt: (assert true)
  ## axiom-lean: reportNode_object_or_empty
proc parseEntryList*(reportNode: JsonNode; result: var AxProofReport) {.axiom, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if not (reportNode.hasKey(entriesKey) and reportNode[entriesKey].kind == JArray):
    return
  var attemptedOrdinal = 0
  for entry in reportNode[entriesKey].elems:
    if entry.kind != JObject: continue
    let statusStr =
      if entry.hasKey(statusKey) and entry[statusKey].kind == JString:
        entry[statusKey].getStr()
      else: "unknown"
    let status = parseAxProofStatus(statusStr)
    let label =
      if entry.hasKey(labelKey) and entry[labelKey].kind == JString:
        entry[labelKey].getStr()
      else: "unknown"
    let attempted =
      if entry.hasKey("attempted") and entry["attempted"].kind == JBool:
        entry["attempted"].getBool()
      else: status != axProofUnattempted
    if attempted:
      inc attemptedOrdinal
      result.attemptedEntryIds.add((label, parseEntryDisplayId(entry, attemptedOrdinal)))
    if status == axProofUnattempted:
      result.entries.add(AxProofEntry(
        id: 0, label: label, status: status, engine: "",
        depth: 0, impactIndex: 0, premises: 0
      ))
      continue
    let engine = detectEngineName(entry)
    let depth =
      if entry.hasKey(dependencyDepthKey) and entry[dependencyDepthKey].kind in {JInt, JFloat}:
        entry[dependencyDepthKey].getInt()
      else: 0
    let impact =
      if entry.hasKey(impactIndexKey) and entry[impactIndexKey].kind in {JInt, JFloat}:
        entry[impactIndexKey].getInt()
      else: 0
    let premises =
      if entry.hasKey(premiseCountKey) and entry[premiseCountKey].kind in {JInt, JFloat}:
        entry[premiseCountKey].getInt()
      else: 0
    result.entries.add(AxProofEntry(
      id: parseEntryDisplayId(entry, attemptedOrdinal),
      label: label, status: status, engine: engine,
      depth: depth, impactIndex: impact, premises: premises
    ))

  ## axiom-smt: (assert true)
  ## axiom-lean: reportNode_object_or_empty
proc parseAxProofReportFromJson*(reportNode: JsonNode): AxProofReport {.axiom, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Wave Y: Dispatch to extracted parse helpers (tkStructuralDecomp)
  parseSummaryFields(reportNode, result.summary)
  parseWorkflowFields(reportNode, result.summary)
  parseReproofRequired(reportNode, result)
  parseEntryList(reportNode, result)
  if reportNode.hasKey(shortcutStateKey) and reportNode[shortcutStateKey].kind == JString:
    result.summary.shortcutState = reportNode[shortcutStateKey].getStr()
func renderTuiHeader(summary: AxProofSummary; termWidth: int; useColor: bool): seq[string] =
  let vkdVal = if summary.vkdFixed4.len > 0: summary.vkdFixed4 else: "0.0000"
  result.add(renderEnterpriseHeaderLines(vkdVal, useColor))
  result.add("")
  let targetDisplay = extractRelativeTarget(summary.sourceRoot, summary.target)
  let config = createLayoutConfig(termWidth)
  let truncatedTarget = ellipsizePath(targetDisplay, config.maxLabelWidth)
  if useColor:
    result.add(applyAnsiBold(applyAnsiColor("Axiom Proof Report", AnsiCyan, true), true))
    result.add("  Target: " & applyAnsiDim(truncatedTarget, true))
    result.add("  Timestamp: " & applyAnsiDim(summary.timestamp, true))
  else:
    result.add("Axiom Proof Report")
    result.add("  Target: " & truncatedTarget)
    result.add("  Timestamp: " & summary.timestamp)
  result.add("")
func renderTuiSummaryBlock(summary: AxProofSummary; termWidth: int; useColor: bool): seq[string] =
  let total = summary.totalNodes       
  let verified = summary.verified      
  let failed = summary.counterExamples + summary.vacuousContradictions
  let timeMs = summary.totalWallTimeMs
  let timeStr = formatTimeField(timeMs)
  let verifiedPct = if total > 0: (verified * 100) div total else: 0
  let failedPct = if total > 0: (failed * 100) div total else: 0

  let widths = computeRowWidthsFromSummary(
    total, verified, verifiedPct, failed, failedPct, timeStr,
    summary.attemptedNodes, summary.unattempted, summary.timedOut, summary.cacheHits
  )
  let topBorder = renderUnicodeBoxTop(widths)
  let bottomBorder = renderUnicodeBoxBottom(widths)
  let separator = renderUnicodeBoxSeparator(widths)

  result.add(topBorder)
  let col1 = alignLeft("Total: " & $total, widths[0])
  let col2 = alignLeft("Verified: " & $verified & " (" & $verifiedPct & "%)", widths[1])
  let col3 = alignLeft("Failed: " & $failed & " (" & $failedPct & "%)", widths[2])
  let col4 = alignLeft("Time: " & timeStr, widths[3])
  result.add(UnicodeBoxVertical & col1 & UnicodeBoxVertical & col2 & UnicodeBoxVertical & col3 & UnicodeBoxVertical & col4 & UnicodeBoxVertical)
  result.add(separator)

  let attemptedCol = alignLeft("Attempted: " & $summary.attemptedNodes, widths[0])
  let unattemptedCol = alignLeft("Unattempted: " & $summary.unattempted, widths[1])
  let timedOutCol = alignLeft("TimedOut: " & $summary.timedOut, widths[2])
  let cacheCol = alignLeft("CacheHits: " & $summary.cacheHits, widths[3])
  result.add(UnicodeBoxVertical & attemptedCol & UnicodeBoxVertical & unattemptedCol & UnicodeBoxVertical & timedOutCol & UnicodeBoxVertical & cacheCol & UnicodeBoxVertical)
  result.add(bottomBorder)
  result.add("")
func renderTuiCertificateBlock(summary: AxProofSummary; useColor: bool = false): seq[string] =
  if summary.certificateAsiFixed4.len == 0:
    return @[]
  let verdict =
    if summary.totalNodes == 0: "EMPTY"
    elif summary.verified > 0 and summary.counterExamples == 0: "PASSED"
    elif summary.verified > 0 and summary.counterExamples > 0: "DEGRADED"
    else: "FAILED"
  result = renderIntegrityCertificateLines(summary.certificateAsiFixed4, verdict)
func computeDisplayBadgeWidth(
  criticalEntries: seq[AxProofEntry];
  warningEntries: seq[AxProofEntry];
  successEntries: seq[AxProofEntry];
  reproofRequired: seq[tuple[label: string, reason: string]];
  unattemptedEntries: seq[AxProofEntry] = @[];
  unknownEntries: seq[AxProofEntry] = @[];
  maxSuccessEntries: int = 5
): int =
  for entry in criticalEntries:
    result = max(result, displayWidth(entryStatusLabel(entry.status)))
  for entry in warningEntries:
    result = max(result, displayWidth(entryStatusLabel(entry.status)))
  let successDisplayCount =
    if maxSuccessEntries > 0:
      min(successEntries.len, maxSuccessEntries)
    else:
      successEntries.len
  for i in 0..<successDisplayCount:
    result = max(result, displayWidth(entryStatusLabel(successEntries[i].status)))
  for item in reproofRequired:
    result = max(result, displayWidth(item.reason))
  for entry in unattemptedEntries:
    result = max(result, displayWidth(entryStatusLabel(entry.status)))
  for entry in unknownEntries:
    result = max(result, displayWidth(entryStatusLabel(entry.status)))
func findEntryDisplayId(entries: seq[AxProofEntry]; label: string): int =
  for entry in entries:
    if entry.label == label:
      return entry.id
  result = 0
func findAttemptedEntryDisplayId(entries: seq[tuple[label: string, id: int]]; label: string): int =
  for entry in entries:
    if entry.label == label:
      return entry.id
  result = 0
func renderTuiSection(
  title: string;
  count: int;
  entries: seq[AxProofEntry];
  colorCode: string;
  labelWidth: int;
  badgeWidth: int;
  useColor: bool;
  maxEntries: int = 0
): seq[string] =
  if entries.len == 0:
    return @[]
  let displayCount = if maxEntries > 0: min(entries.len, maxEntries) else: entries.len
  let headerText = formatSectionTitle(title, count)
  let header =
    if useColor:
      applyAnsiBold(applyAnsiColor(headerText, colorCode, true), true)
    else:
      headerText
  result.add(header)
  let maxIdWidth = 4
  for i in 0..<displayCount:
    let entry = entries[i]
    let idStr = if entry.id > 0: fmt"#{entry.id:02d}" else: "  "
    let idField = alignLeft(idStr, maxIdWidth)
    let labelDisplay = formatEntryLabelField(entry.label, labelWidth)
    let statusLabel = entryStatusLabel(entry.status)
    let statusField = unicode.alignLeft(statusLabel, badgeWidth)
    if useColor:
      result.add(fmt"  {applyAnsiDim(idField, true)}{labelDisplay} [{applyAnsiColor(statusField, colorCode, true)}]")
    else:
      result.add(fmt"  {idField}{labelDisplay} [{statusField}]")
  if maxEntries > 0 and entries.len > maxEntries:
    let remaining = entries.len - maxEntries
    if useColor:
      result.add(applyAnsiDim(fmt"  ... and {remaining} more", true))
    else:
      result.add(fmt"  ... and {remaining} more")
  result.add("")
func renderReproofSection(
  entries: seq[AxProofEntry];
  attemptedEntryIds: seq[tuple[label: string, id: int]];
  reproofRequired: seq[tuple[label: string, reason: string]];
  labelWidth: int;
  badgeWidth: int;
  useColor: bool
): seq[string] =
  if reproofRequired.len == 0:
    return @[]
  let headerText = formatSectionTitle("WARNING", reproofRequired.len) & " - Requires Reproof"
  let header =
    if useColor:
      applyAnsiBold(applyAnsiColor(headerText, AnsiYellow, true), true)
    else:
      headerText
  result.add(header)
  let maxIdWidth = 4
  for item in reproofRequired:
    let visibleEntryId = findEntryDisplayId(entries, item.label)
    let matchedId =
      if visibleEntryId > 0:
        visibleEntryId
      else:
        findAttemptedEntryDisplayId(attemptedEntryIds, item.label)
    let idField =
      if matchedId > 0:
        alignLeft(fmt"#{matchedId:02d}", maxIdWidth)
      else:
        alignLeft("", maxIdWidth)
    let labelDisplay = formatEntryLabelField(item.label, labelWidth)
    let reasonField = unicode.alignLeft(item.reason, badgeWidth)
    if useColor:
      result.add(fmt"  {applyAnsiDim(idField, true)}{labelDisplay} [{applyAnsiColor(reasonField, AnsiYellow, true)}]")
    else:
      result.add(fmt"  {idField}{labelDisplay} [{reasonField}]")
  result.add("")

## Render Tui Report With Width.
func renderTuiReportWithWidth*(report: AxProofReport; termWidth: int; useColor: bool  = true): seq[string] =
  result = renderTuiHeader(report.summary, termWidth, useColor)
  let summaryLines = renderTuiSummaryBlock(report.summary, termWidth, useColor)
  result.add(summaryLines)
  var criticalEntries: seq[AxProofEntry] = @[]
  var warningEntries: seq[AxProofEntry] = @[]
  var successEntries: seq[AxProofEntry] = @[]
  var unattemptedEntries: seq[AxProofEntry] = @[]
  var unknownEntries: seq[AxProofEntry] = @[]
  for entry in report.entries:
    case entry.status
    of axProofUnverifiable, axProofCounterExampleFound, axProofTimedOut, axProofVacuousContradiction:
      criticalEntries.add(entry)
    of axProofBlocked:
      warningEntries.add(entry)
    of axProofVerified:
      successEntries.add(entry)
    of axProofUnattempted:
      unattemptedEntries.add(entry)
    of axProofUnknown:
      unknownEntries.add(entry)
  var visibleLabels: seq[string] = @[]
  for e in criticalEntries: visibleLabels.add(e.label)
  for e in warningEntries: visibleLabels.add(e.label)
  for e in successEntries: visibleLabels.add(e.label)
  for e in unattemptedEntries: visibleLabels.add(e.label)
  for e in unknownEntries: visibleLabels.add(e.label)

  var filteredReproof: seq[tuple[label: string, reason: string]] = @[]
  for item in report.reproofRequired:
    if item.label notin visibleLabels:
      filteredReproof.add(item)

  let config = createLayoutConfig(termWidth)
  let maxAllowedLabelWidth = config.maxLabelWidth - 20
  var sharedLabelWidth = 20
  sharedLabelWidth = max(sharedLabelWidth, computeDisplayLabelWidth(criticalEntries, maxAllowedLabelWidth, maxEntries = 5))
  sharedLabelWidth = max(sharedLabelWidth, computeDisplayLabelWidth(warningEntries, maxAllowedLabelWidth, maxEntries = 5))
  sharedLabelWidth = max(sharedLabelWidth, computeDisplayLabelWidth(successEntries, maxAllowedLabelWidth, maxEntries = 5))
  sharedLabelWidth = max(sharedLabelWidth, computeDisplayLabelWidth(unattemptedEntries, maxAllowedLabelWidth, maxEntries = 5))
  sharedLabelWidth = max(sharedLabelWidth, computeDisplayLabelWidth(unknownEntries, maxAllowedLabelWidth, maxEntries = 5))
  var reproofLabelWidth2 = 20
  for item in filteredReproof:
    let w = displayWidth(item.label)
    if w > reproofLabelWidth2:
      reproofLabelWidth2 = min(w, maxAllowedLabelWidth)
  sharedLabelWidth = max(sharedLabelWidth, reproofLabelWidth2)
  let sharedBadgeWidth =
    max(1, computeDisplayBadgeWidth(criticalEntries, warningEntries, successEntries, filteredReproof, unattemptedEntries, unknownEntries))
  let criticalLines = renderTuiSection("CRITICAL", criticalEntries.len, criticalEntries, AnsiRed, sharedLabelWidth, sharedBadgeWidth, useColor, maxEntries = 5)
  result.add(criticalLines)
  let reproofLines = renderReproofSection(report.entries, report.attemptedEntryIds, filteredReproof, sharedLabelWidth, sharedBadgeWidth, useColor)
  result.add(reproofLines)
  let warningLines = renderTuiSection("WARNING", warningEntries.len, warningEntries, AnsiYellow, sharedLabelWidth, sharedBadgeWidth, useColor, maxEntries = 5)
  result.add(warningLines)
  let successLines = renderTuiSection("VERIFIED", successEntries.len, successEntries, AnsiGreen, sharedLabelWidth, sharedBadgeWidth, useColor, maxEntries = 5)
  result.add(successLines)
  let unattemptedLines = renderTuiSection("UNATTEMPTED", unattemptedEntries.len, unattemptedEntries, AnsiCyan, sharedLabelWidth, sharedBadgeWidth, useColor, maxEntries = 5)
  result.add(unattemptedLines)
  let unknownLines = renderTuiSection("UNKNOWN", unknownEntries.len, unknownEntries, AnsiDim, sharedLabelWidth, sharedBadgeWidth, useColor, maxEntries = 5)
  result.add(unknownLines)
  let stateFileDisplay = ellipsizePath(report.summary.stateFile, config.maxLabelWidth)
  if useColor:
    result.add(applyAnsiDim("State: " & stateFileDisplay, true))
    result.add(applyAnsiDim("Use 'ax inspect <ID>' for details", true))
  else:
    result.add("State: " & stateFileDisplay)
    result.add("Use 'ax inspect <ID>' for details")
  ## Notion Spec v0.3.7 — 3 Final Gates Summary
  result.add("")
  result.add(renderGateSectionHeader(ngkSieve))
  result.add("  Verified: " & $successEntries.len & " | Unverifiable: " & $criticalEntries.len)
  result.add(renderGateSectionHeader(ngkDiagnosis))
  result.add("  Counter-examples: " & $report.summary.counterExamples & " | Vacuous: " & $report.summary.vacuousContradictions & " | Timed-out: " & $report.summary.timedOut)
  result.add(renderGateSectionHeader(ngkGuidance))
  result.add("  Blocked: " & $warningEntries.len & " | Unattempted: " & $unattemptedEntries.len)

  let certificateLines = renderTuiCertificateBlock(report.summary, useColor)
  if certificateLines.len > 0:
    result.add("")
    result.add(certificateLines)

## Render Tui Report.
proc renderTuiReport*(report: AxProofReport; useColor: bool = true): seq[string] =
  renderTuiReportWithWidth(report, terminalWidth(), useColor)
{.pop.}
