## 공유 타입 인터페이스 — tools/ ↔ src/ 의존성 역전 레이어
## 이 모듈만이 tools/에서 import할 수 있는 src/ 경로이다.

import core/trusted/layer_declaration
axiomLayer "infrastructure"
import core/trusted/axiom_pragmas
export axiom_pragmas

import core/audit/audit_types
export audit_types

import core/utils/repo_root
export repo_root

import core/types/results
export results

import core/trusted/env_access
export env_access
import core/utils/idempotent_write
export idempotent_write
import core/observer
export observer
