## tools/release/bundle_tool.nim — §1b Binary Distribution Contract 조립·검증 도구 (Phase 6 S3)
##
## 정본 계약: docs/spec/productization_contract.md §1b "배포 자산".
##   * bundle tar.gz: ax(번들 루트 직접 배치 — bin/ 하위 배치 시 SourceCoherence
##     FATAL, verify가 명시 거부) + config/spec/ + data/verification_scope.lock ·
##     data/baseline.json · data/bug_attribution/ + 루트 앵커 .axiom_root +
##     SAL 1.0 §6.1 파일(LICENSE · LICENSES/ · THIRD-PARTY-NOTICES.md)
##   * SHA256SUMS + manifest.json(버전 · 원본 소스 커밋 · 빌드 SHA · 바이너리 sha256)
##   * attestation-bundle.jsonl은 attest 단계(release-ship attest-bundle 잡)가
##     GitHub artifact attestation에서 산출하고, verify --attestation-bundle이
##     오프라인 `--bundle` + `--signer-repo Archright/Axiom` 핀으로 검증한다(§1b 신뢰 모델).
##
## 결정성: 같은 입력 → 같은 바이트.
##   * tar: --sort=name --owner=0 --group=0 --numeric-owner --mtime='@0' --format=gnu
##   * gzip: -n(이름/타임스탬프 미기록) 고정 레벨 9 — tar·gzip을 파일 경유
##     2단계 실행한다(셸 파이프는 마지막 명령 exit만 전파하는 함정이 있다)
##   * manifest.json: 고정 키 순서(std/json JObject 삽입 순서) + 타임스탬프 무삽입
##   * assemble은 조립을 2회 수행해 tar.gz 바이트를 cmp 단언한다(동일 환경 내
##     주장 — tar/gzip 버전이 다른 환경 간 바이트 동일성은 주장하지 않는다.
##     페이로드 결속은 manifest binarySha256/bundleSha256이 권위다).
##
## fail-closed: 입력 부재 · nimble 버전≠태그 · 바이너리 sha256 불일치 · tracked
## 입력 dirty · 2회 조립 불일치 · 검증 축 하나라도 불일치 → exit 1. 사용법 오류 → exit 2.
##
## 사용법:
##   bundle_tool assemble --repo-root <dir> --binary <path/to/ax> \
##     --expected-binary-sha256 <64hex> --version v0.6.0 \
##     --source-commit <40hex> --build-sha <40hex> --out-dir <dir>
##   bundle_tool verify --dir <asset-dir> --extract-to <dir> \
##     [--repo-root <dir>] [--expect-version <vX.Y.Z>] \
##     [--expect-source-commit <40hex>] [--expect-build-sha <40hex>] \
##     [--run-binary] [--attestation-bundle <file>]
##
## 컴파일 (release-ship verify-metadata의 게이트 컴파일과 동일 플래그):
##   CH="$(nimble path checksums | head -1)"
##   nim c --hints:off --skipParentCfg --skipProjCfg \
##     --path:src --path:tools --path:"$CH" -o:bin/bundle_tool tools/release/bundle_tool.nim

import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [CatchableError].}

import std/[os, osproc, strutils, json, algorithm, sets, tables, sequtils]
import checksums/sha2

const
  Tag = "[BUNDLE_TOOL]"
  SchemaVersion = "axiom.release-bundle.manifest.v1"
  Product = "axiom-cli"
  Platform = "linux-x86_64"
  SourceRepository = "Archright/Axiom"
  ExitOk = 0
  ExitFail = 1
  ExitUsage = 2
  ## §1b 번들이 반드시 운반하는 tracked 입력 경로.
  BundleInputPaths = [
    ".axiom_root",
    "config/spec",
    "data/verification_scope.lock",
    "data/baseline.json",
    "data/bug_attribution",
    "LICENSE",
    "LICENSES",
    "THIRD-PARTY-NOTICES.md",
  ]
  ## 부재 시 조립 불가한 필수 파일 (§1b 명시 열거).
  BundleRequiredFiles = [
    ".axiom_root",
    "data/verification_scope.lock",
    "data/baseline.json",
    "LICENSE",
    "THIRD-PARTY-NOTICES.md",
  ]
  FilePerms = {fpUserRead, fpUserWrite, fpGroupRead, fpOthersRead}       # 0644
  ExecPerms = {fpUserRead, fpUserWrite, fpUserExec, fpGroupRead, fpGroupExec,
               fpOthersRead, fpOthersExec}                                # 0755

proc fail*(msg: string) {.noreturn.} =
  stderr.writeLine(Tag & " FAIL — " & msg & " (fail-closed)")
  quit(ExitFail)

proc usageError*(msg: string) {.noreturn.} =
  stderr.writeLine(Tag & " USAGE — " & msg)
  stderr.writeLine("usage: bundle_tool assemble|verify <flags> (see file header)")
  quit(ExitUsage)

proc ok*(msg: string) =
  stdout.writeLine(Tag & " " & msg)

# ── 공용 프리미티브 ─────────────────────────────────────────────────────

proc fileSha256*(path: string): string {.raises: [CatchableError].} =
  ## sha256 hex(소문자) — checksums/sha2 (파일 전체를 openArray[char]로 해시).
  toLowerAscii($Sha_256.secureHash(readFile(path)))

proc runCmd*(cmd: string; workingDir = ""): tuple[output: string, exitCode: int] =
  ## 셸 경유 명령 실행(stderr 병합 — 실패 출력이 곧 진단).
  try:
    execCmdEx(cmd, {poStdErrToStdOut, poUsePath}, nil, workingDir, "")
  except CatchableError as e:
    (e.msg, -1)

proc mustRun*(cmd, what: string; workingDir = ""): string =
  let (outp, code) = runCmd(cmd, workingDir)
  if code != 0:
    stderr.writeLine(outp)
    fail(what & " failed (rc=" & $code & "): " & cmd)
  outp

proc isHexLower*(s: string; n: int): bool =
  if s.len != n: return false
  for c in s:
    if c notin {'0'..'9', 'a'..'f'}: return false
  true

proc isValidVersionTag*(t: string): bool =
  ## ^v\d+\.\d+\.\d+$ (수동 검사 — 정규식 의존 없음).
  if not t.startsWith("v"): return false
  let parts = t[1..^1].split('.')
  if parts.len != 3: return false
  for p in parts:
    if p.len == 0: return false
    for c in p:
      if c notin {'0'..'9'}: return false
  true

proc topDirFor*(tag: string): string = "axiom-" & tag & "-" & Platform
proc tarNameFor*(tag: string): string = "axiom-bundle-" & tag & "-" & Platform & ".tar.gz"

proc parseArgs*(argv: seq[string]): tuple[sub: string, flags: Table[string, string], switches: HashSet[string]] =
  ## --key value 플래그와 단독 스위치를 파싱한다.
  if argv.len == 0: usageError("subcommand required (assemble|verify)")
  result.sub = argv[0]
  var i = 1
  while i < argv.len:
    let a = argv[i]
    if a.startsWith("--"):
      let key = a[2..^1]
      if key.len == 0: usageError("empty flag")
      if i + 1 < argv.len and not argv[i + 1].startsWith("--"):
        result.flags[key] = argv[i + 1]
        inc i
      else:
        result.switches.incl(key)
    else:
      usageError("unexpected positional argument '" & a & "'")
    inc i

# ── assemble ────────────────────────────────────────────────────────────

proc parseNimbleVersion*(repoRoot: string): string {.raises: [CatchableError].} =
  for line in readFile(repoRoot / "axiom.nimble").splitLines():
    let s = line.strip()
    if s.startsWith("version"):
      let eq = s.find('=')
      if eq >= 0:
        return s[eq + 1..^1].strip().strip(chars = {'"', '\''})
  ""

proc gitLsFilesCmd*(repoRoot: string): string =
  "git -C '" & repoRoot & "' ls-files -- " &
    BundleInputPaths.mapIt("'" & it & "'").join(" ")

proc gitDiffQuietCmd*(repoRoot: string): string =
  "git -C '" & repoRoot & "' diff --quiet HEAD -- " &
    BundleInputPaths.mapIt("'" & it & "'").join(" ")

proc trackedInputFiles*(repoRoot: string): seq[string] =
  let outp = mustRun(gitLsFilesCmd(repoRoot), "git ls-files")
  for line in outp.splitLines():
    if line.len > 0: result.add(line)

proc setDirPermsRec*(root: string) {.raises: [CatchableError].} =
  setFilePermissions(root, ExecPerms)
  for kind, p in walkDir(root):
    if kind == pcDir:
      setDirPermsRec(p)

proc stageBundle*(repoRoot, binary, topDir: string; tracked: seq[string]; stageRoot: string) {.raises: [CatchableError].} =
  removeDir(stageRoot)
  createDir(stageRoot / topDir)
  for f in tracked:
    let src = repoRoot / f
    if not fileExists(src):
      fail("tracked input '" & f & "' missing on disk (fs≠index — clean checkout required)")
    createDir(stageRoot / topDir / f.parentDir())
    copyFile(src, stageRoot / topDir / f)
    setFilePermissions(stageRoot / topDir / f, FilePerms)
  # §1b: ax는 번들 루트에 직접 배치(bin/ 하위 배치 금지 — verify가 거부).
  copyFile(binary, stageRoot / topDir / "ax")
  setFilePermissions(stageRoot / topDir / "ax", ExecPerms)
  setDirPermsRec(stageRoot / topDir)

proc makeTarGz*(stageRoot, topDir, plainTarPath, outPath: string) =
  ## tar → gzip 2단계(파일 경유): 셸 파이프는 마지막 명령 exit만 전파하므로
  ## tar 실패가 gzip 성공에 묻히지 않게 각 exit를 독립 검증한다. gzip 출력은
  ## 셸 리다이렉션으로 직접 파일에 기록한다 — 프로세스 stdout을 문자열로
  ## 캡처하는 경로는 바이너리 페이로드를 손상시킨다(실측: tar -tzf가
  ## "invalid compressed data"로 실패).
  discard mustRun(
    "tar --sort=name --owner=0 --group=0 --numeric-owner --mtime='@0' --format=gnu" &
      " -cf '" & plainTarPath & "' -C '" & stageRoot & "' '" & topDir & "'",
    "tar (deterministic)")
  discard mustRun("gzip -n -9 -c '" & plainTarPath & "' > '" & outPath & "'", "gzip -n -9")

proc writeManifest*(outDir, tarName, tag, ver, sourceCommit, buildSha, binSha, bundleSha: string) =
  let m = %*{
    "schemaVersion": SchemaVersion,
    "product": Product,
    "version": ver,
    "tag": tag,
    "platform": Platform,
    "sourceRepository": SourceRepository,
    "sourceCommit": sourceCommit,
    "buildSha": buildSha,
    "binarySha256": binSha,
    "bundlePath": tarName,
    "bundleSha256": bundleSha,
  }
  writeFile(outDir / "manifest.json", m.pretty() & "\n")

proc runAssemble*(argv: seq[string]) =
  let args = parseArgs(argv)
  if args.sub != "assemble": usageError("internal: runAssemble with '" & args.sub & "'")
  let repoRoot = args.flags.getOrDefault("repo-root")
  let binary = args.flags.getOrDefault("binary")
  let expectedBinSha = args.flags.getOrDefault("expected-binary-sha256")
  let sourceCommit = args.flags.getOrDefault("source-commit")
  let buildSha = args.flags.getOrDefault("build-sha")
  let outDir = args.flags.getOrDefault("out-dir")
  let versionRaw = args.flags.getOrDefault("version")
  if repoRoot.len == 0: usageError("assemble: --repo-root required")
  if binary.len == 0: usageError("assemble: --binary required")
  if expectedBinSha.len == 0: usageError("assemble: --expected-binary-sha256 required")
  if sourceCommit.len == 0: usageError("assemble: --source-commit required")
  if buildSha.len == 0: usageError("assemble: --build-sha required")
  if outDir.len == 0: usageError("assemble: --out-dir required")
  if versionRaw.len == 0: usageError("assemble: --version required")

  if not dirExists(repoRoot): fail("--repo-root '" & repoRoot & "' is not a directory")
  if not fileExists(binary): fail("--binary '" & binary & "' is not a file")
  if not fileExists(repoRoot / "axiom.nimble"): fail("axiom.nimble missing under repo root")
  if not getFilePermissions(binary).contains(fpUserExec): fail("--binary is not executable")

  # 태그 = nimble 버전 (§1b) — release-ship verify-metadata 게이트와 동일 규칙의 지역 재단언.
  var tag = versionRaw.strip()
  if not tag.startsWith("v"): tag = "v" & tag
  if not isValidVersionTag(tag):
    fail("version '" & tag & "' does not match ^v[0-9]+\\.[0-9]+\\.[0-9]+$")
  let ver = tag[1..^1]
  let nimbleVer = parseNimbleVersion(repoRoot)
  if nimbleVer.len == 0: fail("axiom.nimble version line not found")
  if nimbleVer != ver:
    fail("axiom.nimble version '" & nimbleVer & "' != release version '" & ver & "' (§1b: tag = nimble version)")

  if not isHexLower(sourceCommit, 40): fail("--source-commit '" & sourceCommit & "' is not 40-hex lowercase")
  if not isHexLower(buildSha, 40): fail("--build-sha '" & buildSha & "' is not 40-hex lowercase")
  if not isHexLower(expectedBinSha, 64): fail("--expected-binary-sha256 is not 64-hex lowercase")
  let actualBinSha = fileSha256(binary)
  if actualBinSha != expectedBinSha:
    fail("binary sha256 '" & actualBinSha & "' != expected '" & expectedBinSha & "' (L2 build chain broken)")

  let tracked = trackedInputFiles(repoRoot)
  if tracked.len == 0: fail("git ls-files returned no bundle input files")
  for rf in BundleRequiredFiles:
    if rf notin tracked:
      fail("required §1b bundle input '" & rf & "' not tracked (git ls-files)")
  var specCount = 0
  for f in tracked:
    if f.startsWith("config/spec/"): inc specCount
  if specCount < 1: fail("config/spec/ has no tracked files")

  # tracked 입력의 작업 트리 변경 거부 — 번들은 커밋된(frozen) 트리 내용물.
  let (_, diffCode) = runCmd(gitDiffQuietCmd(repoRoot))
  if diffCode != 0:
    fail("bundle input paths have uncommitted modifications — assemble from a clean checkout of the frozen tree")

  let topDir = topDirFor(tag)
  let tarName = tarNameFor(tag)
  let work = getTempDir() / ("bundle-tool-" & $getCurrentProcessId())
  createDir(work)
  defer: removeDir(work)

  stageBundle(repoRoot, binary, topDir, tracked, work / "stage-a")
  makeTarGz(work / "stage-a", topDir, work / "plain-a.tar", work / "a.tar.gz")
  stageBundle(repoRoot, binary, topDir, tracked, work / "stage-b")
  makeTarGz(work / "stage-b", topDir, work / "plain-b.tar", work / "b.tar.gz")
  if readFile(work / "a.tar.gz") != readFile(work / "b.tar.gz"):
    fail("determinism self-check: two assemblies differ byte-wise (same inputs must produce identical tar.gz)")

  let bundleSha = fileSha256(work / "a.tar.gz")
  createDir(outDir)
  copyFile(work / "a.tar.gz", outDir / tarName)
  writeManifest(outDir, tarName, tag, ver, sourceCommit, buildSha, expectedBinSha, bundleSha)

  # SHA256SUMS — 배포 자산(바이트 확정 순서) 커버. attestation-bundle.jsonl은
  # 제외: GitHub 서명 이후 산출되고 스스로 서명으로 인증된다(subject digest 결속).
  let sums = fileSha256(outDir / tarName) & "  " & tarName & "\n" &
             fileSha256(outDir / "manifest.json") & "  manifest.json\n"
  writeFile(outDir / "SHA256SUMS", sums)

  ok("OK — §1b bundle assembled (determinism self-check passed)")
  ok("bundle: " & outDir / tarName)
  ok("bundleSha256: " & bundleSha)
  ok("binarySha256: " & expectedBinSha)
  ok("version: " & tag & " (axiom.nimble=" & nimbleVer & ")")
  ok("sourceCommit: " & sourceCommit & "  buildSha: " & buildSha)
  ok("payload: ax + " & $tracked.len & " tracked inputs (.axiom_root + config/spec(" &
     $specCount & ") + data + licenses)")
  quit(ExitOk)

# ── verify ──────────────────────────────────────────────────────────────

proc runVerify*(argv: seq[string]) =
  let args = parseArgs(argv)
  if args.sub != "verify": usageError("internal: runVerify with '" & args.sub & "'")
  let assetDir = args.flags.getOrDefault("dir")
  let extractTo = args.flags.getOrDefault("extract-to")
  if assetDir.len == 0: usageError("verify: --dir required")
  if extractTo.len == 0: usageError("verify: --extract-to required")
  if not dirExists(assetDir): usageError("verify: --dir '" & assetDir & "' is not a directory")

  let manifestPath = assetDir / "manifest.json"
  if not fileExists(assetDir / "SHA256SUMS"): fail("SHA256SUMS missing in '" & assetDir & "'")
  if not fileExists(manifestPath): fail("manifest.json missing in '" & assetDir & "'")

  # 1. manifest 스키마·필드.
  var m: JsonNode
  try:
    m = parseJson(readFile(manifestPath))
  except CatchableError as e:
    fail("manifest.json is not valid JSON: " & e.msg)
  if m.kind != JObject or m.getOrDefault("schemaVersion").getStr() != SchemaVersion:
    fail("manifest.schemaVersion != '" & SchemaVersion & "'")
  for field in ["product", "version", "tag", "platform", "sourceRepository", "sourceCommit",
                "buildSha", "binarySha256", "bundlePath", "bundleSha256"]:
    let v = m.getOrDefault(field)
    if v.isNil or v.kind != JString or v.getStr().len == 0:
      fail("manifest." & field & " missing or not a non-empty string")
  let mTag = m["tag"].getStr()
  let mVer = m["version"].getStr()
  let mSourceCommit = m["sourceCommit"].getStr()
  let mBuildSha = m["buildSha"].getStr()
  let mBinarySha = m["binarySha256"].getStr()
  let mBundlePath = m["bundlePath"].getStr()
  let mBundleSha = m["bundleSha256"].getStr()
  if not isValidVersionTag(mTag): fail("manifest.tag '" & mTag & "' malformed")
  if mTag != "v" & mVer: fail("manifest.tag '" & mTag & "' != v + version '" & mVer & "'")
  if not isHexLower(mSourceCommit, 40): fail("manifest.sourceCommit malformed")
  if not isHexLower(mBuildSha, 40): fail("manifest.buildSha malformed")
  if not isHexLower(mBinarySha, 64): fail("manifest.binarySha256 malformed")
  if not isHexLower(mBundleSha, 64): fail("manifest.bundleSha256 malformed")
  if "expect-version" in args.flags:
    var ev = args.flags["expect-version"]
    if not ev.startsWith("v"): ev = "v" & ev
    if ev != mTag: fail("expected version '" & ev & "' != manifest.tag '" & mTag & "'")
  if "expect-source-commit" in args.flags and args.flags["expect-source-commit"] != mSourceCommit:
    fail("expected source commit != manifest.sourceCommit '" & mSourceCommit & "'")
  if "expect-build-sha" in args.flags and args.flags["expect-build-sha"] != mBuildSha:
    fail("expected build sha != manifest.buildSha '" & mBuildSha & "'")

  let tarball = assetDir / mBundlePath
  if not fileExists(tarball): fail("bundle tarball '" & mBundlePath & "' missing in asset dir")

  # 2. SHA256SUMS 재검증 (sha256sum -c와 동일 의미 — GNU 2-space 형식).
  var sumsLines = 0
  for line in readFile(assetDir / "SHA256SUMS").splitLines():
    if line.strip().len == 0: continue
    inc sumsLines
    let parts = line.splitWhitespace()
    if parts.len != 2: fail("SHA256SUMS line malformed: '" & line & "'")
    if not fileExists(assetDir / parts[1]): fail("SHA256SUMS references missing file '" & parts[1] & "'")
    if fileSha256(assetDir / parts[1]) != parts[0]:
      fail("sha256 mismatch for '" & parts[1] & "' (SHA256SUMS re-verification)")
  if sumsLines < 2: fail("SHA256SUMS covers fewer than 2 assets (expected: bundle + manifest)")

  # 3. manifest ↔ bundle 바이트 결속.
  if fileSha256(tarball) != mBundleSha:
    fail("manifest.bundleSha256 '" & mBundleSha & "' != measured tar.gz sha256")

  # 4. tar 목록 정적 레이아웃 검사 (§1b).
  let listing = mustRun("tar -tzf '" & tarball & "'", "tar -tzf").splitLines().filterIt(it.len > 0)
  let topDir = topDirFor(mTag)
  var topCount = 0
  for e in listing:
    let stripped = if e.endsWith("/"): e[0..^2] else: e
    if not stripped.contains('/'): inc topCount
  if topCount != 1:
    fail("tarball has " & $topCount & " top-level entries (expected exactly 1: '" & topDir & "/')")
  var haveTop = false
  for e in listing:
    if e == topDir & "/": haveTop = true
  if not haveTop: fail("top-level entry '" & topDir & "/' not found in tar listing")
  let fileList = listing.filterIt(not it.endsWith("/"))
  proc hasExact(p: string): bool = fileList.contains(topDir & "/" & p)
  if not hasExact("ax"): fail("§1b: ax not directly at bundle root ('" & topDir & "/ax')")
  for e in fileList:
    if e.startsWith(topDir & "/bin/"):
      fail("§1b: bundle contains a bin/ subtree — ax must sit at the bundle root (bin/ placement = SourceCoherence FATAL)")
  if not hasExact(".axiom_root"): fail("§1b: root anchor .axiom_root missing")
  if not hasExact("LICENSE"): fail("§1b/SAL §6.1: LICENSE missing")
  if not hasExact("THIRD-PARTY-NOTICES.md"): fail("§1b/SAL §6.1: THIRD-PARTY-NOTICES.md missing")
  var hasLicenseDir = false
  for e in fileList:
    if e.startsWith(topDir & "/LICENSES/") and e.count('/') == 2: hasLicenseDir = true
  if not hasLicenseDir: fail("§1b/SAL §6.1: LICENSES/ empty or missing")
  var specEntries = 0
  for e in fileList:
    if e.startsWith(topDir & "/config/spec/") and e.count('/') == 3: inc specEntries
  if specEntries < 1: fail("§1b: config/spec/ has no documents in the bundle")
  if not hasExact("data/verification_scope.lock"): fail("§1b: data/verification_scope.lock missing")
  if not hasExact("data/baseline.json"): fail("§1b: data/baseline.json missing")
  var hasBugAttr = false
  for e in fileList:
    if e.startsWith(topDir & "/data/bug_attribution/") and e.count('/') == 3: hasBugAttr = true
  if not hasBugAttr: fail("§1b: data/bug_attribution/ empty or missing")

  # 5. 해제 + 해시 결속 + config/spec JSON 유효성.
  removeDir(extractTo)
  createDir(extractTo)
  discard mustRun("tar -xzf '" & tarball & "' -C '" & extractTo & "'", "tar -xzf")
  let exTop = extractTo / topDir
  if not dirExists(exTop): fail("extracted top-level directory missing: '" & exTop & "'")
  if not fileExists(exTop / "ax"): fail("extracted ax missing")
  if not getFilePermissions(exTop / "ax").contains(fpUserExec):
    fail("extracted ax is not executable (tar must preserve 0755)")
  let actualBinSha = fileSha256(exTop / "ax")
  if actualBinSha != mBinarySha:
    fail("manifest.binarySha256 '" & mBinarySha & "' != measured extracted ax sha256 '" & actualBinSha & "'")
  for f in walkFiles(exTop / "config/spec" / "*.json"):
    if not f.endsWith(".json"): continue
    try:
      discard parseJson(readFile(f))
    except CatchableError as e:
      fail("config/spec/" & f.extractFilename() & " is not valid JSON: " & e.msg)

  # 6. 트리와의 완전 동치 (릴리즈 빌드 측 전수 대조 — 고객측은 미제공).
  if "repo-root" in args.flags:
    let repoRoot = args.flags["repo-root"]
    if not dirExists(repoRoot): usageError("--repo-root '" & repoRoot & "' is not a directory")
    let tracked = trackedInputFiles(repoRoot)
    var expected = tracked.mapIt(topDir & "/" & it)
    expected.add(topDir & "/ax")
    sort(expected, system.cmp[string])
    var actual = fileList
    sort(actual, system.cmp[string])
    if expected != actual:
      var diff = "bundle file set != repo tracked §1b input set + ax:"
      let actualSet = actual.toHashSet()
      for e in expected:
        if e notin actualSet: diff.add("\n  missing-in-bundle: " & e)
      let expectedSet = expected.toHashSet()
      for a in actual:
        if a notin expectedSet: diff.add("\n  unexpected-in-bundle: " & a)
      fail(diff)
    for tf in tracked:
      if readFile(repoRoot / tf) != readFile(exTop / tf):
        fail("bundle payload '" & tf & "' differs from the repo tracked file (byte inequality)")
    let (_, diffCode2) = runCmd(gitDiffQuietCmd(repoRoot))
    if diffCode2 != 0:
      fail("--repo-root tree has uncommitted modifications to §1b inputs — comparison base is not the frozen tree")
    ok("tree-equality: bundle payload == repo tracked §1b inputs (byte-exact, set-exact)")

  # 7. 실실행 (번들 루트에서 ./ax --version) — libpcre3 dlopen 의존 포함.
  if "run-binary" in args.switches:
    let (vOut, vCode) = runCmd("./ax --version", workingDir = exTop)
    if vCode != 0:
      stderr.writeLine(vOut)
      fail("./ax --version failed inside the extracted bundle (rc=" & $vCode & ")")
    let first = vOut.splitLines().filterIt(it.len > 0)
    if first.len == 0 or first[0].strip() != mTag:
      fail("./ax --version printed '" & (if first.len > 0: first[0].strip() else: "") &
           "' != manifest tag '" & mTag & "'")
    ok("runtime: ./ax --version == " & mTag & " (executed at bundle root)")

  # 8. 오프라인 attestation 검증 (§1b 신뢰 모델 — gh는 --bundle 모드에서도
  #    owner/repo 플래그 그룹을 요구한다(실측). --signer-repo 핀이 서명자 경계).
  if "attestation-bundle" in args.flags:
    let att = args.flags["attestation-bundle"]
    if not fileExists(att): usageError("--attestation-bundle file '" & att & "' not found")
    let (aOut, aCode) = runCmd(
      "gh attestation verify '" & tarball & "' --bundle '" & att &
      "' --repo " & SourceRepository & " --signer-repo " & SourceRepository)
    if aCode != 0:
      stderr.writeLine(aOut)
      fail("offline attestation verification failed (--bundle + --signer-repo " & SourceRepository & " pin)")
    ok("attestation: offline --bundle verify OK (signer repo pinned: " & SourceRepository & ")")

  ok("PASS — SHA256SUMS, manifest↔bundle↔binary binding, §1b layout verified" &
     (if "repo-root" in args.flags: ", tree equality" else: "") &
     (if "attestation-bundle" in args.flags: ", offline attestation" else: "") &
     (if "run-binary" in args.switches: ", runtime" else: ""))
  quit(ExitOk)

when isMainModule:
  let argv = commandLineParams()
  if argv.len == 0: usageError("subcommand required (assemble|verify)")
  case argv[0]
  of "assemble": runAssemble(argv)
  of "verify": runVerify(argv)
  else: usageError("unknown subcommand '" & argv[0] & "'")
{.pop.}
