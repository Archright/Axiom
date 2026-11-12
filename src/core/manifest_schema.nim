{.push raises: [].}
## Manifest Schema — Canonical type definitions and validation logic.
##
## Pure, effect-free module (AGENTS.md §0.6). No I/O, no side effects.
## Used by: manifest_integrity_gate, analysis_bridge (re-export), tools/manifest_schema.
##
## Types: PropertyKind, FunctionAnnotation, ModuleEntry, ValidationResult.
## Procs: validateManifest*.

import core/trusted/layer_declaration
axiomLayer "domain"
import std/[json, strutils]

type
  PropertyKind* = enum
    pkIdempotent = "idempotent"
    pkAssociative = "associative"
    pkCommutative = "commutative"
    pkIdentity = "identity"
    pkRoundtrip = "roundtrip"
    pkTotality = "totality"
    pkMonotone = "monotone"

  FunctionAnnotation* = object
    properties*: seq[string]  ## PropertyKind string values
    inputTypes*: seq[string]
    outputType*: string
    comment*: string

  ModuleEntry* = object
    path*: string
    functions*: seq[tuple[name: string, annotation: FunctionAnnotation]]

  ValidationResult* = object
    ok*: bool
    errors*: seq[string]
    moduleCount*: int
    functionCount*: int

const
  ValidProperties* = ["idempotent", "associative", "commutative", "identity",
                      "roundtrip", "totality", "monotone"]
  MinModules* = 20
  MinFunctions* = 50

func safeGet*(node: JsonNode; key: string): JsonNode {.raises: [].} =
  ## Safe JSON field access that returns JNull on missing keys.
  try:
    result = node[key]
  except KeyError:
    result = newJNull()

func validateManifest*(manifest: JsonNode): ValidationResult =
  ## Validate a parsed JSON manifest against the schema rules.
  ## Returns a ValidationResult with ok=true if all checks pass.
  result.ok = true
  result.errors = @[]
  result.moduleCount = 0
  result.functionCount = 0

  # 1. Required top-level: "version" (string), "modules" (array)
  let verNode = safeGet(manifest, "version")
  if verNode.kind == JNull:
    result.errors.add("missing required top-level field: 'version'")
    result.ok = false
  elif verNode.kind != JString:
    result.errors.add("'version' must be a string")
    result.ok = false

  let modulesNode = safeGet(manifest, "modules")
  if modulesNode.kind == JNull:
    result.errors.add("missing required top-level field: 'modules'")
    result.ok = false
    return
  elif modulesNode.kind != JArray:
    result.errors.add("'modules' must be an array")
    result.ok = false
    return

  let modules = modulesNode
  result.moduleCount = modules.len

  # Check minimum module count
  if modules.len < MinModules:
    result.errors.add("module count " & $modules.len &
                       " below minimum " & $MinModules)
    result.ok = false

  # Track duplicate detection
  var seenModulePaths: seq[string]

  for mi in 0 ..< modules.len:
    let modNode = modules[mi]
    let modPrefix = "modules[" & $mi & "]"

    # 2. Each module: "path" (string, starts with "src/"), "functions" (array)
    let pathNode = safeGet(modNode, "path")
    if pathNode.kind == JNull:
      result.errors.add(modPrefix & " missing required field: 'path'")
      result.ok = false
      continue

    if pathNode.kind != JString:
      result.errors.add(modPrefix & " 'path' must be a string")
      result.ok = false
      continue

    let modulePath = pathNode.getStr()

    if not modulePath.startsWith("src/"):
      result.errors.add(modPrefix & " 'path' must start with 'src/' (got: '" &
                         modulePath & "')")
      result.ok = false

    # 4. No duplicate module paths
    if modulePath in seenModulePaths:
      result.errors.add(modPrefix & " duplicate module path: '" & modulePath & "'")
      result.ok = false
    seenModulePaths.add(modulePath)

    let funcsNode = safeGet(modNode, "functions")
    if funcsNode.kind == JNull:
      result.errors.add(modPrefix & " missing required field: 'functions'")
      result.ok = false
      continue

    if funcsNode.kind != JArray:
      result.errors.add(modPrefix & " 'functions' must be an array")
      result.ok = false
      continue

    let functions = funcsNode
    var seenFuncNames: seq[string]

    for fi in 0 ..< functions.len:
      let funcNode = functions[fi]
      let funcPrefix = modPrefix & ".functions[" & $fi & "]"
      inc result.functionCount

      # 3. Each function: "name" (string, non-empty), "properties" (non-empty array)
      let nameNode = safeGet(funcNode, "name")
      if nameNode.kind == JNull:
        result.errors.add(funcPrefix & " missing required field: 'name'")
        result.ok = false
        continue

      if nameNode.kind != JString:
        result.errors.add(funcPrefix & " 'name' must be a string")
        result.ok = false
        continue

      let funcName = nameNode.getStr()
      if funcName.len == 0:
        result.errors.add(funcPrefix & " 'name' must be non-empty")
        result.ok = false

      # 5. No duplicate function names within a module
      if funcName in seenFuncNames:
        result.errors.add(funcPrefix & " duplicate function name: '" & funcName &
                           "' in module '" & modulePath & "'")
        result.ok = false
      seenFuncNames.add(funcName)

      let propsNode = safeGet(funcNode, "properties")
      if propsNode.kind == JNull:
        result.errors.add(funcPrefix & " missing required field: 'properties'")
        result.ok = false
        continue

      if propsNode.kind != JArray:
        result.errors.add(funcPrefix & " 'properties' must be an array")
        result.ok = false
        continue

      let properties = propsNode
      if properties.len == 0:
        result.errors.add(funcPrefix & " 'properties' must be non-empty")
        result.ok = false

      for pi in 0 ..< properties.len:
        let propNode = properties[pi]
        if propNode.kind != JString:
          result.errors.add(funcPrefix & ".properties[" & $pi &
                             "] must be a string")
          result.ok = false
          continue
        let propVal = propNode.getStr()
        if propVal notin ValidProperties:
          result.errors.add(funcPrefix & ".properties[" & $pi &
                             "] invalid property: '" & propVal &
                             "' (valid: " & ValidProperties.join(", ") & ")")
          result.ok = false

  # 6. Check minimum function count
  if result.functionCount < MinFunctions:
    result.errors.add("function count " & $result.functionCount &
                       " below minimum " & $MinFunctions)
    result.ok = false
