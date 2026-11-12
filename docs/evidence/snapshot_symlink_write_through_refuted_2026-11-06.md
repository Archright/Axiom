# 스냅숏 symlink 쓰기관통 가설 — 기각 판정 조사 기록 (2026-11-06)

> **종류**: 가설 판정 조사 기록 (hypothesis adjudication record). **이 문서는 관측 기록이지 결정을 대리하지 않는다.**
> 대상 가설: pre-push 스냅숏 make가 `bin/<gate>` symlink 경유로 메인 체크아웃의 게이트 바이너리를
> write-through(쓰기관통)한다.
> **Date**: 2026-11-06 · **Branch**: `workstream/symlink-hypothesis-refuted-evidence` (off `main` @ `af5905649`)
> **Scope**: 본 문서 1건 — 게이트 코드·Makefile·`.githooks/**` 수정 0건 (조사는 완료 상태 — 기록 전용).
> **데이터 원천**: 코드 정적 분석(§1 인용), `~/.cache/axiom/push-admissibility/log.jsonl` (사용자 로컬
> 텔레메트리 — 관측 기록이며 판정 권위가 아님), 잔존 스냅숏 파일시스템 관측(§4), /tmp 제어 실험 1회성
> 수행(§2 — 재생산 절차는 각주).

---

## §0. 판정

**기각(refuted)** — 스냅숏 make가 symlink를 통해 메인 `bin/<gate>`를 write-through한다는 가설은 성립하지
않는다. 재빌드 경로는 실재하나(§1) 쓰기는 구조적으로 차단된다(§2) — gcc 13.3.0/binutils ld 2.42가 출력
생성 전 출력 경로를 먼저 unlink하므로 원본 inode는 쓰기 개방된 적이 없다. 운영 텔레메트리에서
write-through의 필수 서명(재빌드 사유 없는 sha 변동)이 0건이고(§3) 잔존 스냅숏에서 변조 흔적이
없다(§4). 잔여 조건부 위험(미pin 링커)과 실질 방어선(VS-1 스탬프)은 §5, 후속 등록은 §6.

## §1. 증거 1 — 정적 분석: 재빌드 경로의 실재

1. **훅의 스냅숏 부트**: `.githooks/pre-push:703` (`git worktree add --detach`), `:711-717` — 7게이트를
   `ln -sf "$(pwd)/bin/<gate>"`로 **절대 symlink** 연결, `:724-726` (`env -u GIT_DIR … make -C <snapshot>
   push-admissibility`).
2. **훅 순서**: Part 4a(스탬프 판정·필요시 `make -B bin/<gate>` 재빌드, `.githooks/pre-push:646-692`)가
   스냅숏 체크아웃(`:703`)보다 먼저 실행된다 → **메인 바이너리 mtime < 체크아웃 파일 mtime이 구조적**.
3. **symlink가 make prerequisite으로 등재되는 타깃은 2개뿐**: `check-layer-enforcement` (`Makefile:176` →
   prereq `bin/layer_enforcement_gate`, 빌드 규칙 `Makefile:170-174`)와 `check-layer-negative`
   (`Makefile:182`). 나머지 6게이트는 `push-admissibility` 레시피에서 **명령으로 직접 실행**된다
   (`Makefile:519-526`) — make의 신선도 평가 대상이 아니다. 두 check-layer 타깃은 재귀 `$(MAKE)` 호출로
   진입(`Makefile:535-536`)하므로 prerequisite 신선도 판정이 발생한다.
4. **판정 방식**: GNU make 4.3은 symlink를 stat-follow로 판정한다 — 체크아웃 prerequisite이 구조적으로
   신선하므로(2항) 스냅숏의 `bin/layer_enforcement_gate`은 **항상 out-of-date로 재빌드를 시도**한다.
   (이 재빌드의 실재는 §6 Follow-up 1의 근거이기도 하다.)

## §2. 증거 2 — 제어 실험 (/tmp, 1회성): 쓰기관통 부재

- **재현 충실도**: 실제 저장소 worktree · 실제 Makefile · 실제 도구체인(Nim 2.2.10, gcc 13.3.0,
  binutils ld 2.42)으로 /tmp에 스냅숏 구성을 재현하고 `make -C <snapshot> check-layer-enforcement`를
  실행했다.
- **결과**: 원본(메인) 바이너리의 **sha256·mtime·inode 전부 무변**. 스냅숏의 symlink는 **일반 파일로
  치환**됐다 — 재빌드 산출물이 스냅숏 로컬에 착지했다.
- **strace 관측**: `unlink(<출력 경로>)` → `openat(..., O_CREAT|O_TRUNC)` 순서 — gcc 13.3.0/binutils
  ld 2.42가 출력 생성 전 출력 경로를 먼저 unlink한다. **원본 inode는 쓰기 개방된 적이 없다** —
  write-through 부재의 기계적 근거.

## §3. 증거 3 — 텔레메트리 법정학 (VS-1 시대 12 엔트리)

- **대상**: log.jsonl에서 7게이트 전체 sha256 스키마를 가진 엔트리 12건 (2026-11-05T15:19:00Z–
  16:39:23Z — VS-1 착지 직후의 검증 실험·운영 push).
- **게이트당 distinct sha256 정확히 1개**: debt_engine `586aa5d9…` · check_nim_theater `d46a418e…` ·
  doc_path_validator `20c9c315…` · proof_unit_consistency `476b83d7…` · proof_reconcile `aabd3eb5…` ·
  epoch_transaction `b5490faa…` · layer_enforcement `ddfd99b7…`.
- **"재빌드 사유 없는 sha 변동" 0건** — write-through의 필수 서명(훅 판정·재빌드와 무관한 바이너리 신원
  변동)이 부재한다.
- **reuse 판정 지속** = 스탬프 BINARY_SHA256과 실 바이너리 sha가 매 push 일치 — 훅은 push마다 기록된
  입력과 바이너리를 재해시·대조한다 (`.githooks/pre-push:648-654`).
- **layer_enforcement_gate**: 첫 push(15:19:00Z)의 Part 4a 재빌드 1회(바이너리 mtime 15:17:30Z) 이후
  모든 후속 push에서 mtime·sha 불변 (조사 종료 시점 9회 후속 push 관측; 본 문서화 시점 로그 종착 기준
  후속 11 push — 빌드 실패 주입 FAIL 1건은 layer 판정 도달 전 중단이나 sha 기록은 동일). 메인
  `bin/layer_enforcement_gate`의 mtime은 문서화 시점에도 15:17:30Z(Part 4a 빌드 시각) 그대로다.
- **귀속 주석(중요 — 정확한 기록)**: 이 12 엔트리의 doc_path_validator rebuilt 반복은 "클로저/probe
  특성" 같은 자발적 현상이 **아니다** — `docs/evidence/prepush_content_identity_acceptance_2026-11-06.md`
  §2의 **VS-1 착지 검증 실험 시리즈(변조·스탬프 삭제·실변경·자가치유)에 의한 의도적 변**이며, OID가
  1:1로 대응한다. 무변경 push(A·E·main-A: `fe85b8a11`·`7427bc22f`·`2384570100`)에서는 전원 reuse로
  신원 안정성이 입증됐다.

## §4. 증거 4 — 잔존 스냅숏 검사

- **잔존 스냅숏 5개**(SNAP_ROOT `~/.cache/axiom/push-admissibility`) 전부 layer symlink 잔존 — 일반
  파일 치환 부재, symlink lstat 시각 = 스냅숏 생성 시각(생성 후 미치환). 5개 모두 텔레메트리상
  **FAIL push**(`probe/spoof-a`·`probe/p3-bounded-retry-injection`·`feat/v5-evidence-identity`·
  `work/byoa-phase5-incapable` ref)로, 레시피 순서상 layer 평가(`Makefile:535-536`) 도달 전 실패와
  정합한다. VS-1 시대 12 push의 스냅숏 디렉터리는 SNAP_ROOT에 잔존하지 않는다(제거 원인은 기록
  부재로 미확정).
- **타깃 mtime 비교**(비교 가능 4개): 3개(p3-download-recovery 방향 2, byoa 방향 1)는 타깃 바이너리
  mtime이 스냅숏 생성보다 **이전** — 직접 부합. 1개(Axiom3 방향, 스냅숏 2026-10-12)는 타깃 mtime이
  이후(2026-11-05 19:01)이나 symlink lstat이 불변(2026-10-12) — 스냅숏 경유 쓰기였다면 §2 관측대로
  symlink가 일반 파일로 치환됐어야 하므로, 해당 mtime은 타깃 체크아웃(Axiom3) 자체의 후일 재빌드
  (정상 Part 4a/make 경로)로 귀속한다. phase2-v5-evidence 방향 1개는 대상 worktree 제거로 dangling
  (타깃 부재 — 비교 불가).
- **결론**: 잔존 스냅숏에서 스냅숏 경유 변조 흔적 없음 — 변조 없음.

## §5. 잔여 조건부 위험과 실질 방어선

- **unlink-선행 동작은 환경 속성**: `check-determinism`(`Makefile:257-262`)이 pin하는 것은 nim/z3/lean/git
  4종뿐이다 — gcc/binutils는 pin되지 않는다. 링커의 unlink-선행 동작은 pin되지 않은 시스템 링커의
  **환경 속성**이지 저장소가 보장하는 불변식이 아니다.
- **조건부 시나리오**: 구형 ld가 O_TRUNC-in-place로 출력을 열었다면 이론적 write-through가 가능했을
  시나리오가 존재한다(현행 gcc 13.3.0/ld 2.42 환경에서는 §2대로 차단).
- **실질 안전망 — VS-1 BINARY_SHA256**: 그 경우에도 다음 push에서 스탬프 BINARY_SHA256 mismatch →
  자동 재빌드가 작동한다 — 이미 착지·운영 검증됨(변조 실험 C에서 감지·복원 관측,
  `docs/evidence/prepush_content_identity_acceptance_2026-11-06.md` §2). push마다 바이너리 sha를
  재해시·대조하므로(§3) write-through로 인한 신원 변동은 다음 push에서 즉시 탐지·정정된다.
- **F5 오염검사의 맹점**: F5 "메인 트리 무오염" 검증 패턴(`~/.cache/axiom/push-admissibility/
  PHASE0_FINDINGS.md:74`)은 git 상태 기반이므로 `.gitignore:29`(`bin/*`)로 gitignore된 bin/ 내 변조를
  관측하지 못한다 — **bin/의 실질 방어선은 F5가 아니라 VS-1 스탬프의 재해시·대조다.**

## §6. 신규 Follow-up 등록 (범위 밖 — 본 문서는 등록만 하며 구현·확장을 정당화하지 않는다)

1. **`Makefile:462-463` 주석 부정확**: "Uses prebuilt symlinks directly — no per-gate recompilation"이
   layer 게이트에 대해 **부정확**하다 — 매 push 재컴파일이 발생한다(§1·§2 근거; 무결성에는 무해 —
   원본 불변·스냅숏 로컬 산출 — 이나 주석·성능 전제와 불일치). 후보 수정(별도 슬라이스 — Makefile
   수정은 아키텍트 승인 경로): (a) check-layer-* 2 타깃을 나머지 6게이트처럼 `$(MAKE)` 재귀 호출이
   아닌 직접 실행으로 전환, (b) prerequisite order-only(`|`)화, (c) symlink 대신 cp.
2. **gcc/binutils 미pin**: 링커 unlink-선행 동작이 환경 속성이다(§5). `check-determinism` pin 확장
   여부는 별도 판단 사항이다(툴체인 고정 정책 표면).

---

*본 문서는 "스냅숏 symlink 쓰기관통 가설" 조사의 기각 판정 기록이다 — 관측 기록이지 결정을 대리하지
않는다. 제어 실험은 1회성으로 수행됐다(메인 체크아웃에서의 실험 재실행 금지 — 조사 완료 후 기록 전용).
재생산: §1 — 본문 인용 위치 정적 열독. §3 — `python3` + `~/.cache/axiom/push-admissibility/log.jsonl`
(7게이트 sha256 스키마 레코드 필터링). §4 — `stat`/`readlink`/`ls -l`로 SNAP_ROOT 잔존 스냅숏 검사.
§2 재현 절차 요약: /tmp에 `git worktree add`로 스냅숏 재현 → `ln -sf`로 메인
`bin/layer_enforcement_gate` 절대 symlink 연결 → 원본 sha·mtime·inode 사전 기록 →
`strace make -C <snapshot> check-layer-enforcement` 실행 → 원본 무변·symlink의 일반 파일 치환·
unlink-선행 순서 관측.*
