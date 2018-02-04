
proc imageAccessor(targetProc: NimNode, allowMutableImages: bool):
    NimNode {.compileTime.} =

  var
    staticBody = newStmtList()
    dynamicBody = newStmtList()
    targetBody = body(targetProc)

  staticBody.add(parseStmt"const isStaticTarget = true")
  dynamicBody.add(parseStmt"const isStaticTarget = false")
  targetBody.copyChildrenTo(staticBody)
  targetBody.copyChildrenTo(dynamicBody)

  var
    staticParams = targetProc.params.copy
    dynamicParams = targetProc.params.copy

  iterator paramsOfType(node: NimNode, name: string, allow: bool): int =
    var count: int = 0
    for ch in node.children:
      case ch.kind:
      of nnkIdentDefs:
        if allow:
          case ch[1].kind:
          of nnkIdent:
            if $ch[1] == name:
              yield count
          of nnkVarTy:
            if $ch[1][0] == name:
              yield count
          else: discard
        elif $ch[1] == name:
          yield count
      else: discard

      inc count

  template process_params(params, variant: untyped): untyped =
    for i in params.paramsOfType("SomeImage", allowMutableImages):
      case params[i].kind:
      of nnkIdent:
        params[i] = variant.copy
      of nnkIdentDefs:
        if params[i][1].kind == nnkVarTy:
          params[i][1][0] = variant.copy
        else:
          params[i][1] = variant.copy
      else: discard


  let
    staticVariant = nnkBracketExpr.newTree(
      ident"StaticOrderImage", ident"T", ident"S", ident"O")
    dynamicVariant = nnkBracketExpr.newTree(
      ident"DynamicOrderImage", ident"T", ident"S")

  process_params(staticParams, staticVariant)
  process_params(dynamicParams, dynamicVariant)

  result = newStmtList()

  
  # StaticOrderImage procedure
  result.add nnkProcDef.newTree(
    targetProc[0],
    newEmptyNode(),
    nnkGenericParams.newTree(
    nnkIdentDefs.newTree(
      ident"T", ident"S",
      newEmptyNode(),
      newEmptyNode()),
    nnkIdentDefs.newTree(
      ident"O",
      nnkStaticTy.newTree(bindSym"DataOrder"),
      newEmptyNode())),
    staticParams.copy,
    getterPragmaAnyExcept(),
    newEmptyNode(),
    staticBody
  )

  # DynamicOrderImage procedure
  result.add nnkProcDef.newTree(
    targetProc[0],
    newEmptyNode(),
    nnkGenericParams.newTree(
    nnkIdentDefs.newTree(
      ident"T", ident"S",
      newEmptyNode(),
      newEmptyNode())),
    dynamicParams.copy,
    getterPragmaAnyExcept(),
    newEmptyNode(),
    dynamicBody
  )

