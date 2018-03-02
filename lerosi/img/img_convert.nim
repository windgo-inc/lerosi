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

import system, macros, future, strutils, sequtils
import ../img
import ../detail/macroutil


#proc spaceTransProcAst*(layoutIn, layoutOut: ChannelLayout): seq[NimNode] {.compileTime.} =
#  var
#    inParams = nnkIdentDefs.newTree
#    outParams = nnkIdentdefs.newTree
#    # Add the empty return type parameter
#    paramSeq = @[nnkEmpty.newNimNode]
#
#  var params = nnkIdentDefs.newTree
#  for i, ch in layoutIn.mapping.pairs:
#    params.add ident(ch.barename)
#
#  params.add typeIdentIn
#  params.add nnkEmpty.newNimNode
#  paramSeq.add params
#
#  params = nnkIdentDefs.newTree
#  for i, ch in layoutOut.mapping.pairs:
#    params.add ident(ch.barename)
#
#  params.add typeIdentOut
#  params.add nnkEmpty.newNimNode
#  paramSeq.add params
#
#  
#
#
#
#template declareChannelConversion(inSpace, outSpace: type; body: untyped): untyped =
#  const
#    layoutIn = defChannelLayout(inSpace)
#    layoutOut = defChannelLayout(outSpace)
#
#    procShape = spaceTransProcAst(layoutIn, layoutOut)


proc img_convert_slipshod_VideoRGB2VideoCMYe[T, U: SomeReal](
    R, G, B: T;
    C, M, Ye: var U
    ) {.inline, noSideEffect.} =
  C = U(T(1.0) - R)
  M = U(T(1.0) - G)
  Ye = U(T(1.0) - B)


proc img_convert_slipshod_VideoRGB2VideoCMYe[T: SomeReal; U: SomeInteger](
    R, G, B: T;
    C, M, Ye: var U
    ) {.inline, noSideEffect.} =
  const scaleFactor = T(max(U))

  C  = U(scaleFactor * (T(1.0) - R))
  M  = U(scaleFactor * (T(1.0) - G))
  Ye = U(scaleFactor * (T(1.0) - B))


proc img_convert_slipshod_VideoRGB2VideoCMYe[T: SomeInteger; U: SomeReal](
    R, G, B: T;
    C, M, Ye: var U
    ) {.inline, noSideEffect.} =
  const scaleFactor = U(1.0) / U(max(T))

  C = U(max(T) - R) * scaleFactor
  M = U(max(T) - G) * scaleFactor
  Ye = U(max(T) - B) * scaleFactor


proc img_convert_slipshod_VideoRGB2VideoCMYe[T, U: SomeInteger](
    R, G, B: T;
    C, M, Ye: var U
    ) {.inline, noSideEffect.} =

  when T is U and U is T:
    C = max(T) - R
    M = max(T) - G
    Ye = max(T) - B
  elif sizeof(T) > sizeof(U):
    C = (max(T) - R) shr (sizeof(T) - sizeof(U))
    M = (max(T) - G) shr (sizeof(T) - sizeof(U))
    Ye = (max(T) - B) shr (sizeof(T) - sizeof(U))
  elif not (sizeof(T) == sizeof(U)):
    C = (max(T) - R) shl (sizeof(U) - sizeof(T))
    M = (max(T) - G) shl (sizeof(U) - sizeof(T))
    Ye = (max(T) - B) shl (sizeof(U) - sizeof(T))
  else:
    C = U(max(T) - R)
    M = U(max(T) - G)
    Ye = U(max(T) - B)


# TODO Implement me.
#template declareChannelConverter(in_ch: ChannelSpace; out_ch: ChannelId; body: untyped): untyped =

# TODO Implement me.
#proc convert*[ImgObj: DynamicImageObject](img: ImgObj, layout: ChannelLayout): ImgObj =

