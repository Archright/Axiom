import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

import std/syncio
import core/trusted/stdlib_shield
import core/trusted/axiom_pragmas_lite

proc isolatedMoveFile*(source, dest: string) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  safeMoveFile(source, dest)

proc isolatedWriteFile*(path, content: string) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let tmpPath = path & ".tmp"
  writeFile(tmpPath, content)
  isolatedMoveFile(tmpPath, path)

{.pop.}
