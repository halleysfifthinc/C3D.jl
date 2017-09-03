using BinDeps
using Compat

@BinDeps.setup

libvaxdata = library_dependency("libvaxdata")

prefix = joinpath(BinDeps.depsdir(libvaxdata), "usr")
builddir = joinpath(prefix, "include")
libdir = joinpath(prefix, "lib")

provides(Sources, URI("https://pubs.usgs.gov/of/2005/1424/libvaxdata.tar.gz"), libvaxdata)
provides(SimpleBuild, 
    (@build_steps begin
        GetSources(libvaxdata)
        CreateDirectory(prefix)
        CreateDirectory(builddir)
        CreateDirectory(libdir)
        FileRule(joinpath(prefix, "libvaxdata.so"), @build_steps begin
            MakeTargets(["-fMakefile"])
          end)
    end), libvaxdata)

@BinDeps.install Dict(:libvaxdata => :libvaxdata)
