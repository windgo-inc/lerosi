import macros, os, system, sequtils, strutils, math, algorithm, future
import imghdr, nimPNG, arraymancer


# Incorporate ujpeg.c
{.compile: "ujpeg.c".}



type
  ChannelForm = enum
    ## Floating point channel encoding forms
    NormalizedPositiveForm, NormalizedUnitForm

const
  TypeDefaultForm = NormalizedPositiveForm ## The default floating point encoding form



type
  ImageData*[T] = openarray[T]|Tensor[T]


type ImageType* = imghdr.ImageType ## Image format enumeration.


type
  IIOError* = object of Exception


# μJPEG image type is a generic pointer
type
  ujImage = pointer



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
  let c = E(high(I)) / 2.E
  result = I((x + 1.E) * c)


proc normalIntToPos[I: SomeInteger, E: SomeReal](x: I): E {.inline, noSideEffect.} =
  x.E / E(high(I))


proc normalIntToUnit[I: SomeInteger, E: SomeReal](x: I): E {.inline, noSideEffect.} =
  let c = E(high(I)) / 2.E
  result = (x.E / c) - 1.E



template lerosiRenormalized*[U: SomeNumber](d: U, T: typedesc, form: ChannelForm = TypeDefaultForm, form2: ChannelForm = TypeDefaultForm): untyped =
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
    d.map_inline:
      body
  else:
    d.map do (x: U) -> T:
      body


template lerosiRenormalized*[D: ImageData](img: D, T: typedesc, form: ChannelForm = TypeDefaultForm, form2: ChannelForm = TypeDefaultForm): untyped =
  img.lerosiMap:
    renormalized(x, form, form2)


const
  IIO_RGB24* = 0x1
  IIO_RGBA32* = 0x2

  IIO_DEFAULT_FORMAT* = IIO_RGBA32

  IIO_ENCODE_PNG = 0x100 

  IIO_DEFAULT_ENCODING* = IIO_ENCODE_PNG


proc interpret_string[T](data: openarray[T]): string {.noSideEffect.} =
  ## Convert a an array of raw data to a string.
  when sizeof(T) > 1:
    # TODO Untested
    result = newStringOfCap(len(data) * sizeof(T))
    for dat in data:
      var bytes = cast[ptr char](addr(dat))
      for i in 0..<sizeof(T):
        result.add(bytes[i])
  else:
    result = newStringOfCap(len(data))
    for ch in data:
      result.add(ch.char)


template interpret_string(data: string): string = data


template interpret_array(data: string, T: typedesc): untyped =
  ## Convert a string in to an array of integers.
  when sizeof(T) > 1:
    # TODO Untested
    block:
      var
        sq = @[]
        acc: array[sizeof(T), char]
        ctr = 0

      for ch in data:
        acc[ctr] = ch
        inc ctr
        if ctr == sizeof(T):
          ctr = 0
          sq.add(cast[ptr T](acc))
    
      if ctr < sizeof(T):
        for i in ctr..<sizeof(T):
          acc[i] = 0

        sq.add(cast[ptr T](acc)[])

      sq
  else:
    block:
      var sq: seq[T] = @[]
      for ch in data:
        sq.add(T(ch))

      sq

template interpret_array[T](data: openarray[T], U: typedesc): untyped =
  ## Reinterpret an array safely.
  data.interpret_string().interpret_array(U)


# μJPEG library bindings.
proc ujCreate() : ujImage {.cdecl, importc: "ujCreate".}
proc ujDecode(img: ujImage, data: ptr cuchar, size: int) : ujImage {.cdecl, importc: "ujDecode".}
proc ujDecodeFile(img: ujImage, filename: cstring) : ujImage {.cdecl, importc: "ujDecodeFile".}
proc ujGetWidth(img: ujImage) : int {.cdecl, importc: "ujGetWidth".}
proc ujGetHeight(img: ujImage) : int {.cdecl, importc: "ujGetHeight".}
proc ujGetImageSize(img: ujImage) : int {.cdecl, importc: "ujGetImageSize".}
proc ujGetImage(img: ujImage, dest: cstring) : cstring {.cdecl, importc: "ujGetImage".}
proc ujDestroy(img: ujImage) {.cdecl, importc: "ujDestroy".}



proc imageio_check_format(filename: string): ImageType =
  ## Check the image format stored within a file.
  testImage(filename)


proc imageio_check_format*[T](data: openarray[T]): ImageType =
  ## Check the image format stored within core memory.
  testImage(data[0..31].toType(int8))


# TODO Use macros to collapse the two versions of load_png

proc imageio_load_png*[T](filename: string, w, h: var int, options: set[T] = {IIO_DEFAULT_FORMAT}): seq[uint8] =
  ## Load a PNG image from a file.
  var r: PNGResult
  if options.contains(IIO_RGBA32):
    r = loadPNG32(filename)
  elif options.contains(IIO_RGB24):
    r = loadPNG24(filename)
  else:
    raise newException(IIOError, "IIO-PNG: Unrecognized decoder (in-file) output format requested.")

  result = r.data.interpret_array(uint8)
  w = r.width
  h = r.height


proc imageio_load_png*[T; U: SomeInteger](data: openarray[U], w, h: var int, options: set[T] = {IIO_DEFAULT_FORMAT}): seq[uint8] =
  ## Load a PNG image from core.
  var r: PNGResult
  if options.contains(IIO_RGBA32):
    r = decodePNG32(data.interpret_string())
  elif options.contains(IIO_RGB24):
    r = decodePNG24(data.interpret_string())
  else:
    raise newException(IIOError, "IIO-PNG: Unrecognized decoder (in-core) output format requested.")

  result = r.data.interpret_array(uint8)
  w = r.width
  h = r.height


proc imageio_save_string_png[T](filename, data: string, w, h: int, options: set[T] = {IIO_DEFAULT_FORMAT}) =
  ## Save a png to a file
  if options.contains(IIO_RGBA32):
    discard savePNG32(filename, data, w, h)
  elif options.contains(IIO_RGB24):
    discard savePNG24(filename, data, w, h)
  else:
    raise newException(IIOError, "IIO-PNG: Unrecognized encoder (in-core) output format requested.")

# TODO Remove intermediate buffers
proc imageio_save_uint8_png[T](filename: string, data: openarray[uint8], w, h: int, options: set[T] = {IIO_DEFAULT_FORMAT}) {.inline, noSideEffect.} =
  ## Save a png to a file
  imageio_save_string_png(filename, data.interpret_string(), w, h, options)

proc imageio_save_png*[T; U: SomeNumber](filename: string, data: openarray[U], w, h: int, options: set[T] = {IIO_DEFAULT_FORMAT}) {.inline, noSideEffect.} =
  imageio_save_uint8_png(filename, data.toType(uint8), w, h, options)

proc imageio_load*[T; U: string|openarray](resource: U, w, h: var int, options: set[T] = {IIO_DEFAULT_FORMAT}): seq[uint8] =
  ## Load an image from a file or memory
  
  # Detect image type.
  let itype = resource.imageio_check_format(resource)

  # Select loader.
  if itype == PNG:
    result = resource.imageio_load_png(w, h, options)
  else:
    w = 0
    h = 0
    result.setLen(0)
    raise newException(IIOError, "IIO: Unsupported image data format: " & $itype)

#proc imageio_save*[T; U: SomeNumber](filename: string, data: openarray[U], w, h: int, options: set[T] = {IIO_DEFAULT_ENCODING}) =


#proc imageio_save_png*[T; U: SomeNumber](filename: string, data: openarray[U], w, h: int, options: set[T] = {IIO_DEFAULT_FORMAT}) {.inline, noSideEffect.} =
