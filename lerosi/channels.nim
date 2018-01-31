import os, system, macros, future
import strutils, sequtils, sets, tables, algorithm
import ./fixedseq


# Per Ratsimbazafy's observation that the cache line of an x86_64 machine can
# hold 8 64-bit integers, this is chosen to be 7 because the FixedSeq type
# (derived from Ratsimbazafy's work) has an extra integer to record the content
# length. This should be based on a minimum beyond which standard channel
# layouts can no longer be supported, as well as the desire for maximum
# performace and sufficient flexibility to design channel layouts of our own in
# special image processing cases. Hence, the number might be subject to change
# in the future.
const
  MAX_IMAGE_CHANNELS* = 7

{.deprecated: [MAX_CHANNELS: MAX_IMAGE_CHANNELS].}

type
  ChannelLayout* = object of RootObj
  ChannelLayoutId* = distinct int

  ChannelId* = distinct int

  ChannelIndexArray* = FixedSeq[int, MAX_IMAGE_CHANNELS]
  ChannelIdArray* = FixedSeq[ChannelId, MAX_IMAGE_CHANNELS]

  ChannelLayoutDesc* {.deprecated.} = typedesc[ChannelLayout] or ChannelLayoutId


proc `==`*(a, b: typedesc[ChannelLayout]): bool {.inline, noSideEffect, raises: [].} =
  a is b and b is a


proc `==`*(a, b: ChannelLayoutId): bool {.borrow.}
proc `==`*(a, b: ChannelId): bool {.borrow.}


var
  channelLayoutIdCounter {.compileTime.} = 0
  channelIdCounter {.compileTime.} = 0
  channelIdTable {.compileTime.} = initTable[string, int]()

  channelLayoutNameSeq = newSeq[string]()
  channelNameSeq = newSeq[string]()

  channelLayoutChannelsSeq = newSeq[ChannelIdArray]()

iterator capitalTokenIter(str: string): string =
  var acc = newStringOfCap(str.len)

  for i, ch in pairs(str):
    if isUpperAscii(ch) and not acc.isNilOrEmpty:
      yield acc
      acc.setLen(0)
    acc.add(ch)

  # make sure to get the last one too
  if not acc.isNilOrEmpty:
    yield acc


iterator channelInfoGen(layout_str: string): (string, int, bool) =
  for s in capitalTokenIter(layout_str):
    var is_new = false

    if not channelIdTable.contains(s):
      channelIdTable[s] = channelIdCounter
      inc(channelIdCounter)
      is_new = true

    yield (s, channelIdTable[s], is_new)


# Old interface
proc capitalTokens(str: string): seq[string] {.compileTime, deprecated.} =
  result = newSeqOfCap[string](str.len)
  for tok in capitalTokenIter(str):
    result.add(tok)


proc channelMappingGen(layout_str: string): (NimNode, seq[(string, int)]) {.compileTime.} =
  var nameidseq = newSeqOfCap[(string, int)](layout_str.len)
  var stmts = newNimNode(nnkStmtList)

  for name, id, is_new in channelInfoGen(layout_str):
    nameidseq.add((name, id))

    if is_new:
      stmts.add(newCall(bindSym"add", [bindSym"channelNameSeq", newStrLitNode("ChId" & name)]))

  result = (stmts, nameidseq)


proc nodeToStr(node: NimNode): string {.compileTime.} =
  case node.kind:
    of nnkIdent:
      result = $node
    of nnkStrLit, nnkRStrLit:
      result = node.strVal
    else:
      quit "Expected identifier or string as channel layout specifier, but got " & $node & "."
  

proc emptyChannelIds*(): ChannelIdArray {.noSideEffect, inline, raises: [].} =
  result.len = 0

proc name*(layout_id: ChannelLayoutId): string {.noSideEffect, inline.} =
  channelLayoutNameSeq[layout_id.int]

proc name*(ch_id: ChannelId): string {.noSideEffect, inline.} =
  channelNameSeq[ch_id.int]

proc len*(layout_id: ChannelLayoutId): int {.noSideEffect, inline.} =
  channelLayoutChannelsSeq[layout_id.int].len

proc channels*(layout_id: ChannelLayoutId): ChannelIdArray {.noSideEffect, inline.} =
  channelLayoutChannelsSeq[layout_id.int]

proc channel*(layout_id: ChannelLayoutId, chid: ChannelId): int {.noSideEffect, inline.} =
  channelLayoutChannelsSeq[layout_id.int].find(chid)


proc `$`*(layout_id: ChannelLayoutId): string {.noSideEffect, inline.} =
  # ["ChannelLayout(", $(layout_id.int), ")"].join
  layout_id.name

proc `$`*(ch_id: ChannelId): string {.noSideEffect, inline.} =
  # ["Channel(", $(ch_id.int), ")"].join
  ch_id.name


proc declareChannelLayoutImpl*(nameNode: NimNode): NimNode {.compileTime.} =
  var id = channelLayoutIdCounter
  inc(channelLayoutIdCounter)

  let
    name = nodeToStr(nameNode)
    givenname = "ChLayout" & name

    layoutIdent = ident(givenname)

    (channelNameDefs, chanMeta) = channelMappingGen(name)

  var chans: ChannelIdArray
  chans.setLen(0)
  for name, ch in items(chanMeta):
    chans.add(ch.ChannelId)

  let
    nCh = chans.len
    maxCh = chans.len - 1


  # Declare compile time inline procedures for fetching channel layout
  # properties.
  result = quote do:
    type
      `layoutIdent`* = object of ChannelLayout

    proc id*(layout: typedesc[`layoutIdent`]): ChannelLayoutId {.noSideEffect, inline, raises: [].} = ChannelLayoutId(`id`)
    proc len*(layout: typedesc[`layoutIdent`]): Natural {.noSideEffect, inline, raises: [].} = `nCh`
    proc name*(layout: typedesc[`layoutIdent`]): string {.noSideEffect, inline, raises: [].} = `givenname`
    proc channels*(layout: typedesc[`layoutIdent`]): ChannelIdArray {.noSideEffect, inline, raises: [].} = `chans`
    proc channel*(layout: typedesc[`layoutIdent`], chid: ChannelId): int {.noSideEffect, inline, raises: [].} = find(`chans`, chid)

  # Add the runtime channel layout table insertion code.

  channelNameDefs.copyChildrenTo(result)

  result.add(newCall(bindSym"add", [ident"channelLayoutNameSeq", newStrLitNode(givenname)]))
  result.add(newCall(bindSym"add", [ident"channelLayoutChannelsSeq", newCall(bindSym"emptyChannelIds", [])]))

  # Add named channel accessors procedures
  var intermediate = newStmtList()
  for i, x in pairs(chanMeta):
    let
      (name, ch) = x
    
      nameIdent = ident("Ch" & name)
      idIdent = ident("ChId" & name)
      #nameLit = newStrLitNode(name)
      idExpr = newCall(bindSym"ChannelId", [newIntLitNode(ch.int)])

    let accessor = quote do:
      when not declared(`nameIdent`):
        # We must only declare this one time.
        proc `nameIdent`*(layout_id: ChannelLayoutId): Natural =
          layout_id.channel(`idExpr`)

      when not declared(`idIdent`):
        const `idIdent`* = `idExpr`

      proc `nameIdent`*(layout: typedesc[`layoutIdent`]): range[0..`maxCh`] = `i`

    result.add(newCall(bindSym"add", [parseExpr"channelLayoutChannelsSeq[^1]", idExpr]))
    accessor.copyChildrenTo(intermediate)

  intermediate.copyChildrenTo(result)


proc declareChannelLayoutPermuteImpl(nameNode: NimNode, stmts: var NimNode) {.compileTime.} =
  var
    channels = capitalTokens(nodeToStr(nameNode))

  sort(channels, system.cmp)
  while true:
    declareChannelLayoutImpl(newStrLitNode(channels.join)).copyChildrenTo(stmts)
    
    if not nextPermutation(channels):
      break


proc declareChannelGroupSeq(node: NimNode, stmts: var NimNode) {.compileTime.} =
  case node.kind:
    of nnkStrLit, nnkRStrLit, nnkIdent:
      declareChannelLayoutPermuteImpl(node, stmts)
    of nnkBracket:
      for child in node.children:
        declareChannelGroupSeq(child, stmts)
    else:
      quit "Expected string literal, identifier, or bracketed expression."


proc declareChannelGroupsImpl*(nameNodes: openarray[NimNode], stmts: var NimNode) {.compileTime.} =
  for node in nameNodes:
    declareChannelGroupSeq(node, stmts)


proc declareChannelGroupsWithAlphaImpl*(nameNodes: openarray[NimNode], stmts: var NimNode) {.compileTime.} =
  var extNodes = newSeqOfCap[NimNode](nameNodes.len * 2)
  for node in nameNodes:
    let nodeStr = nodeToStr(node)
    extNodes.add(ident(nodeStr))
    extNodes.add(ident(nodeStr & "A"))

  declareChannelGroupsImpl(extNodes, stmts)

macro declareChannelGroups*(nameNodes: varargs[untyped]): untyped =
  result = newStmtList()
  var nodes = newSeqOfCap[NimNode](nameNodes.len)
  for node in nameNodes: nodes.add(node)
  declareChannelGroupsWithAlphaImpl(nodes, result)


declareChannelGroups(
  "RGB",    # Red, Green, Blue
  "CMYe",   # Cyan, Magenta, Yellow
  "HSV",    # Hue, Saturation, Value
  "YCbCr",  # Luminance, Blue Difference, Red Difference
  "YpCbCr", # Luma, Blue Difference, Red Difference
  "Y",      # Luminance
  "Yp"      # Luma
)


proc cmpChannels*(a: typedesc, b: typedesc): ChannelIndexArray {.noSideEffect, inline, raises: [].} =
  for name in b.channels:
    result.add(find(a.channels, name))


proc cmpChannels*(a: ChannelLayoutId, b: ChannelLayoutId): ChannelIndexArray {.noSideEffect, inline.} =
  for name in b.channels:
    result.add(find(a.channels, name))


when isMainModule:
  template doRGBAProcs(what: untyped): untyped =
    echo what.name, ".ChR = ", what.ChR, " ", what.name, ".channel(\"R\") = ", what.channel("R")
    echo what.name, ".ChG = ", what.ChG, " ", what.name, ".channel(\"G\") = ", what.channel("G")
    echo what.name, ".ChB = ", what.ChB, " ", what.name, ".channel(\"B\") = ", what.channel("B")
    echo what.name, ".ChA = ", what.ChA, " ", what.name, ".channel(\"A\") = ", what.channel("A")

  template doYCbCrProcs(what: untyped): untyped =
    echo what.name, ".ChY  = ", what.ChY,  " ", what.name, ".channel(\"Y\")  = ", what.channel("Y")
    echo what.name, ".ChCb = ", what.ChCb, " ", what.name, ".channel(\"Cb\") = ", what.channel("Cb")
    echo what.name, ".ChCr = ", what.ChCr, " ", what.name, ".channel(\"Cr\") = ", what.channel("Cr")

  template doCmpChannelsTest(nam: untyped, a: untyped, b: untyped): untyped =
    echo "cmpChannels(", nam(a), ", ", nam(b), ") = ", cmpChannels(a, b)

  static:
    echo "*** COMPILE TIME TESTS ***"
    template doTest(layoutType: typedesc, body: untyped): untyped =
      echo "Testing ", layoutType.name, " (static type):"
      echo layoutType.name, ".id = ", layoutType.id
      echo layoutType.name, ".len = ", layoutType.len
      echo layoutType.name, ".channels = ", @(layoutType.channels)
      body
    
    doTest(ChLayoutRGBA): doRGBAProcs(ChLayoutRGBA)
    doTest(ChLayoutBGRA): doRGBAProcs(ChLayoutBGRA)

    doTest(ChLayoutYCbCr): doYCbCrProcs(ChLayoutYCbCr)
    doTest(ChLayoutYCrCb): doYCbCrProcs(ChLayoutYCrCb)

    echo " ~ cmpChannels ~"
    doCmpChannelsTest(name, ChLayoutRGBA, ChLayoutRGBA)
    doCmpChannelsTest(name, ChLayoutRGBA, ChLayoutARGB)
    doCmpChannelsTest(name, ChLayoutRGBA, ChLayoutRGB)
    doCmpChannelsTest(name, ChLayoutRGBA, ChLayoutBGRA)
    doCmpChannelsTest(name, ChLayoutRGBA, ChLayoutABGR)
    doCmpChannelsTest(name, ChLayoutRGBA, ChLayoutBGR)

  echo "*** RUN TIME TESTS ***"
  let myLayouts = [ChLayoutRGBA.id, ChLayoutBGRA.id, ChLayoutYCbCr.id, ChLayoutYCrCb.id]
  for i, layout in myLayouts:
    echo "Testing ", layout.name, " ", layout, ":"
    echo layout.name, ".len = ", layout.len
    echo layout.name, ".channels = ", @(layout.channels)
    if i > 1: doYCbCrProcs(layout) else: doRGBAProcs(layout)

  echo " ~ cmpChannels ~"
  doCmpChannelsTest(name, ChLayoutRGBA.id, ChLayoutRGBA.id)
  doCmpChannelsTest(name, ChLayoutRGBA.id, ChLayoutARGB.id)
  doCmpChannelsTest(name, ChLayoutRGBA.id, ChLayoutRGB.id)
  doCmpChannelsTest(name, ChLayoutRGBA.id, ChLayoutBGRA.id)
  doCmpChannelsTest(name, ChLayoutRGBA.id, ChLayoutABGR.id)
  doCmpChannelsTest(name, ChLayoutRGBA.id, ChLayoutBGR.id)
    

