import macros, streams, os, system, sequtils, strutils, math, algorithm, future
import imghdr, arraymancer

import ./spaceconf
import ./dataframe
import ./fixedseq
import ./backend/am

import stb_image/read as stbi
import stb_image/write as stbiw

export fixedseq, spaceconf, dataframe

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


template imageio_load_core_bytes_impl(resource: untyped; h, w, ch: var int): seq[byte] =
  ## Load an image from a file or memory
  block:
    var res: seq[byte]
    try:
      # Detect image type.
      let itype = resource.imageio_check_format()

      # Select loader.
      case itype:
      of imghdr.ImageType.HDR:
        raise newException(IIOError, "LERoSI-IIO: HDR format must be loaded through the image_load_hdr interface.")
      of {imghdr.ImageType.BMP, imghdr.ImageType.PNG, imghdr.ImageType.JPEG}:
        const desired_ch = 0

        # TODO: replace the nim stbi.loadFromMemory procedure with a
        # direct usage of stb_image that forgoes the need of a dynamic
        # sequence, as is already done in the HDR routine below.
        let
          pixels =
            when resource is string:
              # resource is interpreted as a filename if it is a string.
              stbi.load(resource, w, h, ch, desired_ch)
            else:
              when resource is seq:
                # resource is interpreted as an encoded image if it is an openarray
                stbi.loadFromMemory(resource.toType(byte), w, h, ch, desired_ch)
              else:
                (block:
                  let seqResource = @(resource)
                  stbi.loadFromMemory(seqResource.toType(byte), w, h, ch, desired_ch))

        res = pixels
      else:
        raise newException(IIOError, "LERoSI-IIO: Unsupported image format: " & $itype)

    except STBIException:
      raise newException(IIOError, "LERoSI-IIO: Backend: " & getCurrentException().msg)
    except IOError:
      raise newException(IIOError, "LERoSI-IIO: I/O: " & getCurrentException().msg)
    except SystemError:
      raise newException(IIOError, "LERoSI-IIO: System: " & getCurrentException().msg)

    res


proc imageio_load_core2*[T](data: openarray[T]; h, w, ch: var int): seq[byte] =
  data.imageio_load_core_bytes_impl(h, w, ch)


proc imageio_load_core2*(filename: string, h, w, ch: var int): seq[byte] =
  filename.imageio_load_core_bytes_impl(h, w, ch)


# Forward ported 2018/02/13
template imageio_load_core_impl(resource: untyped): Tensor[byte] =
  block:
    var h, w, ch: int
    let pixels = imageio_load_core2(resource, h, w, ch)
    var im1 = newTensorUninit[byte]([h, w, ch])
    for i in 0..<pixels.len:
      im1.data[i] = pixels[i]
    im1


proc imageio_load_core*[T](data: openarray[T]): AmBackendCpu[byte] {.deprecated.} =
  result.backend_data(data.imageio_load_core_impl)


proc imageio_load_core*(filename: string): AmBackendCpu[byte] {.deprecated.} =
  result.backend_data(filename.imageio_load_core_impl)


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



template imageio_load_hdr_core_bytes_impl(resource: untyped; h, w, ch: var int): seq[float32] =
  block:
    var res: seq[float32]
    try:
      # Detect image type.
      let itype = resource.imageio_check_format()

      # Select loader.
      if not (itype == imghdr.ImageType.HDR):
        raise newException(IIOError, "LERoSI-IIO-HDR: Not an HDR format - " & $itype)

      const desired_ch = 0
      var innerw, innerh, innerch: cint
      # Translate from cint to int. Come on compiler, you know what to do about this.

      let data: ptr cfloat =
        when resource is string:
          stbi_loadf(resource.cstring, innerw, innerh, innerch, desired_ch.cint)
        else:
          stbi_loadf_from_memory(
            cast[ptr cuchar](resource[0].unsafeAddr),
            resource.len.cint, innerw, innerh, innerch, desired_ch.cint)

      h = innerh.int
      w = innerw.int
      ch = innerch.int
      
      newSeq(res, w*h*ch)
      copyMem(res[0].addr, data, res.len * sizeof(cfloat))
      stbi_image_free(data)

    except STBIException:
      raise newException(IIOError, "LERoSI-IIO-HDR: Backend: " & getCurrentException().msg)
    except IOError:
      raise newException(IIOError, "LERoSI-IIO-HDR: I/O: " & getCurrentException().msg)
    except SystemError:
      raise newException(IIOError, "LERoSI-IIO-HDR: System: " & getCurrentException().msg)

    res


proc imageio_load_hdr_core2*[T](data: openarray[T]; h, w, ch: var int): seq[float32] =
  imageio_load_hdr_core_bytes_impl(data, h, w, ch)

proc imageio_load_hdr_core2*(filename: string; h, w, ch: var int): seq[float32] =
  imageio_load_hdr_core_bytes_impl(filename, h, w, ch)


# Forward ported 2018/02/13
template imageio_load_hdr_core_impl(resource: untyped): AmBackendCpu[float32] =
  block:
    var
      res: AmBackendCpu[float32]
      h, w, ch: int
    let pixels = resource.imageio_load_hdr_core2(h, w, ch)
    res.backend_data(pixels.toTensor().reshape([h, w, ch]).asType(float32).asContiguous())
    res

proc imageio_load_hdr_core*[T](data: openarray[T]): AmBackendCpu[float32] {.deprecated.} =
  imageio_load_hdr_core_impl(data)

proc imageio_load_hdr_core*(filename: string): AmBackendCpu[float32] {.deprecated.} =
  imageio_load_hdr_core_impl(filename)


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
# TODO: Rewrite to work with sequences.
#
proc imageio_save_core_am[T](img: Tensor[T];
    filename: string;
    saveOpt: SaveOptions = SaveOptions(nil)): bool =

  let opt = if saveOpt == nil: SaveOptions(format: BMP) else: saveOpt

  case opt.format:
    of BMP:
      result = img.write_img_impl(byte, filename, stbiw.writeBMP)
    of PNG:
      result = img.write_img_impl(byte, filename, stbiw.writePNG, opt.stride)
    of JPEG:
      result = img.write_img_impl(byte, filename, stbiw.writeJPG, opt.quality)
    of HDR:
      result = img.write_hdr_impl(filename)
    else:
      raise newException(IIOError, "LERoSI-IIO: Unsupported image format " & $opt.format & ".")


proc imageio_save_core_am[T](img: Tensor[T];
    saveOpt: SaveOptions = SaveOptions(nil)): seq[byte] =

  let opt = if saveOpt == nil: SaveOptions(format: BMP) else: saveOpt

  case opt.format:
    of BMP:
      result = img.write_img_impl(byte, stbiw.writeBMP)
    of PNG:
      result = img.write_img_impl(byte, stbiw.writePNG, opt.stride)
    of JPEG:
      result = img.write_img_impl(byte, stbiw.writeJPG, opt.quality)
    of HDR:
      result = img.write_hdr_impl()
    else:
      raise newException(IIOError, "LERoSI-IIO: Unsupported image format " & $opt.format & ".")


proc imageio_save_core*[T](img: AmBackendCpu[T],
    filename: string,
    saveOpt: SaveOptions = SaveOptions(nil)): bool {.deprecated.} =
  imageio_save_core_am(img.backend_data(), filename, saveOpt)

proc imageio_save_core*[T](img: AmBackendCpu[T],
    saveOpt: SaveOptions = SaveOptions(nil)): seq[byte] {.deprecated.} =
  imageio_save_core_am(img.backend_data(), saveOpt)

# New interface 2018/02/13
proc imageio_save_core2*[T](img: seq[T];
    h, w, ch: int;
    filename: string;
    saveOpt: SaveOptions = SaveOptions(nil)): bool =
  imageio_save_core_am(img.toTensor().reshape([h, w, ch]), filename, saveOpt)

proc imageio_save_core2*[T](img: seq[T];
    h, w, ch: int;
    saveOpt: SaveOptions = SaveOptions(nil)): seq[byte] =
  imageio_save_core_am(img.toTensor().reshape([h, w, ch]), saveOpt)

