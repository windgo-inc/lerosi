import macros, os, system, sequtils, strutils, math, algorithm, future
import imghdr, arraymancer

import stb_image/read as stbi
import stb_image/write as stbiw



const
  IIO_STOR_UINT8* = 1.int8
  IIO_STOR_FLOAT_UNIT* = 2.int8
  IIO_STOR_FLOAT_POSITIVE* = 3.int8

  IIO_CH_ZA*  = 4.int8
  IIO_CH_AZ*  = 5.int8
  IIO_CH_ZX*  = 6.int8
  IIO_CH_XZ*  = 7.int8

  IIO_ORD_V*   = 8.int8
  IIO_ORD_RGB* = 9.int8
  IIO_ORD_BGR* = 10.int8

  IIO_DEFAULT_FORMAT* = {IIO_STOR_UINT8, IIO_ORD_RGB, IIO_CH_ZA}



type
  ChannelForm = enum
    ## Floating point channel encoding forms
    NormalizedPositiveForm, NormalizedUnitForm


type
  ImageFormat = enum
    PNG, BMP, JPEG, LDR2HDR, HDR
  SaveOptions = ref object
    inputForm: ChannelForm
    isHdr: bool
    case kind: ImageFormat
    of PNG:
      stride: int
    of JPEG:
      quality: int
    of LDR2HDR:
      lo: float32
      hi: float32
    else:
      discard

const
  TypeDefaultForm = NormalizedPositiveForm ## The default floating point encoding form



type
  ImageData*[T] = openarray[T]|Tensor[T]


#type
#  ImageType* {.pure.} = imghdr.ImageType ## Image format enumeration.


type
  IIOError* = object of Exception



template toType*[U](d: openarray[U], T: typedesc): untyped =
  ## Convert from one array type to another. In the case that the target type
  ## is the same as the current array type
  when T is U and U is T:
    block:
      d
  else:
    block:
      map(d, proc (x: U): T = T(x))



proc normalPosToI[E: SomeReal, I: SomeInteger](x: E): I {.inline, noSideEffect.} =
  I(x * E(high(I)))


proc normalUnitToI[E: SomeReal, I: SomeInteger](x: E): I {.inline, noSideEffect.} =
  let c = E(high(I)) / E(2.0)
  result = I((x + 1.E) * c)


proc normalIntToPos[I: SomeInteger, E: SomeReal](x: I): E {.inline, noSideEffect.} =
  x.E / E(high(I))


proc normalIntToUnit[I: SomeInteger, E: SomeReal](x: I): E {.inline, noSideEffect.} =
  let c = E(high(I)) / E(2.0)
  result = (x.E / c) - E(1.0)



template lerosiRenormalized*[U: SomeNumber](d: U, T: typedesc, form: static[ChannelForm] = TypeDefaultForm, form2: static[ChannelForm] = TypeDefaultForm): untyped =
  ## Renormalize according to normal channel encoding forms, source, and destination types.
  when U is SomeReal and T is SomeInteger:
    case form:
      of NormalizedPositiveForm:
        normalPosToI[U, T](d)
      of NormalizedUnitForm:
        normalUnitToI[U, T](d)
  else:
    when U is SomeInteger and T is SomeReal:
      case form:
        of NormalizedPositiveForm:
          normalIntToPos[U, T](d)
        of NormalizedUnitForm:
          normalIntToUnit[U, T](d)
    else:
      when U is SomeInteger and T is SomeInteger:
        normalUnitToI[float, T](normalIntToUnit[U, float](d))
      else:
        when U is SomeReal and T is SomeReal:
          when form == form2:
            d
          else:
            case (form, form2):
              of (NormalizedPositiveForm, NormalizedUnitForm):
                T(d.float * 2.float - 1.float)
              of (NormalizedUnitForm, NormalizedPositiveForm):
                T(d.float * 0.5.float + 0.5.float)
              else:
                d.T
        else:
          d.T


template lerosiMap*[D: ImageData](img: D, body: untyped): untyped =
  when D is Tensor:
    img.map_inline:
      body
  else:
    img.map do (x: U) -> T:
      body


template lerosiRenormalized*[D: ImageData](img: D, T: typedesc, form: ChannelForm = TypeDefaultForm, form2: ChannelForm = TypeDefaultForm): untyped =
  img.lerosiMap:
    lerosiRenormalized(x, T, form, form2)


proc get_desired_channels(options: set[int8]): int =
  let alpha_add = if IIO_CH_ZA in options or IIO_CH_AZ in options: 1 else: 0
  if IIO_ORD_V in options:
    result = alpha_add + 1
  elif IIO_ORD_RGB in options or IIO_ORD_BGR in options:
    result = alpha_add + 3
  else:
    result = 0

proc get_stbi_format_by_channels(actual_channels: int): set[int8] =
  result = case actual_channels:
    of 1: {IIO_ORD_V, IIO_STOR_UINT8}
    of 2: {IIO_ORD_V, IIO_CH_ZA, IIO_STOR_UINT8}
    of 3: {IIO_ORD_RGB, IIO_STOR_UINT8}
    of 4: {IIO_ORD_RGB, IIO_CH_ZA, IIO_STOR_UINT8}
    else: IIO_DEFAULT_FORMAT


proc imageio_check_format(filename: string): ImageType =
  ## Check the image format stored within a file.
  testImage(filename)


proc imageio_check_format*[T](data: openarray[T]): ImageType =
  ## Check the image format stored within core memory.
  testImage(data[0..31].toType(int8))


proc channels*[T](img: Tensor[T]): int {.inline.}  =
  ## Return number of channels of the image
  img.shape[^3]


proc height*[T](img: Tensor[T]): int {.inline.} =
  ## Return height of the image
  img.shape[^2]


proc width*[T](img: Tensor[T]): int {.inline.}  =
  ## Return width of the image
  img.shape[^1]


proc hwc2chw*[T](img: Tensor[T]): Tensor[T] =
  ## Convert the storage shape of the image from H⨯W⨯C → C⨯H⨯W.
  ##
  ## By old convention and computer graphics reasons, image I/O libraries often store
  ## the decoded image in H⨯W⨯C, but in the context of image processing, we frequently
  ## wish to process each channel as it's own layer. There are other performance
  ## reasons for storing the image in C⨯H⨯W form, such as the ability to vectorize
  ## recombination of the channels.
  img.permute(2, 0, 1)


proc chw2hwc*[T](img: Tensor[T]): Tensor[T] =
  ## Convert the storage shape of the image from C⨯H⨯W → H⨯W⨯C.
  img.permute(1, 2, 0)


proc pixels*[T](img: Tensor[T]): seq[uint8] =
  # Return contiguous pixel data in the HxWxC convetion, method intended
  # to use for interfacing with other libraries
  img.chw2hwc().asType(uint8).asContiguous().data


proc imageio_load*[U: string|openarray](resource: U): Tensor[uint8] =
  ## Load an image from a file or memory
  
  try:
    # Detect image type.
    let itype = resource.imageio_check_format()

    # Select loader.
    if itype == imghdr.ImageType.HDR:
      raise newException(IIOError, "LERoSI-IIO: HDR format image may not be loaded from " & $itype & " file.")
    elif itype in {imghdr.ImageType.BMP, imghdr.ImageType.PNG, imghdr.ImageType.JPEG}:
      let desired_ch = 0
      var w, h, ch: int

      let pixels =
        when U is string:
          # resource is interpreted as a filename if it is a string.
          stbi.load(resource, w, h, ch, desired_ch)
        else:
          # resource is interpreted as an encoded image if it is an openarray
          stbi.loadFromMemory(resource.toType(byte), w, h, ch, desired_ch)

    
      result = pixels.toTensor().reshape([h, w, ch]).hwc2chw().asType(uint8).asContiguous()
    else:
      raise newException(IIOError, "LERoSI-IIO: Unsupported image format: " & $itype)

  except STBIException:
    raise newException(IIOError, "LERoSI-IIO: Backend: " & getCurrentException().msg)
  except IOError:
    raise newException(IIOError, "LERoSI-IIO: I/O: " & getCurrentException().msg)
  except SystemError:
    raise newException(IIOError, "LERoSI-IIO: System: " & getCurrentException().msg)


proc stbi_loadf(
  filename: cstring;
  x, y, channels_in_file: var cint;
  desired_channels: cint
): ptr cfloat
  {.importc: "stbi_loadf".}

proc stbi_loadf_from_memory(
  buffer: ptr cfloat;
  length: cint;
  x, y, channels_in_file: var cint;
  desired_channels: cint
): ptr cfloat
  {.importc: "stbi_loadf_from_memory".}


proc imageio_load_hdr*[U: string|openarray](resource: U): Tensor[float32] =
  try:
    # Detect image type.
    let itype = resource.imageio_check_format()

    # Select loader.
    if itype == imghdr.ImageType.HDR:
      let desired_ch = 0
      var w, h, ch: cint

      var data: ptr cfloat
      when U is string:
        data = stbi_loadf(resource.cstring, w, h, ch, desired_ch.cint)
      else:
        let inputData = resource.toType(cfloat)
        var
          castedBuffer: ptr cfloat = cast[ptr cfloat](resource[0].unsafeAddr)

        data = stbi_loadf_from_memory(castedBuffer, buffer.len.cint, w, h, ch, desired_ch.cint)

      #shallow(data)
      
      var pixelsOut: seq[cfloat]
      newSeq(pixelsOut, w*h*ch)
      copyMem(pixelsOut[0].addr, data, pixelsOut.len * sizeof(cfloat))

      result = pixelsOut.toTensor().reshape([h.int, w, ch]).hwc2chw().asType(float32).asContiguous()
    else:
      raise newException(IIOError, "LERoSI-IIO-HDR: Not an HDR format - " & $itype)

  except STBIException:
    raise newException(IIOError, "LERoSI-IIO-HDR: Backend: " & getCurrentException().msg)
  except IOError:
    raise newException(IIOError, "LERoSI-IIO-HDR: I/O: " & getCurrentException().msg)
  except SystemError:
    raise newException(IIOError, "LERoSI-IIO-HDR: System: " & getCurrentException().msg)



proc imageio_save*[T](img: Tensor[T], filename: string, saveOpt: SaveOptions = SaveOptions(kind: BMP)): bool =
  let theOpt = if saveOpt == nil: SaveOptions(kind: BMP) else: saveOpt

  var oimg: Tensor[T]
  if theOpt.isHdr and not (theOpt.kind == HDR):
    oimg = img.map_inline:
      x * 255.T
  else:
    oimg = img

  result = case theOpt.kind:
    of BMP:
      stbiw.writeBMP(filename, oimg.width, oimg.height, oimg.channels, oimg.pixels)
    of PNG:
      stbiw.writePNG(filename, oimg.width, oimg.height, oimg.channels, oimg.pixels, theOpt.stride)
    of JPEG:
      stbiw.writeJPG(filename, oimg.width, oimg.height, oimg.channels, oimg.pixels, theOpt.quality)
    of HDR:
      when oimg is Tensor[float32]:
        stbiw.writeHDR(filename, oimg.width, oimg.height, oimg.channels, oimg.chw2hwc().asContiguous().data)
      else:
        false
    of LDR2HDR:
      var dat: Tensor[float32] = oimg.asType(float32)

      dat.apply_inline:
        theOpt.lo + x / (theOpt.hi - theOpt.lo)
      
      stbiw.writeHDR(filename, dat.width, dat.height, dat.channels, dat.chw2hwc().asContiguous().data)
    else:
      stbiw.writeBMP(filename, oimg.width, oimg.height, oimg.channels, oimg.pixels)


proc imageio_save*[T](img: Tensor[T], saveOpt: SaveOptions = SaveOptions(kind: BMP)): bool =
  let theOpt = if saveOpt == nil: SaveOptions(kind: BMP) else: saveOpt

  var oimg: Tensor[T]
  if theOpt.isHdr and not (theOpt.kind == HDR):
    oimg = img.map_inline:
      x * 255.T
  else:
    oimg = img

  result = case theOpt.kind:
    of BMP:
      stbiw.writeBMP(oimg.width, oimg.height, oimg.channels, oimg.pixels)
    of PNG:
      stbiw.writePNG(oimg.width, oimg.height, oimg.channels, oimg.pixels, theOpt.stride)
    of JPEG:
      stbiw.writeJPG(oimg.width, oimg.height, oimg.channels, oimg.pixels, theOpt.quality)
    of HDR:
      when oimg is Tensor[float32]:
        stbiw.writeHDR(oimg.width, oimg.height, oimg.channels, oimg.chw2hwc().asContiguous().data)
      else:
        false
    of LDR2HDR:
      var dat: Tensor[float32] = oimg.asType(float32)

      dat.apply_inline:
        theOpt.lo + x / (theOpt.hi - theOpt.lo)
      
      stbiw.writeHDR(dat.width, dat.height, dat.channels, dat.chw2hwc().asContiguous().data)
    else:
      stbiw.writeBMP(oimg.width, oimg.height, oimg.channels, oimg.pixels)


when isMainModule:
  import typetraits

  let mypic = "test/sample.png".imageio_load()
  echo "PNG Loaded Shape: ", mypic.shape

  echo "Write BMP from PNG: ", mypic.imageio_save("test/samplepng-out.bmp", SaveOptions(kind: BMP))
  echo "Write PNG from PNG: ", mypic.imageio_save("test/samplepng-out.png", SaveOptions(kind: PNG, stride: 0))
  echo "Write JPEG from PNG: ", mypic.imageio_save("test/samplepng-out.jpeg", SaveOptions(kind: JPEG, quality: 100))
  echo "Write HDR from PNG: ", mypic.imageio_save("test/samplepng-out.hdr", SaveOptions(kind: LDR2HDR, lo: 0.float32, hi: 255.float32))

  let mypic2 = "test/samplepng-out.bmp".imageio_load()
  echo "BMP Loaded Shape: ", mypic2.shape

  echo "Write BMP from BMP: ", mypic2.imageio_save("test/samplebmp-out.bmp", SaveOptions(kind: BMP))
  echo "Write PNG from BMP: ", mypic2.imageio_save("test/samplebmp-out.png", SaveOptions(kind: PNG, stride: 0))
  echo "Write JPEG from BMP: ", mypic2.imageio_save("test/samplebmp-out.jpeg", SaveOptions(kind: JPEG, quality: 100))
  echo "Write HDR from BMP: ", mypic2.imageio_save("test/samplebmp-out.hdr", SaveOptions(kind: LDR2HDR, lo: 0.float32, hi: 255.float32))

  let mypicjpeg = "test/samplepng-out.jpeg".imageio_load()
  echo "JPEG Loaded Shape: ", mypicjpeg.shape

  echo "Write BMP from JPEG: ", mypicjpeg.imageio_save("test/samplejpeg-out.bmp", SaveOptions(kind: BMP))
  echo "Write PNG from JPEG: ", mypicjpeg.imageio_save("test/samplejpeg-out.png", SaveOptions(kind: PNG, stride: 0))
  echo "Write JPEG from JPEG: ", mypicjpeg.imageio_save("test/samplejpeg-out.jpeg", SaveOptions(kind: JPEG, quality: 100))
  echo "Write HDR from JPEG: ", mypicjpeg.imageio_save("test/samplejpeg-out.hdr", SaveOptions(kind: LDR2HDR, lo: 0.float32, hi: 255.float32))

  var mypichdr = "test/samplepng-out.hdr".imageio_load_hdr()
  echo "HDR Loaded Shape: ", mypichdr.shape

  #mypichdr *= 255.0

  echo "Write BMP from HDR: ", mypichdr.imageio_save("test/samplehdr-out.bmp", SaveOptions(kind: BMP, isHdr: true))
  echo "Write PNG from HDR: ", mypichdr.imageio_save("test/samplehdr-out.png", SaveOptions(kind: PNG, stride: 0, isHdr: true))
  echo "Write JPEG from HDR: ", mypichdr.imageio_save("test/samplehdr-out.jpeg", SaveOptions(kind: JPEG, quality: 100, isHdr: true))
  echo "Write HDR from HDR: ", mypichdr.imageio_save("test/samplehdr-out.hdr", SaveOptions(kind: HDR, isHdr: true))

  let myhdrpic = "test/samplehdr-out.hdr".imageio_load_hdr()
  echo "HDR Loaded Shape: ", myhdrpic.shape
  echo "Write BMP from second HDR: ", myhdrpic.imageio_save("test/samplehdr2-out.bmp", SaveOptions(kind: BMP))


#proc imageio_save*[T; U: SomeNumber](filename: string, data: openarray[U], w, h: int, options: set[T] = {IIO_DEFAULT_ENCODING}) =


#proc imageio_save_png*[T; U: SomeNumber](filename: string, data: openarray[U], w, h: int, options: set[T] = {IIO_DEFAULT_FORMAT}) {.inline, noSideEffect.} =
