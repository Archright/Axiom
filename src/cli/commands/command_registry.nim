import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}

## Command Registry — OCP-compliant command dispatch
## Replaces case-statement branching with a table-driven approach.
## Adding a new command requires only registering a handler — no existing code modification.

type
  CommandHandler* = proc(args: seq[string]): int {.nimcall, raises: [].}

  CommandEntry* = object
    name*: string
    handler*: CommandHandler
    description*: string

  CommandRegistry* = seq[CommandEntry]

func register*(reg: var CommandRegistry; name: string;
               handler: CommandHandler; description: string) {.raises: [].} =
  ## Register a command handler. Called once per command during initialization.
  reg.add(CommandEntry(name: name, handler: handler, description: description))

proc dispatch*(reg: CommandRegistry; cmd: string;
               args: seq[string]): int {.raises: [].} =
  ## Find and execute a command by name. Returns 1 if not found.
  for entry in reg:
    if entry.name == cmd:
      return entry.handler(args)
  echo "Unknown command: " & cmd
  echo "Available commands:"
  for entry in reg:
    echo "  " & entry.name & "  " & entry.description
  return 1

{.pop}
