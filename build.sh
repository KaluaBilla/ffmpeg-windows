#!/bin/bash

set -xe

ARCH="${1:-$ARCH}"
API_LEVEL="${2:-$API_LEVEL}"
API_LEVEL="${API_LEVEL:-29}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VALID_ARCHES="aarch64 armv7 x86 x86_64 riscv64"

if [[ -z "$ARCH" || ! " $VALID_ARCHES " =~ $ARCH ]]; then
	echo "Usage: $0 <aarch64|armv7|x86|x86_64> [API_LEVEL]"
	echo "Default API_LEVEL: 29"
	exit 1
fi

source "${ROOT_DIR}/scripts/check_cmds.sh"

case "$(uname -s)" in
Linux) HOST_OS=linux ;;
Darwin) HOST_OS=darwin ;;
CYGWIN* | MINGW* | MSYS*) HOST_OS=windows ;;
*)
	echo "ERROR: Unsupported host OS: $(uname -s)"
	exit 1
	;;
esac

case "$ARCH" in
aarch64)
	HOST=aarch64-w64-mingw32
	CLANG_TRIPLE=$HOST
	RUST_TARGET=aarch64-pc-windows-gnu
	CPU=aarch64
	;;
x86)
	HOST=i686-w64-mingw32
	CLANG_TRIPLE=$HOST
	RUST_TARGET=i686-pc-windows-gnu
	CPU=i686
	;;
x86_64)
	HOST=x86_64-w64-mingw32
	CLANG_TRIPLE=$HOST
	RUST_TARGET=x86_64-pc-windows-gnu
	CPU=x86_64
	;;
*)
	echo "Unsupported architecture: $ARCH"
	exit 1
	;;
esac


#export CC="${HOST}-clang"
#export CXX="${CC}++"
#export AR="llvm-ar"
#export RANLIB="llvm-ranlib"
#export STRIP="llvm-strip"
#export NM="llvm-nm"
#export STRINGS="llvm-strings"
#export OBJDUMP="llvm-objdump"
#export OBJCOPY="llvm-objcopy"

export CC="${HOST}-gcc"
export CXX="${HOST}-g++"
export AR="${HOST}-ar"
export RANLIB="${HOST}-ranlib"
export STRIP="${HOST}-strip"
export NM="${HOST}-nm"
export STRINGS="${HOST}-strings"
export OBJDUMP="${HOST}-objdump"
export OBJCOPY="${HOST}-objcopy"
export WINDRES="${HOST}-windres"


case "$ARCH" in
x86 | x86_64)
	if command -v nasm >/dev/null 2>&1; then
		export AS=nasm
	else
		export AS="$CC"
	fi
	;;
aarch64)
	export AS="$CC"
	;;
*)
	echo "Warning: Unknown architecture for assembler setup: $ARCH"
	export AS="$CC"
	;;
esac

resolve_absolute_path() {
	local tool_name="$1"
	local abs_path

	if [[ "$tool_name" = /* ]]; then
		abs_path="$tool_name"
	else
		abs_path=$(which "$tool_name" 2>/dev/null)
	fi

	if [ -z "$abs_path" ] || [ ! -f "$abs_path" ]; then
		echo "ERROR: Tool '$tool_name' not found" >&2
		exit 1
	fi
	echo "$abs_path"
}

CC_ABS=$(resolve_absolute_path "$CC")
CXX_ABS=$(resolve_absolute_path "$CXX")
AR_ABS=$(resolve_absolute_path "$AR")
RANLIB_ABS=$(resolve_absolute_path "$RANLIB")
STRIP_ABS=$(resolve_absolute_path "$STRIP")
NM_ABS=$(resolve_absolute_path "$NM")

BUILD_DIR="$ROOT_DIR/build/mingw/$ARCH"
PREFIX1="$BUILD_DIR/prefix"
PREFIX2="$BUILD_DIR/prefix2"


mkdir -p "$BUILD_DIR" "$PREFIX1" "$PREFIX2"
mkdir -p "$PREFIX1/lib/pkgconfig" 
mkdir -p "$PREFIX1/lib64/pkgconfig"
mkdir -p "$PREFIX2/lib/pkgconfig" 
mkdir -p "$PREFIX2/lib64/pkgconfig"

export PKG_CONFIG_PATH="$PREFIX1/lib/pkgconfig:$PREFIX1/lib64/pkgconfig:$PKG_CONFIG_PATH"
export PKG_CONFIG_PATH="$PREFIX2/lib/pkgconfig:$PREFIX2/lib64/pkgconfig:$PKG_CONFIG_PATH"
export PREFIX="$PREFIX1" #Temporarily export prefix 1 as prefix
export PKG_CONFIG_ALLOW_CROSS=1


SIZE_CFLAGS="-O3 -ffunction-sections -fdata-sections"
SIZE_CXXFLAGS="-O3 -ffunction-sections -fdata-sections"
SIZE_LDFLAGS="-Wl,--gc-sections"

MATH_FLAGS="-fno-math-errno -fno-trapping-math -fassociative-math"
PERF_FLAGS="-funroll-loops -fomit-frame-pointer"

OTHER_FLAGS="-fvisibility=default -fPIC"

export CFLAGS="-I${PREFIX1}/include -I${PREFIX2}/include $SIZE_CFLAGS $PERF_FLAGS $OTHER_FLAGS -D_FORTIFY_SOURCE=0 -DNDEBUG"
export CXXFLAGS="$SIZE_CXXFLAGS $PERF_FLAGS $OTHER_FLAGS -DNDEBUG -D_FORTIFY_SOURCE=0"
export CPPFLAGS="-I${PREFIX1}/include -I${PREFIX2}/include -DNDEBUG -fPIC -D_FORTIFY_SOURCE=0"
export LDFLAGS="-static-libstdc++ -static-libgcc -static -L${PREFIX1}/lib -L${PREFIX1}/lib64 -L${PREFIX2}/lib -L${PREFIX2}/lib64 $SIZE_LDFLAGS -fPIC"




COMMON_AUTOTOOLS_FLAGS=(
	"--prefix=$PREFIX"
	"--host=$HOST"
	"--enable-static"
	"--disable-shared"
)


set_autotools_env() {
	export CC="$CC_ABS"
	export CXX="$CXX_ABS"
	export AR="$AR_ABS"
	export RANLIB="$RANLIB_ABS"
	export STRIP="$STRIP_ABS"
	export CFLAGS="$CFLAGS"
	export CXXFLAGS="$CXXFLAGS"
	export LDFLAGS="$LDFLAGS"
}


autotools_build() {
	local project_name="$1"
	local build_dir="$2"
	shift 2
	
	echo "[+] Building $project_name for $ARCH..."
	cd "$build_dir" || exit 1
	
	(make clean && make distclean) || true
	
	set_autotools_env
	
	./configure "${COMMON_AUTOTOOLS_FLAGS[@]}" "$@"
	make -j"$(nproc)"
	make install
	
	echo "✔ $project_name built successfully"
}


autotools_build_autoreconf() {
	local project_name="$1"
	local build_dir="$2"
	shift 2
	
	echo "[+] Building $project_name for $ARCH..."
	cd "$build_dir" || exit 1
	
	(make clean && make distclean) || true
	autoreconf -fi
	
	set_autotools_env
	
	./configure "${COMMON_AUTOTOOLS_FLAGS[@]}" "$@"
	make -j"$(nproc)"
	make install
	
	echo "✔ $project_name built successfully"
}


make_build() {
	local project_name="$1"
	local build_dir="$2"
	local make_target="${3:-all}"
	local install_target="${4:-install}"
	shift 4
	
	echo "[+] Building $project_name for $ARCH..."
	cd "$build_dir" || exit 1
	
	make clean || true
	
	make -j"$(nproc)" "$make_target" \
		CC="$CC_ABS" \
		AR="$AR_ABS" \
		RANLIB="$RANLIB_ABS" \
		STRIP="$STRIP_ABS" \
		CFLAGS="$CFLAGS" \
		LDFLAGS="$LDFLAGS" \
		PREFIX="$PREFIX" \
		"$@"
	
	make "$install_target" PREFIX="$PREFIX"
	
	echo "✔ $project_name built successfully"
}

generate_pkgconfig() {
	local name="$1"
	local description="$2"
	local version="$3"
	local libs="$4"
	local cflags="${5:--I\${includedir}}"
	local requires="${6:-}"
	local libs_private="${7:-}"
	
	local pc_dir="$PREFIX/lib/pkgconfig"
	local pc_file="$pc_dir/${name}.pc"
	
	[ -f "$pc_file" ] && return 0
	
	mkdir -p "$pc_dir"
	cat >"$pc_file" <<EOF
prefix=$PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: $name
Description: $description
Version: $version
${requires:+Requires: $requires}
Libs: -L\${libdir} $libs
${libs_private:+Libs.private: $libs_private}
Cflags: $cflags
EOF
}


get_asm_flags() {
	case "$ARCH" in
		x86|riscv64) echo "--disable-asm" ;;
		*) echo "" ;;
	esac
}

get_host_override() {
	case "$ARCH" in
		riscv64) echo "riscv64-unknown-linux-gnu" ;;
		*) echo "$HOST" ;;
	esac
}


MINIMAL_CMAKE_FLAGS=(
	"-DCMAKE_SYSTEM_NAME=Windows"
	"-DCMAKE_BUILD_TYPE=Release"
	"-DCMAKE_INSTALL_PREFIX=$PREFIX"
	"-DCMAKE_C_COMPILER=$CC_ABS"
	"-DCMAKE_CXX_COMPILER=$CXX_ABS"
	"-DCMAKE_AR=$AR_ABS"
	"-DCMAKE_RANLIB=$RANLIB_ABS"
	"-DCMAKE_STRIP=$STRIP_ABS"
	"-DCMAKE_C_FLAGS=$CFLAGS"
	"-DCMAKE_CXX_FLAGS=$CXXFLAGS"
	"-DCMAKE_EXE_LINKER_FLAGS=$LDFLAGS"
)


cmake_build() {
	local project_name="$1"
	local build_dir="$2"
	local use_common_flags="${3:-true}"
	shift 3
	
	echo "[+] Building $project_name for $ARCH..."
	cd "$build_dir" || exit 1
	
	rm -rf build && mkdir build && cd build

	cmake .. -G Ninja "${MINIMAL_CMAKE_FLAGS[@]}" "$@"
	ninja -j"$(nproc)"
	ninja install
	
	echo "✓ $project_name built successfully"
}

cmake_ninja_build() {
	cmake_build "$@"
}

get_simd_flags() {
	case "$ARCH" in
		x86|x86_64|i686)
			echo "-DENABLE_SIMD=ON"
			;;
		*)
			echo "-DENABLE_SIMD=OFF"
			;;
	esac
}

CROSS_FILE_TEMPLATE="$BUILD_DIR/.meson-cross-template"
DOWNLOADER_SCRIPT="${ROOT_DIR}/scripts/download_sources.sh"
BUILD_FUNCTIONS="${ROOT_DIR}/scripts/build_functions.sh"
FFMPEG_BUILDER="${ROOT_DIR}/scripts/ffmpeg.sh"

for script in "$DOWNLOADER_SCRIPT" "$BUILD_FUNCTIONS" "$FFMPEG_BUILDER"; do
	if [ -f "$script" ]; then
		source "$script"
	else
		echo "Warning: Script not found: $script (skipping)"
	fi
done

sanitize_flags() {
    local flags="$1"
    echo "$flags" | xargs -n1 | sed "/^$/d; s/.*/'&'/" | paste -sd, -
}

create_meson_cross_file() {
    local output_file="$1"
    local system="${2:-windows}"  # default to windows
    
    local S_CFLAGS=$(sanitize_flags "$CFLAGS")
    local S_CXXFLAGS=$(sanitize_flags "$CXXFLAGS") 
    local S_LDFLAGS=$(sanitize_flags "$LDFLAGS")
    
    cat >"$output_file" <<EOF
[binaries]
c = '$CC_ABS'
cpp = '$CXX_ABS'
ar = '$AR_ABS'
nm = '$NM_ABS'
strip = '$STRIP_ABS'
pkg-config = 'pkg-config'
ranlib = '$RANLIB_ABS'

[built-in options]
c_args = [${S_CFLAGS}]
cpp_args = [${S_CXXFLAGS}]
c_link_args = [${S_LDFLAGS}]
cpp_link_args = [${S_LDFLAGS}]

[host_machine]
system = '${system}'
cpu_family = '${ARCH}'
cpu = '${ARCH}'
endian = 'little'
EOF
}

meson_build() {
    local project_name="$1"
    local build_dir="$2"
    local cross_file="$3"
    shift 3  # remove first 3 args rest are meson options
    
    echo "[+] Building $project_name for $ARCH..."
    cd "$build_dir" || exit 1
    
    rm -rf build && mkdir build
    
    meson setup build . \
        --cross-file="$cross_file" \
        --prefix="$PREFIX" \
        --buildtype=release \
        --default-library=static \
        "$@"
        
    ninja -C build -j"$(nproc)"
    ninja -C build install
    
    echo "✔ $project_name built successfully"
}

init_cross_files() {
    create_meson_cross_file "$CROSS_FILE_TEMPLATE" "windows"
    create_meson_cross_file "$CROSS_FILE_TEMPLATE.linux" "linux"
}

nuke_pkgconfig_libs() {
	echo "[*] Nuking all -l flags from .pc files in $PREFIX..."
	find "$PREFIX" -name "*.pc" -type f -exec sed -i \
		-e 's/^Libs:.*$/Libs: -L${libdir}/' \
		-e 's/^Libs.private:.*$/Libs.private:/' \
		{} \;
	echo "[+] All .pc files cleaned"
}


#!/bin/bash

# Function 1: Nuke all linking flags from .pc files
nuke_pkgconfig_libs() {
	echo "[*] Nuking all -l flags from .pc files in $PREFIX..."
	find "$PREFIX" -name "*.pc" -type f -exec sed -i \
		-e 's/^Libs:.*$/Libs: -L${libdir}/' \
		-e 's/^Libs.private:.*$/Libs.private:/' \
		{} \;
	echo "[+] All .pc files cleaned"
}

# Function 2: Build array of all .a files
build_libs_array() {
	echo "[*] Collecting all .a files from $PREFIX2/lib and $PREFIX2/lib64..."
	
	EXTRA_LIBS_ARRAY=()
	declare -A seen
   
	# Find all .a files and convert to -l flags
	for libfile in $(find "$PREFIX2/lib" "$PREFIX2/lib64" -name "*.a" 2>/dev/null | sort); do
		libbase=$(basename "$libfile")
		
		# Extract the base library name for deduplication
		# libxvidcore.a and libxvidcore.dll.a both -> "xvidcore"
		if [[ "$libbase" == *.dll.a ]]; then
			basename=$(echo "$libbase" | sed 's/\.dll\.a$//' | sed 's/^lib//')
		else
			basename=$(echo "$libbase" | sed 's/\.a$//' | sed 's/^lib//')
		fi
		
		# Skip if we already have this library (prefer .a over .dll.a)
		if [ -n "${seen[$basename]}" ]; then
			continue
		fi
		seen[$basename]=1
		
		# Generate appropriate linker flag
		if [[ "$libbase" == *.dll.a ]]; then
			# Use -l:filename for .dll.a files
			libflag="-l:$libbase"
		elif [[ "$libbase" == lib*.a ]]; then
			# Standard libfoo.a -> -lfoo
			libflag="-l$basename"
		else
			# Fallback: use full filename
			libflag="-l:$libbase"
		fi
		
		# Add to array
		EXTRA_LIBS_ARRAY+=("$libflag")
	done
	
	echo "[+] Found ${#EXTRA_LIBS_ARRAY[@]} unique libraries"
}



download_sources
prepare_sources
apply_extra_setup
init_cross_files
### Compression / crypto
build_zlib
build_lzo
build_lz4
build_snappy
build_bzip2
build_liblzma
build_zstd
build_brotli
build_openssl
### Parsing / XML
build_iconv
build_libxml2
build_libexpat
build_pcre2

### Subtitles / text rendering
build_iconv
build_fribidi

### Graphics stack
build_libffi
build_libpng
export PREFIX="$PREFIX2"
build_freetype
build_harfbuzz
build_fontconfig
build_glib
build_dav1d
build_libass
build_aribb24
build_pixman
build_cairo
build_pango
build_librsvg_c
export PREFIX="$PREFIX1"
#build_rav1e
build_xavs2

### Audio codecs
#build_libgsm #( didnt build )
build_lame
build_twolame
build_opus
build_shine
build_ogg
build_vorbis
build_speex
build_libvo_amrwbenc
build_opencore_amr
build_libilbc
build_libcodec2_native
build_libcodec2
build_libbs2b
#build_libgme #(didnt build)
build_flite
# build_libmodplug #(dint build)
build_liblc3

### Video codecs
build_x264
build_libvpx
build_xavs #(isme kuchh edit karna pada thha common.c mein)
build_davs2
build_libsrt
build_openjpeg
build_x265
build_aom
build_svtav1
build_uavs3d
build_xvidcore
# build_kvazaar # (ffmpeg requires some dll import type shit)
build_vvenc
build_xeve
build_xevd

### Media formats / misc video
build_udfread
build_bluray
build_rtmp
build_libtheora
build_vmaf
build_libzimg
build_libmysofa
build_vidstab
build_soxr
build_fftw
build_rubberband
build_zvbi
build_openmpt
build_libzmq
build_libplacebo
build_librist

### Image / color management
build_lcms
build_libwebp

### Utilities & extras
build_lensfun
build_highway
build_libjxl
build_libssh
build_libqrencode
build_quirc
#build_chromaprint #(same something dll)
# build_lcevcdec # (nahi compile ho raha)
build_openapv

### Final cleanup + FFmpeg
#cleanup_pcfiles

#if [ -z "$FFMPEG_STATIC" ]; then
 #   install_opencl_headers
  #  build_ocl_icd
#fi


patch_ffmpeg


find "$PREFIX" -iname "*.pc" -exec sed -i 's/\s*-ldl\b\s*/ /g' {} +
find "$PREFIX" -iname "*.dll*" -delete
build_ffmpeg

echo "Build completed successfully"
