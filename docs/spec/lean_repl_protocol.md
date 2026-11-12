# Lean 4 REPL JSON Protocol Specification

## Source
- Official: https://github.com/leanprover-community/repl
- Verified via Context7 MCP on 2026-06-28

## Transport
- stdin/stdout, JSON per line
- Commands separated by blank line (`\n\n`)
- Response: single JSON line + trailing newline

## Command → Response Contract

### §1 Command Mode (declaration)
Request:  `{"cmd": "def f := 2"}`
Response: `{"env": 1, "messages": []}`

### §2 Command Mode (with explicit env)
Request:  `{"cmd": "example : f = 2 := rfl", "env": 1}`
Response: `{"env": 2, "sorries": [], "messages": []}`

### §3 Tactic Mode
Request:  `{"cmd": "example : True := by", "env": 0}`
Response: `{"env": 1, "proofStates": [0], "goals": ["⊢ True"], "messages": []}`

### §4 Tactic Step
Request:  `{"cmd": "trivial", "proofState": 0, "env": 1}`
Response: `{"env": 2, "messages": [], "sorries": []}`

### §5 Sorry Detection
Request:  `{"cmd": "example : False := sorry", "env": 0}`
Response: `{"env": 1, "sorries": [{"goal": "⊢ False", "proofState": 0}], "messages": []}`

### §6 Error Response
Request:  `{"cmd": "def := invalid", "env": 0}`
Response: `{"env": 0, "messages": [{"severity": "error", "pos": {}, "data": "..."}]}`

### §7 Exit
Request:  EOF (close stdin)
Response: process exits with code 0

## Notes
- `env` is an integer that increments with each command
- Multiple commands can be sent sequentially, separated by blank lines
- Comments starting with `#` or `--` are ignored
- The REPL loops until EOF
