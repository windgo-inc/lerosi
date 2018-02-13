import macros, sequtils, strutils, tables, future
import system

import ./macroutil
import ./fixedseq
import ./img_permute
import ./spaceconf

export spaceconf

type
  RWFrameObject*[Backend] = object of RootObj
    ## Readable and writable concrete frame object,
    ## intended for inplace manipulation. Does not
    ## have ordering data.
    dat: Backend

  ROFrameObject*[Backend] = object of RootObj
    ## Read only concrete frame object, intended
    ## for streaming input interfaces. Does not
    ## have ordering data.
    dat: Backend

  WOFrameObject*[Backend] = object of RootObj
    ## Write only concrete frame object, intended
    ## for streaming output interfaces. Does not
    ## have ordering data
    dat: Backend

  OrderedFrame[FrameType] = object of FrameType
    ordr: DataOrder

  OrderedRWFrameObject*[Backend] = OrderedFrame[RWFrameObject[Backend]]
    ## Readable and writable concrete frame object,
    ## intended for inplace manipulation. Carries
    ## ordering metadata.

  OrderedROFrameObject*[Backend] = OrderedFrame[ROFrameObject[Backend]]
    ## Read only concrete frame object, intended
    ## for streaming input interfaces. Carries
    ## ordering metadata.

  OrderedWOFrameObject*[Backend] = OrderedFrame[WOFrameObject[Backend]]
    ## Write only concrete frame object, intended
    ## for streaming output interfaces. Carries
    ## ordering metadata.


proc frame_data*[U: ROFrameObject|RWFrameObject](frame: U): U.Backend =
  ## Frame data accessor for readable data frame objects.
  result = frame.dat

proc frame_data*[U: RWFrameObject](frame: var U): var U.Backend =
  ## Frame data mutable accessor for read-write data frame objects.
  result = frame.dat

proc frame_order*[U: OrderedFrame](frame: U): DataOrder =
  ## Get the ordering of any frame object, including write only frame objects.
  ## This is neccesary to determine what the ordering of the data to write must
  ## be.
  frame.ordr

proc `frame_data=`*[U: RWFrameObject|WOFrameObject](frame: var U,
    data: U.Backend) =
  ## Frame data setter for writable data frames.
  frame.dat = data

proc `frame_order=`*[U: OrderedRWFrameObject|OrderedWOFrameObject](
    frame: U; order: DataOrder) =
  ## Set the ordering of a writable frame object. Note that this will not
  ## rotate the storage order for any data written; it is the responsibility
  ## of the caller to ensure that the written data are in the right order.
  frame.ordr = order


type
  ReadDataFrame*[Backend] = concept frame
    ## A readable DataFrame, having a frame_data getter yielding a Backend.
    frame.frame_data is Backend

  WriteDataFrame*[Backend] = concept frame
    ## A writable DataFrame, having a frame_data setter accepting a Backend.
    frame.frame_data = Backend
    
  DataFrame*[Backend] = concept frame
    ## A readable or writable DataFrame
    frame is ReadDataFrame[Backend] or frame is WriteDataFrame[Backend]

  ReadOnlyDataFrame*[Backend] = concept frame
    ## A readable data frame which is not writable.
    frame is ReadDataFrame[Backend]
    not (frame is WriteDataFrame[Backend])

  WriteOnlyDataFrame*[Backend] = concept frame
    ## A writable data frame which is not readable.
    frame is WriteDataFrame[Backend]
    not (frame is ReadDataFrame[Backend])

  OrderedDataFrame*[Backend] = concept frame
    ## A data frame with an associated data ordering.
    frame is DataFrame[Backend]
    frame.frame_order is DataOrder

  UnorderedDataFrame*[Backend] = concept frame
    ## A data frame with no associated data ordering.
    frame is DataFrame[Backend]
    not (frame is OrderedDataFrame[Backend])



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


