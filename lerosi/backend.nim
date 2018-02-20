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

var backendIndex           {.compileTime.} = initTable[string, int]()
var backendByTypenameIndex {.compileTime.} = initTable[string, int]()
var defaultBackendId       {.compileTime.} = -1 # Should be >= 0 by end of file.
var fallbackBackendId      {.compileTime.} = -1 # Should be >= 0 by end of file.

var backendNames {.compileTime.} = newSeq[string]()
var be_datatypes {.compileTime.} = newSeq[string]()
var be_slicetypes {.compileTime.} = newSeq[string]()
var be_shapetypes {.compileTime.} = newSeq[string]()

proc lookupBackendIndexImpl(i: int): int {.compileTime.} =
  result = if i < 0 or i >= backendNames.len: -1 else: i

proc lookupBackendIndexImpl(node: NimNode): int {.compileTime.} =
  result = -1 # By default.
  case node.kind:
    of nnkLiterals:
      case node.kind:
        of nnkStrLit, nnkRStrLit, nnkTripleStrLit:
          # We are naming a backend.
          let str = $node
          if str == "*": # "*" names the default backend.
            result = defaultBackendId
          elif str in backendIndex:
            result = backendIndex[str]
        else: # It is probably a numeric literal.
          try:
            result = int(node.intVal)
          except:
            try:
              result = int(node.floatVal)
            except:
              result = -1
            
          if result < -1 or result >= backendNames.len:
            result = -1
    of nnkIdent:
      # We are looking for a backend with a type.
      let str = $node
      if str in backendByTypenameIndex:
        result = backendByTypenameIndex[str]
    else:
      # We are looking for a backend with a complex type expression.
      # TODO: Improve implementation, this is pretty ad-hoc.
      try:
        let str = $(node[0])
        if str in backendByTypenameIndex:
          result = backendByTypenameIndex[str]
        if result < 0:
          result = lookupBackendIndexImpl(node[0])
      except:
        discard

proc lookupBackendIndexImpl(name: string): int {.compileTime.} =
  lookupBackendIndexImpl(newStrLitNode(name))

proc lookupBackendIndex(id: string|int|NimNode): int {.compileTime.} =
  # Use the implementation to try to find a match.
  result = lookupBackendIndexImpl(id)
  if result == -1 and 0 <= fallbackBackendId:
    # Use the fallback.
    result = fallbackBackendId

proc insertBackend(name, dataname, slicename, shapename: string): int {.compileTime.} =
  if not (name in backendIndex):
    result = backendNames.len

    # add the name to the 'by name' index.
    backendIndex[name] = result

    # add the typenames to the 'by typename' index.
    backendByTypenameIndex[dataname] = result
    backendByTypenameIndex[slicename] = result
    backendByTypenameIndex[shapename] = result

    if fallbackBackendId < 0:
      fallbackBackendId = result

    if defaultBackendId < 0:
      defaultBackendId = result

    # add the name and typenames to the sequences indexed by the backend
    # tables.
    backendNames.add name
    be_datatypes.add dataname
    be_slicetypes.add slicename
    be_shapetypes.add shapename
  else:
    quit "LERoSI: Duplicate backend registered for \"" & name & "\"."

template backend_key_human(id: untyped): untyped =
  when id is int:
    "backend with id " & $id
  elif id is string:
    "backend named \"" & id & "\""
  elif id is NimNode:
    "backend associated with \"" & toStrLit(id).strVal & "\""

proc setDefaultBackend(name: string) {.compileTime.} =
  if name in backendIndex:
    defaultBackendId = backendIndex[name]
  else:
    quit "LERoSI: Cannot set " & backend_key_human(name) & " as default backend because no such backend exists."

proc setFallbackBackend(name: string) {.compileTime.} =
  if name in backendIndex:
    fallbackBackendId = backendIndex[name]
  else:
    quit "LERoSI: Cannot set " & backend_key_human(name) & " as fallback backend because no such backend exists."

proc BackendDesc_impl(id: int|string|NimNode): string {.compileTime.} =
  let i = lookupBackendIndex(id)
  if 0 <= i:
    result = be_datatypes[i]
  else:
    quit "LERoSI: requested type of unknown " & backend_key_human(id) & "."

proc SliceDesc_impl(id: int|string|NimNode): string {.compileTime.} =
  let i = lookupBackendIndex(id)
  if 0 <= i:
    result = be_slicetypes[i]
  else:
    quit "LERoSI: requested slice type of unknown " & backend_key_human(id) & "."

proc ShapeDesc_impl(id: int|string|NimNode): string {.compileTime.} =
  let i = lookupBackendIndex(id)
  if 0 <= i:
    result = be_shapetypes[i]
  else:
    quit "LERoSI: requested shape type of unknown " & backend_key_human(id) & "."

proc BackendId_impl(id: int|string|NimNode): int {.compileTime.} =
  result = lookupBackendIndex(id)

proc BackendName_impl(id: string|NimNode): string {.compileTime.} =
  let i = lookupBackendIndex(id)
  result = if 0 <= i: backendNames[i] else: ""

proc BackendName_impl(id: int): string {.compileTime.} =
  if 0 <= id and id < backendNames.len:
    backendNames[id]
  else:
    ""

proc BackendTypeNode*(key: int|string|NimNode; T: NimNode): NimNode {.compileTime.} =
  let
    typename = BackendDesc_impl key
    typeident = ident(typename)
    typeexpr = nnkBracketExpr.newTree(typeident, T.copy)

  result = typeexpr

macro BackendType*(key, T: untyped): untyped =
  ## Backend type selector
  result = BackendTypeNode(key, T)

proc SliceTypeNode*(key: int|string|NimNode; T: NimNode): NimNode {.compileTime.} =
  let
    typename = SliceDesc_impl key
    typeident = ident(typename)
    typeexpr = nnkBracketExpr.newTree(typeident, T.copy)

  result = typeexpr

macro SliceType*(key, T: untyped): untyped =
  ## Backend slice type selector
  result = SliceTypeNode(key, T)

proc ShapeTypeNode*(key: int|string|NimNode; T: NimNode): NimNode {.compileTime.} =
  let
    typename = ShapeDesc_impl key
    typeident = ident(typename)
    typeexpr = nnkBracketExpr.newTree(typeident, T.copy)

  result = typeexpr

macro ShapeType*(key, T: untyped): untyped =
  ## Backend slice type selector
  result = ShapeTypeNode(key, T)

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

