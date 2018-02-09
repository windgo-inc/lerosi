import macros, sequtils, strutils, tables, future
import system

import ./macroutil
import ./fixedseq
import ./img_permute
import ./img_conf

export img_conf

type
  RWFrameObject*[Backend] = object
    dat: Backend

  ROFrameObject*[Backend] = object
    dat: Backend

  WOFrameObject*[Backend] = object
    dat: Backend


proc frame_data*[U: ROFrameObject|RWFrameObject](frame: U): auto = frame.dat
proc `frame_data=`*[U: RWFrameObject|WOFrameObject](frame: var U, dat: U.Backend) =
  frame.dat = dat

type
  ReadDataFrame*[Backend] = concept frame
    frame.frame_data is Backend

  WriteDataFrame*[Backend] = concept frame
    frame.frame_data = Backend
    
  DataFrame*[Backend] = concept frame
    frame is ReadDataFrame[Backend] or frame is WriteDataFrame[Backend]

  ReadOnlyDataFrame*[Backend] = concept frame
    frame is ReadDataFrame[Backend]
    not (frame is WriteDataFrame[Backend])

  WriteOnlyDataFrame*[Backend] = concept frame
    frame is WriteDataFrame[Backend]
    not (frame is ReadDataFrame[Backend])

when isMainModule:
  import arraymancer # Needed for atypical access to internals for testing.
  import ./backend/am # Temporary, not needed from here.

  template checkFrameConcepts(frame: untyped): untyped =
    trace_result(frame is DataFrame)
    trace_result(frame is ReadDataFrame)
    trace_result(frame is WriteDataFrame)
    trace_result(frame is ReadOnlyDataFrame)
    trace_result(frame is WriteOnlyDataFrame)

    var backend: AMBackendCpu[int]
    trace_result(compiles((frame.data)))
    trace_result(compiles((frame.data = backend)))

  var myFrame: RWFrameObject[AmBackendCpu[int]]
  var myReadOnly: ROFrameObject[AmBackendCpu[int]]
  var myWriteOnly: WOFrameObject[AmBackendCpu[int]]

  checkFrameConcepts(myFrame)
  checkFrameConcepts(myReadOnly)
  checkFrameConcepts(myWriteOnly)
  
  var myCpuData: AmBackendCpu[int]
  var planarSlices: array[0..2, AmBackendCpu[int]]
  var interleavedSlices: array[0..2, AmBackendCpu[int]]

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
    echo "[SLICE ", i, " ", planarSlices[i].backend_data_shape, "] ",
      planarSlices[i].backend_data

  myCpuData.backend_rotate DataInterleaved

  echo "Checking interleaved channel slices:"
  for i in 0..2:
    interleavedSlices[i] = myCpuData.slice_channel(DataInterleaved, i)
    echo "[SLICE ", i, " ", interleavedSlices[i].backend_data_shape, "] ",
      interleavedSlices[i].backend_data

  echo "Checking equality..."
  for i in 0..2:
    let slice1 = planarSlices[i].backend_data().squeeze
    let slice2 = interleavedSlices[i].backend_data().squeeze
    if slice1 == slice2:
      echo "[OK ", i, "]"
    else:
      echo "[FAIL ", i, "]"



