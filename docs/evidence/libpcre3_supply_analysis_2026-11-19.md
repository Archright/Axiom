# libpcre3 공급 의존 분석 — 제거 불가 · 공급 복원력 (2026-11-19)

> **Status**: 관측 증거 동결(freeze). 본 문서는 코드·정책·워크플로를 변경하지 않는다 — 실측값만 기록한다.
> **Created**: 2026-11-19
> **Measured at**: 2026-11-19T14:19Z–14:24Z (UTC).
> **Base**: `aa0f78a8d2a6a070d1ff42ee3ead7d062c85d356` (origin/main, `Merge pull request #210`)
> **작업 트리**: `/tmp/Axiom-supply` (branch `vs/supply-policy`) — `bin/ax`는 트리에 없어 기존 클론에서 복사했다(§1.0).
> **재실행 주의**: §4의 네트워크 도달성과 §5의 다이제스트는 시점 스냅샷이다. 미러 가용성은 시점에 따라 달라진다(본 문서가 그 예를 §4에 기록한다).

## §0. 결론

`bin/ax`의 `libpcre3` 의존은 **제거할 수 없다.** 링크 시점 의존이 아니라 Nim `std/re`가 `libpcre.so.3`을 **런타임에 dlopen**하는 구조이므로, `readelf`의 DT_NEEDED에도 `ldd`에도 나타나지 않지만 실행 경로에서 반드시 로드된다(§1). `src/`에서 `std/re`를 import하는 파일은 **9개**다(§2).

그 의존을 공급하는 단일 지점은 `.github/actions/setup-axiom-toolchain/action.yml`의 apt 스텝이며, 2026-11-19 merge-group run `44519217624`·`44521587339`가 `security.ubuntu.com`의 `503 Service Unavailable`로 실패했다(§3). 같은 시각대에 Ubuntu 미러 계층만 응답하지 않았다(§4).

따라서 **의존은 유지하고 공급을 복원력 있게 만든다.** 신뢰 앵커는 미러가 아니라 **고정된 sha256**이다: `libpcre3_8.39-15build1_amd64.deb`의 권위 다이제스트는 `62b2ea8d178a59495df00b777660377e0fb8d716be3fc552439796f77f515d43`이며, official 호스트 7곳(독립 호스트 6곳)이 모두 같은 값을 반환했다(§5).

## §1. 의존의 형태 — link-time이 아니라 lazy dlopen

### §1.0 분석 대상 바이너리

새 워크트리에는 `bin/ax`가 없다(`bin/`에는 `.gitkeep`만 존재). 기존 클론의 빌드 산출물을 복사해 분석했다.

```console
$ cp <기존 클론>/bin/ax ./bin/ax
$ sha256sum bin/ax
136fc5c8fabbfcf0d47e0cb45e8e6c53a78bd1ed384184a5ebbad226427bad6d  bin/ax
$ stat -c '%s bytes' bin/ax
29106728 bytes
$ file bin/ax
bin/ax: ELF 64-bit LSB pie executable, x86-64, version 1 (SYSV), dynamically linked,
interpreter /lib64/ld-linux-x86-64.so.2, BuildID[sha1]=17e497207db36ba5bccdc4752399a3f32220cbdd,
for GNU/Linux 3.2.0, not stripped
```

`bin/`는 `.gitignore` 대상이므로 이 파일은 커밋에 포함되지 않는다(`git status --short` 출력 없음).

### §1.1 `readelf` — DT_NEEDED에 libpcre 없음

```console
$ readelf -d bin/ax | grep -E 'NEEDED|SONAME'
 0x0000000000000001 (NEEDED)             Shared library: [libm.so.6]
 0x0000000000000001 (NEEDED)             Shared library: [libc.so.6]

$ readelf -d bin/ax | wc -l
31
```

동적 섹션 31줄 전체에서 `NEEDED`는 2건뿐이다. `libpcre`는 링크 시점 의존이 **아니다**.

### §1.2 `strings` — dlopen 후보 이름이 바이너리에 존재

```console
$ strings -a bin/ax | grep libpcre | sort -u
@libpcre.so
@libpcre.so(.3|.1|)
@libpcre.so.1
@libpcre.so.3
```

네 문자열은 Nim의 `dynlib` 로더가 시도하는 후보 목록이다. `libpcre.so(.3|.1|)`는 Nim 런타임이 실패 시 출력하는 진단 문자열이며, §3의 CI 로그와 §1.5의 재현이 같은 문자열을 보여준다.

### §1.3 `ldd` — DT_NEEDED만 따라가므로 pcre가 보이지 않는다

```console
$ ldd bin/ax
	linux-vdso.so.1 (0x00007caf8fb5b000)
	libm.so.6 => /lib/x86_64-linux-gnu/libm.so.6 (0x00007caf8e300000)
	libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x00007caf8e000000)
	/lib64/ld-linux-x86-64.so.2 (0x00007caf8fb5d000)
```

`ldd`는 DT_NEEDED 엣지만 해석한다. pcre 항목이 없는 것은 **의존이 없다는 뜻이 아니라, 로더가 개입하지 않는 dlopen 대상이라는 뜻**이다. 이 구분이 본 문서의 핵심이다 — 정적 검사만으로는 이 의존을 볼 수 없다.

### §1.4 `strace` — 런타임에 실제로 연다

```console
$ strace -f -e trace=openat,open -o /tmp/ax.strace ./bin/ax --version
$ grep -i pcre /tmp/ax.strace
1942127 openat(AT_FDCWD, "/lib/x86_64-linux-gnu/libpcre.so.3", O_RDONLY|O_CLOEXEC) = 3
```

바이너리는 실행 중 `/lib/x86_64-linux-gnu/libpcre.so.3`을 연다. DT_NEEDED에 없는 파일을 런타임에 여는 것이 dlopen의 직접 증거다.

### §1.5 라이브러리 부재 재현 — CI 로그와 같은 문자열

개인 mount namespace에서 `libpcre.so.3`을 `/dev/null`로 덮어 로더가 읽을 수 없게 만들었다(호스트 파일시스템은 변경되지 않는다).

```console
$ unshare -rm bash -c 'mount --bind /dev/null /lib/x86_64-linux-gnu/libpcre.so.3 && ./bin/ax --version'
could not load: libpcre.so(.3|.1|)
(compile with -d:nimDebugDlOpen for more information)
exit=1
```

이 문자열은 §3의 CI 실패와 `action.yml` 주석이 인용하는 실패 형태(`could not load: libpcre.so(.3|.1|)` → ci-bootstrap exit 2)와 **동일**하다. 즉 라이브러리 부재는 곧 `bin/ax` 실행 불가다.

### §1.6 로컬 공급자 확인

```console
$ ls -l /lib/x86_64-linux-gnu/libpcre.so.3*
lrwxrwxrwx 1 root root     17  4월 19  2024 /lib/x86_64-linux-gnu/libpcre.so.3 -> libpcre.so.3.13.3
-rw-r--r-- 1 root root 485488  4월 19  2024 /lib/x86_64-linux-gnu/libpcre.so.3.13.3
$ dpkg -S /lib/x86_64-linux-gnu/libpcre.so.3
libpcre3:amd64: /lib/x86_64-linux-gnu/libpcre.so.3
```

`libpcre.so.3`을 소유한 패키지가 `libpcre3`이다 — 의존 대상 패키지 이름이 실측으로 확정된다.

## §2. 사용 범위 — `src/`의 `std/re` import 9개 파일

```console
$ grep -rlE --include='*.nim' '(from std/re|import std/re|import std/\[[^]]*\bre\b)' src/ | sort
src/cli/check_spec_cli.nim
src/core/topology/declaration.nim
src/gate/runners/debt_integrity_gate.nim
src/gate/runners/hermetic_test_gate.nim
src/mcp/tools.nim
src/personas/legislator.nim
src/verification/lean_axiom_extractor.nim
src/verification/lean_repl_bridge.nim
src/verification/observed_audit_contract.nim

$ ... | wc -l
9
```

`tests/`에는 0건이다.

### §2.1 "11개 파일"과의 불일치 — 원인 판정

배경 설명은 `std/re`가 11개 파일에서 쓰인다고 서술했으나, 본 문서의 실측은 **`src/` 9개**다. 불일치의 원인을 측정했다.

```console
$ grep -rl --include='*.nim' 'std/re' . | grep -vE '^\./(build|\.git)/' | wc -l
11
$ grep -rl --include='*.nim' 'std/re' . | grep -vE '^\./(build|\.git)/' | sort
./src/cli/check_spec_cli.nim
./src/gate/gate_utils.nim
./src/gate/nimtry/nimtry_extract_types.nim
./src/gate/runners/hermetic_test_gate.nim
./src/mcp/tools.nim
./src/verification/lean_axiom_extractor.nim
./tools/auto_convert_proc_to_func.nim
./tools/auto_insert_raises.nim
./tools/codeowners_coverage_gate.nim
./tools/move_and_stub.nim
./tools/proc_to_func_tester.nim
```

**11은 부분 문자열 일치 수다.** 내역은 다음과 같다:

| 파일 | `std/re` 일치의 실제 내용 | 실 import 여부 |
|---|---|---|
| `src/cli/check_spec_cli.nim` | `from std/re import ...` | 예 |
| `src/gate/runners/hermetic_test_gate.nim` | `import std/re` | 예 |
| `src/mcp/tools.nim` | `import std/re` | 예 |
| `src/verification/lean_axiom_extractor.nim` | `import std/re` | 예 |
| `src/gate/gate_utils.nim` | `std/results` (부분 문자열) | 아님 |
| `tools/codeowners_coverage_gate.nim` | 주석 문장 | 아님 |
| `tools/proc_to_func_tester.nim` | 주석 문장 | 아님 |
| `src/gate/nimtry/nimtry_extract_types.nim` | 문자열 목록의 `"std/re"` (동적 import) | 문자열 참조 |
| `tools/auto_convert_proc_to_func.nim` | `import std/re` | 예 |
| `tools/auto_insert_raises.nim` | `import std/re` | 예 |
| `tools/move_and_stub.nim` | `import std/re` | 예 |

즉 실제 `std/re` import는 repo 전체에서 **12개 파일**(`src/` 9 + `tools/` 3)이고, `bin/ax`에 링크되는 것은 `src/`의 9개다. 본 문서는 실측값 9를 사용한다.

## §3. 단일 실패점 — `setup-axiom-toolchain`의 apt 스텝

### §3.1 대상 스텝

`.github/actions/setup-axiom-toolchain/action.yml`의 `Install system deps (canonical system_deps parity — libpcre3)` 스텝. `ldconfig -p | grep 'libpcre\.so'`가 실패할 때만 apt를 호출하고, `||` 체인으로 update+install 폴백을 시도한 뒤 `ldconfig -p | grep 'libpcre\.so\.3'`로 단정한다(fail-closed).

즉 GitHub-hosted 러너처럼 libpcre3이 없는 환경에서는 **매 실행마다 외부 Ubuntu 미러에 의존**한다. 캐시가 데워진 dedicated 호스트에서는 no-op이다.

### §3.2 run `44519217624` / job `135547025260` (`verdict / admission-check`)

```console
$ gh api repos/Archright/Axiom/actions/runs/44519217624 --jq '{event,conclusion,head_sha,head_branch,created_at,updated_at}'
{"event":"merge_group","conclusion":"failure",
 "head_sha":"2ff9f58a8c9d97eeb8bcd25b1333dd9ec4f7fa34",
 "head_branch":"gh-readonly-queue/main/pr-211-aa0f78a8d2a6a070d1ff42ee3ead7d062c85d356",
 "created_at":"2026-11-19T11:56:04Z","updated_at":"2026-11-19T12:07:54Z"}
```

job은 `verdict / admission-check`, `started 12:03:36Z` → `completed 12:07:47Z`, `conclusion=failure`. ANSI 이스케이프를 제거한 로그 원문:

```console
$ gh run view --repo Archright/Axiom --job 135547025260 --log | perl -pe 's/\e\[[0-9;]*[A-Za-z]//g' | sed -E 's/^([^\t]*\t){2}//'
2026-11-19T12:03:48.0626257Z ldconfig -p | grep 'libpcre\.so\.3'
2026-11-19T12:04:59.9966540Z E: Failed to fetch https://security.ubuntu.com/ubuntu/pool/universe/p/pcre3/libpcre3_8.39-15build1_amd64.deb  503  Service Unavailable [IP: 52.15.107.13 80]
2026-11-19T12:04:59.9967280Z E: Unable to fetch some archives, maybe run apt-get update or try with --fix-missing?
2026-11-19T12:07:11.3020928Z W: Failed to fetch mirror+file:/etc/apt/apt-mirrors.txt/dists/noble/InRelease  503  Service Unavailable [IP: 52.15.159.198 80]
2026-11-19T12:07:11.3021785Z W: Failed to fetch mirror+file:/etc/apt/apt-mirrors.txt/dists/noble-updates/InRelease  503  Service Unavailable [IP: 52.15.159.198 80]
2026-11-19T12:07:11.3022499Z W: Failed to fetch mirror+file:/etc/apt/apt-mirrors.txt/dists/noble-backports/InRelease  503  Service Unavailable [IP: 52.15.159.198 80]
2026-11-19T12:07:11.3023093Z W: Failed to fetch mirror+file:/etc/apt/apt-mirrors.txt/dists/noble-security/InRelease  503  Service Unavailable [IP: 52.15.159.198 80]
2026-11-19T12:07:43.6787479Z E: Failed to fetch https://security.ubuntu.com/ubuntu/pool/universe/p/pcre3/libpcre3_8.39-15build1_amd64.deb  503  Service Unavailable [IP: 3.129.149.36 80]
2026-11-19T12:07:43.6788228Z E: Unable to fetch some archives, maybe run apt-get update or try with --fix-missing?
2026-11-19T12:07:43.6811570Z ##[error]Process completed with exit code 100.
2026-11-19T12:07:43.6998256Z ##[error]Process completed with exit code 1.
```

두 번의 시도(12:04:59Z, 12:07:43Z)에서 IP가 `52.15.107.13` → `3.129.149.36`으로 바뀌었으나 응답은 동일하게 `503`이다. 같은 503이 `noble`·`noble-updates`·`noble-backports`·`noble-security` **모든 InRelease**에 걸렸다 — 패키지 한 건의 문제가 아니라 미러 계층 전체의 문제다.

### §3.3 run `44521587339` / job `135551293518` (`attest / build-base-artifacts`)

```console
$ gh api repos/Archright/Axiom/actions/runs/44521587339 --jq '{event,conclusion,head_sha,head_branch,created_at,updated_at}'
{"event":"merge_group","conclusion":"failure",
 "head_sha":"807f38d9fec0e9747a53a5d8de7db843935e97ca",
 "head_branch":"gh-readonly-queue/main/pr-211-aa0f78a8d2a6a070d1ff42ee3ead7d062c85d356",
 "created_at":"2026-11-19T12:11:32Z","updated_at":"2026-11-19T12:24:17Z"}
```

job은 `attest / build-base-artifacts`, `started 12:11:34Z` → `completed 12:15:21Z`, `conclusion=failure`. 같은 스텝, 같은 실패:

```console
$ gh run view --repo Archright/Axiom --job 135551293518 --log | perl -pe 's/\e\[[0-9;]*[A-Za-z]//g' | sed -E 's/^([^\t]*\t){2}//'
2026-11-19T12:12:06.8590003Z ldconfig -p | grep 'libpcre\.so\.3'
2026-11-19T12:13:03.0486172Z E: Failed to fetch https://security.ubuntu.com/ubuntu/pool/universe/p/pcre3/libpcre3_8.39-15build1_amd64.deb  503  Service Unavailable [IP: 3.129.149.36 80]
2026-11-19T12:13:03.0486878Z E: Unable to fetch some archives, maybe run apt-get update or try with --fix-missing?
2026-11-19T12:14:25.1928485Z W: Failed to fetch mirror+file:/etc/apt/apt-mirrors.txt/dists/noble/InRelease  503  Service Unavailable [IP: 52.15.158.54 80]
2026-11-19T12:14:25.1929508Z W: Failed to fetch mirror+file:/etc/apt/apt-mirrors.txt/dists/noble-updates/InRelease  503  Service Unavailable [IP: 52.15.158.54 80]
2026-11-19T12:14:25.1930506Z W: Failed to fetch mirror+file:/etc/apt/apt-mirrors.txt/dists/noble-backports/InRelease  503  Service Unavailable [IP: 52.15.158.54 80]
2026-11-19T12:14:25.1931592Z W: Failed to fetch mirror+file:/etc/apt/apt-mirrors.txt/dists/noble-security/InRelease  503  Service Unavailable [IP: 52.15.158.54 80]
2026-11-19T12:15:20.0624195Z E: Failed to fetch https://security.ubuntu.com/ubuntu/pool/universe/p/pcre3/libpcre3_8.39-15build1_amd64.deb  503  Service Unavailable [IP: 52.15.159.198 80]
2026-11-19T12:15:20.0624988Z E: Unable to fetch some archives, maybe run apt-get update or try with --fix-missing?
2026-11-19T12:15:20.0649408Z ##[error]Process completed with exit code 100.
```

이 run은 `attest / go-critical-lane (0/1)`, `attest / admission-independents`, `attest / admission-check`, `mint-prepare / prepare`, `mint-publish / publish`, `verdict / admission-check`까지 **연쇄 실패**했다 — 스텝 하나가 스테이지 전체를 세운다.

### §3.4 두 run이 공통으로 말하는 것

- 실패 지점은 `bin/ax`를 실행하기 **전**, 러너 프로비저닝 단계다. 즉 제품 코드 실패가 아니라 **공급 실패**다.
- 미러가 503을 반환하는 동안 apt는 `--fix-missing` 없이는 진행하지 못하고 exit 100으로 죽는다.
- 실패한 다운로드 URL이 정확히 `libpcre3_8.39-15build1_amd64.deb` — **패키지 신원이 로그로 확정된다.**

## §4. 네트워크 관측 — 미러 계층만 응답하지 않았다

### §4.1 선행 관측 (2026-11-19T12:25Z — 세션 내 확립, 본 문서에서 재실행하지 않음)

`security.ubuntu.com`과 `archive.ubuntu.com`이 도달 불가였고, `github.com`·`pypi.org`·`de.archive.ubuntu.com`은 HTTP 200을 반환했다. 이 관측은 본 문서 작성 시점에 **재현되지 않았다**(§4.2). 본 문서는 이 값을 재측정값으로 제시하지 않으며, 당시의 상태 서술로만 인용한다. §3의 GitHub Actions 로그(같은 시각대)가 `security.ubuntu.com` 503을 독립적으로 뒷받침한다.

### §4.2 본 문서의 재측정 (2026-11-19T14:19:53Z)

```console
$ date -u +%Y-%m-%dT%H:%M:%SZ
2026-11-19T14:19:53Z
$ for u in https://security.ubuntu.com/ubuntu/dists/noble/InRelease \
           http://archive.ubuntu.com/ubuntu/dists/noble/InRelease \
           https://de.archive.ubuntu.com/ubuntu/dists/noble/InRelease \
           https://github.com https://pypi.org; do
    printf '%-4s %s\n' "$(curl -sS -o /dev/null -m 20 -w '%{http_code}' "$u")" "$u"
  done
200  https://security.ubuntu.com/ubuntu/dists/noble/InRelease
200  http://archive.ubuntu.com/ubuntu/dists/noble/InRelease
000  https://de.archive.ubuntu.com/ubuntu/dists/noble/InRelease
200  https://github.com
200  https://pypi.org
```

| 호스트 | 12:25Z (선행 관측) | 14:19Z (본 문서 재측정) |
|---|---|---|
| `security.ubuntu.com` | 도달 불가 | **200** |
| `archive.ubuntu.com` | 도달 불가 | **200** |
| `de.archive.ubuntu.com` | 200 | **000** (HTTPS) / 200 (HTTP) |
| `github.com` | 200 | 200 |
| `pypi.org` | 200 | 200 |

**시점에 따라 장애 위치가 이동한다.** 12:25Z에는 archive 계열이, 14:19Z에는 독일 미러의 443이 막혔다. `de.archive.ubuntu.com`의 443 실패는 DNS가 아니라 TCP 연결 단계다:

```console
$ curl -sS -o /dev/null -m 20 -w '%{http_code}' https://de.archive.ubuntu.com/ubuntu/dists/noble/InRelease
curl: (7) Failed to connect to de.archive.ubuntu.com port 443 after 1512 ms: Couldn't connect to server
000
$ curl -sS -o /dev/null -m 20 -w '%{http_code}' http://de.archive.ubuntu.com/ubuntu/dists/noble/InRelease
200
```

### §4.3 해석 — 단일 미러는 신뢰 앵커가 될 수 없다

두 시점의 사실을 합치면 결론은 하나다: **어느 미러도 상시 가용하지 않다.** 따라서 공급 설계는 (a) 여러 official 호스트를 순서대로 시도하고, (b) 성공한 바이트를 **미러와 무관한 고정 다이제스트**로 검증해야 한다. 미러 목록은 가용성 장치이고, 신뢰는 다이제스트에만 둔다.

`archive.ubuntu.com`과 `security.ubuntu.com`은 **같은 CDN을 공유**한다 — 독립 소스로 세지 않는다:

```console
$ for h in archive.ubuntu.com security.ubuntu.com de.archive.ubuntu.com us.archive.ubuntu.com; do
    printf '%-24s %s\n' "$h" "$(getent ahostsv4 $h | awk '{print $1}' | sort -u | tr '\n' ' ')"
  done
archive.ubuntu.com       104.20.28.246 172.66.152.176
security.ubuntu.com      104.20.28.246 172.66.152.176
de.archive.ubuntu.com    141.30.62.22 141.30.62.23 141.30.62.24 141.30.62.25 141.30.62.26
us.archive.ubuntu.com    91.189.91.81 91.189.91.82 91.189.91.83
```

## §5. 공급 다이제스트 권위

전체 획득·검증 절차와 원문 출력은 동일 디렉터리의 `docs/evidence/supply_policy_registration_2026-11-19.md`에 있다. 요약:

| 항목 | 값 |
|---|---|
| 패키지 | `libpcre3` |
| 버전 (파일명·풀) | `8.39-15build1` |
| 버전 (control, epoch 포함) | `2:8.39-15build1` |
| 아키텍처 | `amd64` |
| 컴포넌트 / suite | `universe` / `noble` |
| 파일 크기 | `248274` bytes |
| **sha256** | `62b2ea8d178a59495df00b777660377e0fb8d716be3fc552439796f77f515d43` |
| 일치 소스 수 | 7 (official 호스트, 독립 호스트 6) |

이 값은 공급 핀의 권위 값이며, 변경은 trust-surface 변경 절차를 따른다.

`noble/universe` 인덱스도 같은 다이제스트를 담고 있다 — 이는 다이제스트를 suite·component 신원에 결속한다:

```console
$ gunzip -c Packages.gz | sed -n '778775,778795p'
Package: libpcre3
Architecture: amd64
Version: 2:8.39-15build1
Multi-Arch: same
Priority: optional
Section: universe/libs
Source: pcre3
...
Filename: pool/universe/p/pcre3/libpcre3_8.39-15build1_amd64.deb
Size: 248274
MD5sum: 3ea0e5580fb2138344b177295ab38587
SHA1: 91357a696877527a1b731c876813c3372bae427c
SHA256: 62b2ea8d178a59495df00b777660377e0fb8d716be3fc552439796f77f515d43
```

## §6. 결론

1. **의존은 제거할 수 없다.** `bin/ax`는 DT_NEEDED에 pcre를 나열하지 않지만(`readelf`), 실행 중 `libpcre.so.3`을 dlopen한다(`strace`). 부재 시 `could not load: libpcre.so(.3|.1|)`로 실행이 중단된다. 링크 시점 검사(`ldd`)로는 이 의존을 볼 수 없으므로 "의존 없음"으로 오판하기 쉽다.
2. **사용 범위는 좁지만 우회 불가다.** `src/`의 9개 파일이 `std/re`를 import하고, 그 코드가 `bin/ax`에 링크된다. regex 사용을 전면 제거하지 않는 한 의존은 남는다.
3. **공급은 단일 지점이다.** libpcre3이 없는 러너에서 `setup-axiom-toolchain`의 apt 스텝이 유일한 공급자이며, 2026-11-19 두 merge-group run이 그 지점에서 실패했다.
4. **공급은 복원력 있게 만들어야 한다.** 미러 가용성은 시점에 따라 이동한다(§4). 다중 official 소스 순차 시도 + 실패 시 fail-closed가 필요하다.
5. **신뢰 앵커는 미러가 아니라 고정 sha256이다.** 미러는 바이트를 나를 뿐이고, 신뢰는 `62b2ea8d…`와의 일치 여부로만 판정한다. 미러가 침해되어도 다이제스트가 다르면 설치되지 않는다.

## §7. 재현 명령

```console
# §1 — 의존의 형태
cp <기존 클론>/bin/ax ./bin/ax && sha256sum bin/ax
readelf -d bin/ax | grep -E 'NEEDED|SONAME'
strings -a bin/ax | grep libpcre | sort -u
ldd bin/ax
strace -f -e trace=openat,open -o /tmp/ax.strace ./bin/ax --version && grep -i pcre /tmp/ax.strace
unshare -rm bash -c 'mount --bind /dev/null /lib/x86_64-linux-gnu/libpcre.so.3 && ./bin/ax --version'
dpkg -S /lib/x86_64-linux-gnu/libpcre.so.3

# §2 — 사용 범위
grep -rlE --include='*.nim' '(from std/re|import std/re|import std/\[[^]]*\bre\b)' src/ | sort
grep -rl --include='*.nim' 'std/re' . | grep -vE '^\./(build|\.git)/' | sort

# §3 — 실패 로그
gh api repos/Archright/Axiom/actions/runs/44519217624
gh api repos/Archright/Axiom/actions/runs/44519217624/jobs --paginate
gh run view --repo Archright/Axiom --job 135547025260 --log | perl -pe 's/\e\[[0-9;]*[A-Za-z]//g'
gh run view --repo Archright/Axiom --job 135551293518 --log | perl -pe 's/\e\[[0-9;]*[A-Za-z]//g'

# §4 — 도달성 (시점 스냅샷)
for u in https://security.ubuntu.com/ubuntu/dists/noble/InRelease \
         http://archive.ubuntu.com/ubuntu/dists/noble/InRelease \
         https://de.archive.ubuntu.com/ubuntu/dists/noble/InRelease \
         https://github.com https://pypi.org; do
  printf '%-4s %s\n' "$(curl -sS -o /dev/null -m 20 -w '%{http_code}' "$u")" "$u"
done
for h in archive.ubuntu.com security.ubuntu.com de.archive.ubuntu.com us.archive.ubuntu.com; do
  printf '%-24s %s\n' "$h" "$(getent ahostsv4 $h | awk '{print $1}' | sort -u | tr '\n' ' ')"
done

# §5 — 다이제스트
curl -fSL -o libpcre3_8.39-15build1_amd64.deb \
  http://de.archive.ubuntu.com/ubuntu/pool/universe/p/pcre3/libpcre3_8.39-15build1_amd64.deb
sha256sum libpcre3_8.39-15build1_amd64.deb
dpkg-deb -I libpcre3_8.39-15build1_amd64.deb
curl -fSL -o Packages.gz http://de.archive.ubuntu.com/ubuntu/dists/noble/universe/binary-amd64/Packages.gz
gunzip -c Packages.gz | grep -A20 '^Package: libpcre3$'
```