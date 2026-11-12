import core/trusted/layer_declaration
axiomLayer "tools"
import std/macros
import std/strutils

type
  MetamorphicProperty* = enum
    mpIdempotency, mpRoundTrip, mpMonotonicity

proc getTypeName(typeNode: NimNode): string =
  if typeNode.kind == nnkPostfix and typeNode.len > 1 and typeNode[0].strVal == "*":
    result = typeNode[1].strVal
  elif typeNode.kind in {nnkIdent, nnkSym}:
    result = typeNode.strVal
  else:
    result = ""

proc genExprForType(typeNode: NimNode, depthExpr: NimNode = nil): NimNode =
  ## Returns an expression that generates a value of the given type at runtime.
  ## For ref types, depthExpr controls the maxDepth passed to the generator.
  # Unwrap typeDesc wrapper from getTypeImpl/getTypeInst
  let effectiveNode = block:
    if typeNode.kind == nnkBracketExpr and typeNode.len == 2 and
       typeNode[0].kind in {nnkIdent, nnkSym} and typeNode[0].strVal == "typeDesc":
      typeNode[1]
    else:
      typeNode

  var typeName = ""
  if effectiveNode.kind in {nnkIdent, nnkSym}:
    typeName = effectiveNode.strVal
  elif effectiveNode.kind == nnkBracketExpr and effectiveNode.len > 0:
    let base = effectiveNode[0]
    if base.kind in {nnkIdent, nnkSym}:
      typeName = base.strVal

  case typeName
  of "int":
    result = newCall(ident"genInt")
  of "string":
    result = newCall(ident"genString")
  of "bool":
    result = newCall(ident"genBool")
  of "seq":
    if effectiveNode.len > 1:
      let elemGen = genExprForType(effectiveNode[1], depthExpr)
      # genSeq expects proc(): T — wrap elemGen in a no-arg lambda
      let lambdaBody = newStmtList(elemGen)
      let lambdaProc = nnkLambda.newTree(
        newEmptyNode(),                 # no name (anonymous)
        newEmptyNode(),                 # no pattern
        newEmptyNode(),                 # no generic params
        nnkFormalParams.newTree(
          ident"auto"                 # explicit auto return type
        ),
        nnkPragma.newTree(ident"closure"),  # {.closure.} calling convention
        newEmptyNode(),                 # no reserved
        lambdaBody                      # body: return the generated value
      )
      result = newCall(ident"genSeq", lambdaProc)
    else:
      result = newCall(ident"default", newCall(ident"typeof", typeNode))
  else:
    # Try to resolve the type via getTypeImpl for distinct/enum/tuple/ref
    if typeNode.kind in {nnkIdent, nnkSym}:
      try:
        let impl = getTypeImpl(typeNode)
        if impl.kind == nnkBracketExpr and impl.len >= 2:
          let inner = getTypeImpl(impl[1])
          case inner.kind
          of nnkDistinctTy:
            # distinct T -> generator of base type, cast to distinct
            let baseGen = genExprForType(inner[0], depthExpr)
            result = newCall(typeNode, baseGen)
          of nnkEnumTy:
            # enum -> rand from valid values
            # Use: T(rand(ord(low(T))..ord(high(T))))
            result = newCall(
              typeNode,
              newCall(ident"rand",
                newCall(ident"..",
                  newCall(ident"ord", newCall(ident"low", typeNode)),
                  newCall(ident"ord", newCall(ident"high", typeNode))
                )
              )
            )
          of nnkTupleTy:
            # tuple -> field generators combined
            var fields = newNimNode(nnkTupleConstr)
            for i in 0..<inner.len:
              let field = inner[i]
              if field.kind == nnkIdentDefs and field.len >= 3:
                let fieldType = field[^2]
                fields.add(genExprForType(fieldType, depthExpr))
            result = fields
          of nnkRefTy:
            # ref type -> call generator with depth
            if typeNode.kind in {nnkIdent, nnkSym}:
              let genName = ident("gen" & typeNode.strVal)
              let depth = if depthExpr != nil: depthExpr else: newLit(3)
              result = newCall(genName, depth)
            else:
              result = newCall(ident"default", newCall(ident"typeof", typeNode))
          else:
            result = newCall(ident"default", newCall(ident"typeof", typeNode))
        elif impl.kind == nnkRefTy:
          # Direct ref type (non-generic ref object)
          if typeNode.kind in {nnkIdent, nnkSym}:
            let genName = ident("gen" & typeNode.strVal)
            let depth = if depthExpr != nil: depthExpr else: newLit(3)
            result = newCall(genName, depth)
          else:
            result = newCall(ident"default", newCall(ident"typeof", typeNode))
        else:
          result = newCall(ident"default", newCall(ident"typeof", typeNode))
      except CatchableError:
        result = newCall(ident"default", newCall(ident"typeof", typeNode))
    else:
      result = newCall(ident"default", newCall(ident"typeof", typeNode))

macro deriveGenerator*(T: typedesc): untyped =
  let typeImpl = getImpl(T)

  var typeBody: NimNode
  var typeNameStr: string

  if typeImpl.kind == nnkTypeDef:
    typeBody = typeImpl[2]
    typeNameStr = getTypeName(typeImpl[0])
  elif typeImpl.kind == nnkObjectTy:
    typeBody = typeImpl
    typeNameStr = ""
  else:
    typeBody = typeImpl
    typeNameStr = ""

  if typeNameStr == "":
    error("deriveGenerator: could not determine type name. Ensure the type is a named type.", T)

  let procName = ident("gen" & typeNameStr)
  let actualType = getTypeInst(T)[1]

  var body = newStmtList()

  if typeBody.kind == nnkObjectTy:
    var objConstr = nnkObjConstr.newTree(copyNimNode(actualType))

    let recList = typeBody[2]
    for field in recList:
      case field.kind
      of nnkIdentDefs:
        let typeIdx = field.len - 2
        let fieldTypeNode = field[typeIdx]
        for i in 0..<typeIdx:
          let realFieldName = getTypeName(field[i])
          if realFieldName == "":
            continue
          let initExpr = genExprForType(fieldTypeNode)
          objConstr.add(nnkExprColonExpr.newTree(ident(realFieldName), initExpr))
      of nnkRecCase:
        let discIdentDefs = field[0]
        let discNameNode = discIdentDefs[0]
        let discTypeNode = discIdentDefs[discIdentDefs.len - 2]
        let discName = getTypeName(discNameNode)
        let discTypeName = getTypeName(discTypeNode)

        if discName != "" and discTypeName != "":
          let discAssignment = nnkAsgn.newTree(
            nnkDotExpr.newTree(ident"result", ident(discName)),
            newCall(ident(discTypeName),
              newCall(ident"genInt",
                newCall(ident"ord", newCall(ident"low", ident(discTypeName))),
                newCall(ident"ord", newCall(ident"high", ident(discTypeName))))
            )
          )
          body.add(discAssignment)

          var caseStmt = nnkCaseStmt.newTree(
            nnkDotExpr.newTree(ident"result", ident(discName))
          )

          for i in 1..<field.len:
            let branch = field[i]
            case branch.kind
            of nnkOfBranch:
              var ofBranch = nnkOfBranch.newTree()
              for j in 0..<branch.len - 1:
                ofBranch.add(copyNimNode(branch[j]))

              var branchBody = newStmtList()
              let branchRecList = branch[^1]
              if branchRecList.kind == nnkRecList:
                for branchField in branchRecList:
                  if branchField.kind == nnkIdentDefs:
                    let bfTypeIdx = branchField.len - 2
                    let bfTypeNode = branchField[bfTypeIdx]
                    for bi in 0..<bfTypeIdx:
                      let bfName = getTypeName(branchField[bi])
                      if bfName != "":
                        let bfInit = genExprForType(bfTypeNode)
                        branchBody.add(nnkAsgn.newTree(
                          nnkDotExpr.newTree(ident"result", ident(bfName)),
                          bfInit
                        ))
              ofBranch.add(branchBody)
              caseStmt.add(ofBranch)
            of nnkElse:
              caseStmt.add(nnkElse.newTree(newStmtList()))
            else:
              discard

          body.add(caseStmt)
      else:
        discard

    body.add(nnkAsgn.newTree(ident"result", objConstr))
  else:
    case typeBody.kind
    of nnkRefTy:
      let innerType = typeBody[0]
      if innerType.kind == nnkObjectTy:
        # ref object with depth-bounded allocation
        let recList = innerType[2]

        # ── Cycle detection: scan field type names for self-reference ──
        var isSelfRef = false
        for field in recList:
          if field.kind == nnkIdentDefs:
            let typeIdx = field.len - 2
            let fieldTypeNode = field[typeIdx]
            let ftName = getTypeName(fieldTypeNode)
            if ftName == typeNameStr:
              isSelfRef = true
              break

        # ── maxDepth guard ──
        body.add(nnkIfStmt.newTree(
          nnkElifBranch.newTree(
            newCall(ident"<=", ident"maxDepth", newLit(0)),
            newStmtList(nnkReturnStmt.newTree(newNilLit()))
          )
        ))

        # ── new(result) ──
        body.add(newCall(ident"new", ident"result"))

        # ── Fill fields recursively ──
        for field in recList:
          case field.kind
          of nnkIdentDefs:
            let typeIdx = field.len - 2
            let fieldTypeNode = field[typeIdx]
            let ftName = getTypeName(fieldTypeNode)
            for i in 0..<typeIdx:
              let fieldName = getTypeName(field[i])
              if fieldName == "":
                continue
              var initExpr: NimNode
              if ftName == typeNameStr:
                # Self-referential field: nil via default (cursor semantics — non-owning)
                initExpr = newNilLit()
              else:
                let depthDec = nnkInfix.newTree(ident"-", ident"maxDepth", newLit(1))
                initExpr = genExprForType(fieldTypeNode, depthDec)
              body.add(nnkAsgn.newTree(
                nnkDotExpr.newTree(ident"result", ident(fieldName)),
                initExpr
              ))
          of nnkRecCase:
            # Handle variant object fields
            let discIdentDefs = field[0]
            let discNameNode = discIdentDefs[0]
            let discTypeNode = discIdentDefs[discIdentDefs.len - 2]
            let discName = getTypeName(discNameNode)
            let discTypeName = getTypeName(discTypeNode)

            if discName != "" and discTypeName != "":
              body.add(nnkAsgn.newTree(
                nnkDotExpr.newTree(ident"result", ident(discName)),
                newCall(ident(discTypeName),
                  newCall(ident"genInt",
                    newCall(ident"ord", newCall(ident"low", ident(discTypeName))),
                    newCall(ident"ord", newCall(ident"high", ident(discTypeName))))
                )
              ))

              var caseStmt = nnkCaseStmt.newTree(
                nnkDotExpr.newTree(ident"result", ident(discName))
              )

              for i in 1..<field.len:
                let branch = field[i]
                case branch.kind
                of nnkOfBranch:
                  var ofBranch = nnkOfBranch.newTree()
                  for j in 0..<branch.len - 1:
                    ofBranch.add(copyNimNode(branch[j]))

                  var branchBody = newStmtList()
                  let branchRecList = branch[^1]
                  if branchRecList.kind == nnkRecList:
                    for branchField in branchRecList:
                      if branchField.kind == nnkIdentDefs:
                        let bfTypeIdx = branchField.len - 2
                        let bfTypeNode = branchField[bfTypeIdx]
                        let bfTypeName = getTypeName(bfTypeNode)
                        for bi in 0..<bfTypeIdx:
                          let bfName = getTypeName(branchField[bi])
                          if bfName != "":
                            var bfInit: NimNode
                            if bfTypeName == typeNameStr:
                              # Self-referential in variant: nil (cursor semantics)
                              bfInit = newCall(ident"default", copyNimNode(bfTypeNode))
                            else:
                              let depthDec = nnkInfix.newTree(ident"-", ident"maxDepth", newLit(1))
                              bfInit = genExprForType(bfTypeNode, depthDec)
                            branchBody.add(nnkAsgn.newTree(
                              nnkDotExpr.newTree(ident"result", ident(bfName)),
                              bfInit
                            ))
                  ofBranch.add(branchBody)
                  caseStmt.add(ofBranch)
                of nnkElse:
                  caseStmt.add(nnkElse.newTree(newStmtList()))
                else:
                  discard

              body.add(caseStmt)
          else:
            discard

        # ── Create proc with maxDepth parameter ──
        result = newProc(procName, [copyNimNode(actualType)], body, nnkProcDef)
        result[0] = nnkPostfix.newTree(ident"*", procName)

        # Add maxDepth parameter: proc genT(maxDepth: int = 3): T
        result[3].add(nnkIdentDefs.newTree(
          ident"maxDepth", ident"int", newLit(3)
        ))

        # Pragmas: always {.raises: [].}; {.acyclic.} only when not self-referential
        var pragmas = nnkPragma.newTree(
          nnkExprColonExpr.newTree(ident"raises", nnkBracket.newTree())
        )
        if not isSelfRef:
          pragmas.add(ident"acyclic")
        result[4] = pragmas
        return
      else:
        # ref but not object — fallback to default
        body.add(nnkAsgn.newTree(ident"result", genExprForType(typeBody)))
    of nnkDistinctTy:
      # distinct T -> base type generator, then cast
      let baseGen = genExprForType(typeBody[0])
      body.add(nnkAsgn.newTree(ident"result", newCall(actualType, baseGen)))
    of nnkEnumTy:
      # enum -> rand from valid values using ord(low(T))..ord(high(T))
      let typeNameIdent = ident(typeNameStr)
      body.add(nnkAsgn.newTree(ident"result",
        newCall(actualType,
          newCall(ident"rand",
            newCall(ident"..",
              newCall(ident"ord", newCall(ident"low", typeNameIdent)),
              newCall(ident"ord", newCall(ident"high", typeNameIdent))
            )
          )
        )
      ))
    of nnkTupleTy:
      # tuple -> field generators combined
      var tupleConstr = newNimNode(nnkTupleConstr)
      for i in 0..<typeBody.len:
        let field = typeBody[i]
        if field.kind == nnkIdentDefs and field.len >= 3:
          let fieldType = field[^2]
          tupleConstr.add(genExprForType(fieldType))
      body.add(nnkAsgn.newTree(ident"result", tupleConstr))
    else:
      body.add(nnkAsgn.newTree(ident"result", genExprForType(typeBody)))

  result = newProc(procName, [copyNimNode(actualType)], body, nnkProcDef)
  result[0] = nnkPostfix.newTree(ident"*", procName)

  result[4] = nnkPragma.newTree(
    nnkExprColonExpr.newTree(ident"raises", nnkBracket.newTree())
  )

macro deriveMetamorphicTest*(procSym: typed; property: static MetamorphicProperty): untyped =
  let impl = getImpl(procSym)
  let params = impl[3]

  if params.len < 2:
    error("deriveMetamorphicTest: proc must have at least one parameter", procSym)

  let firstParam = params[1]
  if firstParam.kind != nnkIdentDefs:
    error("deriveMetamorphicTest: cannot parse proc parameters", procSym)

  let inputTypeNode = firstParam[1]
  let inputTypeName = getTypeName(inputTypeNode)

  if inputTypeName == "":
    error("deriveMetamorphicTest: cannot determine input type name", procSym)

  let genInputCall = newCall(ident("gen" & inputTypeName))
  let procNameStr = procSym.strVal
  let testProcName = ident("test" & procNameStr & $property)

  var loopBody = newStmtList()

  case property
  of mpIdempotency:
    loopBody.add(nnkVarSection.newTree(
      nnkIdentDefs.newTree(ident"x", newEmptyNode(), genInputCall)
    ))
    let fx = newCall(procSym, ident"x")
    let ffx = newCall(procSym, fx)
    let cond = newCall(ident"!=", ffx, fx)
    let failBody = newStmtList(
      newCall(ident"echo", newLit("Counterexample found for idempotency: x="), ident"x"),
      newCall(ident"echo", newLit("  f(x)   = "), fx),
      newCall(ident"echo", newLit("  f(f(x))= "), ffx),
      newCall(ident"quit", newLit(1))
    )
    loopBody.add(nnkIfStmt.newTree(
      nnkElifBranch.newTree(cond, failBody)
    ))

  of mpRoundTrip:
    var decodeName = ""
    if procNameStr.startsWith("to"):
      decodeName = "from" & procNameStr[2..^1]
    elif procNameStr.startsWith("encode"):
      decodeName = "decode" & procNameStr[6..^1]
    elif procNameStr.startsWith("serialize"):
      decodeName = "deserialize" & procNameStr[9..^1]
    elif procNameStr.startsWith("marshal"):
      decodeName = "unmarshal" & procNameStr[7..^1]
    else:
      error("deriveMetamorphicTest: cannot infer decode function name from '" & procNameStr & "'. " &
            "Expected prefix: to/encode/serialize/marshal", procSym)

    let decodeSym = ident(decodeName)
    loopBody.add(nnkVarSection.newTree(
      nnkIdentDefs.newTree(ident"x", newEmptyNode(), genInputCall)
    ))
    let encoded = newCall(procSym, ident"x")
    let decoded = newCall(decodeSym, encoded)
    let cond = newCall(ident"!=", decoded, ident"x")
    let failBody = newStmtList(
      newCall(ident"echo", newLit("Counterexample found for round-trip: x="), ident"x"),
      newCall(ident"echo", newLit("  encoded = "), encoded),
      newCall(ident"echo", newLit("  decoded = "), decoded),
      newCall(ident"quit", newLit(1))
    )
    loopBody.add(nnkIfStmt.newTree(
      nnkElifBranch.newTree(cond, failBody)
    ))

  of mpMonotonicity:
    loopBody.add(nnkVarSection.newTree(
      nnkIdentDefs.newTree(ident"x1", newEmptyNode(), genInputCall)
    ))
    loopBody.add(nnkVarSection.newTree(
      nnkIdentDefs.newTree(ident"x2", newEmptyNode(), genInputCall)
    ))
    let swapCond = newCall(ident">", ident"x1", ident"x2")
    let swapBody = newStmtList(
      nnkVarSection.newTree(
        nnkIdentDefs.newTree(ident"tmp", newEmptyNode(), ident"x1")
      ),
      nnkAsgn.newTree(ident"x1", ident"x2"),
      nnkAsgn.newTree(ident"x2", ident"tmp")
    )
    loopBody.add(nnkIfStmt.newTree(
      nnkElifBranch.newTree(swapCond, swapBody)
    ))
    let fx1 = newCall(procSym, ident"x1")
    let fx2 = newCall(procSym, ident"x2")
    let cond = newCall(ident">", fx1, fx2)
    let failBody = newStmtList(
      newCall(ident"echo", newLit("Monotonicity violation: x1="), ident"x1", newLit(" x2="), ident"x2"),
      newCall(ident"echo", newLit("  f(x1)="), fx1),
      newCall(ident"echo", newLit("  f(x2)="), fx2),
      newCall(ident"quit", newLit(1))
    )
    loopBody.add(nnkIfStmt.newTree(
      nnkElifBranch.newTree(cond, failBody)
    ))

  let forLoop = nnkForStmt.newTree(
    ident"i",
    nnkInfix.newTree(ident"..", newLit(1), newLit(1000)),
    loopBody
  )

  result = newProc(testProcName, [newEmptyNode()], newStmtList(forLoop), nnkProcDef)
  result[0] = nnkPostfix.newTree(ident"*", testProcName)
