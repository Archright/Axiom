# merge wall 예산 모델 — wall은 DAG 임계경로이며 검사 개수의 합이 아니다 (2026-11-27)

> **종류**: 측정 보고 (Reporter). 본 문서는 **판정을 만들지 않는다** — merge-admission 판정·정책·불변식의 권위는 기존 정본(`docs/spec/`, `config/policy/`)과 GitHub ruleset/App에 그대로 있다.
> **측정 원문**: merge_group `admission-gate` 런 **12건**(2026-11-26T03:27:30Z – 23:48:05Z, 전건 success)의 runs/jobs/steps API, 그리고 런 `45911585676` 의 잡 로그 원문(잡 `140220991383` = `attest / build-base-artifacts`, 잡 `140221285921` = `attest / go-critical-lane (1)`).
> **범위**: docs 전용. 워크플로·코드·정책 변경 **0**. `required_status_checks` 7개, App trust surface 17경로, `FROZEN` 3-class, `frozenExceptions` 모두 **불변**이다.

---

## 1. 판정 요약

1. **merge wall = DAG 임계경로다.** 검사(=required context, 잡, 스텝) 개수의 합이 아니다. 따라서 검증을 늘려도 **임계경로 밖 레인에 배치하면 wall은 늘지 않는다.**
2. **10분 상한은 이미 성립해 있다.** n=12 창에서 p50 **381초(6.35분)**, 평균 405초(6.75분), 최대 713초. 12건 중 11건이 **8분 미만**이다.
3. **10분을 넘긴 유일한 1건(713초)은 검증 누적이 아니라 플랫폼 checkout 정체**다 — `[build] Checkout B only` 가 정상 3–6초 대신 **307초**를 썼다. 같은 배치에서 toolchain 스텝은 44초로 정상이었다.
4. **임계경로가 아닌 레인에 106초 이상의 유휴(slack)가 있다.** 신규 검증은 여기에만 배치해야 한다(§7).
5. **비검증 고정비의 단일 최대 항목은 toolchain 캐시 전송 49.6초 = wall의 15.3%** 이며, 같은 1.06 GiB 페이로드를 두 잡이 각자 받는다(§5).

---

## 2. wall 분포 (merge_group `admission-gate`, n=12)

| 지표 | 값 |
|---|---|
| 표본 | 12 (2026-11-26T03:27:30Z – 23:48:05Z, 전건 success) |
| 최소 | **314 s** |
| p50 | **381 s (6.35 분)** |
| 평균 | 405 s (6.75 분) |
| 최대 | **713 s (11.9 분)** — 1건 |
| 500 s 초과 | **1 / 12** |

원자료(초, 최신순): `334, 324, 362, 713, 362, 450, 348, 314, 416, 418, 417, 400`.

**713초 배치의 원인 귀속**: 해당 배치(run `45863436934`)의 `attest / build-base-artifacts` 는 47초 → **374초**로 늘었고, 초과분의 거의 전부가 `[build] Checkout B only` = **307초**(정상 3–6초)다. 같은 잡의 `setup-axiom-toolchain` 은 44초로 정상 범위였다. 즉 **검증 항목 수의 함수가 아니다.**

---

## 3. 한 배치의 전체 분해 (run `45911585676`, wall 324 s)

| 잡 | 초 | 임계경로 |
|---|---:|---|
| `closure-deriver` | 80 | 아니오 (병렬, 141초에 유휴 진입) |
| `attest / build-base-artifacts` | **53** | **예** |
| `attest / admission-independents` | 81 | 아니오 |
| `attest / go-critical-lane (0)` | 91 | 아니오 (matrix 병렬) |
| `attest / go-critical-lane (1)` | **108** | **예** |
| `attest / go-critical-rollup` | 4 | 아니오 |
| `attest / admission-check` | **62** | **예** |
| `gateway / select` | 61 | 아니오 |
| `mint-prepare / prepare` | **24** | **예** |
| `mint-publish / publish` | **59** | **예** (verdict와 병렬) |
| `verdict / admission-check` | 58 | 아니오 (publish와 병렬) |
| `admission-check` (required context) | 3 | **예** (∧ 결속만) |
| **임계경로 합** | **309** | 53 → 108 → 62 → 24 → 59 → 3 |
| **총 wall** | **324** | 잡 간 스케줄러 갭 ≈ 15 |

### 3-1. `attest / build-base-artifacts` = 53초

| 스텝 | 초 |
|---|---:|
| Set up job | 2 |
| `[build] Checkout B only` | 6 |
| `setup-axiom-toolchain` | **30** |
| └ keygen (`git archive` + closure digest) | 0.6 |
| └ **A-cache restore (1,136,276,758 B ≈ 1.06 GiB)** | **19.4** |
| └ B-cache restore (53,422,937 B) | 1.2 |
| └ a-verify / a-probe / save-auth 등 | ≈ 8.8 |
| `[build] Compile derived-closure deriver from B` | 3 |
| upload base-built artifacts / nimcache | 5 + 3 |
| history record ×2, Post checkout | 2 + 1 |

supply-mode **HIT** 배치이므로 `nimcache functional probe` / `Lake build smoke` / `Build bin/ax` 는 **skip** 이다. 즉 이 잡은 30초를 프로비저닝에 쓰고 나머지 대부분을 업로드에 쓴다.

### 3-2. `attest / go-critical-lane (1)` = 108초

| 스텝 | 초 |
|---|---:|
| Set up job + checkout B + checkout M | 1 + 7 + 2 |
| `setup-axiom-toolchain` | **41** |
| └ keygen | 0.6 |
| └ **A-cache restore (동일 1,136,276,758 B)** | **30.2** |
| └ B-cache restore | 2.7 |
| └ 기타 | ≈ 7.5 |
| Download base-built artifacts | 4 |
| Candidate identity + Judgment CAS plan + Overlay M | 1 + 5 + 1 |
| **`[lane] evidenceId contract check` (self-check battery)** | **35** |
| GO-critical admission tests | 1 |
| upload judgment files + nimcache | 1 + 5 |

`A-cache` 는 두 잡에서 **같은 a-key·추정 1.06 GiB**이며 둘 다 `exact-hit=true` 다.

---

## 4. slack 계산 — 왜 검증을 늘려도 wall이 늘지 않는가

| 지점 | 종료/시작 | 근거 |
|---|---|---|
| `gateway/select` 종료 | **141 s** | closure-deriver 80 + 61 |
| `mint-prepare` 시작 | **≈ 247 s** | 53 + 108 + 62 + 갭 |
| **유휴** | **≈ 106 s** | 이 구간에 검증을 추가해도 wall 불변 |
| `verdict` 종료 | ≈ 281 s | 247 + 58 (publish와 병렬이므로 wall 비지배) |
| `go-critical-lane (0)` 종료 | 91 s | shard 병렬, 108 s 샤드가 지배 |
| 비-wall 레인 (동일 배치) | bsec 99 / debt 78 / observer 64 / generation 34 / probe 15 | 141초 이전에 전부 종료 |

**따라서 "검증 기능을 늘리면 CI가 우상향한다"는 명제는 임계경로에 대해서만 참이다.** 검사를 추가할 때 그 레인이 §4 표의 유휴 구간 안에서 끝나는 한 wall은 움직이지 않는다.

---

## 5. 비검증 고정비 인벤토리 (줄일 수 있는가?)

| 항목 | 양 | 임계경로 기여 | 판정 |
|---|---|---|---|
| toolchain A-cache 전송 (2잡 × 1.06 GiB) | 1,136,276,758 B ×2 | **49.6 s (15.3%)** | **불가** — `~/.nimble`+`~/.choosenim`+`~/.elan`+`~/.local/bin`. 두 잡 모두 `lean --version`(go-critical) 과 `lake build`(build-base, supply MISS 시)를 요구한다. org는 **free 플랜·public repo**라 larger runner/커스텀 이미지/self-hosted가 공식적으로 불가하고, `jobs.<id>.container` 는 잡마다 `docker pull` 이 step 이전에 실행되어 wall을 늘린다. |
| B-cache 전송 | 53,422,937 B ×2 | 1.2 + 2.7 s | 불가 (B payload 자체가 supply) |
| `evidenceId contract check` | 35 s | 35 s | **불가** — 파이프라인 전체에서 **1회만** 실행(`admission-check.yml:4479`). 중복 아님 = 순수 검증. 단독 프로파일은 [vs_t3_evidenceid_battery_profile_2026-11-16.md](vs_t3_evidenceid_battery_profile_2026-11-16.md). |
| checkouts | 6 + 7 + 2 s | 15 s | 불가 (같은 잡이 2개 트리를 본다는 계약) |
| artifact 업로드 | 10 s | 10 s | 불가 (다운스트림 소비) |
| attest→mint envelope | 잡 경계 갭 ≈ 15 s | 15 s | 불가 (GitHub 잡 스케줄러) |

**남는 큰 레버는 App의 blob-equality 보호 계약(`DEBT#558`)뿐이며 App 소유 권한이다.** 저장소 내부에서 이를 흉내 내면 §0.3 신뢰 경계 위반이다.

---

## 6. 폐기된 최적화 후보 — 재조사 금지

같은 논의가 bypass 전례를 만들며 재개되는 것을 막기 위해 실측값과 함께 고정한다.

| 후보 | 기대 | 실측 | 판정 |
|---|---|---|---|
| keygen `git archive` pathspec 축소(`action.yml:307-308`) | 잡당 5–15 s | 전체 트리 6,895파일/93,559,605 B → closure 1,478파일/17,147,416 B 로 줄여도 **archive 생성 310 ms → 75 ms**. keygen 스텝 실측 **0.6 초** | **폐기** — wall 기여 0.4 s 수준. `.github/**` 는 App trust surface라 bypass 1회의 값이 아니다 |
| B checkout 에 `http.lowSpeedLimit/lowSpeedTime` | tail 유계 | `lowSpeedLimit 1024`(1 KiB/s)는 관측된 정체(204 MB/307 s ≈ 664 KiB/s)에 **발화하지 않는다**. 발화 조건을 올리면 `actions/checkout` 의 3회 재시도 × 120 s ≈ **390 s 후 hard fail** — 307초의 완만한 성공보다 개발자에게 나쁘다 | **폐기** |
| path filter / affected-only 실행 | 스킵 | 공식 문서: required workflow를 path filter로 skip 하면 그 check는 **Pending** 으로 남아 PR merge가 **blocked**. `merge_group` 트리거에는 `paths`/`paths-ignore` 키가 없다 | **불가** |
| `go-critical-lane` → `provision-scope: nim` | 30 s | `admission-check.yml:4486-4488` 이 `lean --version` 실패 시 **fail-closed**. Lean 필수 | **불가** |
| supply 판정을 provisioning 앞으로 이동 | 19.4 s | `[s5]` 가 `build/nimcache` 를 보는데 그 경로는 **B-cache restore 산출물**이다. 데이터 의존이라 순서를 바꿀 수 없다 | **불가** |
| `build-base` + `go-critical-lane` 잡 병합 | 41 s | `go-critical-lane` 은 **matrix 2-shard 병렬**(91 s / 108 s). 한 잡으로 합치면 ≈199 s 직렬화로 **악화** | **폐기** |
| `FROZEN`/trust surface pruning | — | 로컬·push 마찰만 줄고 wall 기여 ≈ 0. 2단계 우회 세례는 App 소유 의미론 | **이번 범위 밖** |

---

## 7. 신규 검증 배치 판정 규칙 (이 문서의 실질 산출물)

**R1 (선언).** 신규 검증은 (i) 소속 레인, (ii) 그 레인의 예상 종료 시각을 함께 선언한다.

**R2 (합이 아니라 최대).** 예산은 `Σ(검사 시간)` 이 아니라 `max(레인 종료 시각)` 으로 계산한다. 검사 개수는 예산 지표가 아니다.

**R3 (임계경로 초과 = 예산 개정).** 신규 검증이 속한 레인의 종료 시각이 현재 임계경로 종료(이 배치 기준 **309 초**)를 넘기면 그것은 "검증 추가"가 아니라 **"10분 예산의 명시적 개정"** 이며, 별도 승인·근거를 요구한다.

**R4 (skip 금지).** 경로 기반 skip 으로 검사를 면제하지 않는다 — required check 가 Pending 으로 남아 merge 를 막는다. 예산은 **레인 배치**로 지킨다.

**R5 (추가 위치).** 현재 여유가 가장 큰 곳은 `closure-deriver`(80 s) 이후 `mint-prepare`(247 s) 이전 구간의 **≈106 초**다. 신규 레인은 이 구간에서 종료하도록 배치한다.

---

## 8. 재현 명령

```bash
# 8-1. wall 분포 (n=12)
gh api "repos/Archright/Axiom/actions/runs?event=merge_group&per_page=100" \
  --jq '[.workflow_runs[]|select(.name=="admission-gate")]|sort_by(.created_at)|reverse|.[0:12][]|[.id,.created_at,((.updated_at|fromdate)-(.created_at|fromdate))]|@tsv'

# 8-2. 한 배치의 잡 타임라인
gh api "repos/Archright/Axiom/actions/runs/45911585676/jobs?per_page=100" \
  --jq '.jobs[]|[.name,.conclusion,((.completed_at|fromdate)-(.started_at|fromdate))]|@tsv'

# 8-3. 스텝 분해 (toolchain 내부 포함)
gh api repos/Archright/Axiom/actions/jobs/140220991383/logs > /tmp/bb.log
awk '/^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]\.[0-9]+Z ##\[group\]/ {
  d=substr($0,1,19); gsub(/[-:T]/," ",d);
  t=mktime(d)+substr($0,20,8);
  title=$0; sub(/^[^ ]+ ##\[group\]/,"",title);
  if (n>0) printf "%6.1f  %s\n", t-prevt, prevtitle;
  prevtitle=title; prevt=t; n++ }' /tmp/bb.log
grep -n "Cache Size" /tmp/bb.log
```

**8-3 기대 관측**: `Run ./.github/actions/setup-axiom-toolchain` → keygen **0.6 s** → `actions/cache/restore` **19.4 s** (`Cache Size: ~1084 MB (1136276758 B)`).

---

## 9. 한계

1. 이 문서는 **Reporter** 다. 게이트가 아니며, 새 `make` 타깃·워크플로 잡·verdict producer 를 만들지 않는다.
2. 표본은 **단일 날짜 12건**이다. 플랫폼 네트워크 변동(§2의 713초)은 표본을 늘려도 재발할 수 있다.
3. A-cache 전송 시간은 같은 페이로드에서도 **19.4초 / 30.2초**로 흔들렸다(두 잡, 동일 런). 이 분산은 저장소 코드가 아니라 캐시 서비스·네트워크의 성질이다.
4. `recipe_hash`(`action.yml:350`)가 `Makefile config.nims config/effects.nims src/gate/config.nims` 를 **working tree** 에서 읽는 결함은 이번 문서에서 **보고만** 한다(B key 세대를 움직이는 별도 사안).
5. §5의 "불가" 판정은 이 저장소의 플랫폼 조건(free 플랜, public repo, 호스티드 러너)에 근거한다. 조건이 바뀌면 재평가 대상이다.