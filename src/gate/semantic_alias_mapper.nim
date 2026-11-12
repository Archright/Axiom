import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

import std/strutils
import std/tables

type
  SemanticGateAlias* = enum
    sgaSieve      ## pre-commit  → Sieve-Gate (판별)
    sgaDiagnosis  ## pre-push    → Diagnosis-Gate (진단)
    sgaGuidance   ## ci-cd       → Guidance-Gate (교정)
    sgaUnknown    ## unrecognized

const
  aliasLookup = toTable {
    "pre-commit": sgaSieve,
    "sieve":      sgaSieve,
    "pre-push":   sgaDiagnosis,
    "diagnosis":  sgaDiagnosis,
    "ci-cd":      sgaGuidance,
    "guidance":   sgaGuidance
  }
  displayNameTable: array[SemanticGateAlias, string] = [
    sgaSieve:     "Sieve-Gate",
    sgaDiagnosis: "Diagnosis-Gate",
    sgaGuidance:  "Guidance-Gate",
    sgaUnknown:   "Unknown-Gate"
  ]
  internalNameTable: array[SemanticGateAlias, string] = [
    sgaSieve:     "pre-commit",
    sgaDiagnosis: "pre-push",
    sgaGuidance:  "ci-cd",
    sgaUnknown:   "unknown"
  ]

func toSemanticAlias*(rawGateName: string): SemanticGateAlias {.raises: [].} =
  aliasLookup.getOrDefault(rawGateName.toLowerAscii(), sgaUnknown)

func toDisplayName*(alias: SemanticGateAlias): string {.raises: [].} =
  displayNameTable[alias]

# axiom:warning-fix — toInternalName declared but not used (keep for future use)
func toInternalName*(alias: SemanticGateAlias): string {.used, raises: [].} =
  internalNameTable[alias]

{.pop.}
