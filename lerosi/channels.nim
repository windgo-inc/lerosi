import os, system, macros, future
import strutils, sequtils, sets, algorithm
import fixedseq


const MAX_CHANNELS = 16


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


# Old interface
proc capitalTokens(str: string): seq[string] {.inline.} =
  result = newSeqOfCap[string](str.len)
  for tok in capitalTokenIter(str):
    result.add(tok)


proc nodeToStr(node: NimNode): string {.compileTime.} =
  case node.kind:
    of nnkIdent:
      result = $node
    of nnkStrLit, nnkRStrLit:
      result = node.strVal
    else:
      quit "Expected identifier or string as channel layout specifier, but got " & $node & "."
  

var channelLayoutIdCounter {.compileTime.} = 0
var channelIdCounter {.compileTime.} = 0

type
  ChannelLayout* = object of RootObj
  ChannelLayoutId* = distinct int
  ChannelId = distinct int

  ChannelNameArray* = FixedSeq[string, MAX_CHANNELS]

var
  channelLayoutNameSeq = newSeq[string]()
  channelLayoutChannelsSeq = newSeq[ChannelNameArray]()


proc emptyChannelNames*(): ChannelNameArray =
  result.len = 0

proc `$`(layout_id: ChannelLayoutId): string {.inline.} =
  ["ChannelLayout(", $(layout_id.int), ")"].join

proc name*(layout_id: ChannelLayoutId): string {.inline.} =
  channelLayoutNameSeq[layout_id.int]

proc len*(layout_id: ChannelLayoutId): int {.inline.} =
  channelLayoutChannelsSeq[layout_id.int].len

proc channels*(layout_id: ChannelLayoutId): ChannelNameArray {.inline.} =
  channelLayoutChannelsSeq[layout_id.int]

proc channel*(layout_id: ChannelLayoutId, name: string): int {.inline.} =
  channelLayoutChannelsSeq[layout_id.int].find(name)


proc declareChannelLayoutImpl(nameNode: NimNode): NimNode {.compileTime.} =
  var id = channelLayoutIdCounter
  inc(channelLayoutIdCounter)

  let
    name = nodeToStr(nameNode)

    layoutIdent = ident(name)

    chans = capitalTokens(`name`)
    nCh = chans.len
    maxCh = chans.len - 1

  # Declare compile time inline procedures for fetching channel layout
  # properties.
  result = quote do:
    type
      `layoutIdent`* = object of ChannelLayout

    proc id*(layout: typedesc[`layoutIdent`]): ChannelLayoutId {.inline, raises: [].} = ChannelLayoutId(`id`)
    proc len*(layout: typedesc[`layoutIdent`]): Natural {.inline, raises: [].} = `nCh`
    proc name*(layout: typedesc[`layoutIdent`]): string {.inline, raises: [].} = `name`
    proc channels*(layout: typedesc[`layoutIdent`]): array[0..`maxCh`, string] {.inline, raises: [].} = `chans`
    proc channel*(layout: typedesc[`layoutIdent`], name: string): int {.inline, raises: [].} = find(`chans`, name)

  # Add the runtime channel layout table insertion code.
  result.add(newCall(bindSym"add", [ident"channelLayoutNameSeq", newStrLitNode(name)]))
  result.add(newCall(bindSym"add", [ident"channelLayoutChannelsSeq", newCall(bindSym"emptyChannelNames", [])]))

  # Add named channel accessors procedures
  var intermediate = newStmtList()
  for i, name in chans:
    let nameIdent = ident("Ch" & name)
    let nameLit = newStrLitNode(name)

    let accessor = quote do:
      when not declared(`nameIdent`):
        # We must only declare this one time.
        proc `nameIdent`*(layout_id: ChannelLayoutId): Natural =
          layout_id.channel(`nameLit`)

      proc `nameIdent`*(layout: typedesc[`layoutIdent`]): range[0..`maxCh`] = `i`

    result.add(newCall(bindSym"add", [parseExpr"channelLayoutChannelsSeq[^1]", newStrLitNode(name)]))
    accessor.copyChildrenTo(intermediate)

  intermediate.copyChildrenTo(result)


proc declareChannelLayoutPermuteImpl(nameNode: NimNode): NimNode {.compileTime.} =
  var
    channels = capitalTokens(nodeToStr(nameNode))

  result = newStmtList()

  sort(channels, system.cmp)
  while true:
    declareChannelLayoutImpl(newStrLitNode(channels.join)).copyChildrenTo(result)
    
    if not nextPermutation(channels):
      break


proc declareChannelGroupSeq(node: NimNode): NimNode {.compileTime.} =
  result = newStmtList()
  case node.kind:
    of nnkStrLit, nnkRStrLit, nnkIdent:
      declareChannelLayoutPermuteImpl(node).copyChildrenTo(result)
    of nnkBracket:
      for child in node.children:
        declareChannelGroupSeq(child).copyChildrenTo(result)
    else:
      quit "Expected string literal, identifier, or bracketed expression."


macro declareChannelGroups*(nameNodes: varargs[untyped]): untyped =
  result = newStmtList()
  for node in nameNodes:
    declareChannelGroupSeq(node).copyChildrenTo(result)

#proc getSwizzle(a: typedesc[])

when isMainModule:
  #expandMacros:
  declareChannelGroups("RGB", "YUV", "YCbCr")
  declareChannelGroups("RGBA", "YUVA", "YCbCrA")

  template doRGBAProcs(what: untyped): untyped =
    echo what.name, ".ChR = ", what.ChR, " ", what.name, ".channel(\"R\") = ", what.channel("R")
    echo what.name, ".ChG = ", what.ChG, " ", what.name, ".channel(\"G\") = ", what.channel("G")
    echo what.name, ".ChB = ", what.ChB, " ", what.name, ".channel(\"B\") = ", what.channel("B")
    echo what.name, ".ChA = ", what.ChA, " ", what.name, ".channel(\"A\") = ", what.channel("A")

  template doYCbCrProcs(what: untyped): untyped =
    echo what.name, ".ChY  = ", what.ChY,  " ", what.name, ".channel(\"Y\")  = ", what.channel("Y")
    echo what.name, ".ChCb = ", what.ChCb, " ", what.name, ".channel(\"Cb\") = ", what.channel("Cb")
    echo what.name, ".ChCr = ", what.ChCr, " ", what.name, ".channel(\"Cr\") = ", what.channel("Cr")

  static:
    echo "*** COMPILE TIME TESTS ***"
    template doTest(layoutType: typedesc, body: untyped): untyped =
      echo "Testing ", layoutType.name, " (static type):"
      echo layoutType.name, ".id = ", layoutType.id
      echo layoutType.name, ".len = ", layoutType.len
      echo layoutType.name, ".channels = ", @(layoutType.channels)
      body
    
    doTest(RGBA): doRGBAProcs(RGBA)
    doTest(BGRA): doRGBAProcs(BGRA)

    doTest(YCbCr): doYCbCrProcs(YCbCr)
    doTest(YCrCb): doYCbCrProcs(YCrCb)

  echo "*** RUN TIME TESTS ***"
  let myLayouts = [RGBA.id, BGRA.id, YCbCr.id, YCrCb.id]
  for i, layout in myLayouts:
    echo "Testing ", layout.name, " ", layout, ":"
    echo layout.name, ".len = ", layout.len
    echo layout.name, ".channels = ", @(layout.channels)
    if i > 1: doYCbCrProcs(layout) else: doRGBAProcs(layout)
    

