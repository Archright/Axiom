## feature_manifest_guard.nim — Compile-time guard for manifest existence
## Import this module to enforce that data/feature_manifest.json exists.
## If missing, compilation fails with a clear error message.
##
## Usage: import core/feature_manifest_guard
##   (in files that depend on the feature manifest at compile time)

import core/trusted/layer_declaration
axiomLayer "domain"
import std/os
{.push raises: [].}

const manifestPath {.strdefine.} = "data/feature_manifest.json"

# Auto-check on import (derive project root: src/core/file.nim → src/core → src → project root)
# QUIRK(DEBT#453): currentSourcePath() returns string in const context;
# wrapping in LogicalPath would break const evaluation. Deferred per plan §2.
const projectRoot = parentDir(parentDir(parentDir(currentSourcePath())))
const absManifestPath = projectRoot / manifestPath
when not fileExists(absManifestPath):
  {.error: "data/feature_manifest.json missing. Run: nim c -r tools/feature_manifest_generator.nim".}

{.pop}
