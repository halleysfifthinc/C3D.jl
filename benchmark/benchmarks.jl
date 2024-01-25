using BenchmarkTools, LazyArtifacts, C3D

SUITE = BenchmarkGroup()

SUITE["read"] = BenchmarkGroup()
SUITE["read"]["pc-real"] = BenchmarkGroup(["x86", "float"])
SUITE["read"]["pc-int"] = BenchmarkGroup(["x86", "int"])
SUITE["read"]["vax-real"] = BenchmarkGroup(["vax", "float"])
SUITE["read"]["vax-int"] = BenchmarkGroup(["vax", "int"])
SUITE["read"]["mips-real"] = BenchmarkGroup(["mips", "float"])
SUITE["read"]["mips-int"] = BenchmarkGroup(["mips", "int"])

SUITE["read"]["pc-real"]["sample01/Eb015pr.c3d"] = @benchmarkable readc3d(fn) seconds=10 setup=(fn=artifact"sample01/Eb015pr.c3d")
SUITE["read"]["pc-real"]["sample02/pc_real.c3d"] = @benchmarkable readc3d(fn) seconds=10 setup=(fn=artifact"sample02/pc_real.c3d")

SUITE["read"]["pc-int"]["sample01/Eb015pi.c3d"] = @benchmarkable readc3d(fn) seconds=10 setup=(fn=artifact"sample01/Eb015pi.c3d")
SUITE["read"]["pc-int"]["sample02/pc_int.c3d"] = @benchmarkable readc3d(fn) seconds=10 setup=(fn=artifact"sample02/pc_int.c3d")

SUITE["read"]["vax-real"]["sample01/Eb015vr.c3d"] = @benchmarkable readc3d(fn) seconds=10 setup=(fn=artifact"sample01/Eb015vr.c3d")
SUITE["read"]["vax-real"]["sample02/dec_real.c3d"] = @benchmarkable readc3d(fn) seconds=10 setup=(fn=artifact"sample02/dec_real.c3d")

SUITE["read"]["vax-int"]["sample01/Eb015vi.c3d"] = @benchmarkable readc3d(fn) seconds=10 setup=(fn=artifact"sample01/Eb015vi.c3d")
SUITE["read"]["vax-int"]["sample02/dec_int.c3d"] = @benchmarkable readc3d(fn) seconds=10 setup=(fn=artifact"sample02/dec_int.c3d")

SUITE["read"]["mips-real"]["sample01/Eb015sr.c3d"] = @benchmarkable readc3d(fn) seconds=10 setup=(fn=artifact"sample01/Eb015sr.c3d")
SUITE["read"]["mips-real"]["sample02/sgi_real.c3d"] = @benchmarkable readc3d(fn) seconds=10 setup=(fn=artifact"sample02/sgi_real.c3d")

SUITE["read"]["mips-int"]["sample01/Eb015si.c3d"] = @benchmarkable readc3d(fn) seconds=10 setup=(fn=artifact"sample01/Eb015si.c3d")
SUITE["read"]["mips-int"]["sample02/sgi_int.c3d"] = @benchmarkable readc3d(fn) seconds=10 setup=(fn=artifact"sample02/sgi_int.c3d")

SUITE["read"]["big"]["sample15/FP1.C3D"] = @benchmarkable readc3d(fn) seconds=10 setup=(fn=artifact"sample15/FP1.C3D")
SUITE["read"]["big"]["sample17/128analogchannels.c3d"] = @benchmarkable readc3d(fn) seconds=10 setup=(fn=artifact"sample17/128analogchannels.c3d")
SUITE["read"]["big"]["sample19/sample19.c3d"] = @benchmarkable readc3d(fn) seconds=10 setup=(fn=artifact"sample19/sample19.c3d")

SUITE["show"] = BenchmarkGroup()

SUITE["show"]["simple"] = @benchmarkable show(devnull, f) setup=(f = readc3d(artifact"sample01/Eb015pr.c3d"))
SUITE["show"]["text/plain"] = @benchmarkable show(devnull, "text/plain", f) setup=(f = readc3d(artifact"sample01/Eb015pr.c3d"))

if pkgversion(C3D) > v"0.7.3"
    SUITE["write"] = BenchmarkGroup()
    SUITE["write"]["pc-real"] = BenchmarkGroup(["x86", "float"])
    SUITE["write"]["pc-int"] = BenchmarkGroup(["x86", "int"])
    SUITE["write"]["vax-real"] = BenchmarkGroup(["vax", "float"])
    SUITE["write"]["vax-int"] = BenchmarkGroup(["vax", "int"])
    SUITE["write"]["mips-real"] = BenchmarkGroup(["mips", "float"])
    SUITE["write"]["mips-int"] = BenchmarkGroup(["mips", "int"])


    SUITE["write"]["pc-real"]["sample01/Eb015pr.c3d"] = @benchmarkable writec3d(io, f) seconds=10 setup=(f = readc3d(artifact"sample01/Eb015pr.c3d"); (p, io) = mktemp()) teardown=(close(io)) evals=1
    SUITE["write"]["pc-real"]["sample02/pc_real.c3d"] = @benchmarkable writec3d(io, f) seconds=10 setup=(f = readc3d(artifact"sample02/pc_real.c3d"); (p,io) = mktemp()) teardown=(close(io)) evals=1

    SUITE["write"]["pc-int"]["sample01/Eb015pi.c3d"] = @benchmarkable writec3d(io, f) seconds=10 setup=(f = readc3d(artifact"sample01/Eb015pi.c3d"); (p,io) = mktemp()) teardown=(close(io)) evals=1
    SUITE["write"]["pc-int"]["sample02/pc_int.c3d"] = @benchmarkable writec3d(io, f) seconds=10 setup=(f = readc3d(artifact"sample02/pc_int.c3d"); (p,io) = mktemp()) teardown=(close(io)) evals=1

    SUITE["write"]["vax-real"]["sample01/Eb015vr.c3d"] = @benchmarkable writec3d(io, f) seconds=10 setup=(f = readc3d(artifact"sample01/Eb015vr.c3d"); (p,io) = mktemp()) teardown=(close(io)) evals=1
    SUITE["write"]["vax-real"]["sample02/dec_real.c3d"] = @benchmarkable writec3d(io, f) seconds=10 setup=(f = readc3d(artifact"sample02/dec_real.c3d"); (p,io) = mktemp()) teardown=(close(io)) evals=1

    SUITE["write"]["vax-int"]["sample01/Eb015vi.c3d"] = @benchmarkable writec3d(io, f) seconds=10 setup=(f = readc3d(artifact"sample01/Eb015vi.c3d"); (p,io) = mktemp()) teardown=(close(io)) evals=1
    SUITE["write"]["vax-int"]["sample02/dec_int.c3d"] = @benchmarkable writec3d(io, f) seconds=10 setup=(f = readc3d(artifact"sample02/dec_int.c3d"); (p,io) = mktemp()) teardown=(close(io)) evals=1

    SUITE["write"]["mips-real"]["sample01/Eb015sr.c3d"] = @benchmarkable writec3d(io, f) seconds=10 setup=(f = readc3d(artifact"sample01/Eb015sr.c3d"); (p,io) = mktemp()) teardown=(close(io)) evals=1
    SUITE["write"]["mips-real"]["sample02/sgi_real.c3d"] = @benchmarkable writec3d(io, f) seconds=10 setup=(f = readc3d(artifact"sample02/sgi_real.c3d"); (p,io) = mktemp()) teardown=(close(io)) evals=1

    SUITE["write"]["mips-int"]["sample01/Eb015si.c3d"] = @benchmarkable writec3d(io, f) seconds=10 setup=(f = readc3d(artifact"sample01/Eb015si.c3d"); (p,io) = mktemp()) teardown=(close(io)) evals=1
    SUITE["write"]["mips-int"]["sample02/sgi_int.c3d"] = @benchmarkable writec3d(io, f) seconds=10 setup=(f = readc3d(artifact"sample02/sgi_int.c3d"); (p,io) = mktemp()) teardown=(close(io)) evals=1
end

SUITE["write"]["trc"] = @benchmarkable writetrc(devnull, f) setup=(f=readc3d(artifact"sample01/Eb015pr.c3d"))

