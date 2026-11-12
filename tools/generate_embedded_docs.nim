## generate_embedded_docs.nim
## Regenerates src/policy/embedded_agents_docs.nim from local markdown SSOT.
## This is a build-time helper; it is NOT part of the runtime binary.

import core/trusted/layer_declaration
axiomLayer "tools"
import std/os
import generate_agents_docs

const
  OutputPath = "src/policy/embedded_agents_docs.nim"
  # (display name, const identifier, path relative to project root, path for staticRead from src/policy/)
  Docs = [
    ("AGENTS.md", "AgentsMd", "AGENTS.md", "../../AGENTS.md"),
    ("architecture.md", "ArchitectureMd", "docs/agents/architecture.md", "../../docs/agents/architecture.md"),
    ("rules_workflow.md", "RulesWorkflowMd", "docs/agents/rules_workflow.md", "../../docs/agents/rules_workflow.md")
  ]

proc findProjectRoot(): string =
  ## Walk up from current directory until .axiom_root is found.
  var d = getCurrentDir()
  for i in 0..20:
    if fileExists(d / ".axiom_root"):
      return d
    let parent = parentDir(d)
    if parent == d:
      break
    d = parent
  stderr.writeLine("ERROR: could not find project root (.axiom_root)")
  quit(1)

proc main() =
  let root = findProjectRoot()
  var consts = ""
  var array = ""
  for (name, ident, rootRelPath, staticRelPath) in Docs:
    let fullPath = root / rootRelPath
    if not fileExists(fullPath):
      stderr.writeLine("ERROR: policy doc missing: " & fullPath)
      quit(1)
    let content = readFile(fullPath)
    if content.len == 0:
      stderr.writeLine("ERROR: policy doc empty: " & fullPath)
      quit(1)
    consts.add("const " & ident & "* = staticRead(\"" & staticRelPath & "\")\n")
    if array.len > 0: array.add(",\n")
    array.add("  (\"" & name & "\", " & ident & ")")

  let output = """## Embedded Agents Docs (Zero-Input Knowledge Base)
##
## This file is AUTO-GENERATED at build time from AGENTS.md and docs/agents/*.md.
## Do NOT edit manually. Run `nimble generate-docs` to regenerate.
##
## All policy documents are embedded as Nim constants so that
## bin/axiom-local-docs-lookup can answer policy questions without any
## runtime file system reads.

{.push raises: [].}

""" & consts & """
const EmbeddedDocs* = [
""" & array & """
]

{.pop.}
"""

  let outPath = root / OutputPath
  writeFile(outPath, output)
  echo "[generate-embedded-docs] Wrote " & outPath

when isMainModule:
  main()
