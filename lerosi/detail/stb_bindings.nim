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

# This file should be included in place of importing stb_image
#
import stb_image/read as stbi
import stb_image/write as stbiw

proc stbi_load(
  filename: cstring;
  x, y, channels_in_file: var cint;
  desired_channels: cint
): ptr cuchar
  {.importc: "stbi_load".}


proc stbi_loadf(
  filename: cstring;
  x, y, channels_in_file: var cint;
  desired_channels: cint
): ptr cfloat
  {.importc: "stbi_loadf".}


proc stbi_load_from_memory(
  buffer: ptr cuchar;
  len: cint;
  x, y, channels_in_file: var cint;
  desired_channels: cint
): ptr cuchar
  {.importc: "stbi_load_from_memory".}


proc stbi_loadf_from_memory(
  buffer: ptr cuchar;
  length: cint;
  x, y, channels_in_file: var cint;
  desired_channels: cint
): ptr cfloat
  {.importc: "stbi_loadf_from_memory".}


proc stbi_write_png(
  filename: cstring;
  w, h, comp: cint;
  data: pointer,
  stride_in_bytes: cint
): cint
  {.importc: "stbi_write_png".}

proc stbi_write_bmp(
  filename: cstring;
  w, h, comp: cint;
  data: pointer
): cint
  {.importc: "stbi_write_bmp".}

proc stbi_write_tga(
  filename: cstring;
  w, h, comp: cint;
  data: pointer
): cint
  {.importc: "stbi_write_tga".}

proc stbi_write_hdr(
  filename: cstring;
  x, y, channels: cint;
  data: ptr cfloat
): cint
  {.importc: "stbi_write_hdr".}

proc stbi_write_jpg(
  filename: cstring;
  w, h, comp: cint;
  data: pointer;
  quality: cint;
): cint
  {.importc: "stbi_write_jpg".}

proc stbi_write_png_to_func(
  fn: writeCallback,
  context: pointer,
  w, h, comp: cint,
  data: pointer,
  stride_in_bytes: cint
): cint
  {.importc: "stbi_write_png_to_func".}

proc stbi_write_bmp_to_func(
  fn: writeCallback,
  context: pointer,
  w, h, comp: cint,
  data: pointer
): cint
  {.importc: "stbi_write_bmp_to_func".}

proc stbi_write_tga_to_func(
  fn: writeCallback,
  context: pointer,
  w, h, comp: cint,
  data: pointer
): cint
  {.importc: "stbi_write_tga_to_func".}

proc stbi_write_jpg_to_func(
  fn: writeCallback,
  context: pointer,
  w, h, comp: cint,
  data: pointer,
  quality: cint
): cint
  {.importc: "stbi_write_jpg_to_func".}

proc stbi_write_hdr_to_func(
  fn: writeCallback;
  context: pointer;
  x, y, channels: cint;
  data: ptr cfloat
): cint
  {.importc: "stbi_write_hdr_to_func".}


proc stbi_image_free(p: pointer) {.importc: "stbi_image_free".}
