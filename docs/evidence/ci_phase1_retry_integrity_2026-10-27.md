# CI Phase 1 — 도구 설치 실패의 재시도 낭비 제거

**범위**: 러너 부트스트랩 경로에서 **관측된** 두 실패 클래스만 다룬다.
(1) choosenim 부트스트랩의 `curl` exit 35, (2) dpkg lock 경합 exit 100.
측정·이미지·인스턴스 선택은 이 문서의 범위가 아니다.

---

## 1. 변경

| # | 위치 | 변경 |
|---|---|---|
| 1 | `.github/actions/setup-axiom-toolchain/action.yml` — Install Nim (x64) | `curl \| sh` → `-o` 파일 + `sha256sum -c` + 유한 재시도, 통과 시에만 실행 |
| 2 | `.github/actions/setup-axiom-toolchain/action.yml` — Install Nim (arm64) | tarball 재시도 + `sha256sum -c` |
| 3 | `.github/workflows/runner-pool-acceptance.yml` — Install Nim (x64) | 1과 동일 |
| 4 | `.github/actions/setup-axiom-toolchain/action.yml` — libpcre3 | `-o DPkg::Lock::Timeout=300` |
| 5 | `.github/workflows/release-ship.yml` | 〃 |
| 6 | `.github/workflows/h4-routing-measure.yml` | 〃 |

**되돌린 편집 2건 — 계약이 거부했다(우회하지 않았다).**

| 파일 | 거부 사유 | 근거 |
|---|---|---|
| `.github/workflows/admission-check.yml` | **pinned engine** — `config/trusted_writer_set.json`의 blob 핀이 결속되고, org orchestrator가 callee를 커밋 SHA로 고정 | §1b |
| `.github/workflows/hardware-falsification-smoke.yml` | **FROZEN 표면** — `make check-repository-surface` → `SURFACE_FORBIDDEN`, `changeClass: FROZEN` | `config/repository_surface.json`, policy v89 |

고정한 해시:

```
6c38d83e5f33feb0317647f4fbd757fd2128fef5cdf61b6a6e1709c63b0d8d5c  choosenim/init.sh  (이동 표적)
cd86a6e2bcbf029c4870aa51df5c0169345dbf9959889112fd15d403c13ae33a  nim-2.2.10-linux_arm64.tar.xz  (버전 고정 URL)
```

`init.sh`는 **이동 표적**이다(내용은 nim-lang.org가 갱신, 내부에서 `choosenim/stable`을 조회해
GitHub 릴리스 tarball을 받는다). 해시 불일치 시 **다운로드한 스크립트를 실행하지 않고** 실패한다.
재핀 절차는 소스 주석에 있다.

### 1b. `admission-check.yml`은 **의도적으로 건드리지 않는다**

이 파일에는 같은 클래스의 `apt-get install` 한 지점이 있으나, 편집은 계약상 불가능하다.

| 사실 | 근거 |
|---|---|
| 이 파일은 **pinned engine**이다 — `config/trusted_writer_set.json`의 `trustedAdmissionWorkflowSha`가 이 파일의 **git blob SHA**를 값으로 갖는다 | `config/trusted_writer_set.json:41`, ADR-0022 §5 |
| 변경하면 pre-push가 `EPOCH_TRANSACTION_INCOMPLETE`/`INCONSISTENT`로 차단한다(실측 3건) | `.githooks/pre-push` → `tools/ci/epoch_transaction_gate.nim --diff` |
| 계약상 같은 커밋에서 `trustedAdmissionWorkflowSha` + `config/policy/epoch_manifest.json:productionExecutionPin`을 **함께** 전진시켜야 한다 | `epoch_transaction_gate.nim` G2a |
| 그 위에 **org 저장소 callee 핀이 별도로** 존재한다 — `admission-check.yml@76aa3edb524165f417151cea599483e03446e7e7` | `Archright/.github/.github/workflows/admission-gate-v2.yml:430` |
| 따라서 이 저장소에서 파일을 고쳐도 필수 검사는 **옛 callee를 계속 실행**한다(핀 회전은 main 착지 후의 2단계 handoff) | 〃 |
| 이 핀 불일치가 **거짓 성공**을 만든 이력이 있다 — 옛 callee의 `merge_group` 스킵 + `--dry-run` 무조건 0 | `data/debt_registry.json` 항목(2026-10-13 관측) |

**판정**: apt 타임아웃 1줄을 위해 pinned engine + org 핀을 2단계로 회전하는 것은 비례하지 않고,
회전을 완료하지 않은 상태의 편집은 **필수 검사에 반영되지 않는 무효 변경**이다. 관측된 실패 경로는
`setup-axiom-toolchain`(41개 호출처)이므로 그쪽만 고친다. `admission-check.yml`은 원복했다
(blob `83260f72a8e47645f30618fc426bc1fd7561587f` 복원 확인).

---

## 2. 측정 — curl 재시도 예산

로컬 `curl 8.5.0` (Ubuntu 24.04 빌드 = 러너와 동일 계열). 연결 직후 즉시 close하는 TCP 서버로
**시도 횟수**를 직접 계수했다.

| 플래그 | 시도 | 경과 | 종료코드 |
|---|---:|---:|---:|
| 없음 | 1 | 32 ms | 56 |
| `--retry 4 --retry-delay 2 --retry-max-time 20` (**no** `--retry-all-errors`) | **1** | 16 ms | 56 |
| `--retry 4 --retry-delay 2 --retry-max-time 5` + `--retry-all-errors` | 4 | 6.0 s | 56 |
| `--retry 4 --retry-delay 2 --retry-max-time 20` + `--retry-all-errors` | 5 | 8.0 s | 56 |

**판정**: `--retry` 단독은 recv 실패(56)·SSL connect(35)를 재시도하지 않는다(1회/16 ms).
`--retry-all-errors`가 있어야 실제로 재시도한다. 채택한 조합은 **4회 시도 / 6.0초 상한**이다.
상한은 `--retry-max-time` + `--max-time`이며, `--retry-max-time` 단독은 상한이 아니다
(curl 문서: 재시도 시점에만 적용되고 진행 중인 전송은 중단하지 않는다).

부분 파일 안전성: curl 문서는 재시도 직전 **출력 파일**로 기록된 부분 데이터를 제거하지만
`|` 파이프·`>` 리다이렉트로 흘린 데이터는 제거하지 않는다. 그래서 `| sh`를 폐기하고 `-o`를 쓴다.

---

## 3. 측정 — dpkg lock 타임아웃이 실제로 대기하는가

`flock`은 dpkg의 `fcntl` 락과 상호작용하지 않으므로 **무효**였다(첫 시도 기각).
`fcntl.lockf`로 `/var/lib/dpkg/lock-frontend`를 점유한 뒤 `apt-get install --reinstall`로 측정했다.

| 설정 | 락 점유 | 결과 | 경과 | 종료코드 |
|---|---|---|---:|---:|
| `DPkg::Lock::Timeout=0` | 8 s | `E: Could not get lock /var/lib/dpkg/lock-frontend. It is held by process 116853 (python3)` | **224 ms** | 100 |
| `DPkg::Lock::Timeout=30` | 8 s | `Setting up libpcre3:amd64` → 성공 | **11.3 s** | 0 |

**판정**: 옵션은 실제로 유효하다. 기본값(0)에서는 관측된 CI 실패와 **같은 메시지로 즉시 exit 100**,
300초를 주면 락이 풀릴 때까지 대기한 뒤 성공한다. 즉 이 변경은 "실패를 성공으로 바꾸는" 것이 아니라
**일시적 락 경합을 실패로 승격시키지 않는** 것이다.

---

## 4. 검증 (로컬 게이트)

```bash
$ ./bin/build_all_gates --release
Total:   84
Passed:  82
Skipped: 2  (accepted dead — DEBT#491, DEBT#492)
Failed:  0

$ ./bin/anti_theater_gate
[anti-theater] PASS — no theater signatures detected in 6 file(s)

$ ./bin/debt_engine --validate
Checks: 1513 total, 1513 passed, 0 failed
```

적용 범위:

```bash
$ grep -rn "DPkg::Lock::Timeout" .github/ | wc -l
8         # install 3지점 + 폴백 install 1지점 + update 3지점 + 주석 1건
$ grep -rn "apt-get .*install\|apt-get .*update" .github/ | grep -v DPkg::Lock::Timeout
.github/workflows/admission-check.yml:789,790            ← pinned engine (§1b)
.github/workflows/hardware-falsification-smoke.yml:119   ← FROZEN 표면
.github/actions/setup-axiom-toolchain/action.yml:563     (주석)
$ grep -rn "choosenim/init.sh | sh" .github/
h4-routing-measure.yml:330,482   ← 착지 경로 아님(수동 측정), 제외
```

---

## 5. 잔여 위험 (이 PR이 닫지 않는 것)

| # | 잔여 위험 | 근거 |
|---|---|---|
| 1 | `init.sh` **내부**의 choosenim 다운로드도 `curl`이며 재시도 플래그가 닿지 않는다 | 스크립트 소스 `get_platform`/`install()` — `curl -sSfL "$url" -o …` |
| 2 | 부트스트랩 해시가 상류 갱신 시 **빌드를 차단**한다 | 의도된 fail-closed. 재핀은 수동 검토 후 1줄 변경 |
| 3 | `apt-get update`의 락은 dpkg 락이 아니므로 타임아웃이 무효일 수 있다 | apt는 목록 락을 별도로 쓴다. install 경로가 실제 표적이다 |
| 4 | 게스트 셧다운에 의한 잡 중단 | 원인 미확정 — 증거가 저장소 밖(별도 조사) |
| 5 | `admission-check.yml:789`의 apt는 무방비로 남는다 | §1b — pinned engine + org callee 핀. 회전은 별도 2단계 |
| 6 | `h4-routing-measure.yml:330,482`의 `curl \| sh`는 그대로다 | 수동 측정 워크플로 — 착지 경로가 아니다. 같은 클래스지만 이 PR 범위 밖 |
| 7 | **org orchestrator는 이 액션을 커밋 SHA로 고정해 쓴다** — `setup-axiom-toolchain@18b180094a19096f15a268eeb110a1c7f2f4cfba` | `Archright/.github/.github/workflows/admission-gate-v2.yml:256`. 저장소 자체 워크플로(실패가 관측된 `debt-registry-gate`·`axiom-operational-slice`)는 로컬 액션을 쓰므로 이 수정이 적용된다. org 경유 경로는 org 핀 회전 후에 적용된다 |

1·5·6·7은 이 PR의 승인 범위 밖이며, 은폐하지 않고 여기 남긴다. 5·7은 "고치면 반영되지 않는" 상태이므로
고치는 것 자체가 무효이거나 위험하다 — 핀 회전과 함께 다뤄야 한다.

---

## 6. 이 PR이 하지 않는 것

- 이미지 사전 구성(베이킹)·스냅샷·GARM `--image` 변경 — Phase 2.
- 러너 동시성·`max_runners`·웜 러너 — 별도 실험.
- 재시도 "정책" 변경 — `rerun-failed-jobs`는 이미 적용돼 있다(독립 성공 잡의
  `started_at`/`completed_at`이 attempt 간 초 단위로 동일함을 확인). 잔존 재실행은
  전부 `needs` 의존자이므로 제거 대상이 아니다.
