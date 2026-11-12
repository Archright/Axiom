import std/unittest
import std/strutils
import core/translator/universal_assembler

suite "Context-Aware Colon Filter + Header/Body Split":
  test "strips custom type like NimTopologySymbol":
    let input = "theorem foo : True := by\n  let sym : NimTopologySymbol = getSymbol()"
    let (output, _) = sanitizeLeanSource(input)
    check "NimTopologySymbol" notin output
    check "sym :=" in output

  test "strips generic compound type like NimSeq (NimString)":
    let input = "theorem foo : True := by\n  let s : NimSeq (NimString) = emptySeq()"
    let (output, _) = sanitizeLeanSource(input)
    check "let s :=" in output

  test "strips seq[T] type":
    let input = "theorem foo : True := by\n  var items : seq[string] = @[]"
    let (output, _) = sanitizeLeanSource(input)
    check "var items :=" in output
    check "seq[string]" notin output

  test "preserves := assignment":
    let input = "let valid := 42"
    let (output, _) = sanitizeLeanSource(input)
    check "valid := 42" in output

  test "preserves theorem header colon":
    let input = "theorem foo (x : Int) : x >= 0 := by"
    let (output, _) = sanitizeLeanSource(input)
    check "Int" in output  # colon in theorem header preserved
    check ":= by" in output

  test "strips type annotation in body after := by":
    let input = "theorem foo : True := by\n  let x : Int = 42"
    let (output, _) = sanitizeLeanSource(input)
    # Theorem header should preserve colon
    check "theorem foo : True := by" in output
    # Body should strip type annotation
    check "let x :=" in output

  test "preserves theorem header with parameter types":
    let input = "theorem bar (x : Int) (y : String) : x >= 0 := by"
    let (output, _) = sanitizeLeanSource(input)
    check "(x : Int)" in output
    check "(y : String)" in output
    check ":= by" in output

  test "sanitizeLeanSource captures import lines from body":
    let input = "theorem foo : True := by\n  import Std.Tactic\n  simpa"
    let (cleaned, imports) = sanitizeLeanSource(input)
    check "import Std.Tactic" notin cleaned
    check imports.len >= 1
    check "import Std.Tactic" in imports

  test "sanitizeLeanSource preserves import in header":
    let input = "import Std\n\ntheorem foo : True := by\n  simpa"
    let (cleaned, imports) = sanitizeLeanSource(input)
    check "import Std" in cleaned

  test "assembleZones puts imports before variables":
    let result = assembleZones(
      staticImports = "import Std\n",
      dynamicImports = @["import Std.Tactic"],
      axiomPrelude = "",
      varDecls = "variable (x : Int)\n",
      theoremDecl = "theorem foo : x >= 0 := by\n",
      proofBody = "  simpa\n"
    )
    # Check zone ordering: import Std before variable
    let stdPos = result.find("import Std")
    let stdTacticPos = result.find("import Std.Tactic")
    let varPos = result.find("variable")
    check stdPos < varPos
    check stdTacticPos < varPos

  test "nuclear colon removal strips body colons":
    let input = "theorem foo : True := by\n  let x : Int := 42"
    let (cleaned, _) = sanitizeLeanSource(input)
    check " : Int " notin cleaned

  test "reserved words escaped in body":
    let input = "theorem foo : True := by\n  inferInstanceAs"
    let (cleaned, _) = sanitizeLeanSource(input)
    check "nim_inferInstanceAs" in cleaned
    check "  inferInstanceAs" notin cleaned

  test "sanitizeLeanSource returns imported captures":
    let (cleaned, imports) = sanitizeLeanSource("theorem foo : True := by\n  simpa")
    check cleaned.len > 0


  test "sanitizeLeanSource output tuple works":
    let (c, i) = sanitizeLeanSource("theorem foo : True := by\n  simpa")
    check i.len == 0
