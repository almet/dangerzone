###########################################
# Build PyMuPDF

FROM alpine:latest as pymupdf-build
ARG ARCH
ARG REQUIREMENTS_TXT

# Install PyMuPDF via hash-checked requirements file
COPY ${REQUIREMENTS_TXT} /tmp/requirements.txt

# PyMuPDF provides non-arm musl wheels only.
# Only install build-dependencies if we are actually building the wheel
RUN case "$ARCH" in \
    "arm64") \
        # This is required for copying later, but is created only in the pre-built wheels
        mkdir -p /usr/lib/python3.12/site-packages/PyMuPDF.libs/ \
        && apk --no-cache add linux-headers g++ linux-headers gcc make python3-dev py3-pip clang-dev ;; \
    *) \
        apk --no-cache add py3-pip ;; \
    esac
RUN pip install -vv --break-system-packages --require-hashes -r /tmp/requirements.txt


###########################################
# Download H2ORestart
FROM alpine:latest as h2orestart-dl
ARG H2ORESTART_CHECKSUM=d09bc5c93fe2483a7e4a57985d2a8d0e4efae2efb04375fe4b59a68afd7241e2
RUN mkdir /libreoffice_ext && cd libreoffice_ext \
    && H2ORESTART_FILENAME=h2orestart.oxt \
    && H2ORESTART_VERSION="v0.6.6" \
    && wget https://github.com/ebandal/H2Orestart/releases/download/$H2ORESTART_VERSION/$H2ORESTART_FILENAME \
    && echo "$H2ORESTART_CHECKSUM  $H2ORESTART_FILENAME" | sha256sum -c \
    && install -dm777 "/usr/lib/libreoffice/share/extensions/"


###########################################
# Dangerzone image

FROM alpine:latest

# Install dependencies
RUN apk --no-cache -U upgrade && \
    apk --no-cache add \
    libreoffice \
    openjdk8 \
    python3 \
    py3-magic \
    font-noto-cjk

COPY --from=pymupdf-build /usr/lib/python3.12/site-packages/fitz/ /usr/lib/python3.12/site-packages/fitz
COPY --from=pymupdf-build /usr/lib/python3.12/site-packages/pymupdf/ /usr/lib/python3.12/site-packages/pymupdf
COPY --from=pymupdf-build /usr/lib/python3.12/site-packages/PyMuPDF.libs/ /usr/lib/python3.12/site-packages/PyMuPDF.libs
COPY --from=h2orestart-dl /libreoffice_ext/ /libreoffice_ext

RUN install -dm777 "/usr/lib/libreoffice/share/extensions/"

RUN mkdir -p /opt/dangerzone/dangerzone
RUN touch /opt/dangerzone/dangerzone/__init__.py
COPY conversion /opt/dangerzone/dangerzone/conversion

# Add the unprivileged user. Set the UID/GID of the dangerzone user/group to
# 1000, since we will point to it from the OCI config.
#
# NOTE: A tmpfs will be mounted over /home/dangerzone directory,
# so nothing within it from the image will be persisted.
RUN addgroup -g 1000 dangerzone && \
    adduser -u 1000 -s /bin/true -G dangerzone -h /home/dangerzone -D dangerzone

RUN GVISOR_URL="https://storage.googleapis.com/gvisor/releases/release/latest/$(uname -m)"; \
    wget "${GVISOR_URL}/runsc" "${GVISOR_URL}/runsc.sha512" && \
    sha512sum -c runsc.sha512 && \
    rm -f runsc.sha512 && \
    chmod 555 runsc && \
    mv runsc /usr/bin/

RUN touch /config.json
RUN chown dangerzone:dangerzone /config.json

# Switch to the dangerzone user for the rest of the script.
USER dangerzone

# Create a directory that will be used by gVisor as the place where it will
# store the state of its containers.
RUN mkdir /home/dangerzone/.containers

COPY container/entrypoint.py /

ENTRYPOINT ["/entrypoint.py"]
