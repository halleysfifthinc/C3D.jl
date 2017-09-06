using BinDeps
using Compat

@BinDeps.setup

libvaxdata = library_dependency("libvaxdata", aliases = ["libvaxdata-x86_64", "libvaxdata-i686"])

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
        @build_steps begin
            ChangeDirectory(BinDeps.depsdir(libvaxdata))
            FileRule(joinpath(libdir, "libvaxdata-"*string(Sys.ARCH)*"."*Libdl.dlext), @build_steps begin
                `make -j $(Sys.CPU_CORES) -C $(@__DIR__) -f Makefile ARCH=$(haskey(ENV,"ARCH") ? ENV["ARCH"] : Sys.ARCH)`
            end)
        end
    end), libvaxdata, os = :Unix)

provides(SimpleBuild, 
    (@build_steps begin
        GetSources(libvaxdata)
        CreateDirectory(prefix)
        CreateDirectory(builddir)
        CreateDirectory(libdir)
        @build_steps begin
            ChangeDirectory(BinDeps.depsdir(libvaxdata))
            FileRule(joinpath(libdir, "libvaxdata-"*string(Sys.ARCH)*"."*Libdl.dlext), @build_steps begin
                  `C:/cygwin64/bin/sh -lc "make -j $(Sys.CPU_CORES) -C $(replace(@__DIR__, r"\\", "/")) -f Makefile ARCH=$(haskey(ENV,"ARCH") ? ENV["ARCH"] : Sys.ARCH)"`
              end)
        end
    end), libvaxdata, os = :Windows)

is_windows() && push!(BinDeps.defaults, BuildProcess)

@BinDeps.install Dict(:libvaxdata => :libvaxdata)

is_windows() && pop!(BinDeps.defaults)
