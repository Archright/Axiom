import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Parser Generator — Compile-time Manifest Validation
##
## Validates that data/policy_manifest.json and isKnownSection()
## are in perfect symmetry at compile time. If a section exists
## in one but not the other, compilation fails with a clear error.
##
## "The macro is not a code generator — it is a static prover."
## — Type-Level Invariant Unification design philosophy
##
## Context7 evidence:
## - staticRead: const x = staticRead("file.txt") — verified
## - static: assert — verified
## - error() in macros — verified

import std/macros
import std/json except parseJson
import core/pure/json_parse
import std/sets

# ============================================================
# Manifest SSOT: staticRead at compile time
# ============================================================

const policyManifestJson = staticRead("data/policy_manifest.json")

# ============================================================
# Compile-time validation macro
# ============================================================

macro validateManifestSections*(knownSections: static seq[string]): untyped =
  ## Verifies that every key in policy_manifest.json["sections"]
  ## exists in knownSections, and vice versa.
  ## Fails compilation on any asymmetry.
  let manifest = pureParseJson(policyManifestJson)
  var manifestKeys: HashSet[string]
  for key in manifest["sections"].keys:
    manifestKeys.incl(key)

  var knownSet: HashSet[string]
  for s in knownSections:
    knownSet.incl(s)

  let symDiff = knownSet -+- manifestKeys
  if symDiff.len > 0:
    var msg = "Policy manifest ↔ isKnownSection() asymmetry detected:\n"
    let onlyInKnown = knownSet - manifestKeys
    let onlyInManifest = manifestKeys - knownSet
    if onlyInKnown.len > 0:
      msg.add("  In isKnownSection() but NOT in manifest: " & $onlyInKnown & "\n")
    if onlyInManifest.len > 0:
      msg.add("  In manifest but NOT in isKnownSection(): " & $onlyInManifest & "\n")
    msg.add("Fix: Update data/policy_manifest.json AND isKnownSection() to match.")
    error(msg)

  result = newEmptyNode()

# ============================================================
# Section registry from manifest (generated isKnownSection)
# ============================================================

macro generateSectionRegistry*(): untyped =
  ## Generates a proc that checks section membership
  ## directly from the manifest. This replaces the hardcoded
  ## isKnownSection() function with a manifest-driven version.
  let manifest = pureParseJson(policyManifestJson)
  
  result = newStmtList()
  
  # Generate: func isKnownSection*(section: string): bool =
  #   section in ["meta", "layer", ...]
  let procDef = newProc(
    name = ident("isKnownSection"),
    params = [
      ident("bool"),
      newIdentDefs(ident("section"), ident("string"))
    ],
    body = newStmtList(),
    procType = nnkFuncDef
  )
  
  # Build the array literal
  var arrElements = newNimNode(nnkBracket)
  for key in manifest["sections"].keys:
    arrElements.add(newStrLitNode(key))
  
  procDef.body.add(
    newCall(ident("contains"), arrElements, ident("section"))
  )
  
  result.add(procDef)

# ============================================================
# Compile-time exhaustive section list
# ============================================================

const policySections*: seq[string] = block:
  ## Extract section names from manifest at compile time.
  ## This is the SSOT for section enumeration.
  var sections: seq[string] = @[]
  let m = pureParseJson(policyManifestJson)
  for key in m["sections"].keys:
    sections.add(key)
  sections

# ============================================================
# Validation at module load (eager)
# ============================================================

# This runs at compile time when any module imports parser_gen.
# It verifies the manifest is self-consistent.
static:
  let m = pureParseJson(policyManifestJson)
  var seen: HashSet[string]
  for key in m["sections"].keys:
    if key in seen:
      error("Duplicate section in policy_manifest.json: " & key)
    seen.incl(key)
{.pop.}
