import system, macros, arraymancer, strutils, parseutils

#proc toMetadataArray*[T](dat: openarray[T]): arraymancer.MetadataArray {.inline.} =
#  result = initMetadataArray(0)
#  for d in dat:
#    result.add d

# We just handroll these because they are so short.
#
const rotate_ilvd_tab* = [
  [].toMetadataArray,                           # 0
  [0].toMetadataArray,                          # 1
  [1, 0].toMetadataArray,                       # 2
  [1, 2, 0].toMetadataArray,                    # 3
  [1, 2, 3, 0].toMetadataArray,                 # 4
  [1, 2, 3, 4, 0].toMetadataArray,              # 5
  [1, 2, 3, 4, 5, 0].toMetadataArray,           # 6
  [1, 2, 3, 4, 5, 6, 0].toMetadataArray]        # 7

# We just handroll these because they are so short.
#
const rotate_plnr_tab* = [
  [].toMetadataArray,                           # 0
  [0].toMetadataArray,                          # 1
  [1, 0].toMetadataArray,                       # 2
  [2, 0, 1].toMetadataArray,                    # 3
  [3, 0, 1, 2].toMetadataArray,                 # 4
  [4, 0, 1, 2, 3].toMetadataArray,              # 5
  [5, 0, 1, 2, 3, 4].toMetadataArray,           # 6
  [6, 0, 1, 2, 3, 4, 5].toMetadataArray]        # 7

template rotate_plnr*[T](data: AnyTensor[T], arity: untyped): AnyTensor[T] =
  ## Convert the storage shape of the image from Kn⨯...⨯K1⨯C → C⨯Kn⨯...⨯K1.
  data.permute(rotate_plnr_tab[arity])

template rotate_plnr*[T](data: AnyTensor[T]): AnyTensor[T] =
  ## Convert the storage shape of the image from Kn⨯...⨯K1⨯C → C⨯Kn⨯...⨯K1.
  rotate_plnr(data, data.shape.len)

template rotate_ilvd*[T](data: AnyTensor[T], arity: untyped): AnyTensor[T] =
  ## Convert the storage shape of the image from C⨯Kn⨯...⨯K1 → Kn⨯...⨯K1⨯C.
  data.permute(rotate_ilvd_tab[arity])

template rotate_ilvd*[T](data: AnyTensor[T]): AnyTensor[T] =
  ## Convert the storage shape of the image from C⨯Kn⨯...⨯K1 → Kn⨯...⨯K1⨯C.
  rotate_ilvd(data, data.shape.len)

{.deprecated: [to_chw: rotate_plnr, to_hwc: rotate_ilvd].}

# TODO: Test backwards compatibility and to correctness tests.

#template to_chw*[T](data: Tensor[T]): Tensor[T] =
#  data.permute(2, 0, 1)
#
#
#template to_hwc*[T](data: Tensor[T]): Tensor[T] =
#  ## Convert the storage shape of the image from C⨯H⨯W → H⨯W⨯C.
#  data.permute(1, 2, 0)
