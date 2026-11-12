import core/trusted/layer_declaration
axiomLayer "tools"
# AgentSwarm Prompt Template — Artefact Producer Protocol
#
# 이 템플릿은 AgentSwarm 호출 시 prompt_template으로 사용됩니다.
# {{item}} 플레이스홀더에 각 서브에이전트의 구체적 작업이 삽입됩니다.

const PROMPT_TEMPLATE* = """
## Task
{{item}}

## Artefact Producer Protocol v1.0 (MANDATORY)

You MUST follow this protocol exactly. Failure to do so will result in deterministic task failure.

### Step 1: Generate Code
Use the Write tool to create source files in your isolated workspace.

### Step 2: Read Back Content
Use the Read tool to read each file you created. Record the full content.

### Step 3: Encode and Hash
For EACH file, run these Bash commands:
```bash
# Base64 encode (no line breaks)
base64 <filepath> | tr -d '\n'

# SHA-256 hash of ORIGINAL content (not base64)
sha256sum <filepath> | cut -d' ' -f1
```

### Step 4: Construct JSON Payload
Build a JSON object with this EXACT schema:
```json
{
  "v": "1.0",
  "files": [
    {
      "p": "<project-relative-path>",
      "c": "<base64-encoded-content>",
      "h": "<sha256-hex-hash>"
    }
  ]
}
```

### Step 5: Call YieldArtifact
Call YieldArtifact with:
- payload: the JSON object from Step 4
- finalize: true

### Rules
- ALL file contents MUST be Base64 encoded (no raw strings in JSON)
- SHA-256 hash is of the ORIGINAL binary content, NOT the base64 string
- Paths MUST be relative to project root (e.g., "src/core/gate/foo.nim")
- The "h" field MUST be exactly 64 lowercase hex characters
- If creating multiple files, include ALL files in a single payload
- For files >100KB, use chunked YieldArtifact (finalize=false for intermediate, finalize=true for last)
"""

# AgentSwarm 호출 예시 (오케스트레이터에서 사용):
#
# AgentSwarm(
#   prompt_template=PROMPT_TEMPLATE,
#   items=[
#     "Create src/core/gate/cache_manifest.nim — a cache manifest generator",
#     "Create src/core/gate/merge_defs.nim — a gate definition merger",
#     "Create src/core/gate/orchestrator_hook.nim — an orchestrator hook handler"
#   ],
#   output_mode="artifact"
# )
