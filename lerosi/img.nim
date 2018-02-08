import system, macros, strutils, sequtils

import ./macroutil
import ./fixedseq
import ./img_types


type
  Image*[W; Frame] = object
    lens: W
    baseimg: Frame

  Lens[S]* = object of RootObj
    cspace: ColorSpace

  StaticLens*[S; M: static[ChannelMap]] = object of Lens[S]

  DynamicLens*[S] = object of Lens[S]
    mapping: ChannelMap

  StaticOrderImage[W; T; O: static[DataOrder]] = Image[W, StaticOrderFrame[T, W.S, O]]
  DynamicImage[W; T] = Image[W, DynamicOrderFrame[T, W.S]]


proc mapping*[S](lens: DynamicLens[S]):
  ChannelMap {.inline, noSideEffect, raises: [].} = lens.mapping

proc mapping*[S, M](lens: StaticLens[S, M]):
  ChannelMap {.inline, noSideEffect, raises: [].} = M

proc colorspace*[S](lens: DynamicLens[S]):
    ColorSpace {.inline, noSideEffect, raises: [].} =
  when S is ColorSpaceTypeAny: lens.cspace else: S

proc colorspace*[S, M](lens: StaticLens[S, M]):
    ColorSpace {.inline, noSideEffect, raises: [].} =
  when S is ColorSpaceTypeAny: lens.cspace else: S


#proc init_image[W; FrameType](image: var Image[]):


#proc init_image*[]


