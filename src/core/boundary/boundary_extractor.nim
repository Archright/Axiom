import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

import std/tables

## Module rename alias table.
## Maps legacy module names (from old nodeIds) to current file names.
## Maintains pipeline continuity across refactorings without rewriting nodeId history.
const moduleAliasTable* = {
  "cli_utils.nim": "file_utils.nim",
}.toTable()

# Split sub-module — proper import (module is fully self-contained with exports)
import core/boundary/boundary_extraction_types
import core/boundary/boundary_extraction_helpers
import core/boundary/boundary_extraction_main
export boundary_extraction_types
export boundary_extraction_helpers
export boundary_extraction_main

# ── imported sub-modules ──
# part1: extractBoundaries and related procs
import boundary_extractor_part1
export boundary_extractor_part1

# part1_part1: generateHintFromParamTypes, formatAxiomHintComment, virtual hint injection
import boundary_extractor_part1_part1
export boundary_extractor_part1_part1

{.pop.}
