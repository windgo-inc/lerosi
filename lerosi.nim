import macros, streams, os, system, sequtils, strutils, math, algorithm, future
import imghdr, arraymancer

import stb_image/read as stbi
import stb_image/write as stbiw



type
  ImageFormat* = enum
    PNG, BMP, JPEG, HDR
  SaveOptions* = ref object
    case format: ImageFormat
    of PNG:
      stride: int
    of JPEG:
      quality: int
    else:
      discard

  ImageChannel* = enum
    C_LUMINANCE
    C_RED, C_GREEN, C_BLUE,
    C_CYAN, C_MAGENTA, C_YELLOW

    C_LUMA, C_Chm_U, C_Chm_V, C_Chm_Cb, C_Chm_Cr

    C_DEAD0, C_DEAD1,
    C_ALPHA,

    C_AUX00, C_AUX01, C_AUX02, C_AUX03,
    C_AUX04, C_AUX05, C_AUX06, C_AUX07,
    C_AUX08, C_AUX09, C_AUX10, C_AUX11,
    C_AUX12, C_AUX13, C_AUX14, C_AUX15

  ImageChannelLayout* = seq[ImageChannel]

  ImageDataOrdering* = enum
    OrderInterleaved,
    OrderPlanar

  ImageData*[T] = openarray[T]|Tensor[T]

  ImageObject*[T] = ref object
    layout: ImageChannelLayout
    order: ImageDataOrdering
    data: Tensor[T]

  IIOError* = object of Exception


const
  CH_Y*     = @[C_LUMINANCE]
  CH_YA*    = @[C_LUMINANCE, C_ALPHA]
  CH_AY*    = @[C_ALPHA, C_LUMINANCE]
  CH_RGB*   = @[C_RED, C_GREEN, C_BLUE]
  CH_RGBA*  = @[C_RED, C_GREEN, C_BLUE, C_ALPHA]
  CH_ARGB*  = @[C_ALPHA, C_RED, C_GREEN, C_BLUE]
  CH_RGBX*  = @[C_RED, C_GREEN, C_BLUE, C_DEAD0]
  CH_XRGB*  = @[C_DEAD0, C_RED, C_GREEN, C_BLUE]
  CH_BGR*   = @[C_RED, C_GREEN, C_BLUE]
  CH_BGRA*  = @[C_BLUE, C_GREEN, C_RED, C_ALPHA]
  CH_ABGR*  = @[C_ALPHA, C_BLUE,C_GREEN, C_RED]
  CH_BGRX*  = @[C_BLUE, C_GREEN, C_RED, C_DEAD0]
  CH_XBGR*  = @[C_DEAD0, C_BLUE,C_GREEN, C_RED]
  CH_YUV*   = @[C_LUMA, C_Chm_U, C_Chm_V]
  CH_YCbCr* = @[C_LUMA, C_Chm_Cb, C_Chm_Cr]


template toType*[U](d: openarray[U], T: typedesc): untyped =
  ## Convert from one array type to another. In the case that the target type
  ## is the same as the current array type
  when T is U and U is T: d else: map(d, proc (x: U): T = T(x))



proc imageio_check_format(filename: string): ImageType =
  ## Check the image format stored within a file.
  testImage(filename)


proc imageio_check_format[T](data: openarray[T]): ImageType =
  ## Check the image format stored within core memory.
  var header: seq[int8]
  newSeq(header, 32)
  copyMem(header[0].addr, data[0].unsafeAddr, 32)
  testImage(header)


#template channels[T](img: Tensor[T]): int =
#  ## Return number of channels of the image
#  img.shape[^3]
#
#
#template height[T](img: Tensor[T]): int =
#  ## Return height of the image
#  img.shape[^2]
#
#
#template width[T](img: Tensor[T]): int  =
#  ## Return width of the image
#  img.shape[^1]


proc channels*[T](img: ImageObject[T]): int {.inline, noSideEffect.} =
  case img.order:
    of OrderPlanar: img.data[^3]
    of OrderInterleaved: img.data[^1]


proc width*[T](img: ImageObject[T]): int {.inline, noSideEffect.} =
  case img.order:
    of OrderPlanar: img.data[^1]
    of OrderInterleaved: img.data[^2]


proc height*[T](img: ImageObject[T]): int {.inline, noSideEffect.} =
  case img.order:
    of OrderPlanar: img.data[^2]
    of OrderInterleaved: img.data[^3]


template to_chw[T](img: Tensor[T]): Tensor[T] =
  ## Convert the storage shape of the image from H⨯W⨯C → C⨯H⨯W.
  img.permute(2, 0, 1)


template to_hwc[T](img: Tensor[T]): Tensor[T] =
  ## Convert the storage shape of the image from C⨯H⨯W → H⨯W⨯C.
  img.permute(1, 2, 0)


template pixels[T](img: Tensor[T]): seq[byte] =
  ## Return the contiguous pixel data in canonical form.
  img.to_hwc().asType(byte).asContiguous().data


proc pixels*[T](img: ImageObject[T]): seq[byte] {.inline.} =
  ## Return the contiguous pixel data in canonical form.
  img.to_hwc().asType(byte).asContiguous().data


template imageio_load_core(resource: untyped): Tensor[byte] =
  ## Load an image from a file or memory
  block:
    var res: Tensor[byte]
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
          when resource is string:
            # resource is interpreted as a filename if it is a string.
            stbi.load(resource, w, h, ch, desired_ch)
          else:
            # resource is interpreted as an encoded image if it is an openarray
            stbi.loadFromMemory(resource.toType(byte), w, h, ch, desired_ch)

      
        res = pixels.toTensor().reshape([h, w, ch]).asType(byte)
      else:
        raise newException(IIOError, "LERoSI-IIO: Unsupported image format: " & $itype)

    except STBIException:
      raise newException(IIOError, "LERoSI-IIO: Backend: " & getCurrentException().msg)
    except IOError:
      raise newException(IIOError, "LERoSI-IIO: I/O: " & getCurrentException().msg)
    except SystemError:
      raise newException(IIOError, "LERoSI-IIO: System: " & getCurrentException().msg)

    res



proc stbi_loadf(
  filename: cstring;
  x, y, channels_in_file: var cint;
  desired_channels: cint
): ptr cfloat
  {.importc: "stbi_loadf".}


proc stbi_loadf_from_memory(
  buffer: ptr cuchar;
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


proc stbi_image_free(p: pointer) {.importc: "stbi_image_free".}



template imageio_load_hdr_core(resource: untyped): Tensor[float32] =
  block:
    var res: Tensor[float32]
    try:
      # Detect image type.
      let itype = resource.imageio_check_format()

      # Select loader.
      if itype == imghdr.ImageType.HDR:
        let desired_ch = 0
        var w, h, ch: cint

        let data: ptr cfloat =
          when resource is string:
            stbi_loadf(resource.cstring, w, h, ch, desired_ch.cint)
          else:
            stbi_loadf_from_memory(cast[ptr cuchar](resource[0].unsafeAddr), resource.len.cint, w, h, ch, desired_ch.cint)
        
        var pixelsOut: seq[cfloat]
        newSeq(pixelsOut, w*h*ch)
        copyMem(pixelsOut[0].addr, data, pixelsOut.len * sizeof(cfloat))

        res = pixelsOut.toTensor().reshape([h.int, w, ch]).asType(float32).asContiguous()
        stbi_image_free(data)
      else:
        raise newException(IIOError, "LERoSI-IIO-HDR: Not an HDR format - " & $itype)

    except STBIException:
      raise newException(IIOError, "LERoSI-IIO-HDR: Backend: " & getCurrentException().msg)
    except IOError:
      raise newException(IIOError, "LERoSI-IIO-HDR: I/O: " & getCurrentException().msg)
    except SystemError:
      raise newException(IIOError, "LERoSI-IIO-HDR: System: " & getCurrentException().msg)

    res


# NOTE: We replaced width, height, and channel Tensor properties, since at the low level,
# we implicily deal with interleaved data.

template write_img_impl[T](img: Tensor[T], U: typedesc, filename: string, iface: untyped): untyped =
  iface(filename, img.shape[^2], img.shape[^3], img.shape[^1], img.asType(U).asContiguous().data)

template write_img_impl[T](img: Tensor[T], U: typedesc, filename: string, iface, opt: untyped): untyped =
  iface(filename, img.shape[^2], img.shape[^3], img.shape[^1], img.asType(U).asContiguous().data, opt)

template write_img_impl[T](img: Tensor[T], U: typedesc, iface: untyped): untyped =
  iface(img.shape[^2], img.shape[^3], img.shape[^1], img.asType(U).asContiguous().data)

template write_img_impl[T](img: Tensor[T], U: typedesc, iface, opt: untyped): untyped =
  iface(img.shape[^2], img.shape[^3], img.shape[^1], img.asType(U).asContiguous().data, opt)

template write_hdr_impl[T](img: Tensor[T], filename: string): untyped =
  block:
    let cimg = when img is Tensor[cfloat]: img else: img.asType(cfloat)
    let data = cimg.asContiguous().data
    let res = stbi_write_hdr(filename.cstring, cimg.shape[^2].cint, cimg.shape[^3].cint, cimg.shape[^1].cint, data[0].unsafeAddr) == 1

    res


proc sequence_write(context, data: pointer, size: cint) {.cdecl.} =
  if size > 0:
    let wbuf = cast[ptr StringStream](context)
    wbuf[].writeData(data, size)


template write_hdr_impl[T](img: Tensor[T]): seq[byte] =
  block:
    let cimg = when img is Tensor[cfloat]: img else: img.asType(cfloat)
    let data = cimg.asContiguous().data

    var buf = newStringStream()
    let res = stbi_write_hdr_to_func(sequence_write, buf.addr, cimg.shape[^2].cint, cimg.shape[^3].cint, cimg.shape[^1].cint, data[0].unsafeAddr) == 1

    if not res:
      raise newException(IIOError, "LERoSI-IIO-HDR: Error writing to sequence.")

    cast[seq[byte]](buf.data)


# TODO: Merge imageio_save_core variants using a macro.

proc imageio_save_core[T](img: Tensor[T], filename: string, saveOpt: SaveOptions = SaveOptions(nil)): bool =
  let theOpt = if saveOpt == nil: SaveOptions(format: BMP) else: saveOpt

  case theOpt.format:
    of BMP:
      result = img.write_img_impl(byte, filename, stbiw.writeBMP)
    of PNG:
      result = img.write_img_impl(byte, filename, stbiw.writePNG, theOpt.stride)
    of JPEG:
      result = img.write_img_impl(byte, filename, stbiw.writeJPG, theOpt.quality)
    of HDR:
      result = img.write_hdr_impl(filename)
    else:
      raise newException(IIOError, "LERoSI-IIO: Unsupported image format " & $theOpt.format & ".")


proc imageio_save_core[T](img: Tensor[T], saveOpt: SaveOptions = SaveOptions(nil)): seq[byte] =
  let theOpt = if saveOpt == nil: SaveOptions(format: BMP) else: saveOpt

  case theOpt.format:
    of BMP:
      result = img.write_img_impl(byte, stbiw.writeBMP)
    of PNG:
      result = img.write_img_impl(byte, stbiw.writePNG, theOpt.stride)
    of JPEG:
      result = img.write_img_impl(byte, stbiw.writeJPG, theOpt.quality)
    of HDR:
      result = img.write_hdr_impl()
    else:
      raise newException(IIOError, "LERoSI-IIO: Unsupported image format " & $theOpt.format & ".")



# Public interface begin

proc newImageObject*[T](w, h: int; layout: ImageChannelLayout, order: ImageDataOrdering = OrderPlanar): ImageObject[T] {.noSideEffect, inline.} =
  let data: Tensor[T] =
    if order == OrderPlanar:
      zeros[T](layout.len, h, w)
    else:
      zeros[T](h, w, layout.len)

  result = ImageObject(data: data, layout: layout, order: order)


proc newImageObjectRaw*[T](data: seq[T], layout: ImageChannelLayout, order: ImageDataOrdering): ImageObject[T] {.noSideEffect, inline.} =
  ImageObject(data: data.toTensor, layout: layout, order: order)


proc to_planar*[T](image: ImageObject[T]): ImageObject[T] {.noSideEffect, inline.} =
  if image.order == OrderInterleaved:
    ImageObject(data: image.data.to_chw().asContiguous(), layout: image.layout, order: OrderPlanar)
  else:
    image


proc to_interleaved*[T](image: ImageObject[T]): ImageObject[T] {.noSideEffect, inline.} =
  if image.order == OrderPlanar:
    ImageObject(data: image.data.to_hwc().asContiguous(), layout: image.layout, order: OrderInterleaved)
  else:
    image



proc wrap_stbi_loadedlayout(channels: int): ImageChannelLayout {.noSideEffect, inline.} =
  result = case channels:
    of 1: CH_Y
    of 2: CH_YA
    of 3: CH_RGB
    of 4: CH_RGBA
    else: @[]


#proc wrap_stbi_getsavelayout(layout: ImageChannelLayout): ImageChannelLayout {.noSideEffect, inline.} =
#  result = case layout:
#    of CH_Y: CH_Y
#
#    of CH_YA: CH_YA
#    of CH_AY: CH_YA
#    
#    of CH_ARGB: CH_RGBA
#    of CH_RGBA: CH_RGBA
#
#    of CH_RGB:  CH_RGB
#    of CH_RGBX: CH_RGB
#    of CH_XRGB: CH_RGB
#
#    of CH_YUV:    CH_RGB
#    of CH_YCbCr:  CH_RGB


proc read*[T: SomeNumber](filename: string): ImageObject[T] =
  let data = filename.imageio_load_core()
  var img = ImageObject(data: data, layout: data.shape[^1].imageio_core_loadedlayout, order: OrderInterleaved)


proc read_hdr*[T: SomeReal](filename: string): ImageObject[T] =
  let data = filename.imageio_load_hdr_core()
  var img = ImageObject(data: data, layout: data.shape[^1].imageio_core_loadedlayout, order: OrderInterleaved)


proc write*[T](image: ImageObject[T], opts: SaveOptions = SaveOptions(nil)): seq[byte] =
  # TODO: Support swizzling channels
  imageio_save_core(image.to_interleaved().data, opts)



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

  echo "Writing HDR to memory to read back."
  let hdrseq = myhdrpic.imageio_save_core(SaveOptions(format: HDR))
  #echo hdrseq
  let myhdrpic2 = hdrseq.imageio_load_hdr_core()
  assert myhdrpic == myhdrpic2
  echo "Success!"

  myhdrpic *= 255.0
  echo "Scale for the rest of the bitmap test"

  echo "Write BMP from second HDR: ", myhdrpic.imageio_save_core("test/samplehdr2-out.bmp", SaveOptions(format: BMP))


#proc imageio_save*[T; U: SomeNumber](filename: string, data: openarray[U], w, h: int, options: set[T] = {IIO_DEFAULT_ENCODING}) =


#proc imageio_save_png*[T; U: SomeNumber](filename: string, data: openarray[U], w, h: int, options: set[T] = {IIO_DEFAULT_FORMAT}) {.inline, noSideEffect.} =
