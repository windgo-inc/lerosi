# Copyright 2017 the Arraymancer contributors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# This file is modified by William Whitacre, and these changes are
# (C) WINDGO, Inc. 2018 under the MIT license. Since we have need for a static
# array which behaves like a sequence, but are not using it for a numerical
# purpose, it seemed appropriate to generalize further.


import system, sequtils, future


type FixedSeq*[T; N: static[Natural]] = object
    ## Custom stack allocated array that behaves like seq.
    data*: array[N, T]
    len*: Natural


#proc copyFrom*[A: FixedSeq](a: var A, s: openarray[A.T]) {.inline.} =
#  a.len = s.len
#  for i in 0..<s.len:
#    a.data[i] = s[i]

proc copyFrom*[A: FixedSeq](a: var A, s: varargs[A.T]) {.inline.} =
  a.len = s.len
  for i in 0..<s.len:
    a.data[i] = s[i]

proc copyFrom*(a: var FixedSeq, s: FixedSeq) {.inline.} =
  a.len = s.len
  for i in 0..<s.len:
    a.data[i] = s.data[i]

proc setLen*[A: FixedSeq](a: var A, len: Natural) {.inline.} =
  when compileOption("boundChecks"):
    assert len <= A.N
  a.len = len

proc low*(a: FixedSeq): int {.inline.} =
  0

proc high*(a: FixedSeq): int {.inline.} =
  a.len-1


when NimVersion >= "0.17.3":
  # Need to deal with BackwardsIndex and multi-type slice introduced by:
  # https://github.com/nim-lang/Nim/commit/d52a1061b35bbd2abfbd062b08023d986dbafb3c

  type Index = SomeSignedInt or BackwardsIndex
  template `^^`(s, i: untyped): untyped =
    when i is BackwardsIndex:
      s.len - int(i)
    else: int(i)
else:
  type Index = SomeSignedInt
  template `^^`(s, i: untyped): untyped =
    i

  proc `^`*(x: SomeSignedInt; a: FixedSeq): int {.inline.} =
    a.len - x

proc `[]`*[A: FixedSeq](a: A, idx: Index): A.T {.inline.} =
  a.data[a ^^ idx]

proc `[]`*[A: FixedSeq](a: var A, idx: Index): var A.T {.inline.} =
  a.data[a ^^ idx]

proc `[]=`*[A: FixedSeq](a: var A, idx: Index, v: A.T) {.inline.} =
  a.data[a ^^ idx] = v

proc `[]`*[A: FixedSeq](a: A, slice: Slice[int]): A {.inline.} =
  let bgn_slice = a ^^ slice.a
  let end_slice = a ^^ slice.b

  if end_slice >= bgn_slice:
    result.len = (end_slice - bgn_slice + 1)
    for i in 0..<result.len:
      result[i] = a[bgn_slice+i]

iterator items*[A: FixedSeq](a: A): A.T {.inline.} =
  for i in 0..<a.len:
    yield a.data[i]

iterator mitems*[A: FixedSeq](a: var A): var A.T {.inline.} =
  for i in 0..<a.len:
    yield a.data[i]

iterator pairs*[A: FixedSeq](a: A): (int, A.T) {.inline.} =
  for i in 0..<a.len:
    yield (i,a.data[i])

proc `@`*[A: FixedSeq](a: A): seq[A.T] {.inline.} =
  result = newSeq[A.T](a.len)
  for i in 0..<a.len:
    result[i] = a.data[i]

proc toSeq[A: FixedSeq](a: A): seq[A.T] {.inline.} = @(a)

proc `$`*(a: FixedSeq): string {.inline.} =
  result = "["
  var firstElement = true
  for value in items(a):
    if not firstElement: result.add(", ")
    result.add($value)
    firstElement = false
  result.add("]")

# Removed product procedure.

proc insert*[A: FixedSeq](a: var A, value: A.T, index: Natural = 0) {.inline.} =
  for i in countdown(a.len, index+1):
    a[i] = a[i-1]
  a[index] = value
  inc a.len

proc delete*(a: var FixedSeq, index: Natural) {.inline.} =
  dec(a.len)
  for i in index..<a.len:
    a[i] = a[i+1]
  a[a.len] = 0

proc add*[A: FixedSeq](a: var A, value: A.T) {.inline.} =
  a[a.len] = value
  inc a.len

proc `&`*[A: FixedSeq](a: A, value: A.T): A {.inline.} =
  result = a
  result.add(value)

proc `&`*(a, b: FixedSeq): FixedSeq {.inline.} =
  result = a
  result.len += b.len
  for i in 0..<b.len:
    result[a.len + i] = b[i]

proc reversed*(a: FixedSeq): FixedSeq {.inline.} =
  for i in 0..<a.len:
    result[a.len-i-1] = a[i]
  result.len = a.len

proc reversed*(a: FixedSeq, result: var FixedSeq) {.inline.} =
  for i in 0..<a.len:
    result[a.len-i-1] = a[i]
  for i in a.len..<result.len:
    result[i] = 0
  result.len = a.len

proc applyFilter*[A: FixedSeq](a: A, f: proc (item: A.T): bool) {.inline.} =
  var offset: int = 0
  for i in 0..<a.len:
    if f(a[i + offset]):
      a[i + offset] = a[i]
    else:
      dec(offset)
  a.setLen(a.len + offset)

proc filter*[A: FixedSeq](a: A, f: proc (item: A.T): bool): A {.inline.} =
  for i in 0..<a.len:
    if f(a[i]):
      result.add(a[i])

proc `==`*[A: FixedSeq](a: A, s: openarray[A.T]): bool {.inline.} =
  if a.len != s.len:
    return false
  for i in 0..<s.len:
    if a[i] != s[i]:
      return false
  return true

proc `==`*(a, s: FixedSeq): bool {.inline.} =
  if a.len != s.len:
    return false
  for i in 0..<s.len:
    if a[i] != s[i]:
      return false
  return true

iterator zip*[A, B: FixedSeq](a: A, b: B): (A.T, B.T)=
  let len = min(a.len, b.len)
  for i in 0..<len:
    yield (a[i], b[i])

proc concat*[A: FixedSeq](dsas: varargs[A]): A =
  var total_len = 0
  for dsa in dsas:
    inc(total_len, dsa.len)

  assert total_len <= A.N

  result.len = total_len
  var i = 0
  for dsa in dsas:
    for val in dsa:
      result[i] = val
      inc(i)

