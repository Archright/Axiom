import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [].}
## tools/build_types.nim — The Immutable Builder 공유 타입 정의
## AGENTS.md §0.6: Static First Enforcement
## 모든 빌드 시스템 컴포넌트가 공유하는 타입과 Result 패턴

import std/json
import shared_types/shared_types

type
  BuildErrorKind* = enum
    bekAnalysis        ## 의존성 그래프 추출 실패
    bekQuarantine      ## 격리 충돌
    bekNormalization   ## {.raises: [].} 삽입 실패
    bekCompile         ## nim c 컴파일 실패
    bekOverlay         ## 오버레이 생성 실패
    bekIdempotency     ## 멱등성 검증 실패
    bekIO              ## 파일 I/O 실패

  BuildError* = object
    kind*: BuildErrorKind
    message*: string
    file*: string       ## 관련 파일 (선택)
    line*: int          ## 관련 라인 (선택)

  BuildResult* = Result[void, BuildError]

  ModuleInfo* = object
    path*: string           ## 상대 경로 (src/core/foo.nim)
    imports*: seq[string]   ## import하는 모듈 경로 목록
    importedBy*: seq[string] ## 이 모듈을 import하는 모듈 목록

  DependencyGraph* = object
    modules*: seq[ModuleInfo]
    orphans*: seq[string]   ## 고아 모듈 경로 목록
    entryPoints*: seq[string] ## 최상위 진입점 모듈

  QuarantineEntry* = object
    path*: string           ## 격리 대상 모듈 경로
    reason*: string         ## 격리 사유 (orphan, broken_import)

  QuarantineManifest* = object
    version*: string
    entries*: seq[QuarantineEntry]

  CompileError* = object
    file*: string
    line*: int
    col*: int
    procName*: string
    exceptionType*: string

  ChangeRecord* = object
    file*: string
    line*: int
    procName*: string
    annotation*: string     ## {.raises: [].} 또는 {.raises: [ExcType].}

  BuildConfig* = object
    srcDir*: string          ## "src"
    entryPoint*: string      ## "src/cli/axiom.nim"
    outputPath*: string      ## "bin/axiom"
    overlayDir*: string      ## "build/tmp"
    nimcacheDir*: string     ## "build/nimcache"
    hashFile*: string        ## "data/.build_hash"
    autoRaises*: bool        ## {.raises: [].} 자동 삽입 활성화
    dryRun*: bool            ## Dry Run 모드
    verify*: bool            ## 멱등성 검증 모드
    jsonLog*: bool           ## JSON 구조화 로그

# ── JSON 직렬화 헬퍼 (I/O 경계) ──────────────────────────────────────────────
{.pop.}  # raises: []. — I/O 경계 procs는 IOError 허용

proc toJson*(graph: DependencyGraph): JsonNode {.raises: [].} =
  ## DependencyGraph를 JSON으로 직렬화
  var modules = newJArray()
  for m in graph.modules:
    modules.add(%*{
      "path": m.path,
      "imports": %m.imports,
      "importedBy": %m.importedBy
    })
  %*{
    "modules": modules,
    "orphans": %graph.orphans,
    "entryPoints": %graph.entryPoints
  }

proc toJson*(manifest: QuarantineManifest): JsonNode =
  ## QuarantineManifest를 JSON으로 직렬화
  var entries = newJArray()
  for e in manifest.entries:
    entries.add(%*{"path": e.path, "reason": e.reason})
  %*{
    "version": manifest.version,
    "entries": entries
  }

proc save*(graph: DependencyGraph, path: string) {.raises: [IOError].} =
  ## DependencyGraph를 JSON 파일로 저장
  writeFile(path, graph.toJson().pretty())

proc save*(manifest: QuarantineManifest, path: string) {.raises: [IOError].} =
  ## QuarantineManifest를 JSON 파일로 저장
  writeFile(path, manifest.toJson().pretty())

proc toBuildError*(kind: BuildErrorKind, msg: string, file: string = "", line: int = 0): BuildError {.raises: [].} =
  ## BuildError 생성 헬퍼
  BuildError(kind: kind, message: msg, file: file, line: line)

proc err*(kind: BuildErrorKind, msg: string, file: string = "", line: int = 0): BuildResult {.raises: [].} =
  ## BuildResult 에러 생성 헬퍼
  err(toBuildError(kind, msg, file, line))
