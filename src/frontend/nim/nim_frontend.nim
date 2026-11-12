import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
{.pragma: axiomPure.}

import std/strutils
import core/types/frontend_ir
import frontend/frontend_interface
import frontend/nim/weaver

type
  NimFrontend* {.acyclic.} = ref object of LanguageFrontend  ## No fields — method dispatch only.

method parseToIR*(lf: NimFrontend; sourceCode: string; modulePath: string): FrontendIrNode {.raises: [].} =
  parseNimToIR(sourceCode, modulePath)

method injectGuardFromIR*(lf: NimFrontend; ir: FrontendIrNode; guardKind: string; sourceCode: string = ""): string {.raises: [].} =
  if sourceCode.len > 0:
    weaveGuards(sourceCode, ir)
  else:
    defaultInjectGuard(ir, guardKind)

method languageName*(lf: NimFrontend): string {.raises: [].} =
  "nim"

method canHandle*(lf: NimFrontend; extension: string): bool {.raises: [].} =
  extension.toLowerAscii() == ".nim"

{.pop.}
