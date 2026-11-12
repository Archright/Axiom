import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [].}
## Parses nim check compiler output into structured error records.
## Used by ast_fix_engine.nim to identify and classify compilation errors.

import std/[strutils, sequtils]

type
  CompilerErrorKind* = enum
    ckUnusedImport
    ckUndeclaredRoutine
    ckTypeMismatch
    ckCannotRaise
    ckFuncProcMismatch
    ckForwardDeclMissing
    ckGenericError

  CompilerError* = object
    file*: string
    line*: int
    column*: int
    kind*: CompilerErrorKind
    message*: string
    code*: string

  CompilerOutput* = object
    errors*: seq[CompilerError]
    rawOutput*: string

proc classifyError(msg: string): CompilerErrorKind =
  let lower = msg.toLowerAscii
  if "unusedimport" in lower or "imported and not used" in lower:
    result = ckUnusedImport
  elif "undeclared" in lower:
    result = ckUndeclaredRoutine
  elif "type mismatch" in lower:
    result = ckTypeMismatch
  elif "can raise an unlisted exception" in lower:
    result = ckCannotRaise
  elif "implementation" in lower and "expected" in lower:
    if "func" in lower or "proc" in lower:
      result = ckFuncProcMismatch
    else:
      result = ckForwardDeclMissing
  else:
    result = ckGenericError

proc parseCompilerOutput*(rawOutput: string): CompilerOutput =
  result.rawOutput = rawOutput
  for line in rawOutput.splitLines:
    let line = line.strip
    if line.len == 0 or line.startsWith("["): continue
    let parenStart = line.find('(')
    let parenEnd = line.find(')', parenStart + 1)
    if parenStart < 0 or parenEnd < 0: continue
    let filePath = line[0..<parenStart]
    let location = line[parenStart+1..<parenEnd]
    let parts = location.split(',')
    if parts.len < 2: continue
    var err: CompilerError
    err.file = filePath
    try:
      err.line = parseInt(parts[0].strip)
      err.column = parseInt(parts[1].strip)
    except CatchableError:
      continue
    let afterParen = line[parenEnd+1..^1].strip
    if "Error:" in afterParen:
      err.message = afterParen[afterParen.find("Error:") + 6..^1].strip
    elif "Warning:" in afterParen:
      err.message = afterParen[afterParen.find("Warning:") + 8..^1].strip
    else:
      err.message = afterParen
    let bracketStart = err.message.find('[')
    let bracketEnd = err.message.find(']')
    if bracketStart >= 0 and bracketEnd > bracketStart:
      err.code = err.message[bracketStart+1..<bracketEnd]
    err.kind = classifyError(err.message)
    result.errors.add(err)

proc filterByKind*(output: CompilerOutput; kind: CompilerErrorKind): seq[CompilerError] =
  output.errors.filterIt(it.kind == kind)
