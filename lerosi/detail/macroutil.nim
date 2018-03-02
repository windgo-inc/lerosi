# MIT License
# 
# Copyright (c) 2018 WINDGO, Inc.
# Low Energy Retrieval of Source Information
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

import system, macros, sequtils, strutils, random

proc nodeToStr*(node: NimNode): string {.compileTime.} =
  case node.kind:
    of nnkIdent:
      result = $node
    of nnkStrLit, nnkRStrLit:
      result = node.strVal
    else:
      quit "Expected identifier or string as channel layout specifier, but got " & $node & "."

macro stringify*(x: untyped): untyped =
  result = toStrLit(x)

macro trace_result*(x: untyped): untyped =
  let name = x.toStrLit
  result = newCall(bindSym"echo",
    [newLit"[TRACE] ", name, newLit" -> ", x.copy])

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


proc capitalTokens*(str: string): seq[string] =
  result = newSeqOfCap[string](str.len)
  for tok in capitalTokenIter(str):
    result.add(tok)

proc capitalTokenCount*(str: string): int =
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


# Log-depth recursive unroller. For compile-time tests that can't be put in
# a loop without involving macros.
template repeatStatic*(n: static[int], k: static[int], body: untyped): untyped =
  when 3 < n:
    repeatStatic(n div 3, k):
      body
    repeatStatic(n div 3, k + n div 3):
      body
    repeatStatic(n - 2 * (n div 3), k + 2 * (n div 3)):
      body
  elif n == 3:
    block:
      const i {.inject.} = k
      body
    block:
      const i {.inject.} = k + 1
      body
    block:
      const i {.inject.} = k + 2
      body
  elif n == 2:
    block:
      const i {.inject.} = k
      body
    block:
      const i {.inject.} = k + 1
      body
  elif n == 1:
    block:
      const i {.inject.} = k
      body
  else:
    discard



var countEagerCompileProcs {.compileTime.} = 0
#static:
#  randomize()

proc preferCompileTimeGen(targetProc: NimNode):
    NimNode {.compileTime.} =

  let
    (originalName, isExported) = case targetProc[0].kind:
      of nnkPostfix:
        (toStrLit(targetProc[0][1]).strVal, true)
      else:
        (targetProc.name.toStrLit().strVal, false)

    targetIdent = ident(originalName)

  #echo originalName, if isExported: " is exported" else: " is private"

  inc countEagerCompileProcs
  let r1 = countEagerCompileProcs

  let
    targetProcId = ident(originalName & "_ecom_" & $r1 & "_procdo")
    compileProcId = ident(originalName & "_ecom_" & $r1 & "_procvm")

  var
    compileProc = newProc(compileProcId)

  targetProc.name = targetProcId.copy

  compileProc.params = targetProc.params.copy
  compileProc.pragma = nnkPragma.newTree(ident"compileTime")

  var
    forwardCaller = nnkCall.newTree(targetProcId)
    deferredCompileCaller = nnkCall.newTree(compileProcId)

  for param in targetProc.params:
    case param.kind:
      of nnkIdentDefs:
        #echo "found ident defs ", $toStrLit(param)
        for i in 0..<param.len-2:
          case param[i].kind:
            of nnkIdent:
              #echo "found ident ", param[i]
              forwardCaller.add param[i].copy
              deferredCompileCaller.add param[i].copy
            else:
              continue
      else:
        continue

  compileProc.body = newStmtList(forwardCaller.copy)

  result = newStmtList(targetProc.copy, compileProc.copy)

  var finalProc = newProc(targetIdent.copy)
  finalProc.params = targetProc.params.copy
  finalProc.pragma = nnkPragma.newTree
  finalProc.body = nnkWhenStmt.newTree(
    nnkElifBranch.newTree( # Kind of dirty :/
      parseStmt("compiles(((const priv_" & $r1 & " = " & toStrLit(deferredCompileCaller.copy).strVal & ")))"), deferredCompileCaller.copy
    ),
    nnkElse.newTree(
      forwardCaller
    )
  )

  var myTplt = nnkTemplateDef.newTree
  finalProc.copyChildrenTo(myTplt)

  result.add myTplt

  if isExported:
    result.add nnkExportStmt.newTree(myTplt.name)

  # Debugging purposes
  #echo $toStrLit(result)

macro eagerCompile*(node: untyped): untyped =
  ## Pragma-like macro for roughly enabling implicit static behavior, trying
  ## a compileTime decorated variant, and using the plain procedure
  ## if that does not compile.
  result = preferCompileTimeGen(node)

