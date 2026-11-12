import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

import std/options
import std/strutils
import core/integrity/integrity_refinement_types
import core/logic/refinement_string
import core/logic/refinement_predicate
import core/logic/refinement_query

func tokenizeCpp*(source: string): seq[string] =
  var current: string = ""
  for ch in source:
    if ch.isAlphaNumeric or ch == '_':
      current.add(ch)
    else:
      if current.len > 0:
        result.add(current)
        current = ""
      if ch != ' ' and ch != '\t' and ch != '\n' and ch != '\r':
        result.add($ch)
  if current.len > 0:
    result.add(current)

func countTokenOccurrences*(tokens: seq[string]; target: string): int =
  for tok in tokens:
    if tok == target:
      inc result

func hasTokenPair*(tokens: seq[string]; tok1, tok2: string): bool =
  for i in 0 ..< tokens.len - 1:
    if tokens[i] == tok1 and tokens[i+1] == tok2:
      return true
  false

func hasNegativeTopToken*(tokens: seq[string]): bool =
  for i in 0 ..< tokens.len:
    if tokens[i] == "top" and i + 1 < tokens.len and tokens[i+1] == "(":
      for j in i+2 ..< tokens.len:
        if tokens[j] == ")": return false
        if tokens[j].len > 0 and tokens[j][0] == '-': return true
  false

func hasBoundGuardToken*(tokens: seq[string]): bool =
  for tok in tokens:
    if "MAX_STACK_SIZE" in tok or "512" in tok or "stack.size()" in tok or ".size()" in tok:
      return true
  false

func pushOpcodeBlock(
  profile: var BitcoinScriptTargetProfile;
  label: string;
  blockBody: string;
  startLine: int;
  endLine: int
) =
  if label.len == 0 or profile.opcodeBlockCount >= integrityMaxOpcodeBlocks:
    return
  let trimmedBody = blockBody.strip()
  let tokens = tokenizeCpp(trimmedBody)
  var stackPushes = 0
  for t in tokens:
    if t == "push_back": inc stackPushes
  for i in 0 ..< tokens.len - 1:
    if tokens[i] == "push" and tokens[i+1] == "(": inc stackPushes
  var stackPops = 0
  for t in tokens:
    if t == "popstack" or t == "pop_back": inc stackPops
  var stackReads = 0
  for t in tokens:
    if t == "stacktop": inc stackReads
  for i in 0 ..< tokens.len - 1:
    if tokens[i] == "top" and tokens[i+1] == "(": inc stackReads
  var negativeTop = false
  for i in 0 ..< tokens.len:
    if tokens[i] == "top" and i + 1 < tokens.len and tokens[i+1] == "(":
      for j in i+2 ..< tokens.len:
        if tokens[j] == ")": break
        if tokens[j].len > 0 and tokens[j][0] == '-': negativeTop = true; break
  let minRequiredDepth =
    max(
      (if negativeTop: 1 else: 0),
      max(stackReads, stackPops)
    )
  var branchCount = 0
  for t in tokens:
    if t == "if" or t == "return": inc branchCount
  var hasBoundGuard = false
  for t in tokens:
    if "MAX_STACK_SIZE" in t or "512" in t or "stack.size()" in t or ".size()" in t:
      hasBoundGuard = true
      break
  let opcodeBlock = OpcodeBlockProfile(
    label: label,
    fingerprint: computeSourceFingerprint(label & "\n" & trimmedBody),
    startLine: startLine,
    endLine: endLine,
    stackReads: stackReads,
    stackPushes: stackPushes,
    stackPops: stackPops,
    stackWrites: stackPushes + stackPops,
    minRequiredDepth: minRequiredDepth,
    netStackDelta: stackPushes - stackPops,
    branchCount: branchCount,
    hasNegativeTop: negativeTop,
    hasBoundGuard: hasBoundGuard
  )
  profile.opcodeBlocks[profile.opcodeBlockCount] = opcodeBlock
  inc profile.opcodeBlockCount

func buildBitcoinScriptTargetProfile*(
  sourceCode: string;
  sourcePath: string = "script/interpreter.cpp"
): BitcoinScriptTargetProfile =
  result = BitcoinScriptTargetProfile()
  let normalizedPath =
    if sourcePath.len > 0:
      sourcePath.replace('\\', '/')
    else:
      "script/interpreter.cpp"
  result.sourcePath = normalizedPath
  result.sourceFingerprint = computeSourceFingerprint(sourceCode)
  result.sourceLength = sourceCode.len
  let tokens = tokenizeCpp(sourceCode)
  var stackSignalCount = 0
  for t in tokens:
    if t == "stack" or t == "popstack" or "stack.pop_back" in t: inc stackSignalCount
  var topSignalCount = 0
  for t in tokens:
    if t == "stacktop" or t == "valid": inc topSignalCount
  for i in 0 ..< tokens.len - 1:
    if tokens[i] == "top" and tokens[i+1] == "(": inc topSignalCount
  var boundSignalCount = 0
  for t in tokens:
    if "MAX_STACK_SIZE" in t or "512" in t or "stack.size()" in t: inc boundSignalCount
  var opcodeSignalCount = 0
  for t in tokens:
    if "OP_" in t or t == "opcode" or t == "switch": inc opcodeSignalCount
  var branchSignalCount = 0
  for t in tokens:
    if t == "if" or t == "case" or t == "switch": inc branchSignalCount
  var stackMutationSignalCount = 0
  for t in tokens:
    if t == "popstack" or t == "push" or t == "pop_back" or "stack.push_back" in t: inc stackMutationSignalCount
  var hasStackLimitGuard = false
  for t in tokens:
    if "MAX_STACK_SIZE" in t or "512" in t or "stack.size()" in t or ".size()" in t:
      hasStackLimitGuard = true
      break
  var hasStackTopNegativeIndex = false
  for i in 0 ..< tokens.len:
    if tokens[i] == "top" and i + 1 < tokens.len and tokens[i+1] == "(":
      for j in i+2 ..< tokens.len:
        if tokens[j] == ")": break
        if tokens[j].len > 0 and tokens[j][0] == '-': hasStackTopNegativeIndex = true; break
  result.stackSignalCount = stackSignalCount
  result.topSignalCount = topSignalCount
  result.boundSignalCount = boundSignalCount
  result.opcodeSignalCount = opcodeSignalCount
  result.branchSignalCount = branchSignalCount
  result.stackMutationSignalCount = stackMutationSignalCount
  result.hasStackLimitGuard = hasStackLimitGuard
  result.hasStackTopNegativeIndex = hasStackTopNegativeIndex
  let lines = sourceCode.splitLines()
  var currentLabel = ""
  var currentBody = ""
  var currentStartLine = 0
  for idx, rawLine in lines:
    let line = rawLine.strip()
    if line.startsWith("case ") or line.startsWith("default"):
      if currentLabel.len > 0:
        result.pushOpcodeBlock(currentLabel, currentBody, currentStartLine, idx)
      currentLabel = trimCaseLabel(line)
      currentBody = rawLine & "\n"
      currentStartLine = idx + 1
    elif currentLabel.len > 0:
      currentBody.add(rawLine)
      currentBody.add("\n")
  if currentLabel.len > 0:
    result.pushOpcodeBlock(currentLabel, currentBody, currentStartLine, lines.len)

func scoreOpcodeBlock*(opcodeBlock: OpcodeBlockProfile; violation: IntegrityViolationKind): int {.inline.} =
  case violation
  of violationUnderflow:
    result = max(0, 100 - opcodeBlock.minRequiredDepth * 5)
    if opcodeBlock.hasNegativeTop:
      result += 50
  of violationInvalidPointer:
    result = max(0, 100 - opcodeBlock.stackReads * 3)
    if opcodeBlock.hasBoundGuard:
      result += 30
  of violationBoundExceeded:
    result = max(0, 100 - abs(opcodeBlock.netStackDelta) * 2)
    if opcodeBlock.stackPushes > 0:
      result += 20
  of violationNone:
    result = 0

method selectRelevantOpcodeBlock*(
  profile: BitcoinScriptTargetProfile;
  violation: IntegrityViolationKind
): Option[OpcodeBlockProfile] {.inline, raises: [].} =
  if profile.opcodeBlocks.len == 0:
    return none(OpcodeBlockProfile)
  var bestIdx = 0
  var bestScore = scoreOpcodeBlock(profile.opcodeBlocks[0], violation)
  for idx in 1 ..< profile.opcodeBlocks.len:
    let score = scoreOpcodeBlock(profile.opcodeBlocks[idx], violation)
    if score > bestScore:
      bestScore = score
      bestIdx = idx
  some(profile.opcodeBlocks[bestIdx])

method buildQueryTag*(
  profile: BitcoinScriptTargetProfile;
  action: string;
  propertyName: string;
  opcodeBlock: Option[OpcodeBlockProfile]
): string {.inline, raises: [].} =
  var tag = profile.sourcePath & "#" & profile.sourceFingerprint & "/" & action & "/"
  if opcodeBlock.isSome():
    let selectedOpcode = opcodeBlock.get()
    tag.add("opcode-")
    tag.add(opcodeSlug(selectedOpcode.label))
    tag.add("-")
    tag.add(selectedOpcode.fingerprint)
    tag.add("/")
  tag.add(propertyName)

method buildQueryText*(
  profile: BitcoinScriptTargetProfile;
  registry: InvariantRegistry;
  config: Z3WrapperConfig;
  violatedProperty: string;
  opcodeBlock: Option[OpcodeBlockProfile]
): string {.inline, raises: [].} =
  result = "(set-option :fixed_seed " & $config.fixedSeed & ")\n" &
    "(set-option :smt.threads 1)\n" &
    "; tag=" & config.queryTag & "\n" &
    "; property=" & violatedProperty & "\n" &
    "; source_path=" & profile.sourcePath & "\n" &
    "; source_fingerprint=" & profile.sourceFingerprint & "\n" &
    "; stack_signals=" & $profile.stackSignalCount & "\n" &
    "; top_signals=" & $profile.topSignalCount & "\n" &
    "; bound_signals=" & $profile.boundSignalCount & "\n" &
    "; opcode_signals=" & $profile.opcodeSignalCount & "\n" &
    "; branch_signals=" & $profile.branchSignalCount & "\n" &
    "; stack_mutation_signals=" & $profile.stackMutationSignalCount & "\n" &
    "; has_stack_limit_guard=" & $(if profile.hasStackLimitGuard: 1 else: 0) & "\n" &
    "; has_stacktop_negative_index=" & $(if profile.hasStackTopNegativeIndex: 1 else: 0)
  if opcodeBlock.isSome():
    let selectedOpcode = opcodeBlock.get()
    result.add("\n; opcode_block_label=" & selectedOpcode.label)
    result.add("\n; opcode_block_fingerprint=" & selectedOpcode.fingerprint)
    result.add("\n; opcode_block_lines=" & $selectedOpcode.startLine & "-" & $selectedOpcode.endLine)
    result.add("\n; opcode_block_stack_reads=" & $selectedOpcode.stackReads)
    result.add("\n; opcode_block_stack_pushes=" & $selectedOpcode.stackPushes)
    result.add("\n; opcode_block_stack_pops=" & $selectedOpcode.stackPops)
    result.add("\n; opcode_block_stack_writes=" & $selectedOpcode.stackWrites)
    result.add("\n; opcode_block_min_required_depth=" & $selectedOpcode.minRequiredDepth)
    result.add("\n; opcode_block_net_stack_delta=" & $selectedOpcode.netStackDelta)
    result.add("\n; opcode_block_has_negative_top=" & $(if selectedOpcode.hasNegativeTop: 1 else: 0))
    result.add("\n; opcode_block_has_bound_guard=" & $(if selectedOpcode.hasBoundGuard: 1 else: 0))
  result.add("\n(declare-const size Int)")
  result.add("\n(declare-const valid_top Bool)")
  result.add("\n(declare-const index Int)")
  result.add("\n(declare-const observed Int)")
  for assertion in buildInvariantAssertions(registry):
    result.add("\n(assert (! ")
    result.add(assertion.expr)
    result.add(" :named ")
    result.add(assertion.id)
    result.add("))")
  result.add("\n(check-sat)\n(get-model)\n(get-unsat-core)")

method hasStackSignals*(profile: BitcoinScriptTargetProfile): bool {.inline, raises: [].} =
  profile.stackSignalCount > 0 or profile.sourceLength == 0

method hasTopSignals*(profile: BitcoinScriptTargetProfile): bool {.inline, raises: [].} =
  profile.topSignalCount > 0 or profile.sourceLength == 0

method hasBoundSignals*(profile: BitcoinScriptTargetProfile): bool {.inline, raises: [].} =
  profile.boundSignalCount > 0 or profile.sourceLength == 0

method profileLabel*(profile: BitcoinScriptTargetProfile): string {.inline, raises: [].} =
  "bitcoin-script"

{.pop.}
{.pop.}
