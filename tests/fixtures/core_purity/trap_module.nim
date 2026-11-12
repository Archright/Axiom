## trap_module — documentation and data that MENTION banned tokens, plus exactly
## two real violations. The mentions must never register; the two must.
import core/trusted/layer_declaration
axiomLayer "domain"
import std/strutils

const PolicyText = "forbid echo here, forbid readFile( here, forbid {.importc.} here"
const PragmaProbe = "importc"

func classify*(payload: string): string {.raises: [].} =
  ## Doc prose mentions readFile( and importc and echo — prose is not code.
  if payload.contains("importc") or payload.startsWith("echo "):
    return "ffi"
  result = "plain"

proc emitDiag(): void =
  echo "diagnostic"
  writeFile("gate.log", "x")