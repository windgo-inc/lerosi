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

import macros, streams, os, system, sequtils, strutils, math, algorithm, future
import arraymancer

import ./spaceconf
import ./detail/picio
import ./fixedseq
import ./dataframe
import ./img

const
  loaded_channel_layouts = [
    defChannelLayout"VideoYp",
    defChannelLayout"VideoYpA",
    defChannelLayout"VideoRGB",
    defChannelLayout"VideoRGBA"
  ]


export dataframe, picio, img

#template initImageFromBackend*[T](name: string, data: openarray[T], h, w, ch: int): untyped =
#  initDynamicImage(name, T, 


template readPictureImpl*(isData: bool; T, name, res: untyped): untyped =
  block:
    var r: DynamicImageType(name, "RW", T)
    var h, w, ch: int

    when isData:
      when res is string:
        when T is byte:
          var sq = picio_loadstring_core2(res, h, w, ch)
        elif T is SomeReal:
          var sq = picio_loadstring_hdr_core2(res, h, w, ch)
      else:
        # Why are sequences causing a getAuxTypeDesc crash?
        when T is byte:
          var sq = picio_load_core2(res, h, w, ch)
        elif T is SomeReal:
          var sq = picio_load_hdr_core2(res, h, w, ch)
    else:
      var sq = newSeq[T]()
      picio_load_core3_file_by_type(res, h, w, ch, sq)

    initFrame[FrameType(name, "RW", T), T](r.data_frame, DataInterleaved, sq, [h, w, ch])
    initDynamicImageObject(r, loaded_channel_layouts[ch - 1])
    r

template readPictureFile*(T: typedesc; name: untyped; filename: string): untyped =
  ## read a picture from a file
  readPictureImpl(false, T, name, filename)

template readPictureData*(T: typedesc; name: untyped; data: seq[byte]): untyped =
  ## read a picture from core memory
  readPictureImpl(true, T, name, data)
  
template readPictureData*(T: typedesc; name: untyped; data: string): untyped =
  ## read a picture from core memory
  readPictureImpl(true, T, name, data)


proc preparePictureStb[U](image: U): U {.inline.} =
  # TODO: Implement implicitly in the lerosi/img/img_convert submodule
  # superseding this procedure.
  case image.channelspace
  of VideoChSpaceRGB:
    if VideoChIdA in image.mapping:
      image.reorder [VideoChIdR, VideoChIdG, VideoChIdB, VideoChIdA]
    else:
      image.reorder [VideoChIdR, VideoChIdG, VideoChIdB]
  of VideoChSpaceYpCbCr:
    if VideoChIdA in image.mapping:
      image.reorder [VideoChIdYp, VideoChIdA]
    else:
      image.reorder [VideoChIdYp]
  else:
    # TODO: Implement me based on conversion.
    raise newException(Exception, "LERoSI: Cannot convert to RGB, not yet implemented.")



proc writePicture*[U](image: U;
                opts: SaveOptions = SaveOptions(nil)):
                string =

  let orderedImage = preparePictureStb(image)

  ## write a picture to core memory
  let ilvd = orderedImage.data_frame.interleaved
  let ilvdshape = ilvd.shape
  let innerdata = ilvd.frame_data().backend_data_raw

  picio_savestring_core2(innerdata, ilvdshape[0], ilvdshape[1], ilvd.channel_count, opts)

template writePictureBmp*[U](image: U): string =
  writePicture(image, SaveOptions(format: BMP))

template writePicturePng*[U](image: U): string =
  writePicture(image, SaveOptions(format: PNG, stride: 0))

template writePictureHDR*[U](image: U): string =
  writePicture(image, SaveOptions(format: HDR))

template writePictureJpeg*[U](image: U, quality: range[1..100]): string =
  writePicture(image, SaveOptions(format: JPEG, quality: quality))


proc writePicture*[U](image: U;
                filename: string;
                opts: SaveOptions = SaveOptions(nil)):
                bool =

  let orderedImage = preparePictureStb(image)

  ## write a picture to a file
  let ilvd = orderedImage.data_frame.interleaved
  let ilvdshape = ilvd.shape
  let innerdata = ilvd.frame_data().backend_data_raw
  picio_save_core2(innerdata, ilvdshape[0], ilvdshape[1], ilvd.channel_count, filename, opts)


template writePictureBmp*[U](image: U, filename: string): bool =
  writePicture(image, filename, SaveOptions(format: BMP))

template writePicturePng*[U](image: U, filename: string): bool =
  writePicture(image, filename, SaveOptions(format: PNG, stride: 0))

template writePictureHDR*[U](image: U, filename: string): bool =
  writePicture(image, filename, SaveOptions(format: HDR))

template writePictureJpeg*[U](image: U, filename: string, quality: range[1..100]): bool =
  writePicture(image, filename, SaveOptions(format: JPEG, quality: quality))

