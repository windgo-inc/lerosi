import system, times

template timedAction*(body: untyped): type(epochTime()) =
  let t0 = epochTime()
  body
  
  epochTime() - t0

