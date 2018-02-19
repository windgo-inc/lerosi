# MIT License
# 
# Copyright (c) 2018 WINDGO, Inc.
# Low Energy Retrieval of Source Information
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

import macros, streams, os, system, sequtils, strutils, math, algorithm, future
import arraymancer

import ../macroutil
import ../spaceconf
import ../dataframe
import ../fixedseq

# import the generic backend module
import ../backend

import ./picio_detail
include ./stb_bindings

export picio_detail.PicIOError

export fixedseq, spaceconf, dataframe


proc picio_load_core_file_impl[T](
    filename: string; h, w, ch: var int; result: var seq[T]) =

  const desired_ch = 0.cint
  var innerh, innerw, innerch: cint

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


proc picio_load_core_data_impl[T](
    data_in: string|openarray[byte]; h, w, ch: var int, result: var seq[T]) =

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


template picio_load_core_checks(T: typedesc; itype, load_body: untyped): untyped =
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
          badmsg = "LERoSI/PicIO: HDR format must be loaded " &
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
          raise newException(ValueError, "LERoSI/PicIO: " & badmsg)
        else:
          raise newException(PicIOError, "LERoSI/PicIO: Unsupported image format: " & $itype)
      else:
        static:
          assert(false,
            "LERoSI/PicIO: image must be loaded with a numeric data type.")

    except STBIException:
      raise newException(PicIOError, "LERoSI/PicIO: Backend: " & getCurrentException().msg)
    except IOError:
      raise newException(PicIOError, "LERoSI/PicIO: I/O: " & getCurrentException().msg)
    except SystemError:
      raise newException(PicIOError, "LERoSI/PicIO: System: " & getCurrentException().msg)


proc picio_load_core3_data_by_type*[T; U](
    data: openarray[T];
    h, w, ch: var int;
    result: var seq[U]) =

  # Detect image type.
  let itype = data.picio_check_format()

  # Check to ensure the return type matches the expected type for this picture.
  #picio_load_core_checks(U, itype):
  # load the data.
  picio_load_core_data_impl(data, h, w, ch, result)


template picio_load_core2*[T](
    data: seq[T];
    h, w, ch: var int): seq[byte] =

  block:
    var res: seq[byte]
    picio_load_core3_data_by_type[T, byte](data, h, w, ch, res)
    res


template picio_load_core2*[T](
    U: typedesc; data: seq[T];
    h, w, ch: var int): untyped =

  block:
    var res: seq[U]
    picio_load_core3_data_by_type[T, U](data, h, w, ch, res)
    res


proc picio_load_core3_data_by_type*[U](
    data: string,
    h, w, ch: var int, result: var seq[U]) =

  let
    # Detect image type.
    itype = picio_check_format(cast[seq[byte]](data[0..min(high(data), 32)]))

  # Check to ensure the return type matches the expected type for this picture.
  #picio_load_core_checks(U, itype):
  # load the data.
  picio_load_core_data_impl(data, h, w, ch, result)


template picio_loadstring_core2*(
    data: string;
    h, w, ch: var int): seq[byte] =

  block:
    var res: seq[byte]
    picio_load_core3_data_by_type[byte](data, h, w, ch, res)
    res


template picio_loadstring_core2*(
    U: typedesc;
    data: string;
    h, w, ch: var int): untyped =

  block:
    var res: seq[U]
    picio_load_core3_data_by_type[U](data, h, w, ch, res)
    res


proc picio_load_core3_file_by_type*[U](
    filename: string;
    h, w, ch: var int;
    result: var seq[U]) =

  # Detect image type.
  let itype = filename.picio_check_format()

  # Check to ensure the return type matches the expected type for this picture.
  #picio_load_core_checks(U, itype):
  # load the data.
  picio_load_core_file_impl(filename, h, w, ch, result)


template picio_load_core2*(
    filename: string;
    h, w, ch: var int): seq[byte] =

  block:
    var res: seq[byte]
    picio_load_core3_file_by_type[byte](filename, h, w, ch, res)
    res


template picio_load_core2*(
    U: typedesc; filename: string;
    h, w, ch: var int): untyped =

  block:
    var res: seq[U]
    picio_load_core3_file_by_type[U](filename, h, w, ch, res)
    res


## Forward ported 2018/02/13
template picio_load_core_impl(resource: untyped, T: typedesc): untyped =
  block:
    var h, w, ch: int
    let pixels = picio_load_core2(resource, h, w, ch)
    var im1 = newTensorUninit[T]([h, w, ch])
    for i in 0..<pixels.len:
      im1.data[i] = pixels[i]
    im1

template picio_loadstring_core_impl(resource: string, T: typedesc): untyped =
  block:
    var h, w, ch: int
    let pixels = picio_loadstring_core2(resource, h, w, ch)
    var im1 = newTensorUninit[T]([h, w, ch])
    for i in 0..<pixels.len:
      im1.data[i] = pixels[i]
    im1


proc picio_load_core*[T](data: seq[T]): BackendType("*", byte) {.deprecated.} =
  result.backend_data(data.picio_load_core_impl(byte))


proc picio_loadstring_core*(data: string): BackendType("*", byte) {.deprecated.} =
  result.backend_data(data.picio_loadstring_core_impl(byte))


proc picio_load_core*(filename: string): BackendType("*", byte) {.deprecated.} =
  result.backend_data(filename.picio_load_core_impl(byte))


proc picio_load_hdr_core2*[T](data: seq[T]; h, w, ch: var int): seq[cfloat] =
  picio_load_core3_data_by_type(data, h, w, ch, result)


proc picio_loadstring_hdr_core2*(data: string; h, w, ch: var int): seq[cfloat] =
  picio_load_core3_data_by_type(data, h, w, ch, result)


proc picio_load_hdr_core2*(filename: string; h, w, ch: var int): seq[cfloat] =
  picio_load_core3_file_by_type(filename, h, w, ch, result)


proc picio_load_core*[T](data: seq[T]): BackendType("*", cfloat) {.deprecated.} =
  var h, w, ch: int
  var loaded = picio_load_hdr_core2(data, h, w, ch)
  result.backend_data_raw(loaded, [h, w, ch])


proc picio_loadstring_hdr_core*(data: string): BackendType("*", cfloat) {.deprecated.} =
  var h, w, ch: int
  var loaded = picio_loadstring_hdr_core2(data, h, w, ch)
  result.backend_data_raw(loaded, [h, w, ch])


proc picio_load_hdr_core*(filename: string): BackendType("*", cfloat) {.deprecated.} =
  var h, w, ch: int
  var loaded = picio_load_hdr_core2(filename, h, w, ch)
  result.backend_data_raw(loaded, [h, w, ch])


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
        raise newException(PicIOError, "LERoSI/PicIO: Unsupported image format " & $opt.format & ".")
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
        raise newException(PicIOError, "LERoSI/PicIO: Unsupported image format " & $opt.format & ".")
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


# TODO: Merge picio_save_core variants using a macro.
# TODO: Rewrite to work with sequences.

template handle_load_error2(data, res: untyped): untyped =
  block:
    let x = bool(res)
    if not x:
      raise newException(PicIOError,
        "LERoSI/PicIO: Error writing frame @" &
        $cast[int](data[0].unsafeAddr) & " to sequence.")

proc picio_save_core2*[T](data: seq[T];
    h, w, ch: int;
    filename: string;
    opt: SaveOptions = SaveOptions(nil)): bool =

  var dataRef: seq[T]
  shallowCopy dataRef, data
  # this prevents a deep copy but permits getting the address because dataRef
  # is a variable.

  result = write_img_impl(dataRef[0].unsafeAddr, h, w, ch, filename, opt)
  handle_load_error2(dataRef, result)


proc picio_savestring_core2*[T](data: seq[T];
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

template picio_save_core2*[T](data: seq[T];
    h, w, ch: int;
    opt: SaveOptions = SaveOptions(nil)): seq[byte] =
  cast[seq[byte]](picio_savestring_core2(data, h, w, ch, opt))


# New interface 2018/02/13
# Forward ported 2018/02/14
proc picio_save_core*[T](img: BackendType("am", T),
    filename: string,
    saveOpt: SaveOptions = SaveOptions(nil)): bool {.deprecated, inline.} =

  let
    tens = img.backend_data().asContiguous()
    h = tens.shape[^3]
    w = tens.shape[^2]
    ch = tens.shape[^1]

  picio_save_core2(tens.data, h, w, ch, filename, saveOpt)

proc picio_save_core_legacy[T](img: BackendType("am", T),
    saveOpt: SaveOptions = SaveOptions(nil)): string {.inline.} =
  let
    tens = img.backend_data().asContiguous()
    h = tens.shape[^3]
    w = tens.shape[^2]
    ch = tens.shape[^1]

  picio_savestring_core2(tens.data, h, w, ch, saveOpt)

proc picio_savestring_core*[T](img: BackendType("am", T),
    saveOpt: SaveOptions = SaveOptions(nil)): string {.deprecated.} =
  picio_save_core_legacy(img, saveOpt)

proc picio_save_core*[T](img: BackendType("am", T),
    saveOpt: SaveOptions = SaveOptions(nil)): seq[byte] {.deprecated.} =
  cast[seq[byte]](picio_save_core_legacy(img, saveOpt))

{.deprecated: [
  imageio_load_core3_data_by_type:  picio_load_core3_data_by_type,
  imageio_load_core3_file_by_type:  picio_load_core3_file_by_type,
  imageio_load_core2:               picio_load_core2,
  imageio_load_hdr_core2:           picio_load_hdr_core2,
  imageio_load_core:                picio_load_core,
  imageio_load_hdr_core:            picio_load_hdr_core,
  imageio_loadstring_core2:         picio_loadstring_core2,
  imageio_loadstring_hdr_core2:     picio_loadstring_hdr_core2,
  imageio_loadstring_core:          picio_loadstring_core,
  imageio_loadstring_hdr_core:      picio_loadstring_hdr_core
].}

