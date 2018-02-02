import system, unittest, macros, math
import typetraits, sequtils

import lerosi
import lerosi/iio_core
import lerosi/iio_types

suite "Group of tests":
  test "Image I/O (Internal)":
    # Taken from the isMainModule tests in lerosi.nim
    # TODO: Add an automatic correctness verificiation which may account for
    # the drift in lossy compression methods (JPEG).
    let mypic = "test/sample.png".imageio_load_core()
    echo "PNG Loaded Shape: ", mypic.shape

    echo "Write BMP from PNG: ", mypic.imageio_save_core("test/samplepng-out.bmp", SaveOptions(format: BMP))
    echo "Write PNG from PNG: ", mypic.imageio_save_core("test/samplepng-out.png", SaveOptions(format: PNG, stride: 0))
    echo "Write JPEG from PNG: ", mypic.imageio_save_core("test/samplepng-out.jpeg", SaveOptions(format: JPEG, quality: 100))
    echo "Write HDR from PNG: ", imageio_save_core(mypic.asType(cfloat) / 255.0, "test/samplepng-out.hdr", SaveOptions(format: HDR))

    let mypic2 = "test/samplepng-out.bmp".imageio_load_core()
    echo "BMP Loaded Shape: ", mypic2.shape

    echo "Write BMP from BMP: ", mypic2.imageio_save_core("test/samplebmp-out.bmp", SaveOptions(format: BMP))
    echo "Write PNG from BMP: ", mypic2.imageio_save_core("test/samplebmp-out.png", SaveOptions(format: PNG, stride: 0))
    echo "Write JPEG from BMP: ", mypic2.imageio_save_core("test/samplebmp-out.jpeg", SaveOptions(format: JPEG, quality: 100))
    echo "Write HDR from BMP: ", imageio_save_core(mypic2.asType(cfloat) / 255.0, "test/samplebmp-out.hdr", SaveOptions(format: HDR))

    let mypicjpeg = "test/samplepng-out.jpeg".imageio_load_core()
    echo "JPEG Loaded Shape: ", mypicjpeg.shape

    echo "Write BMP from JPEG: ", mypicjpeg.imageio_save_core("test/samplejpeg-out.bmp", SaveOptions(format: BMP))
    echo "Write PNG from JPEG: ", mypicjpeg.imageio_save_core("test/samplejpeg-out.png", SaveOptions(format: PNG, stride: 0))
    echo "Write JPEG from JPEG: ", mypicjpeg.imageio_save_core("test/samplejpeg-out.jpeg", SaveOptions(format: JPEG, quality: 100))
    echo "Write HDR from JPEG: ", imageio_save_core(mypicjpeg.asType(cfloat) / 255.0, "test/samplejpeg-out.hdr", SaveOptions(format: HDR))

    var mypichdr = "test/samplepng-out.hdr".imageio_load_hdr_core()
    echo "HDR Loaded Shape: ", mypichdr.shape

    echo "Write HDR from HDR: ", mypichdr.imageio_save_core("test/samplehdr-out.hdr", SaveOptions(format: HDR))

    echo "Scale for the rest of the formats"
    mypichdr *= 255.0

    echo "Write BMP from HDR: ", mypichdr.imageio_save_core("test/samplehdr-out.bmp", SaveOptions(format: BMP))
    echo "Write PNG from HDR: ", mypichdr.imageio_save_core("test/samplehdr-out.png", SaveOptions(format: PNG, stride: 0))
    echo "Write JPEG from HDR: ", mypichdr.imageio_save_core("test/samplehdr-out.jpeg", SaveOptions(format: JPEG, quality: 100))

    var myhdrpic = "test/samplehdr-out.hdr".imageio_load_hdr_core()
    echo "HDR Loaded Shape: ", myhdrpic.shape

    echo "Writing HDR to memory to read back."
    let hdrseq = myhdrpic.imageio_save_core(SaveOptions(format: HDR))
    #echo hdrseq
    let myhdrpic2 = hdrseq.imageio_load_hdr_core()
    assert myhdrpic == myhdrpic2
    echo "Success!"

    myhdrpic *= 255.0
    echo "Scale for the rest of the bitmap test"

    echo "Write BMP from second HDR: ", myhdrpic.imageio_save_core("test/samplehdr2-out.bmp", SaveOptions(format: BMP))

  test "Image LDR I/O (User)":
    let mypic = readImage[byte]("test/sample.png")
    echo "Properties of 'test/sample.png':"
    echo "  channelLayoutLen:  ", mypic.channelLayoutLen
    echo "  channelLayoutName: ", mypic.channelLayoutName
    echo "  channels:          ", mypic.channels
    echo "  width:             ", mypic.width
    echo "  height:            ", mypic.height

    echo "Write BMP from PNG: ", mypic.writeImage("test/samplepng-out.bmp", SaveOptions(format: BMP))
    echo "Write PNG from PNG: ", mypic.writeImage("test/samplepng-out.png", SaveOptions(format: PNG, stride: 0))
    echo "Write JPEG from PNG: ", mypic.writeImage("test/samplepng-out.jpeg", SaveOptions(format: JPEG, quality: 100))

    let mypic2 = readImage[byte]("test/samplepng-out.bmp")
    echo "Properties of 'test/samplepng-out.bmp':"
    echo "  channelLayoutLen:  ", mypic2.channelLayoutLen
    echo "  channelLayoutName: ", mypic2.channelLayoutName
    echo "  channels:          ", mypic2.channels
    echo "  width:             ", mypic2.width
    echo "  height:            ", mypic2.height

    echo "Write BMP from BMP: ", mypic2.writeImage("test/samplebmp-out.bmp", SaveOptions(format: BMP))
    echo "Write PNG from BMP: ", mypic2.writeImage("test/samplebmp-out.png", SaveOptions(format: PNG, stride: 0))
    echo "Write JPEG from BMP: ", mypic2.writeImage("test/samplebmp-out.jpeg", SaveOptions(format: JPEG, quality: 100))

    let mypicjpeg = readImage[byte]("test/samplepng-out.jpeg")
    echo "Properties of 'test/samplepng-out.jpeg':"
    echo "  channelLayoutLen:  ", mypicjpeg.channelLayoutLen
    echo "  channelLayoutName: ", mypicjpeg.channelLayoutName
    echo "  channels:          ", mypicjpeg.channels
    echo "  width:             ", mypicjpeg.width
    echo "  height:            ", mypicjpeg.height

    echo "Write BMP from JPEG: ", mypicjpeg.writeImage("test/samplejpeg-out.bmp", SaveOptions(format: BMP))
    echo "Write PNG from JPEG: ", mypicjpeg.writeImage("test/samplejpeg-out.png", SaveOptions(format: PNG, stride: 0))
    echo "Write JPEG from JPEG: ", mypicjpeg.writeImage("test/samplejpeg-out.jpeg", SaveOptions(format: JPEG, quality: 100))

    echo "Success!"

  test "Channels and channel layout properties":
    template doRGBAProcs(what: untyped): untyped =
      echo what, ".ChR = ", what.ChR, " and ", what, ".channel(ChIdR) = ", what.channel(ChIdR)
      echo what, ".ChG = ", what.ChG, " and ", what, ".channel(ChIdG) = ", what.channel(ChIdG)
      echo what, ".ChB = ", what.ChB, " and ", what, ".channel(ChIdB) = ", what.channel(ChIdB)
      echo what, ".ChA = ", what.ChA, " and ", what, ".channel(ChIdA) = ", what.channel(ChIdA)

    template doYCbCrProcs(what: untyped): untyped =
      echo what, ".ChY  = ", what.ChY,  " and ", what, ".channel(ChIdY)  = ", what.channel(ChIdY)
      echo what, ".ChCb = ", what.ChCb, " and ", what, ".channel(ChIdCb) = ", what.channel(ChIdCb)
      echo what, ".ChCr = ", what.ChCr, " and ", what, ".channel(ChIdCr) = ", what.channel(ChIdCr)

    template doCmpChannelsTest(a, b: untyped): untyped =
      echo "cmpChannels(", a, ", ", b, ") = ", cmpChannels(a, b)

    let
      myLayouts = [
        ChLayoutRGBA.id, ChLayoutBGRA.id,
        ChLayoutYCbCr.id, ChLayoutYCrCb.id
      ]

    for i, layout in myLayouts:
      echo "Testing ", layout, ":"
      echo layout, ".len = ", layout.len
      echo layout, ".channels = ", layout.channels
      if i > 1: doYCbCrProcs(layout) else: doRGBAProcs(layout)

    doCmpChannelsTest(ChLayoutRGBA.id, ChLayoutRGBA.id)
    doCmpChannelsTest(ChLayoutRGBA.id, ChLayoutARGB.id)
    doCmpChannelsTest(ChLayoutRGBA.id, ChLayoutRGB.id)
    doCmpChannelsTest(ChLayoutRGBA.id, ChLayoutBGRA.id)
    doCmpChannelsTest(ChLayoutRGBA.id, ChLayoutABGR.id)
    doCmpChannelsTest(ChLayoutRGBA.id, ChLayoutBGR.id)

  test "Compare channels":
    let pic1 = newStaticLayoutImage[byte, ChLayoutYpCbCr](5, 5)
    let pic2 = newStaticLayoutImage[byte, ChLayoutAYpCbCr](5, 5)
    let pic3 = newDynamicLayoutImage[byte](5, 5, ChLayoutRGBA)

    static:
      for j, i in cmpChannels(ChLayoutYpCbCr, ChLayoutAYpCbCr):
        echo "j, i = ", j, ", ", i

    for j, i in cmpChannels(pic1, pic2):
      echo "j, i = ", j, ", ", i
    
    #echo type(pic1).name, " and ", type(pic2).name
    #for j, i in cmpChannels(pic1, pic2):
    #  echo "j, i = ", j, ", ", i

    #for y in 
    #echo type(pic2), " and ", type(pic3)
    #for j, i in cmpChannels(pic2, pic3): echo "j, i = ", j, ", ", i
    #echo type(pic1), " and ", type(pic3)
    #for j, i in cmpChannels(pic1, pic3): echo "j, i = ", j, ", ", i
  
  test "Colorspace":
    #expandMacros:

    RGB2BGR(ChLayoutRGB, "R")

  test "Copy channels":
    let planarpic = readImage[byte]("test/sample.bmp").planar
    let interleavedpic = planarpic.interleaved

    var planaroutpic = newDynamicLayoutImage[byte](planarpic.width, planarpic.height, ChLayoutBGR.id).planar
    var interleavedoutpic = planaroutpic.interleaved

    planarpic.copyChannelsTo(planaroutpic)
    interleavedpic.copyChannelsTo(interleavedoutpic)

    check planaroutpic.writeImage("test/redbluereverse-planar2planar.bmp", SaveOptions(format: BMP))
    check interleavedoutpic.writeImage("test/redbluereverse-interleaved2interleaved.bmp", SaveOptions(format: BMP))

    planarpic.copyChannelsTo(interleavedoutpic)
    interleavedpic.copyChannelsTo(planaroutpic)

    check planaroutpic.writeImage("test/redbluereverse-interleaved2planar.bmp", SaveOptions(format: BMP))
    check interleavedoutpic.writeImage("test/redbluereverse-planar2interleaved.bmp", SaveOptions(format: BMP))

    
