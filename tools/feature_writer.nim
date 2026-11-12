## Isolated file generator for BDD feature files.
## Separate binary — uses collectFeatureSpecs macro to read type definitions
## at compile time and generate .feature files at runtime.
## This is a RUNTIME tool — run via `make generate-features`.

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils]
import tools/feature_gen_macro
import shared_types/shared_types

# Collect feature specs at compile time:
# - Types are resolved via `typed` parameter (getImpl works)
# - Descriptions are passed as a static seq (human-authored metadata)
const featureSpecs* = collectFeatureSpecs(
  [AuditEntry, HealthLevel],
  @["Audit record for gate execution", "Gate health assessment levels"]
)

proc writeFeature(spec: FeatureSpec) =
  var feature = "Feature: " & spec.typeName & "\n"
  feature &= "  " & spec.description & "\n\n"
  feature &= "  Scenario: " & spec.typeName & " is properly defined\n"
  feature &= "    Given the " & spec.typeName & " type exists\n"
  feature &= "    Then it should be accessible from the audit subsystem\n"
  writeFile("tests/features/" & spec.typeName.toLower & ".feature", feature)
  echo "Generated: tests/features/" & spec.typeName.toLower & ".feature"

proc main() =
  createDir("tests/features")
  for spec in featureSpecs:
    writeFeature(spec)

main()
