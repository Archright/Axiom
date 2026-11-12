# Fish Shell Hostname 사용 보안 감사 보고서

**감사 일시**: 2026-06-21  
**감사 대상**: Fish Shell — hostname 관련 코드 패턴 전수조사  
**위험 수준**: 🟡 중간 (즉시 조치 필요 항목 존재)

---

## 0. 감사 환경

| 항목 | 상태 |
|------|------|
| Fish Shell 설치 여부 | ❌ 미설치 (vestigial config만 존재) |
| 시스템 함수 파일 | `/usr/share/fish/functions/` — 존재하지 않음 |
| 사용자 설정 | `~/.config/fish/conf.d/uv.env.fish` 1개 파일만 존재 |
| 감사 방법론 | 소스 코드 grep 기반 정적 분석 (fish 4.x 기준) |

> **참고**: Fish shell 바이너리가 현재 시스템에 설치되어 있지 않으므로, 본 감사는 fish 소스 코드의 grep 결과를 기반으로 한 정적 코드 분석입니다. 향후 fish 설치 시 적용 가능한 보안 평가입니다.

---

## 1. 🎯 해성 타겟 (Hostile Target) — `__fish_print_hostnames`

### 1.1 함수 정의 위치

| 파일 | 라인 | 함수명 |
|------|------|--------|
| `print_hostnames.fish` | L82 | `__fish_print_hostnames` |

### 1.2 함수 동작 메커니즘

```fish
function __fish_print_hostnames -d "Print a list of known hostnames"
    # ... (L82부터)
    # 1. /etc/hosts에서 hostname 파싱
    # 2. ssh_config에서 Host/HostName 값 추출
    # 3. known_hosts에서 hostname 추출
    # 4. SSH config Include 디렉토리 재귀 탐색
end
```

**수집 소스**:
- `/etc/hosts` 파일의 hostname 항목
- `~/.ssh/config` 및 Include 경로의 `Host`, `HostName` 지시자
- `~/.ssh/known_hosts`의 hostname 필드

### 1.3 소비자 (Consumers) — 이 함수를 호출하는 곳

| 소비자 파일 | 라인 | 호출 컨텍스트 | 위험도 |
|------------|------|-------------|--------|
| `ssh.fish` | L2 | `complete -c ssh -xa '(__fish_print_hostnames)'` | 🟡 중간 |
| `scp.fish` | L12 | `complete -c scp -xa '(__fish_print_hostnames)'` | 🟡 중간 |
| `sftp.fish` | L4 | `complete -c sftp -xa '(__fish_print_hostnames)'` | 🟡 중간 |
| `ssh-cocli.fish` | L2 | `complete -c ssh-cocli -xa '(__fish_print_hostnames)'` | 🟡 중간 |
| `duply.fish` | L133 | `duply profile ... ssh_targets ... (__fish_print_hostnames)` | 🟢 낮음 |
| `sv.fish` | L47 | `complete ... -a '(__fish_print_hostnames)'` (service 명령어) | 🟢 낮음 |
| `svk.fish` | L4 | `complete -c svk ... -a '(__fish_print_hostnames)'` | 🟢 낮음 |

### 1.4 위험 평가

**핵심 위험**: `__fish_print_hostnames`는 시스템의 모든 알려진 hostname을 자동완성 후보로 노출합니다. 이 함수가 호출되면:

1. **정보 수집 경로**: `/etc/hosts`, `~/.ssh/config`, `~/.ssh/known_hosts`에서 hostname을 읽음
2. **출력 대상**: Fish 자동완성 시스템 → 사용자에게 표시
3. **보안 의미**: SSH 관련 자동완성에 사용되므로, 탭 완성 시 내부 네트워크 hostname이 화면에 노출될 수 있음

**실제 위험도**: 🟡 중간
- 자동완성은 로컬 터미널에서만 동작 (네트워크 전송 없음)
- 하지만 `/etc/hosts`에 내부 IP↔hostname 매핑이 있으면, 탭 완성 시 내부 네트워크 구조가 시각적으로 노출됨
- SSH config에 민감한 호스트명이 있으면 노출됨

---

## 2. 🔴 Command Injection 패턴 (3건)

### 2.1 `alias.fish` — `eval` 사용

| 항목 | 값 |
|------|---|
| **파일** | `alias.fish` |
| **라인** | L39 |
| **코드** | `eval "$alias_definition"` |
| **오염원** | `set -l alias_definition "function $wrappers..."` (L20-22에서 `$argv` 기반 생성) |
| **심각도** | 🔴 높음 |

**분석**: 
- `$argv` → `$name` (L6) → `$wrappers` (L20) → `$alias_definition` (L22) → `eval` (L39)
- 사용자가 `alias` 명령어에 전달한 인자가 `eval`을 통해 실행됨
- **의도적 설계**: alias의 본질적 기능 — 사용자 입력을 함수로 등록
- **보안 우려**: `alias 'harmless; rm -rf /'` 같은 입력이 가능할 수 있음
- **완화 요인**: Fish의 `eval`은 bash보다 안전한 quoting 메커니즘을 사용하며, `$alias_definition`은 문자열 리터럴로 구성됨

### 2.2 `fish_clipboard_paste.fish` — `eval` 사용

| 항목 | 값 |
|------|---|
| **파일** | `fish_clipboard_paste.fish` |
| **라인** | L53 |
| **코드** | `eval "$__fish_paste_quoted"` |
| **오염원** | 시스템 클립보드 데이터 (L21: `fish_clipboard_copy`) |
| **심각도** | 🔴 높음 |

**분석**:
- 클립보드 데이터 → `$__fish_paste_quoted` → `eval`
- **위험 시나리오**: 악의적인 웹사이트가 클립보드에 명령어를 주입하면, 붙여넣기 시 실행될 수 있음
- **완화 요인**: L20에서 `commandline -i`로 먼저 시도하고, 실패 시에만 `eval` 사용 (L28-29 분기)

### 2.3 `fish_git_prompt.fish` — `eval` 사용

| 항목 | 값 |
|------|---|
| **파일** | `fish_git_prompt.fish` |
| **라인** | L527 |
| **코드** | `eval set previous \$upstream` |
| **오염원** | Git upstream 브랜치명 (L468-474에서 `command git rev-parse --abbrev-ref` 등으로 추출) |
| **심각도** | 🟡 중간 |

**분석**:
- Git upstream 브랜치명 → `$upstream` → `eval set previous \$upstream`
- **위험 시나리오**: 악의적인 git 리포지토리의 브랜치명에 shell 명령어가 포함된 경우
- **완화 요인**: `eval`은 변수 간접 참조 목적으로만 사용됨 (`\$upstream` 형태)

---

## 3. 📤 출력/데이터 오염 패턴 (15건)

### 3.1 stdout으로 직접 출력되는 hostname 데이터

| 파일 | 라인 | 출력 방식 | 오염 가능 데이터 |
|------|------|---------|----------------|
| `prompt_login.fish` | L25 | `echo $hostname` | **시스템 hostname 직접 출력** → 프롬프트에 표시 |
| `fish_git_prompt.fish` | L132 | `echo $___fish_git_prompt_showdirtystate` | git 설정값 |
| `fish_git_prompt.fish` | L164 | `echo $___fish_git_prompt_showuntrackedfiles` | git 설정값 |
| `fish_git_prompt.fish` | L196 | `echo $___fish_git_prompt_showstashstate` | git 설정값 |
| `fish_git_prompt.fish` | L233 | `echo $___fish_git_prompt_status_separator` | 구분자 문자열 |
| `fish_git_prompt.fish` | L317 | `printf '%s' $color_flags_normal` | ANSI 색상 코드 |
| `fish_git_prompt.fish` | L519 | `printf '%s' $current_upstream` | **Git upstream 브랜치명** |
| `type.fish` | L59 | `builtin status features` | Fish 기능 플래그 |
| `umask.fish` | L26 | `$as_binary[(...)]` | 파일 권한 비트 |
| `status.fish` | L26 | `builtin status filename` | **현재 스크립트 파일명** |
| `status.fish` | L28 | `echo $hostname` | **시스템 hostname** |
| `status.fish` | L31 | `builtin status login-shell` | 셸 로그인 여부 |
| `status.fish` | L36 | `builtin status features` | 기능 플래그 |
| `status.fish` | L58 | `$as_binary[(...)]` | 파일 권한 비트 |
| `umask.fish` | L14 | `$octal[(...)]` | umask 값 |

### 3.2 가장 민감한 출력 경로

#### 🔴 `prompt_login.fish` L25: `echo $hostname`
- **용도**: 로그인 프롬프트에 hostname 표시
- **오염 경로**: `hostname` 전역 변수 → stdout → 터미널 프롬프트
- **보안 영향**: 모든 새 터미널 세션에서 hostname이 화면에 표시됨
- **스크린샷/로그 노출 시**: 시스템 hostname이 외부에 유출될 수 있음

#### 🔴 `status.fish` L28: `echo $hostname`
- **용도**: `status` 명령어 출력
- **보안 영향**: 사용자가 `status` 실행 시 hostname이 출력됨

#### 🟡 `fish_git_prompt.fish` L519: `printf '%s' $current_upstream`
- **용도**: git 프롬프트에 upstream 브랜치명 표시
- **보안 영향**: git upstream 이름이 프롬프트에 노출됨

---

## 4. 🔐 프롬프트/로그 민감 패턴 (2건)

### 4.1 `prompt_login.fish` — hostname + username 프롬프트 노출

| 항목 | 값 |
|------|---|
| **파일** | `prompt_login.fish` |
| **라인** | L24-25 |
| **코드** | `prompt_login -u` (user) + `echo $hostname` |
| **민감도** | 시스템 hostname과 username이 프롬프트에 표시됨 |

**보안 영향**:
- 모든 터미널 세션에서 `user@hostname` 형태로 표시
- 스크린샷, 화면 공유, 로그 캡처 시 시스템 식별 정보 유출
- SSH 세션에서는 원격 호스트 hostname이 노출됨

### 4.2 `fish_git_prompt.fish` L470-475 — GIT_DIR 전역 export

```fish
# L470-475
if set -q GIT_DIR
    set -gx __fish_git_prompt_suppress_vcs_info 1
else
    set -g __fish_git_prompt_suppress_vcs_info 0
end
```

**보안 영향**:
- `set -gx`는 **전역 export** — 하위 프로세스에 전파됨
- `GIT_DIR`이 설정된 경우, git 디렉토리 경로가 환경 변수로 노출됨
- 하위 프로세스가 `GIT_DIR`을 읽을 수 있음

---

## 5. 🌐 내부 IP/네트워크 정보 유출 패턴

**결과**: ✅ **발견되지 않음**

- `__fish_print_addresses.fish`에서 `ip addr show`, `ifconfig`, `arp` 명령어를 사용하지만, 이는 fish 자체의 주소 표시 기능이며 hostname과는 무관
- hostname 자체가 IP 주소를 직접 노출하지는 않음
- 단, `/etc/hosts`에 hostname↔IP 매핑이 있으면 `__fish_print_hostnames` 간접 노출 가능

---

## 6. 📦 Supply Chain 패턴 (3건)

### 6.1 `eval` 기반 간접적 위험

| 파일 | 패턴 | 위험도 |
|------|------|--------|
| `alias.fish` L39 | `eval "$alias_definition"` | 🟡 중간 — 사용자 입력이 eval로 실행 |
| `fish_clipboard_paste.fish` L53 | `eval "$__fish_paste_quoted"` | 🔴 높음 — 외부 클립보드 데이터 eval |
| `fish_git_prompt.fish` L527 | `eval set previous \$upstream` | 🟡 중간 — git upstream명 eval |

### 6.2 외부 도구 실행 패턴

| 파일 | 명령어 | 위험도 |
|------|--------|--------|
| `fish_git_prompt.fish` | `command git ...` (10회) | 🟢 낮음 — git 명령어 직접 실행 |
| `__fish_print_hostnames` | `command ssh ...` (완성 경로) | 🟢 낮음 |

---

## 7. 🔄 값 전파 및 오염 경로 상세

### 7.1 Hostname 오염 경로도

```
[시스템 설정]
    ├── /etc/hostname → hostname 명령어
    ├── /etc/hosts → hostname↔IP 매핑
    └── ~/.ssh/config → SSH 호스트 설정
         │
         ▼
[__fish_print_hostnames] (L82, print_hostnames.fish)
    ├── 읽기: /etc/hosts, ~/.ssh/config, ~/.ssh/known_hosts
    └── 출력: seq of hostnames (stdout)
         │
         ▼
[자동완성 소비자]
    ├── ssh.fish L2 → SSH 자동완성
    ├── scp.fish L12 → SCP 자동완성
    ├── sftp.fish L4 → SFTP 자동완성
    ├── ssh-cocli.fish L2 → SSH-COCLI 자동완성
    ├── sv.fish L47 → 서비스 자동완성
    ├── svk.fish L4 → SVK 자동완성
    └── duply.fish L133 → Duply 자동완성
         │
         ▼
[터미널 화면] → 사용자에게 hostname 목록 표시
```

### 7.2 직접 hostname 출력 경로

```
[시스템 hostname 변수]
    │
    ├──→ prompt_login.fish L25: echo $hostname → 프롬프트
    ├──→ status.fish L28: echo $hostname → stdout
    └──→ fish_title.fish L14: hostname → 탭 제목 (스크린샷 취약)
```

### 7.3 Git 데이터 오염 경로

```
[Git 리포지토리]
    ├── command git rev-parse --abbrev-ref → upstream 브랜치명
    ├── command git rev-parse HEAD → commit SHA
    └── command git status → 변경 파일 목록
         │
         ▼
[fish_git_prompt.fish]
    ├── L519: printf '%s' $current_upstream → stdout (프롬프트)
    ├── L467-470: set -l current_upstream → 내부 변수
    └── L470: set -gx GIT_DIR → 전역 환경 변수 export
         │
         ▼
[터미널 프롬프트] + [하위 프로세스 환경]
```

---

## 8. 📊 위험 요약 매트릭스

| # | 패턴 | 파일 | 라인 | 위험도 | 즉시 조치 필요 |
|---|------|------|------|--------|-------------|
| 1 | Command Injection (eval) | `fish_clipboard_paste.fish` | L53 | 🔴 높음 | ✅ 예 |
| 2 | Command Injection (eval) | `alias.fish` | L39 | 🟡 중간 | ⚠️ 검토 |
| 3 | Command Injection (eval) | `fish_git_prompt.fish` | L527 | 🟡 중간 | ⚠️ 검토 |
| 4 | Hostname 직접 출력 | `prompt_login.fish` | L25 | 🔴 높음 | ✅ 예 |
| 5 | Hostname 직접 출력 | `status.fish` | L28 | 🟡 중간 | ⚠️ 검토 |
| 6 | Git upstream 노출 | `fish_git_prompt.fish` | L519 | 🟡 중간 | ⚠️ 검토 |
| 7 | GIT_DIR 전역 export | `fish_git_prompt.fish` | L470 | 🟡 중간 | ⚠️ 검토 |
| 8 | Hostname 자동완성 노출 | `__fish_print_hostnames` | L82 | 🟡 중간 | ⚠️ 검토 |
| 9 | 탭 제목 hostname | `fish_title.fish` | L14 | 🟢 낮음 | ❌ 아니오 |
| 10 | 내부 IP 직접 노출 | — | — | ✅ 없음 | — |

---

## 9. 🛡️ 권고 조치 사항

### 즉시 조치 (P0)

1. **`fish_clipboard_paste.fish` L53**: `eval` 대신 `commandline -i --` 사용 우선순위 강화
   - 현재 L20에서 먼저 시도하지만, 실패 시 eval로 폴백
   - 권고: 폴백 시 `eval` 대신 경고 메시지 출력 후 중단

2. **`prompt_login.fish` L25**: hostname 프롬프트 표시 비활성화 옵션
   - `set -g fish_prompt_show_hostname 0` 같은 설정 추가
   - 또는 SSH 세션에서만 hostname 표시

### 검토 필요 (P1)

3. **`alias.fish` L39**: alias 정의에 허용 문자 제한 적용
   - 함수명에 대한 엄격한 검증 (알파벳, 숫자, underscore, 하이픈만 허용)

4. **`fish_git_prompt.fish` L470**: `set -gx` → `set -g` 변경 검토
   - GIT_DIR이 하위 프로세스에 전파되지 않도록

5. **`__fish_print_hostnames`**: `/etc/hosts`에서 내부 IP 매핑 필터링 옵션
   - `10.*`, `172.16-31.*`, `192.168.*` 대역 hostname 제외 옵션

### 모니터링 (P2)

6. **`fish_title.fish` L14**: 스크린샷/화면 공유 시 hostname 노출 주의
7. **`fish_git_prompt.fish` L527**: 악의적인 git 브랜치명 검증 추가

---

## 10. 결론

Fish shell의 hostname 사용은 대부분 **정상적인 기능 목적** (자동완성, 프롬프트 표시)이지만, 2가지 핵심 위험이 존재합니다:

1. **클립보드 eval 주입** (`fish_clipboard_paste.fish`): 외부 데이터가 `eval`로 실행되는 가장 위험한 패턴
2. **Hostname 정보 노출**: 프롬프트, 자동완성, 탭 제목을 통해 시스템 hostname이 다양한 경로로 표시됨

전체적으로 **네트워크를 통한 원격 공격 표면은 낮지만**, 로컬 정보 유출 및 클립보드 기반 공격 벡터는 실질적 위험이 있습니다.
