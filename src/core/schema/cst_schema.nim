import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import core/types/results
import std/json
type
  CstSpan* = object
    ## Byte-offset range within source text: [start, endPos).
    start*: uint32
    endPos*: uint32
# ── Distinct Types (Semantic Safety) ─────────────────────────────────────────

func toJson*(s: CstSpan): JsonNode {.raises: [].} =
  result = newJObject()
  result["start"] = newJInt(s.start.int)
  result["endPos"] = newJInt(s.endPos.int)
func fromJson*(node: JsonNode, _: typedesc[CstSpan]): Result[CstSpan, string] {.
  raises: [].} =
  try:
    ok(CstSpan(
      start: node["start"].getInt().uint32,
      endPos: node["endPos"].getInt().uint32
    ))
  except CatchableError as e:
    err("CstSpan deserialization failed: " & e.msg)
type
  FilePath* = distinct string
    ## Semantic wrapper for file system paths.
    ## Prevents accidental confusion with raw strings.
func `$`*(p: FilePath): string {.raises: [].} =
  string(p)
func `==`*(a, b: FilePath): bool {.raises: [].} =
  string(a) == string(b)
func initFilePath*(s: string): FilePath {.raises: [].} =
  ## Construct a FilePath from a raw string.
  FilePath(s)
proc `$`*(p: FilePath): string {.raises: [].} =
  string(p)
proc `==`*(a, b: FilePath): bool {.raises: [].} =
  string(a) == string(b)
func initCstSpan*(start, endPos: uint32): CstSpan {.raises: [].} =
  CstSpan(start: start, endPos: endPos)
type
  CstNodeKind* = enum
    ## High-level CST node classification.
    cstUnknown
    cstLeaf
    cstInternal
    cstError
type
  NodeDetail* = enum
    ## Fine-grained node classification for ConcreteCstNode.
    ndNil
    ndIdent
    ndLitInt
    ndLitFloat
    ndLitStr
    ndLitChar
    ndKeyword
    ndOperator
    ndPunctuation
    ndComment
    ndWhitespace
    ndNewline
    ndCall
    ndInfix
    ndPrefix
    ndDot
    ndParen
    ndBracket
    ndCurly
    ndStmtList
    ndProc
    ndFunc
    ndMethod
    ndTemplate
    ndMacro
    ndType
    ndEnum
    ndObject
    ndTuple
    ndModule
    ndImport
    ndExport
    ndInclude
    ndIf
    ndElif
    ndElse
    ndWhile
    ndFor
    ndCase
    ndBlock
    ndVar
    ndLet
    ndConst
    ndAsgn
    ndReturn
    ndDiscard
    ndBreakStmt
    ndContinueStmt
    ndYield
    ndRaise
    ndTry
    ndExcept
    ndFinally
    ndPragma
    ndGenericParam
    ndParamList
    ndArgList
    ndReturnType
    ndTypeSection
    ndVarSection
    ndLetSection
    ndConstSection
    ndRange
    ndColon
    ndCommand
    ndLambda
    ndDo
    ndBindings
    ndArrayConstr
    ndTupleConstr
    ndSuf
    ndError
type
  ConcreteCstNode* {.acyclic.} = ref object
    ## Concrete CstNode implementation for testing and prototyping.
    ## Satisfies the CstNode interface contract (see above).
    name*: string
    kind*: CstNodeKind
    detail*: NodeDetail
    span*: CstSpan
    children*: seq[ConcreteCstNode]
    isNamed*: bool
func newCstNode*(
  nodeName: string = "",
  nodeKind: CstNodeKind = cstUnknown,
  nodeDetail: NodeDetail = ndNil,
  nodeSpan: CstSpan = default(CstSpan),
  nodeChildren: seq[ConcreteCstNode] = @[],
  nodeIsNamed: bool = false
): ConcreteCstNode {.raises: [].} =
  ## Convenience constructor for ConcreteCstNode.
  ## Uses prefixed parameter names to avoid Nim's object-constructor syntax conflict.
  ConcreteCstNode(
    name: nodeName, kind: nodeKind, detail: nodeDetail,
    span: nodeSpan, children: nodeChildren, isNamed: nodeIsNamed
  )
type
  ParseError* = object
    ## A single parse error record with source location.
    line*: uint32
    column*: uint32
    byteOffset*: uint32
    message*: string
type
  ParsedFile* = object
    ## Result of parsing a source file into a CST.
    path*: FilePath
    source*: string
    cst*: ConcreteCstNode
    parseMs*: float64
    errorCount*: int
    errors*: seq[ParseError]
func initParsedFile*(path: FilePath, source: string): ParsedFile {.raises: [].} =
  ParsedFile(path: path, source: source)
type
  SyntaxStats* = object
    ## Aggregate statistics across multiple parse operations.
    parseSuccessCount*: uint32
    parseFailCount*: uint32
    avgParseMs*: float64
func totalParses*(s: SyntaxStats): uint32 {.raises: [].} =
  ## Total number of parse operations.
  s.parseSuccessCount + s.parseFailCount
func successRate*(s: SyntaxStats): float64 {.raises: [].} =
  ## Ratio of successful parses (0.0 .. 1.0).
  let total = s.totalParses()
  if total == 0: 0.0
  else: s.parseSuccessCount.float64 / total.float64
{.pop.}
