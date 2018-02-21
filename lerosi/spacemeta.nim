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

import system, macros, strutils, sequtils
import ./macroutil
import ./fixedseq
import ./spaceconf

declareNamedFixedSeq("ChannelIndex", int, MAX_IMAGE_CHANNELS)

var
  # Channelspace namespaces. There is one global namespace with no name
  # in the case that the prefix field of a channel or channelspace compiler
  # procedure is not furnished.
  namespaceCounter         {.compileTime.} = 0
  namespaceNames           {.compileTime.} = newSeq[string]()

  # Individual channel information. Names are stored with a unique namespace.
  channelCounter           {.compileTime.} = 0
  channelNames             {.compileTime.} = newSeq[(string, string)]()
  channelMemberSpaces      {.compileTime.} = newSeq[seq[int]]()

  # Channelspace information. Names are stored with a unique namespace.
  channelspaceCounter       {.compileTime.} = 0
  channelspaceNames         {.compileTime.} = newSeq[(string, string)]()
  channelspaceIndices       {.compileTime.} = newSeq[ChannelIndex]()

  # Final channelspace counter
  properChannelspaceCounter {.compileTime.} = 0


static:
  namespaceNames.add("")
  channelNames.add(("", ""))
  channelMemberSpaces.add(newSeq[int]())
  channelspaceNames.add(("", ""))
  channelspaceIndices.add(initFixedSeq[int, MAX_IMAGE_CHANNELS]())


proc registerNamespace(namespace: string) {.compileTime.} =
  if not namespaceNames.contains(namespace):
    inc(namespaceCounter)
    namespaceNames.add namespace


proc asChannelCompiler(name: string, namespace: string): int {.compileTime.} =
  registerNamespace namespace
  if not channelNames.contains((name, namespace)):
    inc(channelCounter)
    result = channelCounter
    channelNames.add((name, namespace))
    channelMemberSpaces.add(newSeq[int]())
  else:
    result = channelNames.find((name, namespace))


proc asChannelSpaceCompilerImpl(name: string, channelstr: string, namespace: string = ""):
    int {.compileTime.} =

  let
    namespaceStr =
      if namespace.isNilOrEmpty:
        "Channelspace"
      else:
        "In " & namespace & ", channelspace "

  echo namespaceStr, name, " with channels ", channelstr, "."

  registerNamespace namespace
  if not channelspaceNames.contains((name, namespace)):
    inc(channelspaceCounter)
    result = channelspaceCounter

    channelspaceNames.add((name, namespace))
    if channelstr.isNilOrEmpty:
      channelspaceIndices.add(initChannelIndex())
    else:
      var chindex: ChannelIndex
      chindex.setLen(0)
      for name in capitalTokenIter(channelstr):
        let i = name.asChannelCompiler(namespace)
        chindex.add i
        channelMemberSpaces[i].add(channelspaceCounter)

      channelspaceIndices.add chindex
  else:
    result = channelspaceNames.find((name, namespace))



proc asAnyChannelSpaceCompiler(name: string): int {.compileTime.} =
  asChannelSpaceCompilerImpl(
    name = name,
    channelstr = nil,
    namespace = "")


proc asChannelSpaceCompiler(channelstr: string): int {.compileTime.} =
  result = asChannelSpaceCompilerImpl(
    name = channelstr,
    channelstr = channelstr,
    namespace = "")
  inc properChannelspaceCounter


proc asChannelSpaceCompiler(namespace, channelstr: string): int {.compileTime.} =
  result = asChannelSpaceCompilerImpl(
    name = channelstr,
    channelstr = channelstr,
    namespace = namespace)
  inc properChannelspaceCounter


proc asChannelSpaceExtCompiler(channelstr, extstr: string):
    int {.compileTime.} =
  result = asChannelSpaceCompilerImpl(
    name = channelstr,
    channelstr = channelstr & extstr,
    namespace = "")
  inc properChannelspaceCounter


proc asChannelSpaceExtCompiler(namespace, channelstr, extstr: string):
    int {.compileTime.} =
  result = asChannelSpaceCompilerImpl(
    name = channelstr,
    channelstr = channelstr & extstr,
    namespace = namespace)
  inc properChannelspaceCounter


proc defineAnyChannelSpaceProc(channelstr: string) {.compileTime.} =
  discard asAnyChannelSpaceCompiler(channelstr)
  
macro defineAnyChannelSpace*(node: untyped): untyped =
  defineAnyChannelSpaceProc(nodeToStr(node))

proc defineChannelSpaceProc(channelstr: string) {.compileTime.} =
  discard asChannelSpaceCompiler(channelstr)
  
proc defineChannelSpaceProc(prefix, channelstr: string) {.compileTime.} =
  discard asChannelSpaceCompiler(prefix, channelstr)
  
macro defineChannelSpace*(node: untyped): untyped =
  defineChannelSpaceProc(nodeToStr(node))

macro defineChannelSpace*(prefix, node: untyped): untyped =
  defineChannelSpaceProc(nodeToStr(prefix), nodeToStr(node))

proc defineChannelSpaceExtProc(channelstr, channelstrext: string) {.compileTime.} =
  discard asChannelSpaceExtCompiler(channelstr, channelstrext)

proc defineChannelSpaceExtProc(prefix, channelstr, channelstrext: string)
    {.compileTime.} =
  discard asChannelSpaceExtCompiler(prefix, channelstr, channelstrext)

macro defineChannelSpaceExt*(ext, node: untyped): untyped =
  defineChannelSpaceExtProc(nodeToStr(node), nodeToStr(ext))

macro defineChannelSpaceExt*(prefix, ext, node: untyped): untyped =
  defineChannelSpaceExtProc(nodeToStr(prefix), nodeToStr(node), nodeToStr(ext))

# TODO: Remove.
macro defineChannelSpaceWithAlpha*(node: untyped): untyped {.deprecated.} =
  defineChannelSpaceExtProc(nodeToStr(node), "A")


let dollarProcVar {.compileTime.} = nnkAccQuoted.newTree(ident("$"))

proc makeChannels(): NimNode {.compileTime.} =
  var
    stmts = newStmtList()
    chenums = ""
    chidcases = newNimNode(nnkCaseStmt).add(ident"ch")
    chnamecases = newNimNode(nnkCaseStmt).add(ident"ch")
    chnamespacecases = newNimNode(nnkCaseStmt).add(ident"ch")
    first = true
    skip = true

  for chid, pair in channelNames:
    let (name, namespace) = pair
    if skip:
      skip = false
      continue

    let
      chnamestr = namespace & name
      idname = namespace & "ChId" & name
      idident = ident(idname)

    chidcases.add(
      newNimNode(nnkOfBranch).add(newLit(chnamestr),
      newAssignment(ident"result", idident)))
    chnamecases.add(newNimNode(nnkOfBranch).add(
      idident,
      newAssignment(ident"result", newLit(chnamestr))))
    chnamespacecases.add(newNimNode(nnkOfBranch).add(
      idident,
      newAssignment(ident"result", newLit(namespace))))

    if first:
      first = false
    else:
      chenums.add ", "

    chenums.add idname

  result = newStmtList()
  result.add(parseStmt("type ChannelId* = enum " & chenums))
  stmts.copyChildrenTo(result)

  chidcases.add(newNimNode(nnkElse).add(
    nnkRaiseStmt.newTree(
      nnkCall.newTree(
        newIdentNode(!"newException"),
        newIdentNode(!"ValueError"),
        nnkInfix.newTree(
          newIdentNode(!"&"),
          nnkInfix.newTree(
            newIdentNode(!"&"),
            newLit("No such channel named \""),
            newIdentNode(!"ch")
          ),
          newLit("\".")
        )))))

  let addendum = quote do:
    #proc id*(ch: ChannelId):
    #  ChannelId {.inline, noSideEffect, raises: [].} = ch
    discard

  var dollarproc = newProc(nnkPostfix.newTree(ident"*", dollarProcVar), [
    ident"string",
    newIdentDefs(ident"cs", ident"ChannelId")
  ])

  var idproc = newProc(nnkPostfix.newTree(ident"*", ident"channelof"), [
    ident"ChannelId",
    newIdentDefs(ident"ch", ident"string")
  ])

  var nameproc = newProc(nnkPostfix.newTree(ident"*", ident"name"), [
    ident"string",
    newIdentDefs(ident"ch", ident"ChannelId")
  ])

  var namespaceproc = newProc(nnkPostfix.newTree(ident"*", ident"namespace"), [
    ident"string",
    newIdentDefs(ident"ch", ident"ChannelId")
  ])

  idproc.body = newStmtList(chidcases)
  idproc.pragma = getterPragma(newNimNode(nnkBracket).add(ident"ValueError"))

  nameproc.body = newStmtList(chnamecases.copy)
  nameproc.pragma = getterPragma()

  namespaceproc.body = newStmtList(chnamespacecases.copy)
  namespaceproc.pragma = getterPragma()

  dollarproc.body = newStmtList(chnamecases.copy)
  dollarproc.pragma = getterPragma()

  result.add idproc
  result.add nameproc
  result.add namespaceproc

  addendum.copyChildrenTo(result)

proc makeChannelSpaces(): NimNode {.compileTime.} =
  var
    stmts = newStmtList()
    skip = true
    first = true
    csenums = ""
    csidcases = nnkCaseStmt.newTree(ident"cs")
    csnamecases = nnkCaseStmt.newTree(ident"cs")
    csnamespacecases = nnkCaseStmt.newTree(ident"cs")
    cschancases = nnkCaseStmt.newTree(ident"cs")
    cschanordercases = nnkCaseStmt.newTree(ident"cs")
    cschanindexcases = nnkCaseStmt.newTree(ident"cs")
    cschanorderspacecases = nnkCaseStmt.newTree(ident"ch") # NOTE ch instead of cs
    #cschanlencases = nnkCaseStmt.newTree(ident"cs")

  for csid, pair in channelspaceNames:
    let (name, namespace) = pair
    if skip:
      skip = false
      continue

    let
      typ = ident(namespace & "ChSpaceType" & name)
      csnamestr = namespace & name
      idname = namespace & "ChSpace" & name
      idident = ident(idname)

    var channelSet = nnkCurly.newTree
    var channelOrder = initChannelIndex()
    var channelList = nnkBracket.newTree
    var channelChecks = newStmtList()

    var firstch = true
    for chid, chpair in channelNames:
      let
        (chname, chnamespace) = chpair

      if firstch:
        firstch = false
        continue

      let
        chident = ident(chnamespace & "ChId" & chname)
        idxch = channelspaceIndices[csid].find(chid)
        hasch: bool = 0 <= idxch
        chord = newLit(idxch)

      if hasch:
        channelSet.add(chident)
        channelOrder.add(idxch)

        # Build up the index of channel sub-cases
        cschanorderspacecases.add(nnkOfBranch.newTree(chident, chord.copy))
        
    block:
      var thenodes = initFixedSeq[NimNode, MAX_IMAGE_CHANNELS]()
      for id in channelSet: thenodes.add(id)

      var theindex = initFixedSeq[NimNode, MAX_IMAGE_CHANNELS]()
      theindex.setLen(channelSet.len)

      for chident, idxch in zip(thenodes, channelOrder):
        theindex[idxch] = chident

      for x in theindex:
        channelList.add x

    cschanorderspacecases.add(nnkElse.newTree(newIntLitNode(-1)))
    var typeorderproc = newProc(nnkPostfix.newTree(ident"*",
      ident"order"), [
        ident"int",
        newIdentDefs(ident"cs", nnkBracketExpr.newTree(ident"typedesc", typ)),
        newIdentDefs(ident"ch", ident"ChannelId")
      ])
    typeorderproc.body = cschanorderspacecases.copy
    typeorderproc.pragma = getterPragma()

    let st = quote do:
      type `typ`* = distinct int

      proc name*(T: typedesc[`typ`]):
        string {.inline, noSideEffect, raises: [].} = `csnamestr`

      proc namespace*(T: typedesc[`typ`]):
        string {.inline, noSideEffect, raises: [].} = `namespace`

      proc `dollarProcVar`*(T: typedesc[`typ`]):
        string {.inline, noSideEffect, raises: [].} = `csnamestr`

      proc id*(T: typedesc[`typ`]):
        ChannelSpace {.inline, noSideEffect, raises: [].} = `idident`

    st.copyChildrenTo(stmts)
    channelChecks.copyChildrenTo(stmts)

    csidcases.add(nnkOfBranch.newTree(
      newLit(csnamestr),
      newAssignment(ident"result", idident)
    ))
    csnamecases.add(nnkOfBranch.newTree(
      idident,
      newAssignment(ident"result", newLit(csnamestr))
    ))
    csnamespacecases.add(nnkOfBranch.newTree(
      idident,
      newAssignment(ident"result", newLit(namespace))
    ))
    cschancases.add(nnkOfBranch.newTree(
      idident,
      newAssignment(ident"result", channelSet)
    ))
    cschanindexcases.add nnkOfBranch.newTree(idident, newCall(ident"copyFrom", [ident"result", channelList]))
    cschanordercases.add nnkOfBranch.newTree(idident, cschanorderspacecases)
    cschanorderspacecases = nnkCaseStmt.newTree(ident"ch") # garbage collect old one

    if first:
      first = false
    else:
      csenums.add ", "

    csenums.add idname

  result = newStmtList()
  result.add(parseStmt("type ChannelSpace* = enum " & csenums))

  stmts.copyChildrenTo(result)

  csidcases.add(newNimNode(nnkElse).add(
    nnkRaiseStmt.newTree(
      nnkCall.newTree(
        newIdentNode(!"newException"),
        newIdentNode(!"ValueError"),
        nnkInfix.newTree(
          newIdentNode(!"&"),
          nnkInfix.newTree(
            newIdentNode(!"&"),
            newLit("No such channelspace named \""),
            newIdentNode(!"cs")
          ),
          newLit("\".")
        )))))

  let addendum = quote do:
    proc len*[U: typedesc](T: U):
        int {.inline, noSideEffect, raises: [].} =
      len(T.id)

    proc channels*[U: typedesc](T: U):
        set[ChannelId] {.inline, noSideEffect, raises: [].} =
      channels(T.id)

    proc order*[U: typedesc](T: U):
        FixedSeq[ChannelId, MAX_IMAGE_CHANNELS]
        {.inline, noSideEffect, raises: [].} =
      order(T.id)

    proc order*[U: typedesc](cs: ChannelSpace, T: U):
        int {.inline, noSideEffect, raises: [].} =
      order(cs, T.id)

    proc order*[U: typedesc](T: U, ch: ChannelId):
        int {.inline, noSideEffect, raises: [].} =
      order(T.id, ch)

    proc order*[U, W: typedesc](T: U, V: W):
        int {.inline, noSideEffect, raises: [].} =
      order(T, V.id)


    proc id*(cs: ChannelSpace):
        ChannelSpace {.inline, noSideEffect, raises: [].} =
      cs

  var dollarproc = newProc(nnkPostfix.newTree(ident"*", dollarProcVar), [
    ident"string",
    newIdentDefs(ident"cs", ident"ChannelSpace")
  ])

  var idproc = newProc(nnkPostfix.newTree(ident"*", ident"channelspaceof"), [
    ident"ChannelSpace",
    newIdentDefs(ident"cs", ident"string")
  ])

  var nameproc = newProc(nnkPostfix.newTree(ident"*",
    ident"name"), [
      ident"string",
      newIdentDefs(ident"cs", ident"ChannelSpace")
    ])
  var namespaceproc = newProc(nnkPostfix.newTree(ident"*",
    ident"namespace"), [
      ident"string",
      newIdentDefs(ident"cs", ident"ChannelSpace")
    ])

  var chanproc = newProc(nnkPostfix.newTree(ident"*",
    ident"channels"), [
      nnkBracketExpr.newTree(ident"set", ident"ChannelId"),
      newIdentDefs(ident"cs", ident"ChannelSpace")
    ])

  var chanorderproc = newProc(nnkPostfix.newTree(ident"*",
    ident"order"), [
      ident"int",
      newIdentDefs(ident"cs", ident"ChannelSpace"),
      newIdentDefs(ident"ch", ident"ChannelId")
    ])

  var chanindexproc = newProc(nnkPostfix.newTree(ident"*",
    ident"order"), [
      nnkBracketExpr.newTree(ident"FixedSeq", ident"ChannelId", newLit(MAX_IMAGE_CHANNELS)),
      newIdentDefs(ident"cs", ident"ChannelSpace")
    ])

  var chanlenproc = newProc(nnkPostfix.newTree(ident"*",
    ident"len"), [
      ident"int",
      newIdentDefs(ident"cs", ident"ChannelSpace")
    ])

  idproc.body = newStmtList(csidcases)
  idproc.pragma = getterPragma(newNimNode(nnkBracket).add(ident"ValueError"))

  nameproc.body = newStmtList(csnamecases.copy)
  namespaceproc.body = newStmtList(csnamespacecases.copy)
  dollarproc.body = newStmtList(csnamecases.copy)
  chanproc.body = newStmtList(cschancases)
  chanorderproc.body = newStmtList(cschanordercases)
  chanindexproc.body = newStmtList(cschanindexcases)
  chanlenproc.body = newStmtList().add(
    newDotExpr(newCall(ident"order", [ident"cs"]), ident"len")
  )

  nameproc.pragma = getterPragma()
  namespaceproc.pragma = getterPragma()
  dollarproc.pragma = getterPragma()
  chanproc.pragma = getterPragma()
  chanorderproc.pragma = getterPragma()
  chanindexproc.pragma = getterPragma()
  chanlenproc.pragma = getterPragma()

  result.add idproc
  result.add nameproc
  result.add namespaceproc
  result.add dollarproc
  result.add chanproc
  result.add chanindexproc
  result.add chanorderproc
  result.add chanlenproc

  addendum.copyChildrenTo(result)


proc makeChannelSpaceRefs(): NimNode {.compileTime.} =
  var
    skip = true
    chspacecases = newNimNode(nnkCaseStmt).add(ident"ch")

  for chid, pair in channelNames:
    let (name, namespace) = pair
    if skip:
      skip = false
      continue

    let
      chident = ident(namespace & "ChId" & name)

    let csidseq = channelMemberSpaces[chid]
    var csset = newNimNode(nnkCurly)

    for k, csid in csidseq:
      let
        (csname, csnamespace) = channelspaceNames[csid]
        csident = ident(csnamespace & "ChSpace" & csname)

      csset.add(csident)

    chspacecases.add(newNimNode(nnkOfBranch).add(chident, newAssignment(ident"result", csset)))

  var spacesproc = newProc(
    nnkPostfix.newTree(ident"*", ident"channelspaces"), [
      parseExpr"set[ChannelSpace]",
      newIdentDefs(ident"ch", ident"ChannelId")
    ])

  spacesproc.body = chspacecases
  spacesproc.pragma = getterPragma()

  result = newStmtList().add(spacesproc)

macro declareChannelSpaceMetadata*: untyped =
  result = newStmtList()
  makeChannels().copyChildrenTo(result)
  makeChannelSpaces().copyChildrenTo(result)
  makeChannelSpaceRefs().copyChildrenTo(result)

  echo "Supporting ", channelspaceCounter, " channelspaces of which ",
    properChannelspaceCounter, " are full channelspaces."

