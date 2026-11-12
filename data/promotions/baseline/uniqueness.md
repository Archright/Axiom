# "generation-acceptance" check-context 유일성 사전 검증 (GPA Phase 0 §6.1)

- 관측 시각(UTC): **2026-10-21T18:42:35Z** (KST 2026-10-22 03:42:35)
- 관측 주체: Phase 0 조사 (읽기 전용 — `gh api` / `git` 조회만 수행, 저장소 파일 미변경)
- 대상 브랜치/기준 트리: `origin/main` = `e75f005c73b1aa54a179345f12b4f5e95013a1b1`

---

## 1. 결론 (요약)

> **"generation-acceptance" 이름 충돌: 없음 (NO COLLISION)**
>
> 근거 3중:
> 1. 최근 main 커밋 10개의 check-runs에서 수집된 **distinct check name 40개 어디에도 `generation-acceptance` 없음**. `generation` 또는 `acceptance`를 부분 문자열로 포함한 check name조차 **0건**.
> 2. `origin/main` 트리 전체(`git grep -n "generation-acceptance" origin/main -- .`)에서 문자열 **0건**. `.github/`·`dynamic/` 하위도 동일. 게다가 `origin`의 **모든 remote ref** 전수 grep에서도 0건.
> 3. `dynamic/dependabot/*` 워크플로 2건은 **GitHub/Dependabot가 API 상에서 자동 생성한 합성(synthetic) 워크플로**이며 `event=dynamic`, `actor=dependabot[bot]`으로만 발화한다. `origin/main` 트리에는 `dynamic/` 디렉터리가 **존재하지 않으므로**(파일 0개) push 가능한 경로가 아니며, 따라서 `file_path_restriction`의 우회 벡터가 아니다.

단, 이 판정은 **"check name(context) 충돌 없음"**에 대한 것이다. §5에 서술한 잔여 위험(같은 Actions App 내 name 스푸프, GitHub가 same-name을 구별하지 않는 플랫폼 한계)은 별개이며 **"유일 producer" 선언을 대체하지 않는다**.

---

## 2. 최근 main 커밋 10개의 check-runs 전수 수집

### 2.1 수집 방법

```
GET /repos/Archright/Axiom/commits?sha=main&per_page=10      # 커밋 목록(10건)
GET /repos/Archright/Axiom/commits/<sha>/check-runs?per_page=100   # 각 커밋의 check-run 목록
```

수집 커밋(최신→과거):

| # | SHA | committer date | subject |
|---|---|---|---|
| 1 | e75f005c73b1aa54a179345f12b4f5e95013a1b1 | 2026-10-21T16:55:20Z | Merge pull request #1021 from Archright/test/v5-acceptance-c |
| 2 | 50a46da2ba70363ce1f0538ad0913b2bbdfa6c35 | 2026-10-21T16:48:26Z | test(v5): acceptance C — intentional closure-input change, reuse must be denied |
| 3 | 40be184e42d6b3f49c46029e80729e0dae229f6d | 2026-10-21T16:32:05Z | Merge pull request #1020 from Archright/docs/v5-acceptance-b2 |
| 4 | 5b9d23f4362cde2569292e56d70d7ecc1f195b20 | 2026-10-21T16:23:34Z | docs(evidence): v5 acceptance B2 — same-closure reuse finalization |
| 5 | 76aa3edb524165f417151cea599483e03446e7e7 | 2026-10-21T15:48:32Z | Merge pull request #1019 from Archright/fix/v5-lane-outcome-guard |
| 6 | ea0adc4f62203138c6f4d179a2ec4e21f551f772 | 2026-10-21T15:18:45Z | fix(admission): v5 lane outcome semantics — verified-REUSED is an admissible out |
| 7 | 5affbcd27ed5458b8911a185748b134a03f44313 | 2026-10-21T14:57:47Z | fix(drift): drop the nimble-install bootstrap step |
| 8 | 011c5127d1ab2885628c4d17e06f58f75ecf0cab | 2026-10-21T13:38:00Z | Merge pull request #1016 from Archright/docs/v5-acceptance-b |
| 9 | 30a7e8861ca96a5248b4c5bf86c4148a53c15f2c | 2026-10-21T13:24:43Z | Merge pull request #1015 from Archright/fix/drift-observer-target |
| 10 | 0beb9cf3b3a8afa993aec005694cd573114e4feb | 2026-10-21T13:20:12Z | docs(evidence): v5 acceptance B — same-closure reuse vehicle |

### 2.2 수집된 distinct check name 전수 (40개)

각 이름에 대해 등장 횟수(10 커밋 합산) / 생산 App id를 병기한다. **모든 check는 app_id=15368(GitHub Actions)** 로만 생산되었다.

| # | check name | 등장(10커밋 합산) | app_id |
|---|---|---|---|
| 1 | `admission-check` | 9 | 15368 |
| 2 | `admission-ssot-drift` | 2 | 15368 |
| 3 | `anchor-resolve` | 8 | 15368 |
| 4 | `attest / admission-check` | 8 | 15368 |
| 5 | `attest / build-base-artifacts` | 8 | 15368 |
| 6 | `attest / go-critical-lane` | 4 | 15368 |
| 7 | `attest / go-critical-lane (0)` | 4 | 15368 |
| 8 | `attest / go-critical-lane (1)` | 4 | 15368 |
| 9 | `attest / go-critical-rollup` | 8 | 15368 |
| 10 | `bsec-integrity` | 8 | 15368 |
| 11 | `closure-deriver` | 8 | 15368 |
| 12 | `debt-registry-gate` | 8 | 15368 |
| 13 | `detect` | 1 | 15368 |
| 14 | `gateway / candidate-build-arm` | 8 | 15368 |
| 15 | `gateway / ci-bootstrap` | 8 | 15368 |
| 16 | `gateway / gateway-identity-gate` | 8 | 15368 |
| 17 | `gateway / gateway-shard` | 8 | 15368 |
| 18 | `gateway / proof-reconcile` | 8 | 15368 |
| 19 | `gateway / select` | 8 | 15368 |
| 20 | `merge-admission-sanity` | 8 | 15368 |
| 21 | `mint-prepare / prepare` | 8 | 15368 |
| 22 | `mint-prepare / publish` | 8 | 15368 |
| 23 | `mint-publish / prepare` | 9 | 15368 |
| 24 | `mint-publish / publish` | 8 | 15368 |
| 25 | `observe` | 8 | 15368 |
| 26 | `probe-capture` | 4 | 15368 |
| 27 | `probe-judge` | 4 | 15368 |
| 28 | `publish` | 87 | 15368 |
| 29 | `rearm` | 4 | 15368 |
| 30 | `report` | 1 | 15368 |
| 31 | `repository-surface` | 4 | 15368 |
| 32 | `skip-report` | 87 | 15368 |
| 33 | `sweep-test-issues` | 1 | 15368 |
| 34 | `trust-surface-codeowners` | 8 | 15368 |
| 35 | `trusted-writer-set-pairing` | 8 | 15368 |
| 36 | `verdict / admission-check` | 8 | 15368 |
| 37 | `verdict / build-base-artifacts` | 9 | 15368 |
| 38 | `verdict / go-critical-lane` | 9 | 15368 |
| 39 | `verdict / go-critical-rollup` | 9 | 15368 |
| 40 | `verify-trusted-writer-set` | 8 | 15368 |

### 2.3 판정

```
'dgeneration-acceptance' in collected_names  →  False
names containing 'generation' (case-insens)  →  []      (0건)
names containing 'acceptance' (case-insens)  →  []      (0건)
```

**→ `generation-acceptance` 부재 확인 (PASS).**

참고: 현재 repo ruleset 20303214의 required context 3종(`admission-check` / `bsec-integrity` / `debt-registry-gate`)은 위 목록에 존재하며, `admission-check`는 `Archright/.github`의 `admission-gate-v2.yml`이 job `admission-check`로 생산하고 나머지 둘은 repo-native workflow(381835906 / 389486255)가 생산한다. `generation-acceptance`는 이 3者和 이름이 겹치지 않는다.

---

## 3. `origin/main` 트리 전수 grep

```
$ git grep -n "generation-acceptance" origin/main -- .          # 전체 트리
(출력 0건)

$ git grep -l "generation-acceptance" origin/main -- .github/ dynamic/
(exit 1 = 매칭 없음)

$ git for-each-ref --format='%(refname)' refs/remotes/origin | \
    while read r; do git grep -l "generation-acceptance" "$r" -- .; done
(출력 0건 — origin의 모든 remote ref에서 무매칭)
```

**→ `origin/main` 및 origin 전체 ref에서 문자열 부재 확인 (PASS).**

추가로, `origin/main`의 `.github/` 실체 경로는 **19개**(workflow 18 + action 1)이고 `dynamic/`는 **0개**가 확인되었다. `origin/main`의 workflow 파일 목록:

```
.github/actions/setup-axiom-toolchain/action.yml
.github/workflows/admission-check.yml
.github/workflows/admission-ssot-drift.yml
.github/workflows/bsec-integrity.yml
.github/workflows/certificate-mint.yml
.github/workflows/ci-cache-publisher.yml
.github/workflows/closure-watcher.yml
.github/workflows/debt-registry-gate.yml
.github/workflows/diagnostic-authority.yml
.github/workflows/gateway-jobs-measure.yml
.github/workflows/h4-routing-measure.yml
.github/workflows/hardware-falsification-smoke.yml
.github/workflows/merge-queue-rearm.yml
.github/workflows/observation.yml
.github/workflows/probe-merge-queue.yml
.github/workflows/release-ship.yml
.github/workflows/repository_surface.yml
.github/workflows/runner-pool-acceptance.yml
.github/workflows/trusted-writer-set.yml
```

`generation-acceptance.yml`은 **존재하지 않는다** → 신규 파일로 추가 예정.

### 3.1 주의 — 워크플로 API 레지스트리에는 **origin/main 트리에 없는 항목이 남아 있다**

`GET /repos/Archright/Axiom/actions/workflows`가 보고하는 `.github/workflows/**` 경로 22개 중 **4개는 `origin/main` 트리에 파일이 존재하지 않는다**:

| workflow id | path | state | 트리 존재 |
|---|---|---|---|
| 381954965 | `.github/workflows/spoof-probe-a.yml` | **active** | **없음** |
| 381958514 | `.github/workflows/spoof-probe-b.yml` | **active** | **없음** |
| 363068798 | `.github/workflows/pr-verification.yml` | disabled_manually | 없음 |
| 357643164 | `.github/workflows/scaleset-canary.yml` | disabled_manually | 없음 |

- `spoof-probe-a/b`는 2026-10-12 스푸프 프로브에 쓰인 워크플로로, main에서 파일은 삭제되었으나 **레지스트리에 `active`로 잔존**한다. 같은 경로에 파일이 다시 올라오면 GitHub는 **동일 workflow id를 재사용**하고, job id가 곧 check name이 된다(과거 실측: `spoof-probe-a81de2`).
- **GPA에 대한 함의**: "workflow API에 `generation-acceptance`가 없다"는 사실만으로는 등록 부재의 증명이 되지 않는다(레지스트리 잔존 항목이 있으므로). 본 §6.1 판정이 성립하는 이유는 **check-run 전수 조사(40개 distinct name) + 트리 전수 grep**이라는 **2개의 독립 증거**에 있다.
- **따라서 GPA v1이 `.github/workflows/generation-acceptance.yml`을 추가할 때, 그 파일의 workflow id가 "예상한 새 id"가 될지 "레지스트리에 이미 점유된 id"가 될지를 확인해야 한다**(ruleset PUT 전 readback 대상). 착지 후 check-runs 재수집으로 동일 판정을 한 번 더 수행할 것.


---

## 4. `dynamic/dependabot/*` 경로 실체 조사

### 4.1 워크플로 API 실체

| workflow id | name | path (API가 보고하는 경로) | state | created_at | runs(total) |
|---|---|---|---|---|---|
| 362065556 | Dependency Graph | `dynamic/dependabot/update-graph` | active | 2026-09-19T21:56:37+09:00 | 2 |
| 366563934 | Dependabot Updates | `dynamic/dependabot/dependabot-updates` | active | 2026-09-25T09:50:11+09:00 | 99 |

html_url도 실제 파일 경로가 아니다:
- `https://github.com/Archright/Axiom/actions/workflows/dependabot/update-graph`
- `https://github.com/Archright/Axiom/actions/workflows/dependabot/dependabot-updates`

### 4.2 생성 메커니즘 — **UNREADABLE(추정 금지)**

`dynamic/` 경로의 워크플로는 **repo에 저장되지 않고 GitHub가 런타임에 생성**한다. 관측된 결정적 증거:

- run 이벤트가 **`event=dynamic`** (push/pull_request/schedule 아님 — GitHub 내부 동적 트리거).
- `actor` = `triggering_actor` = **`dependabot[bot]`**.
- `origin/main` 트리에는 `dynamic/` 디렉터리 자체가 **존재하지 않는다** (`git ls-tree -r --name-only origin/main -- dynamic/` → 0개). 체크아웃된 `test/v5-acceptance-c`(HEAD `50a46da2`)도 동일하게 0개.
- `origin/main`의 `.github/dependabot.yml`이 존재하고 내용(관측):
  ```yaml
  version: 2
  updates:
    - package-ecosystem: "github-actions"
      directory: "/"
      schedule:
        interval: "weekly"
  ```
  즉 repo는 `github-actions` 에코시스템의 **주간** 버전 업데이트만 선언한다.

최근 run 예시:

| workflow id | run id | conclusion | event | created_at | actor |
|---|---|---|---|---|---|
| 366563934 | 39039731345 | success | dynamic | 2026-10-17T14:12:06Z | dependabot[bot] |
| 366563934 | 38070691618 | success | dynamic | 2026-10-10T17:11:00Z | dependabot[bot] |
| 366563934 | 38069453708 | success | dynamic | 2026-10-10T16:52:58Z | dependabot[bot] |
| 366563934 | 38060957859 | success | dynamic | 2026-10-10T14:46:38Z | dependabot[bot] |
| 366563934 | 38060957286 | success | dynamic | 2026-10-10T14:46:37Z | dependabot[bot] |
| 362065556 | 35552649662 | success | dynamic | 2026-09-21T01:59:17Z | dependabot[bot] |
| 362065556 | 35444310395 | success | dynamic | 2026-09-19T12:56:37Z | dependabot[bot] |

→ **결론**: 이 2건은 GitHub 플랫폼이 Dependabot 기능과 결합해 만든 **합성 워크플로**이며, `.github/workflows/` 하위의 저장소-resident 파일이 아니다.

> **UNREADABLE: `dynamic/dependabot/*` 워크플로의 정확한 생성 메커니즘(GitHub 내부 경로)의 공식 규격은 GitHub REST API로 관측 불가.**
> 관측된 것은 (a) `event=dynamic`, (b) `actor=dependabot[bot]`, (c) repo 트리 부재, (d) `event=dynamic`은 GitHub 내부 동적 트리거 전용이라는 것까지. **"저장소에 존재하는가"의 답은 "존재하지 않는다"(0개)이다.**

### 4.3 `file_path_restriction` 경로 포함 여부

push ruleset 23967915(`execution-surface-create`)의 실제 값:

```json
{ "type": "file_path_restriction",
  "parameters": { "restricted_file_paths": [".github/workflows/**/*", ".github/actions/**/*"],
                  "ignored_file_paths": [] } }
```

- `dynamic/dependabot/**` 는 **`restricted_file_paths`에 포함되지 않는다** (패턴에 없다).
- **그러나 이 사실은 우회 벡터가 아니다.** 근거:
  1. `dynamic/dependabot/*` 경로의 파일은 **git 트리에 존재하지 않는다** → 어떤 push도 그 경로를 변경할 수 없다. Git은 존재하지 않는 경로의 변경을 push할 수 없다.
  2. 해당 워크플로는 `event=dynamic` + `actor=dependabot[bot]`로만 실행되며, 그 실행은 **GitHub 플랫폼 내부**에서 생성된 사본을 구동한다.
  3. 따라서 "dynamic 경로 변경으로 push rule을 우회해 execution surface를 바꿀 수 있다"는 시나리오는 **구조적으로 성립하지 않는다**.

**단, 역방향 잔여 위험은 존재한다**: `file_path_restriction`이 `.github/workflows/**/*`만 보호하므로, **`dynamic/` 경로가 저장소-resident하게 진화**(예: `dynamic/` 디렉터리를 커밋하여 Dependabot이 `.github/workflows/` 바깥에 워크플로를 두는 배치)는 규칙 범위 밖이다. 현재는 그런 파일이 0개이므로 **잠재(potential) 위험이며 실측된 취약점이 아니다**. GPA의 execution-surface 정의는 `dynamic/**`를 포함하도록 유지하되, 이 부분은 "push rule이 못 막는 영역"이라는 사실을 ADR에 명시해야 한다.

---

## 5. 판정 근거의 한계 (정직한 경계)

| 검증한 것 | 검증하지 못한 것 |
|---|---|
| context **이름** 충돌 없음 (40 distinct names 전수, `generation`/`acceptance` 부분문자열 0건) | 다른 App이 `generation-acceptance`라는 **check name**을 만들 수 있는가 → **GPA의 `integration_id=15368` 결속이 방어선**(repo ruleset 20303214의 기존 3-check와 동일 패턴) |
| `origin/main` + origin 전체 ref 트리 문자열 부재 | **같은 App(15368 = GitHub Actions) 내부의 same-name 스푸프** → GitHub 플랫폼은 이름만 보고 required check를 충족 처리한다. 저장소 문서 `docs/evidence/merge_freeze_spoof_probe_2026-10-12.md`가 이를 실측 기록: `spoof-probe-a81de2` 스푸프가 required check로 통과했다. → **ADR-0036 잔여 위험으로 명시적 수용 필요** |
| `dynamic/dependabot/*`는 저장소-resident 아님 (트리 0개) | `dynamic/`가 **향후** 저장소-resident해지는 경우의 push rule 사각 |
| open PR = 0 → 미병합 PR이 만든 동명 check 없음 | **향후 생성될 PR/워크플로의 동명** (GPA v1 착지 후 재점검 필요) |
| `origin/main`의 `.github/workflows/**` 파일에 `generation-acceptance.yml` 부재 | 다른 **브랜치**(origin에 fetch된 것 외)의 미push 로컬 파일 (관측 범위 밖) |

---

## 6. 결론 문장 (GPA Phase 1 착지 판단용)

> 실측 기준선(2026-10-21T18:42:35Z) 시점, `generation-acceptance` 라는 check context 이름은
> ① 최근 main 커밋 10개의 check-runs에서 수집된 40개 distinct check name 어디에도 존재하지 않고,
> ② `origin/main` 및 origin의 모든 remote ref 트리 어디에도 해당 문자열이 없으며,
> ③ `dynamic/dependabot/*` 2건은 저장소-resident 파일이 아니므로同名 producer가 될 수 없다.
>
> **→ 이름 충돌 없음 (NO COLLISION).**
> 단, 이는 **이름 기준 유일성**의 확정이며, **"유일 producer" 선언이 아니다**(동일 App 내 name 스푸프 잔여 위험은 §5 참조). GPA v1의 `generation-acceptance`를 required로 등록하기 전, 규칙 20303214의 required set에 4번째 context로 `generation-acceptance`(integration_id 15368)를 추가하는 PUT → readback 일치 확인은 그대로 유효.
>
> **등록 전 재점검 권고(Phase 1 착지 시점)**: self-PR이 이미 머지된 상태에서 check name 목록을 한 번 더 수집하고, §4.3의 `dynamic/` resident화 여부를 재확인할 것.
