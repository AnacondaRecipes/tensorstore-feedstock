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
export TENSORSTORE_USE_SYSTEM_NUMPY=1

source gen-bazel-toolchain

# we use openssl instead of boringssl
system_libs="com_google_boringssl"
system_libs+=",org_sourceware_bzip2"
system_libs+=",se_curl"
system_libs+=",libtiff"
system_libs+=",png"
system_libs+=",libjpeg_turbo"
system_libs+=",libwebp"
system_libs+=",net_zlib"
system_libs+=",com_github_nlohmann_json"
system_libs+=",org_aomedia_avif"
# These names must match the Bazel repo names in third_party/*/workspace.bzl.
# system_libs+=",abseil-cpp"
export TENSORSTORE_SYSTEM_LIBS="$system_libs"

build_options=""
build_options+=" --crosstool_top=//bazel_toolchain:toolchain"
build_options+=" --platforms=//bazel_toolchain:target_platform"
build_options+=" --host_platform=//bazel_toolchain:build_platform"
build_options+=" --extra_toolchains=//bazel_toolchain:cc_cf_toolchain"
build_options+=" --extra_toolchains=//bazel_toolchain:cc_cf_host_toolchain"
build_options+=" --logging=6"
build_options+=" --verbose_failures"
build_options+=" --toolchain_resolution_debug=.*"
build_options+=" --enable_workspace"  # Bazel 8 compatibility: use WORKSPACE instead of MODULE.bazel
build_options+=" --noenable_bzlmod"
build_options+=" --define=with_cross_compiler_support=true"
build_options+=" --local_cpu_resources=${CPU_COUNT}"
build_options+=" --cpu=${TARGET_CPU}"
build_options+=" --subcommands"  # comment out for debugging
export TENSORSTORE_BAZEL_BUILD_OPTIONS="$build_options"

cat > .bazelrc <<EOF
build --crosstool_top=//bazel_toolchain:toolchain
build --platforms=//bazel_toolchain:target_platform
build --host_platform=//bazel_toolchain:build_platform
build --extra_toolchains=//bazel_toolchain:cc_cf_toolchain
build --extra_toolchains=//bazel_toolchain:cc_cf_host_toolchain
build --logging=6
build --verbose_failures
build --toolchain_resolution_debug=.*
build --enable_workspace
build --noenable_bzlmod
build --define=with_cross_compiler_support=true
build --local_cpu_resources=${CPU_COUNT}
build --cpu=${TARGET_CPU}
EOF

# replace bundled baselisk with a simpler forwarder to our own bazel in build prefix
export BAZEL_EXE="${BUILD_PREFIX}/bin/bazel"
export TENSORSTORE_BAZELISK="${RECIPE_DIR}/bazelisk_shim.py"

${PYTHON} -m pip install . --no-deps --no-build-isolation --ignore-installed --no-cache-dir -vv

# Save vendored licenses
mkdir -p licenses
ls bazel-work/external/

copy_vendored_license() {
    local out_name="$1"
    shift
    local repo
    local candidate
    for repo in "$@"; do
        for candidate in LICENSE LICENSE.txt COPYING COPYING.txt; do
            if [[ -f "bazel-work/external/${repo}/${candidate}" ]]; then
                cp "bazel-work/external/${repo}/${candidate}" "${SRC_DIR}/licenses/${out_name}"
                return 0
            fi
        done
    done
    echo "Could not locate vendored license for ${out_name}. Checked repos: $*" >&2
    return 1
}

copy_vendored_license com_google_absl.txt abseil-cpp com_google_absl
copy_vendored_license com_google_re2.txt re2 com_google_re2
copy_vendored_license com_google_riegeli.txt riegeli com_google_riegeli
copy_vendored_license net_sourceforge_half.txt net_sourceforge_half

# Clean up a bit to speed-up prefix post-processing
bazel clean || true
bazel shutdown || true
