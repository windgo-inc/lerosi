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

import system, macros, arraymancer, future, math, sequtils, strutils
import arraymancer

import ./am_slicing
import ./am_storageorder
import ../am # Cyclic reference by design
import ../../spaceconf

# memory hints
import ../../detail/memhint
import ../../detail/iterutil
import ../../detail/macroutil
import ../../detail/ptrarith

type
  AmDirectNDSampler*[T] = object
    order: DataOrder
    msource: ptr AmBackendCpu[T]

  AmSampleArray*{.shallow.}[T] = object
    mtab: array[MAX_IMAGE_CHANNELS, ptr T]

  AmDualSampleArray*{.shallow.}[T] = object
    mtab: array[MAX_IMAGE_CHANNELS*2+1, ptr T]

  AmDualTypeSampleArray*{.shallow.}[T; U] = object
    mtab: array[MAX_IMAGE_CHANNELS*2+1, pointer]


proc `[]`*[T, I: SomeInteger](s: AmSampleArray[T]; i: I): T {.inline.} =
  ## Accessor for the sample pointer array
  s.mtab[i][]

proc `[]`*[T, I: SomeInteger](s: var AmSampleArray[T]; i: I): var T {.inline.} =
  ## Mutable accessor for the sample pointer array
  s.mtab[i][]

proc `[]=`*[T, I: SomeInteger](s: var AmSampleArray[T]; i: I, v: T) {.inline.} =
  ## Assignment for the sample pointer array
  s.mtab[i][] = v

proc `[]=`*[T, I: SomeInteger](s: var AmSampleArray[T]; i: I, v: ptr T) {.inline.} =
  ## Pointer assignment for the sample pointer array
  s.mtab[i] = v

proc lhs*[T; I: SomeInteger](ds: AmDualSampleArray[T], i: I): var T {.inline.} =
  ## Index left hand side of dual sample array as a sample var binding.
  ds.mtab[i][]

proc rhs*[T; I: SomeInteger](ds: AmDualSampleArray[T], i: I): var T {.inline.} =
  ## Index right hand side of dual sample array as a sample var binding.
  ds.mtab[i+MAX_IMAGE_CHANNELS+1][]

proc lhs*[T; U; I: SomeInteger](ds: AmDualTypeSampleArray[T, U], i: I): var T {.inline.} =
  ## Index left hand side of a dual type sample array as a sample var binding
  ## taking the first type (T).
  cast[ptr T](ds.mtab[i])[]

proc rhs*[T; U; I: SomeInteger](ds: AmDualTypeSampleArray[T, U], i: I): var U {.inline.} =
  ## Index right hand side of a dual type sample array as a sample var binding
  ## taking the first type (U).
  cast[ptr U](ds.mtab[i+MAX_IMAGE_CHANNELS+1])[]


proc initAmDirectNDSampler*[T](
    b: var AmBackendCpu[T],
    order: DataOrder): AmDirectNDSampler[T] =
  ## Initialize a direct n-dimensional sampler

  result.msource = b.addr
  result.order = order


# We have to take this implementation of atIndex from the private internals
# of Tensor to at least eliminate the terribly inefficient flattening of an
# ND index.
proc tensorIndex[T](t: Tensor[T]; ind: openarray[int]): int =
  ## Convert [i, j, k, l ...] to the proper index.
  when compileOption("boundChecks"):
    assert ind.len <= t.rank

  result = t.offset
  for i in 0..<ind.len:
    result += t.strides[i]*ind[i]


proc tensorAt[T](t: Tensor[T]; ind: openarray[int]): T =
  result = t.data[t.tensorIndex(ind)]


proc tensorAt[T](t: var Tensor[T]; ind: openarray[int]): var T =
  result = t.data[t.tensorIndex(ind)]


# Super inefficient temporary implementation, using tensorIndex; see above.
# Proof of concept. Where do we go from here?
proc msampleND*[T: SomeNumber](samp: AmDirectNDSampler[T]; ind: varargs[int]):
  var T =
  samp.msource[].backend_data.tensorAt(ind)


proc sampleND*[T: SomeNumber](samp: AmDirectNDSampler[T]; ind: varargs[int]): T =
  samp.msource[].backend_data.tensorAt(ind)


# All code below except for modifications by WINDGO, Inc. is copyright
# the Arraymancer contributors under the Apache 2.0 License.

type
  IterKind* = enum
    Values, Iter_Values, Offset_Values


proc indexNamed_impl(name: string, i: int): NimNode {.compileTime.} =
  result = newPar(newBlockStmt(ident(name & $i)))


macro indexNamed(name, i: untyped): typed =
  #echo "indexNamed ", toStrLit(name).strVal, " ", i.kind, "::", toStrLit(i).strVal
  case name.kind
  of nnkStrLit..nnkTripleStrLit:
    result = indexNamed_impl(name.strVal, int(i.intVal))
  else:
    result = indexNamed_impl(toStrLit(name).strVal, int(i.intVal))


proc fwdNamed_impl(name: string): NimNode {.compileTime.} =
  result = ident(name)


macro fwdNamed(name: typed): typed =
  #echo "fwdNamed", toStrLit(name).strVal
  case name.kind
  of nnkStrLit..nnkTripleStrLit:
    result = fwdNamed_impl(name.strVal)
  else:
    result = fwdNamed_impl(toStrLit(name).strVal)

template declStridedIterationVars*(coord, backstrides, iter_pos: untyped): untyped =
  var iter_pos = 0
  use_mem_hints() # MAX_IMAGE_CHANNELS = 8, 8 ints = 64 Bytes, cache line = 64 Bytes --> profit !
  var coord {.align64, noInit.}: array[MAX_IMAGE_CHANNELS, int]
  var backstrides {.align64, noInit.}: array[MAX_IMAGE_CHANNELS, int]


template initStridedIteration*(coord, backstrides, iter_pos: untyped, t, iter_offset, iter_size: typed): untyped =
  ## Iterator init
  for i in 0..<t.rank:
    backstrides[i] = t.strides[i]*(t.shape[i]-1)
    coord[i] = 0

  # Calculate initial coords and iter_pos from iteration offset
  if iter_offset != 0:
    var z = 1
    for i in countdown(t.rank - 1,0):
      coord[i] = (iter_offset div z) mod t.shape[i]
      iter_pos += coord[i]*t.strides[i]
      z *= t.shape[i]


macro declMultiStridedIterationVars*(coord, backstrides, iter_pos: untyped, nmulti: untyped): untyped =
  let
    paramCount =
      (case nmulti.kind
      of nnkIntLit..nnkUInt64Lit: int(nmulti.intVal)
      else: MAX_IMAGE_CHANNELS)
    # In this case, we inject if statements which break initialization at the
    # appropriate line, and we always unroll to maximum channel

  result = newStmtList()
  for i in 0..<paramCount:
    let
      next_index = i + 1

    var
      coordIdent = ident($coord & $i)
      backstridesIdent = ident($backstrides & $i)
      iter_posIdent = ident($iter_pos & $i)
    
    result.add newCall(bindSym"declStridedIterationVars", [
      coordIdent,
      backstridesIdent,
      iter_posIdent
    ])


template isDynamicParamCount(count, isDynamic: untyped;
    nmulti: NimNode): untyped =
  ## Determine if the value of nmulti can be statically interpreted.

  let
    count =
      (case nmulti.kind
      of nnkIntLit..nnkUInt64Lit: int(nmulti.intVal)
      else: MAX_IMAGE_CHANNELS)
    isDynamic = not (nmulti.kind in {nnkIntLit..nnkUInt64Lit})
    # In the dynamic case, we inject if statements which break initialization
    # at the appropriate line, and we always unroll to maximum channel


macro initMultiStridedIteration*(coord, backstrides, iter_pos: untyped;
    t, iter_offsets, iter_size: typed, nmulti: untyped): untyped =
  ## Initialize multi strided iteration

  var
    initBlockLabel = genSym(nskLabel, ident="MULTI_STRIDED_ITERATION")
    initBlock = nnkBlockStmt.newTree(initBlockLabel, newStmtList())

  let
    paramCount =
      (case nmulti.kind
      of nnkIntLit..nnkUInt64Lit: int(nmulti.intVal)
      else: MAX_IMAGE_CHANNELS)
    paramCountIsDynamic = not (nmulti.kind in {nnkIntLit..nnkUInt64Lit})
    # In this case, we inject if statements which break initialization at the
    # appropriate line, and we always unroll to maximum channel
    
  for i in 0..<paramCount:
    let
      next_index = i + 1

      #coordIdent_u = indexNamed_impl(coord.strVal, i)
      #iter_posIdent_u = indexNamed_impl(iter_pos.strVal, i)
      #backstridesIdent_u = indexNamed_impl(backstrides.strVal, i)

      coordIdent = ident(toStrLit(coord).strVal & $i)
      iter_posIdent = ident(toStrLit(iter_pos).strVal & $i)
      backstridesIdent = ident(toStrLit(backstrides).strVal & $i)
    
    initBlock[1].add newCall(bindSym"initStridedIteration", [
      coordIdent,
      backstridesIdent,
      iter_posIdent,
      t, nnkBracketExpr.newTree(iter_offsets, newLit(i)),
      iter_size
    ])

    if paramCountIsDynamic:
      initBlock[1].add nnkIfStmt.newTree(
        nnkElifBranch.newTree(
          infix(nmulti, "<=", newLit(next_index)),
          nnkBreakStmt.newTree(initBlockLabel)
        ))

  result = newStmtList(initBlock)

template advanceStridedIteration*(coord, backstrides, iter_pos,
    t, iter_offset, iter_size: typed, count: typed = 1): untyped =
  ## Computing the next position
  for rep in 0..<count: # FIXME: This is bad news.
    for k in countdown(t.rank - 1,0):
      if coord[k] < t.shape[k]-1:
        coord[k] += 1
        iter_pos += t.strides[k]
        break
      else:
        coord[k] = 0
        iter_pos -= backstrides[k]


macro advanceMultiStridedIteration*(coord, backstrides, iter_pos: untyped,
    t, iter_offsets, iter_size, nmulti,
    imulti: typed = 0, count: typed = 1): untyped =
  ## Computing the next positions
  var
    advBlockLabel = genSym(nskLabel, ident="MULTI_STRIDED_ADVANCE")
    advBlock = nnkBlockStmt.newTree(advBlockLabel, newStmtList())


  let
    paramCount =
      (case nmulti.kind
      of nnkIntLit..nnkUInt64Lit: int(nmulti.intVal)
      else: MAX_IMAGE_CHANNELS)
    paramCountIsDynamic = not (nmulti.kind in {nnkIntLit..nnkUInt64Lit})
    # In this case, we inject if statements which break initialization at the
    # appropriate line, and we always unroll to maximum channel

  let countDecl = newLetStmt(ident"cnt", newCall(bindSym"int", count))
  advBlock[1].add countDecl

  for imulti in 0..<paramCount:
    let
      next_index = imulti + 1

      coordIdent_u = indexNamed_impl(coord.strVal, imulti)
      iter_posIdent_u = indexNamed_impl(iter_pos.strVal, imulti)
      backstridesIdent_u = indexNamed_impl(backstrides.strVal, imulti)

      coordIdent = ident(toStrLit(coordIdent_u[0][1]).strVal)
      iter_posIdent = ident(toStrLit(iter_posIdent_u[0][1]).strVal)
      backstridesIdent = ident(toStrLit(backstridesIdent_u[0][1]).strVal)

    var outerFor = nnkForStmt.newTree(
      ident"_", nnkInfix.newTree(bindSym"..<", newLit(0), ident"cnt"))

    var innerFor = nnkForStmt.newTree(
      ident"k", newCall(bindSym"countdown", [infix(newDotExpr(t, bindSym"rank"), "-", newLit(1)), newLit(0)]))

    var loopBody = nnkBlockStmt.newTree(newEmptyNode(), newStmtList())

    let onNormalStride = newStmtList(
      infix(nnkBracketExpr.newTree(coordIdent, ident"k"), "+=", newLit(1)),
      infix(iter_posIdent, "+=", nnkBracketExpr.newTree(newDotExpr(t, ident"strides"), ident"k")),
      nnkBreakStmt.newTree(newEmptyNode())
    )
    
    let onBackStride = newStmtList(
      nnkAsgn.newTree(nnkBracketExpr.newTree(coordIdent, ident"k"), newLit(0)),
      infix(iter_posIdent, "-=", nnkBracketExpr.newTree(backstridesIdent, ident"k"))
    )

    loopBody[1].add nnkIfExpr.newTree(
      nnkElifExpr.newTree(infix(
        nnkBracketExpr.newTree(coordIdent, ident"k"),
        "<", infix(
          nnkBracketExpr.newTree(
            newDotExpr(t, ident"shape"),
            ident"k"
          ),
          "-", newLit(1)
        )
      ), onNormalStride),
      nnkElseExpr.newTree(onBackStride)
    )

    innerFor.add loopBody
    outerFor.add innerFor
    
    advBlock[1].add outerFor

    if paramCountIsDynamic:
      advBlock[1].add nnkIfStmt.newTree(
        nnkElifBranch.newTree(
          infix(nmulti, "<=", newLit(next_index)),
          nnkBreakStmt.newTree(advBlockLabel)
        ))

  result = newStmtList(advBlock)


template stridedIterationYield*(strider: IterKind, data, i, iter_pos: typed) =
  ## Iterator the return value
  #when strider == IterKind.Values:
  static:
    echo type(data).name
    echo type(data[iter_pos]).name
  yield data[iter_pos]
  #elif strider == IterKind.Iter_Values: yield (i, data[iter_pos])
  #elif strider == IterKind.Offset_Values: yield (iter_pos, data[iter_pos]) ## TODO: remove workaround for C++ backend


macro makeIterPosIdent(iter_pos, imulti: untyped, nmulti: untyped): untyped =
  #echo iter_pos.strVal, " ", iter_pos.kind
  case nmulti.kind:
  of nnkIntLit..nnkUInt64Lit:
    let nmulti_currval = nmulti.intVal
    if nmulti_currval > imulti.intVal:
      result = ident($iter_pos & $(imulti.intVal))
    else:
      result = newLit(0)
    echo "known nmulti ", nmulti_currval, " result ", $result
  else:
    result = ident($iter_pos & $(imulti.intVal))
    echo "blind result ", $result


template yield_sample_array(res, offset, typ, value: typed): untyped =
  when type(res) is AmDualSampleArray|AmSampleArray:
    res.mtab[offset] = cast[ptr typ](value)
  elif type(res) is AmDualTypeSampleArray:
    res.mtab[offset] = cast[pointer](value)
  #elif type(res) is AmSampleArrayPtr:
  #  ptrset(res.itab, offset, cast[ptr typ](value))


# Using indexNamed on iter_pos
template multiStridedIterationYield*(
    label_block: untyped,
    iter_pos: untyped, strider: IterKind, data,
    iter_offsets, i, nmulti, dynn, res: typed,
    imulti: typed = 0, ioff: typed = 0): untyped =
  ## Fill result pointers during multi-strided iteration

  when imulti < nmulti:
    when strider == IterKind.Values:
      yield_sample_array(res, imulti + ioff, type(data[0]),
        data[iter_offsets[imulti] + makeIterPosIdent(iter_pos, imulti, nmulti)].addr)

      when imulti < nmulti - 1:
        when dynn is SomeInteger:
          if dynn <= imulti + 1: break label_block
        
        multiStridedIterationYield(label_block,
          iter_pos, strider, data, iter_offsets, i, nmulti, dynn, res, imulti + 1, ioff)

    # These modes not yet supported
    #elif strider == IterKind.Iter_Values: yield (i, data[iter_pos])
    #elif strider == IterKind.Offset_Values: yield (iter_pos, data[iter_pos]) ## TODO: remove workaround for C++ backend
    


template multiStridedIterationYieldOffset*(offset: typed,
    label_block, iter_pos: untyped, strider: IterKind, data,
    iter_offsets, i, nmulti, dynn, res: typed): untyped =
  ## Fill result pointers during multi-strided iteration

  multiStridedIterationYield(label_block, iter_pos, strider, data,
    iter_offsets, i, nmulti, dynn, res, ioff = offset)


# Only difference is that there is considered to be only one iter_pos.
template multiStridedIterationYieldContiguous*(
    label_block, iter_pos: untyped, strider: IterKind, data,
    iter_offsets, i, nmulti, dynn, res: typed,
    imulti: typed = 0, ioff: typed = 0): untyped =
  ## Fill result pointers during multi-strided iteration (contiguous)

  when imulti < nmulti:
    when strider == IterKind.Values:
      yield_sample_array(res, imulti + ioff, type(data[0]),
        data[iter_offsets[imulti] + (iter_pos)].addr)

      when imulti < nmulti - 1:
        when dynn is SomeInteger:
          if dynn <= imulti + 1: break label_block
        
        multiStridedIterationYieldContiguous(label_block,
          iter_pos, strider, data, iter_offsets, i, nmulti, dynn, res, imulti + 1, ioff)

    # These modes not yet supported
    #elif strider == IterKind.Iter_Values: yield (i, data[iter_pos])
    #elif strider == IterKind.Offset_Values: yield (iter_pos, data[iter_pos]) ## TODO: remove workaround for C++ backend


template multiStridedIterationYieldContiguousOffset*(offset: typed,
    label_block, iter_pos: untyped, strider: IterKind, data,
    iter_offsets, i, nmulti, dynn, res: typed): untyped =
  ## Fill result pointers with an offset during multi-strided iteration (contiguous)

  multiStridedIterationYieldContiguous(label_block, iter_pos, strider, data,
    iter_offsets, i, nmulti, dynn, res, ioff = offset)


template stridedIteration*(strider: IterKind, t, iter_offset, iter_size: typed, adv: typed = 1): untyped =
  ## Iterate over a Tensor, displaying data as in C order, whatever the strides.
  when compileOption("boundChecks"):
    assert 0 <= adv,
      "LERoSI/backend/am/am_accessors: Bad adv step in stridedIteration"

  # Get tensor data address with offset builtin
  use_mem_hints()
  let data{.restrict.} = t.dataArray # Warning ⚠: data pointed may be mutated

  # Optimize for loops in contiguous cases
  if t.is_C_Contiguous:
    for i in countup(iter_offset, iter_offset+((iter_size-1)*adv), step=adv):
      stridedIterationYield(strider, data, i, i)
  else:
    declStridedIterationVars(coord, backstrides, iter_pos)
    initStridedIteration(coord, backstrides, iter_pos, t, iter_offset, iter_size)
    for i in countup(iter_offset, iter_offset+((iter_size-1)*adv), step=adv):
      stridedIterationYield(strider, data, i, iter_pos)
      advanceStridedIteration(
        coord, backstrides, iter_pos, t, iter_offset, iter_size, count = adv)


template declMultiStridedIterationData(srcdata, res, areContiguous, itsiz, nadv, t, iter_size, adv: untyped): untyped =
  ## Multi strided iteration data
  let
    areContiguous = t.is_C_Contiguous
    itsiz = iter_size
    nadv = adv

  use_mem_hints()
  let srcdata {.restrict.} = t.dataArray
  var res {.restrict.}: AmSampleArray[type(t.data[0])]


template typedSame(x, y: typed): bool =
  when type(x) is type(y) and type(y) is type(x):
    true
  else:
    false


template declDualMultiStridedIterationData(lhsdata, rhsdata,
    res, areContiguous, itsiz, nadv_lhs, nadv_rhs, tlhs, trhs,
    iter_size, adv_lhs, adv_rhs: untyped): untyped =
  ## Dual multi strided iteration data
  let
    areContiguous = tlhs.is_C_Contiguous and trhs.is_C_Contiguous
    itsiz = iter_size
    nadv_lhs = adv_lhs
    nadv_rhs = adv_rhs

  use_mem_hints()
  # Declare data for left and right hand sides.
  let lhsdata {.restrict.} = tlhs.dataArray
  let rhsdata {.restrict.} = trhs.dataArray
  # The result vector is twice the length.
  when typedSame(tlhs.data[0], trhs.data[0]):
    var res {.restrict.}: AmDualSampleArray[type(tlhs.data[0])]
  else:
    var res {.restrict.}: AmDualTypeSampleArray[type(tlhs.data[0]), type(trhs.data[0])]



template multiStridedIteration(
    strider, t, iter_offsets,
    iter_size, adv: typed, nmulti: typed): untyped =

  ## Multi strided iteration (over one image)
  when compileOption("boundChecks"):
    assert 0 <= adv,
      "LERoSI/backend/am/am_accessors: Bad adv step in multiStridedIteration"

  const nmultiIsDynamic = not compiles((const nmultiConst = nmulti))
  when nmultiIsDynamic:
    ## Channel count is dynamic
    var dynn: int = nmulti
    const nmultiVal = MAX_IMAGE_CHANNELS
  else:
    ## Channel count is static
    var dynn {.used.} : pointer = nil
    const nmultiVal = nmulti

  ## Initialize iteration data
  declMultiStridedIterationData(source, resultVector, areAllContiguous, itsiz, nadv, t, iter_size, adv)

  if areAllContiguous:
    ## Optimize for loops in contiguous cases
    for j in countup(0, ((itsiz-1)*nadv), step=nadv):
      block MULTI_STRIDED_CONTIGUOUS_SELECT:
        ## Fill result pointer vector
        multiStridedIterationYieldContiguous(MULTI_STRIDED_CONTIGUOUS_SELECT,
          j, strider, source,
          iter_offsets, j, nmultiVal, dynn, resultVector)

      ## Yield the result pointer vector
      yield resultVector

  else:
    ## Declare iteration variables
    declMultiStridedIterationVars(coord, backstrides, iter_pos, nmulti)

    ## Initialize iteration variables
    initMultiStridedIteration(coord, backstrides, iter_pos, t, iter_offsets, itsiz, nmulti)

    for j in countup(0, ((itsiz-1)*nadv), step=nadv):
      block MULTI_STRIDED_INDEX_SELECT:
        ## Fill result pointer vector
        multiStridedIterationYield(MULTI_STRIDED_INDEX_SELECT,
          iter_pos, strider, source, iter_offsets, j, nmultiVal, dynn, resultVector)

      ## Yield the result pointer vector
      yield resultVector

      ## Advance the iteration position
      advanceMultiStridedIteration(
        "coord", "backstrides", "iter_pos", t, iter_offsets, itsiz, nmulti, count = nadv)


template dualMultiStridedIteration(strider, tlhs, trhs,
    iter_offsets_lhs, iter_offsets_rhs,
    iter_size_lhs, iter_size_rhs,
    adv_lhs, adv_rhs: typed,
    nmulti_lhs, nmulti_rhs: typed): untyped =
  ## Dual multi strided iteration
  
  when compileOption("boundChecks"):
    assert 0 <= adv_lhs,
      "LERoSI/backend/am/am_accessors: Bad adv_lhs step in multiStridedIteration"
    assert 0 <= adv_rhs,
      "LERoSI/backend/am/am_accessors: Bad adv_rhs step in multiStridedIteration"

  const nmulti_lhsIsDynamic = not compiles((const nmultiConst = nmulti_lhs))
  when nmulti_lhsIsDynamic:
    ## Left hand channel count is dynamic
    var dynn_lhs: int = nmulti_lhs
    const nmultiVal_lhs = MAX_IMAGE_CHANNELS
  else:
    ## Left hand channel count is static
    var dynn_lhs {.used.} : pointer = nil
    const nmultiVal_lhs = nmulti_lhs

  const nmulti_rhsIsDynamic = not compiles((const nmultiConst = nmulti_rhs))
  when nmulti_rhsIsDynamic:
    ## Right hand channel count is dynamic
    var dynn_rhs: int = nmulti_rhs
    const nmultiVal_rhs = MAX_IMAGE_CHANNELS
  else:
    ## Right hand channel count is static
    var dynn_rhs {.used.} : pointer = nil
    const nmultiVal_rhs = nmulti_rhs

  ## Don't iterate past the end of ither.
  let iter_size = min(iter_size_lhs, iter_size_rhs)
  
  ## Initialize iteration data
  declDualMultiStridedIterationData(lhsData, rhsData, resultVector,
    areAllContiguous, itsiz, nadv_lhs, nadv_rhs,
    tlhs, trhs, iter_size, adv_lhs, adv_rhs)

  if areAllContiguous:
    ## Optimize for loops in contiguous cases
    for j in countup(0, itsiz-1, step=1):
      let
        j_lhs = j * nadv_lhs
        j_rhs = j * nadv_rhs
      block MULTI_STRIDED_CONTIGUOUS_SELECT_LEFT:
        ## Fill result pointer vector left
        multiStridedIterationYieldContiguous(
          MULTI_STRIDED_CONTIGUOUS_SELECT_LEFT,
          j_lhs, strider, lhsData, iter_offsets_lhs, j_lhs,
          nmultiVal_lhs, dynn_lhs, resultVector)

      block MULTI_STRIDED_CONTIGUOUS_SELECT_RIGHT:
        ## Fill result pointer vector right
        multiStridedIterationYieldContiguousOffset(
          MAX_IMAGE_CHANNELS+1, MULTI_STRIDED_CONTIGUOUS_SELECT_RIGHT,
          j_rhs, strider, rhsData, iter_offsets_rhs, j_rhs,
          nmultiVal_rhs, dynn_rhs, resultVector)

      ## Yield the result pointer vector
      yield resultVector

  else:
    ## Fall back on table driven iteration.

    ## Declare left hand side iteration variables
    declMultiStridedIterationVars(
      coord_lhs, backstrides_lhs, iter_pos_lhs, nmulti_lhs)
    ## Declare right hand side iteration variables
    declMultiStridedIterationVars(
      coord_rhs, backstrides_rhs, iter_pos_rhs, nmulti_rhs)

    ## Initialize left hand side iteration variables
    initMultiStridedIteration(
      coord_lhs, backstrides_lhs, iter_pos_lhs,
      tlhs, iter_offsets_lhs, itsiz, nmulti_lhs)
    ## Initialize right hand side iteration variables
    initMultiStridedIteration(
      coord_rhs, backstrides_rhs, iter_pos_rhs,
      tlhs, iter_offsets_rhs, itsiz, nmulti_rhs)

    for j in countup(0, itsiz-1, step=1):
      let
        j_lhs = j * nadv_lhs
        j_rhs = j * nadv_rhs

      block MULTI_STRIDED_INDEX_SELECT_LEFT:
        ## Fill result pointer vector left
        multiStridedIterationYield(MULTI_STRIDED_INDEX_SELECT_LEFT,
          iter_pos_lhs, strider, lhsData, iter_offsets_lhs, j_lhs,
          nmultiVal_lhs, dynn_lhs, resultVector)

      block MULTI_STRIDED_INDEX_SELECT_RIGHT:
        ## Fill result pointer vector right
        multiStridedIterationYieldOffset(
          MAX_IMAGE_CHANNELS+1, MULTI_STRIDED_INDEX_SELECT_RIGHT,
          iter_pos_rhs, strider, rhsData, iter_offsets_rhs, j_rhs,
          nmultiVal_rhs, dynn_rhs, resultVector)

      ## Yield the result pointer vector
      yield resultVector

      ## Advance the left hand iteration position
      advanceMultiStridedIteration(
        "coord_lhs", "backstrides_lhs", "iter_pos_lhs", tlhs,
        iter_offsets_lhs, itsiz, nmulti_lhs, count = nadv_lhs)

      ## Advance the right hand iteration position
      advanceMultiStridedIteration(
        "coord_rhs", "backstrides_rhs", "iter_pos_rhs", trhs,
        iter_offsets_rhs, itsiz, nmulti_rhs, count = nadv_rhs)


template channelStridedIteration*(s1, order, i: typed): untyped =
  var
    msrc = s1.msource
    t = msrc[].backend_data
    totalsize = msrc[].backend_image_size(order)
  case order
  of DataPlanar:
    stridedIteration(
      IterKind.Values, t,
      i * t.strides[0], totalsize,
      adv = 1) # Added new advance parameter
  of DataInterleaved:
    stridedIteration(
      IterKind.Values, t,
      i * t.strides[t.rank - 1], totalsize,
      adv = t.shape[t.rank - 1]) # Added new advance parameter


template declMultiChannelStridedIterationData(
    msrc, t, totalsize, offsets, adv: untyped;
    s, order: typed): untyped =

  ## Multi channel strided iteration data
  var
    msrc = s.msource
    t = msrc[].backend_data
    totalsize = msrc[].backend_image_size(order)

    offsets: array[MAX_IMAGE_CHANNELS, int]
    adv: int


template initMultiChannelStridedIterationData(
    order, offsets, ind, t, adv, nmulti: typed): untyped =

  ## Multi channel strided iteration initialize
  case order
  of DataPlanar:
    for i in 0..<nmulti:
      offsets[i] = ind[i] * t.strides[0]
    adv = 1
  of DataInterleaved:
    for i in 0..<nmulti:
      offsets[i] = ind[i] * t.strides[t.rank - 1]
    adv = t.shape[t.rank - 1]


template multiChannelStridedIteration*(s1, order, ind: typed, nmulti: typed): untyped =
  ## Multi channel strided iteration

  ## Multi channel strided iteration setup
  declMultiChannelStridedIterationData(msrc, t, totalsize, offsets, adv, s1, order)
  initMultiChannelStridedIterationData(order, offsets, ind, t, adv, nmulti)

  ## Multi channel strided iteration invocation
  multiStridedIteration(
    IterKind.Values, t,
    offsets, totalsize,
    adv = adv, nmulti) # Added new advance parameter


template dualMultiChannelStridedIteration*(
    s1, s2, order1, order2,
    ind1, ind2, nmulti1, nmulti2: typed): untyped =
  ## Dual multi channel strided iteration
  
  ## Dual multi channel strided iteration left hand side declarations
  declMultiChannelStridedIterationData(msrc1, t1, totalsize1, offsets1, adv1, s1, order1)
  ## Dual multi channel strided iteration right hand side declarations
  declMultiChannelStridedIterationData(msrc2, t2, totalsize2, offsets2, adv2, s2, order2)

  ## Dual multi channel strided iteration left hand side initialization
  initMultiChannelStridedIterationData(order1, offsets1, ind1, t1, adv1, nmulti1)
  ## Dual multi channel strided iteration right hand side initialization
  initMultiChannelStridedIterationData(order2, offsets2, ind2, t2, adv2, nmulti2)

  ## Dual multi channel strided iteration invocation
  dualMultiStridedIteration(
    IterKind.Values, t1, t2,
    offsets1, offsets2,
    totalsize1, totalsize2,
    adv1, adv2,
    nmulti1, nmulti2) # Added new advance parameter


iterator msampleND*[T](s1: AmDirectNDSampler[T]): var T =
  stridedIteration(
    IterKind.Values, s1.msource[].backend_data,
    0, s1.msource[].backend_data.size, adv = 1)


iterator sampleND*[T](s1: AmDirectNDSampler[T]): T =
  stridedIteration(
    IterKind.Values, s1.msource[].backend_data,
    0, s1.msource[].backend_data.size, adv = 1)


iterator msampleNDchannel*[T](s1: AmDirectNDSampler[T], i: int): var T =
  channelStridedIteration(s1, s1.order, i)


iterator sampleNDchannel*[T](s1: AmDirectNDSampler[T], i: int): T =
  channelStridedIteration(s1, s1.order, i)


iterator sampleNDchannels*[T; N](
    s1: AmDirectNDSampler[T],
    ind: array[N, int]): AmSampleArray[T] =
  ## sampleNDchannels static variadic
  expandMacros:
    ## sampleNDchannels static variadic body
    when N is range:
      const nmulti = high(N) - low(N) + 1
    else:
      const nmulti = int(N)
    multiChannelStridedIteration(s1, s1.order, ind, nmulti)


iterator sampleNDchannels*[T; N](
    s1: AmDirectNDSampler[T],
    ind: array[N, int]{`const`}): AmSampleArray[T] =
  ## sampleNDchannels static variadic
  expandMacros:
    ## sampleNDchannels static variadic body
    when N is range:
      const nmulti = high(N) - low(N) + 1
    else:
      const nmulti = int(N)
    multiChannelStridedIteration(s1, s1.order, ind, nmulti)


iterator sampleNDchannels*[T; S: not array](
    s1: AmDirectNDSampler[T],
    ind: S): AmSampleArray[T] =
  ## sampleNDchannels variadic
  expandMacros:
    ## sampleNDchannels variadic body
    multiChannelStridedIteration(s1, s1.order, ind, ind.len)


iterator sampleDualNDchannels*[T; U; IA: not array; IB: not array](
    s1, s2: AmDirectNDSampler[T];
    ind1: IA,
    ind2: IB): AmDualSampleArray[T] =
  ## sampleDualNDchannels variadic
  expandMacros:
    ## sampleDualNDchannels variadic body
    dualMultiChannelStridedIteration(
      s1, s2, s1.order, s2.order,
      ind1, ind2, ind1.len, ind2.len)


iterator sampleDualNDchannels*[T; U; IA: not array; M](
    s1, s2: AmDirectNDSampler[T];
    ind1: IA,
    ind2: array[M, int]): AmDualSampleArray[T] =
  ## sampleDualNDchannels variadic static right
  expandMacros:
    when M is range:
      const nmulti = high(M) - low(M) + 1
    else:
      const nmulti = int(M)
    ## sampleDualNDchannels variadic body static right
    dualMultiChannelStridedIteration(
      s1, s2, s1.order, s2.order,
      ind1, ind2, ind1.len, nmulti)


iterator sampleDualNDchannels*[T; U; N; IB: not array](
    s1, s2: AmDirectNDSampler[T];
    ind1: array[N, int],
    ind2: IB): AmDualSampleArray[T] =
  ## sampleDualNDchannels variadic static left
  expandMacros:
    when N is range:
      const nmulti = high(M) - low(M) + 1
    else:
      const nmulti = int(M)
    ## sampleDualNDchannels variadic body static left
    dualMultiChannelStridedIteration(
      s1, s2, s1.order, s2.order,
      ind1, ind2, nmulti, ind2.len)


iterator sampleDualNDchannels*[T; U; N; M](
    s1: AmDirectNDSampler[T], s2: AmDirectNDSampler[U];
    ind1: array[N, int],
    ind2: array[M, int]): AmDualSampleArray[T] =
  ## sampleDualNDchannels static variadic
  expandMacros:
    ## sampleDualNDchannels static variadic body
    when N is range:
      const nmulti1 = high(N) - low(N) + 1
    else:
      const nmulti1 = int(N)
    when M is range:
      const nmulti2 = high(M) - low(M) + 1
    else:
      const nmulti2 = int(M)
    static:
      echo "dual nmulti ", nmulti1, " ", nmulti2
    dualMultiChannelStridedIteration(
      s1, s2, s1.order, s2.order,
      ind1, ind2, nmulti1, nmulti2)


template stridedCoordsIteration*(t, iter_offset, iter_size: typed): untyped =
  ## Iterate over a Tensor, displaying data as in C order, whatever the strides. (coords)

  # Get tensor data address with offset builtin
  withMemoryOptimHints()
  let data{.restrict.} = t.dataArray # Warning ⚠: data pointed may be mutated
  let rank = t.rank

  initStridedIteration(coord, backstrides, iter_pos, t, iter_offset, iter_size)
  for i in iter_offset..<(iter_offset+iter_size):
    yield (coord[0..<rank], data[iter_pos])
    advanceStridedIteration(coord, backstrides, iter_pos, t, iter_offset, iter_size)

