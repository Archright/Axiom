# Artefact Producer Protocol v1.0

## §1. 목적

서브에이전트가 생성한 소스 코드를 **IPC 데이터 채널**을 통해 오케스트레이터에게 전달하는 표준 프로토콜.
Git Plumbing CAS(Content-Addressable Storage) 기반 원자적 프로모션을 통해 파일 손실을 방지한다.

## §2. 배경

### 2.1 문제: `isolate_workspace=true` 파일 손실

- Kimi Code CLI의 서브에이전트는 기본적으로 격리 워크스페이스에서 실행
- 격리 워크스페이스의 파일은 서브에이전트 완료 후 정리될 수 있음
- Context compaction이 untracked 파일을 삭제하여 파일 손실 발생

### 2.2 해결: IPC 데이터 주도형 프로모션

- 서브에이전트가 파일시스템에 직접 쓰는 대신, **구조화 JSON 데이터**로 반환
- 오케스트레이터가 수신한 데이터를 Git 오브젝트 DB에 직접 주입
- 파일시스템 노출 없이 영속성 확보

## §3. 프로토콜 명세

### 3.1 YieldArtifact Payload 스키마 (v1.0)

```json
{
  "v": "1.0",
  "files": [
    {
      "p": "src/core/gate/foo.nim",
      "c": "cHJvYyB0ZXN0KCkgPSBkaXNjYXJk",
      "h": "a1b2c3d4e5f67890abcdef1234567890abcdef1234567890abcdef1234567890"
    }
  ]
}
```

### 3.2 필드 정의

| 필드 | 타입 | 필수 | 설명 |
|------|------|------|------|
| `v` | string | ✅ | 프로토콜 버전 (현재 "1.0") |
| `files` | array | ✅ | 파일 아티팩트 목록 |
| `files[].p` | string | ✅ | 프로젝트 루트 기준 상대 경로 |
| `files[].c` | string | ✅ | Base64 인코딩된 파일 본문 |
| `files[].h` | string | ✅ | SHA-256 해시 (hex, 64자) |

### 3.3 인코딩 규칙

- **content 필드**: 반드시 Base64 인코딩 (JSON 특수문자 안전성 보장)
- **SHA-256**: 원본 바이너리의 해시 (Base64 디코딩 후 계산)
- **경로 구분자**: POSIX 스타일 (`/`) — 크로스 플랫폼 호환

## §4. 서브에이전트 의무 사항

### 4.1 필수 단계

```
1. 코드 생성: Write 도구로 격리 FS에 파일 생성
2. 코드 읽기: Read 도구로 파일 내용 획득
3. Base64 인코딩: bash: base64 <파일경로> | tr -d '\n'
4. SHA256 계산: bash: sha256sum <파일경로> | cut -d' ' -f1
5. JSON 구성: 위 스키마에 따라 payload 생성
6. YieldArtifact(payload=<JSON>, finalize=true) 호출
```

### 4.2 준수 강제

- `output_mode='artifact'`가 활성화된 서브에이전트는 반드시 `YieldArtifact`를 호출해야 함
- 호출하지 않으면 플랫폼이 "fails deterministically"로 처리

### 4.3 대용량 파일 분할 (Chunked YieldArtifact)

파일이 100KB를 초과할 경우 분할 전송:

```json
// 청크 1/N (finalize=false)
{"v":"1.0","chunk":{"file":"src/logger.nim","i":0,"n":3},
 "files":[{"p":"src/logger.nim","c":"base64_part_0...","h":"partial"}]}

// 청크 N/N (finalize=true)
{"v":"1.0","chunk":{"file":"src/logger.nim","i":2,"n":3},
 "files":[{"p":"src/logger.nim","c":"base64_part_2...","h":"full_sha256"}]}
```

## §5. 오케스트레이터 의무 사항

### 5.1 수신 및 검증

```
1. payload JSON 파싱
2. 각 파일의 Base64 디코드
3. SHA-256 교차 검증 (디코딩된 내용의 해시 == h 필드)
4. 불일치 시 프로모션 거부 (Fail-Fast)
```

### 5.2 Git Plumbing CAS 주입

```
1. GIT_INDEX_FILE 설정 (UUID 격리)
2. git read-tree HEAD (인덱스 초기화)
3. 각 파일: base64 디코드 → git hash-object -w --stdin → git update-index
4. git write-tree → git commit-tree → git reset --hard
5. posix.sync() (하드웨어 배리어)
```

### 5.3 충돌 해결

| 시나리오 | 처리 |
|---------|------|
| 같은 경로 + 같은 blob SHA | no-op (멱등) |
| 같은 경로 + 다른 blob SHA | Fail-Fast 거부 |
| 서로 다른 경로 | 독립 주입 |

### 5.4 크래시 복구

```bash
cas_promote --recover <commit_sha>
# 이미 영속된 커밋으로 워킹 트리 재설정 (멱등)
```

## §6. 도구

- `tools/cas_promote.nim` — Nim 네이티브 CAS 프로모션 엔진
- Usage: `echo "$payload" | cas_promote`
- Recovery: `cas_promote --recover <commit_sha>`

## §7. 참조

- 계획서: `plans/scarlet-witch-mister-terrific-john-stewart.md`
- AGENTS.md § 서브에이전트 아티팩트 프로토콜
- Context7 검증: Git plumbing, YieldArtifact, AgentSwarm
