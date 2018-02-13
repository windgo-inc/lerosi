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
import ./compilespaces

# Colorspace of solitary alpha channel.
defineChannelSpace("Video", "A")

# Colorspaces with optional alpha channel.
defineChannelSpaceExt("Video", "A", "Y")
defineChannelSpaceExt("Video", "A", "Yp")
defineChannelSpaceExt("Video", "A", "RGB")
defineChannelSpaceExt("Video", "A", "CMYe")
defineChannelSpaceExt("Video", "A", "HSV")
defineChannelSpaceExt("Video", "A", "YCbCr")
defineChannelSpaceExt("Video", "A", "YpCbCr")

# Printer colorspaces.
defineChannelSpace("Print", "K")
defineChannelSpace("Print", "CMYeK")

# Audiospace of solitary LFE channel.
defineChannelSpace("Audio", "Lfe")

# Basic placeholder audiospaces (mono, stero, quadrophonic) with optional
# LFE channel (low frequency effects).
defineChannelSpaceExt("Audio", "Lfe", "Mono")
defineChannelSpaceExt("Audio", "Lfe", "LeftRight")
defineChannelSpaceExt("Audio", "Lfe", "LfRfLbRb")

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


