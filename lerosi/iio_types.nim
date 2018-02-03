import macros, sequtils, strutils, tables, future
import system, arraymancer
#import ./channels
import ./macroutil
import ./fixedseq
import ./img_permute

const
  MAX_IMAGE_CHANNELS = 7

type
  ChannelIndex* = FixedSeq[int, MAX_IMAGE_CHANNELS]

  ImageFormat* = enum
    PNG, BMP, JPEG, HDR
  SaveOptions* = ref object
    case format*: ImageFormat
    of PNG:
      stride*: int
    of JPEG:
      quality*: int
    else:
      discard

  DataOrder* = enum
    DataInterleaved,
    DataPlanar

  ImageData*[T] = openarray[T] or AnyTensor[T]


var
  enableColorSubspaces: bool = true

  channelCounter     {.compileTime.} = 0
  channelNames       {.compileTime.} = newSeq[string]()
  channelColorspaces {.compileTime.} = newSeq[seq[int]]()

  colorspaceCounter {.compileTime.} = 0
  colorspaceNames   {.compileTime.} = newSeq[string]()
  colorspaceIndices {.compileTime.} = newSeq[ChannelIndex]()

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


proc asSingleColorSpaceCompiler(channelstr: string): int {.compileTime.} =
  if not colorspaceNames.contains(channelstr):
    inc(colorspaceCounter)
    result = colorspaceCounter

    var chindex: ChannelIndex
    chindex.setLen(0)
    for name in capitalTokenIter(channelstr):
      let i = name.asChannelCompiler
      chindex.add i
      channelColorspaces[i].add(colorspaceCounter)

    colorspaceNames.add channelstr
    colorspaceIndices.add chindex
  else:
    result = colorspaceNames.find(channelstr)


proc asColorSpaceCompilerImpl(channelseq: var FixedSeq[string, MAX_IMAGE_CHANNELS], count: int): int {.compileTime.} =
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

  
macro defineColorSpace(node: untyped): untyped =
  let name = nodeToStr(node)
  discard asColorSpaceCompiler(name)

proc defineColorSpaceWithAlphaProc(node: string) {.compileTime.} =
  discard asColorSpaceCompiler(node)
  discard asColorSpaceCompiler(node & "A")

macro defineColorSpaceWithAlpha(node: untyped): untyped =
  let name = nodeToStr(node)
  defineColorSpaceWithAlphaProc(name)


template getterPragmaAnyExcept: untyped =
  nnkPragma.newTree(
    ident"inline",
    ident"noSideEffect")

template getterPragma(exceptionList: untyped = newNimNode(nnkBracket)): untyped =
  getterPragmaAnyExcept().add(
    nnkExprColonExpr.newTree(ident"raises", exceptionList))


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
      type `typ` = distinct int

      proc channel_name*(T: typedesc[`typ`]):
        string {.inline, noSideEffect, raises: [].} = `name`
      proc `dollarProcVar`*(T: typedesc[`typ`]):
        string {.inline, noSideEffect, raises: [].} = `name`
      proc channel_type*(T: typedesc[`typ`]):
        typedesc[`typ`] {.inline, noSideEffect, raises: [].} = T
      proc channel_id*(T: typedesc[`typ`]):
        ColorChannel {.inline, noSideEffect, raises: [].} = `idident`

    st.copyChildrenTo(stmts)

    chidcases.add(newNimNode(nnkOfBranch).add(newLit(name), newAssignment(ident"result", idident)))
    chnamecases.add(newNimNode(nnkOfBranch).add(idident, newAssignment(ident"result", newLit(name))))

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

  var idproc = newProc(ident"channel_id", [
    ident"ColorChannel",
    newIdentDefs(ident"ch", ident"string")
  ])

  var nameproc = newProc(ident"channel_name", [
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
    csidcases = newNimNode(nnkCaseStmt).add(ident"cs")
    csnamecases = newNimNode(nnkCaseStmt).add(ident"cs")

  for csid, name in colorspaceNames:
    if skip:
      skip = false
      continue

    let
      typ = ident("ColorSpaceType" & name)
      idname = "ColorSpaceId" & name
      idident = ident(idname)

    var channelSet = newNimNode(nnkCurly)
    var channelChecks = newStmtList()
    #for chid in colorspaceIndices[csid]:
    var firstch = true
    for chid, chname in channelNames:
      if firstch:
        firstch = false
        continue

      let
        chident = ident("ChId" & chname)
        chtyp = ident("ChType" & chname)
        hasch: bool = 0 <= colorspaceIndices[csid].find(chid)
        chlit = if hasch: ident"true" else: ident"false"

      if hasch:
        channelSet.add(chident)
      
      let chk = quote do:
        proc colorspace_has_channel*(T: typedesc[`typ`], U: typedesc[`chtyp`]):
          bool {.inline, noSideEffect, raises: [].} = `chlit`

      chk.copyChildrenTo(channelChecks)

    let st = quote do:
      type `typ` = distinct int

      proc colorspace_name*(T: typedesc[`typ`]):
        string {.inline, noSideEffect, raises: [].} = `name`
      proc `dollarProcVar`*(T: typedesc[`typ`]):
        string {.inline, noSideEffect, raises: [].} = `name`
      proc colorspace_type*(T: typedesc[`typ`]):
        typedesc[`typ`] {.inline, noSideEffect, raises: [].} = T
      proc colorspace_id*(T: typedesc[`typ`]):
        ColorSpace {.inline, noSideEffect, raises: [].} = `idident`
      proc colorspace_channels*(T: typedesc[`typ`]):
        set[ColorChannel] {.inline, noSideEffect, raises: [].} = `channelSet`
      proc colorspace_has_channel*(T: typedesc[`typ`], ch: ColorChannel):
          bool {.inline, noSideEffect, raises: [].} =
        colorspace_channels(T).contains(ch)
      proc colorspace_has_subspace*(T: typedesc[`typ`], subch: set[ColorChannel]):
          bool {.inline, noSideEffect, raises: [].} =
        for ch in subch:
          if not colorspace_channels(T).contains(ch):
            return false
        return true

    st.copyChildrenTo(stmts)
    channelChecks.copyChildrenTo(stmts)

    csidcases.add(newNimNode(nnkOfBranch).add(newLit(name), newAssignment(ident"result", idident)))
    csnamecases.add(newNimNode(nnkOfBranch).add(idident, newAssignment(ident"result", newLit(name))))

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
    proc colorspace_has_subspace_proc*[T; U]:
        bool {.inline, noSideEffect, raises: [].} =
      const subchset = colorspace_channels(U)
      const hassubcs = colorspace_has_subspace(T, subchset)
      hassubcs

    template colorspace_has_subspace*(T, U: untyped): untyped =
      colorspace_has_subspace_proc[T, U]()

    proc colorspace_id*(cs: ColorSpace):
      ColorSpace {.inline, noSideEffect, raises: [].} = cs
    proc `dollarProcVar`*(cs: ColorSpace):
      string {.inline, noSideEffect, raises: [].} = colorspace_name(cs)
    proc colorspace_name*(cs: string):
      string {.inline, noSideEffect, raises: [].} = cs

  var idproc = newProc(ident"colorspace_id", [
    ident"ColorSpace",
    newIdentDefs(ident"cs", ident"string")
  ])

  var nameproc = newProc(ident"colorspace_name", [
    ident"string",
    newIdentDefs(ident"cs", ident"ColorSpace")
  ])

  idproc.body = newStmtList(csidcases)
  idproc.pragma = getterPragma(newNimNode(nnkBracket).add(ident"ValueError"))

  nameproc.body = newStmtList(csnamecases)
  nameProc.pragma = getterPragma()

  result.add idproc
  result.add nameproc

  addendum.copyChildrenTo(result)


proc makeColorSpaceRefs(): NimNode {.compileTime.} =
  var
    skip = true
    first = true
    chspacecases = newNimNode(nnkCaseStmt).add(ident"ch")

  for chid, name in channelNames:
    if skip:
      skip = false
      continue

    let
      chtyp = ident("ChType" & name)
      chident = ident("ChId" & name)

    let csidseq = channelColorspaces[chid]
    var csset = newNimNode(nnkCurly)

    for k, csid in csidseq:
      let
        csname = colorspaceNames[csid]
        cstyp = ident("ColorSpaceType" & csname)
        csident = ident("ColorSpaceId" & csname)

      csset.add(csident)

    chspacecases.add(newNimNode(nnkOfBranch).add(chident, newAssignment(ident"result", csset)))

  var spacesproc = newProc(ident"channel_get_colorspaces", [
    parseExpr"set[ColorSpace]",
    newIdentDefs(ident"ch", ident"ColorChannel")
  ])

  spacesproc.body = chspacecases
  spacesproc.pragma = getterPragma()

  result = newStmtList().add(spacesproc)

      
macro declareColorSpaceMetadata(): untyped =
  result = makeChannels()
  makeColorSpaces().copyChildrenTo(result)
  makeColorSpaceRefs().copyChildrenTo(result)


# Solitary alpha channel
defineColorSpace"A"

# Spaces with optional alpha channel
defineColorSpaceWithAlpha"Y"
defineColorSpaceWithAlpha"Yp"
defineColorSpaceWithAlpha"RGB"
defineColorSpaceWithAlpha"CMYe"
defineColorSpaceWithAlpha"HSV"
defineColorSpaceWithAlpha"YCbCr"
defineColorSpaceWithAlpha"YpCbCr"

static:
  echo "Channels ", $channelNames
  echo "ColorSpaces ", $colorspaceNames

#expandMacros:
declareColorSpaceMetadata()

type
  ColorSpaceAnyType* = distinct int


type
  StaticOrderImage*[T; S; O: static[DataOrder]] = object
    ind: ChannelIndex
    dat: Tensor[T]
    cspace: ColorSpace

  DynamicOrderImage*[T; S] = object
    ind: ChannelIndex
    dat: Tensor[T]
    cspace: ColorSpace
    order: DataOrder

  SomeImage* = distinct int #StaticOrderImage | DynamicOrderImage

  IIOError* = object of Exception


proc imageAccessor(targetProc: NimNode, allowMutableImages: bool):
    NimNode {.compileTime.} =

  let
    targetParams = targetProc.params
    targetGenericParams = targetProc[2]

  var
    staticBody = newStmtList()
    dynamicBody = newStmtList()
    targetBody = body(targetProc)

  staticBody.add(parseStmt"const isStaticTarget = true")
  dynamicBody.add(parseStmt"const isStaticTarget = false")
  targetBody.copyChildrenTo(staticBody)
  targetBody.copyChildrenTo(dynamicBody)

  template genparam_or_new(gparam: untyped): untyped =
    if gparam.kind == nnkEmpty: nnkGenericParams.newTree else: gparam.copy

  var
    staticParams = targetProc.params.copy
    dynamicParams = targetProc.params.copy

  iterator paramsOfType(node: NimNode, name: string, allow: bool): int =
    var count: int = 0
    for ch in node.children:
      case ch.kind:
      of nnkIdentDefs:
        if allow:
          case ch[1].kind:
          of nnkIdent:
            if $ch[1] == name:
              yield count
          of nnkVarTy:
            if $ch[1][0] == name:
              yield count
          else: discard
        elif $ch[1] == name:
          yield count
      else: discard

      inc count

  template process_params(params, variant: untyped): untyped =
    for i in params.paramsOfType("SomeImage", allowMutableImages):
      case params[i].kind:
      of nnkIdentDefs:
        if params[i][1].kind == nnkVarTy:
          params[i][1][0] = variant.copy
        else:
          params[i][1] = variant.copy
      else: discard


  let
    staticVariant = nnkBracketExpr.newTree(
      ident"StaticOrderImage", ident"T", ident"S", ident"O")
    dynamicVariant = nnkBracketExpr.newTree(
      ident"DynamicOrderImage", ident"T", ident"S")

  process_params(staticParams, staticVariant)
  process_params(dynamicParams, dynamicVariant)

  result = newStmtList()
  
  # StaticOrderImage procedure
  result.add nnkProcDef.newTree(
    targetProc[0],
    newEmptyNode(),
    nnkGenericParams.newTree(
    nnkIdentDefs.newTree(
      ident"T", ident"S",
      newEmptyNode(),
      newEmptyNode()),
    nnkIdentDefs.newTree(
      ident"O",
      nnkStaticTy.newTree(bindSym"DataOrder"),
      newEmptyNode())),
    staticParams.copy,
    getterPragmaAnyExcept(),
    newEmptyNode(),
    staticBody
  )

  # DynamicOrderImage procedure
  result.add nnkProcDef.newTree(
    targetProc[0],
    newEmptyNode(),
    nnkGenericParams.newTree(
    nnkIdentDefs.newTree(
      ident"T", ident"S",
      newEmptyNode(),
      newEmptyNode())),
    dynamicParams.copy,
    getterPragmaAnyExcept(),
    newEmptyNode(),
    dynamicBody
  )

macro imageGetter(targetProc: untyped): untyped =
  result = imageAccessor(targetProc, false)

macro imageMutator(targetProc: untyped): untyped =
  result = imageAccessor(targetProc, true)


proc index*(img: SomeImage): ChannelIndex {.imageGetter.} =
  img.ind

proc `index=`*(img: var SomeImage, ind: ChannelIndex) {.imageMutator.} =
  img.ind = ind

proc storage_order*(img: SomeImage): DataOrder {.imageGetter.} =
  when isStaticTarget: O else: img.order

proc `storage_order=`*(img: var DynamicOrderImage, order: DataOrder) {.inline, raises: [].} =
  img.order = order

proc colorspace*(img: SomeImage): ColorSpace {.imageGetter.} =
  when not (S is ColorSpaceAnyType): S.colorspace_id
  else: img.cspace

proc `colorspace=`*(img: var SomeImage, cspace: ColorSpace) {.imageMutator.} =
  when not (S is ColorSpaceAnyType):
    raise newException(Exception,
      "Cannot set the colorspace on a static colorspace object.")
  else:
    img.cspace = cspace


when isMainModule:
  import typetraits

  template has_subspace_test(sp1, sp2, expect: untyped): untyped =
    echo $(sp1), ".colorspace_has_subspace(", $(sp2), ") = ", sp1.colorspace_has_subspace(sp2)
    if sp1.colorspace_has_subspace(sp2) == expect:
      echo " [ok]"
    else:
      echo " [expected ", $(expect), "]"


  template image_statictype_test(datatype, cspace, order: untyped): untyped =
    var myImg: StaticOrderImage[datatype, cspace, order]
    echo type(myImg).name, " :"
    echo "  T = ", type(myImg.T).name
    echo "  S = ", type(myImg.S).name
    echo "  O = ", type(myImg.O).name

    when cspace is ColorSpaceAnyType:
      echo "do: myImg.colorspace = ", ColorSpaceIdYpCbCr
      myImg.colorspace = ColorSpaceIdYpCbCr
      echo "{OK} assignment over dynamic colorspace succeeded expectedly."
    else:
      try:
        myImg.colorspace = ColorSpaceIdYpCbCr
      except:
        echo "{OK} assignment over static colorspace failed expectedly."

    echo "myImg.storage_order = ", myImg.storage_order
    echo "myImg.colorspace = ", myImg.colorspace
    echo "myImg.index = ", myImg.index


  template image_dynamictype_test(datatype, cspace, order: untyped): untyped =
    var myImg: DynamicOrderImage[datatype, cspace]
    echo type(myImg).name, " :"
    echo "  T = ", type(myImg.T).name
    echo "  S = ", type(myImg.S).name

    when cspace is ColorSpaceAnyType:
      echo "do: myImg.colorspace = ", ColorSpaceIdYpCbCr
      myImg.colorspace = ColorSpaceIdYpCbCr
      echo "{OK} assignment over dynamic colorspace succeeded expectedly."
    else:
      try:
        myImg.colorspace = ColorSpaceIdYpCbCr
      except:
        echo "{OK} assignment over static colorspace failed expectedly."

    myImg.storage_order = order
    echo "myImg.storage_order = ", myImg.storage_order
    echo "myImg.colorspace = ", myImg.colorspace
    echo "myImg.index = ", myImg.index

  template image_statictype_test_il(datatype, cspace: untyped): untyped =
    image_statictype_test(datatype, cspace, DataInterleaved)

  template image_statictype_test_pl(datatype, cspace: untyped): untyped =
    image_statictype_test(datatype, cspace, DataPlanar)

  template image_dynamictype_test_il(datatype, cspace: untyped): untyped =
    image_dynamictype_test(datatype, cspace, DataInterleaved)

  template image_dynamictype_test_pl(datatype, cspace: untyped): untyped =
    image_dynamictype_test(datatype, cspace, DataPlanar)


  template has_subspace_test_suite(): untyped =
    has_subspace_test(ColorSpaceTypeRGB, ColorSpaceTypeRGBA, false)
    has_subspace_test(ColorSpaceTypeRGB, ColorSpaceTypeRGB, true)
    has_subspace_test(ColorSpaceTypeRGB, ColorSpaceTypeRG, true)
    has_subspace_test(ColorSpaceTypeRGB, ColorSpaceTypeGB, true)
    has_subspace_test(ColorSpaceTypeRGB, ColorSpaceTypeRB, true)
    has_subspace_test(ColorSpaceTypeRGB, ColorSpaceTypeRBA, false)

  static:
    echo " ~ Compile-time Test ~"
    has_subspace_test_suite()

    image_statictype_test_il(byte, ColorSpaceTypeRGB)
    image_statictype_test_pl(byte, ColorSpaceTypeRGB)
    image_statictype_test_il(byte, ColorSpaceTypeCMYe)
    image_statictype_test_pl(byte, ColorSpaceTypeCMYe)
    image_statictype_test_il(byte, ColorSpaceAnyType)
    image_statictype_test_pl(byte, ColorSpaceAnyType)

  echo " ~ Run-time Test ~"
  has_subspace_test_suite()

  image_statictype_test_il(byte, ColorSpaceTypeRGB)
  image_statictype_test_pl(byte, ColorSpaceTypeRGB)
  image_statictype_test_il(byte, ColorSpaceTypeCMYe)
  image_statictype_test_pl(byte, ColorSpaceTypeCMYe)
  image_statictype_test_il(byte, ColorSpaceAnyType)
  image_statictype_test_pl(byte, ColorSpaceAnyType)

  image_dynamictype_test_il(byte, ColorSpaceTypeRGB)
  image_dynamictype_test_pl(byte, ColorSpaceTypeRGB)
  image_dynamictype_test_il(byte, ColorSpaceTypeCMYe)
  image_dynamictype_test_pl(byte, ColorSpaceTypeCMYe)
  image_dynamictype_test_il(byte, ColorSpaceAnyType)
  image_dynamictype_test_pl(byte, ColorSpaceAnyType)

#proc newDynamicLayoutImage*[T](w, h: int; lid: ChannelLayoutId;
#                        order: DataOrder = DataPlanar):
#                        DynamicLayoutImageRef[T] {.noSideEffect, inline.} =
#  let data: Tensor[T] =
#    if order == DataPlanar:
#      newTensorUninit[T]([lid.len, h, w])
#    else:
#      newTensorUninit[T]([h, w, lid.len])
#
#  result = DynamicLayoutImageRef[T](data: data, lid: lid, order: order)
#
#
#proc newStaticLayoutImage*[T; L: ChannelLayout](w, h: int;
#                        order: DataOrder = DataPlanar):
#                        StaticLayoutImageRef[T, L] {.noSideEffect, inline.} =
#  let data: Tensor[T] =
#    if order == DataPlanar:
#      newTensorUninit[T]([L.len, h, w])
#    else:
#      newTensorUninit[T]([h, w, L.len])
#
#  result = StaticLayoutImageRef[T, L](data: data, order: order)
#
#
#proc newDynamicLayoutImageRaw*[T](data: Tensor[T]; lid: ChannelLayoutId;
#                           order: DataOrder):
#                           DynamicLayoutImageRef[T] {.noSideEffect, inline.} =
#  DynamicLayoutImageRef[T](data: data, lid: lid, order: order)
#
#
#proc newDynamicLayoutImageRaw*[T](data: seq[T]; lid: ChannelLayoutId;
#                           order: DataOrder):
#                           DynamicLayoutImageRef[T] {.noSideEffect, inline.} =
#  newDynamicLayoutImageRaw[T](data.toTensor, lid, order)
#
#
#proc newStaticLayoutImageRaw*[T; L: ChannelLayout](data: Tensor[T];
#                           order: DataOrder):
#                           StaticLayoutImageRef[T, L] {.noSideEffect, inline.} =
#  StaticLayoutImageRef[T](data: data, order: order)
#
#
#proc newStaticLayoutImageRaw*[T; L: ChannelLayout](data: seq[T];
#                           order: DataOrder):
#                           StaticLayoutImageRef[T, L] {.noSideEffect, inline.} =
#  newStaticLayoutImageRaw[T](data.toTensor, order)
#
#
#proc shallowCopy*[O: DynamicLayoutImageRef](img: O): O {.noSideEffect, inline.} =
#  O(data: img.data, lid: img.layoutId, order: img.order)
#
#
#proc shallowCopy*[O: StaticLayoutImageRef](img: O): O {.noSideEffect, inline.} =
#  O(data: img.data, order: img.order)
#
#
## Renamed clone to shallowCopy because clone is not really a semantically
## correct name in the intuitive sense. A clone implies everything is
## duplicated, when in fact only the top level object fields are copied,
## and the data are not.
#{.deprecated: [clone: shallowCopy].}
#
#proc layoutId*[ImgT: DynamicLayoutImageRef](img: ImgT):
#              ChannelLayoutId {.noSideEffect, inline, raises: [].} =
#  img.lid
#
#proc layoutId*[ImgT: StaticLayoutImageRef](img: ImgT):
#              ChannelLayoutId {.noSideEffect, inline, raises: [].} =
#  ImgT.L.id
#
#
## We only have implicit conversions to dynamic layout images. Conversion to
## static layout must be explicit or else the user could unknowingly introduce
## unwanted colorspace conversions.
#converter toDynamicLayoutImage*[O: StaticLayoutImageRef](img: O):
#  DynamicLayoutImageRef[O.T] {.inline, raises: [].} =
#
#  DynamicLayoutImageRef[O.T](data: img.data, lid: img.layoutId, order: img.order)
#
#
#macro staticDynamicImageGetter(procname: untyped, returntype: untyped, inner: untyped): untyped =
#  result = quote do:
#    proc `procname`*[O: DynamicLayoutImageRef](img: O): `returntype` {.inline, noSideEffect.} =
#      ## Dynamic image channel layout variant of `procname`.
#      `inner`(img.lid)
#
#    proc `procname`*[O: StaticLayoutImageRef](img: O): `returntype` {.inline, noSideEffect, raises: [].} =
#      ## Static image channel layout variant of `procname`.
#      `inner`(O.L)
#
#
#staticDynamicImageGetter(channelLayoutLen, range[1..MAX_IMAGE_CHANNELS], len)
#staticDynamicImageGetter(channelLayoutName, string, name)
#staticDynamicImageGetter(channels, ChannelIdArray, channels)
#
#{.deprecated: [channelCount: channelLayoutLen].}
#
#
#proc width*[O: ImageRef](img: O): int {.inline, noSideEffect.} =
#  let shape = img.data.shape
#  case img.order:
#    of DataPlanar: shape[^1]
#    of DataInterleaved: shape[^2]
#
#
#proc height*[O: ImageRef](img: O): int {.inline, noSideEffect.} =
#  let shape = img.data.shape
#  case img.order:
#    of DataPlanar: shape[^2]
#    of DataInterleaved: shape[^3]
#
#
#proc planar*[O: ImageRef](image: O): O {.noSideEffect, inline.} =
#  if image.order == DataInterleaved:
#    result = image.shallowCopy
#    result.data = image.data.to_chw().asContiguous()
#    result.order = DataPlanar
#  else:
#    result = image
#
#
#proc interleaved*[O: ImageRef](image: O): O {.noSideEffect, inline.} =
#  if image.order == DataPlanar:
#    result = image.shallowCopy
#    result.data = image.data.to_hwc().asContiguous()
#    result.order = DataInterleaved
#  else:
#    result = image
#
#proc setOrdering*[O: ImageRef](image: var O, e: DataOrder) {.noSideEffect, inline.} =
#  if not (image.order == e):
#    image.order = e
#    if e == DataPlanar:
#      image.data = image.data.to_chw().asContiguous()
#    else:
#      image.data = image.data.to_hwc().asContiguous()


