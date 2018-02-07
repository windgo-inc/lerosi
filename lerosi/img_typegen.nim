
declareNamedFixedSeq("ChannelIndex", int, MAX_IMAGE_CHANNELS)

var
  enableColorSubspaces    {.compileTime.} = false

  channelCounter          {.compileTime.} = 0
  channelNames            {.compileTime.} = newSeq[string]()
  channelColorspaces      {.compileTime.} = newSeq[seq[int]]()

  properColorspaceCounter {.compileTime.} = 0
  # Counting only full colorspaces, not partial subspaces such as RB or CbCr.

  colorspaceCounter       {.compileTime.} = 0
  colorspaceNames         {.compileTime.} = newSeq[string]()
  colorspaceIndices       {.compileTime.} = newSeq[ChannelIndex]()

static:
  channelNames.add("")
  channelColorspaces.add(newSeq[int]())
  colorspaceNames.add("")
  colorspaceIndices.add(initFixedSeq[int, MAX_IMAGE_CHANNELS]())

proc asChannelCompiler(name: string): int {.compileTime.} =
  if not channelNames.contains(name):
    inc(channelCounter)
    result = channelCounter
    channelNames.add name
    channelColorspaces.add(newSeq[int]())
  else:
    result = channelNames.find(name)


proc asColorSpaceCompilerImpl(name: string, channelstr: string = nil):
    int {.compileTime.} =

  if not colorspaceNames.contains(name):
    inc(colorspaceCounter)
    result = colorspaceCounter

    colorspaceNames.add name
    if channelstr.isNilOrEmpty:
      colorspaceIndices.add(initChannelIndex())
    else:
      var chindex: ChannelIndex
      chindex.setLen(0)
      for name in capitalTokenIter(channelstr):
        let i = name.asChannelCompiler
        chindex.add i
        channelColorspaces[i].add(colorspaceCounter)

      colorspaceIndices.add chindex
  else:
    result = colorspaceNames.find(name)


proc asAnyColorSpaceCompiler(name: string): int {.compileTime.} =
  asColorSpaceCompilerImpl(name=name, channelstr=nil)

proc asSingleColorSpaceCompiler(channelstr: string): int {.compileTime.} =
  asColorSpaceCompilerImpl(name=channelstr, channelstr=channelstr)


proc asColorSpaceCompilerImpl(
    channelseq: var FixedSeq[string, MAX_IMAGE_CHANNELS], count: int):
    int {.compileTime.} =

  result = asSingleColorSpaceCompiler(channelseq.join)

  if enableColorSubspaces:
    var oddOut: string = nil
    if count > 1:
      for i in 0..<count:
        oddOut = channelseq[i]
        delete(channelseq, i)

        discard asColorSpaceCompilerImpl(channelseq, count - 1)
        insert(channelseq, oddOut, i)


proc asColorSpaceCompiler(channelstr: string): int {.compileTime.} =
  var channelseq: FixedSeq[string, MAX_IMAGE_CHANNELS]
  copyFrom(channelseq, capitalTokens(channelstr))
  result = asColorSpaceCompilerImpl(channelseq, channelseq.len)
  inc properColorspaceCounter


macro defineWildcardColorSpace(node: untyped): untyped =
  let name = nodeToStr(node)
  discard asAnyColorSpaceCompiler(name)
  
macro defineColorSpace(node: untyped): untyped =
  let name = nodeToStr(node)
  discard asColorSpaceCompiler(name)

proc defineColorSpaceWithAlphaProc(node: string) {.compileTime.} =
  discard asColorSpaceCompiler(node)
  discard asColorSpaceCompiler(node & "A")

macro defineColorSpaceWithAlpha(node: untyped): untyped =
  let name = nodeToStr(node)
  defineColorSpaceWithAlphaProc(name)


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
        ColorChannel {.inline, noSideEffect, raises: [].} = `idident`

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
  result.add(parseStmt("type ColorChannel* = enum " & chenums))
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
    proc channel_id*(ch: ColorChannel):
      ColorChannel {.inline, noSideEffect, raises: [].} = ch
    proc `dollarProcVar`*(ch: ColorChannel):
      string {.inline, noSideEffect, raises: [].} = channel_name(ch)
    proc channel_name*(ch: string):
      string {.inline, noSideEffect, raises: [].} = ch

  var idproc = newProc(nnkPostfix.newTree(ident"*", ident"channel_id"), [
    ident"ColorChannel",
    newIdentDefs(ident"ch", ident"string")
  ])

  var nameproc = newProc(nnkPostfix.newTree(ident"*", ident"channel_name"), [
    ident"string",
    newIdentDefs(ident"ch", ident"ColorChannel")
  ])

  idproc.body = newStmtList(chidcases)
  idproc.pragma = getterPragma(newNimNode(nnkBracket).add(ident"ValueError"))

  nameproc.body = newStmtList(chnamecases)
  nameProc.pragma = getterPragma()

  result.add idproc
  result.add nameproc

  addendum.copyChildrenTo(result)

proc makeColorSpaces(): NimNode {.compileTime.} =
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

  for csid, name in colorspaceNames:
    if skip:
      skip = false
      continue

    let
      typ = ident("ColorSpaceType" & name)
      idname = "ColorSpaceId" & name
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
        chtyp = ident("ChType" & chname)
        idxch = colorspaceIndices[csid].find(chid)
        hasch: bool = 0 <= idxch
        chlit = ident(if hasch: "true" else: "false")
        chord = newLit(idxch)

      if hasch:
        channelSet.add(chident)
        channelOrder.add(idxch)

        # Build up the index of channel sub-cases
        cschanorderspacecases.add(nnkOfBranch.newTree(chident, chord.copy))
        
      
      #let chk = quote do:
      #  proc colorspace_order*(T: typedesc[`typ`], U: typedesc[`chtyp`]):
      #    int {.inline, noSideEffect, raises: [].} = `chord`

      #  proc colorspace_has_channel*(T: typedesc[`typ`], U: typedesc[`chtyp`]):
      #    bool {.inline, noSideEffect, raises: [].} = `chlit`

      #chk.copyChildrenTo(channelChecks)

    
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
      ident"colorspace_order"), [
        ident"int",
        newIdentDefs(ident"cs", nnkBracketExpr.newTree(ident"typedesc", typ)),
        newIdentDefs(ident"ch", ident"ColorChannel")
      ])
    typeorderproc.body = cschanorderspacecases.copy
    typeorderproc.pragma = getterPragma()

    let channelSetLen = newLit(channelSet.len)
    let st = quote do:
      type `typ`* = distinct int

      proc colorspace_name*(T: typedesc[`typ`]):
        string {.inline, noSideEffect, raises: [].} = `name`

      proc `dollarProcVar`*(T: typedesc[`typ`]):
        string {.inline, noSideEffect, raises: [].} = `name`

      proc colorspace_id*(T: typedesc[`typ`]):
        ColorSpace {.inline, noSideEffect, raises: [].} = `idident`

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
    #cschanlencases.add(nnkOfBranch.newTree(
    #  idident,
    #  newAssignment(ident"result", channelSetLen)
    #))

    if first:
      first = false
    else:
      csenums.add ", "

    csenums.add idname

  result = newStmtList()
  result.add(parseStmt("type ColorSpace* = enum " & csenums))

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
            newLit("No such colorspace named \""),
            newIdentNode(!"cs")
          ),
          newLit("\".")
        )))))

  let addendum = quote do:
    proc colorspace_len*[U: typedesc](T: U):
        int {.inline, noSideEffect, raises: [].} =
      colorspace_len(T.colorspace_id)

    proc colorspace_channels*[U: typedesc](T: U):
        set[ColorChannel] {.inline, noSideEffect, raises: [].} =
      colorspace_channels(T.colorspace_id)

    proc colorspace_order*[U: typedesc](T: U):
        FixedSeq[ColorChannel, MAX_IMAGE_CHANNELS]
        {.inline, noSideEffect, raises: [].} =
      colorspace_order(T.colorspace_id)

    proc colorspace_order*[U: typedesc](cs: ColorSpace, T: U):
        int {.inline, noSideEffect, raises: [].} =
      colorspace_order(cs, T.channel_id)

    proc colorspace_order*[U: typedesc](T: U, ch: ColorChannel):
        int {.inline, noSideEffect, raises: [].} =
      colorspace_order(T.colorspace_id, ch)

    proc colorspace_order*[U, W: typedesc](T: U, V: W):
        int {.inline, noSideEffect, raises: [].} =
      colorspace_order(T, V.channel_id)


    proc colorspace_id*(cs: ColorSpace):
        ColorSpace {.inline, noSideEffect, raises: [].} =
      cs

    proc colorspace_name*(cs: string):
        string {.inline, noSideEffect, raises: [].} =
      cs

    proc `dollarProcVar`*(cs: ColorSpace):
        string {.inline, noSideEffect, raises: [].} =
      colorspace_name(cs)

  var idproc = newProc(nnkPostfix.newTree(ident"*", ident"colorspace_id"), [
    ident"ColorSpace",
    newIdentDefs(ident"cs", ident"string")
  ])

  var nameproc = newProc(nnkPostfix.newTree(ident"*",
    ident"colorspace_name"), [
      ident"string",
      newIdentDefs(ident"cs", ident"ColorSpace")
    ])

  var chanproc = newProc(nnkPostfix.newTree(ident"*",
    ident"colorspace_channels"), [
      nnkBracketExpr.newTree(ident"set", ident"ColorChannel"),
      newIdentDefs(ident"cs", ident"ColorSpace")
    ])

  var chanorderproc = newProc(nnkPostfix.newTree(ident"*",
    ident"colorspace_order"), [
      ident"int",
      newIdentDefs(ident"cs", ident"ColorSpace"),
      newIdentDefs(ident"ch", ident"ColorChannel")
    ])

  var chanindexproc = newProc(nnkPostfix.newTree(ident"*",
    ident"colorspace_order"), [
      nnkBracketExpr.newTree(ident"FixedSeq", ident"ColorChannel", newLit(MAX_IMAGE_CHANNELS)),
      newIdentDefs(ident"cs", ident"ColorSpace")
    ])

  var chanlenproc = newProc(nnkPostfix.newTree(ident"*",
    ident"colorspace_len"), [
      ident"int",
      newIdentDefs(ident"cs", ident"ColorSpace")
    ])

  idproc.body = newStmtList(csidcases)
  idproc.pragma = getterPragma(newNimNode(nnkBracket).add(ident"ValueError"))

  nameproc.body = newStmtList(csnamecases)
  chanproc.body = newStmtList(cschancases)
  chanorderproc.body = newStmtList(cschanordercases)
  chanindexproc.body = newStmtList(cschanindexcases)
  chanlenproc.body = newStmtList().add(
    newDotExpr(newCall(ident"colorspace_order", [ident"cs"]), ident"len")
  )

  nameproc.pragma = getterPragma()
  chanproc.pragma = getterPragma()
  chanorderproc.pragma = getterPragma()
  chanindexproc.pragma = getterPragma()
  chanlenproc.pragma = getterPragma()

  result.add idproc
  result.add nameproc
  result.add chanproc
  result.add chanindexproc
  result.add chanorderproc
  result.add chanlenproc

  addendum.copyChildrenTo(result)


proc makeColorSpaceRefs(): NimNode {.compileTime.} =
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
        csname = colorspaceNames[csid]
        csident = ident("ColorSpaceId" & csname)

      csset.add(csident)

    chspacecases.add(newNimNode(nnkOfBranch).add(chident, newAssignment(ident"result", csset)))

  var spacesproc = newProc(
    nnkPostfix.newTree(ident"*", ident"channel_get_colorspaces"), [
      parseExpr"set[ColorSpace]",
      newIdentDefs(ident"ch", ident"ColorChannel")
    ])

  spacesproc.body = chspacecases
  spacesproc.pragma = getterPragma()

  result = newStmtList().add(spacesproc)

macro declareColorSpaceMetadata(): untyped =
  result = newStmtList()
  makeChannels().copyChildrenTo(result)
  makeColorSpaces().copyChildrenTo(result)
  makeColorSpaceRefs().copyChildrenTo(result)

  let finalmsg = quote do:
    static:
      echo "Supporting ", colorspaceCounter, " sub-colorspaces of which ",
        properColorspaceCounter, " are full colorspaces."
  finalmsg.copyChildrenTo(result)

