import macros, sequtils, strutils, tables, future
import system

import ./macroutil
import ./fixedseq
import ./dataframe
import ./img_conf

import ./backend/am

export img_conf, dataframe

type
  ChannelLayout* = object
    cspace: ChannelSpace
    mapping: ChannelMap

  ChannelLayoutOption* = enum
    LayoutWithAlpha,
    LayoutReversed

  RawImageObject*[Frame] = object
    fr: Frame

  DynamicImageObject*[Frame] = object
    lay: ChannelLayout
    fr: Frame


proc initChannelLayout(cs: ChannelSpace, opt: set[ChannelLayoutOption] = {}):
    ChannelLayout {.inline, noSideEffect, raises: [].} =
  ## Initialize a channel layout object.
  result.cspace = cs
  result.mapping = order(cs)
  if not opt.contains(LayoutWithAlpha):
    dec result.mapping.len
  if opt.contains(LayoutReversed):
    result.mapping = result.mapping.reversed

proc initChannelLayout(cs: ChannelSpace; m: ChannelMap):
    ChannelLayout {.inline, noSideEffect, raises: [].} =
  ## Initialize a channel layout object 
  when compileOption("boundChecks"):
    assert(m.len <= len(cs))
    for ch in m:
      assert(channels(cs).contains(ch))

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


proc layout*[ImgObj: DynamicImageObject](
    img: var ImgObj, cs: ChannelSpace,
    opt: set[ChannelLayoutOption] = {}): var ImgObj {.discardable, inline.} =
  ## Set the channel
  img.lay = initChannelLayout(cs, opt)
  result = img

proc `channelspace=`*[ImgObj: DynamicImageObject](
    img: var ImgObj, cs: ChannelSpace)
    {.inline, noSideEffect, raises: [].} =
  ## Set the channelspace wiuth a default mapping.
  img.layout(cs, {})

proc `mapping=`*[ImgObj: DynamicImageObject](img: var ImgObj, m: ChannelMap)
    {.inline, noSideEffect, raises: [].} =
  ## Set the channel mapping
  img.lay.mapping = m


when isMainModule:
  import typetraits
  import ./backend/am

  template do_dynamic_layout_props_tests(cs: untyped): untyped =
    var img1: DynamicImageObject[OrderedRWFrameObject[AmBackendCpu[byte]]]
    stdout.write "Getters for "
    trace_result(type(img1).name)
    
    img1.channelspace = cs

    trace_result(img1.channelspace)
    trace_result(img1.mapping)

  const constRgba = initChannelLayout(ChannelSpaceIdRGB, {LayoutWithAlpha})
  const constAbgr = initChannelLayout(ChannelSpaceIdRGB, {LayoutWithAlpha, LayoutReversed})
  const constRgb = initChannelLayout(ChannelSpaceIdRGB)
  const constBgr = initChannelLayout(ChannelSpaceIdRGB, {LayoutReversed})

  template test_channel_layout(stage: string): untyped = 
    echo "Test " & stage & " channel layout:"
    echo "RGB : {LayoutWithAlpha}"
    echo constRgba.channelspace
    echo constRgba.mapping
    echo "RGB : {LayoutWithAlpha, LayoutReversed}"
    echo constAbgr.channelspace
    echo constAbgr.mapping
    echo "RGB : {}"
    echo constRgb.channelspace
    echo constRgb.mapping
    echo "RGB : {LayoutReversed}"
    echo constBgr.channelspace
    echo constBgr.mapping

  static:
    test_channel_layout"compile-time"

  test_channel_layout"run-time"

  do_dynamic_layout_props_tests(ChannelSpaceIdRGB)
  do_dynamic_layout_props_tests(ChannelSpaceIdYpCbCr)



