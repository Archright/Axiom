import core/trusted/layer_declaration
axiomLayer "infrastructure"
# ============================================================
# STRICT HUB POLICY
# ============================================================
# 이 파일은 Verification Layer의 유일한 Facade입니다.
# import를 추가하려면 아키텍트 승인이 필요합니다.
#
# nimtry가 이 파일의 import 변경을 자동 감지하여 차단합니다.
# 변경 시 gate_exceptions.json에 예외 등록 필요.
#
# Ratchet Effect: 이 파일에 새 import를 추가하면
# architecture_policy.lock의 [forbidden_call_patterns]이 차단합니다.
# ============================================================

import verification/batch_uap/loop_driver
import verification/state_manager
import verification/lean_lsp
import verification/certificate_manager
# axiomIoBoundary

export loop_driver, state_manager, lean_lsp, certificate_manager
