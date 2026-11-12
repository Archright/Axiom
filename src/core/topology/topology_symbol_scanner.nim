import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

import std/strutils
import std/tables
import core/crypto/hash_kernel
import core/topology/topology_types
import core/topology/topology_parser
import core/utils/file_utils
import core/sorter/sorter_core
import ../../core/trusted/axiom_pragmas

# Auto-split from topology_engine.nim — symbol construction
func isBoundarySymbol(modulePath: string; functionName: string; exported: bool): bool =
  let normalized = normalizePathSeparators(modulePath).toLowerAscii()
  result = exported or
    normalized.find("/cli/") >= 0 or
    normalized.find("/mcp/") >= 0 or
    functionName.startsWith("cmd")

  ## axiom-smt: (assert (and (>= (seq.len symbols) 0) (>= (str.len modulePath) 0) (and (>= declarationLine -9223372036854775808) (<= declarationLine 9223372036854775807)) (or (= parsed_found true) (= parsed_found false)) (>= (str.len parsed_functionName) 0) (or (= parsed_exported true) (= parsed_exported false)) (and (>= parsed_indent -9223372036854775808) (<= parsed_indent 9223372036854775807)) (>= (str.len parsed_bodyFragment) 0) (and (>= parsed_initialBraceDepth -9223372036854775808) (<= parsed_initialBraceDepth 9223372036854775807)) (or (= parsed_braceSeen true) (= parsed_braceSeen false)) (or (= parsed_found true) (= parsed_found false)) (or (= parsed_exported true) (= parsed_exported false)) (or (= parsed_braceSeen true) (= parsed_braceSeen false))))
  ## axiom-lean: symbols.size ≥ 0 ∧ modulePath.length ≥ 0 ∧ declarationLine ≥ -9223372036854775808 ∧ declarationLine ≤ 9223372036854775807 ∧ parsed_found = true ∨ parsed_found = false ∧ parsed_functionName.length ≥ 0 ∧ parsed_exported = true ∨ parsed_exported = false ∧ parsed_indent ≥ -9223372036854775808 ∧ parsed_indent ≤ 9223372036854775807 ∧ parsed_bodyFragment.length ≥ 0 ∧ parsed_initialBraceDepth ≥ -9223372036854775808 ∧ parsed_initialBraceDepth ≤ 9223372036854775807 ∧ parsed_braceSeen = true ∨ parsed_braceSeen = false ∧ parsed_found = true ∨ parsed_found = false ∧ parsed_exported = true ∨ parsed_exported = false ∧ parsed_braceSeen = true ∨ parsed_braceSeen = false
func beginTopologySymbol(
  symbols: var seq[TopologySymbol];
  modulePath: string;
  declarationLine: int;
  parsed: DeclParseResult
) {.axiomTryImpl.} =
  let fingerprintInput = modulePath & "||" & parsed.functionName & "||" & parsed.signatureText
  let defFingerprint = sha256Hex(fingerprintInput)
  symbols.add(TopologySymbol(
    modulePath: modulePath,
    functionName: parsed.functionName,
    nodeType: parsed.nodeType,
    nodeId: sorterNodeId(modulePath & "::" & parsed.functionName),
    declarationLine: declarationLine,
    bodyStartLine: declarationLine,
    bodyEndLine: declarationLine,
    exported: parsed.exported,
    boundaryKind:
      (if isBoundarySymbol(modulePath, parsed.functionName, parsed.exported):
        topologyBoundaryInterface
      else:
        topologyBoundaryNone),
    rawCallTargets: deduplicateStrings(extractCallTargets(parsed.bodyFragment)),
    branchCount: countControlSignals(parsed.bodyFragment),
    nestingDepth: 0,
    lineSpan: 1,
    definitionFingerprint: defFingerprint
  ))

## Scan Topology Source.
  ## axiom-smt: (assert ast_parse_failed_isolated)
  ## axiom-lean: ast_parse_failed_isolated
func scanTopologySource*(modulePath: string; sourceCode: string): seq[TopologySymbol] {.axiomTryImpl.} =
  let lines = sourceCode.splitLines()
  var activeIdx = -1
  var activeIndent = 0
  var activeScopeKind = topologyScopeIndent
  var activeBraceDepth = 0
  var activeBraceSeen = false
  for lineIdx, rawLine in lines:
    let lineNo = lineIdx + 1
    let parsed = parseDeclaration(rawLine, modulePath.endsWith(".nim"))
    if activeIdx >= 0 and parsed.found:
      let mustClose =
        (activeScopeKind == topologyScopeIndent and parsed.indent <= activeIndent) or
        (activeScopeKind == topologyScopeBrace and activeBraceSeen and activeBraceDepth <= 0)
      if mustClose:
        result[activeIdx].bodyEndLine = lineNo - 1
        result[activeIdx].lineSpan = normalizeLineSpan(result[activeIdx].bodyStartLine, result[activeIdx].bodyEndLine)
        activeIdx = -1
    if parsed.found:
      beginTopologySymbol(result, modulePath, lineNo, parsed)
      activeIdx = result.len - 1
      activeIndent = parsed.indent
      activeScopeKind = parsed.scopeKind
      activeBraceDepth = parsed.initialBraceDepth
      activeBraceSeen = parsed.braceSeen
      if activeScopeKind == topologyScopeBrace and activeBraceSeen and activeBraceDepth <= 0:
        result[activeIdx].bodyEndLine = lineNo
        result[activeIdx].lineSpan = normalizeLineSpan(result[activeIdx].bodyStartLine, result[activeIdx].bodyEndLine)
        activeIdx = -1
      continue
    if activeIdx < 0:
      continue
    result[activeIdx].bodyEndLine = lineNo
    result[activeIdx].lineSpan = normalizeLineSpan(result[activeIdx].bodyStartLine, result[activeIdx].bodyEndLine)
    let trimmed = stripInlineComment(rawLine).strip()
    if trimmed.len == 0:
      continue
    let indent = countIndent(rawLine)
    if activeScopeKind == topologyScopeIndent and indent > activeIndent:
      let relativeNesting = max(0, (indent - activeIndent) div 2)
      if relativeNesting > result[activeIdx].nestingDepth:
        result[activeIdx].nestingDepth = relativeNesting
    let controlSignals = countControlSignals(trimmed)
    if controlSignals > 0:
      result[activeIdx].branchCount += controlSignals
    let calls = extractCallTargets(trimmed)
    for call in calls:
      result[activeIdx].rawCallTargets.add(call)
    result[activeIdx].rawCallTargets = deduplicateStrings(result[activeIdx].rawCallTargets)
    if activeScopeKind == topologyScopeBrace:
      let delta = countBraceDelta(trimmed)
      if delta > 0:
        activeBraceSeen = true
      activeBraceDepth += delta
      if activeBraceSeen and activeBraceDepth <= 0:
        activeIdx = -1
  if activeIdx >= 0:
    result[activeIdx].bodyEndLine = lines.len
    result[activeIdx].lineSpan = normalizeLineSpan(result[activeIdx].bodyStartLine, result[activeIdx].bodyEndLine)

  ## axiom-smt: (assert (and (>= (seq.len symbols) 0) (>= symbols 0) (>= result 0)))
  ## axiom-lean: symbols.size ≥ 0 ∧ (symbols ≥ 0) ∧ (result ≥ 0)
func buildSymbolIndexTable*(symbols: seq[TopologySymbol]): Table[string, int] {.axiomTryImpl.} =
  for idx, symbol in symbols:
    result[sorterNodeIdString(symbol.nodeId)] = idx

{.pop.}
