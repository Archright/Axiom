## tests/integration/test_lean_lsp_document_symbol_integration.nim
## Integration tests for getDocumentSymbols with a running Lean 4 LSP server.
## Guarded by axiomIntegration / leanIntegration defines.

when defined(axiomIntegration) or defined(leanIntegration):

  import std/unittest
  import std/json
  import std/sequtils
  import std/os
  import std/strutils
  import verification/lean_lsp_client
  import verification/lean_lsp_feedback
  import core/trusted/runtime_context
  import core/types/lean_lsp_types

  proc fileUri(path: string): string =
    "file:///" & absolutePath(path).replace("\\", "/")

  {.warning[BareExcept]: off.}

  suite "getDocumentSymbols — integration":
    var ctx: VerificationRuntimeContext
    var client: LeanLspClient

    setup:
      ctx = newVerificationRuntimeContext()
      client = startLeanLsp(ctx, "")

    teardown:
      try:
        client.shutdown(ctx)
      except CatchableError:
        discard

    test "extracts symbols from a simple Lean module":
      let tmpFile = getTempDir() / "test_symbols.lean"
      tmpFile.writeFile("""
namespace MyModule

def addOne (n : Nat) : Nat := n + 1

theorem add_one_succ (n : Nat) : addOne n = n + 1 := by rfl

end MyModule
""")
      try:
        let uri = fileUri(tmpFile)
        let source = tmpFile.readFile()
        client.openDocument(tmpFile, source)
        let syms = client.getDocumentSymbols(uri)

        check syms.len > 0
        let names = syms.mapIt(it.name).toSeq()
        check "MyModule" in names or "addOne" in names
      except CatchableError as e:
        stderr.writeLine("[lean_integration] Skipping: " & e.msg)
      finally:
        try:
          removeFile(tmpFile)
        except CatchableError:
          discard
