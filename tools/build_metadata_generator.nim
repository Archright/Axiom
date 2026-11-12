## build_metadata_generator.nim — 정적 빌드 메타데이터 JSON 생성기
##
## config.nims의 모든 gorge() 호출을 제거하기 위해
## src/generated/build_metadata.json을 생성합니다.
## config.nims는 이후 staticRead로 이 파일을 읽어 shell 호출을 완전히 제거합니다.
##
## 특성:
##   - 영등변성(idempotent): 내용이 변경될 때만 기록 (mtime 보존 → 캐시 안전)
##   - 표준 라이브러리만 사용 (외부 의존성 없음)
##   - hermetic_build와 동일한 프로젝트 코딩 컨벤션 준수
##
## 실행:
##   nim c -o:bin/build_metadata_generator tools/build_metadata_generator.nim
##   bin/build_metadata_generator

import core/trusted/layer_declaration
axiomLayer "tools"
import core/config/toolchain_config  # ExpectedZ3Version SSOT (WS-P2-B)
{.push raises: [CatchableError].}

import std/[os, json, times, strutils, osproc, algorithm]

const
  OutputPath = "src/generated/build_metadata.json"
  GeneratorVersion = 2  # v2: +manifestFiles, +runnerFiles
  NimbleFile = "axiom.nimble"

# ── Pure functions ────────────────────────────────────────────────────────────

func parseNimblePackage(nimblePath: string): string =
  ## nimble 파일명에서 패키지 이름 추출 (Nimble 컨벤션: 파일명 = 패키지명)
  let filename = extractFilename(nimblePath)
  if filename.endsWith(".nimble"):
    return filename[0 .. ^8]  # ".nimble" 제거
  return "axiom"  # 기본값

# ── I/O functions (CatchableError 필요) ───────────────────────────────────────

proc getGitCommitCount(): string =
  ## git 커밋 수 조회 (shallow clone 지원)
  try:
    let (output, exitCode) = execCmdEx("git rev-list --count HEAD 2>/dev/null")
    if exitCode == 0:
      let stripped = output.strip()
      if stripped.len > 0:
        return stripped
  except CatchableError:
    discard  # axiom:best-effort(git commit count unavailable)
  return "0"

proc getGitHash(): string =
  ## 짧은 git 해시 조회 (worktree 지원)
  # 환경변수 fallback (CI shallow clone 지원)
  let envHash = getEnv("AXIOM_GIT_HASH", "")
  if envHash.len > 0:
    return envHash
  # worktree 지원: .git이 파일이면 gitdir 포인터를 따라감
  try:
    if fileExists(".git"):
      let gitContent = readFile(".git").strip()
      var gitDir = ""
      if gitContent.startsWith("gitdir: "):
        gitDir = gitContent[8..^1]
      if gitDir.len > 0:
        let headPath = gitDir / "HEAD"
        if fileExists(headPath):
          let headContent = readFile(headPath).strip()
          if headContent.startsWith("ref: "):
            let refName = headContent[5..^1]
            # worktree: ref 파일이 worktree dir에도, main git dir에도 있을 수 있음
            var refPath = gitDir / refName
            if not fileExists(refPath):
              # main git dir에서 시도 (.git/worktrees/xxx → ../..)
              let mainGitDir = gitDir / "../.."
              refPath = mainGitDir / refName
            if fileExists(refPath):
              let fullHash = readFile(refPath).strip()
              return fullHash[0..<min(7, fullHash.len)]
            return refName  # ref 파일 없으면 이름 반환
          else:
            let fullHash = headContent
            return fullHash[0..<min(7, fullHash.len)]
  except CatchableError:
    discard  # axiom:best-effort(worktree .git read failure)
  # fallback: git 명령어 사용
  try:
    let (output, exitCode) = execCmdEx("git rev-parse --short HEAD 2>/dev/null")
    if exitCode == 0:
      let stripped = output.strip()
      if stripped.len > 0:
        return stripped
  except CatchableError:
    discard  # axiom:best-effort(git rev-parse fallback failure)
  return "unknown"

proc getHooksPath(): string =
  ## git hooks 경로 조회
  try:
    let (output, exitCode) = execCmdEx("git config core.hooksPath 2>/dev/null")
    if exitCode == 0:
      let stripped = output.strip()
      if stripped.len > 0:
        return stripped
  except CatchableError:
    discard  # axiom:best-effort(git hooks path unavailable)
  return ""

proc getGlibcVersion(): string =
  ## glibc 버전 조회
  try:
    let (output, exitCode) = execCmdEx("ldd --version 2>&1 | head -1")
    if exitCode == 0:
      let stripped = output.strip()
      if stripped.len > 0:
        return stripped
  except CatchableError:
    discard  # axiom:best-effort(ldd version unavailable)
  return ""

proc getZ3Version(): string =
  ## Z3 버전 — 프로젝트가 선언한 버전 사용 (발견하지 않음)
  return ExpectedZ3Version

proc getNimVersion(): string =
  ## Nim 컴파일러 버전 조회
  try:
    let (output, exitCode) = execCmdEx("nim --version 2>&1 | head -1")
    if exitCode == 0:
      let stripped = output.strip()
      if stripped.len > 0:
        return stripped
  except CatchableError:
    discard  # axiom:best-effort(nim version unavailable)
  return "unknown"

proc collectSourceFiles(srcDir: string): seq[string] =
  ## src/ 디렉토리의 .nim 파일을 상대 경로로 수집, 정렬
  if not dirExists(srcDir):
    return @[]
  for filePath in walkDirRec(srcDir):
    if filePath.endsWith(".nim") and "generated" notin filePath and
       "nimcache" notin filePath:
      # 상대 경로로 변환
      let relPath = filePath.replace(srcDir & "/", "")
      result.add(relPath)
  result.sort()

proc getFeatureManifestMtime(path: string): int64 =
  ## feature_manifest.json의 수정 시간 반환
  try:
    if fileExists(path):
      return int64(getLastModificationTime(path).toUnix())
  except CatchableError:
    discard  # axiom:best-effort(manifest mtime unavailable)
  return 0

proc getNewestFeatureMtime(testsDir: string): int64 =
  ## tests/features/ 디렉토리에서 가장 최신 .feature 파일의 수정 시간 반환
  var newest: int64 = 0
  if not dirExists(testsDir):
    return 0
  try:
    for kind, path in walkDir(testsDir):
      if kind == pcFile and path.endsWith(".feature"):
        let mtime = int64(getLastModificationTime(path).toUnix())
        if mtime > newest:
          newest = mtime
  except CatchableError:
    discard  # axiom:best-effort(feature dir walk failure)
  return newest

# ── Manifest & Runner Collection ─────────────────────────────────────────────

proc collectManifestFiles(manifestDir: string): seq[string] =
  ## src/gate/manifest.d/*.json 파일명 수집 (정렬, _index.json 제외)
  ## manifestSsoTGuard (config/integrity.nims)에서 사용.
  ## _index.json 자체는 sync_topology.nim이 단독 생성 (gate-ID 포맷).
  if not dirExists(manifestDir):
    return @[]
  for kind, path in walkDir(manifestDir):
    let filename = extractFilename(path)
    if kind == pcFile and filename.endsWith(".json") and filename != "_index.json":
      result.add(filename)
  result.sort()

proc collectRunnerFiles(runnersDir: string): seq[string] =
  ## src/gate/runners/*.nim 파일명 수집 (정렬)
  ## gate_registry.nim 러너 검증에서 사용
  if not dirExists(runnersDir):
    return @[]
  for kind, path in walkDir(runnersDir):
    let filename = extractFilename(path)
    if kind == pcFile and filename.endsWith(".nim"):
      result.add(filename)
  result.sort()

# ── Main ──────────────────────────────────────────────────────────────────────

proc main() =
  # 소스 파일 수집
  let sourceFiles = collectSourceFiles("src")

  # nimble 패키지 이름 파싱
  var nimblePackage = "axiom"
  if fileExists(NimbleFile):
    try:
      nimblePackage = parseNimblePackage(NimbleFile)
    except CatchableError:
      discard  # axiom:best-effort(nimble parse failure)

  # 생성 시각 (파일에 기록되지만 영등변성 비교에서는 제외)
  let generatedAt = now().utc().format("yyyy-MM-dd'T'HH:mm:ss'Z'")

  # Manifest & Runner 파일 수집 (config.nims, gate_registry.nim에서 사용)
  let manifestFiles = collectManifestFiles("src/gate/manifest.d")
  let runnerFiles = collectRunnerFiles("src/gate/runners")

  # JSON 빌드
  let json = %*{
    "generatorVersion": GeneratorVersion,
    "generatedAt": generatedAt,
    "commitCount": parseInt(getGitCommitCount()),
    "gitHash": getGitHash(),
    "hooksPath": getHooksPath(),
    "z3Version": getZ3Version(),
    "glibcVersion": getGlibcVersion(),
    "sourceFileList": sourceFiles,
    "manifestFiles": manifestFiles,
    "runnerFiles": runnerFiles,
    "featureManifestMtime": getFeatureManifestMtime("data/feature_manifest.json"),
    "newestFeatureMtime": getNewestFeatureMtime("tests/features"),
    "nimblePackage": nimblePackage,
    "nimVersion": getNimVersion()
  }

  # 영등변성 기록: generatedAt을 제외한 안정적 내용만 비교
  # generatedAt은 매 실행마다 변경되므로 캐시 버스팅 방지를 위해 비교에서 제외
  var stableJson = json.copy()
  stableJson["generatedAt"] = %""  # 비교 전용 임시 값
  let stableContent = stableJson.pretty(indent = 2)
  let newContent = json.pretty(indent = 2)

  var changed = true
  if fileExists(OutputPath):
    try:
      let existing = readFile(OutputPath)
      # 기존 파일에서도 generatedAt을 제거하고 비교
      let existingJson = parseJson(existing)
      var stableExisting = existingJson
      stableExisting["generatedAt"] = %""
      if stableExisting.pretty(indent = 2) == stableContent:
        changed = false
    except CatchableError:
      discard  # axiom:best-effort(existing metadata read failure)

  if changed:
    let dir = parentDir(OutputPath)
    if not dirExists(dir):
      createDir(dir)
    writeFile(OutputPath, newContent)

  echo "[build_metadata] Wrote " & OutputPath & " (" & $sourceFiles.len & " source files, " &
       $manifestFiles.len & " manifests, " & $runnerFiles.len & " runners)"

main()
