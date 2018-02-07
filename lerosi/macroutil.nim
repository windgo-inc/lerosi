import macros, sequtils, strutils

proc nodeToStr*(node: NimNode): string {.compileTime.} =
  case node.kind:
    of nnkIdent:
      result = $node
    of nnkStrLit, nnkRStrLit:
      result = node.strVal
    else:
      quit "Expected identifier or string as channel layout specifier, but got " & $node & "."


iterator capitalTokenIter*(str: string): string =
  var acc = newStringOfCap(str.len)

  for i, ch in pairs(str):
    if isUpperAscii(ch) and not acc.isNilOrEmpty:
      yield acc
      acc.setLen(0)
    acc.add(ch)

  # make sure to get the last one too
  if not acc.isNilOrEmpty:
    yield acc


proc capitalTokens*(str: string): seq[string] {.compileTime.} =
  result = newSeqOfCap[string](str.len)
  for tok in capitalTokenIter(str):
    result.add(tok)

proc capitalTokenCount*(str: string): int {.compileTime.} =
  result = 0
  for tok in capitalTokenIter(str):
    inc result

template getterPragmaAnyException*: untyped =
  nnkPragma.newTree(
    ident"inline",
    ident"noSideEffect")

template getterPragma*(
    exceptionList: untyped = newNimNode(nnkBracket)): untyped =

  getterPragmaAnyException().add(
    nnkExprColonExpr.newTree(ident"raises", exceptionList))

template accessorPragmaAnyException*(ase: bool): untyped =
  # NOTE : There is a careful design decision here to suggest inlining to
  # the compiler if the code can't produce any side effects. The reasoning
  # behind it is that an side effect causing accessor likely won't benefit
  # the performance of the code in to which it is inlined, because it's
  # internals are likely to access things which are farther away an less
  # likely to be cached. In addition, it is also likely that the body of
  # such a procedure will not be kind to code size if inlined repeatedly.
  # Getters and local mutators are by contrast highly optimizable because
  # they produce no side effects, further reducing their probable footprint.
  # Tests should be done with and without inline on getters and mutators
  # to see the difference.
  if allowSideEffects:
    nnkPragma.newTree
  else:
    getterPragmaAnyException()

template accessorPragma*(ase: bool,
    exceptionList: untyped = newNimNode(nnkBracket)): untyped =

  accessorPragmaAnyException(ase).add(
    nnkExprColonExpr.newTree(ident"raises", exceptionList))

{.deprecated: [getterPragmaAnyExcept: getterPragmaAnyException].}

