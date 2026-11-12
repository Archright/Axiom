import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## Compile-Time Manifest Validator — Phase 5A Shift-Left
##
## This module validates feature_manifest.json at compile time using
## `staticRead` + macros. When imported, the module-scope macro call
## triggers validation automatically.
##
## Note: gate_manifest.json was vestigial (empty `{"gates": []}`).
## Gate registration now uses the per-gate JSON files under src/gate/manifest.d/.
## Its compile-time validation macro was removed.
##
## Errors are reported via `error()` from std/macros (Nim 2.2.10 compatible).
## `{.fatal.}` fires unconditionally in `static:` blocks; `error()` is the
## correct pattern for compile-time validation in macros.

import std/macros
import std/json
import std/strutils
import gate/manifest_schema_validator
import core/ast_lint/axiom_ast_lint

# ─── Feature Manifest Validation ──────────────────────────────────────

macro validateFeatureManifest(): untyped =
  ## Validate data/feature_manifest.json at compile time.
  ## Checks:
  ##   1. "features" key exists
  ##   2. Value is a JSON array
  ##   3. No @pending tags (names collected and reported)
  let content = staticRead("../../data/feature_manifest.json")
  let manifest = parseJson(content)

  if not manifest.hasKey("features"):
    error("feature_manifest.json: missing 'features' key. " &
          "Run: nim c -r tools/feature_scaffold_generator.nim")

  let features = manifest["features"]
  if features.kind != JArray:
    error("feature_manifest.json: 'features' must be a JSON array")

  var pendingNames: seq[string] = @[]
  for feat in features:
    if feat.hasKey("tags"):
      for tag in feat["tags"]:
        if tag.getStr() == "@pending":
          if feat.hasKey("name"):
            pendingNames.add(feat["name"].getStr())
          else:
            pendingNames.add("<unnamed>")

  if pendingNames.len > 0:
    error("feature_manifest.json: " & $pendingNames.len &
          " @pending features detected: " & pendingNames.join(", ") &
          ". All features must be resolved before build.")

# ─── Gate Manifest Validation ─────────────────────────────────────────

macro validateGateManifests(): untyped =
  ## Validate all gate manifest JSON files at compile time.
  ## Reads _index.json, loads each file, validates against schema rules
  ## and checks 'after' closure completeness.
  let indexContent = staticRead("../../gate/manifest.d/_index.json")
  var nodes: seq[JsonNode]
  for line in indexContent.splitLines():
    let stripped = line.strip()
    if stripped.len > 0:
      let content = staticRead("../../gate/manifest.d/" & stripped)
      nodes.add(parseJson(content))

  let errors = validateAllGateNodes(nodes)
  if errors.len > 0:
    error("Gate manifest validation FAILED:\n" & errors.join("\n"))

  let closureErrors = checkAfterClosure(nodes)
  if closureErrors.len > 0:
    error("Gate 'after' closure validation FAILED:\n" & closureErrors.join("\n"))

# ─── Module-Scope Triggers ────────────────────────────────────────────
# These macro calls execute at compile time when this module is imported.
# No runtime code is generated — Zero-Artifact principle.

validateFeatureManifest()
validateGateManifests()

# Track-A AST lint (axiom_ast_lint) is linked via the import at line 21; its
# module-scope `static:` block runs AGENTS.md / memory-policy / SSOT checks
# on every compile. Reference a symbol so the import is not flagged unused.
static:
  discard compiles(fileHasFfiPragma(""))
