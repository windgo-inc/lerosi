import macros, sequtils, strutils, tables, future
import system, arraymancer

import ./macroutil
import ./fixedseq
import ./img_permute
import ./img_conf

type
  StaticOrderImage*[T; S; O: static[DataOrder]] = object
    dat: Tensor[T]
    cspace: ColorSpace

  DynamicOrderImage*[T; S] = object
    dat: Tensor[T]
    cspace: ColorSpace
    order: DataOrder

  SomeImage* = distinct int


include ./img_accessor

macro imageGetter*(targetProc: untyped): untyped =
  result = imageAccessor(targetProc, false)

macro imageMutator*(targetProc: untyped): untyped =
  result = imageAccessor(targetProc, true)

proc data*(img: SomeImage): auto {.imageGetter.} = img.dat

proc `data=`*(img: var SomeImage, data: AnyTensor[T]) {.imageMutator.} =
  if data.shape == img.dat.shape:
    img.dat = data
  else:
    raise newException(ValueError,
      "New tensor is of shape " & $(data.shape) &
      " but image requires shape " & $(img.dat.shape))

proc inplaceReorder(img: var SomeImage, order: DataOrder) {.imageMutator.} =
  discard

proc storage_order*(img: SomeImage): DataOrder {.imageGetter.} =
  when isStaticTarget: O else: img.order

proc colorspace*(img: SomeImage): ColorSpace {.imageGetter.} =
  when not (S is ColorSpaceTypeAny): S.colorspace_id
  else: img.cspace

template is_static_ordered*[T: StaticOrderImage](img: T): bool = true
template is_static_ordered*[T: DynamicOrderImage](img: T): bool = false

template is_dynamic_ordered*[T: StaticOrderImage](img: T): bool = false
template is_dynamic_ordered*[T: DynamicOrderImage](img: T): bool = true

template has_static_colorspace*[T; S; O: static[DataOrder]](
    img: StaticOrderImage[T, S, O]): bool =

  when not (S is ColorSpaceTypeAny): true else: false

template has_static_colorspace*[T; S](img: DynamicOrderImage[T, S]): bool =
  when not (S is ColorSpaceTypeAny): true else: false

template has_dynamic_colorspace*(img: untyped): untyped =
  (not has_static_colorspace(img))

proc `storage_order=`*(img: var DynamicOrderImage, order: DataOrder)
    {.inline, raises: [].} =
  img.inplaceReorder(order)
  img.order = order

proc `colorspace=`*(img: var SomeImage, cspace: ColorSpace) {.imageMutator.} =
  when not (S is ColorSpaceTypeAny):
    raise newException(Exception,
      "Cannot set the colorspace on a static colorspace object.")
  else:
    img.cspace = cspace

proc dataShape*(img: SomeImage): MetadataArray {.imageGetter.} = img.dat.shape

proc extent*(img: SomeImage, i: int): range[1..high(int)] {.imageGetter.} =
  when is_static_ordered(img):
    when O == DataPlanar: img.dataShape[i + 1]
    elif O == DataInterleaved: img.dataShape[i]
  else:
    case img.storage_order:
      of DataPlanar: img.dataShape[i + 1]
      of DataInterleaved: img.dataShape[i]

proc extent*(img: SomeImage): MetadataArray {.imageGetter.} =
  when is_static_ordered(img):
    when O == DataPlanar: img.dataShape[1..high(img.dataShape)]
    elif O == DataInterleaved: img.dataShape[0..high(img.dataShape)-1]
  else:
    case img.storage_order:
      of DataPlanar: img.dataShape[1..high(img.dataShape)]
      of DataInterleaved: img.dataShape[0..high(img.dataShape)-1]

proc dim*(img: SomeImage): int {.imageGetter.} =
  img.dataShape.len - 1
  when is_static_ordered(img):
    when O == DataPlanar: [1..high(img.dataShape)]
    elif O == DataInterleaved: img.dataShape[0..high(img.dataShape)-1]
  else:
    case img.storage_order:
      of DataPlanar: img.dataShape[1..high(img.dataShape)]
      of DataInterleaved: img.dataShape[0..high(img.dataShape)-1]

proc init_image_storage*(img: var SomeImage,
    cspace: ColorSpace = ColorSpaceIdAny,
    # cspace argument has no effect on static colorspace images.
    order: DataOrder = DataPlanar,
    # order argument has no effect on static ordered images.
    dim: MetadataArray)
    {.imageMutator.} =

  when has_static_colorspace(img):
    const nchans = colorspace_len(img.S)
  else:
    let nchans = colorspace_len(cspace)

  when is_dynamic_ordered(img):
    img.order = order
  when has_dynamic_colorspace(img):
    img.cspace = cspace
  
  template doPlanarInit: untyped = toMetadataArray(nchans) & dim
  template doInterleavedInit: untyped = dim & nchans
  template computeShape: untyped =
    when is_static_ordered(img):
      when O == DataPlanar: doPlanarInit()
      elif O == DataInterleaved: doInterleavedInit()
    else:
      case img.storage_order:
        of DataPlanar: doPlanarInit()
        of DataInterleaved: doInterleavedInit()

  img.dat = newTensorUninit[T](computeShape())


when isMainModule:
  {.push checks: on.} # Thorough runtime bounds checking for the tests.
  include ./img_types_manualtests
  {.pop.}

#proc newDynamicLayoutImage*[T](w, h: int; lid: ChannelLayoutId;
#                        order: DataOrder = DataPlanar):
#                        DynamicLayoutImageRef[T] {.noSideEffect, inline.} =
#  let data: Tensor[T] =
#    if order == DataPlanar:
#      newTensorUninit[T]([lid.len, h, w])
#    else:
#      newTensorUninit[T]([h, w, lid.len])
#
#  result = DynamicLayoutImageRef[T](data: data, lid: lid, order: order)
#
#
#proc newStaticLayoutImage*[T; L: ChannelLayout](w, h: int;
#                        order: DataOrder = DataPlanar):
#                        StaticLayoutImageRef[T, L] {.noSideEffect, inline.} =
#  let data: Tensor[T] =
#    if order == DataPlanar:
#      newTensorUninit[T]([L.len, h, w])
#    else:
#      newTensorUninit[T]([h, w, L.len])
#
#  result = StaticLayoutImageRef[T, L](data: data, order: order)
#
#
#proc newDynamicLayoutImageRaw*[T](data: Tensor[T]; lid: ChannelLayoutId;
#                           order: DataOrder):
#                           DynamicLayoutImageRef[T] {.noSideEffect, inline.} =
#  DynamicLayoutImageRef[T](data: data, lid: lid, order: order)
#
#
#proc newDynamicLayoutImageRaw*[T](data: seq[T]; lid: ChannelLayoutId;
#                           order: DataOrder):
#                           DynamicLayoutImageRef[T] {.noSideEffect, inline.} =
#  newDynamicLayoutImageRaw[T](data.toTensor, lid, order)
#
#
#proc newStaticLayoutImageRaw*[T; L: ChannelLayout](data: Tensor[T];
#                           order: DataOrder):
#                           StaticLayoutImageRef[T, L] {.noSideEffect, inline.} =
#  StaticLayoutImageRef[T](data: data, order: order)
#
#
#proc newStaticLayoutImageRaw*[T; L: ChannelLayout](data: seq[T];
#                           order: DataOrder):
#                           StaticLayoutImageRef[T, L] {.noSideEffect, inline.} =
#  newStaticLayoutImageRaw[T](data.toTensor, order)
#
#
#proc shallowCopy*[O: DynamicLayoutImageRef](img: O): O {.noSideEffect, inline.} =
#  O(data: img.data, lid: img.layoutId, order: img.order)
#
#
#proc shallowCopy*[O: StaticLayoutImageRef](img: O): O {.noSideEffect, inline.} =
#  O(data: img.data, order: img.order)
#
#
## Renamed clone to shallowCopy because clone is not really a semantically
## correct name in the intuitive sense. A clone implies everything is
## duplicated, when in fact only the top level object fields are copied,
## and the data are not.
#{.deprecated: [clone: shallowCopy].}
#
#proc layoutId*[ImgT: DynamicLayoutImageRef](img: ImgT):
#              ChannelLayoutId {.noSideEffect, inline, raises: [].} =
#  img.lid
#
#proc layoutId*[ImgT: StaticLayoutImageRef](img: ImgT):
#              ChannelLayoutId {.noSideEffect, inline, raises: [].} =
#  ImgT.L.id
#
#
## We only have implicit conversions to dynamic layout images. Conversion to
## static layout must be explicit or else the user could unknowingly introduce
## unwanted colorspace conversions.
#converter toDynamicLayoutImage*[O: StaticLayoutImageRef](img: O):
#  DynamicLayoutImageRef[O.T] {.inline, raises: [].} =
#
#  DynamicLayoutImageRef[O.T](data: img.data, lid: img.layoutId, order: img.order)
#
#
#macro staticDynamicImageGetter(procname: untyped, returntype: untyped, inner: untyped): untyped =
#  result = quote do:
#    proc `procname`*[O: DynamicLayoutImageRef](img: O): `returntype` {.inline, noSideEffect.} =
#      ## Dynamic image channel layout variant of `procname`.
#      `inner`(img.lid)
#
#    proc `procname`*[O: StaticLayoutImageRef](img: O): `returntype` {.inline, noSideEffect, raises: [].} =
#      ## Static image channel layout variant of `procname`.
#      `inner`(O.L)
#
#
#staticDynamicImageGetter(channelLayoutLen, range[1..MAX_IMAGE_CHANNELS], len)
#staticDynamicImageGetter(channelLayoutName, string, name)
#staticDynamicImageGetter(channels, ChannelIdArray, channels)
#
#{.deprecated: [channelCount: channelLayoutLen].}
#
#
#proc width*[O: ImageRef](img: O): int {.inline, noSideEffect.} =
#  let shape = img.data.shape
#  case img.order:
#    of DataPlanar: shape[^1]
#    of DataInterleaved: shape[^2]
#
#
#proc height*[O: ImageRef](img: O): int {.inline, noSideEffect.} =
#  let shape = img.data.shape
#  case img.order:
#    of DataPlanar: shape[^2]
#    of DataInterleaved: shape[^3]
#
#
#proc planar*[O: ImageRef](image: O): O {.noSideEffect, inline.} =
#  if image.order == DataInterleaved:
#    result = image.shallowCopy
#    result.data = image.data.to_chw().asContiguous()
#    result.order = DataPlanar
#  else:
#    result = image
#
#
#proc interleaved*[O: ImageRef](image: O): O {.noSideEffect, inline.} =
#  if image.order == DataPlanar:
#    result = image.shallowCopy
#    result.data = image.data.to_hwc().asContiguous()
#    result.order = DataInterleaved
#  else:
#    result = image
#
#proc setOrdering*[O: ImageRef](image: var O, e: DataOrder) {.noSideEffect, inline.} =
#  if not (image.order == e):
#    image.order = e
#    if e == DataPlanar:
#      image.data = image.data.to_chw().asContiguous()
#    else:
#      image.data = image.data.to_hwc().asContiguous()


