## restructure_agents.nim — Port of restructure_agents.py
##
## Reads AGENTS.md, splits on ## §N headings, extracts §1 (architecture)
## and §2 (rules/workflow) into docs/agents/ files, inserts memory policy
## markers into §0, replaces §1/§2 with stub summaries, and rewrites AGENTS.md.

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils]

type
  Sections = object
    entries: seq[tuple[key, content: string]]

# ---------------------------------------------------------------------------
# Pure helpers (func — no side effects)
# ---------------------------------------------------------------------------

func trimTrailingNl(s: string): string =
  result = s
  while result.len > 0 and result[^1] == '\n':
    result.setLen(result.len - 1)

func sectionIndex(sections: Sections, key: string): int =
  result = -1
  for i, entry in sections.entries:
    if entry.key == key:
      return i

func getSection(sections: Sections, key: string): string =
  let idx = sectionIndex(sections, key)
  if idx >= 0:
    return sections.entries[idx].content
  return ""

func setSection(sections: var Sections, key, content: string) =
  let idx = sectionIndex(sections, key)
  if idx >= 0:
    sections.entries[idx].content = content
  else:
    sections.entries.add((key: key, content: content))

func extractSectionKey(line: string): string =
  ## Extract key from heading like "## §1. ARCHITECTURE". Returns "" on no match.
  ## "## §" is 5 bytes in UTF-8 (§ = 0xC2 0xA7).
  if not line.startsWith("## §"):
    return ""
  # Skip "## §" (5 bytes), then read digits and optional hyphen
  const prefixLen = 5 # len("## §") in bytes
  var pos = prefixLen
  while pos < line.len and (line[pos].isDigit() or line[pos] == '-'):
    inc pos
  if pos == prefixLen:
    return ""
  return line[prefixLen ..< pos]

func splitOnHeadings(text: string): seq[string] =
  ## Split text on lines starting with "## §", keeping delimiters.
  result = @[]
  var current = ""
  for line in text.splitLines():
    if line.startsWith("## §"):
      if current.len > 0:
        result.add(current)
      current = line & "\n"
    else:
      current.add(line & "\n")
  if current.len > 0:
    result.add(current)

func parseSections(text: string): Sections =
  result = Sections()
  let parts = splitOnHeadings(text)
  for p in parts:
    let trimmed = trimTrailingNl(p)
    if trimmed.strip().len == 0:
      continue
    let firstLine = trimmed.splitLines()[0]
    let key = extractSectionKey(firstLine)
    if key.len > 0:
      result.entries.add((key: key, content: trimmed))
    else:
      result.entries.add((key: "preamble", content: trimmed))

func insertAfter04b(s0: string, markerBlock: string): string =
  ## Insert memory policy markers before ### 0.5.
  let anchor = "### 0.5 "
  let pos05 = s0.find(anchor)
  if pos05 < 0:
    return s0 & markerBlock
  let nlBefore = s0.rfind("\n", 0, pos05 - 1)
  if nlBefore >= 0:
    return s0[0 .. nlBefore] & markerBlock & s0[nlBefore + 1 .. ^1]
  return markerBlock & s0

func reassemble(sections: Sections): string =
  const order = ["preamble", "-1", "0", "1", "2", "3", "4"]
  var parts: seq[string] = @[]
  for key in order:
    let content = getSection(sections, key)
    if content.len > 0:
      parts.add(trimTrailingNl(content))
  result = parts.join("\n\n---\n\n") & "\n"

# ---------------------------------------------------------------------------
# I/O procs
# ---------------------------------------------------------------------------

proc readInput(path: string): string =
  readFile(path)

proc writeOutput(path, content: string) =
  let d = parentDir(path)
  if d.len > 0 and not dirExists(d):
    createDir(d)
  writeFile(path, content)

proc printMsg(msg: string) =
  echo msg

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

proc main() =
  let text = readInput("AGENTS.md")
  var sections = parseSections(text)

  # --- Extract §1 and §2 to docs/agents/ ---
  let archFull = getSection(sections, "1")
  let rulesFull = getSection(sections, "2")

  writeOutput("docs/agents/architecture.md",
    archFull & "\n\n<!-- Extracted from AGENTS.md §1 to keep AGENTS.md under the context-size threshold. -->\n")
  writeOutput("docs/agents/rules_workflow.md",
    rulesFull & "\n\n<!-- Extracted from AGENTS.md §2 to keep AGENTS.md under the context-size threshold. -->\n")

  # --- Build replacement stubs ---
  const newS1 = """## §1. ARCHITECTURE

The full architecture specification — module structure, layers, gates, and design decisions — has been moved to [docs/agents/architecture.md](docs/agents/architecture.md) to keep AGENTS.md within the context-size threshold.

High-level decisions remain part of the constitution:

- **CLI First**, **MCP as Extension**, **Language Ban** (Nim only).
- **Layered Gate Architecture** and **4-Layer Resource Defense Stack**.
- **Verification Workflow**: `ax prove` → Topology Analysis → Batch UAP → 4-Layer Pipeline (Scout / Detective / Scribe / Judge).
- Core architectural principles: SOLID, SoC, SSOT, DRY, Import Encapsulation, Forwarding Stub discipline."""

  const newS2 = """## §2. RULES & WORKFLOW

The full rules and workflow specification has been moved to [docs/agents/rules_workflow.md](docs/agents/rules_workflow.md) to keep AGENTS.md under the context-size threshold.

Core principles retained here:

- **Knowledge Load Protocol**: Constitution → Ordinance → Annals → Guardian.
- **Tool Usage**: `code-index` for source, native tools for writes.
- **Parallel-First Mandate** with 300-second subagent timeout.
- **Incremental Principle**: pre-commit gates scan only changed files.
- **Rebase-Only Sync** via `bin/sync-branch`; no direct `git merge`/`git rebase`.
- **Agent Branch Sync** and **Git Immunity** rules protect workspace state."""

  # --- Insert memory policy markers into §0 ---
  # Korean: 메모리에 기록하지 말 것 / 프로젝트 정책/규칙/컨벤션은 모두 AGENTS.md에
  # Unicode: U+BA54=메 U+BAA8=모 U+B9AC=리 U+C5D0=에 U+AE30=기 U+B85D=록
  #          U+D558=하 U+C9C0=지 U+B9D0=말 U+AC83=것 U+D504=프 U+B85C=로
  #          U+C81D=젝 U+D2B8=트 U+C815=정 U+CC45=책 U+ADDC=규 U+CE59=칙
  #          U+CEE8=컨 U+BCA4=벤 U+C158=션 U+C740=은 U+B450=두
  const markerBlock = "\n### 0.4c Memory Policy Markers (HARD RULE)\n\n- **\uBA54\uBAA8\uB9AC\uC5D0 \uAE30\uB85D\uD558\uC9C0 \uB9D0 \uAC83**\n- **\uD504\uB85C\uC81D\uD2B8 \uC815\uCC45/\uADDC\uCE59/\uCEE8\uBCA4\uC158\uC740 \uBAA8\uB450 AGENTS.md\uC5D0**\n\nProject policy must live in `AGENTS.md` and `docs/agents/`, not in agent session memory or ephemeral notes. See [docs/agents/memory_policy.md](docs/agents/memory_policy.md) for the machine-readable SSOT.\n"

  var s0 = getSection(sections, "0")

  # Insert after ### 0.4b Skills SSOT Boundary block (before ### 0.5)
  var s0New = insertAfter04b(s0, markerBlock)
  if s0New == s0:
    # Fallback: force insert before ### 0.5
    let pos05 = s0.find("### 0.5 ")
    if pos05 >= 0:
      let nlPos = s0.rfind("\n", 0, pos05 - 1)
      if nlPos >= 0:
        s0New = s0[0 .. nlPos] & markerBlock & s0[nlPos + 1 .. ^1]
      else:
        s0New = markerBlock & s0

  # Apply all section mutations
  setSection(sections, "0", s0New)
  setSection(sections, "1", trimTrailingNl(newS1))
  setSection(sections, "2", trimTrailingNl(newS2))

  # --- Rewrite AGENTS.md ---
  let newText = reassemble(sections)
  writeOutput("AGENTS.md", newText)

  printMsg("AGENTS.md restructured")
  printMsg("docs/agents/architecture.md written")
  printMsg("docs/agents/rules_workflow.md written")

when isMainModule:
  main()
