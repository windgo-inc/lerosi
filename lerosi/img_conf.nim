import system, macros, strutils

import ./macroutil
import ./fixedseq

const
  MAX_IMAGE_CHANNELS = 7

type
  ChannelIndex* = FixedSeq[int, MAX_IMAGE_CHANNELS]

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

  DataOrder* = enum
    DataInterleaved,
    DataPlanar

  #ColorSpaceAnyType* = distinct int
  IIOError* = object of Exception

# Type generating macros are kept seperately.
include ./img_typegen

# Meta colorspace specifying runtime configuration of colorspaces.
defineWildcardColorSpace"Any"

# Colorspace of solitary alpha channel.
defineColorSpace"A"

# Colorspaces with optional alpha channel.
defineColorSpaceWithAlpha"Y"
defineColorSpaceWithAlpha"Yp"
defineColorSpaceWithAlpha"RGB"
defineColorSpaceWithAlpha"CMYe"
defineColorSpaceWithAlpha"HSV"
defineColorSpaceWithAlpha"YCbCr"
defineColorSpaceWithAlpha"YpCbCr"

# Instantiate the image types and compile-time property getters.
declareColorSpaceMetadata()

{.deprecated: [ColorSpaceAnyType: ColorSpaceTypeAny].}


