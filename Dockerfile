# NOTE: Updating the packages to their latest versions requires bumping the
# Dockerfile args below. For more info about this file, read
# docs/developer/reproducibility.md.

ARG DEBIAN_IMAGE_DATE=20250113

FROM debian:bookworm-${DEBIAN_IMAGE_DATE}-slim

ARG GVISOR_ARCHIVE_DATE=20250106
ARG DEBIAN_ARCHIVE_DATE=20250114
ARG H2ORESTART_CHECKSUM=8a5be77359695c14faaf33891d3eca6c9d73c1224599aab50a9d2ccc04640580
ARG H2ORESTART_VERSION=v0.6.8

ENV DEBIAN_FRONTEND=noninteractive

# The following way of installing packages is taken from
# https://github.com/reproducible-containers/repro-sources-list.sh/blob/master/Dockerfile.debian-12,
# and adapted to allow installing gVisor from each own repo as well.
RUN \
  --mount=type=cache,target=/var/cache/apt,sharing=locked \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  --mount=type=bind,source=./container/repro-sources-list.sh,target=/usr/local/bin/repro-sources-list.sh \
  --mount=type=bind,source=./container/gvisor.key,target=/tmp/gvisor.key \
  : "Hacky way to set a date for the Debian snapshot repos" && \
  touch -d ${DEBIAN_ARCHIVE_DATE} /etc/apt/sources.list.d/debian.sources && \
  touch -d ${DEBIAN_ARCHIVE_DATE} /etc/apt/sources.list && \
  repro-sources-list.sh && \
  : "Setup APT to install gVisor from its separate APT repo" && \
  apt-get update && \
  apt-get upgrade -y && \
  apt-get install -y --no-install-recommends apt-transport-https ca-certificates gnupg && \
  gpg -o /usr/share/keyrings/gvisor-archive-keyring.gpg --dearmor /tmp/gvisor.key && \
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/gvisor-archive-keyring.gpg] https://storage.googleapis.com/gvisor/releases ${GVISOR_ARCHIVE_DATE} main" > /etc/apt/sources.list.d/gvisor.list && \
  : "Install the necessary gVisor and Dangerzone dependencies" && \
  apt-get update && \
  apt-get install -y --no-install-recommends \
      python3 python3-fitz libreoffice-nogui libreoffice-java-common \
      python3 python3-magic default-jre-headless fonts-noto-cjk fonts-dejavu \
      runsc unzip wget && \
  : "Clean up for improving reproducibility (optional)" && \
  rm -rf /var/cache/fontconfig/ && \
  rm -rf /etc/ssl/certs/java/cacerts && \
  rm -rf /var/log/* /var/cache/ldconfig/aux-cache

# Download H2ORestart from GitHub using a pinned version and hash. Note that
# it's available in Debian repos, but not in Bookworm yet.
RUN mkdir /libreoffice_ext && cd libreoffice_ext \
    && H2ORESTART_FILENAME=h2orestart.oxt \
    && wget https://github.com/ebandal/H2Orestart/releases/download/$H2ORESTART_VERSION/$H2ORESTART_FILENAME \
    && echo "$H2ORESTART_CHECKSUM  $H2ORESTART_FILENAME" | sha256sum -c \
    && install -dm777 "/usr/lib/libreoffice/share/extensions/" \
    && rm /root/.wget-hsts

# Create an unprivileged user both for gVisor and for running Dangerzone.
RUN mkdir -p /opt/dangerzone/dangerzone && \
  touch /opt/dangerzone/dangerzone/__init__.py && \
  addgroup --gid 1000 dangerzone && \
  adduser --uid 1000 --ingroup dangerzone --shell /bin/true \
      --disabled-password --home /home/dangerzone dangerzone

COPY conversion/doc_to_pixels.py \
    conversion/common.py \
    conversion/errors.py \
    conversion/__init__.py \
    /opt/dangerzone/dangerzone/conversion

# Let the entrypoint script write the OCI config for the inner container under
# /config.json.
RUN touch /config.json
RUN chown dangerzone:dangerzone /config.json

# Switch to the dangerzone user for the rest of the script.
USER dangerzone

# Create a directory that will be used by gVisor as the place where it will
# store the state of its containers.
RUN mkdir /home/dangerzone/.containers

COPY container/entrypoint.py /

ENTRYPOINT ["/entrypoint.py"]
