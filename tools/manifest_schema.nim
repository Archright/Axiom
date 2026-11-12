import core/trusted/layer_declaration
axiomLayer "tools"
import api/tools_facade
import shared_types/analysis_bridge
import std/[json, strutils, os, times]
import std/[json, strutils, tables, os, times]
export analysis_bridge.ValidationResult, analysis_bridge.validateManifest
export analysis_bridge.PropertyKind, analysis_bridge.FunctionAnnotation
export analysis_bridge.ModuleEntry, analysis_bridge.ValidProperties
export analysis_bridge.MinModules, analysis_bridge.MinFunctions

## Manifest Schema Validator — CLI entry point.
##
## Nim-native JSON Schema validator for ``bootstrap_manifest.json``.
## Validates structure, uniqueness, and minimum coverage thresholds.
##
## Usage:
##   manifest-schema <path-to-manifest.json>
##
## Exit 0 on valid, 1 on invalid.

proc main() =
  let args = commandLineParams()
  if args.len < 1:
    stderr.writeLine("Usage: manifest-schema <path-to-manifest.json>")
    quit(1)

  let manifestPath = args[0]

  if not fileExists(manifestPath):
    stderr.writeLine("INVALID — file not found: " & manifestPath)
    quit(1)

  let raw = try: readFile(manifestPath) except IOError:
    stderr.writeLine("INVALID — cannot read file: " & manifestPath)
    quit(1)

  let jsonData = try: parseJson(raw) except JsonParsingError as e:
    stderr.writeLine("INVALID — JSON parse error: " & e.msg)
    quit(1)

  let res = validateManifest(jsonData)

  if res.ok:
    echo "VALID"
    echo "  modules:   ", res.moduleCount
    echo "  functions: ", res.functionCount
    quit(0)
  else:
    echo "INVALID"
    echo "  modules:   ", res.moduleCount
    echo "  functions: ", res.functionCount
    echo "  errors:"
    for err in res.errors:
      echo "    - ", err
    quit(1)

when isMainModule:
  main()
