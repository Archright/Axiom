# Terminal Outcome Acceptance — DEBT#417 hermetic cache content identity

> Vertical Slice V1 실행 증거. 관측 대상: `config.nims` hermetic pre-build cache
> identity에서 VCS staging state를 제거하고 재컴파일 권한을 Nim 컴파일러에 반환한 변경.
> 정본 문서: `docs/spec/config_nims_hermetic_cache_quirk.md`
> Registry: `data/debt_registry.json` id `DEBT#417` (`closed` / `FIXED`)

## 1. Terminal Outcome (판정 기준)

> main에서, build 대상과 무관한 Git index/HEAD 변경은 Nim compilation cache를
> 무효화하지 않고, 실제 compilation input 변경은 재컴파일을 유발하며,
> 두 경우 모두 최종 artifact digest와 Axiom verification 결과가 결정론적으로 일치한다.
> **false reuse = 0.**

## 2. Landing 관측 (merge-admission L1 / L2 / L3)

| 층 | 관측 | 결과 |
|---|---|---|
| L1 | `admission-check` run `37255896013` conclusion | `SUCCESS` (필수 체크, ruleset 20303214 단일 필수 항목) |
| L1 | `attest / admission-check` conclusion | `SUCCESS` |
| L1 | 독립 재유도 tree digest — PR head `8bd743ac…` | `6f1e921171a140719b90f71059db00062bf6e9ce` |
| L1 | main HEAD `58a7a79d…` tree | `6f1e921171a140719b90f71059db00062bf6e9ce` — **일치** |
| L2 | merge queue entry | `AWAITING_CHECKS` position 1 → 큐 이탈 → `MERGED` |
| L3 | merge commit shape | `58a7a79d72b427f7b17f1275721da74b3295f5b0`, parents `[2530e1b9f…, 8bd743ace…]` = 네이티브 MERGE (2 parents) |
| L3 | mergedAt | `2026-10-05T02:56:39Z` |

랜딩된 `main` 콘텐츠 대조:

| 항목 | 관측값 |
|---|---|
| `sha256sum config.nims` | `addb17f36e6d8090caab03bca35c3317f1d70a2ae63d7a61b078604c9ee7d078` — 레지스트리 `contentHash`와 일치 |
| `grep -c 'rmDir("build/nimcache")' config.nims` | `0` (purge 제거 확인) |
| `grep -c 'computeSourceTreeHash("src")' config.nims` | `3` |
| DEBT#417 | `status=closed`, `resolution=FIXED` |
| `git status --porcelain` (main) | clean |

## 3. 관측 프로토콜

- 빌드: `nim c --hints:on -o:<out> src/cli/main.nim` (`build/v1probe/*` — prod `bin/ax` 비변경)
- CC 라인 계수: `grep -c "CC:"` (Nim `compiler/lineinfos.nim:216` `hintCC`)
- purge 계수: `grep -c "Clearing build/nimcache"`
- hermetic 판정: `nim c` 출력의 `[hermetic] Environment (unchanged|changed)`
- digest: `sha256sum <out> | cut -c1-16`
- 환경: Nim 2.2.10 `[Linux: amd64]`, **`AXIOM_CI_PRESERVE_CACHE` 미설정**(§5.5 — 플래그가 no-op임을 확인)

## 4. 관측 결과 — 변경 전 (baseline, `8bd743ac` 부모 `2530e1b9f`의 config.nims)

| ID | 시나리오 | 결과 |
|---|---|---|
| A1 | 콜드 (`rm -rf build/nimcache/debug`) | 45.1s · CC 629 · digest `90c4b344e67050d8` |
| A2 | **무변경 재실행** | 38.9s · **CC 629** · **MISS + `Clearing build/nimcache`** |
| A3 | `git add` (무변경 파일 — no-op) | 45.3s · CC 629 · MISS + purge |
| A4 | unstage | 45.5s · CC 629 · MISS + purge |

무변경 재실행이 CC 629 + purge였다. §2의 자가무효화 루프의 직접 증거.

### 4.1 근본의 직접 측정

`.git/index` 해시를 빌드 전후로 계측:

| 시점 | `.git/index` sha256 (앞 16) |
|---|---|
| 빌드 없이 2분간 6회 계측 | `ea2ae49e4ef5ba13` **불변** |
| `nim c` 1회 후 | `ea2ae49e4ef5ba13` → `3d44661d9092fe37` → (다음 빌드 후) `ea2ae49e…` |

빌드 전 envHash 폴드 대상 파일 9종 + `src/gate/manifest.d/*.json` 전체 해시를 빌드 전후로
비교한 결과 **변경된 파일 0건**. 그런데도 판정은 MISS. 남은 유일한 후보는 envHash에
들어 있지만 위 대조 대상이 아니었던 `.git/index` 해시였다. 원인 경로:
`tools/hermetic_build.nim:1248`(`git status --porcelain`), `:1256`(`git diff --name-only HEAD`),
`:1726`(`git diff --cached`) — MISS 분기에서 실행되므로 **MISS가 자기 자신의 트리거를 만든다.**

## 5. 관측 결과 — 변경 후 (브랜치 실험, `8bd743ace`)

| ID | 시나리오 | CC | purge | hermetic | digest |
|---|---|---|---|---|---|
| A | 콜드 | 629 | 0 | MISS | `b80d952e38d15470` |
| B | 무변경 재실행 | 43 | 0 | HIT | `b80d952e…` (동일) |
| **B2** | **비의미 편집 + `git add`** | **0** | 0 | HIT | `b80d952e…` (**동일**) |
| B3 | HEAD만 이동 (빈 커밋) | 4 | 0 | HIT | `685366a0…` (변화, §6.1) |
| B4 | 복원 | 47 | 0 | HIT | `b80d952e…` (복귀) |
| C | 의미적 `.nim` 편집 (`src/cli/version.nim:28`) | 45 | 0 | MISS | `14b84acf…` (변화) |
| **C2** | **소비되는 비-`.nim` 입력** (`data/i18n/ko.json`의 `gates.sieve.name`) | **1** | 0 | HIT | `4534e090…` (변화) |
| C2′ | C2 원복 → 2회 빌드 | 1 → **0** | 0 | HIT | `b80d952e…` (복귀) |
| D | C 원복 | 45 | 0 | MISS | `b80d952e…` (복귀) |

## 6. Terminal Outcome 판정 (canonical main `58a7a79d`, clean tree)

| ID | 시나리오 | CC | purge | hermetic | digest | 판정 |
|---|---|---|---|---|---|---|
| M1 | 콜드 | 629 | 0 | HIT | `554f121102ccfe01` | 기준선 |
| M2 | 무변경 재실행 | 43 | 0 | HIT | `554f1211…` (동일) | PASS |
| **M3** | **비의미 편집 + `git add`** | **0** | **0** | HIT | `554f1211…` (**동일**) | **PASS — 핵심 조건** |
| M4 | 복원 | 0 | 0 | HIT | `554f1211…` (동일) | PASS |
| M5 | 안정화(no-op) | 0 | 0 | HIT | `554f1211…` (동일) | PASS |
| — | 의미적 입력 변경 | (브랜치 §5의 C·C2) | 0 | MISS/HIT | **변화 후 복귀** | PASS |
| — | **false reuse** | — | — | — | — | **0** |

main 작업 트리는 실험 종료 시 clean이었다.

### 6.1 B3/M-계열 digest 변화는 결함이 아니다

`bin/ax`는 커밋 해시를 임베딩한다(`BuildEnvGitHash*`).
`src/infrastructure/gate_signing/proof_verifier.nim:41`이 이 값을 증명 서명 identity에
사용하므로, HEAD 이동 시 바이너리가 불변이면 증명 identity가 stale해진다. 관측된 CC 4는
`build_env.nim` → `constants.nim` import 체인만 재컴파일한 것이며 purge 0건이다.
**캐시는 무효화되지 않았고(CC 4 ≪ 629), digest 변화는 설계된 상수 갱신**이다.

### 6.2 실패로 기록한 관측 — C2 설계 결함

첫 C2 시도는 `data/i18n/ko.json` 최상위에 **소비되지 않는** 키(`_v1_probe`)를 추가했다.
소비처(`src/ui/notion_semantic_mapper.nim:29`)가 읽는 키는 `gates.sieve.name`,
`gates.diagnosis.name`, `gates.guidance.name` 뿐이라 codegen이 안 바뀌는 것이 정상이며,
CC 0은 false reuse가 아니라 **실험 설계 결함**이었다. 소비 키를 바꾸자 정확히 1개 모듈이
재컴파일되었다. 이 기록은 "캐시가 아무것도 하지 않는다"는 잘못된 결론을 막기 위한 것이다.

### 6.3 정상 상태 도달 불가에서 정상 상태로

변경 전 보고서에 있던 "warm 51 CC"는 이 트리에서 재현되지 않았다(무변경 재실행이 629였다).
변경 후 **정상 상태의 무변경 재실행은 CC 0**이며, CC 43이 관측되는 경우는 직전 MISS 실행이
`src/generated/*.nim`을 써서 그 import자들이 한 번 정리된 직후뿐이다(그 다음 빌드에서 0).

## 7. 게이트 관측

| 게이트 | 결과 |
|---|---|
| `bin/debt_engine --validate` | `Checks: 1387 total, 1387 passed, 0 failed` / exit 0 |
| `bin/debt_engine --sync-budget` | BUDGET#005 open 51→50, BUDGET#006 closed 168→169 |
| `make check-determinism` | PASS (Nim 2.2.10 / Z3 4.13.3 / Lean 4.33.0 / git 2.43.0 핀 일치) |
| `make verify-contract` | `g1` `g2` `g6g4` `g7` **4/4 PASS**, exit 0 |
| pre-commit 게이트 | `gate-self-check` PASS · `trust-commit-scope` PASS |
| CI `admission-gate` | `admission-check` SUCCESS |
| CI `landing-integrity` | success |

게이트 실행 중 관측한 부수 사실(본 변경과 무관한 선행 결함):

- 첫 커밋 시도가 `trust-commit-scope` FAIL로 차단됐으나, 게이트 출력 로그가
  `CAS compile failed for trust-commit-scope`였다 — 게이트가 실행되지 못한 것이지
  판정이 실패한 것이 아니었다. `bin/precompile_gates`(54 compiled, 0 failed)로 해소.
- `trust-commit-scope` 게이트는 `.nim`만 스캔하므로 `.nims`인 `config.nims`·
  `config/vendors.nims`는 대상이 아니다. 게이트 자체는 변경에 PASS한다.

## 8. 잔여 위험 및 후속 작업

| # | 항목 | 상태 |
|---|---|---|
| R1 | 손상된 `.o` + mtime 유지 시 재사용 (`compiler/cgen.nim:2230`) | purge를 거친 거친 방어를 **의도적으로 포기**. 정상 경로에서는 `.nim.c` 변경 시 함께 재컴파일. 상세는 quirk 문서 §10-R1 |
| R2 | `AXIOM_CI_PRESERVE_CACHE`가 `config.nims`에서 no-op | §9가 플래그 미설정으로 수행되어 관측 확인. 플래그·lease guard 은퇴는 후속 슬라이스 |
| R3 | 정리 안 된 서술 (`docs/agents/constitution_details.md:62`, `docs/spec/canonical_execution_semantics.md:113,121,134`, `Makefile:794`) | 후속 슬라이스 (quirk 문서 §10-R5에 목록화) |
| R4 | `repository_surface.json`에 architect 승인 미기록 | `repository-surface` 워크플로는 계속 `SURFACE_FORBIDDEN`로 실패한다(§10). 머지를 막지는 않았으나(ruleset 필수 체크는 `admission-check` 단일), **정책 진화 PR이 별도로 필요** — 해당 파일은 CODEOWNERS 소유이며 계약상 body PR은 `--no-verify`를 쓰면 안 된다 |
| R5 | DEBT#481 `Makefile` 잔여(공유 `-o:bin/ax` writer) | 본 변경 범위 밖. 등록 근본원인(purge)은 삭제됨 |
| R6 | CI B-cache HIT | 별 작업. DEBT#417과 인과 무관 — CI는 이미 관련 코드를 실행하지 않음(`ci/checker.mk:473-482`가 `AXIOM_HERMETIC_BUILDING=1`로 블록 자체를 건너뜀). 근인은 `.github/**` 캐시 전송층 |

## 9. `repository-surface` 실패에 대한 사실 기록

`git push --no-verify`와 CI `repository-surface` 실패는 **같은 판정의 두 지점**이다:
`config/repository_surface.json` policy v55가 `config.nims`와
`src/gate/orchestrator/hook/memo.nim`을 `FROZEN`으로 분류하고 `MODIFY: FAIL`을 집행한다.

| 지점 | 명령 | 판정 |
|---|---|---|
| 로컬 pre-push | `make check-repository-surface` (구성상) / 직접 실행 | `FAIL / SURFACE_FORBIDDEN`, `policyVersion 55`, 2 violations |
| CI | `.github/workflows/repository-surface.yml` (run `37255895773`) | `FAIL / SURFACE_FORBIDDEN`, `policyVersion 55` |

인간 오너의 명시적 승인은 `git push --no-verify` 경로를 허용했지만, **정책 파일에는 그 승인이
기록되지 않았다.** 게이트는 사람이 승인했는지가 아니라 파일에 기록됐는지만 본다.
따라서 이 변경은 main에 랜딩되었으나 surface 정책과의 정합성은 아직 닫히지 않았다.
