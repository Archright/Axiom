# PR Admission v1.1.0 — Terminal Operational Evidence (2026-11-14)

- **Workstream**: `evidence/pr-admission-v1-1-0-terminal`
- **Subject**: `Archright/nim-libp2p` @ `master`
- **Trusted workflow**: `Archright/.github` @ `27c2f3468658e127f94b87391c74fa5ebee6b143`
- **Contract**: `Archright/.github:.github/axiom-admission/PR_ADMISSION_CONTRACT.md` v1.1.0
- **Engine**: `axiom-cli v0.6.4`, bundle `adc0d531961d98aba8f66d6a717e4f93d597f1768c354ee9c7add76fd17e200f`, source `fd62db26bf1b895085d7b7ed28224f317f29d0a9`

---

## §1. 증명된 Terminal Outcome

PR 작성자가 검증 절차를 소유하지 않는 상태에서, 고정된 채택 명제에 대한 결정론적 증거만 병합 근거로 인정되고, 그 집행이 GitHub Ruleset에 위임된다.

| 관측 항목 | 실측값 |
|---|---|
| 신뢰 워크플로 권위 | org ruleset `27208234` (master), `27205573` (probe) — 둘 다 `enforcement=active`, workflow path `.github/workflows/nim-libp2p-pr-admission.yml`, SHA `27c2f346` |
| 대상 저장소 병합 권한 | GitHub (PR API `merge`); Axiom은 병합을 실행하지 않음 |
| 검증 입력 권위 | `state.declaredRequired` = `libp2p/utils/bytesview.nim::toOpenArray` (인간 채택 명제) |
| 대상 커밋 결속 | `github.sha` = PR merge commit. 양성 `67ed96d6…`, 음성 `3cfdcedc…` |
| 소스 트리 무변경 | `pre_tree_hash == post_tree_hash == 2855d3b922e8a8e663fb532b3624e126103beb99` (양측 leg) |

---

## §2. 양성 통제 — PR #11

| 항목 | 값 |
|---|---|
| Run | `43552724692` |
| PR | #11 `fix/bytesview-toopenarray-slice-bounds` (head `d9e8769c`, base `f4e304cc`) |
| subject commit | `67ed96d607592b5939697d5434488a398e2e140d` |
| `propositions_sha256` | `949adaa54b9b25f402df1d4040ba89521b0b118a4cb7207985dd918c658c2152` |
| `prove_exit` | A=0, B=0 |
| canonical digest | A = B = `f7209f17f78e8e034e2736eab8bc7d9b74b028839efbd9bedcc83cc8fc6d2bd2` |
| integrity | PASS (7/7 guards) |
| classification | `LAW_CONFORMANCE_ACCEPTED_REPRODUCIBLE` |
| acceptance class / tier | `law-conformance` / `candidate` |
| subject verdict | **PASS** — “NOT a formal PROVED verdict” |
| 병합 | MERGED → merge commit `dcb207299b46bcdfda5743902a9d7de6cae280e7` |

vault 실측 (leg A, leg B 동일):

```
libp2p/utils/bytesview.nim::toOpenArray        certZ3Candidate  smCLI  irHash 66d1e276…
libp2p/utils/bytesview.nim::bvSliceLenControl  certZ3Candidate  smCLI  irHash 9ce83016…
```

`EVIDENCE_COHERENCE`가 `declaredRequired`의 vault 커버리지를 검사했으므로 이 green은 공허하지 않다. 엔진 자체의 `verdict_summary`는 `INCONCLUSIVE/FAIL/n/a`로 기록되어 있으며, 계약 §2.7이 이 shape을 law-conformance로 수용한다.

---

## §3. 음성 통제 — PR #13

| 항목 | 값 |
|---|---|
| Run | `43553077178` |
| PR | #13 `revert/bytesview-slice-bounds` — `v.rpos + e` → `v.rpos + e - b` (head `f89afe2b`, base `dcb20729`) |
| subject commit | `3cfdcedc5182fbe2d8d459cce18a2eb1f2079277` |
| subject blob sha256 | `b205c969…` (overlay pin `e5c73a4f…`) |
| `prove_exit` | A=2, B=2 |
| guards | SUBJECT_IDENTITY PASS, INPUT_EQUALITY PASS, ZERO_FOOTPRINT PASS, ENVIRONMENT_EQUALITY PASS, DETERMINISM FAIL, EVIDENCE_NON_VACUITY FAIL, EVIDENCE_COHERENCE FAIL |
| classification | `UNCLASSIFIED` |
| subject verdict | **FAIL** |
| GitHub 병합 | `gh pr merge 13` → exit 1: `not mergeable: the base branch policy prohibits the merge`; `mergedAt=null` |
| master SHA | `dcb20729…` — 병합 시도 전후 불변 |

엔진 원문 (leg A `prove.log`):

```
[ERROR] nim-libp2p bytesview slice subject pin rejected (fail-closed):
nim_libp2p_bytesview_slice.json subject pin: the overlay does not bind this subject tree
(blob mismatch): …/subject/libp2p/utils/bytesview.nim hashes to
b205c969ba04f4199d8fd4a121d4b6fccdc82c426e336add0e1e9fd0e961e5ee,
the overlay pins e5c73a4fc4b4f390a74a95078809639f4773510e029673c3fb7884d53f584c85
— the claim was not adopted for these bytes
```

권한 대조: 동일 계정·동일 저장소에서 PR #11은 병합에 성공했고(#2), PR #13은 정책으로 거부됐다(#3). 따라서 #3의 거부는 권한 부족이 아니라 규칙 집행이다.

---

## §4. 제3자 재현

공개 검증기: `Archright/.github:.github/axiom-admission/verify_pr_admission_replay.py` @ `e677cd2348ca41e64427b4adb7646763b7cd20a7` (PR #274), 절차: 같은 디렉터리 `REPLAY.md`.

```
$ python3 verify_pr_admission_replay.py ./run-43552724692 ./run-43553077178
EXIT=0
run 43552724692 → RESULT: PASS — replay reproduced the recorded verdict (PASS)
run 43553077178 → RESULT: PASS — replay reproduced the recorded verdict (FAIL)
```

검증기는 워크플로를 신뢰하지 않고 다음을 독립 재계산한다:

1. `proposals.json` SHA-256
2. `canonicalProjectionHash(ax_proof_state.json)` — A/B 각각 (`canonical_projection.nim` 규칙)
3. 7개 가드 전부, 필드 단위로 워크플로 보고값과 대조 (양성·음성 모두 `agree`)
4. exit 0 수용 여부 — 엔진 증명 또는 계약 §2.7 law-conformance 접속사
5. 채택 의무의 vault 커버리지 (modulePath + functionName, wave-facing 개명 해석 포함)
6. A/B 대칭성
7. `admission-verdict.json`과 독립 재계산의 일치

증거 결손은 예외가 아니라 FAIL이다 — 증거를 검사할 수 없는 재현은 성공처럼 보일 수 없다.

---

## §5. 한계 (주장하지 않는 것)

- **property-preservation gate가 아니다.** 채택된 blob pin을 유지하는 PR만 승인된다. `libp2p/utils/bytesview.nim`을 바꾸는 모든 PR(정당한 리팩터 포함)은 pin 거절로 차단된다. 원본 template body를 추출해 law를 재검증하는 능력은 계약 §2.7 Invariant W2가 명시적으로 부인한다.
- 따라서 “반증된 변경 차단”은 이 게이트에서 **pin 거절**로 관측된다. 반증(`certRed`) 경로는 대상 blob이 pin과 일치하면서 law를 위반할 때만 도달하며, 현재 번들에서는 구성 불가다.
- `PROVED_REPRODUCIBLE`은 예약 상태다 — `NOT_DISPROVED`가 직렬화되지 않아 제품 전역에서 도달 불가(DEBT#531).
- 외부 fork PR은 실증하지 않았다. 워크플로는 `pull_request` + 시크릿 0 + 읽기 전용 토큰으로 설계됐으나, 실제 fork PR 관측은 범위 밖이다.
- Merge Queue(`merge_group`)는 미사용이며 검증되지 않았다.

---

## §6. 운영 상태와 롤백

| 자산 | 상태 | 롤백 |
|---|---|---|
| ruleset `27208234` (master) | active, pin `27c2f346` | `~/ax-slice-work/ops-2026-11-14/ruleset-master-org-before-v2.json` |
| ruleset `27205573` (probe) | active, pin `27c2f346` | `~/ax-slice-work/ops-2026-11-14/ruleset-probe-org-before-v2.json` |
| `.github` main | `e677cd23` | `~/ax-slice-work/ops-2026-11-14/dotgithub-main-before.txt` (`20f6e4a9`) |
| nim-libp2p master | `dcb20729` | `~/ax-slice-work/ops-2026-11-14/master-sha-before.txt` (`f4e304cc`) |

부작용(의도된 속성): workflow ruleset은 대상 브랜치에 대한 **직접 push도 차단**한다. master 변경은 PR 경유가 강제된다.

---

## §7. 계획이 필요한 잔여 항목

| # | 항목 | 왜 계획이 필요한가 |
|---|---|---|
| P1 | property-preservation gate | 엔진이 PR 바이트에서 template body를 추출해 law를 재검증해야 한다. spec의 blob pin 일반화 + 새 릴리스 + ruleset 재핀 + 계약 개정이 한 세대 전환으로 착지해야 한다(AGENTS §2.5). |
| P2 | pin 거절의 exit 의미 정정 | `exit 2`(INTERNAL_ERROR)로 기록되어 원인이 “엔진 내부 오류”로 오독된다. `INPUT_REJECTED`/`SUBJECT_PIN_MISMATCH`의 5-state 매핑은 엔진 계약 변경 + 릴리스 + 재핀을 수반한다. |
| P3 | Ruleset 운영 승격 | 현재 master/probe 모두 active다. 먼저 관측 기간을 두고 Evaluate 상당의 운영 검증을 하려면 별도 probe 브랜치·복구 권한·감사 기록이 필요하다. |

---

## §8. 관련 DEBT

| DEBT | 상태 | 근거 |
|---|---|---|
| #528 (vacuous green) | **closed 2026-11-14** | §2·§3 실측 + 공개 검증기 재현 |
| #529 (vault가 carrier identity 미기록) | open | 여전히 wave-facing 이름만 기록된다 — `EVIDENCE_COHERENCE`가 module-qualified 매칭으로 우회 |
| #530 (빈 런 exit 0) | open | 이번 슬라이스에서 변경하지 않았다 |
| #531 (`NOT_DISPROVED` 도달 불가) | open | §5의 한계와 동일 원인 |