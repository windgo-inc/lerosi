import macros, streams, os, system, sequtils, strutils, math, algorithm, future
import arraymancer

import ./iio_types
import ./iio_core
import ./fixedseq
import ./channels
import ./img_permute

template pl_slicer(tens, i: untyped): untyped = tens[i,_]
template il_slicer(tens, i: untyped): untyped = tens[_,_,i]

template pl_slice_asgn(tens, i, x: untyped): untyped = tens[i,_] = x
template il_slice_asgn(tens, i, x: untyped): untyped = tens[_,_,i] = x

template ch_copy_impl(src, dest, imap, asgn, slcr, op: untyped): untyped =
  for dest_i, src_i in pairs(imap):
    if src_i >= 0:
      let x = slcr(src, src_i)
      asgn(dest, dest_i, op(x))

template pl_copy_impl(src, dest, imap, slcr, op: untyped): untyped =
  ch_copy_impl(src, dest, imap, pl_slice_asgn, slcr, op)
template il_copy_impl(src, dest, imap, slcr, op: untyped): untyped =
  ch_copy_impl(src, dest, imap, il_slice_asgn, slcr, op)

template pslc_noop(x: untyped): untyped = x

template ch_copy(src, srcOrder, dest, destOrder, imap: untyped): untyped =
  case destOrder:
    of OrderPlanar:
      case srcOrder:
        of OrderPlanar:      pl_copy_impl(src, dest, imap, pl_slicer, pslc_noop)
        of OrderInterleaved: pl_copy_impl(src, dest, imap, il_slicer, to_chw)
    of OrderInterleaved:
      case srcOrder:
        of OrderPlanar:      il_copy_impl(src, dest, imap, pl_slicer, to_hwc)
        of OrderInterleaved: il_copy_impl(src, dest, imap, il_slicer, pslc_noop)


template copyChannelsTo*(srcImg, destImg: untyped): untyped =
  ch_copy(
    srcImg.data,  srcImg.order,
    destImg.data, destImg.order,
    cmpChannels(srcImg.layoutId, destImg.layoutId)
  )

{.deprecated: [copyChannels: copyChannelsTo].}

template copyChannelsFrom*(destImg, srcImg: untyped): untyped =
  copyChannelsTo(srcImg, destImg)



