import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [].}

## generate_agents_docs.nim — docs/agents/*.md auto-generator
##
## Reads src/gate/architecture_policy.lock (INI-like lockfile) and generates
## docs/agents/memory_policy.md from the [memory_policy_markers] section.
## Lock is the SSOT; generated docs are read-only downstream artifacts.
##
## Ported from tools/generate_agents_docs.py
##
## Usage:
##   nim c -r tools/generate_agents_docs.nim
##   nim c -d:release -o:bin/generate_agents_docs tools/generate_agents_docs.nim

import std/[os, strutils, algorithm]

# ── Constants ──────────────────────────────────────────────────────────────

const
  LockPath = "src/gate/architecture_policy.lock"
  OutputDir = "docs/agents"
  OutputFile = OutputDir / "memory_policy.md"

# ── Types ──────────────────────────────────────────────────────────────────

type
  LockSections = seq[tuple[section: string, pairs: seq[tuple[key, val: string]]]]

# ── Pure helpers ───────────────────────────────────────────────────────────

func parseLock(content: string): LockSections {.raises: [].} =
  ## Parse the simple section-based lockfile grammar into an ordered
  ## sequence of (section, pairs) tuples.  Preserves insertion order.
  var currentSection = -1
  for rawLine in content.splitLines():
    let stripped = rawLine.strip()
    if stripped.len == 0 or stripped.startsWith("#"):
      continue
    if stripped.startsWith("[") and stripped.endsWith("]"):
      let name = stripped[1 .. ^2]
      currentSection = result.len
      result.add((section: name, pairs: @[]))
      continue
    if currentSection < 0 or "=" notin stripped:
      continue
    let eqPos = stripped.find('=')
    let key = stripped[0 .. eqPos - 1].strip()
    var val = stripped[eqPos + 1 .. ^1].strip()
    # Strip surrounding double-quotes if present
    if val.len >= 2 and val.startsWith("\"") and val.endsWith("\""):
      val = val[1 .. ^2]
    result[currentSection].pairs.add((key: key, val: val))

func getSectionPairs(sections: LockSections, name: string): seq[tuple[key, val: string]] =
  ## Return key-value pairs for the named section, or empty seq.
  for s in sections:
    if s.section == name:
      return s.pairs
  return @[]

func generateMemoryPolicyDoc(markers: seq[tuple[key, val: string]]): string =
  ## Build the memory_policy.md markdown content.
  var lines: seq[string]
  lines.add("# Memory Policy")
  lines.add("")
  lines.add("This file is **auto-generated** from `[memory_policy_markers]` in " &
    "`src/gate/architecture_policy.lock`. Do not edit manually.")
  lines.add("")
  lines.add("AGENTS.md must contain the following markers verbatim:")
  lines.add("")

  # Sort markers by key for deterministic output
  var sortedMarkers = markers
  sortedMarkers.sort(proc (a, b: tuple[key, val: string]): int =
    cmp(a.key, b.key)
  )

  for m in sortedMarkers:
    lines.add("- **" & m.key & "**: `" & m.val & "`")
  lines.add("")
  lines.add("## Rationale")
  lines.add("")
  lines.add("Project policy, rules, and conventions must live in `AGENTS.md`, " &
    "not in agent session memory or ephemeral notes. " &
    "These markers are enforced by the memory-policy lockfile at " &
    "`src/gate/architecture_policy.lock`.")
  lines.add("")
  lines.join("\n")

# ── I/O boundary ───────────────────────────────────────────────────────────

proc readFileContent(path: string): string {.raises: [CatchableError].} =
  readFile(path)

proc writeIfChanged(path, content: string): bool {.raises: [CatchableError].} =
  ## Only write if content differs (idempotent). Returns true if written.
  if fileExists(path):
    let existing = readFile(path)
    if existing == content:
      return false
  createDir(path.parentDir())
  writeFile(path, content)
  result = true

proc echoStdout(msg: string) {.raises: [].} =
  echo msg

# ── Main ───────────────────────────────────────────────────────────────────

proc main(): int {.raises: [CatchableError].} =
  if not fileExists(LockPath):
    echoStdout("generate_agents_docs: ERROR: " & LockPath & " not found")
    return 1

  let content = readFileContent(LockPath)
  let sections = parseLock(content)
  let markers = getSectionPairs(sections, "memory_policy_markers")

  if markers.len == 0:
    echoStdout("generate_agents_docs: no [memory_policy_markers] section found")
    return 1

  let doc = generateMemoryPolicyDoc(markers)
  let written = writeIfChanged(OutputFile, doc)
  if written:
    echoStdout("generate_agents_docs: generated docs/agents/memory_policy.md")
  else:
    echoStdout("generate_agents_docs: docs/agents/memory_policy.md up to date")

  return 0

when isMainModule:
  let exitCode = main()
  if exitCode != 0:
    quit(exitCode)

{.pop.}
