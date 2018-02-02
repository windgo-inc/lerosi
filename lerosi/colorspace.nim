import macros, streams, os, system, sequtils, strutils, math, algorithm, future
import arraymancer, typetraits

import ./iio_types
import ./iio_core
import ./fixedseq
import ./channels
import ./img_permute
import ./macroutil

template pl_slicer(tens, i: untyped): untyped = tens[i,_]
template il_slicer(tens, i: untyped): untyped = tens[_,_,i]

template pl_slice_asgn(tens, i, x: untyped): untyped = tens[i,_] = x
template il_slice_asgn(tens, i, x: untyped): untyped = tens[_,_,i] = x

template ch_copy1_impl(src, i, dest, j, asgn, slcr, op: untyped): untyped =
  asgn(dest, j, op(slcr(src, i)))

template ch_copyn(src, dest, imapper, asgn, slcr, op: untyped): untyped =
  for j, i in imapper: ch_copy1_impl(src, i, dest, j, asgn, slcr, op)

template pl_copy(copier, src, dest, imap, slcr, op: untyped): untyped =
  copier(src, dest, imap, pl_slice_asgn, slcr, op)

template il_copy(copier, src, dest, imap, slcr, op: untyped): untyped =
  copier(src, dest, imap, il_slice_asgn, slcr, op)

template pslc_noop(x: untyped): untyped = x

template src_copy_impl(copier, order, copyfn, pl_op, il_op, src, dest, imap: untyped): untyped =
  if order == OrderPlanar:
    copyfn(copier, src, dest, imap, pl_slicer, pl_op)
  else:
    copyfn(copier, src, dest, imap, il_slicer, il_op)

template ch_copy(copier, src, srcOrder, dest, destOrder, imap: untyped): untyped =
  if destOrder == OrderPlanar:
    src_copy_impl(copier, srcOrder, pl_copy, pslc_noop, to_chw, src, dest, imap)
  else:
    src_copy_impl(copier, srcOrder, il_copy, to_hwc, pslc_noop, src, dest, imap)

template copyChannelsTo*(srcImg, destImg: untyped): untyped =
  ch_copy(ch_copyn, srcImg.data, srcImg.order,
    destImg.data, destImg.order, cmpChannels(srcImg, destImg))

{.deprecated: [copyChannels: copyChannelsTo].}

#macro channelCopier*(): untyped =

template copyChannelsFrom*(destImg, srcImg: untyped): untyped =
  copyChannelsTo(srcImg, destImg)

proc cstImpl(name, channelsIn: NimNode, body: NimNode): NimNode {.compileTime.} =
  var stmts = newStmtList()
  for chin in items(capitalTokens(nodeToStr(channelsIn))):
    let chproc = ident("Ch" & chin)
    let chname = ident(chin)
    let chidx = ident("index_" & chin)
    stmts.add(newLetStmt(chidx, newCall(chproc, [ident"input"])))

  body.copyChildrenTo(stmts)
  result = newProc(newNimNode(nnkPostfix).add(ident"*", name))
  result.params = newNimNode(nnkIdentDefs).add(ident"input", bindSym"auto")
  result.pragma = newNimNode(nnkPragma).add(ident"compileTime")
  result.body = stmts

macro colorSpaceTransform*(name, channelsIn: untyped, body: untyped): untyped =
  result = cstImpl(name, channelsIn, body)
    
colorSpaceTransform(RGB2BGR, "RGB"): echo indexR, indexG, indexB


