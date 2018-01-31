import system, unittest, macros, math
import typetraits

import lerosi
import lerosi/iio_core

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
  
# These tests need to be reworked to use ChannelIds rather than string channel
# names.

#when isMainModule:
#  template doRGBAProcs(what: untyped): untyped =
#    echo what.name, ".ChR = ", what.ChR, " ", what.name, ".channel(\"R\") = ", what.channel("R")
#    echo what.name, ".ChG = ", what.ChG, " ", what.name, ".channel(\"G\") = ", what.channel("G")
#    echo what.name, ".ChB = ", what.ChB, " ", what.name, ".channel(\"B\") = ", what.channel("B")
#    echo what.name, ".ChA = ", what.ChA, " ", what.name, ".channel(\"A\") = ", what.channel("A")
#
#  template doYCbCrProcs(what: untyped): untyped =
#    echo what.name, ".ChY  = ", what.ChY,  " ", what.name, ".channel(\"Y\")  = ", what.channel("Y")
#    echo what.name, ".ChCb = ", what.ChCb, " ", what.name, ".channel(\"Cb\") = ", what.channel("Cb")
#    echo what.name, ".ChCr = ", what.ChCr, " ", what.name, ".channel(\"Cr\") = ", what.channel("Cr")
#
#  template doCmpChannelsTest(nam: untyped, a: untyped, b: untyped): untyped =
#    echo "cmpChannels(", nam(a), ", ", nam(b), ") = ", cmpChannels(a, b)
#
#  static:
#    echo "*** COMPILE TIME TESTS ***"
#    template doTest(layoutType: typedesc, body: untyped): untyped =
#      echo "Testing ", layoutType.name, " (static type):"
#      echo layoutType.name, ".id = ", layoutType.id
#      echo layoutType.name, ".len = ", layoutType.len
#      echo layoutType.name, ".channels = ", @(layoutType.channels)
#      body
#    
#    doTest(ChLayoutRGBA): doRGBAProcs(ChLayoutRGBA)
#    doTest(ChLayoutBGRA): doRGBAProcs(ChLayoutBGRA)
#
#    doTest(ChLayoutYCbCr): doYCbCrProcs(ChLayoutYCbCr)
#    doTest(ChLayoutYCrCb): doYCbCrProcs(ChLayoutYCrCb)
#
#    echo " ~ cmpChannels ~"
#    doCmpChannelsTest(name, ChLayoutRGBA, ChLayoutRGBA)
#    doCmpChannelsTest(name, ChLayoutRGBA, ChLayoutARGB)
#    doCmpChannelsTest(name, ChLayoutRGBA, ChLayoutRGB)
#    doCmpChannelsTest(name, ChLayoutRGBA, ChLayoutBGRA)
#    doCmpChannelsTest(name, ChLayoutRGBA, ChLayoutABGR)
#    doCmpChannelsTest(name, ChLayoutRGBA, ChLayoutBGR)
#
#  echo "*** RUN TIME TESTS ***"
#  let myLayouts = [ChLayoutRGBA.id, ChLayoutBGRA.id, ChLayoutYCbCr.id, ChLayoutYCrCb.id]
#  for i, layout in myLayouts:
#    echo "Testing ", layout.name, " ", layout, ":"
#    echo layout.name, ".len = ", layout.len
#    echo layout.name, ".channels = ", @(layout.channels)
#    if i > 1: doYCbCrProcs(layout) else: doRGBAProcs(layout)
#
#  echo " ~ cmpChannels ~"
#  doCmpChannelsTest(name, ChLayoutRGBA.id, ChLayoutRGBA.id)
#  doCmpChannelsTest(name, ChLayoutRGBA.id, ChLayoutARGB.id)
#  doCmpChannelsTest(name, ChLayoutRGBA.id, ChLayoutRGB.id)
#  doCmpChannelsTest(name, ChLayoutRGBA.id, ChLayoutBGRA.id)
#  doCmpChannelsTest(name, ChLayoutRGBA.id, ChLayoutABGR.id)
#  doCmpChannelsTest(name, ChLayoutRGBA.id, ChLayoutBGR.id)
    
