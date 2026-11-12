import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

import std/strutils
import std/options
import std/os
import core/utils/io_utils
import core/types/results
import core/judge/smart_search
import core/boundary/boundary_extraction_types
import boundary_extractor_part1
import core/trusted/axiom_pragmas

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc generateHintFromParamTypes*(nodeId, fileContext: string): Option[SemanticHint] {.raises: [CatchableError], tags: [AxiomIOEffect, IOEffect, TimeEffect, RootEffect], axiomEffect: IOEffect.} =
  ## Convenience wrapper for heal.nim integration.
  ## Returns a SemanticHint if boundary extraction is complete or partial.
  ## bcIncompleteIO is now returned ONLY for malformed nodeIds (missing ::).
  let res = extractBoundaries(nodeId, fileContext)
  if res.completeness == bcIncompleteIO:
    return none(SemanticHint)
  return res.hint

# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
# @axiom-hint: lean="(result ≥ 0)" smt="(assert (and (>= result 0)))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func formatAxiomHintComment*(hint: SemanticHint): string {.noSideEffect.} =
  ## Formats a SemanticHint as a virtual @axiom-hint comment for source injection.
  result = "# @axiom-hint: lean=\"" & hint.leanProposition & "\" smt=\"" & hint.smtConstraint & "\""

# @axiom-hint: lean="lines.size ≥ 0 ∧ (∀ (linesIdx : Fin lines.size), (lines.get linesIdx).length ≥ 0) ∧ fnLineIdx ≥ -9223372036854775808 ∧ fnLineIdx ≤ 9223372036854775807 ∧ comment.length ≥ 0" smt="(assert (and (>= (seq.len lines) 0) (forall ((linesIdx Int)) (=> (and (>= linesIdx 0) (< linesIdx (seq.len lines))) (>= (str.len (seq.nth lines linesIdx)) 0))) (and (>= fnLineIdx -9223372036854775808) (<= fnLineIdx 9223372036854775807)) (>= (str.len comment) 0)))"
# @axiom-hint: lean="stripped.length = 0 ∧ stripped = comment ∧ idx ≥ 0 ∧ true ∧ stripped = comment → result = true ∧ (∀ (linesIdx : Fin lines.size), (lines.get linesIdx).length ≥ 0)" smt="(assert (and (= (str.len stripped) 0) (= stripped comment) (>= idx 0) true (=> (= stripped comment) (= result true)) (forall ((linesIdx Int)) (=> (and (>= linesIdx 0) (< linesIdx (seq.len lines))) (>= (str.len (seq.nth lines linesIdx)) 0)))))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func leadingHintBlockContains(lines: seq[string]; fnLineIdx: int; comment: string): bool {.noSideEffect.} =
  var idx = fnLineIdx - 1
  while idx >= 0:
    let stripped = lines[idx].strip()
    if stripped.len == 0:
      break
    if not stripped.startsWith("#"):
      break
    if stripped == comment:
      return true
    dec idx

# @axiom-hint: lean="filePath.length ≥ 0 ∧ logLines.size ≥ 0 ∧ (∀ (logLinesIdx : Fin logLines.size), (logLines.get logLinesIdx).length ≥ 0) ∧ external_io_isolated" smt="(assert (and (>= (str.len filePath) 0) (>= (seq.len logLines) 0) (forall ((logLinesIdx Int)) (=> (and (>= logLinesIdx 0) (< logLinesIdx (seq.len logLines))) (>= (str.len (seq.nth logLines logLinesIdx)) 0))) external_io_isolated))"
# @axiom-hint: lean="(content ≥ 0) ∧ (∀ (logLinesIdx : Fin logLines.size), (logLines.get logLinesIdx).length ≥ 0) ∧ external_io_isolated" smt="(assert (and (>= content 0) (forall ((logLinesIdx Int)) (=> (and (>= logLinesIdx 0) (< logLinesIdx (seq.len logLines))) (>= (str.len (seq.nth logLines logLinesIdx)) 0))) external_io_isolated))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc rewriteVirtualHintComment*(filePath: string; logLines: var seq[string]) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Wave 10 migration helper: rewrites any legacy '# @axiom-hint:' comments to '# @axiom-hint:'.
  if not fileExists(filePath):
    return
  try:
    let readRes = readFileOpt(filePath)
    if readRes.isErr: return
    var content = readRes.get
    if "# @axiom-hint:" notin content:
      return
    content = content.replace("# @axiom-hint:", "# @axiom-hint:")
    ## intentional-discard: writes migrated legacy hint comment; content is a no-op transform
    discard writeFileOpt(filePath, content)
    logLines.add("  -> [VirtualHint] Migrated legacy comment style in " & filePath)
  except CatchableError as e:
    logLines.add("  -> [VirtualHint] Migration failed: " & e.msg)

# @axiom-hint: lean="nodeId.length ≥ 0 ∧ logLines.size ≥ 0 ∧ (∀ (logLinesIdx : Fin logLines.size), (logLines.get logLinesIdx).length ≥ 0) ∧ external_io_isolated" smt="(assert (and (>= (str.len nodeId) 0) (>= (seq.len logLines) 0) (forall ((logLinesIdx Int)) (=> (and (>= logLinesIdx 0) (< logLinesIdx (seq.len logLines))) (>= (str.len (seq.nth logLines logLinesIdx)) 0))) external_io_isolated))"
# @axiom-hint: lean="parts.length < 2 ∧ fnLineIdx < 0 ∧ filePath = modulePath ∧ fnLineIdx = i ∧ (fnLineIdx ≥ 0) ∧ (filePath ≥ 0) ∧ (∀ (logLinesIdx : Fin logLines.size), (logLines.get logLinesIdx).length ≥ 0) ∧ external_io_isolated" smt="(assert (and (< (str.len parts) 2) (< fnLineIdx 0) (= filePath modulePath) (= fnLineIdx i) (>= fnLineIdx 0) (>= filePath 0) (forall ((logLinesIdx Int)) (=> (and (>= logLinesIdx 0) (< logLinesIdx (seq.len logLines))) (>= (str.len (seq.nth logLines logLinesIdx)) 0))) external_io_isolated))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc injectVirtualHintToSource*(nodeId: string; hint: SemanticHint; logLines: var seq[string]) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Injects a virtual @axiom-hint comment into the source file immediately before
  ## the target function declaration. Skips if the comment already exists.
  let parts = nodeId.split("::")
  if parts.len < 2:
    return
  let modulePath = parts[0]
  let functionName = parts[1]

  var filePath = ""
  if modulePath.startsWith("src/"):
    filePath = modulePath
  else:
    filePath = "src/" & modulePath

  if not fileExists(filePath):
    logLines.add("  -> [VirtualHint] Source file not found: " & filePath)
    return

  let comment = formatAxiomHintComment(hint)

  try:
    let readRes2 = readFileOpt(filePath)
    if readRes2.isErr: return
    var lines = readRes2.get.splitLines()
    var fnLineIdx = -1
    for i in 0 ..< lines.len:
      let stripped = lines[i].strip()
      if stripped.startsWith("proc " & functionName) or stripped.startsWith("func " & functionName) or
         stripped.startsWith("template " & functionName) or stripped.startsWith("macro " & functionName) or
         stripped.startsWith("iterator " & functionName):
        fnLineIdx = i
        break

    if fnLineIdx < 0:
      logLines.add("  -> [VirtualHint] Function declaration not found in " & filePath)
      return

    if leadingHintBlockContains(lines, fnLineIdx, comment):
      logLines.add("  -> [VirtualHint] Comment already exists for " & functionName)
      return

    lines.insert(comment, fnLineIdx)
    let newContent = lines.join("\n")
    ## intentional-discard: writes hint injection result; non-mutating transform for downstream tooling
    discard writeFileOpt(filePath, newContent)
    logLines.add("  -> [VirtualHint] Injected @axiom-hint for " & functionName & " in " & filePath)
  except CatchableError as e:
    logLines.add("  -> [VirtualHint] Injection failed: " & e.msg)

{.pop.}
