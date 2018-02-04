import typetraits

template image_init_test(T: untyped; order, cspace: untyped): untyped =
  var img: T
  echo " : init_image_storage on type ", T.name
  init_image_storage(img, cspace, order, dim=[6, 6])
  echo "img.storage_order = ", img.storage_order
  echo "img.colorspace = ", img.colorspace
  echo "img.data.shape = ", img.data.shape
  echo "img.data = ", img.data

template statictype_image_init_test(T, S, O: untyped): untyped =
  image_init_test(StaticOrderImage[T, ColorSpaceTypeAny, O], O, colorspace_id(S))

template dynamictype_image_init_test(T, S, O: untyped): untyped =
  image_init_test(DynamicOrderImage[T, ColorSpaceTypeAny], O, colorspace_id(S))

template statictype_scs_image_init_test(T, S, O: untyped): untyped =
  image_init_test(StaticOrderImage[T, S, O], O, colorspace_id(S))

template dynamictype_scs_image_init_test(T, S, O: untyped): untyped =
  image_init_test(DynamicOrderImage[T, S], O, colorspace_id(S))

template has_subspace_test(sp1, sp2, expect: untyped): untyped =
  echo $(sp1), ".colorspace_has_subspace(", $(sp2), ") = ", sp1.colorspace_has_subspace(sp2)
  if sp1.colorspace_has_subspace(sp2) == expect:
    echo " [ok]"
  else:
    echo " [expected ", $(expect), "]"


template image_statictype_test(datatype, cspace, order: untyped): untyped =
  var img: StaticOrderImage[datatype, cspace, order]
  echo type(img).name, " :"
  echo "  T = ", type(img.T).name
  echo "  S = ", type(img.S).name
  echo "  O = ", $(img.O)

  when cspace is ColorSpaceTypeAny:
    echo "do: img.colorspace = ", ColorSpaceIdYpCbCr
    img.colorspace = ColorSpaceIdYpCbCr
    echo "{OK} assignment over dynamic colorspace succeeded expectedly."
  else:
    try:
      img.colorspace = ColorSpaceIdYpCbCr
    except:
      echo "{OK} assignment over static colorspace failed expectedly."

  echo "img.storage_order = ", img.storage_order
  echo "img.colorspace = ", img.colorspace


template image_dynamictype_test(datatype, cspace, order: untyped): untyped =
  var img: DynamicOrderImage[datatype, cspace]
  echo type(img).name, " :"
  echo "  T = ", type(img.T).name
  echo "  S = ", type(img.S).name

  when cspace is ColorSpaceTypeAny:
    echo "do: img.colorspace = ", ColorSpaceIdYpCbCr
    img.colorspace = ColorSpaceIdYpCbCr
    echo "{OK} assignment over dynamic colorspace succeeded expectedly."
  else:
    try:
      img.colorspace = ColorSpaceIdYpCbCr
    except:
      echo "{OK} assignment over static colorspace failed expectedly."

  img.storage_order = order
  echo "img.storage_order = ", img.storage_order
  echo "img.colorspace = ", img.colorspace

template image_statictype_test_il(datatype, cspace: untyped): untyped =
  image_statictype_test(datatype, cspace, DataInterleaved)

template image_statictype_test_pl(datatype, cspace: untyped): untyped =
  image_statictype_test(datatype, cspace, DataPlanar)

template image_dynamictype_test_il(datatype, cspace: untyped): untyped =
  image_dynamictype_test(datatype, cspace, DataInterleaved)

template image_dynamictype_test_pl(datatype, cspace: untyped): untyped =
  image_dynamictype_test(datatype, cspace, DataPlanar)


template has_subspace_test_suite(): untyped =
  has_subspace_test(ColorSpaceTypeRGB, ColorSpaceTypeRGBA, false)
  has_subspace_test(ColorSpaceTypeRGB, ColorSpaceTypeRGB, true)
  has_subspace_test(ColorSpaceTypeRGB, ColorSpaceTypeRG, true)
  has_subspace_test(ColorSpaceTypeRGB, ColorSpaceTypeGB, true)
  has_subspace_test(ColorSpaceTypeRGB, ColorSpaceTypeRB, true)
  has_subspace_test(ColorSpaceTypeRGB, ColorSpaceTypeRBA, false)

static:
  echo " *** compile-time tests ***"

  echo " ~ subcolorspace inclusion test ~"
  has_subspace_test_suite()

  echo " ~ StaticOrderImage compile-time access tests ~"
  image_statictype_test_il(byte, ColorSpaceTypeRGB)
  image_statictype_test_pl(byte, ColorSpaceTypeRGB)
  image_statictype_test_il(byte, ColorSpaceTypeCMYe)
  image_statictype_test_pl(byte, ColorSpaceTypeCMYe)
  image_statictype_test_il(byte, ColorSpaceTypeAny)
  image_statictype_test_pl(byte, ColorSpaceTypeAny)

  echo " ~ DynamicOrderImage compile-time access tests ~"
  image_dynamictype_test_il(byte, ColorSpaceTypeRGB)
  image_dynamictype_test_pl(byte, ColorSpaceTypeRGB)
  image_dynamictype_test_il(byte, ColorSpaceTypeCMYe)
  image_dynamictype_test_pl(byte, ColorSpaceTypeCMYe)
  image_dynamictype_test_il(byte, ColorSpaceTypeAny)
  image_dynamictype_test_pl(byte, ColorSpaceTypeAny)

echo " ~ run-time tests ~"
has_subspace_test_suite()

echo " ~ StaticOrderImage run-time access tests ~"
image_statictype_test_il(byte, ColorSpaceTypeRGB)
image_statictype_test_pl(byte, ColorSpaceTypeRGB)
image_statictype_test_il(byte, ColorSpaceTypeCMYe)
image_statictype_test_pl(byte, ColorSpaceTypeCMYe)
image_statictype_test_il(byte, ColorSpaceTypeAny)
image_statictype_test_pl(byte, ColorSpaceTypeAny)

echo " ~ DynamicOrderImage run-time access tests ~"
image_dynamictype_test_il(byte, ColorSpaceTypeRGB)
image_dynamictype_test_pl(byte, ColorSpaceTypeRGB)
image_dynamictype_test_il(byte, ColorSpaceTypeCMYe)
image_dynamictype_test_pl(byte, ColorSpaceTypeCMYe)
image_dynamictype_test_il(byte, ColorSpaceTypeAny)
image_dynamictype_test_pl(byte, ColorSpaceTypeAny)

echo " ~ StaticOrderImage initialization (dynamic colorspace) ~"
statictype_image_init_test(byte, ColorSpaceTypeRGB, DataPlanar)
statictype_image_init_test(byte, ColorSpaceTypeRGB, DataInterleaved)
statictype_image_init_test(byte, ColorSpaceTypeCMYe, DataPlanar)
statictype_image_init_test(byte, ColorSpaceTypeCMYe, DataInterleaved)
statictype_image_init_test(byte, ColorSpaceTypeYpCbCr, DataPlanar)
statictype_image_init_test(byte, ColorSpaceTypeYpCbCr, DataInterleaved)

echo " ~ DynamicOrderImage initialization (dynamic colorspace) ~"
dynamictype_image_init_test(byte, ColorSpaceTypeRGB, DataPlanar)
dynamictype_image_init_test(byte, ColorSpaceTypeRGB, DataInterleaved)
dynamictype_image_init_test(byte, ColorSpaceTypeCMYe, DataPlanar)
dynamictype_image_init_test(byte, ColorSpaceTypeCMYe, DataInterleaved)
dynamictype_image_init_test(byte, ColorSpaceTypeYpCbCr, DataPlanar)
dynamictype_image_init_test(byte, ColorSpaceTypeYpCbCr, DataInterleaved)

echo " ~ StaticOrderImage initialization (static colorspace) ~"
statictype_scs_image_init_test(byte, ColorSpaceTypeRGB, DataPlanar)
statictype_scs_image_init_test(byte, ColorSpaceTypeRGB, DataInterleaved)
statictype_scs_image_init_test(byte, ColorSpaceTypeCMYe, DataPlanar)
statictype_scs_image_init_test(byte, ColorSpaceTypeCMYe, DataInterleaved)
statictype_scs_image_init_test(byte, ColorSpaceTypeYpCbCr, DataPlanar)
statictype_scs_image_init_test(byte, ColorSpaceTypeYpCbCr, DataInterleaved)

echo " ~ DynamicOrderImage initialization (static colorspace) ~"
dynamictype_scs_image_init_test(byte, ColorSpaceTypeRGB, DataPlanar)
dynamictype_scs_image_init_test(byte, ColorSpaceTypeRGB, DataInterleaved)
dynamictype_scs_image_init_test(byte, ColorSpaceTypeCMYe, DataPlanar)
dynamictype_scs_image_init_test(byte, ColorSpaceTypeCMYe, DataInterleaved)
dynamictype_scs_image_init_test(byte, ColorSpaceTypeYpCbCr, DataPlanar)
dynamictype_scs_image_init_test(byte, ColorSpaceTypeYpCbCr, DataInterleaved)
