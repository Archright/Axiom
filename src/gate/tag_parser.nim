import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## Gherkin Feature Tag Parser
##
## Deterministic line scanner that extracts tags from .feature files.
## Reads only lines preceding the ``Feature:`` keyword.
## Used by procedure gate to determine @executable vs @manual status.
##
## Complexity: O(lines before Feature), typically <= 5.
import std/strutils
import core/parsers/safe_parsers
import core/results

type
  FeatureTags* = object
    tags*: seq[string]
    specDensity*: int  ## @spec-density <value>; default 50

## Parse Gherkin tags from feature file content.
## Scans only lines preceding the first "Feature:" keyword.
## Tags are whitespace-delimited words starting with '@'.
## Deterministic: identical content → identical FeatureTags.
func parseFeatureTags*(content: string): FeatureTags =
  result = FeatureTags(tags: @[], specDensity: 50)
  for rawLine in content.splitLines():
    let stripped = rawLine.strip()
    if stripped.len == 0:
      continue
    if stripped.startsWith("Feature:"):
      break
    if stripped.startsWith("@"):
      let words = stripped.splitWhitespace()
      var i = 0
      while i < words.len:
        let word = words[i]
        if word.startsWith("@") and word.len > 1:
          let tagName = word[1..^1]
          result.tags.add(tagName)
          if tagName == "spec-density" and i + 1 < words.len:
            let parsed = safeParseInt(words[i + 1])
            if parsed.isOk:
              result.specDensity = parsed.get
              inc i  # skip the value token
        inc i

## Returns true if the parsed tags contain "manual".
## A @manual feature is exempt from automated runner checks.
func isManual*(tags: FeatureTags): bool =
  tags.tags.contains("manual")

## Returns true if the parsed tags contain "legacy".
## A @legacy feature follows deprecated conventions.
func isLegacy*(tags: FeatureTags): bool =
  tags.tags.contains("legacy")

## Returns true if the parsed tags contain "executable".
## Explicit marker that a runner is required (same semantic as absent tag).
func isExecutable*(tags: FeatureTags): bool =
  tags.tags.contains("executable")

## Returns true if the parsed tags contain "spec-density".
func hasSpecDensity*(tags: FeatureTags): bool =
  tags.tags.contains("spec-density")

## Returns the spec-density threshold.  ## Default 50 if not tagged.
func getSpecDensity*(tags: FeatureTags): int =
  tags.specDensity
{.pop.}
