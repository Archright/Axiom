import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils, parseopt]
import core/types/results
import src/verification/cert_promotion

proc main() =
  var candidatePath = ""
  var allowNegativeFixture = false

  for kind, key, val in getopt():
    case kind
    of cmdLongOption, cmdShortOption:
      case key
      of "allow-negative-fixture":
        allowNegativeFixture = true
      of "help", "h":
        echo "Usage: promote_cert <path-to-build-cert> [OPTIONS]"
        echo ""
        echo "Promotes a certificate from build/certificates/ to the canonical vault."
        echo ""
        echo "Options:"
        echo "  --allow-negative-fixture   Allow promotion of certRed (canonical negative fixture)"
        echo "  --help, -h                 Show this help"
        return
      else: discard
    else: discard

  for i in 1 ..< paramCount():
    let p = paramStr(i)
    if p.startsWith("-"):
      continue
    candidatePath = p

  if candidatePath.len == 0:
    echo "ERROR: candidate path required"
    quit(1)

  let result = promoteToCanonical(candidatePath, allowNegativeFixture)
  if result.isOk:
    echo "OK: " & result.get()
  else:
    echo "REJECTED: " & result.error()
    quit(1)

when isMainModule:
  main()