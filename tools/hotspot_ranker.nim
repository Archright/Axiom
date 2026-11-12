import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [].}
## Hotspot Ranker — 기하평균 기반 모듈 우선순위 결정 도구
##
## DEBT_REGISTRY.md + AST 분석 → 기하평균 정렬된 모듈 큐 생성
## 사용법: nim c -r tools/hotspot_ranker.nim

import std/[os, strutils, algorithm, tables]
import shared_types/analysis_bridge

type
  RankedModule = object
    name: string
    metrics: ModuleMetrics
    score: float

proc parseDebtRegistry(path: string): seq[(string, float)] =
  ## DEBT_REGISTRY.md에서 Open 항목의 모듈명과 위험도 추출
  ## 실제 P1 v2 projection 스키마(6컬럼): | ID | Severity | Category | Title | Files | Status |
  result = @[]
  if not fileExists(path): return
  var raw: string
  try: raw = readFile(path)
  except IOError: return
  let lines = raw.splitLines
  for line in lines:
    # Title 셀의 마크다운 이스케이프 파이프(\|)를 치환해 컬럼 위치를 고정
    let sanitized = line.replace("\\|", "\x1f")
    let parts = sanitized.split("|")
    if parts.len < 7: continue
    let status = parts[6].strip
    if not ("Open" in status): continue
    let severity = parts[2].strip.toLowerAscii
    var weight = 1.0
    if "critical" in severity: weight = 3.0
    elif "high" in severity: weight = 2.0
    elif "medium" in severity: weight = 1.5
    # Files 컬럼에서 .nim 경로 추출 (<br> 및 쉼표 구분 다중 파일 지원)
    let fileField = parts[5].strip
    for token in fileField.split("<br>"):
      for sub in token.split(","):
        let f = sub.strip
        if f.len >= 5 and f.endsWith(".nim"):
          result.add((f, weight))

proc countImports(modulePath: string): int =
  ## 모듈을 참조하는 타 모듈의 수 (in-degree) 추정
  ## 간단한 grep 기반 — 정확한 AST 분석은 nimcheck가 담당
  result = 0
  let moduleName = modulePath.extractFilename.changeFileExt("")
  var walker: seq[string]
  try:
    for f in walkDirRec("src/"): walker.add(f)
  except OSError: return
  for nimFile in walker:
    if nimFile.endsWith(".nim") and nimFile != modulePath:
      var content: string
      try: content = readFile(nimFile)
      except IOError: continue
      if moduleName in content:
        result += 1

proc rankModules*(registryPath: string = "docs/DEBT_REGISTRY.md"): seq[RankedModule] =
  ## 기하평균 기반 결정론적 모듈 우선순위 큐 생성
  let debtEntries = parseDebtRegistry(registryPath)

  # 모듈 큐이므로 동일 모듈 중복 제거 — 가장 심각한(최대 가중치) Open 부채로 대표
  var worstWeight: Table[string, float]
  for (modulePath, hotspotWeight) in debtEntries:
    let prev = worstWeight.getOrDefault(modulePath, 0.0)
    if hotspotWeight > prev: worstWeight[modulePath] = hotspotWeight

  var uniq: seq[(string, float)]
  for modulePath, weight in worstWeight: uniq.add((modulePath, weight))
  uniq.sort(proc(a, b: (string, float)): int = cmp(a[0], b[0]))

  var modules: seq[RankedModule] = @[]
  for (modulePath, hotspotWeight) in uniq:
    if not fileExists(modulePath): continue

    var content: string
    try: content = readFile(modulePath)
    except IOError: continue
    let nodeCount = float(content.splitLines.len)  # 줄 수로 근사
    let inDeg = float(countImports(modulePath))

    let metrics = ModuleMetrics(
      hotspotDepth: hotspotWeight,
      astNodeCount: nodeCount,
      inDegree: max(inDeg, 1.0)
    )

    modules.add(RankedModule(
      name: modulePath,
      metrics: metrics,
      score: calculatePriority(metrics)
    ))

  # 기하평균 점수 기준 내림차순 정렬 (동점 시 모듈명 오름차순으로 결정론 고정)
  modules.sort(proc(a, b: RankedModule): int =
    let byScore = cmp(b.score, a.score)
    if byScore != 0: byScore else: cmp(a.name, b.name))
  result = modules

when isMainModule:
  echo "🔬 Axiom Hotspot Ranker — 기하평균 기반 모듈 우선순위"
  echo "═══════════════════════════════════════════════════"

  let ranked = rankModules()

  echo "\n📊 Top-20 Hotspot Modules:"
  echo "───────────────────────────────────────────────────"
  echo alignLeft("#", 3), "  ", alignLeft("Score", 8), "  ",
       alignLeft("H", 5), alignLeft("C", 6), alignLeft("D", 5), "  Module"
  echo "───────────────────────────────────────────────────"

  for i, m in ranked[0 ..< min(20, ranked.len)]:
    echo alignLeft($(i+1), 3), "  ", formatFloat(m.score, ffDecimal, 2).alignLeft(8), "  ",
         formatFloat(m.metrics.hotspotDepth, ffDecimal, 0).alignLeft(5),
         formatFloat(m.metrics.astNodeCount, ffDecimal, 0).alignLeft(6),
         formatFloat(m.metrics.inDegree, ffDecimal, 0).alignLeft(5), "  ", m.name

  echo "\n총 ", ranked.len, "개 모듈 분석 완료."
