import system, macros, strutils, sequtils

import ./macroutil
import ./fixedseq
import ./img_types

type
  Image*[Lens; ImgType] = object
    lens: Lens
    baseimg: ImgType

  StaticLens*[S, static[ChannelMap]] = object
    lens_cspace: ColorSpace

  DynamicLens*[S] = object
    cspace: ColorSpace
    mapping: ChannelMap

proc mapping*[S](lens: DynamicLens[S]): ChannelMap {.inline, noSideEffect, raises: [].} = lens.mapping
proc mapping*[S, M](lens: StaticLens[S, M]): ChannelMap {.inline, noSideEffect, raises: [].} = M

proc colorspace*[S](lens: DynamicLens[S]):
    ColorSpace {.inline, noSideEffect, raises: [].} =
  when S is ColorSpaceTypeAny: lens.cspace else: S

proc colorspace*[S, M](lens: StaticLens[S, M]):
    ColorSpace {.inline, noSideEffect, raises: [].} =
  when S is ColorSpaceTypeAny: lens.cspace else: S

proc init_image


