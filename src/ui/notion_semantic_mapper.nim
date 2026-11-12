import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [].}
## Notion Spec Semantic Localization Mapper
## Maps internal orchestration statuses to Notion-spec gate names.
## SSOT: https://app.notion.com/p/344c1d573f3f802299b5fecd0086e0a7

import std/strutils
import std/json

type
  NotionGateKind* = enum
    ngkSieve     ## The Sieve — Proven vs Unverifiable classification
    ngkDiagnosis ## The Diagnosis — Mathematical discontinuity specification
    ngkGuidance  ## The Guidance — Refactoring patterns & deterministic correction

const GateLocalizedNames*: array[NotionGateKind, string] = [
  "Sieve-Gate",
  "Diagnosis-Gate",
  "Guidance-Gate"
]

const GateLocalizedDescriptions*: array[NotionGateKind, string] = [
  "Proven vs Unverifiable classification",
  "Mathematical discontinuity specification",
  "Deterministic correction via f×g×h integrity patterns"
]

const koJsonData = staticRead("../../data/i18n/ko.json")

const koGateNames: array[NotionGateKind, string] = static:
  let parsed = parseJson(koJsonData)
  [
    parsed["gates"]["sieve"]["name"].getStr(),
    parsed["gates"]["diagnosis"]["name"].getStr(),
    parsed["gates"]["guidance"]["name"].getStr()
  ]

const koGateDescriptions: array[NotionGateKind, string] = static:
  let parsed = parseJson(koJsonData)
  [
    parsed["gates"]["sieve"]["description"].getStr(),
    parsed["gates"]["diagnosis"]["description"].getStr(),
    parsed["gates"]["guidance"]["description"].getStr()
  ]

# axiom:warning-fix — mapOrchestrationStatusToGate declared but not used (keep for future use)
func mapOrchestrationStatusToGate*(status: string): NotionGateKind {.used, raises: [].} =
  let lower = status.toLowerAscii
  if lower.contains("verified") or lower.contains("proven") or
     lower.contains("unverifiable") or lower.contains("sieve"):
    ngkSieve
  elif lower.contains("counter_example") or lower.contains("diagnosis") or
       lower.contains("discontinuity") or lower.contains("failed"):
    ngkDiagnosis
  elif lower.contains("blocked") or lower.contains("guidance") or
       lower.contains("refactor") or lower.contains("heal"):
    ngkGuidance
  else:
    ngkSieve

func renderGateLabel*(gate: NotionGateKind; locale: string = "en"): string {.raises: [].} =
  if locale == "ko":
    "[" & koGateNames[gate] & "]"
  else:
    "[" & GateLocalizedNames[gate] & "]"

func renderGateSectionHeader*(gate: NotionGateKind; locale: string = "en"): string {.raises: [].} =
  let label = renderGateLabel(gate, locale)
  let desc = if locale == "ko": koGateDescriptions[gate] else: GateLocalizedDescriptions[gate]
  "━━━ " & label & " ━━━ " & desc
{.pop.}

