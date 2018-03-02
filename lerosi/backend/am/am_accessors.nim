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


type
  AmDirectNDSampler*[T] = object
    order: DataOrder
    msource: ptr AmBackendCpu[T]


proc initAmDirectNDSampler*[T](b: var AmBackendCpu[T], order: DataOrder): AmDirectNDSampler[T] =
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


# Super inefficient temporary implementation, using tensorIndex; see above. Proof of concept. Where do we go from here?
proc msampleND*[T: SomeNumber](samp: AmDirectNDSampler[T]; ind: varargs[int]): var T =
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
  var
    paramCount: int

  try:
    paramCount = int(nmulti.intVal)
  except:
    paramCount = MAX_IMAGE_CHANNELS
    # In this case, we inject if statements which break initialization at the
    # appropriate line, and we always unroll to maximum channel

  result = newStmtList()
  for i in 0..<paramCount:
    let
      next_index = i + 1

    var
      coordIdent = ident("coord" & $i)
      backstridesIdent = ident("backstrides" & $i)
      iter_posIdent = ident("iter_pos" & $i)
    
    result.add newCall(bindSym"declStridedIterationVars", [
      coordIdent,
      backstridesIdent,
      iter_posIdent
    ])


macro initMultiStridedIteration*(coord, backstrides, iter_pos: untyped, t, iter_offsets, iter_size: typed, nmulti: untyped): untyped =
  var
    initBlockLabel = genSym(nskLabel, ident="MULTI_STRIDED_ITERATION")
    initBlock = nnkBlockStmt.newTree(initBlockLabel, newStmtList())

    paramCount: int
    paramCountIsDynamic = false

  try:
    paramCount = int(nmulti.intVal)
  except:
    paramCount = MAX_IMAGE_CHANNELS
    paramCountIsDynamic = true
    # In this case, we inject if statements which break initialization at the
    # appropriate line, and we always unroll to maximum channels

  for i in 0..<paramCount:
    let
      next_index = i + 1

    var
      coordIdent = ident("coord" & $i)
      backstridesIdent = ident("backstrides" & $i)
      iter_posIdent = ident("iter_pos" & $i)
    
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

template advanceStridedIteration*(coord, backstrides, iter_pos, t, iter_offset, iter_size: typed, count: typed = 1): untyped =
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


macro advanceMultiStridedIteration*(coord, backstrides, iter_pos: untyped, t, iter_offsets, iter_size, nmulti, imulti: typed = 0, count: typed = 1): untyped =
  ## Computing the next positions
  result = newStmtList()

  let countDecl = newLetStmt(ident"cnt", newCall(bindSym"int", count))
  result.add countDecl

  for imulti in 0..<int(nmulti.intVal):
    let
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
    
    result.add outerFor


template stridedIterationYield*(strider: IterKind, data, i, iter_pos: typed) =
  ## Iterator the return value
  when strider == IterKind.Values: yield data[iter_pos]
  elif strider == IterKind.Iter_Values: yield (i, data[iter_pos])
  elif strider == IterKind.Offset_Values: yield (iter_pos, data[iter_pos]) ## TODO: remove workaround for C++ backend


macro makeIterPosIdent(iter_pos, imulti: untyped): untyped =
  #echo iter_pos.strVal, " ", iter_pos.kind
  result = ident(iter_pos.strVal & $(imulti.intVal))


# Using indexNamed on iter_pos
template multiStridedIterationYield*(
    iter_pos: untyped, strider: IterKind, data,
    iter_offsets, i, nmulti, res: typed,
    imulti: typed = 0, ioff: typed = 0): untyped =

  when imulti < nmulti:
    when strider == IterKind.Values:
      let ipos_z = makeIterPosIdent("iter_pos", imulti) # FIXME: Should use iter_pos parameter.
      res[imulti + ioff] = cast[ptr type(data[0])](data[iter_offsets[imulti] + ipos_z].addr)
      multiStridedIterationYield(
        iter_pos, strider, data, iter_offsets, i, nmulti, res, imulti + 1)

    # These modes not yet supported
    #elif strider == IterKind.Iter_Values: yield (i, data[iter_pos])
    #elif strider == IterKind.Offset_Values: yield (iter_pos, data[iter_pos]) ## TODO: remove workaround for C++ backend


template multiStridedIterationYieldOffset*(offset: typed,
    iter_pos: untyped, strider: IterKind, data,
    iter_offsets, i, nmulti, res: typed): untyped =

  multiStridedIterationYield(iter_pos, strider, data,
    iter_offsets, i, nmulti, res, ioff = offset)


# Only difference is that there is considered to be only one iter_pos.
template multiStridedIterationYieldContiguous*(
    iter_pos: untyped, strider: IterKind, data,
    iter_offsets, i, nmulti, res: typed,
    imulti: typed = 0, ioff: typed = 0): untyped =

  when imulti < nmulti:
    when strider == IterKind.Values:
      let ipos_z = iter_pos
      res[imulti + ioff] = cast[ptr type(data[0])](data[iter_offsets[imulti] + ipos_z].addr)
      multiStridedIterationYieldContiguous(
        iter_pos, strider, data, iter_offsets, i, nmulti, res, imulti + 1)

    # These modes not yet supported
    #elif strider == IterKind.Iter_Values: yield (i, data[iter_pos])
    #elif strider == IterKind.Offset_Values: yield (iter_pos, data[iter_pos]) ## TODO: remove workaround for C++ backend


template multiStridedIterationYieldContiguousOffset*(offset: typed,
    iter_pos: untyped, strider: IterKind, data,
    iter_offsets, i, nmulti, res: typed): untyped =

  multiStridedIterationYield(iter_pos, strider, data,
    iter_offsets, i, nmulti, res, ioff = offset)


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
  let
    areContiguous = t.is_C_Contiguous
    itsiz = iter_size
    nadv = adv

  use_mem_hints()
  let srcdata {.restrict.} = t.dataArray
  var res {.restrict.}: array[MAX_IMAGE_CHANNELS, ptr type(t.data[0])]


template declDualMultiStridedIterationData(lhsdata, rhsdata, res, areContiguous, itsiz, nadv, tlhs, trhs, iter_size, adv: untyped): untyped =
  let
    areContiguous = t.is_C_Contiguous
    itsiz = iter_size
    nadv = adv

  use_mem_hints()
  # Declare data for left and right hand sides.
  let lhsdata {.restrict.} = tlhs.dataArray
  let rhsdata {.restrict.} = trhs.dataArray
  # The result vector is twice the length.
  var res {.restrict.}: array[MAX_IMAGE_CHANNELS*2, pointer]



template multiStridedIteration(strider, t, iter_offsets, iter_size, adv: typed, nmulti: typed): untyped =
  when compileOption("boundChecks"):
    assert 0 <= adv,
      "LERoSI/backend/am/am_accessors: Bad adv step in multiStridedIteration"
  declMultiStridedIterationData(source, resultVector, areAllContiguous, itsiz, nadv, t, iter_size, adv)

  # Optimize for loops in contiguous cases
  if areAllContiguous:
    for j in countup(0, ((itsiz-1)*nadv), step=nadv):
      multiStridedIterationYieldContiguous(j, strider, source,
        iter_offsets, j, nmulti, resultVector)
      # The above only sets up a yield by writing to res.
      yield resultVector

  else:
    declMultiStridedIterationVars(coord, backstrides, iter_pos, nmulti)
    initMultiStridedIteration(coord, backstrides, iter_pos, t, iter_offsets, itsiz, nmulti)
    for j in countup(0, ((itsiz-1)*nadv), step=nadv):
      multiStridedIterationYield(iter_pos, strider, source, iter_offsets, j, nmulti, resultVector)
      yield resultVector
      advanceMultiStridedIteration(
        "coord", "backstrides", "iter_pos", t, iter_offsets, itsiz, nmulti, count = nadv)


template dualMultiStridedIteration(strider, tlhs, trhs,
    iter_offsets_lhs, iter_offsets_rhs,
    iter_size_lhs, iter_size_rhs,
    adv_lhs, adv_rhs: typed,
    nmulti_lhs, nmulti_rhs: typed): untyped =
  when compileOption("boundChecks"):
    assert 0 <= adv,
      "LERoSI/backend/am/am_accessors: Bad adv step in multiStridedIteration"
  declDualMultiStridedIterationData(lhsData, rhsData, resultVector, areAllContiguous, itsiz, nadv, tlhs, trhs, iter_size, adv)

  # Optimize for loops in contiguous cases
  if areAllContiguous:
    for j in countup(0, ((itsiz-1)*nadv), step=nadv):
      multiStridedIterationYieldContiguous(
        j, strider, lhsData, iter_offsets_lhs, j, nmulti_lhs, resultVector)
      multiStridedIterationYieldContiguousOffset(MAX_IMAGE_CHANNELS,
        j, strider, rhsData, iter_offsets_rhs, j, nmulti_rhs, resultVector)
      # The above only sets up a yield by writing to res.
      yield resultVector

  else:
    declMultiStridedIterationVars(
      coord_lhs, backstrides_lhs, iter_pos_lhs, nmulti_lhs)
    declMultiStridedIterationVars(
      coord_rhs, backstrides_rhs, iter_pos_rhs, nmulti_rhs)

    initMultiStridedIteration(
      coord_lhs, backstrides_lhs, iter_pos_lhs,
      tlhs, iter_offsets_lhs, itsiz, nmulti_lhs)
    initMultiStridedIteration(
      coord_rhs, backstrides_rhs, iter_pos_rhs,
      tlhs, iter_offsets_rhs, itsiz, nmulti_rhs)

    for j in countup(0, ((itsiz-1)*nadv), step=nadv):
      multiStridedIterationYield(
        iter_pos_lhs, strider, lhsData, iter_offsets, j, nmulti, resultVector)
      multiStridedIterationYieldOffset(MAX_IMAGE_CHANNELS,
        iter_pos_rhs, strider, rhsData, iter_offsets, j, nmulti, resultVector)
      yield resultVector
      advanceMultiStridedIteration(
        "coord_lhs", "backstrides_lhs", "iter_pos_lhs", t, iter_offsets, itsiz, nmulti, count = nadv)
      advanceMultiStridedIteration(
        "coord", "backstrides", "iter_pos", t, iter_offsets, itsiz, nmulti, count = nadv)


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

  var
    msrc = s.msource
    t = msrc[].backend_data
    totalsize = msrc[].backend_image_size(order)

    offsets: array[MAX_IMAGE_CHANNELS, int]
    adv: int


template initMultiChannelStridedIterationData(
    order, offsets, ind, t, adv, nmulti: typed): untyped =
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
  declMultiChannelStridedIterationData(msrc, t, totalsize, offsets, adv, s1, order)
  initMultiChannelStridedIterationData(order, offsets, ind, t, adv, nmulti)

  multiStridedIteration(
    IterKind.Values, t,
    offsets, totalsize,
    adv = adv, nmulti) # Added new advance parameter

template dualMultiChannelStridedIteration*(
    s1, s2, order1, order2,
    ind1, ind2, nmulti1, nmulti2: typed): untyped =

  declMultiChannelStridedIterationData(msrc1, t1, totalsize1, offsets1, adv1, s1, order1)
  declMultiChannelStridedIterationData(msrc2, t2, totalsize2, offsets2, adv2, s2, order2)

  initMultiChannelStridedIterationData(order1, offsets1, ind1, t1, adv1, nmulti1)
  initMultiChannelStridedIterationData(order2, offsets2, ind2, t2, adv2, nmulti2)

#strider, tlhs, trhs,
#    iter_offsets_lhs, iter_offsets_rhs,
#    iter_size_lhs, iter_size_rhs,
#    adv_lhs, adv_rhs: typed,
#    nmulti_lhs, nmulti_rhs: typed

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


iterator msampleNDchannels*[T](
    s1: AmDirectNDSampler[T], i: int): array[MAX_IMAGE_CHANNELS, ptr T] =
  multiChannelStridedIteration(s1, s1.order, [i], 1)


iterator sampleNDchannels*[T](
    s1: AmDirectNDSampler[T], i: int): array[MAX_IMAGE_CHANNELS, ptr T] =
  multiChannelStridedIteration(s1, s1.order, [i], 1)


# Need more work!
iterator sampleNDchannels*[T, U](
    s1: AmDirectNDSampler[T], s2: AmDirectNDSampler[U],
    i1, i2: int): array[MAX_IMAGE_CHANNELS*2, pointer] =
  dualMultiChannelStridedIteration(s1, s2, s1.order, s2.order, [i1], [i2], 1, 1)


iterator msampleNDchannels*[T](s1: var AmDirectNDSampler[T],
    i, j: int): array[MAX_IMAGE_CHANNELS, ptr T] =
  multiChannelStridedIteration(s1, s1.order, [i, j], 2)


iterator sampleNDchannels*[T](s1: AmDirectNDSampler[T],
    i, j: int): array[MAX_IMAGE_CHANNELS, ptr T] =
  multiChannelStridedIteration(s1, s1.order, [i, j], 2)


iterator msampleNDchannels*[T](s1: var AmDirectNDSampler[T],
    i, j, k: int): array[MAX_IMAGE_CHANNELS, ptr T] =
  multiChannelStridedIteration(s1, s1.order, [i, j, k], 3)


iterator sampleNDchannels*[T](s1: AmDirectNDSampler[T],
    i, j, k: int): array[MAX_IMAGE_CHANNELS, ptr T] =
  multiChannelStridedIteration(s1, s1.order, [i, j, k], 3)


iterator msampleNDchannels*[T](s1: var AmDirectNDSampler[T],
    i1, i2, i3, i4: int): array[MAX_IMAGE_CHANNELS, ptr T] =
  multiChannelStridedIteration(s1, s1.order, [i1, i2, i3, i4], 4)


iterator sampleNDchannels*[T](s1: AmDirectNDSampler[T],
    i1, i2, i3, i4: int): array[MAX_IMAGE_CHANNELS, ptr T] =
  multiChannelStridedIteration(s1, s1.order, [i1, i2, i3, i4], 4)


iterator msampleNDchannels*[T](
    s1: var AmDirectNDSampler[T],
    i1, i2, i3, i4, i5: int): array[MAX_IMAGE_CHANNELS, ptr T] =
  multiChannelStridedIteration(s1, s1.order, [i1, i2, i3, i4, i5], 5)


iterator sampleNDchannels*[T](
    s1: AmDirectNDSampler[T],
    i1, i2, i3, i4, i5: int): array[MAX_IMAGE_CHANNELS, ptr T] =
  multiChannelStridedIteration(s1, s1.order, [i1, i2, i3, i4, i5], 5)


iterator msampleNDchannels*[T](
    s1: var AmDirectNDSampler[T],
    i1, i2, i3, i4, i5, i6: int): array[MAX_IMAGE_CHANNELS, ptr T] =
  multiChannelStridedIteration(s1, s1.order, [i1, i2, i3, i4, i5, i6], 6)


iterator sampleNDchannels*[T](
    s1: AmDirectNDSampler[T],
    i1, i2, i3, i4, i5, i6: int): array[MAX_IMAGE_CHANNELS, ptr T] =
  multiChannelStridedIteration(s1, s1.order, [i1, i2, i3, i4, i5, i6], 6)


iterator msampleNDchannels*[T](
    s1: var AmDirectNDSampler[T],
    i1, i2, i3, i4, i5, i6, i7: int): array[MAX_IMAGE_CHANNELS, ptr T] =
  multiChannelStridedIteration(s1, s1.order, [i1, i2, i3, i4, i5, i6, i7], 7)


iterator sampleNDchannels*[T](
    s1: AmDirectNDSampler[T],
    i1, i2, i3, i4, i5, i6, i7: int): array[MAX_IMAGE_CHANNELS, ptr T] =
  multiChannelStridedIteration(s1, s1.order, [i1, i2, i3, i4, i5, i6, i7], 7)


iterator sampleNDchannels*[T](
    s1: AmDirectNDSampler[T],
    ind: array[1, int]): array[MAX_IMAGE_CHANNELS, ptr T] =
  for x in sampleNDchannels(s1, ind[0]):
    yield x


iterator sampleNDchannels*[T](
    s1: AmDirectNDSampler[T],
    ind: array[2, int]): array[MAX_IMAGE_CHANNELS, ptr T] =
  for x in sampleNDchannels(s1, ind[0], ind[1]):
    yield x


iterator sampleNDchannels*[T](
    s1: AmDirectNDSampler[T],
    ind: array[3, int]): array[MAX_IMAGE_CHANNELS, ptr T] =
  for x in sampleNDchannels(s1, ind[0], ind[1], ind[2]):
    yield x


iterator sampleNDchannels*[T](
    s1: AmDirectNDSampler[T],
    ind: array[4, int]): array[MAX_IMAGE_CHANNELS, ptr T] =
  for x in sampleNDchannels(s1, ind[0], ind[1], ind[2], ind[3]):
    yield x


iterator sampleNDchannels*[T](
    s1: AmDirectNDSampler[T],
    ind: array[5, int]): array[MAX_IMAGE_CHANNELS, ptr T] =
  for x in sampleNDchannels(s1,
      ind[0], ind[1], ind[2], ind[3], ind[4]):
    yield x


iterator sampleNDchannels*[T](
    s1: AmDirectNDSampler[T],
    ind: array[6, int]): array[MAX_IMAGE_CHANNELS, ptr T] =
  for x in sampleNDchannels(s1,
      ind[0], ind[1], ind[2], ind[3], ind[4], ind[5]):
    yield x


iterator sampleNDchannels*[T](
    s1: AmDirectNDSampler[T],
    ind: array[7, int]): array[MAX_IMAGE_CHANNELS, ptr T] =
  for x in sampleNDchannels(s1,
      ind[0], ind[1], ind[2], ind[3], ind[4], ind[5], ind[6]):
    yield x


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

