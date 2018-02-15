import macros, streams, os, system, sequtils, strutils, math, algorithm, future
import imghdr, arraymancer

import ./macroutil
import ./spaceconf
import ./dataframe
import ./fixedseq
import ./backend/am

include ./detail/stb_bindings

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


proc imageio_load_core_file_impl[T](filename: string; h, w, ch: var int; result: var seq[T]) =
  const desired_ch = 0.cint
  var innerh, innerw, innerch: cint

  # TODO: replace the nim stbi.loadFromMemory procedure with a
  # direct usage of stb_image that forgoes the need of a dynamic
  # sequence, as is already done in the HDR routine below.
  when T is SomeInteger:
    var data = stbi_load(cstring(filename), innerw, innerh, innerch, desired_ch)
  elif T is SomeReal:
    var data = stbi_loadf(cstring(filename), innerw, innerh, innerch, desired_ch)
  else:
    static:
      assert false, "Image data type must be numeric!"

  h = innerh.int
  w = innerw.int
  ch = innerch.int

  newSeq(result, h*w*ch)
  copyMem(result[0].addr, data, result.len * sizeof(T))
  stbi_image_free(data)


#        when resource is string:
#          stbi_loadf(resource.cstring, innerw, innerh, innerch, desired_ch.cint)
#        else:
#          stbi_loadf_from_memory(
#            cast[ptr cuchar](resource[0].unsafeAddr),
#            resource.len.cint, innerw, innerh, innerch, desired_ch.cint)


proc imageio_load_core_data_impl[T](data_in: string|openarray[byte]; h, w, ch: var int, result: var seq[T]) =
  const desired_ch = 0.cint
  var innerh, innerw, innerch: cint

  when data_in is seq:
    var data_in_wrap: seq[cuchar]
    shallowCopy data_in_wrap, data_in
  elif data_in is openarray:
    var data_in_wrap: seq[cuchar]
    data_in_wrap = map(data_in, x => x.cuchar)
  else:
    var data_in_wrap: string
    shallowCopy data_in_wrap, data_in


  # TODO: replace the nim stbi.loadFromMemory procedure with a
  # direct usage of stb_image that forgoes the need of a dynamic
  # sequence, as is already done in the HDR routine below.
    when T is SomeInteger:
      var data = stbi_load_from_memory(data_in_wrap[0].unsafeAddr,
        cint(data_in.len * sizeof(data_in[0])),
        innerw, innerh, innerch, desired_ch.cint)
    elif T is SomeReal:
      var data = stbi_loadf_from_memory(data_in_wrap[0].unsafeAddr,
        cint(data_in.len * sizeof(data_in[0])),
        innerw, innerh, innerch, desired_ch.cint)


  h = innerh.int
  w = innerw.int
  ch = innerch.int

  newSeq(result, h*w*ch)
  copyMem(result[0].addr, data, result.len * sizeof(T))
  stbi_image_free(data)


template imageio_load_core_checks(T: typedesc; itype, load_body: untyped): untyped =
  block:
    try:
      when T is SomeInteger:
        const badset = {
          imghdr.ImageType.HDR
        }
        const goodset = {
          imghdr.ImageType.BMP,
          imghdr.ImageType.PNG,
          imghdr.ImageType.JPEG
        }
        const
          badmsg = "LERoSI/IIO: HDR format must be loaded " &
                   "with a floating point data type."
      elif T is SomeReal:
        const badmsg = ""
        const goodset = {}
        const goodset = {
          imghdr.ImageType.HDR,
          imghdr.ImageType.BMP,
          imghdr.ImageType.PNG,
          imghdr.ImageType.JPEG
        }

      # Determine whether the image type can be loaded given return type seq[T]
      when T is SomeNumber:
        case itype:
        of goodset:
          load_body
        of badset:
          raise newException(ValueError, "LERoSI/IIO: " & badmsg)
        else:
          raise newException(IIOError, "LERoSI/IIO: Unsupported image format: " & $itype)
      else:
        static:
          assert(false,
            "LERoSI/IIO: image must be loaded with a numeric data type.")

    except STBIException:
      raise newException(IIOError, "LERoSI/IIO: Backend: " & getCurrentException().msg)
    except IOError:
      raise newException(IIOError, "LERoSI/IIO: I/O: " & getCurrentException().msg)
    except SystemError:
      raise newException(IIOError, "LERoSI/IIO: System: " & getCurrentException().msg)


proc imageio_load_core3_data_by_type*[T; U](
    data: openarray[T];
    h, w, ch: var int;
    result: var seq[U]) =

  # Detect image type.
  let itype = data.imageio_check_format()

  # Check to ensure the return type matches the expected type for this picture.
  #imageio_load_core_checks(U, itype):
  # load the data.
  imageio_load_core_data_impl(data, h, w, ch, result)


template imageio_load_core2*[T](
    data: seq[T];
    h, w, ch: var int): seq[byte] =

  block:
    var res: seq[byte]
    imageio_load_core3_data_by_type[T, byte](data, h, w, ch, res)
    res


template imageio_load_core2*[T](
    U: typedesc; data: seq[T];
    h, w, ch: var int): untyped =

  block:
    var res: seq[U]
    imageio_load_core3_data_by_type[T, U](data, h, w, ch, res)
    res


proc imageio_load_core3_data_by_type*[U](
    data: string,
    h, w, ch: var int, result: var seq[U]) =

  let
    # Detect image type.
    itype = imageio_check_format(cast[seq[byte]](data[0..min(high(data), 32)]))

  # Check to ensure the return type matches the expected type for this picture.
  #imageio_load_core_checks(U, itype):
  # load the data.
  imageio_load_core_data_impl(data, h, w, ch, result)


template imageio_loadstring_core2*(
    data: string;
    h, w, ch: var int): seq[byte] =

  block:
    var res: seq[byte]
    imageio_load_core3_data_by_type[byte](data, h, w, ch, res)
    res


template imageio_loadstring_core2*(
    U: typedesc;
    data: string;
    h, w, ch: var int): untyped =

  block:
    var res: seq[U]
    imageio_load_core3_data_by_type[U](data, h, w, ch, res)
    res


proc imageio_load_core3_file_by_type*[U](
    filename: string;
    h, w, ch: var int;
    result: var seq[U]) =

  # Detect image type.
  let itype = filename.imageio_check_format()

  # Check to ensure the return type matches the expected type for this picture.
  #imageio_load_core_checks(U, itype):
  # load the data.
  imageio_load_core_file_impl(filename, h, w, ch, result)


template imageio_load_core2*(
    filename: string;
    h, w, ch: var int): seq[byte] =

  block:
    var res: seq[byte]
    imageio_load_core3_file_by_type[byte](filename, h, w, ch, res)
    res


template imageio_load_core2*(
    U: typedesc; filename: string;
    h, w, ch: var int): untyped =

  block:
    var res: seq[U]
    imageio_load_core3_file_by_type[U](filename, h, w, ch, res)
    res


## Forward ported 2018/02/13
template imageio_load_core_impl(resource: untyped, T: typedesc): untyped =
  block:
    var h, w, ch: int
    let pixels = imageio_load_core2(resource, h, w, ch)
    var im1 = newTensorUninit[T]([h, w, ch])
    for i in 0..<pixels.len:
      im1.data[i] = pixels[i]
    im1

template imageio_loadstring_core_impl(resource: string, T: typedesc): untyped =
  block:
    var h, w, ch: int
    let pixels = imageio_loadstring_core2(resource, h, w, ch)
    var im1 = newTensorUninit[T]([h, w, ch])
    for i in 0..<pixels.len:
      im1.data[i] = pixels[i]
    im1


proc imageio_load_core*[T](data: seq[T]): AmBackendCpu[byte] {.deprecated.} =
  result.backend_data(data.imageio_load_core_impl(byte))


proc imageio_loadstring_core*(data: string): AmBackendCpu[byte] {.deprecated.} =
  result.backend_data(data.imageio_loadstring_core_impl(byte))


proc imageio_load_core*(filename: string): AmBackendCpu[byte] {.deprecated.} =
  result.backend_data(filename.imageio_load_core_impl(byte))


proc imageio_load_hdr_core2*[T](data: seq[T]; h, w, ch: var int): seq[cfloat] =
  imageio_load_core3_data_by_type(data, h, w, ch, result)


proc imageio_loadstring_hdr_core2*(data: string; h, w, ch: var int): seq[cfloat] =
  imageio_load_core3_data_by_type(data, h, w, ch, result)


proc imageio_load_hdr_core2*(filename: string; h, w, ch: var int): seq[cfloat] =
  imageio_load_core3_file_by_type(filename, h, w, ch, result)


proc imageio_load_core*[T](data: seq[T]): AmBackendCpu[cfloat] {.deprecated.} =
  var h, w, ch: int
  var loaded = imageio_load_hdr_core2(data, h, w, ch)
  result.backend_data_raw(loaded, [h, w, ch])


proc imageio_loadstring_hdr_core*(data: string): AmBackendCpu[cfloat] {.deprecated.} =
  var h, w, ch: int
  var loaded = imageio_loadstring_hdr_core2(data, h, w, ch)
  result.backend_data_raw(loaded, [h, w, ch])


proc imageio_load_hdr_core*(filename: string): AmBackendCpu[cfloat] {.deprecated.} =
  var h, w, ch: int
  var loaded = imageio_load_hdr_core2(filename, h, w, ch)
  result.backend_data_raw(loaded, [h, w, ch])


## OLD CODE

#template imageio_load_hdr_core_bytes_impl(resource: untyped; h, w, ch: var int): seq[float32] =
#  block:
#    var res: seq[float32]
#    try:
#      # Detect image type.
#      let itype = resource.imageio_check_format()
#
#      # Select loader.
#      if not (itype == imghdr.ImageType.HDR):
#        raise newException(IIOError, "LERoSI-IIO-HDR: Not an HDR format - " & $itype)
#
#      const desired_ch = 0
#      var innerw, innerh, innerch: cint
#      # Translate from cint to int. Come on compiler, you know what to do about this.
#
#      let data: ptr cfloat =
#        when resource is string:
#          stbi_loadf(resource.cstring, innerw, innerh, innerch, desired_ch.cint)
#        else:
#          stbi_loadf_from_memory(
#            cast[ptr cuchar](resource[0].unsafeAddr),
#            resource.len.cint, innerw, innerh, innerch, desired_ch.cint)
#
#      h = innerh.int
#      w = innerw.int
#      ch = innerch.int
#      
#      # debate this step. it's slow. would it be better to return a pointer
#      # with a garbage collection hook?
#      newSeq(res, w*h*ch)
#      copyMem(res[0].addr, data, res.len * sizeof(cfloat))
#      stbi_image_free(data)
#
#    except STBIException:
#      raise newException(IIOError, "LERoSI-IIO-HDR: Backend: " & getCurrentException().msg)
#    except IOError:
#      raise newException(IIOError, "LERoSI-IIO-HDR: I/O: " & getCurrentException().msg)
#    except SystemError:
#      raise newException(IIOError, "LERoSI-IIO-HDR: System: " & getCurrentException().msg)
#
#    res
#
#
#proc imageio_load_hdr_core2*[T](data: openarray[T]; h, w, ch: var int): seq[float32] =
#  imageio_load_hdr_core_bytes_impl(data, h, w, ch)
#
#proc imageio_load_hdr_core2*(filename: string; h, w, ch: var int): seq[float32] =
#  imageio_load_hdr_core_bytes_impl(filename, h, w, ch)
#
#
## Forward ported 2018/02/13
#template imageio_load_hdr_core_legacy(resource: untyped): AmBackendCpu[float32] =
#  block:
#    var
#      res: AmBackendCpu[float32]
#      h, w, ch: int
#    let pixels = resource.imageio_load_hdr_core2(h, w, ch)
#    res.backend_data(pixels.toTensor().reshape([h, w, ch]).asType(float32).asContiguous())
#    res
#
#proc imageio_load_hdr_core*[T](data: openarray[T]): AmBackendCpu[float32] {.deprecated.} =
#  imageio_load_hdr_core_legacy(data)
#
#proc imageio_load_hdr_core*(filename: string): AmBackendCpu[float32] {.deprecated.} =
#  imageio_load_hdr_core_legacy(filename)


template write_img_impl_immediate(img: pointer; h, w, ch: int; filename: cstring): untyped =
  # Take the argument list as an untyped for forwarding.
  # Assume img, opt, and h, w, ch are defined.
  block:
    var res: bool
    case opt.format:
      of ImageFormat.PNG: res = stbi_write_png(filename, w.cint, h.cint, ch.cint, cast[ptr byte](img), opt.stride.cint) == 1
      of ImageFormat.JPEG: res = stbi_write_jpg(filename, w.cint, h.cint, ch.cint, cast[ptr byte](img), opt.quality.cint) == 1
      of ImageFormat.BMP: res = stbi_write_bmp(filename, w.cint, h.cint, ch.cint, cast[ptr byte](img)) == 1
      of ImageFormat.HDR: res = stbi_write_hdr(filename, w.cint, h.cint, ch.cint, cast[ptr cfloat](img)) == 1
      else:
        raise newException(IIOError, "LERoSI-IIO: Unsupported image format " & $opt.format & ".")
    res

template write_img_tofunc_impl_immediate(img: pointer; h, w, ch: int; seqwri, buf: untyped): untyped =
  # Take the argument list as an untyped for forwarding.
  # Assume img, opt, and h, w, ch are defined.
  block:
    var res: bool
    case opt.format:
      of ImageFormat.PNG: res = stbi_write_png_to_func(seqwri, buf.addr, w.cint, h.cint, ch.cint, cast[ptr byte](img), opt.stride.cint) == 1
      of ImageFormat.JPEG: res = stbi_write_jpg_to_func(seqwri, buf.addr, w.cint, h.cint, ch.cint, cast[ptr byte](img), opt.quality.cint) == 1
      of ImageFormat.BMP: res = stbi_write_bmp_to_func(seqwri, buf.addr, w.cint, h.cint, ch.cint, cast[ptr byte](img)) == 1
      of ImageFormat.HDR: res = stbi_write_hdr_to_func(seqwri, buf.addr, w.cint, h.cint, ch.cint, cast[ptr cfloat](img)) == 1
      else:
        raise newException(IIOError, "LERoSI-IIO: Unsupported image format " & $opt.format & ".")
    res

proc sequence_write(context, data: pointer, size: cint) {.cdecl.} =
  if size > 0:
    let wbuf = cast[ptr StringStream](context)
    wbuf[].writeData(data, size)

proc write_img_impl(img: pointer; h, w, ch: int; filename: string; opt: SaveOptions): bool {.inline.} =
  # Needs img, opt, and h, w, ch
  write_img_impl_immediate(img, h, w, ch, filename.cstring)

proc write_img_impl(img: pointer; h, w, ch: int; buf: var StringStream; opt: SaveOptions): bool {.inline.} =
  # Needs img, opt, and h, w, ch
  write_img_tofunc_impl_immediate(img, h, w, ch, sequence_write, buf)


# TODO: Merge imageio_save_core variants using a macro.
# TODO: Rewrite to work with sequences.

template handle_load_error2(data, res: untyped): untyped =
  block:
    let x = bool(res)
    if not x:
      raise newException(IIOError,
        "LERoSI-IIO: Error writing frame @" &
        $cast[int](data[0].unsafeAddr) & " to sequence.")

proc imageio_save_core2*[T](data: seq[T];
    h, w, ch: int;
    filename: string;
    opt: SaveOptions = SaveOptions(nil)): bool =

  var dataRef: seq[T]
  shallowCopy dataRef, data
  # this prevents a deep copy but permits getting the address because dataRef
  # is a variable.

  result = write_img_impl(dataRef[0].unsafeAddr, h, w, ch, filename, opt)
  handle_load_error2(dataRef, result)


proc imageio_savestring_core2*[T](data: seq[T];
    h, w, ch: int;
    opt: SaveOptions = SaveOptions(nil)): string =

  var sink = newStringStream() # This will handle the result buffer
  var dataRef: seq[T]
  shallowCopy dataRef, data
  # this prevents a deep copy but permits getting the address because dataRef
  # is a variable.

  handle_load_error2 dataRef:
    write_img_impl(dataRef[0].unsafeAddr, h, w, ch, sink, opt)
  result = sink.data

template imageio_save_core2*[T](data: seq[T];
    h, w, ch: int;
    opt: SaveOptions = SaveOptions(nil)): seq[byte] =
  cast[seq[byte]](imageio_savestring_core2(data, h, w, ch, opt))


# New interface 2018/02/13
# Forward ported 2018/02/14
proc imageio_save_core*[T](img: AmBackendCpu[T],
    filename: string,
    saveOpt: SaveOptions = SaveOptions(nil)): bool {.deprecated, inline.} =

  let
    tens = img.backend_data().asContiguous()
    h = tens.shape[^3]
    w = tens.shape[^2]
    ch = tens.shape[^1]

  imageio_save_core2(tens.data, h, w, ch, filename, saveOpt)

proc imageio_save_core_legacy[T](img: AmBackendCpu[T],
    saveOpt: SaveOptions = SaveOptions(nil)): string {.inline.} =
  let
    tens = img.backend_data().asContiguous()
    h = tens.shape[^3]
    w = tens.shape[^2]
    ch = tens.shape[^1]

  imageio_savestring_core2(tens.data, h, w, ch, saveOpt)

proc imageio_savestring_core*[T](img: AmBackendCpu[T],
    saveOpt: SaveOptions = SaveOptions(nil)): string {.deprecated.} =
  imageio_save_core_legacy(img, saveOpt)

proc imageio_save_core*[T](img: AmBackendCpu[T],
    saveOpt: SaveOptions = SaveOptions(nil)): seq[byte] {.deprecated.} =
  cast[seq[byte]](imageio_save_core_legacy(img, saveOpt))
