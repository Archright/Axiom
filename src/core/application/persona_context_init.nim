import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## PersonaContext Init — Application-layer composition root.
##
## Per ADR-014: `core/application/` is the Application layer. This module is
## the single Application-owned crossing into Infrastructure. It delegates
## wiring to focused composition modules under `verification/composition/`,
## one per bounded context.
##
## Personas receive a fully wired `PersonaContext` and call through it.

import core/application/persona_context
## KNOWN EXCEPTION: ADR-014 composition root
## (docs/history/ADR-014-extract-application-context-layer.md, Status: Accepted:
##  "The single Application-owned crossing into Infrastructure is
##   persona_context_init.nim").
## This module is the single Application-owned crossing into Infrastructure.
## Direct verification/ imports are intentional per architecture §1.2.
## (Formerly cited as DEBT#244 — that ID has no entry in
##  data/debt_registry.json; ghost reference removed 2026-10-11.)
import verification/composition/leanstral_registry
import verification/composition/scan_registry
import verification/composition/bmc_registry
import verification/composition/cegar_registry
import verification/composition/healing_registry

func initPersonaContext*(): PersonaContext {.raises: [].} =
  ## Factory: wires every verification callback into the context.
  ## Aborts immediately if any callback is left nil.
  result = PersonaContext()
  result.registerLeanstral()
  result.registerScan()
  result.registerBmc()
  result.registerCegar()
  result.registerHealing()
  result.validate()

## Default module-level PersonaContext shared by all personas.
## Eliminates DRY duplication of `let ctx = initPersonaContext()`.
let defaultPersonaCtx* = initPersonaContext()

{.pop.}
