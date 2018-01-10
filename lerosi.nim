import system, sequtils, strutils, math, algorithm
import imghdr, nimpng

type ImageType* = imghdr.ImageType ## Image format enumeration.

proc check_image_format*(filename: string): ImageType =
  ## Check the image format stored within a file.
  testImage(filename)


proc check_image_format*(data: seq[uint8]): ImageType =
  ## Check the image format stored within core memory.
  testImage(data)

