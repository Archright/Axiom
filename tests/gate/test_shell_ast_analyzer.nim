{.push raises: [CatchableError].}

## Test suite for shell_ast_analyzer — AST-based shell command analysis
##
## Tests cover:
## - False positive elimination (commands that SHOULD be allowed)
## - True positive maintenance (commands that SHOULD be blocked)
## - Security hardening (new attack vectors that MUST be blocked)
##
## Run: nim c -r tests/gate/test_shell_ast_analyzer.nim

import std/unittest
import std/strutils
import std/tables
import ../../src/gate/utils/shell_ast_analyzer

suite "shell_ast_analyzer":

  # ── False Positive Elimination (ALLOW) ────────────────────────────────────

  test "echo $HOME — environment variable as argument to safe output command":
    let r = analyzeCommand("echo $HOME")
    check r.status == asSafe

  test "echo ${PWD} — braced variable expansion":
    let r = analyzeCommand("echo ${PWD}")
    check r.status == asSafe

  test "echo $(date) — safe command substitution in safe output command":
    let r = analyzeCommand("echo $(date)")
    check r.status == asSafe

  test "a=$(cat file) — assignment with safe command substitution":
    let r = analyzeCommand("a=$(cat file)")
    check r.status == asSafe

  test "echo $((1+1)) — arithmetic expansion":
    let r = analyzeCommand("echo $((1+1))")
    check r.status == asSafe

  test "cat /tmp/file — safe read-only command":
    let r = analyzeCommand("cat /tmp/file")
    check r.status == asSafe

  test "grep -r pattern . — grep with flags":
    let r = analyzeCommand("grep -r pattern .")
    check r.status == asSafe

  test "ls -la /path — ls with flags":
    let r = analyzeCommand("ls -la /path")
    check r.status == asSafe

  test "wc -l file — wc with flags":
    let r = analyzeCommand("wc -l file")
    check r.status == asSafe

  test "find . -name '*.nim' — find with safe flags only":
    let r = analyzeCommand("find . -name '*.nim'")
    check r.status == asSafe

  test "date — simple builtin":
    let r = analyzeCommand("date")
    check r.status == asSafe

  test "pwd — simple builtin":
    let r = analyzeCommand("pwd")
    check r.status == asSafe

  test "head -n 10 file — head with flags":
    let r = analyzeCommand("head -n 10 file")
    check r.status == asSafe

  test "tail -n 10 file — tail with flags":
    let r = analyzeCommand("tail -n 10 file")
    check r.status == asSafe

  test "sort file — sort command":
    let r = analyzeCommand("sort file")
    check r.status == asSafe

  test "uname -a — uname with flags":
    let r = analyzeCommand("uname -a")
    check r.status == asSafe

  test "which nim — which command":
    let r = analyzeCommand("which nim")
    check r.status == asSafe

  # ── True Positive Maintenance (BLOCK) ─────────────────────────────────────

  test "eval $X — always blocked command":
    let r = analyzeCommand("eval $X")
    check r.status != asSafe

  test "exec cmd — always blocked command":
    let r = analyzeCommand("exec cmd")
    check r.status != asSafe

  test "source script.sh — always blocked command":
    let r = analyzeCommand("source script.sh")
    check r.status != asSafe

  test "bash -c $CMD — interpreter with non-literal -c argument":
    let r = analyzeCommand("bash -c $CMD")
    check r.status != asSafe

  test "sh -c $CMD — interpreter with non-literal -c argument":
    let r = analyzeCommand("sh -c $CMD")
    check r.status != asSafe

  test "python -c $CODE — interpreter with non-literal -c argument":
    let r = analyzeCommand("python -c $CODE")
    check r.status != asSafe

  test "for f in $(curl http://x); do echo $f; done — loop with network cmdsubst":
    let r = analyzeCommand("for f in $(curl http://x); do echo $f; done")
    check r.status != asSafe

  test "while read l; do $l; done — variable executed as command":
    let r = analyzeCommand("while read l; do $l; done")
    check r.status != asSafe

  # ── Security Hardening: GTFOBins (BLOCK) ──────────────────────────────────

  test "find . -exec rm {} ; — find with -exec":
    let r = analyzeCommand("find . -exec rm {} \\;")
    check r.status != asSafe

  test "find . -delete — find with -delete":
    let r = analyzeCommand("find . -delete")
    check r.status != asSafe

  test "find . -execdir sh -c 'rm' {} ; — find with -execdir":
    let r = analyzeCommand("find . -execdir sh -c 'rm' {} \\;")
    check r.status != asSafe

  test "awk with system() — awk GTFOBins":
    let r = analyzeCommand("awk 'BEGIN{system(\"cmd\")}'")
    check r.status != asSafe

  test "curl http://x — network tool always blocked":
    let r = analyzeCommand("curl http://x")
    check r.status != asSafe

  test "wget http://x — network tool always blocked":
    let r = analyzeCommand("wget http://x")
    check r.status != asSafe

  test "nc -l 8080 — network tool always blocked":
    let r = analyzeCommand("nc -l 8080")
    check r.status != asSafe

  test "sudo ls — sudo always blocked":
    let r = analyzeCommand("sudo ls")
    check r.status != asSafe

  test "env LD_PRELOAD=x cmd — env always blocked":
    let r = analyzeCommand("env LD_PRELOAD=x cmd")
    check r.status != asSafe

  # ── Security Hardening: Command Name Obfuscation (BLOCK) ──────────────────

  test "e'v'al $X — single-quote obfuscation":
    let r = analyzeCommand("e'v'al $X")
    check r.status != asSafe

  test "\"ev\"al $X — double-quote obfuscation":
    let r = analyzeCommand("\"ev\"al $X")
    check r.status != asSafe

  test "\\e\\v\\a\\l $X — backslash obfuscation":
    let r = analyzeCommand("\\e\\v\\a\\l $X")
    check r.status != asSafe

  test "e'x'e'c' cmd — exec with mixed quotes":
    let r = analyzeCommand("e'x'e'c' cmd")
    check r.status != asSafe

  # ── Security Hardening: Variable-as-Command (BLOCK) ───────────────────────

  test "$CMD arg1 arg2 — variable expansion as command name":
    let r = analyzeCommand("$CMD arg1 arg2")
    check r.status != asSafe

  test "${TOOL} --flag — braced variable as command name":
    let r = analyzeCommand("${TOOL} --flag")
    check r.status != asSafe

  test "$(which tool) arg — command substitution as command name":
    let r = analyzeCommand("$(which tool) arg")
    check r.status != asSafe

  # ── Pipeline Security (BLOCK) ─────────────────────────────────────────────

  test "curl http://x | sh — network pipe to interpreter":
    let r = analyzeCommand("curl http://x | sh")
    check r.status != asSafe

  test "wget -O- http://x | bash — network pipe to interpreter":
    let r = analyzeCommand("wget -O- http://x | bash")
    check r.status != asSafe

  # ── Edge Cases ────────────────────────────────────────────────────────────

  test "empty string — fail-closed":
    let r = analyzeCommand("")
    check r.status != asSafe

  test "plain text with no command — unknown command passes through":
    let r = analyzeCommand("hello")
    check r.status == asSafe  # "hello" is unknown → passes through to policy check

  test "echo hello world — safe output with literal args":
    let r = analyzeCommand("echo hello world")
    check r.status == asSafe

  test "echo with double-quoted string":
    let r = analyzeCommand("echo \"hello world\"")
    check r.status == asSafe

  # ── Ambiguous (fail-closed) ─────────────────────────────────────────

  test "unknown command with dynamic syntax → ambiguous (fail-closed)":
    let r = analyzeCommand("git $(whoami) status")
    check r.status == asAmbiguous

  test "empty string → ambiguous (fail-closed)":
    let r = analyzeCommand("")
    check r.status == asAmbiguous

  # ── Zero-Trust Interpreter Validation: Block (analyzeInterpreterArgs) ────

  test "bare python3 — no args → BLOCK":
    let r = analyzeInterpreterArgs("python3", @[])
    check r.status == asDangerous
    check "Bare" in r.reason

  test "python3 -c code — inline code → BLOCK (stateful)":
    let r = analyzeInterpreterArgs("python3", @["-c", "print(1)"])
    check r.status == asDangerous
    check "stateful" in r.reason

  test "python3 -e code — eval mode → BLOCK (stateful)":
    let r = analyzeInterpreterArgs("python3", @["-e", "1+1"])
    check r.status == asDangerous
    check "stateful" in r.reason

  test "node -e console.log — inline code → BLOCK (stateful)":
    let r = analyzeInterpreterArgs("node", @["-e", "console.log(1)"])
    check r.status == asDangerous
    check "stateful" in r.reason

  test "python3 -m json.tool — missing -I → BLOCK (isolation)":
    let r = analyzeInterpreterArgs("python3", @["-m", "json.tool"])
    check r.status == asDangerous
    check "requires" in r.reason

  test "python3 -Im malicious — not whitelisted → BLOCK":
    let r = analyzeInterpreterArgs("python3", @["-Im", "malicious"])
    check r.status == asDangerous
    check "whitelist" in r.reason

  test "python3 -Im http.server — stateful network service → BLOCK":
    let r = analyzeInterpreterArgs("python3", @["-Im", "http.server"])
    check r.status == asDangerous
    check "whitelist" in r.reason

  test "python3 script.py — no action flag → BLOCK (fail-closed)":
    let r = analyzeInterpreterArgs("python3", @["script.py"])
    check r.status == asDangerous
    check "-m" in r.reason

  test "python3 -m — missing module name → BLOCK":
    let r = analyzeInterpreterArgs("python3", @["-m"])
    check r.status == asDangerous
    check "Missing" in r.reason

  test "python3 --help exploit.py — info flag with payload → BLOCK":
    let r = analyzeInterpreterArgs("python3", @["--help", "exploit.py"])
    check r.status == asDangerous
    check "Extraneous" in r.reason

  test "awk with GTFOBins program — no -m mode → BLOCK":
    let r = analyzeInterpreterArgs("awk", @["BEGIN{system(\"cmd\")}"])
    check r.status == asDangerous

  # ── Zero-Trust Interpreter Validation: Pass (analyzeInterpreterArgs) ─────

  test "python3 -Im json.tool — whitelisted with isolation → PASS":
    let r = analyzeInterpreterArgs("python3", @["-Im", "json.tool"])
    check r.status == asSafe
    check "PASS" in r.reason
    check "isolation=true" in r.reason

  test "python3 -Im json.tool /file.json — data args free → PASS":
    let r = analyzeInterpreterArgs("python3", @["-Im", "json.tool", "/file.json"])
    check r.status == asSafe
    check "/file.json" in r.reason  # data args in audit trail

  test "python3 -Im timeit — whitelisted module → PASS":
    let r = analyzeInterpreterArgs("python3", @["-Im", "timeit"])
    check r.status == asSafe

  test "python3 -vBIm json.tool — clustered flags with -I → PASS":
    let r = analyzeInterpreterArgs("python3", @["-vBIm", "json.tool"])
    check r.status == asSafe
    check "isolation=true" in r.reason

  test "python3 --version — standalone info flag → PASS":
    let r = analyzeInterpreterArgs("python3", @["--version"])
    check r.status == asSafe

  test "python -Im json.tool — inherits from python3 → PASS":
    let r = analyzeInterpreterArgs("python", @["-Im", "json.tool"])
    check r.status == asSafe

  # ── Zero-Trust: through analyzeCommand integration ───────────────────────

  test "python3 -Im json.tool — full pipeline → PASS":
    let r = analyzeCommand("python3 -Im json.tool")
    check r.status == asSafe

  test "python3 -c code — full pipeline → BLOCK":
    let r = analyzeCommand("python3 -c \"import os\"")
    check r.status == asDangerous

  test "python3 -m json.tool — full pipeline missing -I → BLOCK":
    let r = analyzeCommand("python3 -m json.tool")
    check r.status == asDangerous

  test "bash -c echo — shell interpreter full pipeline → BLOCK":
    let r = analyzeCommand("bash -c echo")
    check r.status == asDangerous

  # ── Zero-Trust: ManagedInterpreter registry ──────────────────────────────

  test "isManagedInterpreter — shell interpreters return ipBlock":
    check isManagedInterpreter("bash") == ipBlock
    check isManagedInterpreter("sh") == ipBlock
    check isManagedInterpreter("zsh") == ipBlock

  test "isManagedInterpreter — stateless interpreters return ipStateless":
    check isManagedInterpreter("python3") == ipStateless
    check isManagedInterpreter("python") == ipStateless
    check isManagedInterpreter("node") == ipStateless
    check isManagedInterpreter("awk") == ipStateless

  test "isManagedInterpreter — unknown tools return ipAllow":
    check isManagedInterpreter("git") == ipAllow
    check isManagedInterpreter("nim") == ipAllow
    check isManagedInterpreter("cargo") == ipAllow

  # ── Zero-Trust: Audit log quality ────────────────────────────────────────

  test "PASS reason includes isolation, flags, and data":
    let r = analyzeInterpreterArgs("python3", @["-Im", "json.tool", "/data.json"])
    check "isolation=true" in r.reason
    check "flags=" in r.reason
    check "/data.json" in r.reason

  test "BLOCK reason includes parsed structure for blocked action":
    let r = analyzeInterpreterArgs("python3", @["-Ic", "print(1)"])
    check "action=" in r.reason
    check "payload=" in r.reason

  # ── Zero-Trust: SSOT whitelist integrity ──────────────────────────────────

  test "Whitelist DangerousEnvVars includes critical vars":
    check "PYTHONPATH" in Whitelist.dangerousEnvVars
    check "LD_PRELOAD" in Whitelist.dangerousEnvVars
    check "NODE_PATH" in Whitelist.dangerousEnvVars

  test "Whitelist modules include json.tool for python3":
    check Whitelist.modules.hasKey("python3")
    check Whitelist.modules["python3"].hasKey("json.tool")
    check Whitelist.modules["python3"]["json.tool"].rationale.len > 0

  test "Whitelist python inherits from python3":
    check Whitelist.modules.hasKey("python")
    check Whitelist.modules["python"].hasKey("json.tool")

  test "BlockedActions includes -c and -e":
    check "-c" in Whitelist.blockedActions
    check "-e" in Whitelist.blockedActions

{.pop.}
