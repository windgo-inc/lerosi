import macros, streams, os, system, sequtils, strutils, math, algorithm, future
import arraymancer

import ./img_types
import ./iio_core
import ./fixedseq
#import ./channels
#import ./channelspace

const
  loaded_channel_layouts = [
    ChannelSpaceIdYp, ChannelSpaceIdYpA,
    ChannelSpaceIdRGB, ChannelSpaceIdRGBA
  ]


proc wrap_stbi_loadedlayout_ranged(channels: range[1..4]):
    ChannelSpace {.noSideEffect, inline, raises: [].} =
  loaded_channel_layouts[channels - 1]


proc wrap_stbi_loadedlayout(channels: int):
    ChannelSpace {.noSideEffect, inline.} =

  if channels >= 1 and channels <= 4:
    # Compiler has proof that channels is in range by getting here.
    result = wrap_stbi_loadedlayout_ranged(channels)
  else:
    raise newException(IIOError,
      "wrap_stbi_loadedlayout: Channel count must be between 1 and 4.")


proc readImage*[T: SomeNumber](filename: string): StaticOrderFrame[T, ChannelSpaceTypeAny, DataInterleaved] =
  let data = filename.imageio_load_core
  init_image_storage(result, wrap_stbi_loadedlayout(data.shape[^1]), data=data.asType(T))

proc readImage*[T: SomeNumber](resource: openarray[byte]): StaticOrderFrame[T, ChannelSpaceTypeAny, DataInterleaved] =
  let data = resource.imageio_load_core
  init_image_storage(result, wrap_stbi_loadedlayout(data.shape[^1]), data=data.asType(T))

proc readHdrImage*[T: SomeReal](filename: string): StaticOrderFrame[T, ChannelSpaceTypeAny, DataInterleaved] =
  let data = filename.imageio_load_hdr_core
  init_image_storage(result, wrap_stbi_loadedlayout(data.shape[^1]), data=data.asType(T))

proc readHdrImage*[T: SomeReal](resource: openarray[byte]): StaticOrderFrame[T, ChannelSpaceTypeAny, DataInterleaved] =
  let data = resource.imageio_load_hdr_core
  init_image_storage(result, wrap_stbi_loadedlayout(data.shape[^1]), data=data.asType(T))

proc writeImage*(image: SomeImage;
                opts: SaveOptions = SaveOptions(nil)):
                seq[byte] {.imageProc.} =
  imageio_save_core(interleaved(image).data, opts)

proc writeImage*(image: SomeImage;
                filename: string;
                opts: SaveOptions = SaveOptions(nil)):
                bool {.imageProc.} =
  imageio_save_core(interleaved(image).data, filename, opts)



