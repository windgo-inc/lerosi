
import system, arraymancer
import ./channels

type
  ImageFormat* = enum
    PNG, BMP, JPEG, HDR
  SaveOptions* = ref object
    case format*: ImageFormat
    of PNG:
      stride*: int
    of JPEG:
      quality*: int
    else:
      discard

  ImageDataOrdering* = enum
    OrderInterleaved,
    OrderPlanar

  ImageData*[T] = openarray[T] or AnyTensor[T]

  ImageObject*[T] = object of RootObj
    order*: ImageDataOrdering
    data*: Tensor[T]

  ImageObjectRef*[T] = ref ImageObject[T]

  DynamicLayoutImage*[T] = object of ImageObject[T]
    lid: ChannelLayoutId

  StaticLayoutImage*[T; L: ChannelLayout] = object of ImageObject[T]

  DynamicLayoutImageRef*[T] = ref DynamicLayoutImage[T]
  StaticLayoutImageRef*[T; L: ChannelLayout] = ref StaticLayoutImage[T, L]

  IIOError* = object of Exception



proc newDynamicLayoutImage*[T](w, h: int; lid: ChannelLayoutId;
                        order: ImageDataOrdering = OrderPlanar):
                        DynamicLayoutImageRef[T] {.noSideEffect, inline.} =
  let data: Tensor[T] =
    if order == OrderPlanar:
      newTensorUninit[T]([lid.len, h, w])
    else:
      newTensorUninit[T]([h, w, lid.len])

  result = DynamicLayoutImage[T](data: data, lid: lid, order: order)


proc newStaticLayoutImage*[T; L: ChannelLayout](w, h: int;
                        order: ImageDataOrdering = OrderPlanar):
                        StaticLayoutImageRef[T, L] {.noSideEffect, inline.} =
  let data: Tensor[T] =
    if order == OrderPlanar:
      newTensorUninit[T]([L.len, h, w])
    else:
      newTensorUninit[T]([h, w, L.len])

  result = StaticLayoutImage[T, L](data: data, order: order)


proc newDynamicLayoutImageRaw*[T](data: Tensor[T]; lid: ChannelLayoutId;
                           order: ImageDataOrdering):
                           DynamicLayoutImageRef[T] {.noSideEffect, inline.} =
  DynamicLayoutImageRef[T](data: data, lid: lid, order: order)


proc newDynamicLayoutImageRaw*[T](data: seq[T]; lid: ChannelLayoutId;
                           order: ImageDataOrdering):
                           DynamicLayoutImageRef[T] {.noSideEffect, inline.} =
  newDynamicLayoutImageRaw[T](data.toTensor, lid, order)


proc newStaticLayoutImageRaw*[T; L: ChannelLayout](data: Tensor[T];
                           order: ImageDataOrdering):
                           StaticLayoutImageRef[T, L] {.noSideEffect, inline.} =
  StaticLayoutImageRef[T](data: data, order: order)


proc newStaticLayoutImageRaw*[T; L: ChannelLayout](data: seq[T];
                           order: ImageDataOrdering):
                           StaticLayoutImageRef[T, L] {.noSideEffect, inline.} =
  newStaticLayoutImageRaw[T](data.toTensor, order)


proc clone*[O: DynamicLayoutImageRef](img: O): O {.noSideEffect, inline.} =
  O(data: img.data, lid: img.layoutId, order: img.order)


proc clone*[O: StaticLayoutImageRef](img: O): O {.noSideEffect, inline.} =
  O(data: img.data, order: img.order)


proc layoutId*[ImgT: DynamicLayoutImageRef](img: ImgT):
              ChannelLayoutId {.noSideEffect, inline, raises: [].} =
  img.lid

proc layoutId*[ImgT: StaticLayoutImageRef](img: ImgT):
              ChannelLayoutId {.noSideEffect, inline, raises: [].} =
  ImgT.L.id


# We only have implicit conversions to dynamic layout images. Conversion to
# static layout must be explicit or else the user could unknowingly introduce
# unwanted colorspace conversions.
converter toDynamicLayoutImage*[O: StaticLayoutImageRef](img: O):
  DynamicLayoutImageRef[O.T] {.inline, raises: [].} =

  DynamicLayoutImageRef[O.T](data: img.data, lid: img.layoutId, order: img.order)


template to_chw[T](data: Tensor[T]): Tensor[T] =
  ## Convert the storage shape of the image from H⨯W⨯C → C⨯H⨯W.
  data.permute(2, 0, 1)


template to_hwc[T](data: Tensor[T]): Tensor[T] =
  ## Convert the storage shape of the image from C⨯H⨯W → H⨯W⨯C.
  data.permute(1, 2, 0)


proc channels*[O: ImageObjectRef](img: O): int {.inline, noSideEffect.} =
  case img.order:
    of OrderPlanar: img.data[^3]
    of OrderInterleaved: img.data[^1]


proc width*[O: ImageObjectRef](img: O): int {.inline, noSideEffect.} =
  case img.order:
    of OrderPlanar: img.data[^1]
    of OrderInterleaved: img.data[^2]


proc height*[O: ImageObjectRef](img: O): int {.inline, noSideEffect.} =
  case img.order:
    of OrderPlanar: img.data[^2]
    of OrderInterleaved: img.data[^3]


proc planar*[O: ImageObjectRef](image: O): O {.noSideEffect, inline.} =
  if image.order == OrderInterleaved:
    result = image.clone()
    result.data = image.data.to_chw().asContiguous()
  else:
    result = image


proc interleaved*[O: ImageObjectRef](image: O): O {.noSideEffect, inline.} =
  if image.order == OrderPlanar:
    result = image.clone()
    result.data = image.data.to_hwc().asContiguous()
  else:
    result = image


