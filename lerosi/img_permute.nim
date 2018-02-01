import arraymancer

template to_chw*[T](data: Tensor[T]): Tensor[T] =
  ## Convert the storage shape of the image from H⨯W⨯C → C⨯H⨯W.
  data.permute(2, 0, 1)


template to_hwc*[T](data: Tensor[T]): Tensor[T] =
  ## Convert the storage shape of the image from C⨯H⨯W → H⨯W⨯C.
  data.permute(1, 2, 0)


