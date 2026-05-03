#Build Stage
FROM fuzzers/aflplusplus:3.12c AS builder

##Install Build Dependencies
RUN apt-get update && \
        DEBIAN_FRONTEND=noninteractive apt-get install -y python3 sudo curl libpulse-dev pulseaudio wget cmake make autoconf automake build-essential tar
##ADD source code to the build stage
WORKDIR /
ADD . /spchcat
WORKDIR /spchcat

##Build
RUN ./scripts/download_libs.sh
RUN mkdir -p build/models/en_US
WORKDIR build/models/en_US
RUN wget https://github.com/coqui-ai/STT-models/releases/download/english%2Fcoqui%2Fv1.0.0-huge-vocab/model.tflite
WORKDIR /spchcat
ENV LD_LIBRARY_PATH=/spchcat/build/lib${LD_LIBRARY_PATH}
ENV BUILD_FOR_AFL=1
RUN ls
RUN make

FROM fuzzers/aflplusplus:3.12c
RUN apt-get update && \
        DEBIAN_FRONTEND=noninteractive apt-get install -y libpulse0 libstdc++6 libgcc-s1 libdbus-1-3 libxcb1 libsystemd0 libwrap0 libsndfile1 libasyncns0 libapparmor1 libxau6 libxdmcp6 liblzma5 liblz4-1 libgcrypt20 libc6 libflac8 libogg0 libvorbis0a libvorbisenc2 libbsd0 libgpg-error0
COPY --from=builder /spchcat/build/models /models
COPY --from=builder /spchcat/corpus /tests
COPY --from=builder /spchcat/build/bin/spchcat /spchcat
COPY --from=builder /spchcat/build/lib /usr/lib
ENTRYPOINT ["afl-fuzz", "-i", "/tests", "-o", "-out", "-t", "10"]
CMD ["/spchcat", "--languages_dir=/models", "@@"]
