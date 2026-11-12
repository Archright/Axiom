import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
import std/tables
import compiler/ast
type
  BasicBlock* = object
    id*: int
    statements*: seq[PNode]
    successors*: seq[int]
    predecessors*: seq[int]
    loopHeader*: bool
    loopBackEdgeFrom*: seq[int]

  ControlFlowGraph* = object
    blocks*: seq[BasicBlock]
    entry*: int
    exit*: int
    blockById*: Table[int, BasicBlock]

{.pop.}
