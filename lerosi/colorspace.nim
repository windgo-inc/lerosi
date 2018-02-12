import macros, system, sequtils, strutils, math, future
import arraymancer

# TODO: Update this and rename for the purpose of channel mapping facilities.
#       Explore methodologies which might enable an in-place swizzle.
#       Explore channelspace conversions using broadcasted operators in order
#       to maximize exploitation of the backend's batching and caching, in
#       recognition that more than one backend will ultimately be required.

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

template pl_copy(src, dest, imap, slcr, op: untyped): untyped =
  ch_copy_impl(src, dest, imap, pl_slice_asgn, slcr, op)
template il_copy(src, dest, imap, slcr, op: untyped): untyped =
  ch_copy_impl(src, dest, imap, il_slice_asgn, slcr, op)

#template pslc_noop(x: untyped): untyped = x
#
#template src_copy_impl(order, copyfn, pl_op, il_op, src, dest, imap: untyped): untyped =
#  if order == OrderPlanar:
#    copyfn(src, dest, imap, pl_slicer, pl_op)
#  else:
#    copyfn(src, dest, imap, il_slicer, il_op)
#
#template ch_copy(src, srcOrder, dest, destOrder, imap: untyped): untyped =
#  if destOrder == OrderPlanar:
#    src_copy_impl(srcOrder, pl_copy, pslc_noop, to_chw, src, dest, imap)
#  else:
#    src_copy_impl(srcOrder, il_copy, to_hwc, pslc_noop, src, dest, imap)
#
#template copyChannelsTo*(srcImg, destImg: untyped): untyped =
#  ch_copy(
#    srcImg.data,  srcImg.order,
#    destImg.data, destImg.order,
#    cmpChannels(srcImg, destImg)
#  )
#
#{.deprecated: [copyChannels: copyChannelsTo].}
#
#template copyChannelsFrom*(destImg, srcImg: untyped): untyped =
#  copyChannelsTo(srcImg, destImg)



