
declareNamedFixedSeq("ChannelIndex", int, MAX_IMAGE_CHANNELS)

var
  enableColorSubspaces    {.compileTime.} = false

  channelCounter          {.compileTime.} = 0
  channelNames            {.compileTime.} = newSeq[string]()
  channelColorspaces      {.compileTime.} = newSeq[seq[int]]()

  properColorspaceCounter {.compileTime.} = 0
  # Counting only full channelspaces, not partial subspaces such as RB or CbCr.

  channelspaceCounter       {.compileTime.} = 0
  channelspaceNames         {.compileTime.} = newSeq[string]()
  channelspaceIndices       {.compileTime.} = newSeq[ChannelIndex]()

static:
  channelNames.add("")
  channelColorspaces.add(newSeq[int]())
  channelspaceNames.add("")
  channelspaceIndices.add(initFixedSeq[int, MAX_IMAGE_CHANNELS]())

proc asChannelCompiler(name: string): int {.compileTime.} =
  if not channelNames.contains(name):
    inc(channelCounter)
    result = channelCounter
    channelNames.add name
    channelColorspaces.add(newSeq[int]())
  else:
    result = channelNames.find(name)


proc asChannelSpaceCompilerImpl(name: string, channelstr: string = nil):
    int {.compileTime.} =

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
        channelColorspaces[i].add(channelspaceCounter)

      channelspaceIndices.add chindex
  else:
    result = channelspaceNames.find(name)


#proc asAnyChannelSpaceCompiler(name: string): int {.compileTime.} =
#  asChannelSpaceCompilerImpl(name=name, channelstr=nil)

proc asSingleChannelSpaceCompiler(channelstr: string): int {.compileTime.} =
  asChannelSpaceCompilerImpl(name=channelstr, channelstr=channelstr)


proc asSingleChannelSpaceWithAlphaCompiler(channelstr: string): int {.compileTime.} =
  asChannelSpaceCompilerImpl(name=channelstr, channelstr=channelstr&"A")


proc asChannelSpaceCompilerImpl(
    channelseq: var FixedSeq[string, MAX_IMAGE_CHANNELS], count: int):
    int {.compileTime.} =

  result = asSingleChannelSpaceCompiler(channelseq.join)

  #if enableColorSubspaces:
  #  var oddOut: string = nil
  #  if count > 1:
  #    for i in 0..<count:
  #      oddOut = channelseq[i]
  #      delete(channelseq, i)

  #      discard asChannelSpaceCompilerImpl(channelseq, count - 1)
  #      insert(channelseq, oddOut, i)


proc asChannelSpaceWithAlphaCompilerImpl(
    channelseq: var FixedSeq[string, MAX_IMAGE_CHANNELS], count: int):
    int {.compileTime.} =

  result = asSingleChannelSpaceWithAlphaCompiler(channelseq.join)

  #if enableColorSubspaces:
  #  var oddOut: string = nil
  #  if count > 1:
  #    for i in 0..<count:
  #      oddOut = channelseq[i]
  #      delete(channelseq, i)

  #      discard asChannelSpaceCompilerImpl(channelseq, count - 1)
  #      insert(channelseq, oddOut, i)


proc asChannelSpaceCompiler(channelstr: string): int {.compileTime.} =
  var channelseq: FixedSeq[string, MAX_IMAGE_CHANNELS]
  copyFrom(channelseq, capitalTokens(channelstr))
  result = asChannelSpaceCompilerImpl(channelseq, channelseq.len)
  inc properColorspaceCounter


proc asChannelSpaceWithAlphaCompiler(channelstr: string): int {.compileTime.} =
  var channelseq: FixedSeq[string, MAX_IMAGE_CHANNELS]
  copyFrom(channelseq, capitalTokens(channelstr))
  result = asChannelSpaceWithAlphaCompilerImpl(channelseq, channelseq.len)
  inc properColorspaceCounter


#macro defineWildcardChannelSpace(node: untyped): untyped =
#  let name = nodeToStr(node)
#  discard asAnyChannelSpaceCompiler(name)

proc defineChannelSpaceProc(node: string) {.compileTime.} =
  discard asChannelSpaceCompiler(node)
  
macro defineChannelSpace(node: untyped): untyped =
  let name = nodeToStr(node)
  defineChannelSpaceProc(name)

proc defineChannelSpaceWithAlphaProc(node: string) {.compileTime.} =
  #discard asChannelSpaceCompiler(node)
  discard asChannelSpaceWithAlphaCompiler(node)

macro defineChannelSpaceWithAlpha(node: untyped): untyped =
  let name = nodeToStr(node)
  defineChannelSpaceWithAlphaProc(name)


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

      proc channel_name*(T: typedesc[`typ`]):
        string {.inline, noSideEffect, raises: [].} = `name`
      proc `dollarProcVar`*(T: typedesc[`typ`]):
        string {.inline, noSideEffect, raises: [].} = `name`
      proc channel_type*(T: typedesc[`typ`]):
        typedesc[`typ`] {.inline, noSideEffect, raises: [].} = T
      proc channel_id*(T: typedesc[`typ`]):
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
            newLit("No such color channel named \""),
            newIdentNode(!"ch")
          ),
          newLit("\".")
        )))))

  let addendum = quote do:
    proc channel_id*(ch: ChannelId):
      ChannelId {.inline, noSideEffect, raises: [].} = ch
    proc `dollarProcVar`*(ch: ChannelId):
      string {.inline, noSideEffect, raises: [].} = channel_name(ch)
    proc channel_name*(ch: string):
      string {.inline, noSideEffect, raises: [].} = ch

  var idproc = newProc(nnkPostfix.newTree(ident"*", ident"channel_id"), [
    ident"ChannelId",
    newIdentDefs(ident"ch", ident"string")
  ])

  var nameproc = newProc(nnkPostfix.newTree(ident"*", ident"channel_name"), [
    ident"string",
    newIdentDefs(ident"ch", ident"ChannelId")
  ])

  idproc.body = newStmtList(chidcases)
  idproc.pragma = getterPragma(newNimNode(nnkBracket).add(ident"ValueError"))

  nameproc.body = newStmtList(chnamecases)
  nameProc.pragma = getterPragma()

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
      order(cs, T.channel_id)

    proc order*[U: typedesc](T: U, ch: ChannelId):
        int {.inline, noSideEffect, raises: [].} =
      order(T.id, ch)

    proc order*[U, W: typedesc](T: U, V: W):
        int {.inline, noSideEffect, raises: [].} =
      order(T, V.channel_id)


    proc id*(cs: ChannelSpace):
        ChannelSpace {.inline, noSideEffect, raises: [].} =
      cs

    proc name*(cs: string):
        string {.inline, noSideEffect, raises: [].} =
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

    let csidseq = channelColorspaces[chid]
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

macro declareChannelSpaceMetadata(): untyped =
  result = newStmtList()
  makeChannels().copyChildrenTo(result)
  makeChannelSpaces().copyChildrenTo(result)
  makeChannelSpaceRefs().copyChildrenTo(result)

  let finalmsg = quote do:
    static:
      echo "Supporting ", channelspaceCounter, " channelspaces of which ",
        properColorspaceCounter, " are full channelspaces."
  finalmsg.copyChildrenTo(result)

