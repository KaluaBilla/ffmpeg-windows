#!/bin/bash

mkdir -p "$ROOT_DIR/temp"

check() {
	for cmd in "$@"; do
		printf "checking for %s... " "$cmd"
		sleep 0.01
		if command -v "$cmd" >/dev/null 2>&1; then
			echo "found"
		else
			echo "not found"
			echo "Error: '$cmd' is missing. Aborting."
			exit 1
		fi
	done
}

detect_host_cc() {
	for cc in gcc clang cc; do
		cc_path=$(command -v "$cc" 2>/dev/null)
		if [[ -n "$cc_path" ]]; then
			test_file="$ROOT_DIR/temp/test.c"
			test_bin="$ROOT_DIR/temp/test_cc"
			echo 'int main() { return 0; }' >"$test_file"
			if "$cc_path" "$test_file" -o "$test_bin" &>/dev/null; then
				"$test_bin" &>/dev/null
				if [[ $? -eq 0 ]]; then
					HOST_CC="$cc_path"
					rm -f "$test_file" "$test_bin"
					echo "Detected working Host C compiler: $HOST_CC"
					return
				fi
			fi
		fi
	done
	echo "No working C compiler detected. Aborting."
	exit 1
}

detect_host_cxx() {
	for cxx in g++ clang++ c++; do
		cxx_path=$(command -v "$cxx" 2>/dev/null)
		if [[ -n "$cxx_path" ]]; then
			test_file="$ROOT_DIR/temp/test.cpp"
			test_bin="$ROOT_DIR/temp/test_cxx"
			echo 'int main() { return 0; }' >"$test_file"
			if "$cxx_path" "$test_file" -o "$test_bin" &>/dev/null; then
				"$test_bin" &>/dev/null
				if [[ $? -eq 0 ]]; then
					HOST_CXX="$cxx_path"
					rm -f "$test_file" "$test_bin"
					echo "Detected working Host C++ compiler: $HOST_CXX"
					return
				fi
			fi
		fi
	done
	echo "No working C++ compiler detected. Aborting."
	exit 1
}

check which curl wget tar zip sed meson \
	make autopoint ninja autoconf automake libtool pkg-config makeinfo \
	gettext gperf bison flex git xz unzip file find cp mv rm ln svn nasm yasm

detect_host_cc
detect_host_cxx

export HOST_CC HOST_CXX

__CMAKE_BIN=""

cmake() {
    if [[ -z "$__CMAKE_BIN" ]]; then
        local sys_cmake ver
        sys_cmake=$(command -v cmake 2>/dev/null)

        if [[ -z "$sys_cmake" ]]; then
            echo "Error: cmake not found on system."
            exit 1
        fi

        # FIX: Use 'command' to call the real cmake binary, not this function
        ver=$(command cmake --version | awk '/version/ {print $3; exit}')

        # Check if system cmake version is < 4.0.0
        if [[ $(printf '%s\n' "$ver" "4.0.0" | sort -V | head -n1) == "$ver" ]]; then
            __CMAKE_BIN="$sys_cmake"
        else
            local src="$ROOT_DIR/cmake/src"
            local build="$ROOT_DIR/cmake/build"
            local inst="$ROOT_DIR/cmake/install"
            mkdir -p "$src" "$build" "$inst"

            if [[ ! -x "$inst/bin/cmake" ]]; then
                echo "Detected CMake $ver >= 4.0.0, building 3.31.9..."
                (
                    cd "$ROOT_DIR/cmake" || exit 1
                    if [[ ! -f "$src/CMakeLists.txt" ]]; then
                        [[ -f cmake-3.31.9.tar.gz ]] || \
                            curl -LO https://github.com/Kitware/CMake/releases/download/v3.31.9/cmake-3.31.9.tar.gz
                        tar -xf cmake-3.31.9.tar.gz -C "$src" --strip-components=1
                    fi
                    cd "$build" || exit 1
                    # Use 'command' here too to avoid recursion
                    "$src/bootstrap" --prefix="$inst" \
                        CC="$HOST_CC" CXX="$HOST_CXX"
                    command make -j"$(nproc)"
                    command make install
                ) || { echo "CMake 3.31.9 build failed."; exit 1; }
            fi

            __CMAKE_BIN="$inst/bin/cmake"
        fi
    fi

    "$__CMAKE_BIN" "$@"
}

check cmake
cmake --version
