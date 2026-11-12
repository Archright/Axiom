## Intentional pragma violation fixture.
## dynlib is restricted to src/cli/action_interpreter_cli.nim,
## src/core/sync_utils_process.nim, and src/core/sync_utils_resource.nim.
## Using it from src/mcp/ triggers solid-forbidden-pragmas.

proc foreignCall*(name: cstring): pointer {.dynlib: "libforeign".} =
  discard
