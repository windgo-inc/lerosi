import macros, streams, os, system, sequtils, strutils, math, algorithm, future
import imghdr, arraymancer

import stb_image/read as stbi
import stb_image/write as stbiw



type
  ImageFormat = enum
    PNG, BMP, JPEG, LDR2HDR, HDR
  SaveOptions = ref object
    case format: ImageFormat
    of PNG:
      stride: int
    of JPEG:
      quality: int
    of LDR2HDR:
      lo: float32
      hi: float32
    else:
      discard

  ImageChannel = enum
    C_LUMINANCE, C_INTENSITY,
    C_RED, C_GREEN, C_BLUE,
    C_CYAN, C_MAGENTA, C_YELLOW

    C_LUMA, C_Chm_U, C_Chm_V, C_Chm_Cb, C_Chm_Cr

    C_DEAD0, C_DEAD1,
    C_ALPHA,

    C_AUX00, C_AUX01, C_AUX02, C_AUX03,
    C_AUX04, C_AUX05, C_AUX06, C_AUX07,
    C_AUX08, C_AUX09, C_AUX10, C_AUX11,
    C_AUX12, C_AUX13, C_AUX14, C_AUX15


  ImageChannelLayout = object
    channels: seq[ImageChannel]


  ImageChannelBoundKind = enum
    Unbounded,
    BoundLower,
    BoundTotal

  ImageChannelBound[T] = ref object
    case kind: ImageChannelBoundKind
    of BoundLower:
      bound: T
    of BoundTotal:
      lbound: T
      ubound: T
    of Unbounded:
      discard

  ImageProperties[T] = object
    layout: ImageChannelLayout
    bound: ImageChannelBound[T]
    scale: T
    


template count[L: ImageChannelLayout](layout: L): untyped = layout.channels.len



type
  ImageData*[T] = openarray[T]|Tensor[T]

  IIOError* = object of Exception



template toType*[U](d: openarray[U], T: typedesc): untyped =
  ## Convert from one array type to another. In the case that the target type
  ## is the same as the current array type
  when T is U and U is T: d else: map(d, proc (x: U): T = T(x))



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


proc imageio_load_core*[U: string|openarray](resource: U): Tensor[uint8] =
  ## Load an image from a file or memory
  
  try:
    # Detect image type.
    let itype = resource.imageio_check_format()

    # Select loader.
    if itype == imghdr.ImageType.HDR:
      raise newException(IIOError, "LERoSI-IIO: HDR format must be loaded through the image_load_hdr interface.")
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

proc stbi_write_hdr(
  filename: cstring;
  x, y, channels: cint;
  data: ptr cfloat
): cint
  {.importc: "stbi_write_hdr".}

proc stbi_write_hdr_to_func(
  fn: writeCallback;
  context: pointer;
  x, y, channels: cint;
  data: ptr cfloat
): cint
  {.importc: "stbi_write_hdr_to_func".}



proc imageio_load_hdr_core*[U: string|openarray](resource: U): Tensor[float32] =
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



template write_img_impl[T](img: Tensor[T], filename: string, iface: untyped): untyped =
  iface(filename, img.width, img.height, img.channels, img.pixels)

template write_img_impl[T](img: Tensor[T], filename: string, iface, opt: untyped): untyped =
  iface(filename, img.width, img.height, img.channels, img.pixels, opt)

template write_img_impl[T](img: Tensor[T], iface: untyped): untyped =
  iface(img.width, img.height, img.channels, img.pixels)

template write_img_impl[T](img: Tensor[T], iface, opt: untyped): untyped =
  iface(img.width, img.height, img.channels, img.pixels, opt)

template write_hdr_impl[T](img: Tensor[T], filename: string): untyped =
  block:
    let cimg = when img is Tensor[cfloat]: img else: img.asType(cfloat)
    let data = cimg.chw2hwc().asContiguous().data
    let res = stbi_write_hdr(filename.cstring, cimg.width.cint, cimg.height.cint, cimg.channels.cint, data[0].unsafeAddr) == 1

    res


proc sequence_write(context, data: pointer, size: cint) {.cdecl.} =
  if size > 0:
    let wbuf = cast[ptr seq[byte]](context)
    let wbufl = wbuf[].len

    wbuf[].setLen(wbufl + size)
    copyMem(wbuf[][wbufl].addr, data, size)


template write_hdr_impl[T](img: Tensor[T]): untyped =
  block:
    let cimg = when img is Tensor[cfloat]: img else: img.asType(cfloat)
    let data = cimg.chw2hwc().asContiguous().data

    var buf: seq[byte]
    let res = stbi_write_hdr_to_func(sequence_write, buf.addr, cimg.width.cint, cimg.height.cint, cimg.channels.cint, data[0].unsafeAddr) == 1

    res


proc imageio_save_core[T](img: Tensor[T], filename: string, saveOpt: SaveOptions = SaveOptions(nil)): bool =
  let theOpt = if saveOpt == nil: SaveOptions(format: BMP) else: saveOpt

  case theOpt.format:
    of BMP:
      result = img.write_img_impl(filename, stbiw.writeBMP)
    of PNG:
      result = img.write_img_impl(filename, stbiw.writePNG, theOpt.stride)
    of JPEG:
      result = img.write_img_impl(filename, stbiw.writeJPG, theOpt.quality)
    of HDR:
      result = img.write_hdr_impl(filename)
    else:
      raise newException(IIOError, "LERoSI-IIO: Unsupported image format " & $theOpt.format & ".")


proc imageio_save_core*[T](img: Tensor[T], saveOpt: SaveOptions = SaveOptions(nil)): bool =
  let theOpt = if saveOpt == nil: SaveOptions(format: BMP) else: saveOpt

  case theOpt.format:
    of BMP:
      result = img.write_img_impl(stbiw.writeBMP)
    of PNG:
      result = img.write_img_impl(stbiw.writePNG, theOpt.stride)
    of JPEG:
      result = img.write_img_impl(stbiw.writeJPG, theOpt.quality)
    of HDR:
      result = img.write_hdr_impl()
    else:
      raise newException(IIOError, "LERoSI-IIO: Unsupported image format " & $theOpt.format & ".")


when isMainModule:
  import typetraits

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

  myhdrpic *= 255.0
  echo "Scale for the rest of the bitmap test"

  echo "Write BMP from second HDR: ", myhdrpic.imageio_save_core("test/samplehdr2-out.bmp", SaveOptions(format: BMP))


#proc imageio_save*[T; U: SomeNumber](filename: string, data: openarray[U], w, h: int, options: set[T] = {IIO_DEFAULT_ENCODING}) =


#proc imageio_save_png*[T; U: SomeNumber](filename: string, data: openarray[U], w, h: int, options: set[T] = {IIO_DEFAULT_FORMAT}) {.inline, noSideEffect.} =
