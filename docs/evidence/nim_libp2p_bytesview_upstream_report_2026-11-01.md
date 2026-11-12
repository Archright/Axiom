# nim-libp2p bytesview upstream 보고 — 운영 수용 증거 (2026-11-01)

> **문서 성격**: 이 문서는 receipt JSON의 단독 파생 투영이 아니라 **관측 기록**이다 — prove·report 실행 관측(명령→결과), GitHub 이슈·코멘트 관측, 런 로그를 기록하며 그 상당 부분은 receipt JSON에 존재하지 않는다 (AGENTS.md §5 — docs/evidence/는 실행 증거(관측·검증 기록)의 위치다).
>
> **계약 관계·충돌(확인됨)**: 기계 소비 제출 정본은 receipt `data/upstream_reports/38647549ce6cced6c8f0ee8a0c83163e34d4cf7da006a45e4b7295af578914b4.json`다 — 제출 상태·이슈 번호·URL·지문·subject pin은 receipt가 권위다 (docs/spec/upstream_reporting_contract.md §10). 같은 §10은 docs/evidence 기록을 "receipt의 DERIVED 인간 가독 투영 — 독립적으로 편집되지 않는다"로 규정하지만, 이 문서의 실제 성격은 관측 기록이고 receipt는 DUPLICATE 재실행 갱신 때 최초 submittedAt·attempts를 덮어써 소실시켰다(§1) — 소실된 관측은 JSON 어디에도 없으므로 "JSON 단독 결정" 모델은 이 문서에 성립하지 않는다. 이 충돌의 개정은 §4의 후속 계약 개정 항목에 유보한다(이 문서에서 계약을 고치지 않는다).
>
> 계약: docs/spec/upstream_reporting_contract.md · 판정 의미: docs/spec/bug_verdict_glossary.md §2.2 (BUG_FOUND=E1 전용, 추론 근거=BUG_SUSPECTED) · grounds: data/bug_attribution/SPEC-LIBP2P-BV-SLICE.json
>
> 구현 슬라이스: PR #1152 (merge 9a7e84efd, native 2-parent, required checks 5/5 SUCCESS).

## 1. Terminal Outcome 대응 관측

| 요구 | 관측 (명령 → 결과) |
|---|---|
| 명제 반증 판정 | canonical main(9a7e84efd) `make ci-compile` exit 0 → `AXIOM_STATE_DIR=/tmp/axops1_state AXIOM_PROVE_VAULT_DIR=/tmp/axops1_vault ./bin/ax prove --project …/nim-libp2p --target "libp2p/utils/bytesview.nim::toOpenArray"` → **exit 1** + `[ce-replay] bvSliceLenActual — replay agreed; PROPOSITION_DISPROVED payload assembled (13 records)` |
| 2축 판정 투영 | state `ax_proof_state.json` `/display/units[0]` = `propositionVerdict=DISPROVED · bugAttribution=BUG_SUSPECTED · requirementSourceStatus=unrecorded · uncertaintyKinds=[upstream-spec] · adoptedSpecRef={specId: SPEC-LIBP2P-BV-SLICE, specRelPath: nim_libp2p_bytesview_slice.json} · ruleJudgment="Axiom-Defined Rule Violated"` |
| 실제 보고 | `./bin/ax report --upstream --state-file …/ax_proof_state.json` → dry-run `READY` (/tmp/upstream_dryrun.log) → **SUBMITTED https://github.com/iftech/nim-libp2p/issues/3364** (/tmp/upstream_submit.log; 제출 시각은 GitHub 이슈 createdAt 2026-10-31T16:23:47Z — 이슈 번호·URL·상태의 권위는 GitHub다, 계약 §2). 원 제출 런의 submittedAt·attempts는 receipt가 SUBMITTED→DUPLICATE로 갱신될 때 덮어써져 소실되었다(현재 submittedAt=null) — 소실된 시도 내용은 재구성하지 않는다 |
| 멱등성 | 동일 명령 재실행 → **DUPLICATE** 동일 URL #3364 (/tmp/upstream_rerun.log; receipt 잔존 attempts = 재실행 런의 `resolve-repository`·`verify-ledger-submission` 2단계, exit=0, ts 2026-10-31T16:30:15Z — ledger 경로, create 시도 없음), receipt status SUBMITTED→DUPLICATE 갱신, 보고 이슈 총 1개 |
| Zero-Footprint | 대상 사전·사후 핀 동일: HEAD `a130a7f32219909bdcda14b7f1e64d0804fc832c`, `git status --porcelain` 공백, `libp2p/utils/bytesview.nim` sha256 `b205c969ba04f4199d8fd4a121d4b6fccdc82c426e336add0e1e9fd0e961e5ee` |

이슈 생성(GitHub createdAt): 2026-10-31T16:23:47Z · 재실행 DUPLICATE(receipt attempts ts): 2026-10-31T16:30:15Z · 재현 보강 코멘트: 2026-10-31T16:32:53Z · 실행자: wintrover (gh keyring 인증, §2.4 네이티브 경로). receipt의 최초 submittedAt는 소실(null)이며 제출 시각의 잔존 증거는 GitHub createdAt뿐이다.

## 2. 이슈 #3364 (iftech/nim-libp2p)

- 제목: `toOpenArray: adopted proposition violated (external:libp2p/bytesview/slice-length-law)` · 상태 OPEN
- 본문(제출 시점, reporter 생성분): 대상 4중항(저장소·커밋·모듈+sha256·심볼), 관측 모델 `bvSliceLenActual(e) == (e - 1)` vs 채택 법칙 `bvSliceLenLaw1(e) == e`, 영향, "pinned replay" pseudo 블록, **INFERRED 면책**("The project has NOT been shown to guarantee this behavior"), uncertainty·requirementSourceStatus, `reportFingerprint` 라인, Axiom 내부 인증서 세부 배제 — docs/spec/upstream_reporting_contract.md §9. **한계: §9의 자립 최소 재현(Nim snippet + pinned commit + module sha256)은 이 본문에 없었다** — receipt의 반례 바인딩이 빈(normalized=[]) 경우 reporter는 실행 가능 snippet 대신 pseudo 블록만 생성한다(`src/cli/upstream_report_cli.nim` `deriveReproSnippet` — run 커밋 9a7e84efd와 현재 HEAD 모두에서 소스 확인).
- 구체 재현 보강 코멘트(사용자 승인 작업에서 추가): https://github.com/iftech/nim-libp2p/issues/3364#issuecomment-6546124019 (2026-10-31T16:32:53Z; e=4, b=1, rpos=0 → 관측 길이 3 vs 포함적 기대 4; `bytesview.nim:18-19`의 `v.rpos + e - b` 상한이 시작 오프셋을 두 번 빼는 산술; b=0 경로는 생산 호출 지점(noise.nim 32바이트 목적지)과 우연히 일치) — 게시 사실·내용 일치는 2026-11-01 GitHub 관측으로 확인했고 내용은 grounds의 관측 4중항·위반 진술과 일치한다(data/bug_attribution/SPEC-LIBP2P-BV-SLICE.json). 현재 이슈 본문에는 동일 내용의 "Executable reproduction (independently verified)" 섹션이 관측된다(2026-11-01 GitHub 관측; GitHub timeline에는 본문 편집 이벤트가 관측되지 않는다) — 이 섹션은 reporter 소스가 생성하는 것이 아니다.
- 저장소 해석: 요청 `status-im/nim-libp2p` → resolved canonical `iftech/nim-libp2p` (redirect 추적, receipt에 둘 다 기록).

## 3. 판정 근거 (grounds 요약)

- E1(명시적 요구사항) 부재 → requirementSourceStatus=unrecorded → **BUG_SUSPECTED** (AI 추론 명제; glossary §2.2 판정표 DISPROVED×unrecorded 행).
- grounds 참조: Nim stdlib `system.toOpenArray` 포함적 의미(길이 = last − first + 1), 공식 문서 예 `s.toOpenArray(1, 3) == [1, 2, 3]`.
- 반례: 고정 커밋에서 ce-replay가 재현 (13 records payload; 관측 3, 법칙 요구 4).

## 4. 알려진 한계 (정직 기록, 후속 계약 개정 필요)

- display 유닛이 외부 주체에 counterexample quartet 필드를 투영하지 않아 이번 지문의 `normalizedCounterexample`가 공집합이다. 지문의 결정론(동일 입력 → 동일 지문, 계약 §4)은 성립하고 멱등성(재실행 DUPLICATE)은 관측으로 성립하나, **반례가 빈 지문이 이 결함을 일반적으로 구분한다고 보장할 근거는 없다** — 계약 §4는 "동일 결함 → 동일 지문"의 정방향만 규정할 뿐 서로 다른 결함을 구분한다는 보장은 하지 않는다. 또한 **지문 입력을 사후에 채우면 지문 해시가 바뀌어 이미 제출된 결함의 정체성이 갈라져 중복 이슈을 만든다** — 따라서 이 슬라이스에서는 보존하고, 채널 완성은 명시적 계약 개정(§0.12)을 동반하는 별도 워크패키지로만 한다.
- 자동 reporter는 계약 §9의 자립 최소 재현을 여전히 충족하지 못한다 — 빈 반례에서는 pseudo 블록만 생성되고(§2), 제출된 구체 재현은 reporter 밖 보강(코멘트)으로 확립되었다; 현재 receipt도 normalized=[]이므로 재실행 결과도 동일하다. §10의 "docs/evidence = DERIVED 투영" 규정과 본 문서의 관측 기록 성격 사이의 충돌(헤더 참조)도 같은 개정 워크패키지의 대상이다.
- 메인테이너의 수용·기각·수정은 외부 소유자 권한이므로 완료 조건이 아니다 (계약 §12).

## 5. 원본 명령·산출물

- receipt(기계 소비 정본): `data/upstream_reports/38647549ce6cced6c8f0ee8a0c83163e34d4cf7da006a45e4b7295af578914b4.json`
- prove 로그: `/tmp/prove_main.log` · dry-run: `/tmp/upstream_dryrun.log` · 제출: `/tmp/upstream_submit.log` · 재실행: `/tmp/upstream_rerun.log` — 4개 모두 2026-11-01 잔존 확인.
- 상태 파일: `/tmp/axops1_state/logs/ax_proof_state.json` — §1의 2축 판정 투영을 확인한 실행 산출물이다. `/tmp`는 영구 보존 장소가 아니다.
- 관련 슬라이스: PR #1152 (판정 모델·reporter 구현), PR #1150 (판정 재사용 증거).
