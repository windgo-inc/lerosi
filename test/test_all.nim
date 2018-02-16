import system, strutils, unittest, macros, math, future
import typetraits

import lerosi
import lerosi/iio_core # we test the internals of IIO from here
import lerosi/img

# Nicer alias for save options.
type
  SO = SaveOptions

const testChannelSpaceIds = [
  VideoChSpaceA,         # VideoA
  VideoChSpaceY,         # VideoY
  VideoChSpaceYp,        # VideoYp
  VideoChSpaceRGB,       # VideoRGB
  VideoChSpaceCMYe,      # VideoCMYe
  VideoChSpaceHSV,       # VideoHSV
  VideoChSpaceYCbCr,     # VideoYCbCr
  VideoChSpaceYpCbCr,    # VideoYpCbCr
  PrintChSpaceK,         # PrintK
  PrintChSpaceCMYeK,     # PrintCMYeK
  AudioChSpaceLfe,       # AudioLfe
  AudioChSpaceMono,      # AudioMono
  AudioChSpaceLeftRight, # AudioLeftRight
  AudioChSpaceLfRfLbRb   # AudioLfRfLbRb
]

suite "LERoSI Unit Tests":
  var
    # iio_core globals
    testpic_initialized = false
    testpic: AmBackendCpu[byte]
    hdrpic: AmBackendCpu[cfloat]
    expect_shape: MetadataArray

    # IIO/base globals
    #testimg: StaticOrderFrame[byte, ChannelSpaceTypeAny, DataInterleaved]

    #plnrimg: StaticOrderFrame[byte, ChannelSpaceTypeAny, DataPlanar]
    #ilvdimg: StaticOrderFrame[byte, ChannelSpaceTypeAny, DataInterleaved]
    #dynimg: DynamicOrderFrame[byte, ChannelSpaceTypeAny]

  test "iio_core load test reference image (PNG)":
    try:
      testpic = imageio_load_core("test/sample.png")
      hdrpic.backend_source(testpic, x => x.cfloat / 255.0)
      expect_shape = testpic.backend_data_shape
      testpic_initialized = true
    except:
      testpic_initialized = false
      raise

  template require_equal_extent[T; U](pic: AmBackendCpu[T], expectpic: AmBackendCpu[U]): untyped =
    require pic.backend_data_shape[0..1] == expectpic.backend_data_shape[0..1]

  template require_equal_extent[T](pic: AmBackendCpu[T]): untyped =
    require pic.backend_data_shape[0..1] == testpic.backend_data_shape[0..1]

  template check_equal_extent[T; U](pic: AmBackendCpu[T], expectpic: AmBackendCpu[U]): untyped =
    check pic.backend_data_shape[0..1] == expectpic.backend_data_shape[0..1]

  template check_equal_extent[T](pic: AmBackendCpu[T]): untyped =
    check pic.backend_data_shape[0..1] == testpic.backend_data_shape[0..1]

  template require_consistency[T; U](pic: AmBackendCpu[T], expectpic: AmBackendCpu[U]): untyped =
    require_equal_extent pic, expectpic
    # TODO: Add a histogram check

  template require_consistency[T](pic: AmBackendCpu[T]): untyped =
    require_consistency pic, testpic

  template check_consistency[T; U](pic: AmBackendCpu[T], expectpic: AmBackendCpu[U]): untyped =
    check_equal_extent pic, expectpic

  template check_consistency[T](pic: AmBackendCpu[T]): untyped =
    check_consistency pic, testpic

  #template test_jpeg_decades(fn: untyped): untyped =
  #  template gn(qual: int): untyped =
  #    fn(qual);   fn(qual-1); fn(qual-2); fn(qual-3); fn(qual-4);
  #    fn(qual-5); fn(qual-6); fn(qual-7); fn(qual-8); fn(qual-9);

  #  gn(100); gn(90); gn(80);# gn(70);
  #  #gn(60);  gn(50); gn(40); gn(30);

  test "iio_core obtained test image":
    require testpic_initialized
  
  test "Backend extent equality":
    require(testpic.backend_data_shape == expect_shape)

  test "Backend extent identity":
    require_equal_extent testpic

  test "iio_core save BMP":
    require testpic.imageio_save_core(
      "test/samplepng-out.bmp",
      SO(format: BMP))

  test "iio_core save PNG":
    require testpic.imageio_save_core(
      "test/samplepng-out.png",
      SO(format: PNG, stride: 0))

  test "iio_core save JPEG":
    require testpic.imageio_save_core(
      "test/samplepng-out.jpeg",
      SO(format: JPEG, quality: 100))

  # We want to prevent template explosion; this is a big part of
  # why the high level interface should be preferred.
  proc do_write_jpeg_test[T](pic: AmBackendCpu[T], qual: int): bool =
    result = testpic.imageio_save_core(
      "test/samplepng-out.q" & $qual & ".jpeg",
      SO(format: JPEG, quality: qual))

  test "iio_core save JPEG quality parameter coverage":
    var n: int = 0
    for qual in countdown(100, 10):
      check do_write_jpeg_test(testpic, qual)
      inc n
    echo "    # Quality variations saved: ", n

  test "iio_core save HDR":
    check imageio_save_core(hdrpic,
      "test/samplepng-out.hdr",
      SO(format: HDR))

  # Loading

  test "iio_core load BMP":
    let inpic = imageio_load_core("test/samplepng-out.bmp")
    check_consistency inpic
    
  test "iio_core load PNG":
    let inpic = imageio_load_core("test/samplepng-out.png")
    check_consistency inpic

  test "iio_core load JPEG":
    let inpic = imageio_load_core("test/samplepng-out.jpeg")
    check_consistency inpic

  # We want to prevent template explosion; this is a big part of
  # why the high level interface should be preferred.
  proc do_read_jpeg_test(qual: int): AmBackendCpu[byte] =
    result = imageio_load_core("test/samplepng-out.q" & $qual & ".jpeg")

  # Wrapping imageio_load_core template
  #proc do_read_res_test(res: string): AmBackendCpu[byte] =
  #  result = imageio_loadstring_core(res)


  test "iio_core load JPEG quality parameter coverage":
    var n: int = 0
    for qual in countdown(100, 10):
      check_consistency do_read_jpeg_test(qual)
      inc n
    echo "    # Quality variations loaded: ", n

  test "iio_core load HDR":
    let inpic = imageio_load_hdr_core("test/samplepng-out.hdr")
    check_consistency inpic, hdrpic

  test "iio_core encode and decode BMP in-memory":
    let coredata = imageio_savestring_core(testpic, SO(format: BMP))
    echo "    # Saved BMP size is ", formatFloat(coredata.len.float / 1024.0, precision = 5), "KB"
    let recovered = coredata.imageio_loadstring_core
    check_consistency testpic, recovered

  test "iio_core encode and decode PNG in-memory":
    let coredata = imageio_savestring_core(testpic, SO(format: PNG, stride: 0))
    echo "    # Saved PNG size is ", formatFloat(coredata.len.float / 1024.0, precision = 5), "KB"
    let recovered = coredata.imageio_loadstring_core
    check_consistency testpic, recovered

  test "iio_core encode and decode JPEG in-memory":
    let coredata = imageio_savestring_core(testpic, SO(format: JPEG, quality: 100))
    echo "    # Saved JPEG size is ", formatFloat(coredata.len.float / 1024.0, precision = 5), "KB"
    let recovered = coredata.imageio_loadstring_core
    check_consistency testpic, recovered

  test "iio_core encode and decode HDR in-memory":
    let coredata = imageio_savestring_core(hdrpic, SO(format: HDR))
    echo "    # Saved HDR size is ", formatFloat(coredata.len.float / 1024.0, precision = 5), "KB"
    let recovered = coredata.imageio_loadstring_hdr_core
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

  test "img defChannelLayout: eagerCompile works":
    #template print_channel_layout_t(name, mapping: untyped): untyped =
    #  echo "    # ", name, " ", mapping.possibleChannelSpaces
    #  #echo "    # ", name
    #  #echo "    #    channelspace: ", layout.channelspace
    #  #echo "    #    mapping:      ", layout.mapping

    #macro print_channel_layout(layout: untyped): untyped =
    #  let name = toStrLit(layout)
    #  result = getAst(print_channel_layout_t(name, layout))

    template print_channel_layout(layout: untyped): untyped =
      echo "    # ", layout.channelspace.name, " ", layout.mapping.possibleChannelSpaces

    template test_channel_layouts(stage: string): untyped = 
      echo "    # (!) Testing channel layout generator ", stage
      echo "    # Test static channel layout generator (alpha)"
      print_channel_layout(defChannelLayout"VideoA")
      echo "    # Test static channel layout generator (RGB)"
      print_channel_layout(defChannelLayout"VideoRGBA")
      print_channel_layout(defChannelLayout"VideoBGRA")
      print_channel_layout(defChannelLayout"VideoARGB")
      print_channel_layout(defChannelLayout"VideoABGR")
      print_channel_layout(defChannelLayout"VideoRGB")
      print_channel_layout(defChannelLayout"VideoBGR")
      echo "    # Test static channel layout generator (luma-chrominance)"
      print_channel_layout(defChannelLayout"VideoYp")
      print_channel_layout(defChannelLayout"VideoY")
      print_channel_layout(defChannelLayout"VideoCbCrYp")
      print_channel_layout(defChannelLayout"VideoCrCbYp")
      print_channel_layout(defChannelLayout"VideoYpCbCr")
      print_channel_layout(defChannelLayout"VideoYpCrCb")
      print_channel_layout(defChannelLayout"VideoCbCr")
      print_channel_layout(defChannelLayout"VideoCrCb")
      print_channel_layout(defChannelLayout"VideoYCbCr")
      print_channel_layout(defChannelLayout"VideoYCrCb")
      print_channel_layout(defChannelLayout"VideoCbCrY")
      print_channel_layout(defChannelLayout"VideoCrCbY")
      echo "    # Test static channel layout generator (CMYe print and CMYe video)"
      print_channel_layout(defChannelLayout"PrintK")
      print_channel_layout(defChannelLayout"PrintKCMYe")
      print_channel_layout(defChannelLayout"PrintCMYeK")
      print_channel_layout(defChannelLayout"PrintCMYe")
      print_channel_layout(defChannelLayout"VideoCMYeA")
      print_channel_layout(defChannelLayout"VideoCMYe")

    test_channel_layouts"with pragma {.eagerCompile.}"

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
  #  let recovered = coredata.imageio_load_hdr_core
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
  #    testpic.imageio_save_core("test/samplepng-out.bmp", SO(format: BMP))
  #  echo "Write PNG from PNG: ",
  #    testpic.imageio_save_core(
  #      "test/samplepng-out.png", SO(format: PNG, stride: 0))
  #  echo "Write JPEG from PNG: ",
  #    testpic.imageio_save_core(
  #      "test/samplepng-out.jpeg", SO(format: JPEG, quality: 100))
  #  echo "Write HDR from PNG: ",
  #    imageio_save_core(testpic.asType(cfloat) / 255.0,
  #      "test/samplepng-out.hdr", SO(format: HDR))

  #  let testpic2 = "test/samplepng-out.bmp".imageio_load_core()
  #  echo "BMP Loaded Shape: ", testpic2.shape

  #  echo "Write BMP from BMP: ",
  #    testpic2.imageio_save_core("test/samplebmp-out.bmp", SO(format: BMP))
  #  echo "Write PNG from BMP: ",
  #    testpic2.imageio_save_core(
  #      "test/samplebmp-out.png", SO(format: PNG, stride: 0))
  #  echo "Write JPEG from BMP: ",
  #    testpic2.imageio_save_core(
  #      "test/samplebmp-out.jpeg", SO(format: JPEG, quality: 100))
  #  echo "Write HDR from BMP: ",
  #    imageio_save_core(testpic2.asType(cfloat) / 255.0,
  #      "test/samplebmp-out.hdr", SO(format: HDR))

  #  let testpicjpeg = "test/samplepng-out.jpeg".imageio_load_core()
  #  echo "JPEG Loaded Shape: ", testpicjpeg.shape

  #  echo "Write BMP from JPEG: ",
  #    testpicjpeg.imageio_save_core("test/samplejpeg-out.bmp", SO(format: BMP))
  #  echo "Write PNG from JPEG: ",
  #    testpicjpeg.imageio_save_core(
  #      "test/samplejpeg-out.png", SO(format: PNG, stride: 0))
  #  echo "Write JPEG from JPEG: ",
  #    testpicjpeg.imageio_save_core(
  #      "test/samplejpeg-out.jpeg", SO(format: JPEG, quality: 100))
  #  echo "Write HDR from JPEG: ",
  #    imageio_save_core(testpicjpeg.asType(cfloat) / 255.0,
  #      "test/samplejpeg-out.hdr", SO(format: HDR))

  #  var testpichdr = "test/samplepng-out.hdr".imageio_load_hdr_core()
  #  echo "HDR Loaded Shape: ", testpichdr.shape

  #  echo "Write HDR from HDR: ",
  #    testpichdr.imageio_save_core("test/samplehdr-out.hdr", SO(format: HDR))

  #  echo "Scale for the rest of the formats"
  #  testpichdr *= 255.0

  #  echo "Write BMP from HDR: ",
  #    testpichdr.imageio_save_core("test/samplehdr-out.bmp", SO(format: BMP))
  #  echo "Write PNG from HDR: ",
  #    testpichdr.imageio_save_core(
  #      "test/samplehdr-out.png", SO(format: PNG, stride: 0))
  #  echo "Write JPEG from HDR: ",
  #    testpichdr.imageio_save_core(
  #      "test/samplehdr-out.jpeg", SO(format: JPEG, quality: 100))

  #  var myhdrpic = "test/samplehdr-out.hdr".imageio_load_hdr_core()
  #  echo "HDR Loaded Shape: ", myhdrpic.shape

  #  echo "Writing HDR to memory to read back."
  #  let hdrseq = myhdrpic.imageio_save_core(SO(format: HDR))
  #  #echo hdrseq
  #  let myhdrpic2 = hdrseq.imageio_load_hdr_core()
  #  assert myhdrpic == myhdrpic2
  #  echo "Success!"

  #  myhdrpic *= 255.0
  #  echo "Scale for the rest of the bitmap test"

  #  echo "Write BMP from second HDR: ",
  #    myhdrpic.imageio_save_core("test/samplehdr2-out.bmp", SO(format: BMP))



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

    
