import system, strutils, unittest, macros, math
import typetraits

import lerosi
import lerosi/img_permute
import lerosi/iio_core # we test the internals of IIO from here
#import lerosi/img

# Nicer alias for save options.
type
  SO = SaveOptions

#const testColorSpaceIds = [
#  ColorSpaceIdA,
#  ColorSpaceIdY,
#  ColorSpaceIdYA,
#  ColorSpaceIdYp,
#  ColorSpaceIdYpA,
#  ColorSpaceIdYCbCr,
#  ColorSpaceIdYCbCrA,
#  ColorSpaceIdYpCbCr,
#  ColorSpaceIdYpCbCrA,
#  ColorSpaceIdRGB,
#  ColorSpaceIdRGBA,
#  ColorSpaceIdHSV,
#  ColorSpaceIdHSVA,
#  ColorSpaceIdCMYe,
#  ColorSpaceIdCMYeA
#]

suite "LERoSI Unit Tests":
  var
    # IIO/core globals
    testpic_initialized = false
    testpic: Tensor[byte]
    hdrpic: Tensor[cfloat]
    expect_shape: MetadataArray

    # IIO/base globals
    #testimg: StaticOrderFrame[byte, ColorSpaceTypeAny, DataInterleaved]

    #plnrimg: StaticOrderFrame[byte, ColorSpaceTypeAny, DataPlanar]
    #ilvdimg: StaticOrderFrame[byte, ColorSpaceTypeAny, DataInterleaved]
    #dynimg: DynamicOrderFrame[byte, ColorSpaceTypeAny]

  test "IIO/core load test reference image (PNG)":
    try:
      testpic = imageio_load_core("test/sample.png")
      hdrpic = testpic.asType(cfloat) / 255.0
      expect_shape = testpic.shape
      testpic_initialized = true
    except:
      testpic_initialized = false
      raise

  template require_equal_extent[T; U](pic: Tensor[T], expectpic: Tensor[U]): untyped =
    require pic.shape[0..1] == expectpic.shape[0..1]

  template require_equal_extent[T](pic: Tensor[T]): untyped =
    require pic.shape[0..1] == testpic.shape[0..1]

  template check_equal_extent[T; U](pic: Tensor[T], expectpic: Tensor[U]): untyped =
    check pic.shape[0..1] == expectpic.shape[0..1]

  template check_equal_extent[T](pic: Tensor[T]): untyped =
    check pic.shape[0..1] == testpic.shape[0..1]

  template require_consistency[T; U](pic: Tensor[T], expectpic: Tensor[U]): untyped =
    require_equal_extent pic, expectpic
    # TODO: Add a histogram check

  template require_consistency[T](pic: Tensor[T]): untyped =
    require_consistency pic, testpic

  template check_consistency[T; U](pic: Tensor[T], expectpic: Tensor[U]): untyped =
    check_equal_extent pic, expectpic

  template check_consistency[T](pic: Tensor[T]): untyped =
    check_consistency pic, testpic

  #template test_jpeg_decades(fn: untyped): untyped =
  #  template gn(qual: int): untyped =
  #    fn(qual);   fn(qual-1); fn(qual-2); fn(qual-3); fn(qual-4);
  #    fn(qual-5); fn(qual-6); fn(qual-7); fn(qual-8); fn(qual-9);

  #  gn(100); gn(90); gn(80);# gn(70);
  #  #gn(60);  gn(50); gn(40); gn(30);

  test "IIO obtained test image":
    require testpic_initialized
  
  test "Tensor shape equality":
    require(testpic.shape == expect_shape)

  test "Tensor image extent equality":
    require_equal_extent testpic

  test "IIO/core save BMP":
    require testpic.imageio_save_core(
      "test/samplepng-out.bmp",
      SO(format: BMP))

  test "IIO/core save PNG":
    require testpic.imageio_save_core(
      "test/samplepng-out.png",
      SO(format: PNG, stride: 0))

  test "IIO/core save JPEG":
    require testpic.imageio_save_core(
      "test/samplepng-out.jpeg",
      SO(format: JPEG, quality: 100))

  # We want to prevent template explosion; this is a big part of
  # why the high level interface should be preferred.
  proc do_write_jpeg_test[T](pic: Tensor[T], qual: int): bool =
    result = testpic.imageio_save_core(
      "test/samplepng-out.q" & $qual & ".jpeg",
      SO(format: JPEG, quality: qual))

  test "IIO/core save JPEG quality parameter coverage":
    for qual in countdown(100, 20):
      check do_write_jpeg_test(testpic, qual)

  test "IIO/core save HDR":
    check imageio_save_core(hdrpic,
      "test/samplepng-out.hdr",
      SO(format: HDR))

  # Loading

  test "IIO/core load BMP":
    let inpic = imageio_load_core("test/samplepng-out.bmp")
    check_consistency inpic
    
  test "IIO/core load PNG":
    let inpic = imageio_load_core("test/samplepng-out.png")
    check_consistency inpic

  test "IIO/core load JPEG":
    let inpic = imageio_load_core("test/samplepng-out.jpeg")
    check_consistency inpic

  # We want to prevent template explosion; this is a big part of
  # why the high level interface should be preferred.
  proc do_read_jpeg_test(qual: int): Tensor[byte] =
    result = imageio_load_core("test/samplepng-out.q" & $qual & ".jpeg")

  # Wrapping imageio_load_core template
  proc do_read_res_test(res: seq[byte]): Tensor[byte] =
    result = imageio_load_core(res)


  test "IIO/core load JPEG quality parameter coverage":
    for qual in countdown(100, 80):
      check_consistency do_read_jpeg_test(qual)

  test "IIO/core load HDR":
    let inpic = imageio_load_hdr_core("test/samplepng-out.hdr")
    check_consistency inpic, hdrpic

  test "IIO/core encode and decode BMP in-memory":
    let coredata = imageio_save_core(testpic, SO(format: BMP))
    echo "    # Saved BMP size is ", formatFloat(coredata.len.float / 1024.0, precision = 5), "KB"
    let recovered = coredata.do_read_res_test
    check_consistency testpic, recovered

  test "IIO/core encode and decode PNG in-memory":
    let coredata = imageio_save_core(testpic, SO(format: PNG, stride: 0))
    echo "    # Saved PNG size is ", formatFloat(coredata.len.float / 1024.0, precision = 5), "KB"
    let recovered = coredata.do_read_res_test
    check_consistency testpic, recovered

  test "IIO/core encode and decode JPEG in-memory":
    let coredata = imageio_save_core(testpic, SO(format: JPEG, quality: 100))
    echo "    # Saved JPEG size is ", formatFloat(coredata.len.float / 1024.0, precision = 5), "KB"
    let recovered = coredata.do_read_res_test
    check_consistency testpic, recovered

  test "IIO/core encode and decode HDR in-memory":
    let coredata = imageio_save_core(hdrpic, SO(format: HDR))
    echo "    # Saved HDR size is ", formatFloat(coredata.len.float / 1024.0, precision = 5), "KB"
    let recovered = coredata.imageio_load_hdr_core
    check_consistency hdrpic, recovered

  test "img/permute shift data order explicit arity correctness":
    let plnrpic = rotate_plnr(testpic, 3)
    check plnrpic.shape[1..2] == testpic.shape[0..1]
    for i in 0..plnrpic.shape[0]-1:
      check plnrpic[i, _].squeeze == testpic[_, _, i].squeeze
    let ilvdpic = rotate_ilvd(plnrpic, 3)
    check ilvdpic.shape == testpic.shape
    check ilvdpic == testpic

  test "img/permute shift data order implicit arity correctness":
    let plnrpic = rotate_plnr(testpic)
    check plnrpic.shape[1..2] == testpic.shape[0..1]
    check plnrpic[0, _].squeeze == testpic[_, _, 0].squeeze
    let ilvdpic = rotate_ilvd(plnrpic)
    for i in 0..plnrpic.shape[0]-1:
      check plnrpic[i, _].squeeze == testpic[_, _, i].squeeze

#[
  template onEachColorspaceType(fn: untyped): untyped =
    fn(ColorSpaceTypeA)
    fn(ColorSpaceTypeY)
    fn(ColorSpaceTypeYA)
    fn(ColorSpaceTypeYp)
    fn(ColorSpaceTypeYpA)
    fn(ColorSpaceTypeYCbCr)
    fn(ColorSpaceTypeYCbCrA)
    fn(ColorSpaceTypeYpCbCr)
    fn(ColorSpaceTypeYpCbCrA)
    fn(ColorSpaceTypeRGB)
    fn(ColorSpaceTypeRGBA)
    fn(ColorSpaceTypeHSV)
    fn(ColorSpaceTypeHSVA)
    fn(ColorSpaceTypeCMYe)
    fn(ColorSpaceTypeCMYeA)

  template onEachColorspaceId(fn: untyped): untyped =
    fn(ColorSpaceIdA)
    fn(ColorSpaceIdY)
    fn(ColorSpaceIdYA)
    fn(ColorSpaceIdYp)
    fn(ColorSpaceIdYpA)
    fn(ColorSpaceIdYCbCr)
    fn(ColorSpaceIdYCbCrA)
    fn(ColorSpaceIdYpCbCr)
    fn(ColorSpaceIdYpCbCrA)
    fn(ColorSpaceIdRGB)
    fn(ColorSpaceIdRGBA)
    fn(ColorSpaceIdHSV)
    fn(ColorSpaceIdHSVA)
    fn(ColorSpaceIdCMYe)
    fn(ColorSpaceIdCMYeA)

  template lengthCheck(cspace: untyped): untyped =
    const cslen = colorspace_len(cspace)
    const csorder = colorspace_order(cspace)
    check csorder.len == cslen

  template runTimeLengthCheck(cspace: untyped): untyped =
    let cslen = colorspace_len(cspace)
    let csorder = colorspace_order(cspace)
    check csorder.len == cslen

  template orderCheck(cspace: untyped): untyped =
    const csorder = colorspace_order(cspace)
    const cschans = colorspace_channels(cspace)

    var n: int = 0
    for ch in cschans:
      inc n
      check csorder[colorspace_order(cspace, ch)] == ch

    check n == csorder.len
    for i, o in csorder:
      check i == colorspace_order(cspace, o)

  template runTimeOrderCheck(cspace: untyped): untyped =
    let csorder = colorspace_order(cspace)
    let cschans = colorspace_channels(cspace)

    var n: int = 0
    for ch in cschans:
      inc n
      check csorder[colorspace_order(cspace, ch)] == ch

    check n == csorder.len
    for i, o in csorder:
      check i == colorspace_order(cspace, o)

  template nameCheck(cspace: untyped): untyped =
    const name = cspace.colorspace_name
    const cspaceId = cspace.colorspace_id
    const nameToId = name.colorspace_id
    check cspaceId == nameToId

  template runTimeNameCheck(cspace: untyped): untyped =
    let name = cspace.colorspace_name
    let nameToId = name.colorspace_id
    check cspace == nameToId

  test "ColorSpaceDB ColorSpaceType* length consistency compile-time check":
    onEachColorspaceType(lengthCheck)

  test "ColorSpaceDB ColorSpaceType* order consistency compile-time check":
    onEachColorspaceType(orderCheck)

  test "ColorSpaceDB ColorSpace length consistency compile-time check":
    onEachColorspaceId(lengthCheck)

  test "ColorSpaceDB ColorSpace length consistency run-time check":
    for id in testColorSpaceIds: runTimeLengthCheck(id)

  test "ColorSpaceDB ColorSpace order consistency compile-time check":
    onEachColorspaceId(orderCheck)

  test "ColorSpaceDB ColorSpace order consistency run-time check":
    for id in testColorSpaceIds: runTimeOrderCheck(id)

  test "ColorSpaceDB ColorSpace to/from string compile-time naming consistency":
    onEachColorspaceType(nameCheck)

  test "ColorSpaceDB ColorSpace to/from string run-time naming consistency":
    for id in testColorSpaceIds: runTimeNameCheck(id)

  template echo_props(name, pic: untyped): untyped =
    echo "Properties of '", name, "':"
    echo "  colorspace_order: ", pic.colorspace.colorspace_order
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
    check testimg.colorspace.colorspace_name == "RGBA"

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
  #    echo what, ".ChR = ", what.ChR, " and ", what, ".channel(ChIdR) = ", what.channel(ChIdR)
  #    echo what, ".ChG = ", what.ChG, " and ", what, ".channel(ChIdG) = ", what.channel(ChIdG)
  #    echo what, ".ChB = ", what.ChB, " and ", what, ".channel(ChIdB) = ", what.channel(ChIdB)
  #    echo what, ".ChA = ", what.ChA, " and ", what, ".channel(ChIdA) = ", what.channel(ChIdA)

  #  template doYCbCrProcs(what: untyped): untyped =
  #    echo what, ".ChY  = ", what.ChY,  " and ", what, ".channel(ChIdY)  = ", what.channel(ChIdY)
  #    echo what, ".ChCb = ", what.ChCb, " and ", what, ".channel(ChIdCb) = ", what.channel(ChIdCb)
  #    echo what, ".ChCr = ", what.ChCr, " and ", what, ".channel(ChIdCr) = ", what.channel(ChIdCr)

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

    
