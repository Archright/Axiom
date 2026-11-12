# CI 러너 부트스트랩 비용의 분해와 다음 슬라이스 경계 — 2026-10-28

**범위**: Phase 1(`ci_phase1_retry_integrity_2026-10-27.md`)이 착지한 뒤, 남은 병목을
**코드 변경 없이** 측정·확정한 결과. Phase 2(이미지 사전 구성)의 착수 여부를 판정하기 위한
입력이며, 이 문서 자체는 어떤 동작도 바꾸지 않는다.

값은 전부 실제 명령 출력 또는 공식 소스에서 복사했다. 출처를 함께 적는다.

---

## 1. 확정된 사실

### 1.1 GARM 러너 설치 템플릿에 "캐시된 러너" 분기가 이미 있다

`garm-cli template show 5 --format json` → base64 디코드 (310줄).
템플릿 이름 `axiom-garm-linux-202610270256`, `owner_id: admin`.

```
 23: RUN_HOME="/home/{{ .RunnerUsername }}/actions-runner"
152: if [ ! -d "$RUN_HOME" ];then
153:   downloadAndExtractRunner
158:   sudo ./bin/installdependencies.sh && break    # 5회 재시도, 15초 간격
167:   sendStatus "using cached runner found in $RUN_HOME"
168:   cd "$RUN_HOME"
```

이미지에 `actions-runner` 디렉터리가 존재하면 **tarball 다운로드와
`installdependencies.sh`가 템플릿 수정 없이 건너뛰어진다.**
이는 새 기능이 아니라 GARM이 이미 제공하는 분기다.

반대 위험: 이 분기에는 무결성 검사가 없다. 디렉터리가 불완전해도
"using cached runner"로 진입하고 `config.sh` 단계에서야 실패한다.

### 1.2 `ImageOS` / `ImageVersion`은 템플릿이 유도하는 관측값이다

```
263: # Axiom runner environment contract.
264: # The previous provider (Ubicloud) exposed ImageOS/ImageVersion and the pinned
265: # verifier reads them under `set -u`. Derive them from the VM itself, so the
266: # value is an observation, not a fabricated constant.
271: test "${ID:-}" = ubuntu || { echo "unexpected runner OS: ${ID:-unset}" >&2; exit 1; }
274: IMAGE_OS_VALUE="ubuntu${VERSION_ID%%.*}"
275: printf 'ImageOS=%s\nImageVersion=%s\n' ... >> "$RUN_HOME/.env"
```

`ubuntu24`는 상수가 아니라 기반 이미지의 `/etc/os-release` 유도값이다.
기반 이미지를 교체하면 이 값이 계약을 유지하는지 확인해야 한다.

### 1.3 러너 자격 증명은 템플릿이 직접 내려받는다

```
183: getRunnerFile "credentials/runner"                → $RUN_HOME/.runner
184: getRunnerFile "credentials/credentials"           → $RUN_HOME/.credentials
185: getRunnerFile "credentials/credentials_rsaparams" → $RUN_HOME/.credentials_rsaparams
186: getRunnerFile "system/service-name"               → $RUN_HOME/.service
```

이미지에 이 네 파일이 있으면 등록 신원이 이미지에 각인된 것이다.
이미지 검사 목록에는 `.runner` · `.credentials` · `.credentials_rsaparams` ·
`.service` · `_work`가 모두 포함되어야 한다.

### 1.4 `disable_updates=true`는 `apt-get update`를 제거하지 못한다

**증거 1 — GARM cloud-config 스키마** (`cloudbase/garm-provider-common/cloudconfig/cloudconfig.go:70-82`):

```go
type CloudInit struct {
	Users             []string    `yaml:"users"`
	PackageUpgrade    bool        `yaml:"package_upgrade"`
	Packages          []string    `yaml:"packages,omitempty"`
	SSHAuthorizedKeys []string    `yaml:"ssh_authorized_keys,omitempty"`
	SystemInfo        *SystemInfo `yaml:"system_info,omitempty"`
	RunCmd            []string    `yaml:"runcmd,omitempty"`
	WriteFiles        []File      `yaml:"write_files,omitempty"`
	CACerts           CACerts     `yaml:"ca-certs,omitempty"`
	BootCmd           []string    `yaml:"bootcmd,omitempty"`
}
```

`package_update` 필드가 **존재하지 않는다.** `NewDefaultCloudInitConfig()`(`:30-48`)는
`PackageUpgrade: true`, `Packages: []string{"curl","tar"}`로 시작한다.

**증거 2 — 실제 provider 바이너리** (`<user-home>/.axiom-garm/providers/garm-provider-openstack`):

```
yaml:"package_upgrade"                 ← 이것만 존재
json:"extra_packages" ...
json:"disable_updates,omitempty"       jsonschema:"description=Disable automatic updates on the VM."
toml:"disable_updates_on_boot"
```

**증거 3 — provider 설정** (`<user-home>/.axiom-garm/provider-config.toml`):

```toml
cloud = "ovh"
boot_from_volume = false
use_config_drive = false
disable_updates_on_boot = false        # provider 전역 스위치
```

**결론**: `extra_specs.disable_updates=true`는 cloud-init의 `package_upgrade`만 끈다.
`packages`가 비어있지 않은 한 cloud-init은 `apt-get update`를 계속 실행한다.
현재 스케일셋의 `extra_packages`는 14종이므로 `packages`는 항상 비어있지 않다.
`apt-get update`를 없애는 유일한 스케일셋 레버는 `extra_packages: []`이며,
그것이 update까지 없애는지는 **미검증**이다(기본 seed `[curl,tar]`가 남을 수 있다).

### 1.5 `garm-cli scaleset update`는 변경된 플래그만 전송한다

`cloudbase/garm/cmd/garm-cli/cmd/scalesets.go:377-432` — 모든 필드가 `cmd.Flags().Changed()` 게이팅.

CLI 기본값(`--max-runners 5`, `--min-idle-runners 1`, `--runner-bootstrap-timeout 20`)은
전송되지 않는다. 따라서 `--image` 단독 호출은 다른 필드를 덮어쓰지 않는다.
(계획서가 `--image` 단독 호출을 요구한 이유가 소스로 확인된다. 단, 적용 전후 JSON diff로
재확인해야 한다.)

### 1.6 라이브 스케일셋 2 실측

```
id=2  scale_set_id=9  name=ci-axiom-x64  provider=ovh-sgp1  flavor=c3-4
image=7daa4ffe-c4af-47e5-85e0-f86e610e6fe0
max_runners=8  min_idle_runners=<키 없음>  runner_bootstrap_timeout=6
disable_update=false        ← 러너 소프트웨어 자동 업데이트 ON
extra_specs={"disable_updates":true,"extra_packages":[14종]}
template_id=5  template_name=axiom-garm-linux-202610270256
state="pending_create"
```

### 1.7 스케일셋 `state` 필드는 건강 신호가 아니다

`params/params.go:207-211`에 `ScaleSetPendingCreate="pending_create"`,
`ScaleSetCreated="created"`, `ScaleSetError`, `ScaleSetPendingDelete`,
`ScaleSetPendingForceDelete`가 정의된다. 그러나 `ScaleSetCreated`는
**정의 외 사용처가 없다**(GitHub 코드 검색 결과 `params/params.go` 단일 히트).
`runner/pool/pool.go`·`workers/provider/instance_manager.go`의 `pending_create` 언급은
전부 **인스턴스** 상태다.

따라서 `state="pending_create"`를 이상 신호로 읽거나, `created`로의 전이를 기다려서는 안 된다.

---

## 2. 머지 게이트의 시간 분해 (실측)

`merge_group` 검증 1회 — `2026-10-27T16:48:13Z` 시작, 워크플로 5개
(`admission-gate` `generation-acceptance` `debt-registry-gate`
`observer-manifest-consistency` `axiom-operational-slice`).

### 2.1 잡별 `created_at → started_at`

| 잡 | 대기(s) |
|---|---:|
| attest/build-base-artifacts | 357 |
| closure-deriver | 310 |
| observe | 306 |
| debt-registry-gate | 282 |
| verdict/admission-check | 160 |
| admission-check (verdict workflow) | 158 |
| mint-prepare/prepare | 157 |
| attest/go-critical-rollup | 154 |
| mint-publish/publish | 153 |
| attest/admission-check | 152 |
| attest/go-critical-lane (0) | 151 |
| gateway/select | 148 |
| generation-acceptance | 147 |
| axiom-operational-slice | 139 |
| attest/go-critical-lane (1) | 136 |
| **합계 (잡 15개)** | **2,910 = 48.5 job-min** |

### 2.2 임계 경로

```
closure-deriver → gateway/select → go-critical-lane → attest/admission-check
→ mint-prepare/prepare → mint-publish/publish → verdict/admission-check
→ admission-check(final)
```

8개 잡이 순차로 **서로 다른 러너 8대**에서 실행된다
(`garm-fyym3yoqxtjq` `garm-ocgbo2hpp3pr` `garm-spw6xuzhpb0h` `garm-kmls9iazegv0`
`garm-pgz0xrdxqsys` `garm-gjugxznsfdnu` `garm-ufwauqwjsttk` `garm-tekgs8gtzlmg`).

| 값 | 초 | 분 |
|---|---:|---:|
| 임계 경로 대기 합 | 1,374 | 22.9 |
| merge_group 벽시계 | 1,958 | 32.6 |
| **비율** | | **70.2%** |

### 2.3 해석의 한계

`created_at → started_at`에는 ① 풀 포화 대기, ② GARM 반응, ③ VM 부팅·cloud-init,
④ 러너 등록이 모두 섞여 있다. **70.2% 전부를 부트스트랩이라고 주장할 수 없다.**

같은 시각(16:48:14)에 생성된 잡들의 대기가 139초(`axiom-operational-slice`)에서
310초(`closure-deriver`)까지 2.2배 벌어진 것이 ①의 존재 증거다.
Phase A에서 측정한 M3(GARM 반응)는 6초였다.

그러나 **공격 가능한 상한은 22.9분**이다. per-job 150초를 30초로 줄이면
`120 × 8 = 960초 = 16분`이 임계 경로에서 사라진다(32.6 → 약 16.6분).
실제 절감은 그중 부트스트랩 비중만큼이며, **그 비중은 아직 측정되지 않았다.**

### 2.4 이 수치가 뒤집는 것

- "고정 135초 기준선"은 실측 분포(136~357초)를 대표하지 못한다.
- 랜딩 1회당 부트스트랩은 15회 지불되고, 그중 8회가 임계 경로에 있다.
- 웜 러너 1대로 8단계 순차 사슬을 덮을 수 없다. GARM은 유휴 러너가 작업을 받으면
  대체 러너를 만들지만, 보충에 드는 시간이 다음 잡 도착 간격보다 길면 효과가 0이다.

---

## 3. A-레이어 캐시 실제 크기

```
gh api repos/Archright/Axiom/actions/caches
axiom-a-Linux-8497f84b…-7483645eecae   1,072,102,813 B  (1.07 GB)  2026-10-27T17:26Z
axiom-a-Linux-8497f84b…-3618d290e198   1,163,312,899 B  (1.16 GB)  2026-10-27T08:48Z
axiom-a-rt-…                              14,123,782 B  (14 MB)
A-캐시 전체 합계                          9,131,062,865 B  (9.13 GB)
```

GitHub 리포 캐시 한도는 10 GB다. **A-캐시 전체가 9.13 GB로 한도에 근접**해
오래된 엔트리가 밀려난다. "랜딩마다 1 GB대 다운로드"라는 전제는 실재한다.

---

## 4. OVH SGP1 단가 (공식, 2026-10-28 확인)

| 항목 | 단가 | 근거 |
|---|---|---|
| `c3-4` compute | S$0.0686/h | ovhcloud.com/en-sg/public-cloud/prices |
| `c3-4` local NVMe 50 GB | S$0.010935/h | 〃 (Storage → Local Storage) |
| Public IPv4 | S$0.00405/h **주소당** | 〃 (Network → Public IP) |
| `c3-4` all-in | **S$0.0836/h = S$0.001393/min** | 합산 |
| `d2-4` | S$0.0309/h (월 상한 S$17.16) | 〃 (General Purpose → Discovery) |
| 인스턴스 스냅샷/이미지 | S$0.000024/GB/h = S$0.01752/GB/월 | 〃 (Instance Backup) |
| Egress | 1 TB/월/프로젝트 무료, 초과 S$0.0145/GB | 〃 |

- **`c3-4`는 4 vCPU가 아니다** — 2 vCore / 4 GB / 50 GB local NVMe다.
- 과금 단위는 **초 단위, 리소스당 최소 1분**.
- 스냅샷은 원본 인스턴스를 삭제해도 자동 삭제되지 않고 계속 과금된다.
- **손익분기**: 스냅샷 2.16 GB = S$0.0378/월 ≈ c3-4 **27.2 VM-분**.
  VM당 30초를 절약하면 월 5.4 랜딩에서 본전.
  → **스냅샷 비용은 의사결정의 지배 변수가 아니다.**

미검증: SG GST 적용 여부, `d2-4`에 2026-10-01 분리가 적용되는지에 대한 d2 전용 문구,
청구서가 스냅샷을 실제 크기로 매기는지.

---

## 5. 게스트 증거 보존 — 유일한 내구 경로

### 5.1 SIGTERM 이후에는 post 스텝이 **구조적으로** 실행되지 않는다

| 수단 | 판정 | 근거 |
|---|---|---|
| `post:` / `post-if: always()` | 불가능 | `StepsRunner.cs:205-207` — shutdown 토큰 시 조건 재평가를 건너뛰고 `conditionResult=false` 유지 |
| `ACTIONS_RUNNER_HOOK_JOB_COMPLETED` | 불가능 | `JobExtension.cs:573-581`이 post-job step으로 등록 → 같은 skip 경로 |
| `actions/upload-artifact` + `if: always()` | 불가능 | 업로드도 스텝이다 |
| 셸 `trap` / `finally` | 불가능 | SIGINT → 7.5s → SIGTERM → 2.5s → kill 트리 |

서버 취소와 러너 종료는 다르다. 서버 취소는 `if: always()`를 재평가하지만,
러너 SIGTERM은 `RunnerShutdownToken` 경로라 재평가 자체를 건너뛴다.

`OperatingSystemShutdown` 문구는 Windows 서비스 호스트 Ctrl-Break 전용이며
(`Runner.cs:371-389`), Linux의 `systemctl stop`/SIGTERM은 언제나 `UserCancelled`다
(`Runner.cs:352-355`). 따라서 "OS 종료 문구가 없다"는 재부팅 배제 근거가 되지 못한다.

### 5.2 유일한 내구 sink는 GitHub 잡 로그이고, 주입점은 `ACTIONS_RUNNER_HOOK_JOB_STARTED`다

- 러너는 stdout을 250/500 ms 주기로 업로드한다(`src/Runner.Common/JobServerQueue.cs:32-33`).
- 시작 훅은 첫 사용자 스텝 **이전**에 실행되고 출력이 잡 로그로 간다
  (`JobExtension.cs:304-313`, `Program.cs:176-179`, `Constants.cs:279` = `"Set up runner"`).
- 활성 증명: 잡 로그에 `A Set up runner step has been configured by the self-hosted runner administrator`
  (`JobHookProvider.cs:46`).
- **전제**: (i) 러너 계정이 `systemd-journal`/`adm` 그룹이어야 `journalctl -b`가 전체를 본다,
  (ii) `ghs_*`·`--token` 리댁션 필수, (iii) 실패 시 비-0 종료
  (훅이 실패하면 **잡이 실행되지 않고 실패**한다 — fail-closed).

### 5.3 대안 경로는 전부 새 구성요소를 요구한다

- cloud-init `output:`은 로컬 파일 리다이렉션이다(`cloudinit/util.py:1677-1771`).
- `phone_home`은 고정 페이로드만 보낸다(`cc_phone_home.py:22-28`).
- GARM은 게스트 로그를 보관하지 않는다(`apiserver/controllers/agent.go:18,63`).
  `garm-cli debug-log`는 컨트롤러 자신의 로그다(`cmd/garm-cli/cmd/log.go:35-38`).
- OVH v1 API `cloud.json` 676경로 중 `console` 경로는 0개. `/vnc`는 대화형 URL이다.
- OpenStack `os-getConsoleOutput`만 가능하나 **서버 삭제 후 404** → 폴러 또는
  티어다운 훅이라는 새 구성요소가 필요하다.
- `systemd-journal-upload`는 HTTPS 수신자 + TLS + 저장소를 요구한다(과잉).

---

## 6. 검증되지 않은 것 (정직하게 남김)

1. **attempt 1 SIGTERM의 근본 원인.** 증거 경로는 확정했으나(§5.2), 원인 자체는 미확정.
2. **`extra_packages: []`가 `apt-get update`까지 제거하는지.** 기본 seed `[curl,tar]`가
   남을 수 있다. 실측 필요.
3. **부트스트랩 비중** — §2.3의 22.9분 중 VM 부팅·cloud-init이 차지하는 몫.
   GARM `runner_status` 전이(`pending`→`installing`→`idle`)로 분해 가능하나
   다수 표본이 필요하다.
4. **`action.yml`(setup-axiom-toolchain) 경로의 `init_sha256` 실행 증거.**
   A-캐시 히트로 `Install Nim`이 skip된다. A-key가 다른 환경(arm64)은 SL-09 게이트로
   skipped라 관측되지 않았다.
5. **SL-09 게이트 잡 5종**(`gateway-shard` 8-leg, `candidate-build-arm`,
   `proof-reconcile`, `gateway-identity-gate`, `ci-bootstrap`)의 실제 실행 시간.
6. **`c3-4` ↔ `d2-4` 실행 시간 차이.** 단가 차이는 2.7배(S$0.0836 vs S$0.0309)이나
   작업당 총비용은 실행 시간에 의존한다.

---

## 7. 다음 슬라이스에 주는 함의

1. **이미지 사전 구성은 GARM의 기존 분기를 쓰는 일이지 새 기능이 아니다.**
   템플릿 수정 없이 `actions-runner` 디렉터리를 이미지에 넣으면 다운로드가 사라진다.
2. **그러나 이득의 절반은 액션 게이트에 있다.** 설치 5단계가
   `a-restore.cache-hit != 'true'`에 묶여 있으므로, 이미지가 있어도 액션이 모르면
   A-레이어 1 GB대 다운로드가 그대로 발생한다.
3. **`disable_updates`는 이 문제의 답이 아니다.** `apt-get update`는 남는다.
4. **측정 계약을 먼저 고쳐야 한다.** M2/M3/M4의 의미가 §2.3의 분해와 일치해야
   "이미지가 얼마를 줄였는가"를 귀속할 수 있다.
5. **자원 회수 판정은 fail-closed여야 한다.** 자원이 존재하는 상태에서 실패하는지를
   먼저 시험하지 않은 술어는 영원히 통과한다.