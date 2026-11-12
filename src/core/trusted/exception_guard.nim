## exception_guard.nim — Compile-time exception hygiene enforcement
## Part of the Guard Ring system for Axiom-core.
##
## Detects and rejects:
## - bare `except:` (no type specified) → compile error
## - `except Exception:` → compile error (with documented exemptions)

import core/trusted/layer_declaration
axiomLayer "domain"
{.warning[UnusedImport]: off.}  # Macro-only module — import is always "unused" at surface
import std/macros
import std/strutils
{.push raises: [].}

const
  DocumentedExceptions* = [
    "stdlib_shield",      # intentionally catches Exception for stdlib interop
    "artifact_manifest",  # documented policy exception
    "sharded_log"         # documented policy exception
  ]

macro enforceExceptionHygiene*(moduleBody: untyped): untyped =
  ## Compile-time AST walk that inspects except branches:
  ## - bare except: (len == 1, no type child) → compile error
  ## - except Exception: → compile error (exempt modules excluded)
  let srcFile = instantiationInfo().filename
  let isExempt = block:
    var exempt = false
    for pattern in DocumentedExceptions:
      if pattern in srcFile:
        exempt = true
        break
    exempt

  func checkExceptBranch(node: NimNode, src: string) =
    if node.kind == nnkExceptBranch:
      if node.len == 1:
        error("EXCEPTION HYGIENE: bare 'except:' detected in " & src &
              ". Use 'except CatchableError:' or a specific exception type.")
      elif node.len >= 2:
        let excTypeRepr = node[0].repr.strip()
        if excTypeRepr == "Exception" and not isExempt:
          error("EXCEPTION HYGIENE: 'except Exception:' detected in " & src &
                ". Use 'except CatchableError:' instead. " &
                "Only stdlib_shield, artifact_manifest, sharded_log are exempt.")

  func walkAst(node: NimNode, src: string) =
    checkExceptBranch(node, src)
    for child in node:
      walkAst(child, src)

  walkAst(moduleBody, srcFile)
  result = moduleBody

{.pop}
