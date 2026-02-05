#!/usr/bin/env bash
set -euxo pipefail

# NOTE (for maintainers)

# 1) Clang modules MUST be disabled on macOS.
#    Bazel + Apple Clang modules cause “outside of execution root” and random
#    header failures (absl, protobuf, libc). We explicitly disable modules for
#    both host and target builds.

# 2) System libraries via TENSORSTORE_SYSTEM_LIBS require extra handling.
#    In conda-build, headers/libs live under $PREFIX. Bazel does not see them
#    by default. third_party/repo.bzl is patched to:
#      - symlink $PREFIX/include, $PREFIX/lib into external repos
#      - expose PREFIX / CONDA_PREFIX to repository rules

#    All system.BUILD.bazel files must explicitly export:
#      hdrs = glob(["include/**/*.h"])
#      includes = ["include"]

# 3) Protobuf MUST remain vendored!
#    Using system protobuf is not supported in practice:
#      - Bazel generates .pb.h files with its own protoc
#      - Mixing system headers causes version mismatch errors
#      - Bazel creates an internal “protobuf~” repo which conflicts
#    Therefore com_google_protobuf MUST NOT be added to TENSORSTORE_SYSTEM_LIBS.

# 4) bzlmod must be disabled.
#    Newer Bazel enables bzlmod by default, which breaks TensorStore builds
#    (duplicate protobuf repos, toolchain failures).
#    Always use:
#      common --noenable_bzlmod

# 5) Linker paths are NOT automatic.
#    Even with system libs, Bazel does not add $PREFIX/lib to the linker.
#    We must explicitly add:
#      -L$PREFIX/lib
#      -Wl,-rpath,$PREFIX/lib

source gen-bazel-toolchain

# we use openssl instead of boringssl
system_libs="com_google_boringssl"
system_libs+=",org_sourceware_bzip2"
system_libs+=",org_blosc_cblosc"
system_libs+=",se_curl"
system_libs+=",jpeg"
system_libs+=",libtiff"
system_libs+=",png"
system_libs+=",libwebp"
system_libs+=",org_lz4"
system_libs+=",net_zlib"
system_libs+=",com_github_pybind_pybind11"
system_libs+=",com_github_nlohmann_json"
system_libs+=",org_aomedia_avif"
export TENSORSTORE_SYSTEM_LIBS="$system_libs"

build_options=""
build_options+=" --crosstool_top=//bazel_toolchain:toolchain"
build_options+=" --logging=6"
build_options+=" --verbose_failures"
build_options+=" --toolchain_resolution_debug"
build_options+=" --local_cpu_resources=${CPU_COUNT}"
build_options+=" --cpu=${TARGET_CPU}"
build_options+=" --subcommands"  # comment out for debugging

if [[ "$target_platform" == osx-* ]] ; then
    build_options+=" --cxxopt=-Wno-missing-template-arg-list-after-template-kw"
    build_options+=" --cxxopt=-Wno-error=missing-template-arg-list-after-template-kw"
    # Disable clang modules (target + host)
    build_options+=" --features=-modules"
    build_options+=" --features=-module_maps"
    build_options+=" --features=-use_header_modules"
    build_options+=" --host_features=-modules"
    build_options+=" --host_features=-module_maps"
    build_options+=" --host_features=-use_header_modules"
    # Extra hard-disable in case toolchain still tries modules
    build_options+=" --copt=-fno-modules"
    build_options+=" --cxxopt=-fno-modules"
    build_options+=" --host_copt=-fno-modules"
    build_options+=" --host_cxxopt=-fno-modules"
fi

# Disble bazel sandbox build, because it goes with toolchain error
# src/main/tools/process-wrapper-legacy.cc:80: 
# "execvp(bazel_toolchain/crosstool_wrapper_driver_is_not_gcc, ...)": No such file or directory
build_options+=" --spawn_strategy=standalone"
export TENSORSTORE_BAZEL_BUILD_OPTIONS="$build_options"

cat > .bazelrc <<EOF
build --crosstool_top=//bazel_toolchain:toolchain
build --logging=6
build --verbose_failures
build --spawn_strategy=standalone
build --local_cpu_resources=${CPU_COUNT}
build --cxxopt=-std=c++17
build --host_cxxopt=-std=c++17

# allow repo rules to see PREFIX (твои symlink'и include/lib)
build --repo_env=PREFIX=${PREFIX}
build --repo_env=CONDA_PREFIX=${PREFIX}

# critical: disable bzlmod to avoid cmake_to_bazel protobuf~ etc.
common --noenable_bzlmod

# help linker find conda libs + runtime load
build --linkopt=-L${PREFIX}/lib
build --linkopt=-Wl,-rpath,${PREFIX}/lib
build --host_linkopt=-L${PREFIX}/lib
build --host_linkopt=-Wl,-rpath,${PREFIX}/lib
EOF

# replace bundled baselisk with a simpler forwarder to our own bazel in build prefix
export BAZEL_EXE="${BUILD_PREFIX}/bin/bazel"
export TENSORSTORE_BAZELISK="${RECIPE_DIR}/bazelisk_shim.py"

${PYTHON} -m pip install . --no-deps --no-build-isolation --ignore-installed --no-cache-dir -vv

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
