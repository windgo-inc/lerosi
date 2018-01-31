import macros, streams, os, system, sequtils, strutils, math, algorithm, future
import arraymancer

import ./iio_types
import ./iio_core
import ./fixedseq
import ./channels
#import ./colorspace

const
  loaded_channel_layouts = [
    ChLayoutYp.id, ChLayoutYpA.id,
    ChLayoutRGB.id, ChLayoutRGBA.id
  ]


proc wrap_stbi_loadedlayout_ranged(channels: range[1..4]):
                        ChannelLayoutId {.noSideEffect, inline, raises: [].} =
  result = loaded_channel_layouts[channels - 1]


proc wrap_stbi_loadedlayout(channels: int):
                        ChannelLayoutId {.noSideEffect, inline.} =
  if channels >= 1 and channels <= 4:
    # Compiler has proof that channels is in range by getting here.
    result = wrap_stbi_loadedlayout_ranged(channels)
  else:
    raise newException(IIOError,
      "wrap_stbi_loadedlayout: Channel count must be between 1 and 4.")


proc readImage*[T: SomeNumber](filename: string): DynamicLayoutImageRef[T] =
  let data = filename.imageio_load_core()
  newDynamicLayoutImageRaw[T](data.asType(T),
    data.shape[^1].wrap_stbi_loadedlayout(),
    OrderInterleaved)

proc readHdrImage*[T: SomeReal](filename: string): DynamicLayoutImageRef[T] =
  let data = filename.imageio_load_hdr_core()
  newDynamicLayoutImageRaw[T](data.asType(T),
    data.shape[^1].wrap_stbi_loadedlayout(),
    OrderInterleaved)

proc writeImage*[O: ImageObjectRef](image: O;
               opts: SaveOptions = SaveOptions(nil)): seq[byte] =
  imageio_save_core(interleaved(image).data, opts)

proc writeImage*[O: ImageObjectRef](image: O;
               filename: string;
               opts: SaveOptions = SaveOptions(nil)): bool =
  imageio_save_core(interleaved(image).data, filename, opts)


