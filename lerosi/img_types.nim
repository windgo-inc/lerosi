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

proc init_image_storage(img: var SomeImage,
    cspace: ColorSpace = ColorSpaceIdAny,
    # cspace argument has no effect on static colorspace images.
    order: DataOrder = DataPlanar,
    # order argument has no effect on static ordered images.
    dim: openarray[int] = [1])
    {.imageMutator.} =

  let
    nchans = colorspace_len(
      when has_static_colorspace(img): img.S
      else: cspace)

  when is_dynamic_ordered(img):
    img.order = order
 
  when has_dynamic_colorspace(img):
    img.cspace = cspace

  case img.storage_order:
  of DataPlanar:
    img.dat = newTensorUninit[T]([nchans].toMetadataArray & dim.toMetadataArray)
  of DataInterleaved:
    img.dat = newTensorUninit[T](dim.toMetadataArray & [nchans].toMetadataArray)


when isMainModule:
  import typetraits

  template image_init_test(T: untyped; order, cspace: untyped): untyped =
    var img: T
    echo " : init_image_storage on type ", T.name
    init_image_storage(img, cspace, order, dim=[6, 6])
    echo "img.storage_order = ", img.storage_order
    echo "img.colorspace = ", img.colorspace
    echo "img.data.shape = ", img.data.shape
    echo "img.data = ", img.data

  template statictype_image_init_test(T, S, O: untyped): untyped =
    image_init_test(StaticOrderImage[T, ColorSpaceTypeAny, O], O, colorspace_id(S))

  template dynamictype_image_init_test(T, S, O: untyped): untyped =
    image_init_test(DynamicOrderImage[T, ColorSpaceTypeAny], O, colorspace_id(S))

  template statictype_scs_image_init_test(T, S, O: untyped): untyped =
    image_init_test(StaticOrderImage[T, S, O], O, colorspace_id(S))

  template dynamictype_scs_image_init_test(T, S, O: untyped): untyped =
    image_init_test(DynamicOrderImage[T, S], O, colorspace_id(S))

  template has_subspace_test(sp1, sp2, expect: untyped): untyped =
    echo $(sp1), ".colorspace_has_subspace(", $(sp2), ") = ", sp1.colorspace_has_subspace(sp2)
    if sp1.colorspace_has_subspace(sp2) == expect:
      echo " [ok]"
    else:
      echo " [expected ", $(expect), "]"


  template image_statictype_test(datatype, cspace, order: untyped): untyped =
    var img: StaticOrderImage[datatype, cspace, order]
    echo type(img).name, " :"
    echo "  T = ", type(img.T).name
    echo "  S = ", type(img.S).name
    echo "  O = ", $(img.O)

    when cspace is ColorSpaceTypeAny:
      echo "do: img.colorspace = ", ColorSpaceIdYpCbCr
      img.colorspace = ColorSpaceIdYpCbCr
      echo "{OK} assignment over dynamic colorspace succeeded expectedly."
    else:
      try:
        img.colorspace = ColorSpaceIdYpCbCr
      except:
        echo "{OK} assignment over static colorspace failed expectedly."

    echo "img.storage_order = ", img.storage_order
    echo "img.colorspace = ", img.colorspace


  template image_dynamictype_test(datatype, cspace, order: untyped): untyped =
    var img: DynamicOrderImage[datatype, cspace]
    echo type(img).name, " :"
    echo "  T = ", type(img.T).name
    echo "  S = ", type(img.S).name

    when cspace is ColorSpaceTypeAny:
      echo "do: img.colorspace = ", ColorSpaceIdYpCbCr
      img.colorspace = ColorSpaceIdYpCbCr
      echo "{OK} assignment over dynamic colorspace succeeded expectedly."
    else:
      try:
        img.colorspace = ColorSpaceIdYpCbCr
      except:
        echo "{OK} assignment over static colorspace failed expectedly."

    img.storage_order = order
    echo "img.storage_order = ", img.storage_order
    echo "img.colorspace = ", img.colorspace

  template image_statictype_test_il(datatype, cspace: untyped): untyped =
    image_statictype_test(datatype, cspace, DataInterleaved)

  template image_statictype_test_pl(datatype, cspace: untyped): untyped =
    image_statictype_test(datatype, cspace, DataPlanar)

  template image_dynamictype_test_il(datatype, cspace: untyped): untyped =
    image_dynamictype_test(datatype, cspace, DataInterleaved)

  template image_dynamictype_test_pl(datatype, cspace: untyped): untyped =
    image_dynamictype_test(datatype, cspace, DataPlanar)


  template has_subspace_test_suite(): untyped =
    has_subspace_test(ColorSpaceTypeRGB, ColorSpaceTypeRGBA, false)
    has_subspace_test(ColorSpaceTypeRGB, ColorSpaceTypeRGB, true)
    has_subspace_test(ColorSpaceTypeRGB, ColorSpaceTypeRG, true)
    has_subspace_test(ColorSpaceTypeRGB, ColorSpaceTypeGB, true)
    has_subspace_test(ColorSpaceTypeRGB, ColorSpaceTypeRB, true)
    has_subspace_test(ColorSpaceTypeRGB, ColorSpaceTypeRBA, false)

  static:
    echo " *** compile-time tests ***"

    echo " ~ subcolorspace inclusion test ~"
    has_subspace_test_suite()

    echo " ~ StaticOrderImage compile-time access tests ~"
    image_statictype_test_il(byte, ColorSpaceTypeRGB)
    image_statictype_test_pl(byte, ColorSpaceTypeRGB)
    image_statictype_test_il(byte, ColorSpaceTypeCMYe)
    image_statictype_test_pl(byte, ColorSpaceTypeCMYe)
    image_statictype_test_il(byte, ColorSpaceTypeAny)
    image_statictype_test_pl(byte, ColorSpaceTypeAny)

    echo " ~ DynamicOrderImage compile-time access tests ~"
    image_dynamictype_test_il(byte, ColorSpaceTypeRGB)
    image_dynamictype_test_pl(byte, ColorSpaceTypeRGB)
    image_dynamictype_test_il(byte, ColorSpaceTypeCMYe)
    image_dynamictype_test_pl(byte, ColorSpaceTypeCMYe)
    image_dynamictype_test_il(byte, ColorSpaceTypeAny)
    image_dynamictype_test_pl(byte, ColorSpaceTypeAny)

  echo " ~ run-time tests ~"
  has_subspace_test_suite()

  echo " ~ StaticOrderImage run-time access tests ~"
  image_statictype_test_il(byte, ColorSpaceTypeRGB)
  image_statictype_test_pl(byte, ColorSpaceTypeRGB)
  image_statictype_test_il(byte, ColorSpaceTypeCMYe)
  image_statictype_test_pl(byte, ColorSpaceTypeCMYe)
  image_statictype_test_il(byte, ColorSpaceTypeAny)
  image_statictype_test_pl(byte, ColorSpaceTypeAny)

  echo " ~ DynamicOrderImage run-time access tests ~"
  image_dynamictype_test_il(byte, ColorSpaceTypeRGB)
  image_dynamictype_test_pl(byte, ColorSpaceTypeRGB)
  image_dynamictype_test_il(byte, ColorSpaceTypeCMYe)
  image_dynamictype_test_pl(byte, ColorSpaceTypeCMYe)
  image_dynamictype_test_il(byte, ColorSpaceTypeAny)
  image_dynamictype_test_pl(byte, ColorSpaceTypeAny)

  echo " ~ StaticOrderImage initialization (dynamic colorspace) ~"
  statictype_image_init_test(byte, ColorSpaceTypeRGB, DataPlanar)
  statictype_image_init_test(byte, ColorSpaceTypeRGB, DataInterleaved)
  statictype_image_init_test(byte, ColorSpaceTypeCMYe, DataPlanar)
  statictype_image_init_test(byte, ColorSpaceTypeCMYe, DataInterleaved)
  statictype_image_init_test(byte, ColorSpaceTypeYpCbCr, DataPlanar)
  statictype_image_init_test(byte, ColorSpaceTypeYpCbCr, DataInterleaved)

  echo " ~ DynamicOrderImage initialization (dynamic colorspace) ~"
  dynamictype_image_init_test(byte, ColorSpaceTypeRGB, DataPlanar)
  dynamictype_image_init_test(byte, ColorSpaceTypeRGB, DataInterleaved)
  dynamictype_image_init_test(byte, ColorSpaceTypeCMYe, DataPlanar)
  dynamictype_image_init_test(byte, ColorSpaceTypeCMYe, DataInterleaved)
  dynamictype_image_init_test(byte, ColorSpaceTypeYpCbCr, DataPlanar)
  dynamictype_image_init_test(byte, ColorSpaceTypeYpCbCr, DataInterleaved)

  echo " ~ StaticOrderImage initialization (static colorspace) ~"
  statictype_scs_image_init_test(byte, ColorSpaceTypeRGB, DataPlanar)
  statictype_scs_image_init_test(byte, ColorSpaceTypeRGB, DataInterleaved)
  statictype_scs_image_init_test(byte, ColorSpaceTypeCMYe, DataPlanar)
  statictype_scs_image_init_test(byte, ColorSpaceTypeCMYe, DataInterleaved)
  statictype_scs_image_init_test(byte, ColorSpaceTypeYpCbCr, DataPlanar)
  statictype_scs_image_init_test(byte, ColorSpaceTypeYpCbCr, DataInterleaved)

  echo " ~ DynamicOrderImage initialization (static colorspace) ~"
  dynamictype_scs_image_init_test(byte, ColorSpaceTypeRGB, DataPlanar)
  dynamictype_scs_image_init_test(byte, ColorSpaceTypeRGB, DataInterleaved)
  dynamictype_scs_image_init_test(byte, ColorSpaceTypeCMYe, DataPlanar)
  dynamictype_scs_image_init_test(byte, ColorSpaceTypeCMYe, DataInterleaved)
  dynamictype_scs_image_init_test(byte, ColorSpaceTypeYpCbCr, DataPlanar)
  dynamictype_scs_image_init_test(byte, ColorSpaceTypeYpCbCr, DataInterleaved)


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


