#!/bin/bash
# build openGauss arm64
docker buildx build --platform linux/arm -f ./openeuler_open_gauss/Dockerfile --build-arg OPENGAUSS_VERSION=5.0.3_arm -t server.aiknown.cn:31003/z-rps/opengauss:5.0.3_arm .