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
    layout: ChannelLayout
    fr: Frame


proc initChannelLayout(cs: ChannelSpace, opt: set[ChannelLayoutOption] = {}):
    ChannelLayout {.inline, noSideEffect, raises: [].} =
  ## Initialize a channel layout object.
  result.cspace = cs
  result.mapping = channelspace_order(cs)
  if not opt.contains(LayoutWithAlpha):
    dec result.mapping.len
  if opt.contains(LayoutReversed):
    result.mapping = result.mapping.reversed

proc initChannelLayout(cs: ChannelSpace; m: ChannelMap; opt: set[ChannelLayoutOption] = {}):
    ChannelLayout {.inline, noSideEffect, raises: [].} =
  ## Initialize a channel layout object 
  when compileOption("boundChecks"):
    assert(m.len <= channelspace_len(cs))
    for ch in m:
      assert(channelspace_channels(cs).contains(ch))

  result.cspace = cs
  result.mapping = m
  #if opt.contains(LayoutWithAlpha) and m.contains(ChannelIdIdAlpha):
  #  dec result.mapping.len

proc `mapping=`*[ImgObj: DynamicImageObject](layout: var ChannelLayout, m: ChannelMap)
    {.inline, noSideEffect, raises: [].} =
  ## Get the channel mapping
  when compileOption("boundChecks"):
    assert(m.len <= channelspace_len(layout.channelspace))

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
  ## Get the channel mapping
  img.layout.mapping

proc channelspace*[ImgObj: DynamicImageObject](img: ImgObj):
    ChannelSpace {.inline, noSideEffect, raises: [].} =
  ## Get the channel mapping
  img.layout.cspace


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


proc `channelspace=`*[ImgObj: DynamicImageObject](
    img: var ImgObj, cs: ChannelSpace) {.inline, noSideEffect, raises: [].} =
  ## Get the channel mapping
  img.layout = initChannelLayout(cs)

proc `mapping=`*[ImgObj: DynamicImageObject](img: var ImgObj, m: ChannelMap)
    {.inline, noSideEffect, raises: [].} =
  ## Get the channel mapping
  when compileOption("boundChecks"):
    assert(m.len <= channelspace_len(img.channelspace))

  img.layout.mapping = m


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

  do_dynamic_layout_props_tests(ChannelSpaceIdRGB)
  do_dynamic_layout_props_tests(ChannelSpaceIdYpCbCr)



