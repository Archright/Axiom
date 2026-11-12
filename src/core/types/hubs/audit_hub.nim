import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Canonical audit types — SSOT for SAD gate audit results.

type
  AuditResult* = enum
    arPass      ## Real assertions present or exempted
    arStub      ## Compilation-only stub (discard only)
    arExempt    ## @no-sad-required annotation found
    arMissing   ## No test file found

{.pop.}
