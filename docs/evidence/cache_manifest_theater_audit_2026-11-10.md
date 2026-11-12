# cache_manifest.nim 극장 감사·처분 등록 — 기계 관측 증거 (2026-11-10)

> **종류**: 감사(audit)·§0.9 처분 등록 증거 기록. **판정 권위는 기계 관측이며, 이 문서는 그 기록이다. 코드 변경 0 — 등록이 처분이다.**
> **Date**: 2026-11-10 · **Branch**: `workstream/cache-manifest-audit` (base `5f3595a4067f833331aa0e6cbf73519846430652` = main @ PR #52 merge)
> **대상**: `src/core/gate/cache_manifest.nim` (81줄, "Merkle-DAG with Single-Writer Gate" 표방) + 고아 Gherkin 스펙 `tests/features/cache_manifest.feature`
> **판정**: **§0.9 극장 (Theater/Disguised Stub) + 무소비 사체 복합** — 보장하는 척하며 아무것도 보장하지 않는 계층. 등록 ID: **DEBT#525**.

---

## §1. 판정 요약

| 질문 | 관측된 답 |
|---|---|
| 이 모듈을 import하는 .nim 파일 | **0건** (전 저장소, import/from/include 전부) |
| 게이트 CAS 재사용 판정 경로가 consult하는가 | **아니오** — 소비자 0건이므로 구조적으로 불가 |
| `computeContentHash`는 해시인가 | **아니오** — payload 문자열을 그대로 반환 (:31-36) |
| `compactManifests`는 주석이 말하는 일을 하는가 | **아니오** — "Topological sort of .tx files, merge into snapshot" 주석과 달리 무조건 `ok` 반환 no-op stub (:79-81) |
| 저장 경로 `.axiom/cache/manifests` | **존재하지 않음** — 한 번도 쓰인 적 없음 |
| Gherkin 스펙의 runner | **없음** (`data/feature_manifest.json`에서 `runner: ""`) — 구현이 뒷받침하지 않는 스펙 |

## §2. 전수 소비자 조사 (2026-11-10, main `5f3595a`)

**M1 — 심볼 전수 grep (Nim 전체)**: `rg 'appendTxRecord|claimOwnership|createMergeNode|compactManifests|computeContentHash|TxRecord|TxKind|GateOwnership|OwnershipError|ManifestDir|cache/manifests' --type nim` → 이 모듈 소유 심볼의 **외부 실사용 0건**. 일치는 전부 우연 동명(typo가 아닌 별개 정의):

- `computeContentHash` — 8+개 모듈의 동명 proc/func: `src/core/crypto/hash_kernel.nim:49`(진짜 sha256), `src/gate/static_gate_scanner.nim:55`, `src/verification/batch_uap/ast_hash.nim:114`, `src/gate/runners/source_fetcher.nim:49`, `tools/product_surface_closure.nim:205`, `tools/cert_integrity_gate.nim:55`, `tools/debt_backfill.nim` 등 — 전부 각자 정의한 별개 함수.
- `claimOwnership` — **spec-overlay JSON 필드명** `"claimOwnership"`(owner/provenance 검증): `src/cli/axiom_engine.nim:1947,2818`, `src/cli/verdict_display.nim:141,354,362`, `src/cli/external_subject_registry.nim:343-348`, `src/core/trusted/bug_attribution_grounds.nim:36-37,116`(`validateClaimOwnership` — additive spec 필드 검증기). 이 4개 파일은 임무 지시의 문자열-grep 후보였으며 **전부 JSON 필드 우연 일치로 판명** — 이 모듈의 `claimOwnership(reg: var GateOwnership, ...)` proc과 무관.
- `ManifestDir` — `tools/sync_topology.nim:11`·`src/gate/runners/manifest_consistency_gate.nim:84`의 별개 상수 (`"src/gate/manifest.d"` 지향, 이 모듈과 무관).

**M2 — import 구문 전수**: `rg '(import|from|include)\s[^#\n]*cache_manifest' --type nim` → **0건**. 브래킷 import(`core/gate/[...]`)·별칭(`as`)·include 변형 전부 0건.

**M3 — 전체 문자열 grep (Nim)**: `rg 'cache_manifest' --type nim` → 2건: 모듈 자신(:3 헤더 주석) + `tools/artefact_prompt_template.nim:66`(프롬프트 템플릿 안의 예시 문장 — 비코드).

**M4 — 테스트·빌드 표면**:
- `tests/`에서 모듈 참조: `tests/features/cache_manifest.feature`(스펙, §4) 외 0건. `tests/gateway/`에 대응 feature 테스트 부재(`ls tests/gateway | grep cache` → cache_middleware·summary_cache·unsat_core_cache만).
- 빌드 타깃 부재: `config/*.nims`·`tools/build/`·`ci/checker.mk`·`Makefile`에서 `cache_manifest` 0건.
- `tests/auto_generated/batch_manifest.json`이 `gate/cache_manifest`를 tier2로 수록 → tier2 실행부(`tools/test_scale_orchestrator.nim` runTier2Test :85-118)는 `tools/capture_runner.nim --module=...`로 대상 모듈을 **컴파일+실행해 `when isMainModule` stdout만 캡처**한다. 이 모듈은 `isMainModule` 블록이 없다(`grep -c isMainModule` = 0) — 캡처 트레이스가 항상 빈 결정론적 트레이스(의미 검증 불가). 실제 녹화물: `tests/recordings/`에 `trace_normalizer.json` 1건뿐, cache_manifest 녹화 0건. 오케스트레이터는 CI에 연동되지 않음(`.github/workflows/`·`ci/`·`tools/build/` 참조 0건).
- `bin/cache_manifest` 바이너리: 현재 부재. `data/debt_registry.json` DEBT#419 historicalFiles(2026-08-17 디렉터리 감사 스냅샷)에만 등재. `git log --all -- 'bin/cache_manifest*'` → **0건** (트래킹 이력 없음).

**M5 — 정적 분석 표면 (소비 아님, 관측 기록)**: `data/nimtry_baseline.json`(purity 경고 3건: :31,:46,:79), `data/complexity_report.json`(totalComplexity 12), `data/code_health_baseline.json`(deepNesting 1), `data/verification_auditor_snapshot.json`(layer="infrastructure"), `data/architecture_debt.json`(표준 항목 1건: rawContentHash `sha256:68edad41…`), `src/generated/build_metadata.json`(파일 인벤토리 목록), `experiments/act2-r0-reanchor/execution_authority.json`(sha 인벤토리) — 전부 "분석 대상 파일" 등재이며 실행 소비가 아니다.

**M6 — 기원·불변성**: `git log --follow -- src/core/gate/cache_manifest.nim` → 단 1커밋 `6104b24`(clean-origin root). `git diff 903d1d1 HEAD -- <file>` → 빈(diff 없음, 무변경 재확인).

## §3. 극장 요소 — 모듈 본문 관측 (`src/core/gate/cache_manifest.nim`)

1. **가짜 content-addressing**: 헤더(:3)는 "Merkle-DAG with Single-Writer Gate"를 표방하나 `computeContentHash`(:31-36)는 `result = $payload` — 해시가 아니라 **연접 payload 문자열 그 자체**를 반환한다. 이름·도큐먼트는 content-addressing을 약속하나 구현에 해시 함수가 없다. `appendTxRecord`(:49-67)는 이 "contentHash"로 파일명을 만들어(dir=payload[0..1], file=payload[2..^1]+".tx") `.tx`를 기록하고 TxRecord.contentHash 필드에 payload를 저장한다 — Merkle-DAG(각 노드가 부모 해시를 해시로 결합)와 구조적으로 다르다(parentHashes 조차 해시 없이 연정).
2. **무조건 통과 stub**: `compactManifests`(:79-81) — 주석 `# Topological sort of .tx files, merge into snapshot`는 실제 작업을 서술하나 본문은 `Result[void, string](ok: true)` **무조건 ok 반환**. topological sort도 snapshot merge도 존재하지 않으며 실패가 불가능하다(§0.9 disguised-stub·always-pass 정의).
3. **환상 저장소**: `ManifestDir = ".axiom/cache/manifests"`(:28) — 메인 클론 `.axiom/cache/` 실측: `gate_closure/`, `gates/`(171항목), `nimcache_leases/`, `gate_env.lock`, `hermetic_env_hash.txt`. **`manifests/` 부재** — 이 계층이 산출물을 쓴 적이 없다는 물리 증거.

## §4. 주변 투영 관측

- **고아 Gherkin 스펙**: `tests/features/cache_manifest.feature`(16줄) — "cache manifest entry는 stale hash를 무효 판정·refresh 표시한다"는 행위를 시나리오로 주장. `data/feature_manifest.json`은 이 스펙을 `"runner": ""`(대조: cache_middleware는 runner 지정)로 수록 — **runner가 없으므로 아무 검증도 이 스펙을 시행하지 않는다**. DEBT#475(sandbox_launcher: 구현 없는 스펙 + 불가능한-실패 테스트)와 동일 구조.
- **모순된 커버리지 투영**: `data/coverage_baseline.json`은 module `cache_manifest` coverage **100.0** 기록(srcHash `b45a114c…` — 현행 파일 digest `68edad41…`와 불일치 = stale baseline)하는 동시에 `data/coverage_report_untested.json`은 `src/core/gate/cache_manifest.nim`을 untested로 수록. 실측 소비자 0건이므로 100%는 빈 분모·정적 투영의 유사 마스킹이다(§0.9a와 별개 파일이라 조용히 수정하지 않고 관측으로 기록).
- **이미 등록된 면책**: `config/decision_binding.waiver.json` grandfather 항목 — file `src/core/gate/cache_manifest.nim`, reason "Grandfathered legacy code - pending rationale extraction", expires 2026-12-31. 본 감사가 그 rationale 부채를 확정한다.

## §5. 판정 및 처분 등록

**판정**: (a) 무소비 사체 = 참(M1-M4), (c) §0.9 극장 = 참(§3의 1·2·§4의 고아 스펙). AGENTS.md §0.9 정의 — "보장하는 척/보이는 척 하면서 아무것도 보장하지 않는 것(…위장 스텁·죽은 게이트…)"에 정확히 부합. **발견된 극장은 반드시 registry에 등록한다 — 조용히 패치하지 않는다.**

**등록**: `data/debt_registry.json`에 **DEBT#525** (category `Theater/Disguised Stub`, source `theater_audit`, status `open`). contentHash = 대상 파일 전체의 sha256 `sha256:68edad41b5f74ce386c7c85c5aecd03255b17a35e1c02ad074115b6da9c9aaac`(관측: `sha256sum` — `data/architecture_debt.json` rawContentHash와 동일). 고아 스펙 digest `57b13031051bb5a00ce10168c68959ecf59248878c4b74406460ba2c33542a72`.

**미변경 (범위 규율)**: 모듈 소스·스펙·커버리 baseline·waiver·FROZEN 영역(`src/gate/**`, `.github/workflows/**`, `AGENTS.md`, import_encapsulation) 전부 미접촉. 삭제는 Owner 별도 결정 사항(§2.2 기회적 리팩터링 금지) — 등록이 본 임무의 처분이다.

## §6. 기계 검증 (등록 후, 워크트리 `workstream/cache-manifest-audit`)

```
$ bin/debt_engine --codegen    # 투영 재생성: src/generated/debt_constants.nim + docs/DEBT_REGISTRY.md
$ bin/debt_engine --sync-budget # data/debt_ledger.json BUDGET 동기화
$ bin/debt_engine --validate
→ (본 문서 커밋 시점의 기대: baseline 1604/1604 + 신규 검증 항목 전부 통과, EXIT=0 — 아래 착지 기록 참조)
```

최종 검증 결과·PR 번호·merge SHA·merge 후 main 재검증(`bin/debt_engine --validate` EXIT=0)은 본 PR 본문 및 임무 최종 보고에 기록한다.

## §7. 재현 명령

```bash
rg '(import|from|include)\s[^#\n]*cache_manifest' --type nim   # 0건
rg 'cache_manifest' --type nim                                  # 모듈 자신 + 프롬프트 템플릿 주석
rg 'appendTxRecord|claimOwnership|createMergeNode|compactManifests|GateOwnership|cache/manifests' --type nim
ls .axiom/cache/                                                 # manifests/ 부재
python3 -c "import json; [print(f['name'],repr(f['runner'])) for f in json.load(open('data/feature_manifest.json'))['features'] if f['name']=='cache_manifest']"  # runner ''
git log --follow --oneline -- src/core/gate/cache_manifest.nim   # 6104b24 (root) 단일
git diff 903d1d1 HEAD -- src/core/gate/cache_manifest.nim        # 빈
sha256sum src/core/gate/cache_manifest.nim                       # 68edad41…
```
