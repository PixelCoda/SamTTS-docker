FROM debian:buster-slim as build

ENV LANG C.UTF-8

# IFDEF PROXY
#! RUN echo 'Acquire::http { Proxy "http://${APT_PROXY_HOST}:${APT_PROXY_PORT}"; };' >> /etc/apt/apt.conf.d/01proxy
# ENDIF

RUN apt-get update && \
    apt-get install --yes --no-install-recommends \
        build-essential \
        python3 python3-dev python3-pip python3-venv python3-setuptools \
        espeak libsndfile1 git \
        llvm-11 llvm-11-dev llvm-11-tools libatlas-base-dev libopenblas-dev gfortran \
        ca-certificates wget python3-wheel curl ca-certificates

ENV LLVM_CONFIG=/usr/bin/llvm-config-7

COPY source/ /source/

RUN mkdir -p /app && \
    cd /app && \
    if [ -f '/source/TTS.tar.gz' ]; then \
      tar -C /app -xf /source/TTS.tar.gz; \
    else \
      git clone https://github.com/mozilla/TTS; \
    fi

ENV VENV=/app/venv
RUN python3 -m venv ${VENV}

# IFDEF PROXY
#! ENV PIP_INDEX_URL=http://${PYPI_PROXY_HOST}:${PYPI_PROXY_PORT}/simple/
#! ENV PIP_TRUSTED_HOST=${PYPI_PROXY_HOST}
# ENDIF

# Set up Python virtual environment
# RUN ${VENV}/bin/pip3 install --upgrade pip && \
#     ${VENV}/bin/pip3 install --upgrade wheel setuptools

# Target architecture
ARG TARGETARCH
ARG TARGETVARIANT

# Copy shared and architecture-specific files
COPY download/shared/ /download/
COPY download/${TARGETARCH}${TARGETVARIANT}/ /download/

RUN wget https://files.pythonhosted.org/packages/5d/5e/35140615fc1f925023f489e71086a9ecc188053d263d3594237281284d82/torch-1.6.0-cp37-cp37m-manylinux1_x86_64.whl -P download/

# IFDEF NOAVX
#! RUN mv download/noavx/* download/
# ENDIF

# RUN wget --no-check-certificate -O - https://apt.llvm.org/llvm-snapshot.gpg.key | sudo apt-key add -
# RUN add-apt-repository 'deb http://apt.llvm.org/buster/   llvm-toolchain-buster-11  main'
# RUN apt update
# RUN apt install llvm

RUN ${VENV}/bin/pip3 install -f download/ 'numpy==1.20.1' 'wheel'

# Install torch from local cache if present
# RUN ${VENV}/bin/pip3 install git+https://github.com/pytorch/pytorch.git@b31f58de6fa8bbda5353b3c77d9be4914399724d



# Install the rest of the requirements
RUN cd /app/TTS && \
    if [ -f /download/requirements.txt ]; then cp /download/requirements.txt . ; fi && \
    ${VENV}/bin/pip3 install -f /download -r requirements.txt

# Install MozillaTTS itself
RUN cd /app/TTS && \
    ${VENV}/bin/python3 setup.py install

# Packages needed for web server
RUN ${VENV}/bin/pip3 install -f download/ 'quart' 'quart-cors'

# -----------------------------------------------------------------------------

FROM debian:buster-slim

ENV LANG C.UTF-8

# IFDEF PROXY
#! RUN echo 'Acquire::http { Proxy "http://${APT_PROXY_HOST}:${APT_PROXY_PORT}"; };' >> /etc/apt/apt.conf.d/01proxy
# ENDIF

RUN apt-get update && \
    apt-get install --yes --no-install-recommends \
        python3 python3-distutils python3-llvmlite libpython3.7 \
        espeak libsndfile1 git \
        espeak \
        libsndfile1 libgomp1 libatlas3-base libgfortran4 libopenblas-base \
        libjbig0 liblcms2-2 libopenjp2-7 libtiff5 libwebp6 libwebpdemux2 libwebpmux3 \
        libnuma1

# IFDEF PROXY
#! RUN rm -f /etc/apt/apt.conf.d/01proxy
# ENDIF

COPY --from=build /app/venv/ /app/

ARG LANGUAGE=en
COPY model/${LANGUAGE}/ /app/model/
COPY tts_web/ /app/tts_web/
COPY run.sh /

WORKDIR /app

EXPOSE 5002

ENTRYPOINT ["/bin/bash", "/run.sh"]
