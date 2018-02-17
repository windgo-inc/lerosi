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

import macros, img
import ./macroutil


proc defChannelMap*(s: string): ChannelMap {.inline.} =
  var toks = capitalTokens(s)
  let namespace = toks[0]
  let channels = toks[1..^1].map(na => channelof(namespace & na))
  initChannelMap(result, channels)


proc defChannelMap*(cs: ChannelSpace; s: string): ChannelMap {.inline.} =
  let ns = cs.namespace
  var toks = capitalTokens(s)
  result.setLen 0
  for i in 0..<toks.len:
    let ch = channelof(ns & toks[i])
    when compileOption("boundChecks"):
      assert ch in cs.channels, "Channel " & ch.name &
        " cannot be mapped in channelspace " & cs.name
    result.add ch


proc possibleChannelSpaces(mapping: ChannelMap; num_options: var int): set[ChannelSpace] {.inline.} =
  var
    first = true
    revised: set[ChannelSpace]

  for ch in mapping:
    if first:
      result = ch.channelspaces
      first = false
    else:
      num_options = 0
      revised = {}
      for cs in ch.channelspaces:
        if cs in result:
          revised.incl(cs)
          inc num_options
      
      result = revised

proc possibleChannelSpaces*(mapping: ChannelMap): set[ChannelSpace] {.inline.} =
  var x: int
  possibleChannelSpaces(mapping, x)

proc defChannelLayout*(cs: ChannelSpace, s: string): ChannelLayout {.inline, eagerCompile.} =
  result = initChannelLayout(cs, defChannelMap(cs, s))


proc defChannelLayout*(s: string): ChannelLayout {.inline, eagerCompile.} =
  var 
    num_options: int
    space: ChannelSpace
    found_space = false

  let
    mapping = defChannelMap(s)
    possibilities = possibleChannelSpaces(mapping, num_options)

  for cs in possibilities:
    space = cs
    found_space = true
    break

  if not found_space:
    quit "No channelspace containing channels " & $mapping

  result = initChannelLayout(space, mapping)

