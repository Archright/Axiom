import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

import std/strutils

func makeLabel*(sourceFile: string, sourceLine: int, semantic: string): string {.raises: [].} =
  ## Generate lossless assertion label: <file>L<line>_<semantic>
  let sanitized = sourceFile.replace("/", "_").replace(".", "_").replace("-", "_")
  sanitized & "L" & $sourceLine & "_" & semantic

{.pop.}

{.pop.}
