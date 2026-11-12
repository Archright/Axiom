import core/trusted/layer_declaration
axiomLayer "tools"
# tools/safe_move.nim — Local atomic moveFile wrapper for tools context
# Eliminates core/trusted/stdlib_shield dependency (import boundary compliance)
import std/os

type
  FileMoveError* = object of CatchableError

proc safeMoveFile*(source, dest: string) {.raises: [FileMoveError].} =
  {.push warning[BareExcept]: off.}
  try:
    moveFile(source, dest)
  except Exception as e:
    raise newException(FileMoveError, "moveFile(" & source & " -> " & dest & "): " & e.msg, e)
  {.pop.}
