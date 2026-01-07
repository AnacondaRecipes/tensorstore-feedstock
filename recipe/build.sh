#!/bin/bash

set -euxo pipefail

source gen-bazel-toolchain

system_libs="com_google_boringssl"
system_libs+=",org_sourceware_bzip2"
system_libs+=",org_blosc_cblosc"
system_libs+=",se_curl"
system_libs+=",jpeg"
system_libs+=",png"
system_libs+=",libwebp"
system_libs+=",org_lz4"
system_libs+=",org_tukaani_xz"
system_libs+=",net_zlib"
system_libs+=",com_github_pybind_pybind11"
system_libs+=",com_github_nlohmann_json"
system_libs+=",org_aomedia_avif"
# system_libs+=",com_google_absl"
export TENSORSTORE_SYSTEM_LIBS="$system_libs"

build_options=""
build_options+=" --crosstool_top=//bazel_toolchain:toolchain"
build_options+=" --logging=6"
build_options+=" --verbose_failures"
build_options+=" --toolchain_resolution_debug"
build_options+=" --local_cpu_resources=${CPU_COUNT}"
build_options+=" --cpu=${TARGET_CPU}"
build_options+=" --subcommands"  # comment out for debugging
export TENSORSTORE_BAZEL_BUILD_OPTIONS="$build_options"

# Disble bazel sandbox build, because it goes with toolchain error
# src/main/tools/process-wrapper-legacy.cc:80: 
# "execvp(bazel_toolchain/crosstool_wrapper_driver_is_not_gcc, ...)": No such file or directory
build_options+=" --spawn_strategy=standalone"

# TODO: figure out why we need both TENSORSTORE_BAZEL_BUILD_OPTIONS and a bazelrc
cat > .bazelrc <<EOF
build --crosstool_top=//custom_toolchain:toolchain
build --logging=6
build --verbose_failures
build --local_cpu_resources=${CPU_COUNT}
EOF

# replace bundled baselisk with a simpler forwarder to our own bazel in build prefix
export BAZEL_EXE="${BUILD_PREFIX}/bin/bazel"
export TENSORSTORE_BAZELISK="${RECIPE_DIR}/bazelisk_shim.py"

${PYTHON} -m pip install . -vv

# Save vendored licenses
mkdir -p licenses
ls bazel-work/external/
cp bazel-work/external/com_google_absl/LICENSE "${SRC_DIR}/licenses/com_google_absl.txt"
cp bazel-work/external/com_google_re2/LICENSE "${SRC_DIR}/licenses/com_google_re2.txt"
cp bazel-work/external/com_google_riegeli/LICENSE "${SRC_DIR}/licenses/com_google_riegeli.txt"
cp bazel-work/external/net_sourceforge_half/LICENSE.txt "${SRC_DIR}/licenses/net_sourceforge_half.txt"

# Clean up a bit to speed-up prefix post-processing
bazel clean || true
bazel shutdown || true
