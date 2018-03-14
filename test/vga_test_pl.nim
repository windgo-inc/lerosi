import lerosi, times, ./benchtime

var sourceFrame: BackendType("am", byte)
var destFrame: BackendType("am", byte)

discard sourceFrame.backend_data_noinit(3, 640, 480)
discard destFrame.backend_data_noinit(3, 640, 480)

var destSampler = destFrame.initAmDirectNDSampler DataPlanar
var sourceSampler = sourceFrame.initAmDirectNDSampler DataPlanar

const N = 600

let interval = timedAction:
  for k in 1..N:
    for s in sampleDualNDchannels(destSampler, sourceSampler, [0, 1, 2], [0, 1, 2]):
      s.lhs(0) = s.rhs(0)
      s.lhs(1) = s.rhs(1)
      s.lhs(2) = s.rhs(2)

echo N, " frames in ", interval, " second(s): ", N.float/interval, " frames per second."

