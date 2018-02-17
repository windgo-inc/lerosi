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


proc initChannelLayout(cs: ChannelSpace; m: ChannelMap):
    ChannelLayout {.inline, noSideEffect, raises: [].} =
  ## Initialize a channel layout object 
  when compileOption("boundChecks"):
    assert(m.len <= len(cs))
    let chs = cs.channels
    for ch in m: assert(ch in chs)

  result.cspace = cs
  result.mapping = m


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

import ./img/layout
import ./img/sampling
import ./img/convert

export layout, sampling, convert


