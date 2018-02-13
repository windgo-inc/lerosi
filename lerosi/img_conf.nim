import system, macros, strutils

import ./macroutil
import ./fixedseq

const
  MAX_IMAGE_CHANNELS* = 7

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

  DataOrder* = enum
    DataInterleaved,
    DataPlanar

  #ChannelSpaceAnyType* = distinct int
  IIOError* = object of Exception


# Type generating macros are kept seperately.
include ./compilespaces

# Colorspace of solitary alpha channel.
defineChannelSpace"A"

# Colorspaces with optional alpha channel.
defineChannelSpaceExt("A", "Y")
defineChannelSpaceExt("A", "Yp")
defineChannelSpaceExt("A", "RGB")
defineChannelSpaceExt("A", "CMYe")
defineChannelSpaceExt("A", "HSV")
defineChannelSpaceExt("A", "YCbCr")
defineChannelSpaceExt("A", "YpCbCr")

# Basic placeholder audiospaces (mono, stero, quadrophonic) with optional
# LFE channel (low frequency effects).
defineChannelSpaceExt("Lfe", "Mono")
defineChannelSpaceExt("Lfe", "LR")
defineChannelSpaceExt("Lfe", "LfRfLbRb")

# Instantiate the image types and compile-time property getters.
#expandMacros:
declareChannelSpaceMetadata()
declareNamedFixedSeq(ChannelMap, ChannelId, MAX_IMAGE_CHANNELS)

{.deprecated: [
  colorspace_len: len,
  colorspace_channels: channels,
  colorspace_order: order,
  colorspace_id: id,
  colorspace_name: name,
  channel_get_colorspaces: channelspaces,

  channelspace_len: len,
  channelspace_channels: channels,
  channelspace_order: order,
  channelspace_id: id,
  channelspace_name: name,
  channel_get_channelspaces: channelspaces
].}


