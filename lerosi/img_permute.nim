import system, macros, arraymancer, strutils, parseutils

#proc toMetadataArray*[T](dat: openarray[T]): arraymancer.MetadataArray {.inline.} =
#  result = initMetadataArray(0)
#  for d in dat:
#    result.add d

# We just handroll these because they are so short.
#
template rotate_ilvd_impl[T](data: var AnyTensor[T], arity: untyped): untyped =
  when compiles((const x = arity)):
    when arity == 2:
      const permutation = [1, 0]
    elif arity == 3:
      const permutation = [1, 2, 0]
    elif arity == 4:
      const permutation = [1, 2, 3, 0]
    elif arity == 5:
      const permutation = [1, 2, 3, 4, 0]
    elif arity == 6:
      const permutation = [1, 2, 3, 4, 5, 0]
    elif arity == 7:
      const permutation = [1, 2, 3, 4, 5, 6, 0]
    data = data.permute(permutation)
  else:
    case arity:
    of 2: data = data.permute([1, 0])
    of 3: data = data.permute([1, 2, 0])
    of 4: data = data.permute([1, 2, 3, 0])
    of 5: data = data.permute([1, 2, 3, 4, 0])
    of 6: data = data.permute([1, 2, 3, 4, 5, 0])
    of 7: data = data.permute([1, 2, 3, 4, 5, 6, 0])
    else:
      discard

# We just handroll these because they are so short.
#
template rotate_plnr_impl[T](data: var AnyTensor[T], arity: untyped): untyped =
  when compiles((const x = arity)):
    when arity == 2:
      const permutation = [1, 0]
    elif arity == 3:
      const permutation = [2, 0, 1]
    elif arity == 4:
      const permutation = [3, 0, 1, 2]
    elif arity == 5:
      const permutation = [4, 0, 1, 2, 3]
    elif arity == 6:
      const permutation = [5, 0, 1, 2, 3, 4]
    elif arity == 7:
      const permutation = [6, 0, 1, 2, 3, 4, 5]
    data = data.permute(permutation)
  else:
    case arity:
    of 2: data = data.permute([1, 0])
    of 3: data = data.permute([2, 0, 1])
    of 4: data = data.permute([3, 0, 1, 2])
    of 5: data = data.permute([4, 0, 1, 2, 3])
    of 6: data = data.permute([5, 0, 1, 2, 3, 4])
    of 7: data = data.permute([6, 0, 1, 2, 3, 4, 5])
    else:
      discard

template rotate_plnr_tplt[T](data: AnyTensor[T], arity: untyped): AnyTensor[T] =
  ## Convert the storage shape of the image from Kn⨯...⨯K1⨯C → C⨯Kn⨯...⨯K1.
  block:
    var r = data
    rotate_plnr_impl(r, arity)
    r

proc rotate_plnr*[T](data: AnyTensor[T], arity: static[int]): AnyTensor[T] =
  ## Convert the storage shape of the image from Kn⨯...⨯K1⨯C → C⨯Kn⨯...⨯K1.
  rotate_plnr_tplt(data, arity)

proc rotate_plnr*[T](data: AnyTensor[T], arity: int): AnyTensor[T] =
  ## Convert the storage shape of the image from Kn⨯...⨯K1⨯C → C⨯Kn⨯...⨯K1.
  rotate_plnr_tplt(data, arity)

proc rotate_plnr*[T](data: AnyTensor[T]): AnyTensor[T] =
  ## Convert the storage shape of the image from Kn⨯...⨯K1⨯C → C⨯Kn⨯...⨯K1.
  rotate_plnr_tplt(data, data.shape.len)

template rotate_ilvd_tplt[T](data: AnyTensor[T], arity: untyped): AnyTensor[T] =
  ## Convert the storage shape of the image from C⨯Kn⨯...⨯K1 → Kn⨯...⨯K1⨯C.
  block:
    var r = data
    rotate_ilvd_impl(r, arity)
    r

proc rotate_ilvd*[T](data: AnyTensor[T], arity: static[int]): AnyTensor[T] =
  ## Convert the storage shape of the image from C⨯Kn⨯...⨯K1 → Kn⨯...⨯K1⨯C.
  rotate_ilvd_tplt(data, arity)

proc rotate_ilvd*[T](data: AnyTensor[T], arity: int): AnyTensor[T] =
  ## Convert the storage shape of the image from C⨯Kn⨯...⨯K1 → Kn⨯...⨯K1⨯C.
  rotate_ilvd_tplt(data, arity)

proc rotate_ilvd*[T](data: AnyTensor[T]): AnyTensor[T] =
  ## Convert the storage shape of the image from C⨯Kn⨯...⨯K1 → Kn⨯...⨯K1⨯C.
  rotate_ilvd_tplt(data, data.shape.len)

{.deprecated: [to_chw: rotate_plnr, to_hwc: rotate_ilvd].}


