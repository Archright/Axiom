import core/trusted/layer_declaration
axiomLayer "gate"
import std/os
from core/utils/repo_root import findRepoRoot

## documentation_first_gate_types
## Constants, types, and module-level state extracted from documentation_first_gate

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const
  GateTag* = "[documentation-first]"
  ConfigRelPath* = "src" / "gate" / "configs" / "documentation_first.json"
  HistoryFileName* = "gate_history.jsonl"
  GateId* = "documentation-first"

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

type
  TriggerConfig* = object
    keyword*: string
    severity*: string
    description*: string
    docUrl*: string

  Issue* = object
    ruleId*: string
    severity*: string
    filePath*: string
    line*: int
    message*: string
    component*: string

# ---------------------------------------------------------------------------
# Paths (deterministic root resolution)
# ---------------------------------------------------------------------------

let
  repoDir* = findRepoRoot()
  configPath* = repoDir / ConfigRelPath
  evidenceDir* = repoDir / "docs" / "evidence"
  historyPath* = getHomeDir() / ".axiom" / HistoryFileName
  debugMarker* = repoDir / ".axiom" / "debug_mode_on"
