#!/usr/bin/env bash
#
# Build a CentOS 7 (glibc 2.17) compatible prebuilt of node-pty.
#
# This script runs INSIDE the manylinux2014 container (launched by build.sh
# or by .github/workflows/centos7-prebuild.yml):
#
#   - manylinux2014 is based on CentOS 7 -> glibc 2.17, exactly the target
#     environment, so the produced binary cannot require anything newer
#   - the image ships devtoolset-10 (gcc 10, full C++17 support) and
#     python 3.8, which node-gyp needs
#
# Inputs (env):
#   NODE_DIST_TAR  path to a Node.js tarball of the unofficial
#                  "linux-x64-glibc-217" variant (runs on glibc >= 2.17)
#
# Outputs:
#   build/Release/pty.node               the compiled addon
#   prebuilds/linux-x64/node.abi*.node   loader layout for many Node ABIs
#   lib/                                 compiled JavaScript
#
set -euxo pipefail

NODE_DIST_TAR="${NODE_DIST_TAR:-/src/.node-dist.tar.gz}"

# manylinux toolchain: devtoolset-10 (gcc 10, full C++17) for compiling, and
# a CPython from the image for node-gyp. The exact /opt/python/cpXY versions
# shipped change over time (EOL'ed CPythons get dropped from the image), so
# discover the newest one instead of hardcoding a path.
PYTHON_BIN_DIR=$(ls -d /opt/python/cp3*/bin 2>/dev/null | sort -V | tail -1 || true)
if [ -z "${PYTHON_BIN_DIR}" ]; then
  echo "ERROR: no CPython found under /opt/python" >&2
  exit 1
fi
export PATH="/opt/rh/devtoolset-10/root/usr/bin:${PYTHON_BIN_DIR}:/usr/local/bin:${PATH}"

gcc --version | head -1
python3 --version

# Node.js: unofficial "glibc-217" build, runs on glibc >= 2.17 (CentOS 7)
tar -xzf "${NODE_DIST_TAR}" -C /usr/local --strip-components=1
export PATH="/usr/local/bin:${PATH}"
node -p "'node ' + process.version + ' (abi ' + process.versions.modules + ')'"
npm -v

# Install dependencies WITHOUT running lifecycle scripts: the default install
# chain would try `prebuild-install`, which downloads upstream binaries built
# against a newer glibc (Debian bookworm) - those cannot load on CentOS 7.
npm ci --ignore-scripts

# TypeScript -> lib/
npm run build

# C++ -> build/Release/pty.node
./node_modules/.bin/node-gyp rebuild
ls -la build/Release/

# Assemble prebuilds/linux-x64/ - the layout the runtime loader looks for
# (src/prebuild-file-path.ts).
mkdir -p prebuilds/linux-x64
cp build/Release/pty.node "prebuilds/linux-x64/node.abi$(node -p process.versions.modules).node"

# The addon is pure N-API (node-addon-api): a single binary loads on every
# Node >= its N-API level (NAPI 8 => Node 16+), regardless of ABI. Ship one
# filename per common ABI so the loader always finds a match without any
# local compilation.
ABI_FILES=$(node - <<'EOF'
const wanted = new Set(['16.0.0', '17.0.1', '18.0.0', '19.0.0', '20.0.0',
                        '21.0.0', '22.0.0', '23.0.0', '24.0.0', '25.0.0', '26.0.0']);
for (const e of require('./abi_registry.json')) {
  if (e.runtime === 'node' && wanted.has(e.target)) {
    console.log(`node.abi${e.abi}.node`);
  }
}
EOF
)
for name in $(printf '%s\n' "${ABI_FILES}" | sort -u); do
  cp build/Release/pty.node "prebuilds/linux-x64/${name}"
done
ls -la prebuilds/linux-x64/

# Functional check on this glibc 2.17 environment: the loader must pick the
# prebuild, and a real pty must spawn and die cleanly.
node scripts/check-prebuild.js
node - <<'EOF'
const pty = require('./lib/index.js');
const p = pty.spawn('/bin/sh', [], { name: 'xterm', cols: 80, rows: 24 });
console.log('spawned /bin/sh, pid =', p.pid);
p.kill();
console.log('SMOKE TEST OK');
EOF

# Hard requirement check: referenced symbol versions must not exceed what
# CentOS 7 provides (glibc 2.17 / libstdc++ GLIBCXX 3.4.19). Strip the
# GLIBC_/GLIBCXX_ prefix before comparing, so sort -V sees plain versions.
MAX_GLIBC=$(objdump -T build/Release/pty.node | grep -oE 'GLIBC_[0-9.]+' | sed 's/^GLIBC_//' | sort -uV | tail -1 || true)
MAX_GLIBCXX=$(objdump -T build/Release/pty.node | grep -oE 'GLIBCXX_[0-9.]+' | sed 's/^GLIBCXX_//' | sort -uV | tail -1 || true)
echo "max GLIBC = ${MAX_GLIBC:-<none>}   max GLIBCXX = ${MAX_GLIBCXX:-<none>}"
[ -z "${MAX_GLIBC}" ]   || [ "$(printf '%s\n2.17\n'    "${MAX_GLIBC}"   | sort -uV | tail -1)" = "2.17" ]
[ -z "${MAX_GLIBCXX}" ] || [ "$(printf '%s\n3.4.19\n' "${MAX_GLIBCXX}" | sort -uV | tail -1)" = "3.4.19" ]

echo 'BUILD OK'
