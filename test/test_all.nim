import system, strutils, unittest, macros, math
import typetraits

import lerosi
import lerosi/iio_core # we test the internals of IIO from here

# Nicer alias for save options.
type
  SO = SaveOptions


suite "LERoSI Unit Tests":
  var
    testpic_initialized = false
    testpic: Tensor[byte]
    hdrpic: Tensor[cfloat]
    expect_shape: MetadataArray

  test "IIO load test reference image (PNG) core implementation":
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

  template require_consistency[T](pic: Tensor[T]): untyped =
    require_consistency pic, testpic

  template check_consistency[T; U](pic: Tensor[T], expectpic: Tensor[U]): untyped =
    check_equal_extent pic, expectpic

  template check_consistency[T](pic: Tensor[T]): untyped =
    check_consistency pic, testpic

  template test_jpeg_decades(fn: untyped): untyped =
    template gn(qual: int): untyped =
      fn(qual);   fn(qual-1); fn(qual-2); fn(qual-3); fn(qual-4);
      fn(qual-5); fn(qual-6); fn(qual-7); fn(qual-8); fn(qual-9);

    gn(100); gn(90); gn(80); gn(70);
    gn(60);  gn(50); gn(40); gn(30);

  test "IIO obtained test image":
    require testpic_initialized
  
  test "Tensor shape equality":
    require(testpic.shape == expect_shape)

  test "Tensor image extent equality":
    require_equal_extent testpic

  test "IIO save BMP core implementation":
    require testpic.imageio_save_core(
      "test/samplepng-out.bmp",
      SO(format: BMP))

  test "IIO save PNG core implementation":
    require testpic.imageio_save_core(
      "test/samplepng-out.png",
      SO(format: PNG, stride: 0))

  test "IIO save JPEG core implementation":
    require testpic.imageio_save_core(
      "test/samplepng-out.jpeg",
      SO(format: JPEG, quality: 100))

  # We want to prevent template explosion; this is a big part of
  # why the high level interface should be preferred.
  proc do_write_jpeg_test[T](pic: Tensor[T], qual: int): bool =
    result = testpic.imageio_save_core(
      "test/samplepng-out.q" & $qual & ".jpeg",
      SO(format: JPEG, quality: qual))

  template jpeg_write_quality_test(qual: int): untyped =
    test "IIO save JPEG(quality=" & $qual & ") core implementation":
      check do_write_jpeg_test(testpic, qual)
  
  test_jpeg_decades(jpeg_write_quality_test)

  test "IIO save HDR core implementation":
    check imageio_save_core(hdrpic,
      "test/samplepng-out.hdr",
      SO(format: HDR))

  # Loading

  test "IIO load BMP core implementation":
    let inpic = imageio_load_core("test/samplepng-out.bmp")
    check_consistency inpic
    
  test "IIO load PNG core implementation":
    let inpic = imageio_load_core("test/samplepng-out.png")
    check_consistency inpic

  test "IIO load JPEG core implementation":
    let inpic = imageio_load_core("test/samplepng-out.jpeg")
    check_consistency inpic

  # We want to prevent template explosion; this is a big part of
  # why the high level interface should be preferred.
  proc do_read_jpeg_test(qual: int): Tensor[byte] =
    result = imageio_load_core("test/samplepng-out.q" & $qual & ".jpeg")

  # Wrapping imageio_load_core template
  proc do_read_res_test(res: seq[byte]): Tensor[byte] =
    result = imageio_load_core(res)


  template jpeg_read_quality_test(qual: int): untyped =
    test "IIO load JPEG(quality=" & $qual & ") core implementation":
      let inpic = do_read_jpeg_test(qual)
      check_consistency inpic
  
  test_jpeg_decades(jpeg_read_quality_test)

  test "IIO load HDR core implementation":
    let inpic = imageio_load_hdr_core("test/samplepng-out.hdr")
    check_consistency inpic, hdrpic

  test "IIO encode/decode BMP in-memory core implementation":
    let coredata = imageio_save_core(testpic, SO(format: BMP))
    echo "Saved BMP size is ", coredata.len.float / 1024.0, "KB"
    let recovered = coredata.do_read_res_test
    check_consistency testpic, recovered

  test "IIO encode/decode PNG in-memory core implementation":
    let coredata = imageio_save_core(testpic, SO(format: PNG, stride: 0))
    echo "Saved PNG size is ", coredata.len.float / 1024.0, "KB"
    let recovered = coredata.do_read_res_test
    check_consistency testpic, recovered

  test "IIO encode/decode JPEG in-memory core implementation":
    let coredata = imageio_save_core(testpic, SO(format: JPEG, quality: 100))
    echo "Saved JPEG size is ", coredata.len.float / 1024.0, "KB"
    let recovered = coredata.do_read_res_test
    check_consistency testpic, recovered

  test "IIO encode/decode HDR in-memory core implementation":
    let coredata = imageio_save_core(hdrpic, SO(format: HDR))
    echo "Saved HDR size is ", coredata.len.float / 1024.0, "KB"
    let recovered = coredata.imageio_load_hdr_core
    check_consistency hdrpic, recovered


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

  #test "Image LDR I/O (User)":
  #  let mypic = readImage[byte]("test/sample.png")
  #  echo "Properties of 'test/sample.png':"
  #  echo "  storage_order: ", mypic.storage_order
  #  echo "  colorspace:    ", mypic.colorspace
  #  echo "  width:         ", mypic.width
  #  echo "  height:        ", mypic.height

  #  echo "Write BMP from PNG: ",
  #    mypic.writeImage("test/samplepng-out.bmp", SO(format: BMP))
  #  echo "Write PNG from PNG: ",
  #    mypic.writeImage("test/samplepng-out.png", SO(format: PNG, stride: 0))
  #  echo "Write JPEG from PNG: ",
  #    mypic.writeImage("test/samplepng-out.jpeg",
  #      SO(format: JPEG, quality: 100))

  #  let mypic2 = readImage[byte]("test/samplepng-out.bmp")
  #  echo "Properties of 'test/samplepng-out.bmp':"
  #  echo "  storage_order: ", mypic2.storage_order
  #  echo "  colorspace:    ", mypic2.colorspace
  #  echo "  width:         ", mypic2.width
  #  echo "  height:        ", mypic2.height

  #  echo "Write BMP from BMP: ",
  #    mypic2.writeImage("test/samplebmp-out.bmp", SO(format: BMP))
  #  echo "Write PNG from BMP: ",
  #    mypic2.writeImage("test/samplebmp-out.png", SO(format: PNG, stride: 0))
  #  echo "Write JPEG from BMP: ",
  #    mypic2.writeImage("test/samplebmp-out.jpeg",
  #      SO(format: JPEG, quality: 100))

  #  let mypicjpeg = readImage[byte]("test/samplepng-out.jpeg")
  #  echo "Properties of 'test/samplepng-out.jpeg':"
  #  echo "  storage_order: ", mypicjpeg.storage_order
  #  echo "  colorspace:    ", mypicjpeg.colorspace
  #  echo "  width:         ", mypicjpeg.width
  #  echo "  height:        ", mypicjpeg.height

  #  echo "Write BMP from JPEG: ",
  #    mypicjpeg.writeImage("test/samplejpeg-out.bmp", SO(format: BMP))
  #  echo "Write PNG from JPEG: ",
  #    mypicjpeg.writeImage("test/samplejpeg-out.png",
  #      SO(format: PNG, stride: 0))
  #  echo "Write JPEG from JPEG: ",
  #    mypicjpeg.writeImage("test/samplejpeg-out.jpeg",
  #      SO(format: JPEG, quality: 100))

  #  echo "Success!"


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

    
