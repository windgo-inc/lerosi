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

import ./detail/macroutil
import ./fixedseq
import ./spacemeta
import ./spaceconf
import ./backend

export spaceconf

type
  RWFrameObject*[Backend] = object
    ## Readable and writable concrete frame object,
    ## intended for inplace manipulation.
    ## Has ordering metadata.
    dat: Backend
    ordr: DataOrder

  ROFrameObject*[Backend] = object
    ## Read only concrete frame object, intended
    ## for streaming input interfaces.
    ## Has ordering metadata.
    dat: Backend
    ordr: DataOrder

  WOFrameObject*[Backend] = object
    ## Write only concrete frame object, intended
    ## for streaming output interfaces.
    ## Has ordering metadata.
    dat: Backend
    ordr: DataOrder


proc frame_data*[U: ROFrameObject|RWFrameObject](frame: U): U.Backend =
  ## Frame data accessor for readable data frame objects.
  result = frame.dat

proc frame_data*[U: RWFrameObject](frame: var U): var U.Backend =
  ## Frame data mutable accessor for read-write data frame objects.
  result = frame.dat

proc frame_order*[U: ROFrameObject|WOFrameObject|RWFrameObject](frame: U): DataOrder =
  ## Get the ordering of any frame object, including write only frame objects.
  ## This is neccesary to determine what the ordering of the data to write must
  ## be.
  frame.ordr

proc `frame_data=`*[U: RWFrameObject|WOFrameObject](frame: var U,
    data: U.Backend) =
  ## Frame data setter for writable data frames.
  frame.dat = data

proc `frame_order=`*[U: RWFrameObject|WOFrameObject|ROFrameObject](
    frame: var U; order: DataOrder) =
  ## Set the ordering of a writable frame object. Note that this will not
  ## rotate the storage order for any data written; it is the responsibility
  ## of the caller to ensure that the written data are in the right order.
  frame.ordr = order


proc FrameTypeNode*(name, access: string, T: NimNode): NimNode {.compileTime.} =
  let
    betype = BackendTypeNode(name, T)
    upperAccess = access.toUpperAscii

  case upperAccess:
    of "RO", "R":  result = nnkBracketExpr.newTree(bindSym"ROFrameObject", betype)
    of "WO", "W":  result = nnkBracketExpr.newTree(bindSym"WOFrameObject", betype)
    of "RW", "WR": result = nnkBracketExpr.newTree(bindSym"RWFrameObject", betype)
    else:
      quit "Invalid access descriptor string " & access & " for FrameType " & name & "."

macro FrameType*(name, access, T: untyped): untyped =
  ## Backend type selector
  result = FrameTypeNode($name, $access, T)

type
  ReadDataFrame*[B] = ROFrameObject[B]|RWFrameObject[B]
  WriteDataFrame*[B] = WOFrameObject[B]|RWFrameObject[B]
  ReadOnlyDataFrame*[B] = ROFrameObject[B]
  WriteOnlyDataFrame*[B] = WOFrameObject[B]
  DataFrame*[B] = ROFrameObject[B]|WOFrameObject[B]|RWFrameObject[B]


proc initFrame*[U; S: not int](result: var U; order: DataOrder; sh: S) {.inline.} =
  backend_data_noinit(result.dat, sh)
  result.ordr = order

proc initFrame*[U; S: not int; T](result: var U; order: DataOrder; dat: seq[T], sh: S) {.inline.} =
  backend_data_raw(result.dat, dat, sh)
  result.ordr = order

proc initFrameSlices*[U; S: not int](result: var U; order: DataOrder; slices: varargs[S]) {.inline.} =
  backend_slices_source(result.dat, order, slices)
  result.ordr = order

proc initFrameSlices*[U; S: not int](result: var U; order: DataOrder; slices: seq[S]) {.inline.} =
  backend_slices_source(result.dat, order, slices)
  result.ordr = order

proc initFrame*[U](result: var U; order: DataOrder; sh: varargs[int]) {.inline.} =
  backend_data_noinit(result.dat, sh)
  result.ordr = order

proc initFrame*[U; T](result: var U; order: DataOrder; dat: seq[T], sh: varargs[int]) {.inline.} =
  backend_data_raw(result.dat, dat, sh)
  result.ordr = order

#proc initFrame*[U: DataFrame; Storage](result: var U; order: DataOrder; dat: Storage) {.inline.} =
#  backend_data(result.dat, dat)
#  result.order = order


proc interleaved*[U: DataFrame](frame: U): U {.inline, noSideEffect.} =
  ## Rotate to interleaved storage order.
  result.ordr = DataInterleaved
  case frame.ordr:
    of DataPlanar:
      result.dat = backend_rotate_interleaved(frame.dat)
    of DataInterleaved:
      result.dat = frame.dat


proc planar*[U: DataFrame](frame: U): U {.inline, noSideEffect.} =
  ## Rotate to interleaved storage order.
  result.ordr = DataPlanar
  case frame.ordr:
    of DataInterleaved:
      result.dat = frame.dat
      result.dat = backend_rotate_planar(result.dat)
    of DataPlanar:
      result.dat = frame.dat


proc ordered*[U: DataFrame](frame: U; order: DataOrder): U {.inline, noSideEffect.} =
  if not (result.ordr == order):
    result.dat = frame.dat
    result.dat = backend_rotate(result.dat, order)
    result.ordr = order


proc shape*[U: DataFrame](frame: U): auto {.inline, noSideEffect.} = #ShapeType(U) =
  case frame.ordr:
    of DataInterleaved:
      result = backend_data_shape(frame.dat)
      result = result[0..result.len - 2]
    of DataPlanar:
      result = backend_data_shape(frame.dat)
      result = result[1..result.len - 1]


proc channel_count*[U: DataFrame](frame: U): int {.inline, noSideEffect.} =
  case frame.ordr:
    of DataInterleaved:
      let v = backend_data_shape(frame.dat)
      result = v[v.len - 1].int
    of DataPlanar:
      let v = backend_data_shape(frame.dat)
      result = v[0].int


proc channel*[U: DataFrame](frame: U; i: int): auto {.inline, noSideEffect.} =
  slice_channel frame.dat, frame.ordr, i

proc channel*[T; U: DataFrame](frame: var U; i: int; slc: T): var U {.inline, discardable.} =
  discard mslice_channel(frame.dat, frame.ordr, i, slc)
  frame

proc channels_impl[U: DataFrame](frame: U; idx: openarray[int]|seq[int]|ChannelIndex): U {.inline.} =
  # TODO: Move the slicing to initFrame slices so that the unneccessary
  # sequence is eliminated.

  # A hack to set the type of the sequence without reverse type lookup.
  # Ugly!
  var slices = @[slice_channel(frame.dat, frame.ordr, 0)]
  slices.delete(0)
  for i in 0..<idx.len:
    if 0 <= idx[i]:
      slices.add slice_channel(frame.dat, frame.ordr, idx[i])
    else:
      # Missing indices are given zeros
      slices.add slice_channel_zero(frame.dat, frame.ordr)

  initFrameSlices result, frame.ordr, slices

proc channelspan_impl[U: DataFrame](frame: U; slc: Slice[int]): U {.inline.} =
  # TODO: Move the slicing to initFrame slices so that the unneccessary
  # sequence is eliminated.

  # A hack to set the type of the sequence without reverse type lookup.
  # Ugly!
  var slices = @[slice_channel(frame.dat, frame.ordr, slc.a)]
  if slc.a < slc.b:
    for i in countup(slc.a+1, slc.b):
      slices.add slice_channel(frame.dat, frame.ordr, i)
  elif slc.a > slc.b:
    for i in countdown(slc.a-1, slc.b):
      slices.add slice_channel(frame.dat, frame.ordr, i)

  initFrameSlices result, frame.ordr, slices

proc channels*[U: DataFrame](frame: U; idx: ChannelIndex): U {.inline.} =
  channels_impl(frame, idx)

proc channels*[U: DataFrame](frame: U; idx: varargs[int]): U {.inline.} =
  channels_impl(frame, idx)

proc channels*[U: DataFrame](frame: U; idx: seq[int]): U {.inline.} =
  channels_impl(frame, idx)

proc channelspan*[U: DataFrame](frame: U; slc: Slice[int]): U {.inline.} =
  channelspan_impl(frame, slc)


when isMainModule:
  import arraymancer # Needed for atypical access to internals for testing.
  import ./backend/am # Temporary, not needed from here.

  template checkFrameConcepts(frame: untyped): untyped =
    trace_result(frame is DataFrame)
    trace_result(frame is ReadDataFrame)
    trace_result(frame is WriteDataFrame)
    trace_result(frame is ReadOnlyDataFrame)
    trace_result(frame is WriteOnlyDataFrame)

    var backend: AmBackendCpu[int]
    trace_result(compiles((frame.data)))
    trace_result(compiles((frame.data = backend)))

  var myFrame: RWFrameObject[AmBackendCpu[int]]
  var myReadOnly: ROFrameObject[AmBackendCpu[int]]
  var myWriteOnly: WOFrameObject[AmBackendCpu[int]]

  checkFrameConcepts(myFrame)
  checkFrameConcepts(myReadOnly)
  checkFrameConcepts(myWriteOnly)
  
  var myCpuData: AmBackendCpu[int]
  var planarSlices: array[0..2, AmSliceCpu[int]]
  var interleavedSlices: array[0..2, AmSliceCpu[int]]

  let testSlice = [
    [1, 2, 3, 4, 5],
    [6, 7, 8, 9, 10],
    [11, 12, 13, 14, 15],
    [16, 17, 18, 19, 20],
    [21, 22, 23, 24, 25]
  ].toTensor().reshape(1, 5, 5)

  myCpuData.backend_data(
    concat(testSlice, testSlice .+ 25, testSlice .+ 50, axis = 0))

  echo "Checking planar channel slices:"
  for i in 0..2:
    planarSlices[i] = myCpuData.slice_channel(DataPlanar, i)
    echo "[SLICE ", i, " ", planarSlices[i].slice_shape, "] ",
      planarSlices[i].slice_data

  echo "Rotating to interleaved."
  echo "myCpuData.backend_rotate DataInterleaved"
  myCpuData.backend_rotate DataInterleaved

  echo "Checking interleaved channel slices:"
  for i in 0..2:
    interleavedSlices[i] = myCpuData.slice_channel(DataInterleaved, i)
    echo "[SLICE ", i, " ", interleavedSlices[i].slice_shape, "] ",
      interleavedSlices[i].slice_data

  echo "Checking equality..."
  for i in 0..2:
    let slice1 = planarSlices[i].slice_data
    let slice2 = interleavedSlices[i].slice_data
    echo((if slice1 == slice2: "[OK " else: "[FAIL "), i, "]")

  echo "Rotating to planar."
  echo "myCpuData.backend_rotate DataPlanar"
  myCpuData.backend_rotate DataPlanar

  echo "Checking restored planar channel slice consistency:"
  for i in 0..2:
    let isgood =
      myCpuData.slice_channel(DataPlanar, i) == interleavedSlices[i]
    echo((if isgood: "[OK " else: "[FAIL "), i, "]")


