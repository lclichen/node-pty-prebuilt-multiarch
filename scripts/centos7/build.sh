#!/usr/bin/env bash
#
# Build the CentOS 7 (glibc 2.17) compatible prebuilt for node-pty.
# Run from the repository root on any machine with Docker (this is also
# what the GitHub Actions workflow runs):
#
#   bash scripts/centos7/build.sh
#   NODE_VERSION=22.23.0 bash scripts/centos7/build.sh
#
# Produces:
#   build/Release/pty.node              compiled binary
#   prebuilds/linux-x64/node.abi*.node  loader layout (same N-API binary)
#   lib/                                compiled JavaScript
#
set -euxo pipefail

NODE_VERSION="${NODE_VERSION:-22.23.0}"

# Unofficial Node.js build linked against glibc 2.17 - the newest Node line
# that still runs on CentOS 7 (official builds require glibc >= 2.28 since
# Node 18). See https://github.com/nodejs/unofficial-builds
curl -fsSLo .node-dist.tar.gz \
  "https://unofficial-builds.nodejs.org/download/release/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64-glibc-217.tar.gz"

docker run --rm \
  -v "${PWD}:/src" -w /src \
  -e NODE_DIST_TAR=/src/.node-dist.tar.gz \
  quay.io/pypa/manylinux2014_x86_64 \
  bash scripts/centos7/build-in-container.sh
