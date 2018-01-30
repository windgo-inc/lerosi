import macros, streams, os, system, sequtils, strutils, math, algorithm, future
import imghdr, arraymancer

import ./iio_types
import ./fixedseq
import ./channels

import stb_image/read as stbi
import stb_image/write as stbiw

export arraymancer, channels, fixedseq, iio_types

template toType*[U](d: openarray[U], T: typedesc): untyped =
  ## Convert from one array type to another. In the case that the target type
  ## is the same as the current array type
  when T is U and U is T: d else: map(d, proc (x: U): T = T(x))


proc imageio_check_format*(filename: string): ImageType =
  ## Check the image format stored within a file.
  testImage(filename)


proc imageio_check_format*[T](data: openarray[T]): ImageType =
  ## Check the image format stored within core memory.
  var header: seq[int8]
  newSeq(header, 32)
  copyMem(header[0].addr, data[0].unsafeAddr, 32)
  testImage(header)


template imageio_load_core*(resource: untyped): Tensor[byte] =
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

      
        var im1 = newTensorUninit[byte]([h, w, ch])
        for i, pix in pixels:
          im1.data[i] = pixels[i]
        #let im2 = im1.reshape([h, w, ch])
        res = im1
        #res = pixels.toTensor().reshape([h, w, ch]).asType(byte)
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



template imageio_load_hdr_core*(resource: untyped): Tensor[float32] =
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

proc imageio_save_core*[T](img: Tensor[T], filename: string, saveOpt: SaveOptions = SaveOptions(nil)): bool =
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


proc imageio_save_core*[T](img: Tensor[T], saveOpt: SaveOptions = SaveOptions(nil)): seq[byte] =
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
