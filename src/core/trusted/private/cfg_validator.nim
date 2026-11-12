import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import std/[options, sequtils, sets, tables]
import core/trusted/axiom_ir
import core/trusted/symbol_table_types
import core/trusted/verification_model_types

type
  CFGValidationResult* = object
    valid*: bool
    errors*: seq[string]

func validateCFG*(cfg: FunctionCFG; model: VerificationModel): CFGValidationResult {.raises: [].} =
  var nodeMap: OrderedTable[uint32, CFGNode]
  for node in cfg.nodes:
    nodeMap[uint32(node.id)] = node

  var errors: seq[string]

  # 1. Reachability: BFS from cfg.entry along successors
  var reachable: HashSet[uint32]
  var queue: seq[NodeId]
  if uint32(cfg.entry) in nodeMap:
    queue.add(cfg.entry)
    reachable.incl(uint32(cfg.entry))
  var i = 0
  while i < queue.len:
    let current = queue[i]
    i += 1
    let node = nodeMap.getOrDefault(uint32(current))
    for succ in node.successors:
      let sid = uint32(succ)
      if sid notin nodeMap:
        continue
      if sid notin reachable:
        reachable.incl(sid)
        queue.add(succ)

  for node in cfg.nodes:
    if uint32(node.id) notin reachable:
      errors.add("unreachable node: " & $(node.id))

  # 2. Terminator Correctness
  for node in cfg.nodes:
    let actual = node.successors.len
    case node.kind
    of cnkEntry:
      if actual != 1:
        errors.add("invalid successor count for node " & $(node.id) & " kind " & $node.kind)
    of cnkExit:
      if actual != 0:
        errors.add("invalid successor count for node " & $(node.id) & " kind " & $node.kind)
    of cnkCondition:
      if actual != 2:
        errors.add("invalid successor count for node " & $(node.id) & " kind " & $node.kind)
    of cnkBlock:
      if actual != 1:
        errors.add("invalid successor count for node " & $(node.id) & " kind " & $node.kind)
    of cnkMerge:
      if actual < 1:
        errors.add("invalid successor count for node " & $(node.id) & " kind " & $node.kind)
    of cnkReturn:
      if actual > 1:
        errors.add("invalid successor count for node " & $(node.id) & " kind " & $node.kind)
    of cnkBreak:
      if actual != 1:
        errors.add("invalid successor count for node " & $(node.id) & " kind " & $node.kind)
    of cnkContinue:
      if actual != 1:
        errors.add("invalid successor count for node " & $(node.id) & " kind " & $node.kind)

  # 3. Edge Validity
  for node in cfg.nodes:
    for succ in node.successors:
      if uint32(succ) notin nodeMap:
        errors.add("unknown successor " & $(succ))

  for trans in model.semantic.transitions:
    if uint32(trans.source) notin nodeMap:
      errors.add("unknown transition endpoint " & $(trans.source))
    if uint32(trans.target) notin nodeMap:
      errors.add("unknown transition endpoint " & $(trans.target))

  # 4. Break Target
  for trans in model.semantic.transitions:
    let srcId = uint32(trans.source)
    if srcId in nodeMap:
      let src = nodeMap.getOrDefault(srcId, CFGNode())
      if src.kind == cnkBreak:
        let tgtId = uint32(trans.target)
        if tgtId in nodeMap:
          let tgt = nodeMap.getOrDefault(tgtId, CFGNode())
          if tgt.kind notin {cnkExit, cnkMerge}:
            errors.add("break targets non-exit node")

  # 5. Continue Target
  for trans in model.semantic.transitions:
    let srcId = uint32(trans.source)
    if srcId in nodeMap:
      let src = nodeMap.getOrDefault(srcId, CFGNode())
      if src.kind == cnkContinue:
        let tgtId = uint32(trans.target)
        if tgtId in nodeMap:
          let tgt = nodeMap.getOrDefault(tgtId, CFGNode())
          if tgt.kind notin {cnkReturn, cnkBlock, cnkCondition, cnkMerge}:
            errors.add("continue targets invalid node")

  # 6. Transition Frame Correctness
  var stateNameSet: HashSet[string]
  for sv in model.semantic.states:
    stateNameSet.incl(sv.name)

  for trans in model.semantic.transitions:
    for assign in trans.update.assignments:
      if assign.symbol notin stateNameSet:
        errors.add("frame references non-state: " & assign.symbol)
    for havoc in trans.update.havocs:
      if havoc notin stateNameSet:
        errors.add("frame references non-state: " & havoc)

  result = CFGValidationResult(valid: errors.len == 0, errors: errors)