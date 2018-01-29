
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

  ImageObject*[T] = ref object
    layout: ChannelLayoutId
    order: ImageDataOrdering
    data: Tensor[T]

  StaticLayoutImageObject*[T; L: ChannelLayout] = ref object
    order: ImageDataOrdering
    data: Tensor[T]

  IIOError* = object of Exception

