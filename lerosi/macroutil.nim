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

