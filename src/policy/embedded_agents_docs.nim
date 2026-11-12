## Embedded Agents Docs (Zero-Input Knowledge Base)
##
## This file is AUTO-GENERATED at build time from AGENTS.md and docs/agents/*.md.
## Do NOT edit manually. Run `nimble generate-docs` to regenerate.
##
## All policy documents are embedded as Nim constants so that
## bin/axiom-local-docs-lookup can answer policy questions without any
## runtime file system reads.

{.push raises: [].}

const AgentsMd* = staticRead("../../AGENTS.md")
const ArchitectureMd* = staticRead("../../docs/agents/architecture.md")
const RulesWorkflowMd* = staticRead("../../docs/agents/rules_workflow.md")
const EmbeddedDocs* = [
  ("AGENTS.md", AgentsMd),
  ("architecture.md", ArchitectureMd),
  ("rules_workflow.md", RulesWorkflowMd)]

{.pop.}
