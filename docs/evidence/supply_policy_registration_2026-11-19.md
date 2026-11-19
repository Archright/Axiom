# 공급 정책 등록 — libpcre3 (2026-11-19)

> **Status**: 정책 등록(policy registration). 본 문서는 **정책 값과 그 권위를 기록**하며, 실행 경로를 변경하지 않는다.
> **Created**: 2026-11-19
> **Measured at**: 2026-11-19T14:20:27Z–14:20:50Z (UTC) — 다이제스트 획득·검증 시각.
> **Base**: `aa0f78a8d2a6a070d1ff42ee3ead7d062c85d356` (origin/main)
> **선행 증거**: `docs/evidence/libpcre3_supply_analysis_2026-11-19.md` — 의존의 형태(dlopen)·사용 범위·실패 로그.

## §0. 이 문서가 등록하는 것

`bin/ax`의 `libpcre3` 런타임 의존을 공급하기 위한 **패키지 신원·신뢰 앵커·실패 시맨틱**을 고정한다. 실행 경로(워크플로·액션·설치 스크립트)는 본 문서의 범위 밖이며, 본 문서는 어떤 실행 표면도 변경하지 않는다.

## §1. 정책 값

```yaml
package: libpcre3
version: 8.39-15build1
architecture: amd64
component: universe
suite: noble
sha256: 62b2ea8d178a59495df00b777660377e0fb8d716be3fc552439796f77f515d43
sources_ordered:
  - http://de.archive.ubuntu.com/ubuntu/pool/universe/p/pcre3/libpcre3_8.39-15build1_amd64.deb
  - https://archive.ubuntu.com/ubuntu/pool/universe/p/pcre3/libpcre3_8.39-15build1_amd64.deb
retry: {attempts: 2, backoff_s: 5, connect_timeout_s: 15}
on_all_sources_failed: exit 1, message begins "external_dependency: libpcre3 unavailable"
forbidden: [--allow-unauthenticated, --fix-missing, unsigned dpkg -i, unversioned install, third-party mirror]
```

### §1.1 소스 순서와 scheme에 대한 사실 기록

- **1순위 `de.archive.ubuntu.com`은 `http`로 등록했다.** 측정 호스트에서 이 호스트의 443은 TCP 연결 단계에서 실패했고(`curl (7) ... port 443 ... Couldn't connect to server`), 80은 200이었다(선행 문서 §4.2). 등록 URL은 **실제로 200을 관측한 scheme**과 일치시켰다. 확인하지 않은 `https` URL을 등록하지 않는다.
- **2순위 `archive.ubuntu.com`은 `https`로 등록했다.** 200을 관측했다.
- 전송 계층 보안은 신뢰 앵커가 **아니다**. 신뢰는 §2의 sha256 일치로만 판정한다. 따라서 `http` 소스의 존재가 신뢰를 낮추지 않는다 — 변조된 바이트는 다이제스트 불일치로 설치되지 않는다.
- `security.ubuntu.com`은 `archive.ubuntu.com`과 **같은 CDN**(동일 A 레코드 `104.20.28.246`, `172.66.152.176`)이므로 독립 소스로 세지 않았다.

## §2. 신뢰 앵커 — sha256

```
62b2ea8d178a59495df00b777660377e0fb8d716be3fc552439796f77f515d43
```

이 값은 공급 핀의 권위 값이며, 변경은 trust-surface 변경 절차를 따른다.

### §2.1 획득 — official 호스트 7곳, 전부 동일

모든 파일은 `curl -fSL`로 `pool/universe/p/pcre3/libpcre3_8.39-15build1_amd64.deb`에서 직접 받았다.

| # | URL | HTTP | bytes | sha256 | 획득 시각 (UTC) |
|---|---|---|---|---|---|
| 1 | `http://de.archive.ubuntu.com/ubuntu/pool/universe/p/pcre3/libpcre3_8.39-15build1_amd64.deb` | 200 | 248274 | `62b2ea8d…5d43` | 2026-11-19T14:20:27Z |
| 2 | `http://archive.ubuntu.com/ubuntu/pool/universe/p/pcre3/libpcre3_8.39-15build1_amd64.deb` | 200 | 248274 | `62b2ea8d…5d43` | 2026-11-19T14:20:27Z |
| 3 | `https://security.ubuntu.com/ubuntu/pool/universe/p/pcre3/libpcre3_8.39-15build1_amd64.deb` | 200 | 248274 | `62b2ea8d…5d43` | 2026-11-19T14:20:29Z |
| 4 | `http://fr.archive.ubuntu.com/ubuntu/pool/universe/p/pcre3/libpcre3_8.39-15build1_amd64.deb` | 200 | 248274 | `62b2ea8d…5d43` | 2026-11-19T14:20:50Z |
| 5 | `http://us.archive.ubuntu.com/ubuntu/pool/universe/p/pcre3/libpcre3_8.39-15build1_amd64.deb` | 200 | 248274 | `62b2ea8d…5d43` | 2026-11-19T14:20:50Z |
| 6 | `http://nl.archive.ubuntu.com/ubuntu/pool/universe/p/pcre3/libpcre3_8.39-15build1_amd64.deb` | 200 | 248274 | `62b2ea8d…5d43` | 2026-11-19T14:20:50Z |
| 7 | `http://ftp.ubuntu.com/ubuntu/pool/universe/p/pcre3/libpcre3_8.39-15build1_amd64.deb` | 200 | 248274 | `62b2ea8d…5d43` | 2026-11-19T14:20:50Z |

**불일치 0건.** 모든 소스가 같은 sha256을 반환했으므로 §2의 값이 권위 값이다. 불일치가 있었다면 본 문서는 값을 선택하지 않고 중단·보고했을 것이다.

원문 출력:

```console
$ sha256sum *.deb | sort
62b2ea8d178a59495df00b777660377e0fb8d716be3fc552439796f77f515d43  fr.archive.ubuntu.com_libpcre3.deb
62b2ea8d178a59495df00b777660377e0fb8d716be3fc552439796f77f515d43  ftp.ubuntu.com_libpcre3.deb
62b2ea8d178a59495df00b777660377e0fb8d716be3fc552439796f77f515d43  libpcre3_8.39-15build1_amd64.deb
62b2ea8d178a59495df00b777660377e0fb8d716be3fc552439796f77f515d43  nl.archive.ubuntu.com_libpcre3.deb
62b2ea8d178a59495df00b777660377e0fb8d716be3fc552439796f77f515d43  us.archive.ubuntu.com_libpcre3.deb
```

### §2.2 독립성 — 호스트 주소로 확인

```console
$ for h in archive.ubuntu.com security.ubuntu.com de.archive.ubuntu.com us.archive.ubuntu.com; do
    printf '%-24s %s\n' "$h" "$(getent ahostsv4 $h | awk '{print $1}' | sort -u | tr '\n' ' ')"
  done
archive.ubuntu.com       104.20.28.246 172.66.152.176
security.ubuntu.com      104.20.28.246 172.66.152.176
de.archive.ubuntu.com    141.30.62.22 141.30.62.23 141.30.62.24 141.30.62.25 141.30.62.26
us.archive.ubuntu.com    91.189.91.81 91.189.91.82 91.189.91.83
```

정책의 두 소스는 **서로 다른 호스트**다: `de.archive.ubuntu.com`(141.30.62.0/24)과 `archive.ubuntu.com`(Cloudflare). 7개 확인 소스 중 독립 호스트는 6개다(`de`, `fr`, `us`, `nl`, `ftp`, `archive`).

### §2.3 패키지 신원 검증 — `dpkg-deb -I`

```console
$ dpkg-deb -I libpcre3_8.39-15build1_amd64.deb
 new Debian package, version 2.0.
 size 248274 bytes: control archive=1411 bytes.
     876 bytes,    21 lines      control
     637 bytes,     9 lines      md5sums
     156 bytes,     4 lines      shlibs
    1125 bytes,    39 lines      symbols
      75 bytes,     2 lines      triggers
 Package: libpcre3
 Source: pcre3
 Version: 2:8.39-15build1
 Architecture: amd64
 Maintainer: Ubuntu Developers <ubuntu-devel-discuss@lists.ubuntu.com>
 Installed-Size: 682
 Depends: libc6 (>= 2.34)
 Conflicts: libpcre3-dev (<= 4.3-3)
 Breaks: approx (<< 4.4-1~), cduce (<< 0.5.3-2~), cmigrep (<< 1.5-7~), galax (<< 1.1-7~), libpcre-ocaml (<< 6.0.1~), liquidsoap (<< 0.9.2-3~), ocsigen (<< 1.3.3-1~)
 Section: libs
 Priority: optional
 Multi-Arch: same
 Description: Old Perl 5 Compatible Regular Expression Library - runtime files
  This is a library of functions to support regular expressions whose syntax
  and semantics are as close as possible to those of the Perl 5 language.
  .
  New packages should use the newer pcre2 packages, and existing
  packages should migrate to pcre2.
  .
  This package contains the runtime libraries.
 Original-Maintainer: Matthew Vernon <matthew@debian.org>
```

**에포크 표기**: control의 `Version`은 `2:8.39-15build1`이고, 파일명·풀 경로의 버전은 `8.39-15build1`이다(Debian 규약상 에포크는 파일명에 들어가지 않는다). 정책의 `version: 8.39-15build1`은 **파일명·풀 버전**을 지칭하며, apt pin `libpcre3=8.39-15build1`은 에포크 없는 표기로 그대로 매칭된다.

### §2.4 suite·component 결속 — 인덱스가 같은 다이제스트를 담는다

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

`Section: universe/libs` + `Filename: pool/universe/...`가 component `universe`를, 인덱스 경로 `dists/noble/universe/binary-amd64/Packages.gz`가 suite `noble`을 확정한다. `Size: 248274`는 §2.1의 실측 크기와 일치한다.

### §2.5 검증하지 않은 것 — `noble-security` pocket

본 문서는 **`noble-security` pocket에 대한 미러 allowlist를 검증하지 않았다.** 관측한 것은 `noble`(release pocket)의 `universe/binary-amd64` 인덱스와 그 풀 파일뿐이다. `noble-security`·`noble-updates`에 동일 버전이 존재하는지, 어떤 호스트가 서빙하는지는 본 문서의 주장 범위 밖이다.

## §3. 실패 시맨틱

### §3.1 재시도

```yaml
retry: {attempts: 2, backoff_s: 5, connect_timeout_s: 15}
```

소스당 시도 횟수 2, 재시도 간 5초, 연결 타임아웃 15초. 2026-11-19의 실패는 `503`이 수 분간 지속되는 형태였으므로(선행 문서 §3.2–§3.3) 짧은 백오프 1회로는 회복되지 않는다 — 재시도의 목적은 **일시적 5xx·연결 실패를 흡수**하는 것이고, 지속 장애는 다음 소스로 넘어가는 것이 설계 의도다.

### §3.2 전 소스 실패

```yaml
on_all_sources_failed: exit 1, message begins "external_dependency: libpcre3 unavailable"
```

- **exit 1** — 성공으로 위장하지 않는다. `--fix-missing`으로 넘기는 경로가 없으므로 "설치된 척"이 발생할 수 없다.
- 메시지 접두사 `external_dependency: libpcre3 unavailable` — 실패 클래스를 **외부 공급**으로 분류해, 코드 결함·게이트 실패와 구별한다.
- 이 시맨틱은 fail-closed다. 라이브러리 없이 `bin/ax`를 실행하면 선행 문서 §1.5의 `could not load: libpcre.so(.3|.1|)`로 어차피 실패하므로, 조기·명시적 실패가 진단 비용을 낮춘다.

### §3.3 금지 목록

| 금지 항목 | 이유 |
|---|---|
| `--allow-unauthenticated` | 서명 검증을 끄는 것은 신뢰 앵커 제거다. 다이제스트 핀이 있어도 금지한다. |
| `--fix-missing` | 누락 패키지를 조용히 건너뛰어 **부분 설치를 성공처럼** 만든다 — 극장 경로다. |
| unsigned `dpkg -i` | 저장소 서명·다이제스트 검증 경로를 우회한다. |
| unversioned install | `libpcre3` 무버전 설치는 미래 버전으로 표류한다. `8.39-15build1` 고정을 깬다. |
| third-party mirror | official Ubuntu 호스트가 아닌 미러는 신뢰 경계 밖이다. |

## §4. 권위

### §4.1 승인 주체

- **승인자**: 인간 아키텍트.
- **승인 경로**: 본 세션의 **상시 포괄 승인(standing blanket authorization)**. 별도 서명·티켓 없이, 본 세션에서 부여된 권한 범위 안에서 본 정책 값을 승인된 것으로 등록한다.
- **등록자**: 에이전트(서브에이전트). 에이전트는 값을 **측정·기록**했으며, 값을 임의로 선택하지 않았다 — 7개 소스가 모두 같은 sha256을 반환한 사실이 값의 근거다.

### §4.2 재승인이 필요한 변경

다음 중 **하나라도** 바뀌면 본 등록은 효력을 잃고 재승인이 필요하다:

- `package` (다른 패키지로 교체)
- `version` (다른 버전 — 에포크 포함 표기 변경 포함)
- `architecture` (amd64 이외)
- `sha256` (다이제스트 변경 — 업스트림 재빌드·미러 변조·핀 오류를 모두 포함)

재승인은 **trust-surface 변경 절차**를 따른다. 즉 새 다이제스트를 독립 소스 2곳 이상에서 재획득·교차 검증하고, 본 문서를 갱신한 뒤, 실행 표면 변경은 별도 PR로 분리한다.

### §4.3 재승인이 필요 없는 변경

- `sources_ordered`의 **순서** 변경, official 호스트의 추가/제거 — 단, official Ubuntu 호스트만 허용한다(§3.3의 third-party 금지 유지).
- `retry` 파라미터 조정 — 실패 시맨틱(exit 1, 메시지 접두사)이 유지되는 한 운영 파라미터다.
- 본 문서가 다루지 않는 실행 표면의 변경 — 별도 PR·별도 승인 절차를 따른다.

## §5. 이 문서가 하지 않는 것

- 실행 경로(워크플로·액션·설치 스크립트)를 **변경하지 않는다**. 본 문서는 정책 등록과 증거뿐이다.
- `.github/**`, `config/policy/**`를 **수정하지 않는다**.
- 릴리스 자산을 만들거나 업로드하지 않는다.
- `noble-security` pocket의 allowlist를 검증했다고 **주장하지 않는다**(§2.5).