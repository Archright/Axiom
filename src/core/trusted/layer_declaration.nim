## Layer Declaration Pragmas for Architectural Enforcement
## Each module declares its layer using one of these pragmas.
## The layer_enforcement macro validates imports against these declarations.
##
## nim-check: skip — not checkable as a standalone root: discard_result_linter
## is globally injected into every module and imports THIS module for
## axiomLayer, so a standalone check of this file is a recursive-module cycle
## (axiomLayer undeclared at the linter's call site). Integrity is verified by
## the full project build (nimble build). Same policy as PR #519 include
## fragments; harness-level fix is a recorded follow-up.

{.push raises: [].}

template axiomLayer*(layerName: static string) {.pragma.}  ## Module-level layer declaration

template domainLayer*() {.pragma.}        ## src/core/ — Domain logic

template infrastructureLayer*() {.pragma.}  ## src/verification/, src/engine/, src/frontend/, src/infrastructure/

template presentationLayer*() {.pragma.}    ## src/cli/, src/mcp/, src/ui/, src/api/

template gateLayer*() {.pragma.}            ## src/gate/, src/policy/

template toolLayer*() {.pragma.}            ## tools/

## Layer inference lives in core/trusted/layer_enforcement.nim (inferLayer) —
## the single SSOT for the path→layer mapping. The former inferLayerFromPath
## duplicate and Layer* string constants were removed with the DEBT#287
## closed-universe change: they were unreferenced and had already diverged
## from inferLayer (no sieve/shared_types/src-bin cases).
