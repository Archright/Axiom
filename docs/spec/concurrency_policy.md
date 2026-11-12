# Axiom 동시성 정책 (Concurrency Policy)

> **AGENTS.md §0.6a의 구현 규격.**
> 새 에이전트가 동시성 도구를 선택할 때 이 문서를 참조합니다.
>
> **배경**: malebolgia는 8번의 add/remove 주기를 겪었습니다. FD 고갈, ORC 할당자 누수, 중첩 병렬 폭발이 원인이었고, 모두 malebolgia 자체의 결함이 아닙니다. 현재 OS 프로세스 수준 병렬처리로 전환하여 안정 운영 중입니다. malebolgia는 향후 CPU 바운드 작업에 재도입 가능합니다.

---

## §1. 의사결정 트리

```
작업의 성격이 무엇인가?
│
├── 1. 네트워크 통신, LSP 메시지 송수신, 비동기 I/O
│      └── 🎯 asyncdispatch (기존 유지)
│      └── 📋 구체적 예시:
│          - lean_lsp.nim의 LeanLspClient 통신
│          - MCP 서버의 JSON-RPC 송수신
│          - 외부 HTTP API 호출
│      └── ⚠️ 주의사항:
│          - 이 컨텍스트의 ref object에는 {.acyclic.}를 적용하지 말 것
│          - async가 순환 참조를 생성할 수 있기 때문
│
├── 2. 외부 프로그램(Z3 솔버, 타사 린터, nim check 등) 실행
│      └── 🎯 startProcess (OS 프로세스 격리)
│      └── 📋 구체적 예시:
│          - gate_hook.nim의 게이트 바이너리 실행
│          - Z3 솔버 프로세스 풀 (z3_pool.nim)
│          - nim check 실행
│          - Lean 4 컴파일러 실행
│      └── 📋 패턴:
│          let process = startProcess(cmd, args, options={poUsePath})
│          let exitCode = process.waitForExit(timeout)
│          let output = process.outputStream.readAll()
│          process.close()
│      └── ⚠️ 주의사항:
│          - fork()는 부모의 모든 FD를 상속함 (RLIMIT_NOFILE 주의)
│          - 대량의 외부 프로세스를 동시에 생성하지 말 것 (bounded concurrency)
│          - 현재 MaxConcurrentL2 = 4 적용 중
│
└── 3. 고속 수학 연산, AST 탐색, BMC 기호 실행 등 "순수 CPU"
       │
       └── [스레드 간에 주고받을 데이터의 타입이 무엇인가?]
              │
              ├── 값 타입이다 (object, tuple, seq[string], int, float 등)
              │      └── 🎯 malebolgia 투입 (초고속 병렬 처리)
              │      └── 📋 안전 사용 체크리스트 (6개 전부 충족 필수):
              │          □ 1. spawn 인자는 반드시 값 타입
              │             - 허용: object, tuple, seq[T], string, int, float, bool
              │             - 금지: ref object, ptr, pointer, addr
              │          □ 2. spawn 내부에서 fork/exec/startProcess 호출 없음
              │             - spawn된 프로시저는 순수 CPU 연산만 수행
              │             - 파일 I/O는 허용 (writeFile, readFile)
              │          □ 3. createMaster() 중첩 없음
              │             - 단일 수준의 createMaster() + awaitAll()만 허용
              │             - spawn 내부에서 또 다른 createMaster() 호출 금지
              │          □ 4. bounded concurrency 적용
              │             - 명시적으로 MaxWorkers 지정 또는
              │             - 시스템 CPU 코어 수의 절반 이하로 제한
              │          □ 5. 결과를 메모리에 누적하지 않고 스트리밍
              │             - 대량 문자열을 GateResult.stdout에 누적하지 말 것
              │             - 파일에 직접 쓰거나 Channel로 스트리밍
              │          □ 6. {-d:useMalloc} 플래그 적용
              │             - ORC 할당자 누수(nim-lang/Nim#23361) 회피
              │             - config.nims에 추가 또는 빌드 시 명시
              │      └── 📋 코드 예시:
              │          import malebolgia
              │          type WorkItem = object  # 값 타입!
              │            id: int
              │            data: string
              │          proc processItem(item: WorkItem) {.gcsafe.} =
              │            # CPU 연산만 수행
              │            let result = heavyComputation(item.data)
              │            writeFile("output/" & $item.id & ".txt", result)
              │          var master = createMaster()
              │          master.awaitAll:
              │            for i in 0..<countProcessors() div 2:
              │              master.spawn processItem(WorkItem(id: i, data: tasks[i]))
              │
              └── 힙 참조 타입이다 (ref object, 포인터 얽힘)
                     └── 🎯 malebolgia 금지!
                     └── 📋 대안 (2가지 중 선택):
                     │   ① 값 타입으로 변환: ref object → object
                     │      - 가능한 경우: 트리 구조를 seq 기반으로 변경
                     │      - 불가능한 경우: 다형성(method dispatch)이 필요하면 ②번
                     │   ② OS 프로세스로 분리: startProcess로 격리 실행
                     │      - 프로세스 간 통신은 파일 또는 stdin/stdout
                     └── ⚠️ 왜 금지인가?
                         - Nim의 RC(참조 카운트) 연산은 비원자적(non-atomic)
                         - 스레드 간 ref 공유 시 참조 카운트 corruption 가능
                         - malebolgia의 isolate()가 불완전할 수 있음
                         - 프로젝트 역사: 8번의 add/remove 주기, 3가지 별도 원인의 실패
```

---

## §2. 메모리 모델 정책 (--mm:orc + {.acyclic.})

### 프로젝트는 `--mm:orc`를 사용합니다 (config.nims 라인 4).

```
ref object를 선언하는가?
│
├── 순환 참조가 가능한가? (부모↔자식, self-ref, 양방향 연결)
│   │
│   ├── 아니오 (단방향 트리/DAG 구조)
│   │      └── 🎯 {.acyclic.} 의무 적용
│   │      └── 📋 코드 예시:
│   │          type
│   │            SymSymSExprObj {.acyclic.} = ref object
│   │              name: string
│   │              children: seq[SymSymSExprObj]  # 부모→자식만, 역참조 없음
│   │      └── 📋 효과:
│   │          - ORC의 cycle collector가 이 타입을 스캔 대상에서 제외
│   │          - 머신 코드 크기 감소
│   │          - 결정론적 해제 (trial deletion 없이 순수 RC)
│   │      └── 📋 안전성:
│   │          - Nim 공식 문서: "Misuse can lead to memory leaks but
│   │            will not compromise memory safety"
│   │          - 순환 참조가 없으므로 누수도 발생하지 않음
│   │      └── 📋 Nim 공식 권장 (mm.html):
│   │          "We generally advise you to use the acyclic annotation
│   │           in order to optimize away the cycle collector's overhead"
│   │
│   └── 예 (순환 참조 구조)
│          └── 🎯 {.cursor.}로 비소유 엣지 표시
│          └── 📋 코드 예시:
│              type
│                Node = ref object
│                  parent: Node              # 소유 참조 (참조 카운트 증가)
│                  children: seq[Node]       # 소유 참조
│                  sibling {.cursor.}: Node  # 비소유 참조 (참조 카운트 미참여)
│          └── ⚠️ 주의사항:
│              - {.cursor.}는 raw 포인터임 (C++의 weak_ptr이 아님)
│              - Nim 공식 문서: "this is not C++'s weak_ptr, it is a
│                raw pointer without runtime checks"
│              - dangling pointer 감지 없음 (런타임 체크 없음)
│              - 비소유 참조의 수명을 수동으로 관리해야 함
│              - 반드시 주석으로 순환 구조를 문서화할 것
│
└── async 컨텍스트에서 사용하는가?
    └── 예 → 타입 구조를 확인할 것
        └── 타입 자체에 self-referential 필드가 없으면 {.acyclic.} 적용 가능
           (async 런타임의 내부 순환은 ORC가 별도로 처리함)
        └── 단, async가 생성하는 Future/closure 내부의 순환은 {.acyclic.}와 무관
           (这是 ORC 런타임 수준의 문제, 타입 수준의 문제가 아님)
        └── Nim 공식 문서 (mm.html):
            "Notice that the default async implementation produces
             cycles and leaks memory with --mm:arc"
            → 이는 async 런타임 자체의 순환 참조이며, 사용자 정의 타입과 무관
        └── 예시: LeanLspClient는 async 컨텍스트에서 사용되지만,
           자기 참조 필드가 없으므로 {.acyclic.} 적용 가능 (✅ 적용됨)
```

---

## §3. 각 도구별 상세 가이드

### 3.1 asyncdispatch (비동기 I/O)

| 항목 | 내용 |
|------|------|
| **何时** | 네트워크 통신, LSP 메시지 송수신, HTTP API |
| **コードパターン** | `{.async.}` 프로시저 + `Future[T]` |
| **注意** | 이 컨텍스트의 ref에는 {.acyclic.} 미적용 |
| **現在使用** | `lean_lsp.nim`, `mcp/server.nim` |

### 3.2 startProcess (OS 프로세스 격리)

| 항목 | 내용 |
|------|------|
| **何时** | 외부 프로그램 실행, 컴파일러 호출 |
| **コードパターン** | `startProcess` + `waitForExit` + `outputStream.readAll` |
| **注意** | bounded concurrency (`MaxConcurrentL2 = 4`) |
| **現在使用** | `gate_hook.nim`, `z3_pool.nim` |

### 3.3 malebolgia (스레드 병렬)

| 항목 | 내용 |
|------|------|
| **何时** | 순수 CPU 바운드 + 값 타입 데이터 |
| **コードパターン** | `createMaster` + `spawn` + `awaitAll` |
| **注意** | §1의 6개 체크리스트 전부 충족 필수 |
| **現在使用** | 없음 (제거됨). 향후 BMC 등에 재도입 가능. |
| **設計者** | Andreas Rumpf (Nim 창시자) |
| **コードサイズ** | ~300줄 미만의 구조적 동시성 라이브러리 |

---

## §4. 금지 패턴

### ❌ 패턴 1: spawn 내부에서 ref object 캡처

```nim
# malebolgia spawn에 ref를 전달하면 참조 카운트 corruption 가능
proc bad(item: ref MyObj) {.gcsafe.} =  # 금지!
  echo item.name
master.spawn bad(myRefObj)
```

**왜 금지**: Nim의 RC 연산은 비원자적. 스레드 간 ref 공유 시 참조 카운트가 corruption될 수 있음.

### ❌ 패턴 2: addr/ref를 통한 스레드 간 직접 포인터 전달

```nim
# Issue #24988과 동일한 패턴 — SIGSEGV 발생
var s = newSeq[int]()
createThread(thr, threadFunc, s.addr)  # unsafe!
```

**왜 금지**: `ptr`는 raw 포인터로, Nim의 메모리 안전성 보장이 적용되지 않음.

### ❌ 패턴 3: 중첩 createMaster()

```nim
# 무제한 스레드 폭발 — OOM 유발
var outer = createMaster()
outer.awaitAll:
  outer.spawn(proc() =
    var inner = createMaster()  # 금지!
    inner.awaitAll: ...
  )
```

**왜 금지**: 프로젝트 역사상 이 패턴이 377개 프로세스 동시 생성 → OOM을 유발했음.

### ❌ 패턴 4: spawn 내부에서 대량 문자열 누적

```nim
proc bad(item: WorkItem) {.gcsafe.} =
  var output = ""
  for i in 0..<10000:
    output &= heavyComputation(i)  # 메모리 누적!
```

**올바른 대안**: 파일에 직접 쓰거나 Channel로 스트리밍.

### ❌ 패턴 5: {.cast(gcsafe).} 남용

```nim
# 최후의 수단만. 남용 시 스레드 안전성 검증 불가.
{.cast(gcsafe).}:
  sharedData.modify()  # 위험!
```

**왜 위험**: 컴파일러의 gcsafe 검증을 우회하여 스레드 안전성을 수동으로 보장해야 함.

---

## §5. 사고 기록 참조

| 문서 | 내용 |
|------|------|
| `docs/history/malebolgia_fd_root_cause_analysis.md` | FD 고갈 분석 (353줄) |
| `docs/history/oom-reinvestigation-2026-05-27.md` | OOM 재조사 — ORC 할당자 누수 |
| `docs/history/oom-final-root-cause-2026-05-27.md` | 3-Layer 메모리 폭탄 구조 |
| `docs/history/gemini-rebuttal.md` | Gemini 주장 반박 (2026-05-27) |
| `docs/spec/nim_effect_system_quirks.md` | Nim 효과 시스템 quirks |
| `docs/spec/threadpool_migration.md` | malebolgia 의사결정 기록 |

---

## §6. 변경 이력

| 날짜 | 변경 | 이유 |
|------|------|------|
| 2026-06-01 | 초안 작성 | Context7 공식문서 기반 동시성 정책 수립 |
