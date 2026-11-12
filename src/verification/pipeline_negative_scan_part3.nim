import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

import std/json
import std/options
import std/strutils
import compiler/ast
import core/axiom_pragmas

import core/utils/text_utils
import core/pipeline_core_types
import core/logic/universal_translation_types
import core/parser_utils
import core/parsers/pnode_nav

import verification/pipeline_negative_scan_part1 as part1
import verification/pipeline_negative_scan_part2 as part2
# axiomIoBoundary

proc checkBufferOverflow*(result: var NegativeInvariantScan;
    translation: UniversalTranslation; sourceAst: Option[PNode];
    activeInvariant: string) {.axiomEffect: IOEffect, tags: [RootEffect, TimeEffect, AxiomIOEffect, IOEffect].} =
  ## Check for index-out-of-bounds vulnerability.
  try:
    if part2.coversPromotedInvariant(vkBufferOverflow, activeInvariant):
      return
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
  var hasIndexAssert = false
  var hasIndexGuard = false
  if sourceAst.isSome:
    let astNode = sourceAst.get
    for cond in collectAssertConditionsP(astNode):
      var hasIdxLower = false
      var hasIdxUpper = false
      for infix in findNodesP(cond, {nkInfix}):
        for op in findNodesP(infix, {nkIdent}):
          let opText = pNodeText(op)
          if opText in [">=", ">", "notin", "in"]:
            for ident in findNodesP(infix, {nkIdent}):
              if pNodeText(ident) == "idx":
                hasIdxLower = true
          if opText in ["<", "<=", "notin", "in"]:
            for ident in findNodesP(infix, {nkIdent}):
              if pNodeText(ident) == "idx":
                hasIdxUpper = true
      if hasIdxLower and hasIdxUpper:
        hasIndexAssert = true
        break
    for cond in collectIfConditionsP(astNode):
      var hasIdx = false
      for infix in findNodesP(cond, {nkInfix}):
        for ident in findNodesP(infix, {nkIdent}):
          if pNodeText(ident) == "idx":
            hasIdx = true
            break
        if hasIdx:
          for op in findNodesP(infix, {nkIdent}):
            if pNodeText(op) in ["<", "<=", ">=", ">", "notin", "in"]:
              hasIndexGuard = true
              break
  if not (hasIndexAssert or hasIndexGuard):
    try:
      let cexBo = part2.buildCounterExampleInput(translation, "buffer_overflow",
        "index_out_of_bounds", """{"idx":-1}""")
      if cexBo.isSome:
        result.hits.add(part2.buildAnnotatedHit(vkBufferOverflow,
          VulnerabilityHit(kind: vkBufferOverflow, boInfo: BufferOverflowInfo(address: 0, size: 0)),
          "index out of bounds", cexBo.get(), "assert idx >= 0; assert idx < length"))
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

proc checkNullPointer*(result: var NegativeInvariantScan;
    translation: UniversalTranslation; sourceAst: Option[PNode];
    activeInvariant: string) {.axiomEffect: IOEffect, tags: [RootEffect, TimeEffect, AxiomIOEffect, IOEffect].} =
  ## Check for null-pointer-dereference vulnerability.
  try:
    if part2.coversPromotedInvariant(vkNullPointerDereference, activeInvariant):
      return
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
  var hasNullAssert = false
  var hasNullGuard = false
  if sourceAst.isSome:
    let astNode = sourceAst.get
    for cond in collectAssertConditionsP(astNode):
      var hasPtr = false
      for ident in findNodesP(cond, {nkIdent}):
        if pNodeText(ident) == "ptr":
          hasPtr = true
          break
      if not hasPtr:
        for ptrNode in findNodesP(cond, {nkPrefix}):
          if pNodeText(ptrNode) == "ptr":
            hasPtr = true
            break
      if hasPtr:
        for infix in findNodesP(cond, {nkInfix}):
          for op in findNodesP(infix, {nkIdent}):
            if pNodeText(op) in ["!=", "==", "notin", "in"]:
              hasNullAssert = true
              break
    for cond in collectIfConditionsP(astNode):
      var hasPtr = false
      for ident in findNodesP(cond, {nkIdent}):
        if pNodeText(ident) == "ptr":
          hasPtr = true
          break
      if not hasPtr:
        for ptrNode in findNodesP(cond, {nkPrefix}):
          if pNodeText(ptrNode) == "ptr":
            hasPtr = true
            break
      if hasPtr:
        for infix in findNodesP(cond, {nkInfix}):
          for op in findNodesP(infix, {nkIdent}):
            if pNodeText(op) in ["==", "!=", "<", ">", "<=", ">=", "notin", "in"]:
              hasNullGuard = true
              break
  if not (hasNullAssert or hasNullGuard):
    try:
      let cexNp = part2.buildCounterExampleInput(translation, "null_pointer_dereference",
        "pointer_not_null", """{"ptr":"nil"}""")
      if cexNp.isSome:
        result.hits.add(part2.buildAnnotatedHit(vkNullPointerDereference,
          VulnerabilityHit(kind: vkNullPointerDereference, npInfo: NullPointerInfo(derefInstruction: "")),
          "optional/pointer safety violated", cexNp.get(), "assert ptr != nil"))
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

proc checkIntegerOverflow*(result: var NegativeInvariantScan;
    translation: UniversalTranslation; sourceCode: string;
    sourceAst: Option[PNode]; activeInvariant: string) {.axiomEffect: IOEffect, tags: [RootEffect, TimeEffect, AxiomIOEffect, IOEffect].} =
  ## Check for integer-overflow/underflow vulnerability.
  try:
    if part2.coversPromotedInvariant(vkIntegerOverflowUnderflow, activeInvariant):
      return
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
  var hasArithmeticTransition = false
  for entry in translation.ilEntries:
    let tokens = tokenizeLowered(entry.il)
    if "add" in tokens or "sub" in tokens:
      hasArithmeticTransition = true
      break
  if not (hasArithmeticTransition and
      part2.hasArithmeticRiskSignal(translation, sourceCode, sourceAst)):
    return
  var hasAmountGuard = false
  var hasValueGuard = false
  if sourceAst.isSome:
    let astNode = sourceAst.get
    for cond in collectAssertConditionsP(astNode):
      for ident in findNodesP(cond, {nkIdent}):
        let name = pNodeText(ident)
        if name in ["amount", "value"]:
          for infix in findNodesP(cond, {nkInfix}):
            for op in findNodesP(infix, {nkIdent}):
              if pNodeText(op) in ["<=", "<", ">=", ">", "notin", "in"]:
                if name == "amount":
                  hasAmountGuard = true
                else:
                  hasValueGuard = true
    for cond in collectIfConditionsP(astNode):
      for ident in findNodesP(cond, {nkIdent}):
        if pNodeText(ident) in ["amount", "value"]:
          for infix in findNodesP(cond, {nkInfix}):
            for op in findNodesP(infix, {nkIdent}):
              if pNodeText(op) in ["<=", "<", ">=", ">", "notin", "in"]:
                if pNodeText(ident) == "amount":
                  hasAmountGuard = true
                else:
                  hasValueGuard = true
  if not (hasAmountGuard or hasValueGuard):
    try:
      let cexIo = part2.buildCounterExampleInput(translation, "integer_overflow_underflow",
        "arithmetic_overflow_underflow", """{"amount":2147483647,"balance":0}""")
      if cexIo.isSome:
        result.hits.add(part2.buildAnnotatedHit(vkIntegerOverflowUnderflow,
          VulnerabilityHit(kind: vkIntegerOverflowUnderflow, ioInfo: IntegerOverflowInfo(registerName: "", isOverflow: false)),
          "arithmetic operation can overflow/underflow", cexIo.get(), "assert amount <= balance; assert amount >= 0"))
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

proc checkGhostUpdate*(result: var NegativeInvariantScan;
    translation: UniversalTranslation; sourceCode: string;
    sourceAst: Option[PNode]; activeInvariant: string) {.axiomEffect: IOEffect, tags: [RootEffect, TimeEffect, AxiomIOEffect, IOEffect].} =
  ## Check for ghost-update (version monotonicity) vulnerability.
  try:
    if part2.coversPromotedInvariant(vkGhostUpdate, activeInvariant):
      return
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
  if part1.hasVersionTransition(translation) and part2.hasVersionPayloadState(sourceCode, sourceAst) and
      not part2.hasVersioningGuard(sourceCode, sourceAst):
    try:
      let cexGu = part2.buildCounterExampleInput(translation, "ghost_update",
        "version_monotonicity_violated",
        """{"version":2,"payload":200,"stale_version":1,"stale_payload":100,"delta":1,"stale":true}""")
      if cexGu.isSome:
        result.hits.add(part2.buildAnnotatedHit(vkGhostUpdate,
          VulnerabilityHit(kind: vkGhostUpdate, guInfo: GhostUpdateInfo(shadowStateVariable: "")),
          "version monotonicity violated", cexGu.get(),
          "assert next.version >= state.version; assert next.version == state.version implies next.payload == state.payload"))
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

proc checkDeadlockRace*(result: var NegativeInvariantScan;
    translation: UniversalTranslation; sourceCode: string;
    sourceAst: Option[PNode]; activeInvariant: string) {.axiomEffect: IOEffect, tags: [RootEffect, TimeEffect, AxiomIOEffect, IOEffect].} =
  ## Check for deadlock/race-condition vulnerability.
  try:
    if part2.coversPromotedInvariant(vkDeadlockRaceCondition, activeInvariant):
      return
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
  if not (translation.controlFlowCount > 0 and
      part2.hasConcurrencySignal(translation, sourceCode, sourceAst)):
    return
  var hasLockOrAtomic = false
  if sourceAst.isSome:
    let astNode = sourceAst.get
    hasLockOrAtomic = hasCallToP(astNode, "lock") or hasCallToP(astNode, "atomic") or
                      hasPragmaNamedP(astNode, "gcsafe") or hasPragmaNamedP(astNode, "threadvar")
  if not hasLockOrAtomic:
    try:
      let cexDl = part2.buildCounterExampleInput(translation, "deadlock_race_condition",
        "concurrency_guard_missing", """{"t1":"enter","t2":"enter"}""")
      if cexDl.isSome:
        result.hits.add(part2.buildAnnotatedHit(vkDeadlockRaceCondition,
          VulnerabilityHit(kind: vkDeadlockRaceCondition, dlInfo: DeadlockInfo(trace: "")),
          "concurrency synchronization missing", cexDl.get(), "add lock/atomic guard around shared state transition"))
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

proc runNegativeInvariantSearch*(
  translation: UniversalTranslation;
  sourceCode: string;
  activeInvariant: string = ""
): NegativeInvariantScan {.raises: [], axiomEffect: IOEffect, tags: [RootEffect, AxiomIOEffect, IOEffect].} =
  var sourceAst = none(PNode)
  if translation.language.toLowerAscii() == "nim" and sourceCode.len > 0:
    try:
      sourceAst = some(parseStringAST(sourceCode))
    except CatchableError:
      discard  # best-effort  # axiom:best-effort(ioboundary catch)
  try:
    if translation.memoryAccessCount > 0:
      checkBufferOverflow(result, translation, sourceAst, activeInvariant)
      checkNullPointer(result, translation, sourceAst, activeInvariant)
    checkIntegerOverflow(result, translation, sourceCode, sourceAst, activeInvariant)
    checkGhostUpdate(result, translation, sourceCode, sourceAst, activeInvariant)
    checkDeadlockRace(result, translation, sourceCode, sourceAst, activeInvariant)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

  result.hasVulnerability = false
  for hit in result.hits:
    if hit.sat:
      result.hasVulnerability = true
      break
    try:
      let json = json.parseJson(hit.counterExampleInput)
      if json.hasKey("status") and json["status"].getStr() == "vacuous":
        result.logicModelConflicted = true
        break
    except CatchableError:
      discard  # best-effort  # axiom:best-effort(ioboundary catch)

# @axiom-hint: lean="isCStyle ∧ usesResult" smt="(assert (and isCStyle usesResult))"
func remediationSnippet(language: string; hit: VulnerabilityHit; baseIndent: string; sourceContext: string = ""): seq[string] =
  let normalized = language.toLowerAscii()
  let isCStyle = normalized == "c" or normalized == "cpp" or normalized == "c++"
  let childIndent = baseIndent & "  "
  case hit.kind
  of vkBufferOverflow:
    if isCStyle:
      @[baseIndent & "if (idx < 0 || idx >= length) {", childIndent & "return -1;", baseIndent & "}"]
    else:
      @[baseIndent & "if idx < 0 or idx >= length:", childIndent & "return -1"]
  of vkIntegerOverflowUnderflow:
    if isCStyle:
      @[baseIndent & "if (amount < 0 || amount > balance) {", childIndent & "return balance;", baseIndent & "}"]
    else:
      @[baseIndent & "if amount >= 0 and amount <= balance:", childIndent & "return balance"]
  of vkNullPointerDereference:
    if isCStyle:
      @[baseIndent & "if (ptr == NULL) {", childIndent & "return -1;", baseIndent & "}"]
    else:
      @[baseIndent & "if ptr == nil:", childIndent & "return -1"]
  of vkDeadlockRaceCondition:
    if isCStyle:
      @[baseIndent & "if (!lock_held) {", childIndent & "return balance;", baseIndent & "}"]
    else:
      @[baseIndent & "if not lockHeld:", childIndent & "return balance"]
  of vkGhostUpdate:
    let usesResult = sourceContext.contains("result =") or sourceContext.contains("result.")
    if isCStyle:
      @[baseIndent & "if (next.version < state.version) {", childIndent & "return state;", baseIndent & "}"]
    else:
      if usesResult:
        @[baseIndent & "if result.version < state.version:", childIndent & "return state"]
      else:
        @[baseIndent & "if next.version < state.version:", childIndent & "return state"]

## Apply One Remediation.
# @axiom-hint: lean="lines.length = 0 ∧ snippet.length = 0 ∧ inserted ∧ inserted = true ∧ (lines ≥ 0) ∧ (snippet ≥ 0) ∧ (inserted ≥ 0)" smt="(assert (and (= (str.len lines) 0) (= (str.len snippet) 0) inserted (= inserted true) (>= lines 0) (>= snippet 0) (>= inserted 0)))"
func applyOneRemediation*(
  source: string;
  language: string;
  hit: VulnerabilityHit
): tuple[updated: string; changed: bool] =
  let lines = source.splitLines()
  if lines.len == 0:
    return (updated: source, changed: false)
  let normalized = language.toLowerAscii()
  let isCStyle = normalized == "c" or normalized == "cpp" or normalized == "c++"
  var output: seq[string] = @[]
  var inserted = false
  for line in lines:
    output.add(line)
    let stripped = line.strip()
    let isNimAnchor = not isCStyle and stripped.endsWith("=")
    let isCAnchor = isCStyle and stripped.endsWith("{")
    if not inserted and (isNimAnchor or isCAnchor):
      let indent = text_utils.leadingWhitespace(line) & "  "
      let snippet = remediationSnippet(language, hit, indent, source)
      if snippet.len == 0:
        return (updated: source, changed: false)
      for patchLine in snippet:
        output.add(patchLine)
      inserted = true
  if inserted:
    return (updated: output.join("\n"), changed: true)
  let snippet = remediationSnippet(language, hit, "", source)
  if snippet.len == 0:
    return (updated: source, changed: false)
  for patchLine in snippet:
    output.add(patchLine)
  (updated: output.join("\n"), changed: true)
{.pop.}
