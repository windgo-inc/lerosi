# MIT License
# 
# Copyright (c) 2018 WINDGO, Inc.
# Low Energy Retrieval of Source Information
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.


import macros, sequtils, strutils, tables, future
import system

import ./macroutil
import ./fixedseq
import ./dataframe
import ./spaceconf

import ./backend

export spaceconf, dataframe, backend, fixedseq


type
  ChannelLayout* = object
    cspace: ChannelSpace
    mapping: ChannelMap

  RawImageObject*[Frame] = object
    fr: Frame

  DynamicImageObject*[Frame] = object
    lay: ChannelLayout
    fr: Frame

proc defChannelLayout*(
    cs: ChannelSpace; m: ChannelMap):
    ChannelLayout {.eagerCompile, inline.} =
  ## Define a channel layout by a ChannelSpace and a ChannelMap.
  
  when compileOption("boundChecks"):
    assert(m.len <= len(cs))
    let chs = cs.channels
    for ch in m: assert(ch in chs)

  result.cspace = cs
  result.mapping = m



#proc initRawImageObjectImpl*[Frame: DataFrame; T](result: var RawImageObject[Frame], data: seq[T], sh: varargs[int]) =
#  ## Initialize a raw image object from a raw data.
#  backend_data_raw(result.fr.frame_data(), data, sh)
#
#template initRawImageObject*[T](Frame: typedesc[DataFrame], data: seq[T], sh: varargs[int]): untyped =
#  block:
#    var fr: Frame
#    initRawImageObjectImpl[Frame](fr, data, sh)
#    fr
#
#proc initRawImageObject*[Frame: DataFrame](fr: Frame): RawImageObject[Frame] =
#  ## Initialize a raw image object from an existing frame.
#  result.fr = fr
#
#
#proc toDynamic*[Frame: DataFrame](obj: RawImageObject[Frame],
#    lay: ChannelLayout): DynamicImageObject[Frame] =
#  ## Convert a RawImageObject in to a DynamicImageObject with associated
#  ## layout information.
#  result.fr = obj.fr
#  result.lay = lay
#
#
#template initDynamicImageObject*[T](name: string; lay: ChannelLayout; data: seq[T]; sh: varargs[int]): untyped =
#  toDynamic(initRawImageObject(RWFrameObject[BackendType(name, T)], data, sh), lay)
#
#template initDynamicImageObject*[T](name: string; lay: string; data: seq[T]; sh: varargs[int]): untyped =
#  toDynamic(initRawImageObject(RWFrameObject[BackendType(name, T)], data, sh), defChannelLayout(lay))


proc initDynamicImageObject*[Img: DynamicImageObject](result: var Img, layout: ChannelLayout) =
  result.lay = layout


proc channelspace*(layout: ChannelLayout):
    ChannelSpace {.eagerCompile, inline, noSideEffect, raises: [].} =
  ## Get the channelspace
  result = layout.cspace


proc mapping*(layout: ChannelLayout):
    ChannelMap {.eagerCompile, inline, noSideEffect, raises: [].} =
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


type
  BaseImage*[Frame] = concept img
    img.data_frame is Frame

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

proc data_order*[Img: DynamicImageObject](im: Img): DataOrder {.inline.} =
  im.data_frame.frame_order

template RawImageType*(name, access: string; T: untyped): untyped =
  RawImageObject[FrameType(name, access, T)]

template DynamicImageType*(name, access: string; T: untyped): untyped =
  DynamicImageObject[FrameType(name, access, T)]

template initDynamicImageLike*[Img: DynamicImageObject](
    name, access: string; T: untyped; im: Img): untyped =

  block:
    var r: DynamicImageType(name, access, T)
    let shap = im.data_frame.frame_data.backend_data_shape
    r.data_frame.frame_order = im.data_frame.frame_order
    initFrame r.data_frame, im.data_order, shap
    r

import ./img/layout
import ./img/sampling
import ./img/convert

export layout, sampling, convert


