# MIT License
# 
# Copyright (c) 2018 WINDGO, Inc.
# Low Energy Retrieval of Source Information
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

import system, macros, strutils

import ./detail/macroutil
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

# Type generating macros are kept seperately.
import ./spacemeta

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


