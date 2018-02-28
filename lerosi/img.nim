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
import ./spacemeta
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


proc layout*[ImgObj: DynamicImageObject](img: ImgObj):
    ChannelLayout {.inline, noSideEffect, raises: [].} =
  ## Get the channel layout.
  img.lay


proc layout*[ImgObj: DynamicImageObject; M](
    img: var ImgObj, cs: ChannelSpace,
    m: M): var ImgObj {.discardable, inline.} =
  ## Set the channel layout.
  img.lay = defChannelLayout(cs, m)
  result = img


proc channelspace*[ImgObj: DynamicImageObject](img: ImgObj):
    ChannelSpace {.inline, noSideEffect, raises: [].} =
  ## Get the channelspace
  result = img.lay.cspace

proc channelspace*(layout: ChannelLayout):
    ChannelSpace {.eagerCompile, inline, noSideEffect, raises: [].} =
  ## Get the channelspace
  result = layout.cspace


proc mapping*[ImgObj: DynamicImageObject](img: ImgObj):
    ChannelMap {.inline, noSideEffect, raises: [].} =
  ## Get the channelspace
  result = img.lay.mapping


proc mapping*(layout: ChannelLayout):
    ChannelMap {.eagerCompile, inline, noSideEffect, raises: [].} =
  ## Get the channelspace
  result = layout.mapping


proc `mapping=`*(layout: var ChannelLayout, m: ChannelMap)
    {.inline, noSideEffect, raises: [].} =
  ## Set the channel mapping
  when compileOption("boundChecks"):
    assert(m.len <= len(layout.channelspace))
    for x in m: assert(x in layout.channelspace.channels)

  layout.mapping = m


import ./img/img_layout


proc initDynamicImageObject*[Img: DynamicImageObject](
    result: var Img, layout: ChannelLayout) =

  result.lay = layout


proc initDynamicImageObject*[Img: DynamicImageObject](result: var Img,
    layout: ChannelLayout, fr: Img.Frame) =

  result.lay = layout
  result.fr = fr
  

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


proc swizzle_impl[ImgObj: DynamicImageObject](
    img: ImgObj, idx: openarray[int]|ChannelIndex): ImgObj {.inline, noSideEffect.} =

  result.lay.mapping.setLen 0
  for i in 0..<idx.len:
    result.lay.mapping.add img.lay.mapping[idx[i]]

  result.lay.cspace = img.lay.cspace
  result.fr = img.fr.channels(idx)


# Can't quite be based on swizzle_impl because it needs to properly
# label the zero channels.
proc reorder_impl[ImgObj: DynamicImageObject](
    img: ImgObj, m: openarray[ChannelId]|ChannelMap): ImgObj {.inline, noSideEffect.} =

  var idx: ChannelIndex
  idx.setLen 0
  result.lay.mapping.setLen 0
  for i in 0..<m.len:
    let j = find(img.lay.mapping, m[i])
    result.lay.mapping.add m[i]
    idx.add j

  result.lay.cspace = img.lay.cspace
  result.fr = img.fr.channels(idx)


proc reinterpret_impl[ImgObj: DynamicImageObject](
    img: ImgObj, lay: ChannelLayout): ImgObj {.inline, noSideEffect.} =

  when compileOption("boundChecks"):
    assert lay.mapping.len <= img.lay.mapping.len

  if img.lay.mapping.len > lay.mapping.len:
    result.fr = img.fr.channelspan(0..lay.mapping.len-1)
  else:
    result.fr = img.fr

  result.lay = lay


proc swizzle*[ImgObj: DynamicImageObject](
    img: ImgObj, idx: varargs[int]): ImgObj {.inline, noSideEffect.} =

  swizzle_impl(img, idx)


proc swizzle*[ImgObj: DynamicImageObject](
    img: ImgObj, idx: seq[int]): ImgObj {.inline, noSideEffect.} =

  swizzle_impl(img, idx)


proc swizzle*[ImgObj: DynamicImageObject](
    img: ImgObj, idx: ChannelIndex): ImgObj {.inline, noSideEffect.} =

  swizzle_impl(img, idx)


proc reorder*[ImgObj: DynamicImageObject](
    img: ImgObj, m: varargs[ChannelId]): ImgObj {.inline, noSideEffect.} =

  reorder_impl(img, m)


proc reorder*[ImgObj: DynamicImageObject](
    img: ImgObj, m: seq[ChannelId]): ImgObj {.inline, noSideEffect.} =

  reorder_impl(img, m)


proc reorder*[ImgObj: DynamicImageObject](
    img: ImgObj, m: ChannelMap): ImgObj {.inline, noSideEffect.} =

  reorder_impl(img, m)


proc reorder*[ImgObj: DynamicImageObject](
    img: ImgObj, lay: ChannelLayout): ImgObj {.inline, noSideEffect.} =

  reorder_impl(img, lay.mapping)


proc reinterpret*[ImgObj: DynamicImageObject](
    img: ImgObj, lay: ChannelLayout): ImgObj {.inline, noSideEffect.} =

  reinterpret_impl(img, lay)


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

import ./img/img_convert
import ./img/img_sampling

export img_layout, img_sampling, img_convert


