#!/bin/bash

EXTRA_LIBS=(
  # Core libraries (order matters for static linking)
  -lrsvg_2
  -lpangocairo-1.0
  -lpango-1.0
  -lpangoft2-1.0
  -lpangowin32-1.0
  -lcairo-gobject
  -lcairo-script-interpreter
  -lcairo
  -lharfbuzz-subset
  -lharfbuzz
  -lgio-2.0
  -lgirepository-2.0
  -lgobject-2.0
  -lgmodule-2.0
  -lgthread-2.0
  -lglib-2.0
  -lfribidi
  -lfontconfig
  -lfreetype
  -lpixman-1
  -lpng16
  -lxml2
  -lvorbisfile
  -lvorbis
  -logg
  -lbrotlidec
  -lbrotlicommon
  -lffi
  -lpcre2-8
  -lexpat
  -lbz2
  -lz
  -liconv
  -lintl
  -lssh
  -lcrypto
  -lssl
  -lcrypt32
  -lfftw3
  -lmodplug
  
  # Windows system libraries (CRITICAL - these were missing)
  -luserenv      # For GetUserProfileDirectoryW
  -lmsimg32      # For AlphaBlend
  -ldnsapi       # For DnsQuery_UTF8
  -lbcrypt       # For BCryptGenRandom
  -lgdi32
  -ldwrite
  -lshlwapi
  -liphlpapi
  -lole32
  -loleaut32
  -lshell32
  -luuid
  -lcomdlg32
  -lwinspool
  -lntdll
  -lws2_32
  -luser32
  -lkernel32
  -lwinmm

  -lstdc++
#  -lpthread
  -lm
)



patch_ffmpeg() {
	cd "$BUILD_DIR/FFmpeg"
	if ! grep -q "int ff_dec_init(" fftools/ffmpeg_dec.c; then
		sed -i 's/int dec_init(/int ff_dec_init(/g' fftools/ffmpeg_dec.c
		sed -i 's/int dec_init(/int ff_dec_init(/g' fftools/ffmpeg.h
		sed -i 's/dec_init(/ff_dec_init(/g' fftools/ffmpeg_demux.c
	fi

	LC_FILE="libavfilter/vf_lcevc.c"
	if grep -q "LCEVC_SendDecoderEnhancementData(lcevc->decoder, in->pts, 0, sd->data, sd->size)" "$LC_FILE"; then
		sed -i 's/LCEVC_SendDecoderEnhancementData(lcevc->decoder, in->pts, 0, sd->data, sd->size)/LCEVC_SendDecoderEnhancementData(lcevc->decoder, in->pts, sd->data, sd->size)/' "$LC_FILE"
	fi
	if grep -q "LCEVC_SendDecoderBase(lcevc->decoder, in->pts, 0, picture, -1, in)" "$LC_FILE"; then
		sed -i 's/LCEVC_SendDecoderBase(lcevc->decoder, in->pts, 0, picture, -1, in)/LCEVC_SendDecoderBase(lcevc->decoder, in->pts, picture, 0, in)/' "$LC_FILE"
	fi
	LC_FILE="libavcodec/lcevcdec.c"
	if grep -q "LCEVC_SendDecoderEnhancementData(lcevc->decoder, in->pts, 0, sd->data, sd->size)" "$LC_FILE"; then
		sed -i 's/LCEVC_SendDecoderEnhancementData(lcevc->decoder, in->pts, 0, sd->data, sd->size)/LCEVC_SendDecoderEnhancementData(lcevc->decoder, in->pts, sd->data, sd->size)/' "$LC_FILE"
	fi
	if grep -q "LCEVC_SendDecoderBase(lcevc->decoder, in->pts, 0, picture, -1, NULL)" "$LC_FILE"; then
		sed -i 's/LCEVC_SendDecoderBase(lcevc->decoder, in->pts, 0, picture, -1, NULL)/LCEVC_SendDecoderBase(lcevc->decoder, in->pts, picture, 0, NULL)/' "$LC_FILE"
	fi
}

build_ffmpeg() {
	echo "Building FFmpeg for $ARCH..."
	cd "$BUILD_DIR/FFmpeg" || exit 1
	ASM_FLAG=()
	[ "$ARCH" = "x86" ] && [ -z "$FFMPEG_STATIC" ] && ASM_FLAG=(--disable-asm)
    type=${ARCH}
	(make clean && make distclean) || true
	EXTRA_VERSION="windows-[gh/tg]/KaluaBilla"
	CONFIGURE_FLAGS=(
		--enable-cross-compile
		--disable-shared
		--enable-static
		--prefix="$PREFIX"
		--host-cc="${HOST_CC}"
		--cc="$CC_ABS"
		--cxx="$CXX_ABS"
		--ar="$AR_ABS"
		--nm="$NM_ABS"
		--ranlib="$RANLIB_ABS"
		--strip="$STRIP_ABS"
		--arch="$ARCH"
		--target-os=mingw32
		--pkg-config-flags=--static
		--extra-cflags="${CFLAGS} -I${PREFIX1}/include/ -I${PREFIX2}/include/ -I${PREFIX1}/include/cairo -I${PREFIX2}/include/cairo -DMODPLUG_STATIC -DCHROMAPRINT_NODLL -DKVZ_STATIC_LIB -DOPENMPT_STATIC -DXEVE_STATIC -DXEVD_STATIC -DXVIDCORE_STATIC -DCAIRO_STATIC -DLIBTWOLAME_STATIC -DLIBSSH_STATIC -DZMQ_STATIC -DCAIRO_WIN32_STATIC_BUILD"
		--extra-ldflags="${LDFLAGS} -static -static-libstdc++ -static-libgcc"
		--extra-libs="${EXTRA_LIBS[*]} -liphlpapi -lole32 -lshell32 -luuid -lm -lpthread -lws2_32 -luser32 -lkernel32 -lcomdlg32 -lole32 -loleaut32 -luuid -lwinspool"
		--extra-version=$EXTRA_VERSION
		--disable-debug
		--enable-pic
		--disable-doc
		--enable-gpl
		--disable-w32threads
		--enable-version3
		--enable-libx264
		--enable-libx265
		--enable-libvpx
		--enable-libaom
		--enable-libdav1d
		--enable-libharfbuzz
		--enable-libbs2b
		--enable-libgsm
		--enable-libtheora
		--enable-libopenjpeg
		--enable-libwebp
		--enable-libxvid
		--enable-libkvazaar
		--enable-libxavs
		--enable-libdavs2
		--enable-libmp3lame
		--enable-libvorbis
		--enable-libopus
		--enable-libtwolame
		--enable-libsoxr
		--enable-libvo-amrwbenc
		--enable-libopencore-amrnb
		--enable-libopencore-amrwb
		--enable-libvvenc
		--enable-libilbc
		--enable-libcodec2
		--enable-libmysofa
		--enable-libopenmpt
		--enable-libfreetype
		--enable-libfontconfig
		--enable-libfribidi
		--enable-libass
		--enable-libxml2
		--enable-openssl
		--enable-zlib
		--enable-bzlib
        --enable-libsnappy
		--enable-libsrt
		--enable-libzmq
		--enable-librist
		--enable-libaribb24
		--enable-libvmaf
		--enable-libzimg
		--enable-liblensfun
		--enable-libflite
		--enable-libssh
		--enable-libsvtav1
		--enable-libuavs3d
		--enable-librtmp
		--enable-libgme
		--enable-libjxl
		--enable-libqrencode
		--enable-libquirc
        --enable-chromaprint
		--enable-libspeex
		--enable-libbluray
		--enable-lcms2
		--enable-liblc3
		--enable-libmodplug
		--enable-librubberband
		--enable-libshine
		--enable-vapoursynth
		--enable-avisynth
		--enable-liboapv 
		--enable-libxeve 
		--enable-libxevd
		--enable-librsvg
        --enable-libxavs2
		--enable-mediafoundation
		--enable-amf
		--enable-sdl2
		--enable-ffplay
		"${ASM_FLAG[@]}"
	)

	#[ "$ARCH" != "x86" ] && CONFIGURE_FLAGS+=(--enable-libzvbi)


test=(--enable-cross-compile
		--prefix="$PREFIX"
		--host-cc="${HOST_CC}"
		--cc="$CC_ABS"
		--cxx="$CXX_ABS"
		--ar="$AR_ABS"
		--nm="$NM_ABS"
		--ranlib="$RANLIB_ABS"
		--strip="$STRIP_ABS"
		--arch="$ARCH"
		--target-os=mingw32
		--pkg-config-flags=--static
		--extra-cflags="${CFLAGS} -I${PREFIX2}/include/cairo -DKVZ_STATIC_LIB"
		--extra-cxxflags="${CXXFLAGS} -DKVZ_STATIC_LIB"
		--extra-ldflags="${LDFLAGS}"
		--extra-libs="${EXTRA_LIBS[*]} -ltwolame -liphlpapi -lole32 -lshell32 -luuid -lm -lpthread -lws2_32 -luser32 -lkernel32 -lcomdlg32 -lole32 -loleaut32 -luuid -lwinspool"
		--extra-version=$EXTRA_VERSION
		--disable-debug
		--enable-pic
		--disable-doc
		--enable-gpl
		--enable-version3
		)


	./configure "${CONFIGURE_FLAGS[@]}"
	#./configure "${test[@]}"
	#exit 1
	
	# strip out the messy toolchain/build flags from banner, keep only the library stuff
	sed -i "/#define FFMPEG_CONFIGURATION/c\\#define FFMPEG_CONFIGURATION \"$(echo "${CONFIGURE_FLAGS[@]}" | tr ' ' '\n' | grep -E '^--(enable|disable)-' | tr '\n' ' ' | sed 's/ *$//')\"" config.h

	make -j"$(nproc)"
	make install

	echo "[+] FFmpeg built successfully "
}
