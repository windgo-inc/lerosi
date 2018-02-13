import system, macros, strutils, sequtils
import ./macroutil
import ./fixedseq
import ./img_conf

declareNamedFixedSeq("ChannelIndex", int, MAX_IMAGE_CHANNELS)

var
  channelCounter          {.compileTime.} = 0
  channelNames            {.compileTime.} = newSeq[string]()
  channelMemberSpaces      {.compileTime.} = newSeq[seq[int]]()

  properChannelspaceCounter {.compileTime.} = 0
  # Counting only full channelspaces, not partial subspaces such as RB or CbCr.

  channelspaceCounter       {.compileTime.} = 0
  channelspaceNames         {.compileTime.} = newSeq[string]()
  channelspaceIndices       {.compileTime.} = newSeq[ChannelIndex]()

static:
  channelNames.add("")
  channelMemberSpaces.add(newSeq[int]())
  channelspaceNames.add("")
  channelspaceIndices.add(initFixedSeq[int, MAX_IMAGE_CHANNELS]())

proc asChannelCompiler(name: string): int {.compileTime.} =
  if not channelNames.contains(name):
    inc(channelCounter)
    result = channelCounter
    channelNames.add name
    channelMemberSpaces.add(newSeq[int]())
  else:
    result = channelNames.find(name)


proc asChannelSpaceCompilerImpl(name: string, channelstr: string = nil):
    int {.compileTime.} =

  echo "Compiling channelspace \"", name, "\" with channels \"", channelstr, "\"."

  if not channelspaceNames.contains(name):
    inc(channelspaceCounter)
    result = channelspaceCounter

    channelspaceNames.add name
    if channelstr.isNilOrEmpty:
      channelspaceIndices.add(initChannelIndex())
    else:
      var chindex: ChannelIndex
      chindex.setLen(0)
      for name in capitalTokenIter(channelstr):
        let i = name.asChannelCompiler
        chindex.add i
        channelMemberSpaces[i].add(channelspaceCounter)

      channelspaceIndices.add chindex
  else:
    result = channelspaceNames.find(name)



proc asAnyChannelSpaceCompiler(name: string): int {.compileTime.} =
  asChannelSpaceCompilerImpl(name=name, channelstr=nil)


proc asChannelSpaceCompiler(channelstr: string): int {.compileTime.} =
  result = asChannelSpaceCompilerImpl(
    name = channelstr,
    channelstr = channelstr)
  inc properChannelspaceCounter


proc asChannelSpaceExtCompiler(channelstr: string, extstr: string): int {.compileTime.} =
  result = asChannelSpaceCompilerImpl(
    name = channelstr,
    channelstr = channelstr & extstr)
  inc properChannelspaceCounter


proc defineAnyChannelSpaceProc(channelstr: string) {.compileTime.} =
  discard asAnyChannelSpaceCompiler(channelstr)
  
macro defineAnyChannelSpace*(node: untyped): untyped =
  defineAnyChannelSpaceProc(nodeToStr(node))

proc defineChannelSpaceProc(channelstr: string) {.compileTime.} =
  discard asChannelSpaceCompiler(channelstr)
  
macro defineChannelSpace*(node: untyped): untyped =
  defineChannelSpaceProc(nodeToStr(node))

proc defineChannelSpaceExtProc(channelstr: string, channelstrext: string) {.compileTime.} =
  discard asChannelSpaceExtCompiler(channelstr, channelstrext)

macro defineChannelSpaceExt*(ext, node: untyped): untyped =
  defineChannelSpaceExtProc(nodeToStr(node), nodeToStr(ext))

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
    first = true
    skip = true

  for chid, name in channelNames:
    if skip:
      skip = false
      continue

    let
      typ = ident("ChType" & name)
      idname = "ChId" & name
      idident = ident(idname)

    let st = quote do:
      type `typ`* = distinct int

      proc name*(T: typedesc[`typ`]):
        string {.inline, noSideEffect, raises: [].} = `name`

      proc `dollarProcVar`*(T: typedesc[`typ`]):
        string {.inline, noSideEffect, raises: [].} = `name`

      proc id*(T: typedesc[`typ`]):
        ChannelId {.inline, noSideEffect, raises: [].} = `idident`

    st.copyChildrenTo(stmts)

    chidcases.add(
      newNimNode(nnkOfBranch).add(newLit(name),
      newAssignment(ident"result", idident)))
    chnamecases.add(newNimNode(nnkOfBranch).add(
      idident,
      newAssignment(ident"result", newLit(name))))

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
    proc id*(ch: ChannelId):
      ChannelId {.inline, noSideEffect, raises: [].} = ch

  var dollarproc = newProc(nnkPostfix.newTree(ident"*", dollarProcVar), [
    ident"string",
    newIdentDefs(ident"cs", ident"ChannelId")
  ])

  var idproc = newProc(nnkPostfix.newTree(ident"*", ident"id"), [
    ident"ChannelId",
    newIdentDefs(ident"ch", ident"string")
  ])

  var nameproc = newProc(nnkPostfix.newTree(ident"*", ident"name"), [
    ident"string",
    newIdentDefs(ident"ch", ident"ChannelId")
  ])

  idproc.body = newStmtList(chidcases)
  idproc.pragma = getterPragma(newNimNode(nnkBracket).add(ident"ValueError"))

  nameproc.body = newStmtList(chnamecases.copy)
  nameproc.pragma = getterPragma()

  dollarproc.body = newStmtList(chnamecases.copy)
  dollarproc.pragma = getterPragma()

  result.add idproc
  result.add nameproc

  addendum.copyChildrenTo(result)

proc makeChannelSpaces(): NimNode {.compileTime.} =
  var
    stmts = newStmtList()
    skip = true
    first = true
    csenums = ""
    csidcases = nnkCaseStmt.newTree(ident"cs")
    csnamecases = nnkCaseStmt.newTree(ident"cs")
    cschancases = nnkCaseStmt.newTree(ident"cs")
    cschanordercases = nnkCaseStmt.newTree(ident"cs")
    cschanindexcases = nnkCaseStmt.newTree(ident"cs")
    cschanorderspacecases = nnkCaseStmt.newTree(ident"ch") # NOTE ch instead of cs
    #cschanlencases = nnkCaseStmt.newTree(ident"cs")

  for csid, name in channelspaceNames:
    if skip:
      skip = false
      continue

    let
      typ = ident("ChannelSpaceType" & name)
      idname = "ChannelSpaceId" & name
      idident = ident(idname)

    var channelSet = nnkCurly.newTree
    var channelOrder = initChannelIndex()
    var channelList = nnkBracket.newTree
    var channelChecks = newStmtList()

    var firstch = true
    for chid, chname in channelNames:
      if firstch:
        firstch = false
        continue

      let
        chident = ident("ChId" & chname)
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
        string {.inline, noSideEffect, raises: [].} = `name`

      proc `dollarProcVar`*(T: typedesc[`typ`]):
        string {.inline, noSideEffect, raises: [].} = `name`

      proc id*(T: typedesc[`typ`]):
        ChannelSpace {.inline, noSideEffect, raises: [].} = `idident`

    st.copyChildrenTo(stmts)
    channelChecks.copyChildrenTo(stmts)

    csidcases.add(nnkOfBranch.newTree(
      newLit(name),
      newAssignment(ident"result", idident)
    ))
    csnamecases.add(nnkOfBranch.newTree(
      idident,
      newAssignment(ident"result", newLit(name))
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

  var idproc = newProc(nnkPostfix.newTree(ident"*", ident"id"), [
    ident"ChannelSpace",
    newIdentDefs(ident"cs", ident"string")
  ])

  var nameproc = newProc(nnkPostfix.newTree(ident"*",
    ident"name"), [
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
  dollarproc.body = newStmtList(csnamecases.copy)
  chanproc.body = newStmtList(cschancases)
  chanorderproc.body = newStmtList(cschanordercases)
  chanindexproc.body = newStmtList(cschanindexcases)
  chanlenproc.body = newStmtList().add(
    newDotExpr(newCall(ident"order", [ident"cs"]), ident"len")
  )

  nameproc.pragma = getterPragma()
  dollarproc.pragma = getterPragma()
  chanproc.pragma = getterPragma()
  chanorderproc.pragma = getterPragma()
  chanindexproc.pragma = getterPragma()
  chanlenproc.pragma = getterPragma()

  result.add idproc
  result.add nameproc
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

  for chid, name in channelNames:
    if skip:
      skip = false
      continue

    let
      chident = ident("ChId" & name)

    let csidseq = channelMemberSpaces[chid]
    var csset = newNimNode(nnkCurly)

    for k, csid in csidseq:
      let
        csname = channelspaceNames[csid]
        csident = ident("ChannelSpaceId" & csname)

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

  let finalmsg = quote do:
    static:
      echo "Supporting ", channelspaceCounter, " channelspaces of which ",
        properChannelspaceCounter, " are full channelspaces."
  finalmsg.copyChildrenTo(result)

