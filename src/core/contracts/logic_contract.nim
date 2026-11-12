import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

## Logic Contract — Facade for persona→logic dependencies.
##
## [WARN] MAINTENANCE: core/logic/에 새 API 추가 시 반드시 이 파일의 re-export 목록을 업데이트하세요.
## 위반 시 import_encapsulation_gate가 personas/의 새 import를 차단합니다.
##
## Exposes only the symbols that personas actually use.
## I/O procs are included but marked as axiomIoBoundary in source modules.
##
## SSOT: core/logic/*.nim modules are the single source of truth.

# --- Type re-exports (full module forwarding) ---
from core/logic/universal_translation_types import nil
export universal_translation_types

from core/logic/pipeline_fingerprint_engine import nil
export pipeline_fingerprint_engine

from core/logic/pipeline_verdict_engine import nil
export pipeline_verdict_engine

# --- Type + function re-exports (full module forwarding for type-rich modules) ---
from core/logic/pipeline_trace_artifacts import nil
export pipeline_trace_artifacts

from core/logic/pipeline_healing_logic import nil
export pipeline_healing_logic

from core/solver/z3_result_parser import parseUnsatCore
export parseUnsatCore

from core/orchestrator/cfg_builder import buildControlFlowGraph, findPrimaryLoopHeader
export buildControlFlowGraph, findPrimaryLoopHeader

{.pop.}
{.pop.}
