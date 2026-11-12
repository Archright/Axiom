import std/[json, os, strutils, times, math]

proc parseArgs(): tuple[input: string, output: string] =
  var inputFile = "data/benchmarks/tier_stats.json"
  var outputFile = "data/benchmarks/report.html"

  var i = 1
  while i <= paramCount():
    let arg = paramStr(i)
    if arg == "--input" and i < paramCount():
      inputFile = paramStr(i + 1)
      inc i
    elif arg == "--output" and i < paramCount():
      outputFile = paramStr(i + 1)
      inc i
    i += 1

  result = (inputFile, outputFile)

type Metrics = object
  tier1: seq[float]
  tier1_5: seq[float]
  tier2: seq[float]
  tier3: seq[float]
  totalCases: int
  failedCount: int
  functionNames: seq[string]
  tierLabels: seq[string]

proc extractMetrics(data: JsonNode): Metrics =
  var m = Metrics(
    tier1: @[], tier1_5: @[], tier2: @[], tier3: @[],
    functionNames: @[], tierLabels: @[]
  )

  let metrics = data["metrics"]
  if metrics.isNil:
    return m

  m.totalCases = data["totalCases"].getInt()
  m.failedCount = data["tierCounts"]["failed"].getInt()

  for item in metrics:
    let tier = item["resolvedTier"].getStr()
    let duration = item["durationMs"].getFloat()
    let fnName = item["functionName"].getStr()

    m.functionNames.add(fnName)

    case tier:
    of "tkTier1_Fast":
      m.tier1.add(duration)
      m.tierLabels.add("Tier 1 (Fast)")
    of "tkTier1_5_Inductive":
      m.tier1_5.add(duration)
      m.tierLabels.add("Tier 1.5 (Inductive)")
    of "tkTier2_LLM":
      m.tier2.add(duration)
      m.tierLabels.add("Tier 2 (LLM)")
    of "tkTier3_Z3":
      m.tier3.add(duration)
      m.tierLabels.add("Tier 3 (Z3)")
    else:
      discard

  result = m

func avg(data: seq[float]): float =
  if data.len == 0: return 0.0
  var sum = 0.0
  for v in data: sum += v
  result = sum / data.len.float

func stddev(data: seq[float]): float =
  if data.len <= 1: return 0.0
  let mean = avg(data)
  var sumSq = 0.0
  for v in data: sumSq += (v - mean) * (v - mean)
  result = sqrt(sumSq / (data.len - 1).float)

func minVal(data: seq[float]): float =
  if data.len == 0: return 0.0
  result = data[0]
  for v in data:
    if v < result: result = v

func maxVal(data: seq[float]): float =
  if data.len == 0: return 0.0
  result = data[0]
  for v in data:
    if v > result: result = v

proc formatJsArray(data: seq[float]): string =
  if data.len == 0: return "[]"
  result = "["
  for i, v in data:
    if i > 0: result.add(", ")
    result.add($v)
  result.add("]")

proc fmt(v: float, decimals: int = 3): string =
  if v == 0.0: return "0.000"
  result = v.formatFloat(ffDefault, decimals)

proc generateHtml(data: JsonNode): string =
  let m = extractMetrics(data)

  let tier1Avg = avg(m.tier1)
  let tier1_5Avg = avg(m.tier1_5)
  let tier2Avg = avg(m.tier2)
  let tier3Avg = avg(m.tier3)

  let tier1Std = stddev(m.tier1)
  let tier1_5Std = stddev(m.tier1_5)
  let tier2Std = stddev(m.tier2)
  let tier3Std = stddev(m.tier3)

  let tier1Min = minVal(m.tier1)
  let tier1_5Min = minVal(m.tier1_5)
  let tier2Min = minVal(m.tier2)
  let tier3Min = minVal(m.tier3)

  let tier1Max = maxVal(m.tier1)
  let tier1_5Max = maxVal(m.tier1_5)
  let tier2Max = maxVal(m.tier2)
  let tier3Max = maxVal(m.tier3)

  let timestamp = now().format("yyyy-MM-dd HH:mm:ss")
  let passCount = m.totalCases - m.failedCount
  let passRate = if m.totalCases > 0: (passCount.float / m.totalCases.float * 100.0) else: 0.0

  let dataObj = "{\n" &
    "\"tier1\": " & formatJsArray(m.tier1) & ",\n" &
    "\"tier1_5\": " & formatJsArray(m.tier1_5) & ",\n" &
    "\"tier2\": " & formatJsArray(m.tier2) & ",\n" &
    "\"tier3\": " & formatJsArray(m.tier3) & ",\n" &
    "\"totalCases\": " & $m.totalCases & ",\n" &
    "\"failedCount\": " & $m.failedCount & ",\n" &
    "\"passCount\": " & $passCount & "\n" &
  "}"

  var csvLines: seq[string] = @[]
  csvLines.add("function_name,tier,duration_ms,status")
  for i, fn in m.functionNames:
    let tierLabel = m.tierLabels[i]
    let dur = if i < m.tier1.len: fmt(m.tier1[i])
              elif i - m.tier1.len < m.tier1_5.len: fmt(m.tier1_5[i - m.tier1.len])
              elif i - m.tier1.len - m.tier1_5.len < m.tier2.len: fmt(m.tier2[i - m.tier1.len - m.tier1_5.len])
              else: fmt(m.tier3[i - m.tier1.len - m.tier1_5.len - m.tier2.len])
    csvLines.add(fn & "," & tierLabel & "," & dur & ",pass")
  let csvData = csvLines.join("\n")

  result = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Axiom 4-Tier Pipeline Performance Report</title>
  <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.7/dist/chart.umd.min.js"></script>
  <script src="https://cdn.jsdelivr.net/npm/chartjs-plugin-zoom@2.2.0/dist/chartjs-plugin-zoom.min.js"></script>
  <style>
    *, *::before, *::after { margin: 0; padding: 0; box-sizing: border-box; }

    :root {
      --bg-body: #0b1120;
      --bg-card: #151f38;
      --bg-card-hover: #1a2645;
      --bg-input: #1e2a47;
      --border: #263453;
      --text-primary: #e8edf5;
      --text-secondary: #8899b4;
      --text-muted: #5a6d8a;
      --accent-blue: #569dff;
      --accent-green: #3dd68c;
      --accent-yellow: #ffc857;
      --accent-red: #ff6b6b;
      --accent-purple: #a78bfa;
      --shadow: rgba(0, 0, 0, 0.4);
      --chart-grid: rgba(255, 255, 255, 0.06);
    }

    .light {
      --bg-body: #f1f5f9;
      --bg-card: #ffffff;
      --bg-card-hover: #f8fafc;
      --bg-input: #e2e8f0;
      --border: #cbd5e1;
      --text-primary: #0f172a;
      --text-secondary: #475569;
      --text-muted: #94a3b8;
      --shadow: rgba(0, 0, 0, 0.08);
      --chart-grid: rgba(0, 0, 0, 0.08);
    }

    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
      background: var(--bg-body);
      color: var(--text-primary);
      padding: 24px 16px;
      transition: background 0.35s ease, color 0.35s ease;
      min-height: 100vh;
      line-height: 1.5;
    }

    .container { max-width: 1440px; margin: 0 auto; }

    header {
      text-align: center;
      margin-bottom: 28px;
      padding: 24px 16px;
      background: linear-gradient(135deg, var(--bg-card) 0%, var(--bg-input) 100%);
      border-radius: 16px;
      border: 1px solid var(--border);
    }

    h1 {
      font-size: clamp(1.3rem, 3vw, 1.8rem);
      font-weight: 700;
      background: linear-gradient(135deg, var(--accent-blue), var(--accent-purple));
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
      background-clip: text;
      letter-spacing: -0.02em;
    }

    .subtitle {
      display: flex;
      justify-content: center;
      align-items: center;
      gap: 12px;
      flex-wrap: wrap;
      margin-top: 8px;
      color: var(--text-secondary);
      font-size: 0.85rem;
    }

    .subtitle .sep { color: var(--text-muted); }

    .control-bar {
      display: flex;
      justify-content: space-between;
      align-items: center;
      flex-wrap: wrap;
      gap: 12px;
      margin-bottom: 24px;
      padding: 12px 16px;
      background: var(--bg-card);
      border-radius: 12px;
      border: 1px solid var(--border);
    }

    .control-group {
      display: flex;
      align-items: center;
      gap: 8px;
    }

    .control-group label {
      font-size: 0.78rem;
      color: var(--text-muted);
      text-transform: uppercase;
      letter-spacing: 0.04em;
      font-weight: 600;
    }

    .btn-group {
      display: flex;
      gap: 3px;
      background: var(--bg-input);
      border-radius: 8px;
      padding: 3px;
    }

    .btn {
      background: transparent;
      border: none;
      color: var(--text-secondary);
      padding: 6px 14px;
      border-radius: 6px;
      cursor: pointer;
      font-size: 0.8rem;
      font-weight: 500;
      transition: all 0.18s ease;
      white-space: nowrap;
    }

    .btn:hover { color: var(--text-primary); background: rgba(255,255,255,0.06); }
    .btn.active {
      background: var(--accent-blue);
      color: #fff;
      box-shadow: 0 2px 8px rgba(86, 157, 255, 0.25);
    }

    .btn-icon {
      display: inline-flex;
      align-items: center;
      gap: 5px;
      background: transparent;
      border: 1px solid var(--border);
      color: var(--text-secondary);
      padding: 6px 14px;
      border-radius: 8px;
      cursor: pointer;
      font-size: 0.8rem;
      font-weight: 500;
      transition: all 0.18s ease;
    }

    .btn-icon:hover {
      border-color: var(--accent-blue);
      color: var(--accent-blue);
      background: rgba(86, 157, 255, 0.08);
    }

    .btn-icon.primary {
      border-color: var(--accent-blue);
      color: var(--accent-blue);
    }
    .btn-icon.primary:hover {
      background: var(--accent-blue);
      color: #fff;
    }

    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(380px, 1fr));
      gap: 20px;
    }

    .card {
      background: var(--bg-card);
      border-radius: 14px;
      padding: 20px;
      border: 1px solid var(--border);
      box-shadow: 0 2px 12px var(--shadow);
      transition: transform 0.2s ease, box-shadow 0.2s ease, border-color 0.2s ease, background 0.35s ease;
    }

    .card:hover {
      border-color: var(--accent-blue);
      box-shadow: 0 4px 24px rgba(86, 157, 255, 0.08);
    }

    .card-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 16px;
    }

    .card h2 {
      font-size: 1rem;
      font-weight: 600;
      color: var(--text-primary);
    }

    .card .badge {
      font-size: 0.7rem;
      padding: 3px 10px;
      border-radius: 20px;
      background: var(--bg-input);
      color: var(--text-muted);
      font-weight: 500;
    }

    .chart-wrap {
      position: relative;
      height: 300px;
    }

    .chart-wrap canvas { width: 100% !important; height: 100% !important; }

    .chart-actions {
      display: flex;
      gap: 6px;
      flex-wrap: wrap;
    }

    .chart-action-btn {
      background: var(--bg-input);
      border: none;
      color: var(--text-muted);
      padding: 4px 10px;
      border-radius: 5px;
      cursor: pointer;
      font-size: 0.7rem;
      transition: all 0.15s ease;
    }

    .chart-action-btn:hover {
      background: var(--accent-blue);
      color: #fff;
    }

    .legend {
      display: flex;
      flex-wrap: wrap;
      gap: 14px;
      margin-top: 14px;
      padding-top: 14px;
      border-top: 1px solid var(--border);
    }

    .legend-item {
      display: flex;
      align-items: center;
      gap: 7px;
      cursor: pointer;
      font-size: 0.8rem;
      color: var(--text-secondary);
      transition: opacity 0.18s ease;
      user-select: none;
    }

    .legend-item:hover { opacity: 0.8; }

    .legend-dot {
      width: 10px;
      height: 10px;
      border-radius: 50%;
      flex-shrink: 0;
    }

    .legend-bar {
      width: 18px;
      height: 4px;
      border-radius: 2px;
      flex-shrink: 0;
    }

    table {
      width: 100%;
      border-collapse: collapse;
      font-size: 0.82rem;
    }

    thead th {
      padding: 8px 10px;
      text-align: left;
      font-weight: 600;
      font-size: 0.72rem;
      text-transform: uppercase;
      letter-spacing: 0.04em;
      color: var(--text-muted);
      border-bottom: 2px solid var(--border);
    }

    tbody td {
      padding: 8px 10px;
      border-bottom: 1px solid var(--border);
      color: var(--text-secondary);
    }

    tbody tr:last-child td { border-bottom: none; }
    tbody tr:hover td { background: rgba(255,255,255,0.02); }

    .stat-val {
      font-family: 'SF Mono', 'Fira Code', 'Cascadia Code', monospace;
      color: var(--accent-green);
      font-weight: 500;
      font-size: 0.82rem;
    }

    .summary-strip {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(110px, 1fr));
      gap: 10px;
      margin-top: 16px;
    }

    .summary-cell {
      background: var(--bg-input);
      padding: 12px 8px;
      border-radius: 10px;
      text-align: center;
    }

    .summary-cell .label {
      font-size: 0.65rem;
      color: var(--text-muted);
      text-transform: uppercase;
      letter-spacing: 0.05em;
      font-weight: 600;
    }

    .summary-cell .value {
      font-size: 1.1rem;
      font-weight: 700;
      color: var(--text-primary);
      margin-top: 4px;
    }

    .summary-cell .value.green { color: var(--accent-green); }
    .summary-cell .value.red { color: var(--accent-red); }
    .summary-cell .value.blue { color: var(--accent-blue); }
    .summary-cell .value.yellow { color: var(--accent-yellow); }

    .card-full { grid-column: 1 / -1; }

    @media (max-width: 820px) {
      .grid { grid-template-columns: 1fr; }
      .card-full { grid-column: 1; }
      .control-bar { flex-direction: column; align-items: stretch; }
      .control-group { justify-content: center; }
      .btn-group { flex-wrap: wrap; }
      body { padding: 12px 8px; }
      .chart-wrap { height: 240px; }
      .summary-strip { grid-template-columns: repeat(2, 1fr); }
    }

    @media (max-width: 480px) {
      .summary-strip { grid-template-columns: 1fr; }
      header { padding: 16px 12px; }
      .card { padding: 14px; }
      h1 { font-size: 1.1rem; }
    }
  </style>
</head>
<body class="dark">
  <div class="container">
    <header>
      <h1>4-Tier Pipeline Performance Report</h1>
      <div class="subtitle">
        <span>""" & timestamp & """</span>
        <span class="sep">|</span>
        <span>""" & $m.totalCases & """ test cases</span>
        <span class="sep">|</span>
        <span style="color:var(--accent-green)">""" & $passCount & """ passed</span>
        <span class="sep">|</span>
        <span style="color:var(--accent-red)">""" & $m.failedCount & """ failed</span>
      </div>
    </header>

    <div class="control-bar">
      <div class="control-group">
        <label>Theme</label>
        <div class="btn-group" id="themeGroup">
          <button class="btn active" data-theme="dark">Dark</button>
          <button class="btn" data-theme="light">Light</button>
        </div>
      </div>
      <div class="control-group">
        <label>Range</label>
        <div class="btn-group" id="rangeGroup">
          <button class="btn active" data-runs="10">10 runs</button>
          <button class="btn" data-runs="30">30 runs</button>
          <button class="btn" data-runs="all">All</button>
        </div>
      </div>
      <div class="control-group">
        <button class="btn-icon primary" id="exportPngBtn">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="2" ry="2"/><circle cx="8.5" cy="8.5" r="1.5"/><polyline points="21 15 16 10 5 21"/></svg>
          Export PNG
        </button>
        <button class="btn-icon" id="exportCsvBtn">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
          Export CSV
        </button>
      </div>
    </div>

    <div class="grid">
      <div class="card">
        <div class="card-header">
          <h2>Latency Trend</h2>
          <span class="badge">ms over runs</span>
        </div>
        <div class="chart-wrap">
          <div class="chart-actions">
            <button class="chart-action-btn" data-action="resetZoom">reset zoom</button>
          </div>
          <canvas id="latencyChart"></canvas>
        </div>
        <div class="legend" id="latencyLegend">
          <div class="legend-item" data-key="tier1">
            <div class="legend-bar" style="background:#3dd68c;"></div>
            Tier 1 (Fast)
          </div>
          <div class="legend-item" data-key="tier1_5">
            <div class="legend-bar" style="background:#569dff;"></div>
            Tier 1.5 (Inductive)
          </div>
          <div class="legend-item" data-key="tier2">
            <div class="legend-bar" style="background:#ffc857;"></div>
            Tier 2 (LLM)
          </div>
          <div class="legend-item" data-key="tier3">
            <div class="legend-bar" style="background:#ff6b6b;"></div>
            Tier 3 (Z3)
          </div>
        </div>
      </div>

      <div class="card">
        <div class="card-header">
          <h2>Average Latency per Tier</h2>
          <span class="badge">mean ms</span>
        </div>
        <div class="chart-wrap">
          <canvas id="barChart"></canvas>
        </div>
      </div>

      <div class="card">
        <div class="card-header">
          <h2>Pass / Fail</h2>
          <span class="badge">""" & $m.totalCases & """ total</span>
        </div>
        <div class="chart-wrap" style="height:260px;">
          <canvas id="pieChart"></canvas>
        </div>
      </div>

      <div class="card card-full">
        <div class="card-header">
          <h2>Detailed Statistics</h2>
          <span class="badge">Min · Max · Avg · StdDev</span>
        </div>
        <div style="overflow-x:auto;">
          <table>
            <thead>
              <tr>
                <th>Tier</th>
                <th>Count</th>
                <th>Min (ms)</th>
                <th>Max (ms)</th>
                <th>Avg (ms)</th>
                <th>StdDev (ms)</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td>Tier 1 (Fast)</td>
                <td class="stat-val">""" & $m.tier1.len & """</td>
                <td class="stat-val">""" & fmt(tier1Min) & """</td>
                <td class="stat-val">""" & fmt(tier1Max) & """</td>
                <td class="stat-val">""" & fmt(tier1Avg) & """</td>
                <td class="stat-val">""" & fmt(tier1Std) & """</td>
              </tr>
              <tr>
                <td>Tier 1.5 (Inductive)</td>
                <td class="stat-val">""" & $m.tier1_5.len & """</td>
                <td class="stat-val">""" & fmt(tier1_5Min) & """</td>
                <td class="stat-val">""" & fmt(tier1_5Max) & """</td>
                <td class="stat-val">""" & fmt(tier1_5Avg) & """</td>
                <td class="stat-val">""" & fmt(tier1_5Std) & """</td>
              </tr>
              <tr>
                <td>Tier 2 (LLM)</td>
                <td class="stat-val">""" & $m.tier2.len & """</td>
                <td class="stat-val">""" & fmt(tier2Min) & """</td>
                <td class="stat-val">""" & fmt(tier2Max) & """</td>
                <td class="stat-val">""" & fmt(tier2Avg) & """</td>
                <td class="stat-val">""" & fmt(tier2Std) & """</td>
              </tr>
              <tr>
                <td>Tier 3 (Z3)</td>
                <td class="stat-val">""" & $m.tier3.len & """</td>
                <td class="stat-val">""" & fmt(tier3Min) & """</td>
                <td class="stat-val">""" & fmt(tier3Max) & """</td>
                <td class="stat-val">""" & fmt(tier3Avg) & """</td>
                <td class="stat-val">""" & fmt(tier3Std) & """</td>
              </tr>
            </tbody>
          </table>
        </div>
        <div class="summary-strip">
          <div class="summary-cell">
            <div class="label">Total Cases</div>
            <div class="value blue">""" & $m.totalCases & """</div>
          </div>
          <div class="summary-cell">
            <div class="label">Pass Rate</div>
            <div class="value green">""" & fmt(passRate, 1) & """%</div>
          </div>
          <div class="summary-cell">
            <div class="label">Failed</div>
            <div class="value red">""" & $m.failedCount & """</div>
          </div>
          <div class="summary-cell">
            <div class="label">Overall Avg</div>
            <div class="value yellow">""" & fmt((avg(m.tier1) + avg(m.tier1_5) + avg(m.tier2) + avg(m.tier3)) / 4.0) & """ ms</div>
          </div>
        </div>
      </div>
    </div>
  </div>

  <script>
    Chart.register(chartjsZoom);

    const DATA = """ & dataObj & """;

    let currentTheme = 'dark';
    let currentRuns = '10';

    const tierColors = {
      tier1: { border: '#3dd68c', bg: 'rgba(61, 214, 140, 0.18)' },
      tier1_5: { border: '#569dff', bg: 'rgba(86, 157, 255, 0.18)' },
      tier2: { border: '#ffc857', bg: 'rgba(255, 200, 87, 0.18)' },
      tier3: { border: '#ff6b6b', bg: 'rgba(255, 107, 107, 0.18)' }
    };

    const tierLabels = ['Tier 1 (Fast)', 'Tier 1.5 (Inductive)', 'Tier 2 (LLM)', 'Tier 3 (Z3)'];
    let visibleTiers = ['tier1', 'tier1_5', 'tier2', 'tier3'];

    function getRunsCount() {
      if (currentRuns === 'all') {
        return Math.max(DATA.tier1.length, DATA.tier1_5.length, DATA.tier2.length, DATA.tier3.length, 1);
      }
      return parseInt(currentRuns);
    }

    function padArray(arr, len) {
      return arr.slice(-len).concat(Array(Math.max(0, len - arr.length)).fill(null));
    }

    function buildDatasets(runs) {
      const keys = ['tier1', 'tier1_5', 'tier2', 'tier3'];
      return keys.map((key, i) => ({
        label: tierLabels[i],
        data: padArray(DATA[key], runs),
        borderColor: tierColors[key].border,
        backgroundColor: tierColors[key].bg,
        fill: true,
        tension: 0.3,
        pointRadius: 3,
        pointHoverRadius: 6,
        pointBackgroundColor: tierColors[key].border,
        hidden: !visibleTiers.includes(key)
      }));
    }

    function getTextColor() {
      return getComputedStyle(document.body).getPropertyValue('--text-secondary').trim();
    }

    function getGridColor() {
      return getComputedStyle(document.body).getPropertyValue('--chart-grid').trim();
    }

    function getCardBg() {
      return getComputedStyle(document.body).getPropertyValue('--bg-card').trim();
    }

    Chart.defaults.color = getTextColor;
    Chart.defaults.borderColor = getGridColor;

    let latencyChart, barChart, pieChart;

    function createLatencyChart() {
      const runs = getRunsCount();
      const ctx = document.getElementById('latencyChart').getContext('2d');
      latencyChart = new Chart(ctx, {
        type: 'line',
        data: {
          labels: Array.from({length: runs}, (_, i) => 'Run ' + (i + 1)),
          datasets: buildDatasets(runs)
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          interaction: {
            mode: 'index',
            intersect: false
          },
          plugins: {
            legend: { display: false },
            tooltip: {
              backgroundColor: 'rgba(0,0,0,0.85)',
              titleColor: '#e8edf5',
              bodyColor: '#8899b4',
              borderColor: 'rgba(255,255,255,0.08)',
              borderWidth: 1,
              padding: 10,
              callbacks: {
                label: function(ctx) {
                  if (ctx.parsed.y === null) return ctx.dataset.label + ': N/A';
                  return ctx.dataset.label + ': ' + ctx.parsed.y.toFixed(3) + ' ms';
                }
              }
            },
            zoom: {
              zoom: {
                wheel: { enabled: true },
                pinch: { enabled: true },
                drag: { enabled: true, backgroundColor: 'rgba(86,157,255,0.12)', borderColor: '#569dff' },
                mode: 'x'
              },
              pan: {
                enabled: true,
                mode: 'x'
              }
            }
          },
          scales: {
            x: {
              grid: { color: getGridColor },
              ticks: { color: getTextColor, maxTicksLimit: 20 }
            },
            y: {
              title: { display: true, text: 'Latency (ms)', color: getTextColor },
              grid: { color: getGridColor },
              ticks: { color: getTextColor },
              beginAtZero: true
            }
          },
          animations: {
            tension: { duration: 600, easing: 'easeInOutQuad' }
          }
        }
      });
    }

    function createBarChart() {
      const ctx = document.getElementById('barChart').getContext('2d');
      const tiers = ['tier1', 'tier1_5', 'tier2', 'tier3'];
      const avgs = tiers.map(k => {
        const d = DATA[k];
        return d.length > 0 ? d.reduce((a, b) => a + b, 0) / d.length : 0;
      });
      barChart = new Chart(ctx, {
        type: 'bar',
        data: {
          labels: ['Tier 1\n(Fast)', 'Tier 1.5\n(Inductive)', 'Tier 2\n(LLM)', 'Tier 3\n(Z3)'],
          datasets: [{
            label: 'Average Latency (ms)',
            data: avgs,
            backgroundColor: ['#3dd68c', '#569dff', '#ffc857', '#ff6b6b'],
            borderRadius: 4,
            borderSkipped: false
          }]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          plugins: {
            legend: { display: false },
            tooltip: {
              backgroundColor: 'rgba(0,0,0,0.85)',
              titleColor: '#e8edf5',
              bodyColor: '#8899b4',
              callbacks: {
                label: function(ctx) {
                  return 'Avg: ' + ctx.parsed.y.toFixed(3) + ' ms';
                }
              }
            }
          },
          scales: {
            x: {
              grid: { display: false },
              ticks: { color: getTextColor }
            },
            y: {
              title: { display: true, text: 'Avg Latency (ms)', color: getTextColor },
              grid: { color: getGridColor },
              ticks: { color: getTextColor },
              beginAtZero: true
            }
          }
        }
      });
    }

    function createPieChart() {
      const ctx = document.getElementById('pieChart').getContext('2d');
      const hasData = DATA.passCount > 0 || DATA.failedCount > 0;
      pieChart = new Chart(ctx, {
        type: 'doughnut',
        data: {
          labels: hasData ? ['Pass', 'Fail'] : ['No Data'],
          datasets: [{
            data: hasData ? [DATA.passCount, DATA.failedCount] : [1],
            backgroundColor: hasData ? ['#3dd68c', '#ff6b6b'] : ['#334155'],
            borderWidth: 0,
            hoverOffset: 8
          }]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          cutout: '60%',
          plugins: {
            legend: {
              position: 'bottom',
              labels: {
                color: getTextColor,
                padding: 16,
                usePointStyle: true,
                pointStyle: 'circle',
                font: { size: 12 }
              }
            },
            tooltip: {
              backgroundColor: 'rgba(0,0,0,0.85)',
              titleColor: '#e8edf5',
              bodyColor: '#8899b4',
              callbacks: {
                label: function(ctx) {
                  const total = ctx.dataset.data.reduce((a, b) => a + b, 0);
                  const pct = total > 0 ? ((ctx.parsed / total) * 100).toFixed(1) : 0;
                  return ctx.label + ': ' + ctx.parsed + ' (' + pct + '%)';
                }
              }
            }
          }
        }
      });
    }

    function updateLatencyChart(runs) {
      if (!latencyChart) return;
      const cnt = runs === 'all' ? Math.max(DATA.tier1.length, DATA.tier1_5.length, DATA.tier2.length, DATA.tier3.length, 1) : parseInt(runs);
      latencyChart.data.labels = Array.from({length: cnt}, (_, i) => 'Run ' + (i + 1));
      latencyChart.data.datasets = buildDatasets(cnt);
      latencyChart.update();
    }

    function toggleTier(key) {
      const idx = visibleTiers.indexOf(key);
      if (idx > -1) {
        visibleTiers.splice(idx, 1);
      } else {
        visibleTiers.push(key);
      }
      const items = document.querySelectorAll('.legend-item[data-key="' + key + '"]');
      items.forEach(el => el.style.opacity = visibleTiers.includes(key) ? '1' : '0.35');
      updateLatencyChart(currentRuns);
    }

    function setTheme(theme) {
      currentTheme = theme;
      document.body.className = theme;
      document.querySelectorAll('#themeGroup .btn').forEach(b => b.classList.toggle('active', b.dataset.theme === theme));
      if (latencyChart) latencyChart.update();
      if (barChart) barChart.update();
      if (pieChart) pieChart.update();
    }

    function setRange(runs) {
      currentRuns = runs;
      document.querySelectorAll('#rangeGroup .btn').forEach(b => b.classList.toggle('active', b.dataset.runs === runs));
      updateLatencyChart(runs);
    }

    function combineChartsToCanvas() {
      const charts = [
        { id: 'latencyChart', label: 'Latency Trend' },
        { id: 'barChart', label: 'Avg Latency per Tier' },
        { id: 'pieChart', label: 'Pass / Fail' }
      ];
      const w = 800;
      const rowH = 300;
      const headerH = 40;
      const gap = 20;
      const totalH = headerH + charts.length * (rowH + gap);

      const canvas = document.createElement('canvas');
      canvas.width = w;
      canvas.height = totalH;
      const ctx = canvas.getContext('2d');

      ctx.fillStyle = getComputedStyle(document.body).getPropertyValue('--bg-body').trim() || '#0b1120';
      ctx.fillRect(0, 0, w, totalH);

      ctx.fillStyle = getComputedStyle(document.body).getPropertyValue('--text-primary').trim() || '#e8edf5';
      ctx.font = 'bold 20px -apple-system, BlinkMacSystemFont, sans-serif';
      ctx.textAlign = 'center';
      ctx.fillText('Axiom 4-Tier Pipeline Performance Report', w / 2, 28);

      charts.forEach((ch, i) => {
        const src = document.getElementById(ch.id);
        if (!src) return;
        const y = headerH + i * (rowH + gap);
        ctx.fillStyle = getComputedStyle(document.body).getPropertyValue('--text-secondary').trim() || '#8899b4';
        ctx.font = '13px -apple-system, sans-serif';
        ctx.textAlign = 'left';
        ctx.fillText(ch.label, 12, y + 16);
        try {
          ctx.drawImage(src, 0, y + 22, w, rowH - 22);
        } catch (e) {
          ctx.fillStyle = '#ff6b6b';
          ctx.fillText('(unavailable)', w / 2, y + rowH / 2);
        }
      });
      return canvas;
    }

    function exportPng() {
      const cvs = combineChartsToCanvas();
      const link = document.createElement('a');
      link.download = 'axiom_performance_report.png';
      link.href = cvs.toDataURL('image/png');
      link.click();
    }

    function exportCsv() {
      const csv = `""" & csvData & """`;
      const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
      const link = document.createElement('a');
      link.href = URL.createObjectURL(blob);
      link.download = 'axiom_performance_data.csv';
      link.click();
      URL.revokeObjectURL(link.href);
    }

    document.addEventListener('DOMContentLoaded', function() {
      createLatencyChart();
      createBarChart();
      createPieChart();

      document.querySelectorAll('#themeGroup .btn').forEach(btn => {
        btn.addEventListener('click', function() { setTheme(this.dataset.theme); });
      });

      document.querySelectorAll('#rangeGroup .btn').forEach(btn => {
        btn.addEventListener('click', function() { setRange(this.dataset.runs); });
      });

      document.querySelectorAll('#latencyLegend .legend-item').forEach(item => {
        item.addEventListener('click', function() { toggleTier(this.dataset.key); });
      });

      document.querySelector('[data-action="resetZoom"]').addEventListener('click', function() {
        if (latencyChart) latencyChart.resetZoom();
      });

      document.getElementById('exportPngBtn').addEventListener('click', exportPng);
      document.getElementById('exportCsvBtn').addEventListener('click', exportCsv);
    });
  </script>
</body>
</html>"""

proc main() =
  let (inputFile, outputFile) = parseArgs()

  if not fileExists(inputFile):
    echo "[perf_visualizer] Error: Input file not found: ", inputFile
    quit(1)

  let content = readFile(inputFile)
  let data = parseJson(content)

  let outputDir = outputFile.parentDir()
  if outputDir.len > 0 and not dirExists(outputDir):
    createDir(outputDir)

  let html = generateHtml(data)
  writeFile(outputFile, html)

  echo "[perf_visualizer] Report generated: ", outputFile

when isMainModule:
  main()
