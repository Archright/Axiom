import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import core/trusted/axiom_pragmas_lite
import core/types/results
import std/json
import std/os
import std/strutils
import core/interfaces/logging_hub
import core/macros/best_effort
type
  # ── 기존 에러 타입 ──

  FileMoveError* = object of CatchableError
    ## moveFile에서 발생하는 파일 이동 에러

  # ── Topology 도메인 에러 계층 (Deterministic Exception Translation) ──
  # Context7 검증: Nim stdlib의 IOError→EOFError 패턴과 동일한 상속 구조
  # NEP-1 준수: *Error suffix
  TopologyBaseError* = object of CatchableError
    ## Topology 도메인의 모든 I/O/파싱 에러 base class
    ## CLI 핸들러에서 except TopologyBaseError: 하나로 전체 도메인 에러 캐치 가능

  TopologyIOError* = object of TopologyBaseError
    ## topology 파일 I/O 전용 (readFile, walkDirRec, dirExists)

  JsonParseShieldError* = object of TopologyBaseError
    ## parseJson/parseFile 전용 (JSON 파싱 실패)

  # ── I/O Result 에러 (Result-based I/O wrappers) ──
  IoError* = enum
    ieFileNotFound = "file_not_found"
    iePermissionDenied = "permission_denied"
    ieDiskFull = "disk_full"
    ieParseFailure = "parse_failure"
    ieNetworkUnreachable = "network_unreachable"
    ieTimeout = "timeout"
    ieAlreadyExists = "already_exists"
    ieInvalidPath = "invalid_path"
proc safeMoveFile*(source, dest: string) {.raises: [FileMoveError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## moveFile를 안전하게 래핑합니다.
  ## stdlib moveFile lacks {raises: [CatchableError]} — strictEffects infers Exception.
  ## We intentionally catch Exception here; suppressed BareExcept via push/pop.
  {.push warning[BareExcept]: off.}
  try:
    moveFile(source, dest)
  except Exception as e:
    raise newException(FileMoveError, "moveFile(" & source & " → " & dest & "): " & e.msg, e)
  {.pop.}
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc safeRemoveFile*(path: string) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## removeFile를 안전하게 래핑합니다.
  ## stdlib removeFile lacks {raises: [CatchableError]} — strictEffects infers Exception.
  {.push warning[BareExcept]: off.}
  try:
    removeFile(path)
  except Exception as e:
    raise newException(CatchableError, "removeFile(" & path & "): " & e.msg, e)
  {.pop.}
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func safeRunCallback*[T](
  cb: proc(v: T) {.closure, gcsafe, raises: [CatchableError].},
  val: T
): Result[void, string] {.raises: [].} =
  ## 외부 콜백의 CatchableError를 Result로 변환합니다.
  ## 콜백이 CatchableError를 던질 수 있음을 명시적으로 선언합니다.
  try:
    cb(val)
    ok[void, string]()
  except CatchableError as e:
    err[void, string]("callback failed: " & e.msg)
# ── Topology I/O Shield Wrappers (Deterministic Exception Translation) ──
# OSError/IOError를 IoError enum으로 분류하여 Result로 반환합니다.

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func classifyIoError(e: ref Exception): IoError {.raises: [].} =
  ## OSError/IOError 메시지를 분석하여 IoError enum으로 분류합니다.
  let msg = e.msg
  if "already exists" in msg: ieAlreadyExists
  elif "permission" in msg or "denied" in msg: iePermissionDenied
  elif "not found" in msg or "no such file" in msg: ieFileNotFound
  elif "no space" in msg or "disk full" in msg: ieDiskFull
  elif "network" in msg or "unreachable" in msg: ieNetworkUnreachable
  elif "timeout" in msg or "timed out" in msg: ieTimeout
  elif "invalid" in msg: ieInvalidPath
  else: ieFileNotFound
# shieldLog로 raise 직전 상태를 기록합니다 (shieldLog의 IOError 안전 처리).
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
template shieldLog(msg: string) {.bestEffort("""logging failure must not affect business logic""").} =
  ## shieldLog의 IOError를 안전하게 무시하는 로깅 템플릿.
  ## 로깅 실패가 비즈니스 로직에 영향을 주지 않아야 합니다.
  try: logInfo(msg)
  except CatchableError: discard  # axiom:best-effort(ioboundary catch)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
template shieldLogChain(e: ref Exception) {.used.} =
  ## Dumps full exception chain to stderr (developer debug mode only).
  ## Traverses Nim's built-in parent* field to show root cause.
  when defined(axiomDebug):
    var current: ref Exception = e
    var depth = 0
    while current != nil:
      shieldLog("  " & "  ".repeat(depth) & "\u2514\u2500 " & $current.name & ": " & current.msg)
      current = current.parent
      inc depth
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc safeWriteFile*(path: string, content: string): Result[void, IoError] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## writeFile를 Result 기반으로 안전하게 래핑합니다.
  ## OSError → IoError enum 변환.
  try:
    writeFile(path, content)
    Result[void, IoError](ok: true)
  except CatchableError as e:
    shieldLog("[SHIELD] safeWriteFile failed: path=" & path & " reason=" & e.msg)
    Result[void, IoError](ok: false, err: classifyIoError(e))
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc safeDeleteFile*(path: string): Result[void, IoError] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## removeFile를 Result 기반으로 안전하게 래핑합니다.
  ## OSError → IoError enum 변환.
  try:
    removeFile(path)
    Result[void, IoError](ok: true)
  except CatchableError as e:
    shieldLog("[SHIELD] safeDeleteFile failed: path=" & path & " reason=" & e.msg)
    Result[void, IoError](ok: false, err: classifyIoError(e))
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc safeCreateDir*(dir: string): Result[void, IoError] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## createDir를 Result 기반으로 안전하게 래핑합니다.
  ## OSError → IoError enum 변환.
  try:
    createDir(dir)
    Result[void, IoError](ok: true)
  except CatchableError as e:
    shieldLog("[SHIELD] safeCreateDir failed: dir=" & dir & " reason=" & e.msg)
    Result[void, IoError](ok: false, err: classifyIoError(e))
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc safeReadFile*(path: string): string {.raises: [TopologyIOError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## readFile 실패 시 path 정보 포함. IOError/OSError → TopologyIOError 변환.
  try:
    readFile(path)
  except CatchableError as e:
    shieldLog("[SHIELD] safeReadFile failed: path=" & path & " reason=" & e.msg)
    raise newException(TopologyIOError, "readFile failed: path=" & path & " reason=" & e.msg, e)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc safeWalkDirRec*(dir: string): seq[string] {.raises: [TopologyIOError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## walkDirRec 실패 시 dir 정보 포함.
  try:
    var files: seq[string] = @[]
    for entry in walkDirRec(dir):
      files.add(entry)
    files
  except OSError as e:
    shieldLog("[SHIELD] safeWalkDirRec failed: dir=" & dir & " reason=" & e.msg)
    raise newException(TopologyIOError, "walkDirRec failed: dir=" & dir & " reason=" & e.msg, e)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc safeDirExists*(dir: string): bool {.raises: [TopologyIOError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## dirExists 실패 시 dir 정보 포함.
  try:
    dirExists(dir)
  except OSError as e:
    shieldLog("[SHIELD] safeDirExists failed: dir=" & dir & " reason=" & e.msg)
    raise newException(TopologyIOError, "dirExists failed: dir=" & dir & " reason=" & e.msg, e)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc safeParseJson*(s: string): JsonNode {.raises: [JsonParseShieldError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## JSON 문자열 파싱. 원본 파일 경로는 호출부에서 메시지에 추가.
  try:
    parseJson(s)
  except JsonParsingError as e:
    shieldLog("[SHIELD] safeParseJson failed: reason=" & e.msg)
    raise newException(JsonParseShieldError, "JSON parse failed: " & e.msg, e)
  except CatchableError as e:
    shieldLog("[SHIELD] safeParseJson failed: reason=" & e.msg)
    raise newException(JsonParseShieldError, "JSON parse failed: " & e.msg, e)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc safeParseFile*(path: string): JsonNode {.raises: [TopologyBaseError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## readFile + parseJson 원자적 변환.
  ## readFile 실패 → TopologyIOError (읽기 권한/경로 문제)
  ## parseJson 실패 → JsonParseShieldError (파일은 읽혔으나 JSON 깨짐)
  ## 에러 메시지로 명확히 구분: "read failure: path=X" vs "parse failure: path=X reason=Y"
  let content =
    try:
      readFile(path)
    except CatchableError as e:
      shieldLog("[SHIELD] safeParseFile read failure: path=" & path & " reason=" & e.msg)
      raise newException(TopologyIOError, "read failure: path=" & path & " reason=" & e.msg, e)
  try:
    parseJson(content)
  except JsonParsingError as e:
    shieldLog("[SHIELD] safeParseFile parse failure: path=" & path & " reason=" & e.msg)
    raise newException(JsonParseShieldError, "parse failure: path=" & path & " reason=" & e.msg, e)
  except CatchableError as e:
    shieldLog("[SHIELD] safeParseFile parse failure: path=" & path & " reason=" & e.msg)
    raise newException(JsonParseShieldError, "parse failure: path=" & path & " reason=" & e.msg, e)

{.pop.}
