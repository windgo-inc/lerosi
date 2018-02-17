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

var countEagerCompileProcs {.compileTime.} = 0
#static:
#  randomize()

proc preferCompileTimeGen(targetProc: NimNode):
    NimNode {.compileTime.} =

  let
    originalName = targetProc.name.toStrLit().strVal
    targetIdent = ident(originalName)

  inc(countEagerCompileProcs)
  let
    r1 = random(10000000)
    r2 = random(10000000)

  let
    targetProcId = ident(originalName & $r1 & $countEagerCompileProcs)
    compileProcId = ident(originalName & "Com" & $r2 & $countEagerCompileProcs)

  var
    compileProc = newProc(compileProcId)

  targetProc.name = targetProcId.copy

  compileProc.params = targetProc.params.copy
  compileProc.pragma = nnkPragma.newTree(ident"compileTime")

  var
    forwardCaller = nnkCall.newTree(targetProcId)

    compileCaller = nnkCall.newTree(compileProcId)
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
              compileCaller.add param[i].copy
              deferredCompileCaller.add param[i].copy
            else:
              continue
      else:
        continue

  compileProc.body = newStmtList(
    #nnkCall.newTree(ident"echo", newLit"compile time !!!"),
    forwardCaller.copy)
  #echo targetIdent

  result = newStmtList(targetProc.copy, compileProc.copy)

  var finalProc = newProc(targetIdent.copy)
  finalProc.params = targetProc.params.copy
  finalProc.pragma = nnkPragma.newTree
  finalProc.body = nnkWhenStmt.newTree(
    nnkElifBranch.newTree(
      parseStmt("compiles(((const privt_sss = " & toStrLit(deferredCompileCaller.copy).strVal & ")))"), compileCaller
    ),
    nnkElse.newTree(
      forwardCaller
    )
  )

  var myTplt = nnkTemplateDef.newTree
  finalProc.copyChildrenTo(myTplt)

  result.add myTplt
  result.add nnkExportStmt.newTree(myTplt.name)

  # Debugging purposes
  #echo $toStrLit(result)

macro eagerCompile*(node: untyped): untyped =
  ## Pragma-like macro for roughly enabling implicit static behavior, trying
  ## a compileTime decorated variant, and using the plain procedure
  ## if that does not compile.
  result = preferCompileTimeGen(node)

