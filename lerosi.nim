import macros, os, system, sequtils, strutils, math, algorithm, future
import imghdr, nimPNG, arraymancer

import stb_image/read as stbi
import stb_image/write as stbiw




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
    d.map_inline:
      body
  else:
    d.map do (x: U) -> T:
      body


template lerosiRenormalized*[D: ImageData](img: D, T: typedesc, form: ChannelForm = TypeDefaultForm, form2: ChannelForm = TypeDefaultForm): untyped =
  img.lerosiMap:
    renormalized(x, form, form2)


const
  IIO_STOR_UINT8 = 0x1
  IIO_STOR_FLOAT_UNIT = 0x2
  IIO_STOR_FLOAT_POSITIVE = 0x4

  IIO_CH_ZA   = 0x0008
  IIO_CH_AZ   = 0x0010
  IIO_CH_ZX   = 0x0020
  IIO_CH_XZ   = 0x0040

  IIO_ORD_V    = 0x0100
  IIO_ORD_RGB* = 0x0200
  IIO_ORD_BGR* = 0x0400

  IIO_DEFAULT_FORMAT* = {IIO_STOR_UINT8, IIO_ORD_RGB, IIO_CH_ZA}


proc interpret_string[T](data: openarray[T]): string {.noSideEffect.} =
  ## Convert a an array of raw data to a string by reinterpretation.
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
  ## Convert a string in to an array of integers by reinterpretation.
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



proc imageio_check_format(filename: string): ImageType =
  ## Check the image format stored within a file.
  testImage(filename)


proc imageio_check_format*[T](data: openarray[T]): ImageType =
  ## Check the image format stored within core memory.
  testImage(data[0..31].toType(int8))


proc hwc2chw*[T](img: Tensor[T]): Tensor[T] =
  ## Convert image from HxWxC convetion to the CxHxW convention,
  ## where C,W,H stands for channels, width, height, note that this library
  ## only works with CxHxW images for optimization and internal usage reasons
  ## using CxHxW for images is also a common approach in deep learning
  img.permute(2, 0, 1)

proc chw2hwc*[T](img: Tensor[T]): Tensor[T] =
  ## Convert image from CxHxW convetion to the HxWxC convention,
  ## where C,W,H stands for channels, width, height, note that this library
  ## only works with CxHxW images for optimization and internal usage reasons
  ## using CxHxW for images is also a common approach in deep learning
  img.permute(1, 2, 0)



proc imageio_load*[T; U: string|openarray](resource: U, w, h, ch: var int, options: set[T] = IIO_DEFAULT_FORMAT): seq[uint8] =
  ## Load an image from a file or memory
  
  # Detect image type.
  let itype = resource.imageio_check_format(resource)

  # Select loader.
  if itype in {BMP, PNG, JPEG, TGA, HDR}:
    try:
      let pixels = stbi.load(resource, w, h, ch, 4)
      result = pixels.toTensor().reshape([h, w, ch]).hwc2chw().asContiguous()
  else:
    w = 0
    h = 0
    result.setLen(0)
    raise newException(IIOError, "IIO: Unsupported image data format: " & $itype)

#proc imageio_save*[T; U: SomeNumber](filename: string, data: openarray[U], w, h: int, options: set[T] = {IIO_DEFAULT_ENCODING}) =


#proc imageio_save_png*[T; U: SomeNumber](filename: string, data: openarray[U], w, h: int, options: set[T] = {IIO_DEFAULT_FORMAT}) {.inline, noSideEffect.} =
