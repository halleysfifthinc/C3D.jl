using Downloads, ArtifactUtils, Artifacts, TOML, Tar

sampledatalinks = [ "sample00" "https://www.c3d.org/data/Sample00.zip";
"sample01" "https://www.c3d.org/data/Sample01.zip";
"sample02" "https://www.c3d.org/data/Sample02.zip";
"sample08" "https://www.c3d.org/data/Sample08.zip";
"sample36" "https://www.c3d.org/data/Sample36.zip";
"sample07" "https://www.c3d.org/data/Sample07.zip";
"sample10" "https://www.c3d.org/data/Sample10.zip";
"sample12" "https://www.c3d.org/data/Sample12.zip";
"sample17" "https://www.c3d.org/data/Sample17.zip";
"sample19" "https://www.c3d.org/data/Sample19.zip";
"sample22" "https://www.c3d.org/data/Sample22.zip";
"sample29" "https://www.c3d.org/data/Sample29.zip";
# "sample31" "https://www.c3d.org/data/Sample31.zip"; # Over the gist file size limit of 100Mb
"sample34" "https://www.c3d.org/data/Sample34.zip";
"sample03" "https://www.c3d.org/data/Sample03.zip";
"sample04" "https://www.c3d.org/data/Sample04.zip";
"sample05" "https://www.c3d.org/data/Sample05.zip";
"sample23" "https://www.c3d.org/data/Sample23.zip";
"sample26" "https://www.c3d.org/data/Sample26.zip";
"sample27" "https://www.c3d.org/data/Sample27.zip";
"sample28" "https://www.c3d.org/data/Sample28.zip";
"sample30" "https://www.c3d.org/data/Sample30.zip";
"sample33" "https://www.c3d.org/data/Sample33.zip";
"sample35" "https://www.c3d.org/data/Sample35.zip";
"sample06" "https://www.c3d.org/data/Sample06.zip";
"sample09" "https://www.c3d.org/data/Sample09.zip";
"sample11" "https://www.c3d.org/data/Sample11.zip";
"sample13" "https://www.c3d.org/data/Sample13.zip";
"sample14" "https://www.c3d.org/data/Sample14.zip";
"sample15" "https://www.c3d.org/data/Sample15.zip";
"sample16" "https://www.c3d.org/data/Sample16.zip";
"sample18" "https://www.c3d.org/data/Sample18.zip";
"sample20" "https://www.c3d.org/data/Sample20.zip";
"sample21" "https://www.c3d.org/data/Sample21.zip";
"sample24" "https://www.c3d.org/data/Sample24.zip";
"sample25" "https://www.c3d.org/data/Sample25.zip";
"sample32" "https://www.c3d.org/data/Sample32.zip";
 ]

tempdatadir = mktempdir();

arts = TOML.parsefile("Artifacts.toml")

for i in axes(sampledatalinks, 1)
    sampname = sampledatalinks[i,1]
    if haskey(arts, sampname)
        @info "$sampname exists; skipping..."
        continue
    end
    @info sampname
    downloaded_samp = Downloads.download(sampledatalinks[i,2])
    unzipdir = mkdir(joinpath(tempdatadir, sampname))
    run(`unzip $(downloaded_samp) -d $unzipdir`)
    artifact_id = artifact_from_directory(unzipdir)
    gist = upload_to_gist(artifact_id; private=false)
    add_artifact!("Artifacts.toml", sampname, gist)
end

# # Sample 31
# samp31 = Downloads.download("https://www.c3d.org/data/Sample31.zip")
# Tar.create(samp31, joinpath(@__DIR__, "sample31.tar"))
# run(`gzip $(joinpath(@__DIR__, "sample31.tar"))`)
# # Manually upload to GitHub release for tag "longdata" (larger file size limit, 2Gb, for release artifacts)
# add_artifact!("Artifacts.toml", "sample31", "https://github.com/halleysfifthinc/C3D.jl/releases/download/longdata/sample31.tar.gz")
