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

# Import where any backend is needed.

import system, macros, sequtils, strutils, tables

import ./macroutil

var backendIndex      {.compileTime.} = initTable[string, int]()
var defaultBackendId  {.compileTime.} = -1 # Should be >= 0 by end of file.
var fallbackBackendId {.compileTime.} = -1 # Should be >= 0 by end of file.

var backendNames {.compileTime.} = newSeq[string]()
var be_datatypes {.compileTime.} = newSeq[string]()
var be_slicetypes {.compileTime.} = newSeq[string]()
var be_shapetypes {.compileTime.} = newSeq[string]()

proc insertBackend(name, dataname, slicename, shapename: string): int {.compileTime.} =
  result = backendNames.len
  backendIndex[name] = result
  if defaultBackendId < 0:
    defaultBackendId = result
  backendNames.add name
  be_datatypes.add dataname
  be_slicetypes.add slicename
  be_shapetypes.add shapename

proc setDefaultBackend(name: string) {.compileTime.} =
  if name in backendIndex:
    defaultBackendId = backendIndex[name]
  else:
    quit "LERoSI: Cannot set default backend to " & name & " because no such backend exists."

proc setFallbackBackend(name: string) {.compileTime.} =
  if name in backendIndex:
    fallbackBackendId = backendIndex[name]
  else:
    quit "LERoSI: Cannot set fallback backend to " & name & " because no such backend exists."

proc BackendDesc_impl(name: string): string {.compileTime.} =
  if name in backendIndex:
    result = be_datatypes[backendIndex[name]]
  elif name == "*":
    result = be_datatypes[defaultBackendId]
  else:
    quit "LERoSI: requested type of unknown backend " & name & "."

proc SliceDesc_impl(name: string): string {.compileTime.} =
  if name in backendIndex:
    result = be_slicetypes[backendIndex[name]]
  elif name == "*":
    result = be_slicetypes[defaultBackendId]
  else:
    quit "LERoSI: requested slice type of unknown backend " & name & "."

proc ShapeDesc_impl(name: string): string {.compileTime.} =
  if name in backendIndex:
    result = be_shapetypes[backendIndex[name]]
  elif name == "*":
    result = be_shapetypes[defaultBackendId]
  else:
    quit "LERoSI: requested shape type of unknown backend " & name & "."

proc BackendId_impl(name: string): int {.compileTime.} =
  if name in backendIndex:
    backendIndex[name]
  else:
    -1

proc BackendName_impl(id: int): string {.compileTime.} =
  if 0 <= id and id < backendNames.len:
    backendNames[id]
  else:
    ""

proc BackendTypeNode*(name: string; T: NimNode): NimNode {.compileTime.} =
  let
    typename = BackendDesc_impl name
    typeident = ident(typename)
    typeexpr = nnkBracketExpr.newTree(typeident, T.copy)

  result = typeexpr

macro BackendType*(name, T: untyped): untyped =
  ## Backend type selector
  result = BackendTypeNode($name, T)

proc SliceTypeNode*(name: string; T: NimNode): NimNode {.compileTime.} =
  let
    typename = SliceDesc_impl name
    typeident = ident(typename)
    typeexpr = nnkBracketExpr.newTree(typeident, T.copy)

  result = typeexpr

macro SliceType*(name, T: untyped): untyped =
  ## Backend slice type selector
  result = SliceTypeNode($name, T)

proc ShapeTypeNode*(name: string; T: NimNode): NimNode {.compileTime.} =
  let
    typename = ShapeDesc_impl name
    typeident = ident(typename)
    typeexpr = nnkBracketExpr.newTree(typeident, T.copy)

  result = typeexpr

macro ShapeType*(name, T: untyped): untyped =
  ## Backend slice type selector
  result = ShapeTypeNode($name, T)

macro declareBackend(name, dataname, slicename, shapename: untyped): untyped =
  let
    sname = nodeToStr(name)
    sdataname = nodeToStr(dataname)
    sslicename = nodeToStr(slicename)
    sshapename = nodeToStr(shapename)

    be_index = insertBackend(sname, sdataname, sslicename, sshapename)

    gentype_ident = ident"T"

  result = newStmtList(
    newConstStmt(ident(sname & "BackendId"), newLit(be_index)),

    # We don't need this because we can use the macros to construct
    # each case immediately. This frees us from having to rely on
    # the compiler for more type info.
    
    #nnkTypeSection.newTree(
    #  nnkTypeDef.newTree(
    #    ident(sname & "BackendType"),
    #    nnkGenericParams.newTree(
    #      nnkIdentDefs.newTree(
    #        gentype_ident.copy,
    #        newEmptyNode(),
    #        newEmptyNode()
    #      )
    #    ),
    #    BackendType(sname, gentype_ident.copy)
    #  )
    #)
  )

when not declared(lerosiDisableAmBackend):
  import ./backend/am
  export am

  declareBackend "am", "AmBackendCpu", "AmSliceCpu", "AmShape"
  static: setDefaultBackend "am"

  #declareBackend "am_cuda", "AmBackendCuda", "AmSliceCuda"
  #declareBackend "am_cl", "AmBackendCL", "AmSliceCL"

# A contrivance to illustrate where this is headed.
when declared(lerosiExperimentalBackend):
  import ./backend/experimental
  export experimental

when declared(lerosiFallbackBackend):
  import ./backend/fallback
  export fallback

  declareBackend "fallback", "FbBackend", "FbSlice", "FbShape"
  static: setFallbackBackend "fallback"

