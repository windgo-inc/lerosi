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

import system, sequtils, strutils, unittest, macros, math, future, algorithm
import typetraits

import lerosi
import lerosi/macroutil
import lerosi/detail/picio
import lerosi/picture
import lerosi/img

# Nicer alias for save options.
type
  SO = SaveOptions

#const testChannelSpaceIds = [
#  VideoChSpaceA,         # VideoA
#  VideoChSpaceY,         # VideoY
#  VideoChSpaceYp,        # VideoYp
#  VideoChSpaceRGB,       # VideoRGB
#  VideoChSpaceCMYe,      # VideoCMYe
#  VideoChSpaceHSV,       # VideoHSV
#  VideoChSpaceYCbCr,     # VideoYCbCr
#  VideoChSpaceYpCbCr,    # VideoYpCbCr
#  PrintChSpaceK,         # PrintK
#  PrintChSpaceCMYeK,     # PrintCMYeK
#  AudioChSpaceLfe,       # AudioLfe
#  AudioChSpaceMono,      # AudioMono
#  AudioChSpaceLeftRight, # AudioLeftRight
#  AudioChSpaceLfRfLbRb   # AudioLfRfLbRb
#]

suite "LERoSI Unit Tests":
  var
    # backend globals
    testpic_initialized = false
    testpic: BackendType("*", byte)
    hdrpic: BackendType("*", cfloat)
    expect_shape: MetadataArray

    # IIO/base globals
    #testimg: StaticOrderFrame[byte, ChannelSpaceTypeAny, DataInterleaved]

    #plnrimg: StaticOrderFrame[byte, ChannelSpaceTypeAny, DataPlanar]
    #ilvdimg: StaticOrderFrame[byte, ChannelSpaceTypeAny, DataInterleaved]
    #dynimg: DynamicOrderFrame[byte, ChannelSpaceTypeAny]

  test "picio load test reference image (PNG)":
    try:
      testpic = picio_load_core("test/sample.png")
      hdrpic.backend_source(testpic, x => x.cfloat / 255.0)
      expect_shape = testpic.backend_data_shape
      testpic_initialized = true
    except:
      testpic_initialized = false
      raise

  template require_equal_extent[T; U](pic: BackendType("*", T), expectpic: BackendType("*", U)): untyped =
    require pic.backend_data_shape[0..1] == expectpic.backend_data_shape[0..1]

  template require_equal_extent[T](pic: BackendType("*", T)): untyped =
    require pic.backend_data_shape[0..1] == testpic.backend_data_shape[0..1]

  template check_equal_extent[T; U](pic: BackendType("*", T), expectpic: BackendType("*", U)): untyped =
    check pic.backend_data_shape[0..1] == expectpic.backend_data_shape[0..1]

  template check_equal_extent[T](pic: BackendType("*", T)): untyped =
    check pic.backend_data_shape[0..1] == testpic.backend_data_shape[0..1]

  template require_consistency[T; U](pic: BackendType("*", T), expectpic: BackendType("*", U)): untyped =
    require_equal_extent pic, expectpic
    # TODO: Add a histogram check

  template require_consistency[T](pic: BackendType("*", T)): untyped =
    require_consistency pic, testpic

  template check_consistency[T; U](pic: BackendType("*", T), expectpic: BackendType("*", U)): untyped =
    check_equal_extent pic, expectpic

  template check_consistency[T](pic: BackendType("*", T)): untyped =
    check_consistency pic, testpic

  #template test_jpeg_decades(fn: untyped): untyped =
  #  template gn(qual: int): untyped =
  #    fn(qual);   fn(qual-1); fn(qual-2); fn(qual-3); fn(qual-4);
  #    fn(qual-5); fn(qual-6); fn(qual-7); fn(qual-8); fn(qual-9);

  #  gn(100); gn(90); gn(80);# gn(70);
  #  #gn(60);  gn(50); gn(40); gn(30);

  test "picio obtained test image":
    require testpic_initialized
  
  test "Backend extent equality":
    require(testpic.backend_data_shape == expect_shape)

  test "Backend extent identity":
    require_equal_extent testpic

  test "picio save BMP":
    require testpic.picio_save_core(
      "test/samplepng-out.bmp",
      SO(format: BMP))

  test "picio save PNG":
    require testpic.picio_save_core(
      "test/samplepng-out.png",
      SO(format: PNG, stride: 0))

  test "picio save JPEG":
    require testpic.picio_save_core(
      "test/samplepng-out.jpeg",
      SO(format: JPEG, quality: 100))

  # We want to prevent template explosion; this is a big part of
  # why the high level interface should be preferred.
  proc do_write_jpeg_test[T](pic: BackendType("*", T), qual: int): bool =
    result = testpic.picio_save_core(
      "test/samplepng-out.q" & $qual & ".jpeg",
      SO(format: JPEG, quality: qual))

  test "picio save JPEG quality parameter coverage":
    var n: int = 0
    for qual in countdown(100, 10):
      check do_write_jpeg_test(testpic, qual)
      inc n
    echo "    # Quality variations saved: ", n

  test "picio save HDR":
    check picio_save_core(hdrpic,
      "test/samplepng-out.hdr",
      SO(format: HDR))

  # Loading

  test "picio load BMP":
    let inpic = picio_load_core("test/samplepng-out.bmp")
    check_consistency inpic
    
  test "picio load PNG":
    let inpic = picio_load_core("test/samplepng-out.png")
    check_consistency inpic

  test "picio load JPEG":
    let inpic = picio_load_core("test/samplepng-out.jpeg")
    check_consistency inpic

  # We want to prevent template explosion; this is a big part of
  # why the high level interface should be preferred.
  proc do_read_jpeg_test(qual: int): AmBackendCpu[byte] =
    result = picio_load_core("test/samplepng-out.q" & $qual & ".jpeg")

  # Wrapping picio_load_core template
  #proc do_read_res_test(res: string): AmBackendCpu[byte] =
  #  result = picio_loadstring_core(res)


  test "picio load JPEG quality parameter coverage":
    var n: int = 0
    for qual in countdown(100, 10):
      check_consistency do_read_jpeg_test(qual)
      inc n
    echo "    # Quality variations loaded: ", n

  test "picio load HDR":
    let inpic = picio_load_hdr_core("test/samplepng-out.hdr")
    check_consistency inpic, hdrpic

  test "picio encode and decode BMP in-memory":
    let coredata = picio_savestring_core(testpic, SO(format: BMP))
    echo "    # Saved BMP size is ", formatFloat(coredata.len.float / 1024.0, precision = 5), "KB"
    let recovered = coredata.picio_loadstring_core
    check_consistency testpic, recovered

  test "picio encode and decode PNG in-memory":
    let coredata = picio_savestring_core(testpic, SO(format: PNG, stride: 0))
    echo "    # Saved PNG size is ", formatFloat(coredata.len.float / 1024.0, precision = 5), "KB"
    let recovered = coredata.picio_loadstring_core
    check_consistency testpic, recovered

  test "picio encode and decode JPEG in-memory":
    let coredata = picio_savestring_core(testpic, SO(format: JPEG, quality: 100))
    echo "    # Saved JPEG size is ", formatFloat(coredata.len.float / 1024.0, precision = 5), "KB"
    let recovered = coredata.picio_loadstring_core
    check_consistency testpic, recovered

  test "picio encode and decode HDR in-memory":
    let coredata = picio_savestring_core(hdrpic, SO(format: HDR))
    echo "    # Saved HDR size is ", formatFloat(coredata.len.float / 1024.0, precision = 5), "KB"
    let recovered = coredata.picio_loadstring_hdr_core
    check_consistency hdrpic, recovered

  test "backend rotate storage order correctness":
    var plnrpic: AmBackendCpu[byte]
    plnrpic.backend_source testpic
    plnrpic.backend_rotate DataPlanar

    for i in 0..plnrpic.backend_data_shape[0]-1:
      check plnrpic.slice_channel_planar(i).slice_data == testpic.slice_channel_interleaved(i).slice_data

    var ilvdpic: AmBackendCpu[byte]
    ilvdpic.backend_source plnrpic
    ilvdpic.backend_rotate DataInterleaved

    for i in 0..plnrpic.backend_data_shape[0]-1:
      check plnrpic.slice_channel_planar(i).slice_data == ilvdpic.slice_channel_interleaved(i).slice_data

    check backend_cmp(ilvdpic, testpic)

  template lengthCheck(cspace: untyped): untyped =
    const cslen = len(cspace)
    const csorder = order(cspace)
    check csorder.len == cslen

  template runTimeLengthCheck(cspace: untyped): untyped =
    let cslen = len(cspace)
    let csorder = order(cspace)
    check csorder.len == cslen

  template orderCheck(cspace: untyped): untyped =
    const csorder = order(cspace)
    const cschans = channels(cspace)

    var n: int = 0
    for ch in cschans:
      inc n
      check csorder[order(cspace, ch)] == ch

    check n == csorder.len
    for i, o in csorder:
      check i == order(cspace, o)

  template runTimeOrderCheck(cspace: untyped): untyped =
    let csorder = order(cspace)
    let cschans = channels(cspace)

    var n: int = 0
    for ch in cschans:
      inc n
      check csorder[order(cspace, ch)] == ch

    check n == csorder.len
    for i, o in csorder:
      check i == order(cspace, o)

  template nameCheck(cspace: untyped): untyped =
    const name = cspace.name
    const nameToId = name.channelspaceof
    check cspace == nameToId

  template runTimeNameCheck(cspace: untyped): untyped =
    let name = cspace.name
    let nameToId = name.channelspaceof
    check cspace == nameToId

  template nameCheckCh(ch: untyped): untyped =
    const name = ch.name
    const nameToId = name.channelof
    check ch == nameToId

  template runTimeNameCheckCh(ch: untyped): untyped =
    let name = ch.name
    let nameToId = name.channelof
    check ch == nameToId

  template forEachSpace(fn: untyped): untyped =
    fn(VideoChSpaceA)         # VideoA
    fn(VideoChSpaceY)         # VideoY
    fn(VideoChSpaceYp)        # VideoYp
    fn(VideoChSpaceRGB)       # VideoRGB
    fn(VideoChSpaceCMYe)      # VideoCMYe
    fn(VideoChSpaceHSV)       # VideoHSV
    fn(VideoChSpaceYCbCr)     # VideoYCbCr
    fn(VideoChSpaceYpCbCr)    # VideoYpCbCr
    fn(PrintChSpaceK)         # PrintK
    fn(PrintChSpaceCMYeK)     # PrintCMYeK
    fn(AudioChSpaceLfe)       # AudioLfe
    fn(AudioChSpaceMono)      # AudioMono
    fn(AudioChSpaceLeftRight) # AudioLeftRight
    fn(AudioChSpaceLfRfLbRb)  # AudioLfRfLbRb

  template forEachChannel(fn: untyped): untyped =
    fn(VideoChIdA)            # VideoA
    fn(VideoChIdY)            # VideoY
    fn(VideoChIdYp)           # VideoYp
    fn(VideoChIdR)            # VideoR
    fn(VideoChIdG)            # VideoG
    fn(VideoChIdB)            # VideoB
    fn(VideoChIdC)            # VideoC
    fn(VideoChIdM)            # VideoM
    fn(VideoChIdYe)           # VideoYe
    fn(VideoChIdH)            # VideoH
    fn(VideoChIdS)            # VideoS
    fn(VideoChIdV)            # VideoV
    fn(VideoChIdCb)           # VideoCb
    fn(VideoChIdCr)           # VideoCr
    fn(PrintChIdK)            # PrintK
    fn(PrintChIdC)            # PrintC
    fn(PrintChIdM)            # PrintM
    fn(PrintChIdYe)           # PrintYe
    fn(AudioChIdLfe)          # AudioLfe
    fn(AudioChIdMono)         # AudioMono
    fn(AudioChIdLeft)         # AudioLeft
    fn(AudioChIdRight)        # AudioRight
    fn(AudioChIdLf)           # AudioLf
    fn(AudioChIdRf)           # AudioRf
    fn(AudioChIdLb)           # AudioLb
    fn(AudioChIdRb)           # AudioRb

  test "CT^2-DB ChannelSpace enumeration":
    for id in ChannelSpace: echo "    # ", id.name

  test "CT^2-DB ChannelId enumeration":
    for id in ChannelId: echo "    # ", id.name

  test "CT^2-DB ChannelSpace length consistency compile-time check":
    forEachSpace(lengthCheck)

  test "CT^2-DB ChannelSpace order consistency compile-time check":
    forEachSpace(orderCheck)

  test "CT^2-DB ChannelSpace to/from string compile-time naming consistency":
    forEachSpace(nameCheck)

  test "CT^2-DB ChannelSpace length consistency run-time check":
    for id in ChannelSpace: runTimeLengthCheck(id)

  test "CT^2-DB ChannelSpace order consistency run-time check":
    for id in ChannelSpace: runTimeOrderCheck(id)

  test "CT^2-DB ChannelSpace to/from string run-time naming consistency":
    for id in ChannelSpace: runTimeNameCheck(id)

  test "CT^2-DB ChannelId to/from string compile-time naming consistency":
    forEachChannel(nameCheckCh)

  test "CT^2-DB ChannelId to/from string run-time naming consistency":
    for id in ChannelId: runTimeNameCheckCh(id)

  proc genericallyGetTheType[T](x: T): string =
    result = SliceType(T).name

  test "CT^2-DB reverse type lookup":
    var x: AmBackendCpu[int]

    check compiles((SliceType(AmBackendCpu[int]).name))
    check compiles((genericallyGetTheType(x)))

  var runtimeCallValue: int = 0
  proc amIEagerlyDoingIt(x: int): bool {.eagerCompile.} =
    when nimvm:
      result = true
    else:
      runtimeCallValue = x
      result = false
  
  test "macroutil repeatStatic 11, 0, i is monotonic":
    var x: int = -1
    repeatStatic 11, 0:
      inc x
      check x == i

  test "macroutil eagerCompile with static parameters runs in nimvm":
    repeatStatic 11, 0:
      check amIEagerlyDoingIt(i)
    check runtimeCallValue == 0

  template check_channel_layout(layout: untyped): untyped =
    check layout.channelspace in layout.mapping.possibleChannelSpaces
    for ch in layout.mapping:
      check ch in layout.channelspace.channels
      check ch in layout.channelspace.order

  template all_permutations(namespace: string, channelLists: openarray[seq[string]]): untyped =
    var
      q: seq[string]
      bLoop = true

    for channels in channelLists:
      deepCopy q, channels
      sort q, system.cmp
      while bLoop:
        check_channel_layout(defChannelLayout(namespace & q.join))
        bLoop = nextPermutation(q)

  template all_ordinary_subgroups(ns, a, b, c, d, o: untyped): untyped =
    all_permutations(ns, [
      @[a, b, c, d, o],
      @[a, b, c, d],
      @[a, b, o],
      @[c, d, o],
      @[a, b],
      @[c, d]
    ])
  
  template all_ordinary_subgroups(ns, a, b, c, o: untyped): untyped =
    all_permutations(ns, [
      @[a, b, c, o],
      @[a, b, c],
      @[a, b],
      @[a, c],
      @[b, c],
      @[a],
      @[b],
      @[c],
      @[o]
    ])

  template all_ordinary_subgroups(ns, a, b, c: untyped): untyped =
    all_permutations(ns, [
      @[a, b, c],
      @[a, b],
      @[a, c],
      @[b, c],
      @[a],
      @[b],
      @[c]
    ])

  # Video channel mapping consistency
  test "img/layout defChannelLayout consistency (subgroups of RGB)":
    all_ordinary_subgroups("Video", "R", "G", "B", "A")

  test "img/layout defChannelLayout consistency (subgroups of CMYe)":
    all_ordinary_subgroups("Video", "C", "M", "Ye", "A")

  test "img/layout defChannelLayout consistency (subgroups of HSV)":
    all_ordinary_subgroups("Video", "H", "S", "V", "A")

  test "img/layout defChannelLayout consistency (subgroups of YpCbCr)":
    all_ordinary_subgroups("Video", "Yp", "Cb", "Cr", "A")

  test "img/layout defChannelLayout consistency (subgroups of YCbCr)":
    all_ordinary_subgroups("Video", "Y", "Cb", "Cr", "A")


  # Print channel mapping consistency
  test "img/layout defChannelLayout consistency (subgroups of CMYeK)":
    all_ordinary_subgroups("Print", "C", "M", "Ye", "K")


  # Audio channel mapping consistency
  test "img/layout defChannelLayout consistency (subgroups of LeftRightLfe)":
    all_ordinary_subgroups("Audio", "Left", "Right", "Lfe")

  test "img/layout defChannelLayout consistency (subgroups of LfRfLbRbLfe)":
    all_ordinary_subgroups("Audio", "Lf", "Rf", "Lb", "Rb", "Lfe")

  template check_frame_type_consistency(be, acc, U: untyped): untyped =
    block:
      var x: FrameType(be, acc, U)
      check type(x) is FrameType(be, acc, U) and FrameType(be, acc, U) is type(x)

  template check_frame_type_consistency_for_each_access_policy(be, U: untyped): untyped =
    check_frame_type_consistency(be, "RO", U)
    check_frame_type_consistency(be, "WO", U)
    check_frame_type_consistency(be, "RW", U)
    check_frame_type_consistency(be, "ro", U)
    check_frame_type_consistency(be, "wo", U)
    check_frame_type_consistency(be, "rw", U)

  template check_frame_type_access_policy_readable(be, acc, U: untyped; isTrue: bool): untyped =
    block:
      var x: FrameType(be, acc, U)

      proc myProc(fr: ReadDataFrame) = discard

      check compiles((x.frame_data)) == isTrue
      check compiles((myProc(x))) == isTrue

  template check_frame_type_access_policy_writable(be, acc, U: untyped; isTrue: bool): untyped =
    block:
      var x: FrameType(be, acc, U)
      var buf: BackendType(be, U)

      proc myProc(fr: var WriteDataFrame) = discard

      check compiles((x.frame_data = buf)) == isTrue
      check compiles((myProc(x))) == isTrue

  test "dataframe FrameType consistency for default backend \"*\"":
    check_frame_type_consistency_for_each_access_policy("*", byte)

  test "dataframe FrameType access policy string \"RO\" is read-only":
    check_frame_type_access_policy_readable("*", "RO", byte, true)
    check_frame_type_access_policy_writable("*", "RO", byte, false)

  test "dataframe FrameType access policy string \"ro\" is read-only":
    check_frame_type_access_policy_readable("*", "ro", byte, true)
    check_frame_type_access_policy_writable("*", "ro", byte, false)

  test "dataframe FrameType access policy string \"R\" is read-only":
    check_frame_type_access_policy_readable("*", "R", byte, true)
    check_frame_type_access_policy_writable("*", "R", byte, false)

  test "dataframe FrameType access policy string \"r\" is read-only":
    check_frame_type_access_policy_readable("*", "r", byte, true)
    check_frame_type_access_policy_writable("*", "r", byte, false)

  test "dataframe FrameType access policy string \"WO\" is write-only":
    check_frame_type_access_policy_readable("*", "WO", byte, false)
    check_frame_type_access_policy_writable("*", "WO", byte, true)

  test "dataframe FrameType access policy string \"wo\" is write-only":
    check_frame_type_access_policy_readable("*", "wo", byte, false)
    check_frame_type_access_policy_writable("*", "wo", byte, true)

  test "dataframe FrameType access policy string \"W\" is write-only":
    check_frame_type_access_policy_readable("*", "W", byte, false)
    check_frame_type_access_policy_writable("*", "W", byte, true)

  test "dataframe FrameType access policy string \"w\" is write-only":
    check_frame_type_access_policy_readable("*", "w", byte, false)
    check_frame_type_access_policy_writable("*", "w", byte, true)

  test "dataframe FrameType access policy string \"RW\" is read-write":
    check_frame_type_access_policy_readable("*", "RW", byte, true)
    check_frame_type_access_policy_writable("*", "RW", byte, true)

  test "dataframe FrameType access policy string \"rw\" is read-write":
    check_frame_type_access_policy_readable("*", "rw", byte, true)
    check_frame_type_access_policy_writable("*", "rw", byte, true)

  test "dataframe FrameType access policy string \"WR\" is read-write":
    check_frame_type_access_policy_readable("*", "WR", byte, true)
    check_frame_type_access_policy_writable("*", "WR", byte, true)

  test "dataframe FrameType access policy string \"wr\" is read-write":
    check_frame_type_access_policy_readable("*", "wr", byte, true)
    check_frame_type_access_policy_writable("*", "wr", byte, true)

  test "dataframe initFrame":
    var mySeq = toSeq(1..75)
    var myFrame: FrameType("*", "rw", int)
    initFrame myFrame, DataPlanar, mySeq, 3, 5, 5

    check myFrame.frame_order == DataPlanar
    check backend_data_raw(myFrame.frame_data) == mySeq

  test "dataframe storage order rotation shape consistency":
    var mySeq = toSeq(1..75)
    var myFrame: FrameType("*", "rw", int)
    initFrame myFrame, DataPlanar, mySeq, 3, 5, 5

    var myInterleavedFrame = myFrame.interleaved
    check myInterleavedFrame.shape == myFrame.shape

  test "dataframe storage order rotation data consistency":
    var mySeq = toSeq(1..75)
    var myFrame: FrameType("*", "rw", int)
    initFrame myFrame, DataPlanar, mySeq, 3, 5, 5

    var myInterleavedFrame = myFrame.interleaved

    for i in 0..2:
      check myInterleavedFrame.channel(i).slice_data == myFrame.channel(i).slice_data

  template checkFrameSimple(myFrame: untyped): untyped =
    check myFrame.interleaved.shape == expect_shape[0..1]
    check myFrame.planar.shape == expect_shape[0..1]

    for i in 0..2:
      let
        data1 = myFrame.interleaved.channel(i).slice_data
        data2 = myFrame.planar.channel(i).slice_data
      check data1 == data2

  template checkFrameAgainst(myFrame, otherFrame: untyped): untyped =
    check myFrame.interleaved.shape == otherFrame.shape
    check myFrame.planar.shape == otherFrame.shape

    if myFrame.planar.shape == otherFrame.shape:
      for i in 0..<min(myFrame.channel_count, otherFrame.channel_count):
        let
          data1 = myFrame.interleaved.channel(i).slice_data
          data2 = myFrame.planar.channel(i).slice_data
          data3 = otherFrame.channel(i).slice_data
        check data1 == data2
        check data1 == data3

  test "dataframe image from picio":
    var myFrame: FrameType("*", "rw", byte)
    var myImgData: seq[byte]
    var h, w, ch: int

    picio_load_core3_file_by_type("test/sample.png", h, w, ch, myImgData)
    initFrame myFrame, DataInterleaved, myImgData, [h, w, ch]

    checkFrameSimple myFrame

  test "picture readPictureFile dataframe check":
    #var myImage: DynamicImageType("*", "rw", byte)
    let myImage = readPictureFile(byte, "*", "test/sample.png")

    checkFrameSimple myImage.data_frame

  test "picture writePicture/readPictureData dataframe check":
    #var myImage: DynamicImageType("*", "rw", byte)

    let myImage = readPictureFile(byte, "*", "test/sample.png")
    let coredata = myImage.writePicture(SO(format: PNG))
    
    #var myMirror: DynamicImageType("*", "rw", byte)
    let myMirror = readPictureData(byte, "*", coredata)
    
    checkFrameSimple myMirror.data_frame
    checkFrameAgainst myImage.data_frame, myMirror.data_frame

  test "dataframe channel mutator red/blue swap":
    var myImage = readPictureFile(byte, "*", "test/sample.bmp")
    let refImage = readPictureFile(byte, "*", "test/redbluereverse.bmp")
    var targetImage = initDynamicImageLike("*", "rw", byte, refImage)

    myImage.data_frame.initFrame(
      DataInterleaved,
      myImage.data_frame.channel(0),
      myImage.data_frame.channel(1),
      myImage.data_frame.channel(2)
    )

    echo "Channels in myImage ", myImage.data_frame.channel_count
    echo "Channels in refImage ", refImage.data_frame.channel_count

    checkFrameSimple myImage.data_frame

    let red = myImage.data_frame.channel(0)
    let green = myImage.data_frame.channel(1)
    let blue = myImage.data_frame.channel(2)

    targetImage.data_frame.channel(0, blue)
    targetImage.data_frame.channel(1, green)
    targetImage.data_frame.channel(2, red)

    check targetImage.writePicture("test/redbluereverse_test.bmp", SO(format: BMP))

    checkFrameAgainst targetImage.data_frame, refImage.data_frame

  test "dataframe channel mutator red/blue swap in-place":
    var myImage = readPictureFile(byte, "*", "test/sample.bmp")
    let refImage = readPictureFile(byte, "*", "test/redbluereverse.bmp")

    echo "Channels in myImage ", myImage.data_frame.channel_count
    echo "Channels in refImage ", refImage.data_frame.channel_count

    checkFrameSimple myImage.data_frame

    let red = myImage.data_frame.channel(0).slice_copy
    let blue = myImage.data_frame.channel(2)

    myImage.data_frame.channel(0, blue)
    myImage.data_frame.channel(2, red)

    check myImage.writePicture("test/redbluereverse_inplace_test.bmp", SO(format: BMP))

    checkFrameAgainst myImage.data_frame, refImage.data_frame


  #test "img initRawImageObject":
  #  var mySeq = toSeq(1..75)
  #  var img = initRawImageObject("am", mySeq, [5, 5])


  # 

#[
  template echo_props(name, pic: untyped): untyped =
    echo "Properties of '", name, "':"
    echo "  order: ", pic.colorspace.order
    echo "  colorspace:       ", pic.colorspace
    echo "  width:            ", pic.width
    echo "  height:           ", pic.height

  template read_verbose(name, T: untyped): untyped =
    block:
      let pic = readImage[T](name)
      echo_props name, pic
      pic

  test "IIO/base load test reference image (PNG)":
    testimg = readImage[byte]("test/sample.png")
    require_consistency testimg.data

  test "IIO/base getter width, extent, and dataShape consistency":
    check testimg.width == testimg.extent(1) and testimg.width == testimg.dataShape[1]

  test "IIO/base getter height, extent, and dataShape consistency":
    check testimg.height == testimg.extent(0) and testimg.height  == testimg.dataShape[0]

  #test "IIO/base interleaved to planar order":

  #test "IIO/base planar and interleaved width consistency":
  #  img = testimg.planar
  #  check pla

  test "IIO/base getter colorspace":
    check testimg.colorspace.name == "RGBA"

  test "IIO/base save BMP":
    check testimg.writeImage("test/samplepng-out2.bmp", SO(format: BMP))

  test "IIO/base load BMP":
    testimg = readImage[byte]("test/samplepng-out2.bmp")
    require_consistency testimg.data

  test "IIO/base save PNG":
    check testimg.writeImage("test/samplepng-out2.png", SO(format: PNG, stride: 0))

  test "IIO/base load PNG":
    testimg = readImage[byte]("test/samplepng-out2.png")
    require_consistency testimg.data

  test "IIO/base save JPEG":
    check testimg.writeImage("test/samplepng-out2.jpeg", SO(format: JPEG, quality: 100))

  test "IIO/base load JPEG":
    testimg = readImage[byte]("test/samplepng-out2.jpeg")
    require_consistency testimg.data

  test "IIO/base encode and decode BMP in-memory":
    let coredata = writeImage(testimg, SO(format: BMP))
    echo "    # Saved BMP size is ", formatFloat(coredata.len.float / 1024.0, precision = 5), "KB"
    let recovered = readImage[byte](coredata)
    check_consistency testimg.data, recovered.data

  test "IIO/base encode and decode PNG in-memory":
    let coredata = writeImage(testimg, SO(format: PNG, stride: 0))
    echo "    # Saved PNG size is ", formatFloat(coredata.len.float / 1024.0, precision = 5), "KB"
    let recovered = readImage[byte](coredata)
    check_consistency testimg.data, recovered.data

  test "IIO/base encode and decode JPEG in-memory":
    let coredata = writeImage(testimg, SO(format: JPEG, quality: 100))
    echo "    # Saved JPEG size is ", formatFloat(coredata.len.float / 1024.0, precision = 5), "KB"
    let recovered = readImage[byte](coredata)
    check_consistency testimg.data, recovered.data
]#

  #test "IIO/base encode and decode HDR in-memory":
  #  let coredata = writeImage(hdrpic, SO(format: HDR))
  #  echo "    # Saved HDR size is ", coredata.len.float / 1024.0, "KB"
  #  let recovered = coredata.picio_load_hdr_core
  #  check_consistency hdrpic, recovered


  #test "Image LDR I/O (User)":
  #  let mypic = read_verbose("test/sample.png", byte)

  #  echo "Write BMP from PNG: ",
  #    
  #  echo "Write PNG from PNG: ",
  #    mypic.writeImage("test/samplepng-out2.png", SO(format: PNG, stride: 0))
  #  echo "Write JPEG from PNG: ",
  #    mypic.writeImage("test/samplepng-out2.jpeg",
  #      SO(format: JPEG, quality: 100))

  #  let mypic2 = read_verbose("test/samplepng-out2.bmp", byte)

  #  echo "Write BMP from BMP: ",
  #    mypic2.writeImage("test/samplebmp-out2.bmp", SO(format: BMP))
  #  echo "Write PNG from BMP: ",
  #    mypic2.writeImage("test/samplebmp-out2.png", SO(format: PNG, stride: 0))
  #  echo "Write JPEG from BMP: ",
  #    mypic2.writeImage("test/samplebmp-out2.jpeg",
  #      SO(format: JPEG, quality: 100))

  #  let mypicjpeg = read_verbose("test/samplepng-out2.jpeg", byte)

  #  echo "Write BMP from JPEG: ",
  #    mypicjpeg.writeImage("test/samplejpeg-out.bmp", SO(format: BMP))
  #  echo "Write PNG from JPEG: ",
  #    mypicjpeg.writeImage("test/samplejpeg-out.png",
  #      SO(format: PNG, stride: 0))
  #  echo "Write JPEG from JPEG: ",
  #    mypicjpeg.writeImage("test/samplejpeg-out.jpeg",
  #      SO(format: JPEG, quality: 100))

  #test "Image I/O (Internal)":
  #  # Taken from the isMainModule tests in lerosi.nim
  #  # TODO: Add an automatic correctness verificiation which may account for
  #  # the drift in lossy compression methods (JPEG).
  #  #   TODO: Use a histogram and shape test as a first pass.
  #  echo "PNG Loaded Shape: ", testpic.shape

  #  echo "Write BMP from PNG: ",
  #    testpic.picio_save_core("test/samplepng-out.bmp", SO(format: BMP))
  #  echo "Write PNG from PNG: ",
  #    testpic.picio_save_core(
  #      "test/samplepng-out.png", SO(format: PNG, stride: 0))
  #  echo "Write JPEG from PNG: ",
  #    testpic.picio_save_core(
  #      "test/samplepng-out.jpeg", SO(format: JPEG, quality: 100))
  #  echo "Write HDR from PNG: ",
  #    picio_save_core(testpic.asType(cfloat) / 255.0,
  #      "test/samplepng-out.hdr", SO(format: HDR))

  #  let testpic2 = "test/samplepng-out.bmp".picio_load_core()
  #  echo "BMP Loaded Shape: ", testpic2.shape

  #  echo "Write BMP from BMP: ",
  #    testpic2.picio_save_core("test/samplebmp-out.bmp", SO(format: BMP))
  #  echo "Write PNG from BMP: ",
  #    testpic2.picio_save_core(
  #      "test/samplebmp-out.png", SO(format: PNG, stride: 0))
  #  echo "Write JPEG from BMP: ",
  #    testpic2.picio_save_core(
  #      "test/samplebmp-out.jpeg", SO(format: JPEG, quality: 100))
  #  echo "Write HDR from BMP: ",
  #    picio_save_core(testpic2.asType(cfloat) / 255.0,
  #      "test/samplebmp-out.hdr", SO(format: HDR))

  #  let testpicjpeg = "test/samplepng-out.jpeg".picio_load_core()
  #  echo "JPEG Loaded Shape: ", testpicjpeg.shape

  #  echo "Write BMP from JPEG: ",
  #    testpicjpeg.picio_save_core("test/samplejpeg-out.bmp", SO(format: BMP))
  #  echo "Write PNG from JPEG: ",
  #    testpicjpeg.picio_save_core(
  #      "test/samplejpeg-out.png", SO(format: PNG, stride: 0))
  #  echo "Write JPEG from JPEG: ",
  #    testpicjpeg.picio_save_core(
  #      "test/samplejpeg-out.jpeg", SO(format: JPEG, quality: 100))
  #  echo "Write HDR from JPEG: ",
  #    picio_save_core(testpicjpeg.asType(cfloat) / 255.0,
  #      "test/samplejpeg-out.hdr", SO(format: HDR))

  #  var testpichdr = "test/samplepng-out.hdr".picio_load_hdr_core()
  #  echo "HDR Loaded Shape: ", testpichdr.shape

  #  echo "Write HDR from HDR: ",
  #    testpichdr.picio_save_core("test/samplehdr-out.hdr", SO(format: HDR))

  #  echo "Scale for the rest of the formats"
  #  testpichdr *= 255.0

  #  echo "Write BMP from HDR: ",
  #    testpichdr.picio_save_core("test/samplehdr-out.bmp", SO(format: BMP))
  #  echo "Write PNG from HDR: ",
  #    testpichdr.picio_save_core(
  #      "test/samplehdr-out.png", SO(format: PNG, stride: 0))
  #  echo "Write JPEG from HDR: ",
  #    testpichdr.picio_save_core(
  #      "test/samplehdr-out.jpeg", SO(format: JPEG, quality: 100))

  #  var myhdrpic = "test/samplehdr-out.hdr".picio_load_hdr_core()
  #  echo "HDR Loaded Shape: ", myhdrpic.shape

  #  echo "Writing HDR to memory to read back."
  #  let hdrseq = myhdrpic.picio_save_core(SO(format: HDR))
  #  #echo hdrseq
  #  let myhdrpic2 = hdrseq.picio_load_hdr_core()
  #  assert myhdrpic == myhdrpic2
  #  echo "Success!"

  #  myhdrpic *= 255.0
  #  echo "Scale for the rest of the bitmap test"

  #  echo "Write BMP from second HDR: ",
  #    myhdrpic.picio_save_core("test/samplehdr2-out.bmp", SO(format: BMP))



  # TODO: Insert new tests.

  #test "Channels and channel layout properties":
  #  template doRGBAProcs(what: untyped): untyped =
  #    echo what, ".ChR = ", what.ChR, " and ", what, ".channel(R) = ", what.channel(ChIdR)
  #    echo what, ".ChG = ", what.ChG, " and ", what, ".channel(G) = ", what.channel(ChIdG)
  #    echo what, ".ChB = ", what.ChB, " and ", what, ".channel(B) = ", what.channel(ChIdB)
  #    echo what, ".ChA = ", what.ChA, " and ", what, ".channel(A) = ", what.channel(ChIdA)

  #  template doYCbCrProcs(what: untyped): untyped =
  #    echo what, ".ChY  = ", what.ChY,  " and ", what, ".channel(Y)  = ", what.channel(ChIdY)
  #    echo what, ".ChCb = ", what.ChCb, " and ", what, ".channel(Cb) = ", what.channel(ChIdCb)
  #    echo what, ".ChCr = ", what.ChCr, " and ", what, ".channel(Cr) = ", what.channel(ChIdCr)

  #  template doCmpChannelsTest(a, b: untyped): untyped =
  #    echo "cmpChannels(", a, ", ", b, ") = ", cmpChannels(a, b)

  #  let
  #    myLayouts = [
  #      ChLayoutRGBA.id, ChLayoutBGRA.id,
  #      ChLayoutYCbCr.id, ChLayoutYCrCb.id
  #    ]

  #  for i, layout in myLayouts:
  #    echo "Testing ", layout, ":"
  #    echo layout, ".len = ", layout.len
  #    echo layout, ".channels = ", layout.channels
  #    if i > 1: doYCbCrProcs(layout) else: doRGBAProcs(layout)

  #  doCmpChannelsTest(ChLayoutRGBA.id, ChLayoutRGBA.id)
  #  doCmpChannelsTest(ChLayoutRGBA.id, ChLayoutARGB.id)
  #  doCmpChannelsTest(ChLayoutRGBA.id, ChLayoutRGB.id)
  #  doCmpChannelsTest(ChLayoutRGBA.id, ChLayoutBGRA.id)
  #  doCmpChannelsTest(ChLayoutRGBA.id, ChLayoutABGR.id)
  #  doCmpChannelsTest(ChLayoutRGBA.id, ChLayoutBGR.id)

  #test "Copy channels":
  #  let planarpic = readImage[byte]("test/sample.bmp").planar
  #  let interleavedpic = planarpic.interleaved

  #  var planaroutpic = newDynamicLayoutImage[byte](planarpic.width, planarpic.height, ChLayoutBGR.id).planar
  #  var interleavedoutpic = planaroutpic.interleaved

  #  planarpic.copyChannelsTo(planaroutpic)
  #  interleavedpic.copyChannelsTo(interleavedoutpic)

  #  check planaroutpic.writeImage("test/redbluereverse-planar2planar.bmp", SO(format: BMP))
  #  check interleavedoutpic.writeImage("test/redbluereverse-interleaved2interleaved.bmp", SO(format: BMP))

  #  planarpic.copyChannelsTo(interleavedoutpic)
  #  interleavedpic.copyChannelsTo(planaroutpic)

  #  check planaroutpic.writeImage("test/redbluereverse-interleaved2planar.bmp", SO(format: BMP))
  #  check interleavedoutpic.writeImage("test/redbluereverse-planar2interleaved.bmp", SO(format: BMP))

    
