import macros, sequtils, strutils, tables, future
import system

import ./macroutil
import ./fixedseq
import ./dataframe
import ./spaceconf

import ./backend

export spaceconf, dataframe, backend

type
  ChannelLayout* = object
    cspace: ChannelSpace
    mapping: ChannelMap

  ChannelLayoutOption* {.deprecated.} = enum
    LayoutWithAlpha,
    LayoutReversed

  RawImageObject*[Frame] = object
    fr: Frame

  DynamicImageObject*[Frame] = object
    lay: ChannelLayout
    fr: Frame


#proc initChannelLayout(cs: ChannelSpace, opt: set[ChannelLayoutOption] = {}):
#    ChannelLayout {.deprecated, inline, noSideEffect, raises: [].} =
#  ## Initialize a channel layout object.
#  result.cspace = cs
#  result.mapping = order(cs)
#  if not opt.contains(LayoutWithAlpha):
#    discard result.mapping.remove(VideoChIdA)
#  if opt.contains(LayoutReversed):
#    result.mapping = result.mapping.reversed

proc initChannelLayout(cs: ChannelSpace; m: ChannelMap):
    ChannelLayout {.inline, noSideEffect, raises: [].} =
  ## Initialize a channel layout object 
  when compileOption("boundChecks"):
    assert(m.len <= len(cs))
    let chs = cs.channels
    for ch in m: assert(chs.contains(ch))

  result.cspace = cs
  result.mapping = m

proc channelspace*(layout: ChannelLayout):
    ChannelSpace {.inline, noSideEffect, raises: [].} =
  ## Get the channelspace
  result = layout.cspace

proc mapping*(layout: ChannelLayout):
    ChannelMap {.inline, noSideEffect, raises: [].} =
  ## Get the channelspace
  result = layout.mapping

proc `mapping=`*(layout: var ChannelLayout, m: ChannelMap)
    {.inline, noSideEffect, raises: [].} =
  ## Set the channel mapping
  when compileOption("boundChecks"):
    assert(m.len <= len(layout.channelspace))

  layout.mapping = m
  

proc data_frame*
    [ImgObj: RawImageObject|DynamicImageObject](
    img: ImgObj): ImgObj.Frame {.inline, noSideEffect, raises: [].} =
  ## Get the underlying data frame.
  img.fr

proc data_frame*
    [ImgObj: RawImageObject|DynamicImageObject](
    img: var ImgObj): var ImgObj.Frame {.inline, noSideEffect, raises: [].} =
  ## Get the variable reference to the underlying data frame.
  img.fr

proc mapping*[ImgObj: DynamicImageObject](img: ImgObj):
    ChannelMap {.inline, noSideEffect, raises: [].} =
  ## Get the channel mapping from the channel layout.
  img.lay.mapping

proc channelspace*[ImgObj: DynamicImageObject](img: ImgObj):
    ChannelSpace {.inline, noSideEffect, raises: [].} =
  ## Get the channel mapping from the channel layout.
  img.lay.cspace

proc layout*[ImgObj: DynamicImageObject](img: ImgObj):
    ChannelLayout {.inline, noSideEffect, raises: [].} =
  ## Get the channel layout.
  img.lay

#proc layout*[ImgObj: DynamicImageObject](
#    img: var ImgObj, cs: ChannelSpace,
#    opt: set[ChannelLayoutOption] = {}): var ImgObj {.discardable, inline, deprecated.} =
#  ## Set the channel
#  img.lay = initChannelLayout(cs, opt)
#  result = img

proc layout*[ImgObj: DynamicImageObject](
    img: var ImgObj, cs: ChannelSpace,
    m: ChannelMap): var ImgObj {.discardable, inline.} =
  ## Set the channel
  img.lay = initChannelLayout(cs, m)
  result = img

proc `channelspace=`*[ImgObj: DynamicImageObject](
    img: var ImgObj, cs: ChannelSpace)
    {.inline, noSideEffect, raises: [].} =
  ## Set the channelspace wiuth a default mapping.
  img.layout(cs, cs.order)

proc `mapping=`*[ImgObj: DynamicImageObject](img: var ImgObj, m: ChannelMap)
    {.inline, noSideEffect, raises: [].} =
  ## Set the channel mapping
  img.lay.mapping = m

type
  BaseImage*[Frame] = concept img
    img.data_frame is Frame

  OrderedImage*[Frame] = concept img
    img is BaseImage[Frame]
    img.data_frame is OrderedDataFrame

  UnorderedImage*[Frame] = concept img
    img is BaseImage[Frame]
    img.data_frame is UnorderedDataFrame

  WriteOnlyImage*[Frame] = concept img
    img is BaseImage[Frame]
    img.data_frame is WriteOnlyDataFrame

  WritableImage*[Frame] = concept img
    img is BaseImage[Frame]
    img.data_frame is WriteDataFrame

  ReadOnlyImage*[Frame] = concept img
    img is BaseImage[Frame]
    img.data_frame is ReadOnlyDataFrame

  ReadableImage*[Frame] = concept img
    img is BaseImage[Frame]
    img.data_frame is ReadDataFrame

  MutableImage*[Frame] = concept img
    img is WritableImage[Frame]
    img is ReadableImage[Frame]

  StructuredImage*[Frame] = concept img
    img is BaseImage[Frame]
    img.channelspace is ChannelSpace
    img.mapping is ChannelMap

  UnstructuredImage*[Frame] = concept img
    img is BaseImage[Frame]
    not (img is StructuredImage[Frame])


proc defChannelMap*(s: string): ChannelMap {.inline.} =
  var toks = capitalTokens(s)
  let namespace = toks[0]
  let channels = toks[1..^1].map(na => channelof(namespace & na))
  initChannelMap(result, channels)


proc defChannelMap*(cs: ChannelSpace; s: string): ChannelMap {.inline.} =
  let ns = cs.namespace
  var toks = capitalTokens(s)
  result.setLen 0
  for i in 0..<toks.len:
    let ch = channelof(ns & toks[i])
    when compileOption("boundChecks"):
      assert ch in cs.channels, "Channel " & ch.name &
        " cannot be mapped in channelspace " & cs.name
    result.add ch


proc possibleChannelSpaces(mapping: ChannelMap; num_options: var int): set[ChannelSpace] {.inline.} =
  var
    first = true
    revised: set[ChannelSpace]

  for ch in mapping:
    if first:
      result = ch.channelspaces
      first = false
    else:
      num_options = 0
      revised = {}
      for cs in ch.channelspaces:
        if cs in result:
          revised.incl(cs)
          inc num_options
      
      result = revised

proc possibleChannelSpaces*(mapping: ChannelMap): set[ChannelSpace] {.inline.} =
  var x: int
  possibleChannelSpaces(mapping, x)

proc defChannelLayout*(cs: ChannelSpace, s: string): ChannelLayout {.inline, eagerCompile.} =
  result = initChannelLayout(cs, defChannelMap(cs, s))


proc defChannelLayout*(s: string): ChannelLayout {.inline, eagerCompile.} =
  var 
    num_options: int
    space: ChannelSpace
    found_space = false

  let
    mapping = defChannelMap(s)
    possibilities = possibleChannelSpaces(mapping, num_options)

  # Finally, pick the first possibility. This may be unstable if more than one
  # possibility exists.
  
  #if num_options > 1:
  #  echo "Warning: There is ambiguity in the channelspaces that can be chosen with ", s, ":"
  #  for cs in possibilities:
  #    echo "    ", cs.name

  for cs in possibilities:
    space = cs
    found_space = true
    break

  if not found_space:
    quit "No channelspace containing channels " & $mapping

  #echo "Found mapping ", mapping, " with spaces ", possibilities, "."
  result = initChannelLayout(space, mapping)

when isMainModule:
  import typetraits

  template do_dynamic_layout_props_tests(cs: untyped): untyped =
    var img1: DynamicImageObject[OrderedRWFrameObject[AmBackendCpu[byte]]]
    stdout.write "Getters for "
    trace_result(type(img1).name)
    
    img1.channelspace = cs

    trace_result(img1.channelspace)
    trace_result(img1.mapping)

  let mystr = "RGBA"

  let rtRgba = defChannelLayout("Video" & mystr) # This will force runtime computation.

  template print_channel_layout_t(name, layout: untyped): untyped =
    echo "    # ", name
    echo "    #    channelspace: ", layout.channelspace
    echo "    #    mapping:      ", layout.mapping

  macro print_channel_layout(layout: untyped): untyped =
    let name = toStrLit(layout)
    result = getAst(print_channel_layout_t(name, layout))

  template test_channel_layouts(stage: string): untyped = 
    echo "    # (!) Testing channel layout generator at ", stage
    echo "    # Test static channel layout generator (alpha)"
    print_channel_layout(defChannelLayout"VideoA")
    echo "    # Test static channel layout generator (RGB)"
    print_channel_layout(defChannelLayout"VideoRGBA")
    print_channel_layout(defChannelLayout"VideoBGRA")
    print_channel_layout(defChannelLayout"VideoARGB")
    print_channel_layout(defChannelLayout"VideoABGR")
    print_channel_layout(defChannelLayout"VideoRGB")
    print_channel_layout(defChannelLayout"VideoBGR")
    echo "    # Test static channel layout generator (luma-chrominance)"
    print_channel_layout(defChannelLayout"VideoYp")
    print_channel_layout(defChannelLayout"VideoY")
    print_channel_layout(defChannelLayout"VideoCbCrYp")
    print_channel_layout(defChannelLayout"VideoCrCbYp")
    print_channel_layout(defChannelLayout"VideoYpCbCr")
    print_channel_layout(defChannelLayout"VideoYpCrCb")
    print_channel_layout(defChannelLayout"VideoCbCr")
    print_channel_layout(defChannelLayout"VideoCrCb")
    print_channel_layout(defChannelLayout"VideoYCbCr")
    print_channel_layout(defChannelLayout"VideoYCrCb")
    print_channel_layout(defChannelLayout"VideoCbCrY")
    print_channel_layout(defChannelLayout"VideoCrCbY")
    echo "    # Test static channel layout generator (CMYe print and CMYe video)"
    print_channel_layout(defChannelLayout"PrintK")
    print_channel_layout(defChannelLayout"PrintKCMYe")
    print_channel_layout(defChannelLayout"PrintCMYeK")
    print_channel_layout(defChannelLayout"PrintCMYe")
    print_channel_layout(defChannelLayout"VideoCMYeA")
    print_channel_layout(defChannelLayout"VideoCMYe")

  static:
    test_channel_layout"compile-time"

  test_channel_layout"run-time"

  do_dynamic_layout_props_tests(VideoChSpaceRGB)
  do_dynamic_layout_props_tests(VideoChSpaceYpCbCr)



