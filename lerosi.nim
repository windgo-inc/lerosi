import os, system, sequtils, strutils, math, algorithm
import imghdr, nimPNG, arraymancer



type ImageType* = imghdr.ImageType ## Image format enumeration.


type
  IIOError* = object of Exception


const
  IIO_RGB24* = 1
  IIO_RGBA32* = 2
  IIO_DEFAULT_FORMAT* = 1



proc uint8array_to_string(data: openarray[uint8]): string =
  ## Convert a an array of uint8s to a string.
  result = newStringOfCap(len(data))
  for ch in data:
    result.add(ch.char)


proc string_to_uint8array(data: string): seq[uint8] =
  ## Convert a string in to an array of uint8s.
  result = @[]
  for ch in data:
    result.add(ch.uint8)



proc imageio_check_format(filename: string): ImageType =
  ## Check the image format stored within a file.
  testImage(filename)


proc imageio_check_format(data: openarray[uint8]): ImageType =
  ## Check the image format stored within core memory.
  testImage(data.map(proc (x: uint8): int8 = x.int8))


# TODO Use macros to collapse the two versions of load_png

proc imageio_load_png*[T](filename: string, options: set[T], w, h: var int): seq[uint8] =
  ## Load a PNG image from a file.
  var r: PNGResult
  if options.contains(IIO_RGBA32):
    r = loadPNG32(filename)
  elif options.contains(IIO_RGB24):
    r = loadPNG24(filename)
  else:
    raise newException(IIOError, "IIO-PNG: Unrecognized decoder (in-file) output format requested.")

  result = r.data.string_to_uint8_array
  w = r.width
  h = r.height


proc imageio_load_png*[T](data: openarray[uint8], options: set[T], w, h: var int): seq[uint8] =
  ## Load a PNG image from core.
  var r: PNGResult
  if options.contains(IIO_RGBA32):
    r = decodePNG32(uint8array_to_string(data))
  elif options.contains(IIO_RGB24):
    r = decodePNG24(uint8array_to_string(data))
  else:
    raise newException(IIOError, "IIO-PNG: Unrecognized decoder (in-core) output format requested.")

  result = r.data.string_to_uint8_array
  w = r.width
  h = r.height


proc save_image_png*[T](filename, data: string, w, h: int, options: set[T] = {IIO_DEFAULT_FORMAT}) =
  ## Save a png to a file
  if options.contains(IIO_RGBA32):
    discard savePNG32(filename, data, w, h)
  elif options.contains(IIO_RGB24):
    discard savePNG24(filename, data, w, h)
  else:
    raise newException(IIOError, "IIO-PNG: Unrecognized encoder (in-core) output format requested.")


proc save_image_png*[T](filename: string, data: openarray[uint8], w, h: int, options: set[T] = {IIO_DEFAULT_FORMAT}) =
  ## Save a png to a file
  save_image_png(filename, uint8array_to_string(data), w, h, options)


