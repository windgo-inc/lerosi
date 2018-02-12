import macros, sequtils, strutils, tables, future
import system

import ./macroutil
import ./fixedseq
import ./dataframe
import ./img_conf

import ./backend/am

export img_conf, dataframe

type
  RawImageObject*[Frame] = object
    fr: Frame

  DynamicImageObject*[Frame] = object
    cspace: ColorSpace
    mapping: ChannelMap
    fr: Frame


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
  img.mapping

proc colorspace*[ImgObj: DynamicImageObject](img: ImgObj):
    ColorSpace {.inline, noSideEffect, raises: [].} =
  ## Get the channel mapping
  img.cspace


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
    img.colorspace is ColorSpace
    img.mapping is ChannelMap

  UnstructuredImage*[Frame] = concept img
    img is BaseImage[Frame]
    not (img is StructuredImage[Frame])


proc `colorspace=`*[ImgObj: DynamicImageObject](
    img: var ImgObj, cs: ColorSpace) {.inline, noSideEffect, raises: [].} =
  ## Get the channel mapping
  img.cspace = cs
  img.mapping = colorspace_order(cs)

proc `mapping=`*[ImgObj: DynamicImageObject](img: var ImgObj, m: ChannelMap)
    {.inline, noSideEffect, raises: [].} =
  ## Get the channel mapping
  when compileOption("boundChecks"):
    assert(m.len <= colorspace_len(img.colorspace))

  img.mapping = m


when isMainModule:
  import typetraits
  import ./backend/am

  template do_dynamic_layout_props_tests(cs: untyped): untyped =
    var img1: DynamicImageObject[OrderedRWFrameObject[AmBackendCpu[byte]]]
    stdout.write "Getters for "
    trace_result(type(img1).name)
    
    img1.colorspace = cs

    trace_result(img1.colorspace)
    trace_result(img1.mapping)

  do_dynamic_layout_props_tests(ColorSpaceIdRGB)
  do_dynamic_layout_props_tests(ColorSpaceIdYpCbCr)



