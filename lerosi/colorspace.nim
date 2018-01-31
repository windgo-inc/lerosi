import macros, streams, os, system, sequtils, strutils, math, algorithm, future
import arraymancer

import ./iio_types
import ./iio_core
import ./fixedseq
import ./channels

template copyChannelsPlanarImpl(srcTensor, destTensor, indexMap: untyped): untyped =
  echo "shapes src.shape=", srcTensor.shape, " dest.shape=", destTensor.shape
  for dest_i, src_i in pairs(indexMap):
    if src_i >= 0:
      echo "copy src channel ", src_i, " to dest channel ", dest_i
      destTensor[dest_i, _] = srcTensor[src_i, _]

template copyChannelsInterleavedImpl(srcTensor, destTensor, indexMap: untyped): untyped =
  for dest_i, src_i in pairs(indexMap):
    if src_i >= 0:
      destTensor[_, _, dest_i] = srcTensor[_, _, src_i]

template copyChannelsImpl(srcImg, destImg, indexMap: untyped): untyped =
  destImg.setOrdering(srcImg.order)
  case srcImg.order:
    of OrderPlanar:      copyChannelsPlanarImpl(srcImg.data, destImg.data, indexMap)
    of OrderInterleaved: copyChannelsInterleavedImpl(srcImg.data, destImg.data, indexMap)

template copyChannelsTo*(srcImg, destImg: untyped): untyped =
  copyChannelsImpl(srcImg, destImg, cmpChannels(srcImg.layoutId, destImg.layoutId))

{.deprecated: [copyChannels: copyChannelsTo].}

template copyChannelsFrom*(destImg, srcImg: untyped): untyped =
  copyChannelsTo(srcImg, destImg)



