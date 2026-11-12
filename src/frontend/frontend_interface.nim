import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Language Frontend Interface (Wave 3.5)
##
## Abstract base type that every language frontend must inherit from.
## Adding a new language (Rust, Go, Pseudo-code, ...) only requires
## implementing parseToIR() and injectGuardFromIR().

import core/types/frontend_ir
import ../core/trusted/axiom_pragmas

## Default Inject Guard.
func defaultInjectGuard*(ir: FrontendIrNode; guardKind: string): string {.raises: [], axiom: ["(assert ast_parse_failed_isolated)", "ast_parse_failed_isolated"].} =
  ## Fallback guard injection that works for any IR node.
  ## Returns a plain-text contract block that can be appended to a prompt.
  if ir.name.len == 0:
    return ""
  result = "-- Axiom-IR Guard (" & guardKind & ") for " & ir.name & "\n"
  result.add(ir.toLeanContract())

type
  LanguageFrontend* {.acyclic.} = ref object of RootObj  ## No ref fields — method dispatch base only.

method parseToIR*(lf: LanguageFrontend; sourceCode: string; modulePath: string): FrontendIrNode {.base, raises: [].} =
  ## Translate source code into language-neutral Axiom-IR.
  discard

method injectGuardFromIR*(lf: LanguageFrontend; ir: FrontendIrNode; guardKind: string; sourceCode: string = ""): string {.base, raises: [].} =
  ## Generate a verification-prompt guard block from an IR node.
  ## If sourceCode is provided, the frontend may perform source-level injection.
  defaultInjectGuard(ir, guardKind)

method languageName*(lf: LanguageFrontend): string {.base, raises: [].} =
  ""

method canHandle*(lf: LanguageFrontend; extension: string): bool {.base, raises: [].} =
  false

{.pop.}
