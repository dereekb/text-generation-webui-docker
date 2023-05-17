FROM nvidia/cuda:11.8.0-devel-ubuntu22.04 AS env_base
# Pre-reqs
RUN apt-get update && apt-get install --no-install-recommends -y \
    git vim build-essential python3-dev python3-venv python3-pip
# Instantiate venv and pre-activate
RUN pip3 install virtualenv
RUN virtualenv /venv
# Credit, Itamar Turner-Trauring: https://pythonspeed.com/articles/activate-virtualenv-dockerfile/
ENV VIRTUAL_ENV=/venv
RUN python3 -m venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"
RUN pip3 install --upgrade pip setuptools && \
    pip3 install torch torchvision torchaudio


FROM env_base AS app_base 
### DEVELOPERS/ADVANCED USERS ###
# Clone oobabooga/text-generation-webui
RUN git clone https://github.com/oobabooga/text-generation-webui /src
# To use local source: comment out the git clone command then set the build arg `LCL_SRC_DIR`
#ARG LCL_SRC_DIR="text-generation-webui"
#COPY ${LCL_SRC_DIR} /src
#################################
# Copy source to app
RUN cp -ar /src /app
# Install oobabooga/text-generation-webui
RUN --mount=type=cache,target=/root/.cache/pip pip3 install -r /app/requirements.txt
# Install extensions
COPY ./scripts/build_extensions.sh /scripts/build_extensions.sh
RUN --mount=type=cache,target=/root/.cache/pip \
    chmod +x /scripts/build_extensions.sh && . /scripts/build_extensions.sh
# Clone default GPTQ
RUN git clone https://github.com/oobabooga/GPTQ-for-LLaMa.git -b cuda /app/repositories/GPTQ-for-LLaMa
# Build and install default GPTQ ('quant_cuda')
ARG TORCH_CUDA_ARCH_LIST="6.1;7.0;7.5;8.0;8.6+PTX"
RUN cd /app/repositories/GPTQ-for-LLaMa/ && python3 setup_cuda.py install


FROM nvidia/cuda:11.8.0-runtime-ubuntu22.04 AS base
# Runtime pre-reqs
RUN apt-get update && apt-get install --no-install-recommends -y \
    python3-venv git
# Copy app and src
COPY --from=app_base /app /app
COPY --from=app_base /src /src
# Copy and activate venv
COPY --from=app_base /venv /venv
ENV VIRTUAL_ENV=/venv
RUN python3 -m venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"
# Finalise app setup
WORKDIR /app
EXPOSE 7860
EXPOSE 5000
EXPOSE 5005
# Required for Python print statements to appear in logs
ENV PYTHONUNBUFFERED=1  
# Run
COPY ./scripts/docker-entrypoint.sh /scripts/docker-entrypoint.sh
RUN chmod +x /scripts/docker-entrypoint.sh
ENTRYPOINT ["/scripts/docker-entrypoint.sh"]



# VARIANT BUILDS
FROM base AS cuda
RUN echo "CUDA" >> /variant.txt
RUN apt-get install --no-install-recommends -y git python3-dev python3-pip
RUN rm -rf /app/repositories/GPTQ-for-LLaMa && \
    git clone https://github.com/qwopqwop200/GPTQ-for-LLaMa -b cuda /app/repositories/GPTQ-for-LLaMa
RUN pip3 uninstall -y quant-cuda && \
    pip3 install -r /app/repositories/GPTQ-for-LLaMa/requirements.txt
ENV EXTRA_LAUNCH_ARGS=""
CMD ["python3", "/app/server.py"]


FROM base AS triton
RUN echo "TRITON" >> /variant.txt
RUN apt-get install --no-install-recommends -y git python3-dev build-essential python3-pip
RUN rm -rf /app/repositories/GPTQ-for-LLaMa && \
    git clone https://github.com/qwopqwop200/GPTQ-for-LLaMa -b triton /app/repositories/GPTQ-for-LLaMa
RUN pip3 uninstall -y quant-cuda && \
    pip3 install -r /app/repositories/GPTQ-for-LLaMa/requirements.txt
ENV EXTRA_LAUNCH_ARGS=""
CMD ["python3", "/app/server.py"]


FROM base AS default
RUN echo "DEFAULT" >> /variant.txt
ENV EXTRA_LAUNCH_ARGS=""
CMD ["python3", "/app/server.py"]