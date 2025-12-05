#!/bin/bash
# build openGauss
docker buildx build --platform linux/amd64 -f ./openeuler_open_gauss/Dockerfile -t server.aiknown.cn:31003/z-rps/opengauss:5.0.3 .