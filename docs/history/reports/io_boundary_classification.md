# I/O 경계 분류 리포트 (Stage 3A)

> 총 impure proc: 320개

## 카테고리별 분류

| I/O 유형 | Count |
|----------|-------|
| file_io | 23 |
| json_parse | 12 |
| process_exec | 12 |
| vault_persistence | 8 |
| semaphore | 6 |
| provenance | 4 |
| console | 2 |
| system | 1 |
| uncategorized | 252 |

## 분류별 상세

### file_io (23개)
- `src/core/encoding/vfs.nim:clearVfs`
- `src/core/encoding/vfs.nim:readVfs`
- `src/core/encoding/vfs.nim:vfsExists`
- `src/core/encoding/vfs.nim:writeVfsLean`
- `src/core/encoding/vfs.nim:writeVfsZ3`
- ... and 18 more

### json_parse (12개)
- `src/core/api/axiom_api_session_helpers.nim:parseStoredProofResponse`
- `src/core/gateway/gateway_json.nim:jsonParseSafe`
- `src/core/json/json_safe.nim:safeParseJson`
- `src/core/json/json_safe.nim:safeParseJsonFile`
- `src/core/json/json_utils.nim:parseJsonOpt`
- ... and 7 more

### process_exec (12개)
- `src/core/application/verification_orchestration.nim:runLeanProofRefinement`
- `src/core/audit/hotspot_analyzer.nim:runGitLog`
- `src/core/gate/layer_guard.nim:runAxiomEngineCli`
- `src/core/gate/layer_guard.nim:z3ExecPersistent`
- `src/core/judge/lean_replay.nim:runLeanReplay`
- ... and 7 more

### vault_persistence (8개)
- `src/core/gate/gate_memo.nim:loadGateMemo`
- `src/core/gate/gate_memo.nim:saveGateMemo`
- `src/core/vault/vault_factory.nim:getProof`
- `src/core/vault/vault_factory.nim:listSessions`
- `src/core/vault/vault_factory.nim:loadVaultStore`
- ... and 3 more

### semaphore (6개)
- `src/core/sync/sync_utils_process.nim:acquireResourceSemaphoreTimeout`
- `src/core/sync/sync_utils_process.nim:acquireTicket`
- `src/core/sync/sync_utils_resource.nim:acquireResourceSemaphore`
- `src/core/sync/sync_utils_resource.nim:acquireResourceSemaphoreTimeout`
- `src/core/sync/sync_utils_resource.nim:acquireTicket`
- ... and 1 more

### provenance (4개)
- `src/core/trusted/provenance_guard.nim:drainThreadProvenanceLog`
- `src/core/trusted/provenance_guard.nim:enforceProvenanceBeforeWrite`
- `src/core/trusted/provenance_guard.nim:recordProvenanceOverwriteAttempt`
- `src/core/trusted/reasoning_recorder.nim:drainThreadReasoningTrail`

### console (2개)
- `src/core/io/io_utils.nim:writeStderrLine`
- `src/core/proof/proof_universe_lock.nim:writeStderr`

### system (1개)
- `src/core/telemetry/trace_normalizer.nim:detectProjectRoot`

