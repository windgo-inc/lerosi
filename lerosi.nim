import macros, streams, os, system, sequtils, strutils, math, algorithm, future
import imghdr, arraymancer

import lerosi/iio_types
import lerosi/iio_core
import lerosi/fixedseq
import lerosi/channels

export channels, iio_types

const
  loaded_channel_layouts = [ChLayoutYp.id,ChLayoutYpA.id,ChLayoutRGB.id,ChLayoutRGBA.id]

# TODO: Full rework.
# Public interface begin

proc newImageObject*[T](w, h: int; layout: ChannelLayout, order: ImageDataOrdering = OrderPlanar): ImageObject[T] {.noSideEffect, inline.} =
  let data: Tensor[T] =
    if order == OrderPlanar:
      zeros[T](layout.len, h, w)
    else:
      zeros[T](h, w, layout.len)

  result = ImageObject(data: data, layout: layout, order: order)


proc newImageObjectRaw*[T](data: seq[T], layout: ChannelLayout, order: ImageDataOrdering): ImageObject[T] {.noSideEffect, inline.} =
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


proc wrap_stbi_loadedlayout_ranged(channels: range[1..4]): ChannelLayoutId {.noSideEffect, inline, raises: [].} =
  result = loaded_channel_layouts[channels - 1]


proc wrap_stbi_loadedlayout(channels: int): ChannelLayoutId {.noSideEffect, inline.} =
  if channels >= 1 and channels <= 4:
    # Compiler has proof that channels is in range by getting here.
    result = wrap_stbi_loadedlayout_ranged(channels)
  else:
    raise newException(IIOError, "wrap_stbi_loadedlayout: Channel count must be between 1 and 4.")


proc read*[T: SomeNumber](filename: string): ImageObject[T] =
  let data = filename.imageio_load_core()
  var img = ImageObject(data: data, layout: data.shape[^1].imageio_core_loadedlayout().id, order: OrderInterleaved)


proc read_hdr*[T: SomeReal](filename: string): ImageObject[T] =
  let data = filename.imageio_load_hdr_core()
  var img = ImageObject(data: data, layout: data.shape[^1].imageio_core_loadedlayout().id, order: OrderInterleaved)


proc write*[T](image: ImageObject[T], opts: SaveOptions = SaveOptions(nil)): seq[byte] =
  imageio_save_core(image.to_interleaved().data, opts)


