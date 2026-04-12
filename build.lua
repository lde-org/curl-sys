local outDir = os.getenv("LDE_OUTPUT_DIR")
local sep = string.sub(package.config, 1, 1)
local isWindows = jit.os == "Windows"
local isMac = jit.os == "OSX"
local isAndroid = os.getenv("ANDROID_ROOT") ~= nil
local sh = isAndroid and "/data/data/com.termux/files/usr/bin/sh" or "/bin/sh"
local scriptDir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])")
local curlSrc = scriptDir .. "vendor" .. sep .. "curl"
local opensslSrc = scriptDir .. "vendor" .. sep .. "openssl"
local opensslOut = opensslSrc .. sep .. "build"
local libName = isWindows and "curl.dll" or isMac and "libcurl.dylib" or "libcurl.so"
local outLib = outDir .. sep .. libName

-- skip if already built
if io.open(outLib, "rb") then return end

local function exec(cmd)
	local ret = os.execute(cmd)
	assert(ret == 0 or ret == true, "command failed: " .. cmd)
end

---@format disable-next
if isWindows then
	exec('cmake -S "' .. curlSrc .. '" -B "' .. curlSrc .. '\\build" -DBUILD_SHARED_LIBS=ON -DBUILD_CURL_EXE=OFF -DCURL_USE_LIBPSL=OFF -DCURL_USE_SCHANNEL=ON')
	exec('cmake --build "' .. curlSrc .. '\\build" --config Release')
	exec('copy "' .. curlSrc .. '\\build\\lib\\Release\\libcurl.dll" "' .. outLib .. '"')
else
	local arch = jit.arch == "x64" and "x86_64" or (isMac and "arm64" or "aarch64")
	local ndkRoot = os.getenv("ANDROID_NDK_ROOT")
	local opensslTarget, curlEnv, curlHost
	local opensslMin = "no-shared no-tests no-docs no-apps no-legacy no-cms no-ct no-srp no-idea no-mdc2 no-rc2 no-rc4 no-rc5 no-md2 no-md4 no-rmd160 no-whirlpool no-seed no-camellia no-cast no-bf no-des no-dsa no-dh no-ec2m no-sm2 no-sm3 no-sm4 no-comp no-ocsp no-ts no-srtp no-ui-console no-quic no-ml-dsa no-ml-kem no-slh-dsa no-asm no-blake2 no-deprecated"

	if isAndroid and ndkRoot then
		local toolchain = ndkRoot .. "/toolchains/llvm/prebuilt/linux-aarch64/bin"
		local ndkEnv = 'PATH="' .. toolchain .. ':$PATH" ANDROID_NDK_ROOT="' .. ndkRoot .. '"'
		opensslTarget = "android-arm64"
		exec('cd "' .. opensslSrc .. '" && ' .. ndkEnv .. ' perl Configure ' .. opensslTarget .. ' ' .. opensslMin .. ' --prefix="' .. opensslOut .. '" && ' .. ndkEnv .. ' make -j$(nproc) && make install_sw')
		local cc = toolchain .. "/aarch64-linux-android24-clang"
		local cxx = toolchain .. "/aarch64-linux-android24-clang++"
		curlEnv = 'CC="' .. cc .. '" CXX="' .. cxx .. '" AR="' .. toolchain .. '/llvm-ar" RANLIB="' .. toolchain .. '/llvm-ranlib" '
		curlHost = " --host=aarch64-linux-android"
	else
		opensslTarget = isMac and ("darwin64-" .. arch .. "-cc") or ("linux-" .. arch)
		exec('cd "' .. opensslSrc .. '" && perl Configure ' .. opensslTarget .. ' ' .. opensslMin .. ' --prefix="' .. opensslOut .. '" && make -j$(nproc) && make install_sw')
		curlEnv = ""
		curlHost = ""
	end

	local curlMin = "--disable-static --enable-shared --with-openssl=\"" .. opensslOut .. "\" --without-libpsl --without-zstd --without-brotli --without-nghttp2 --without-nghttp3 --without-libidn2 --without-zlib --without-libgsasl --disable-ldap --disable-manual --disable-debug --disable-ftp --disable-file --disable-telnet --disable-tftp --disable-smtp --disable-pop3 --disable-imap --disable-smb --disable-gopher --disable-mqtt --disable-rtsp --disable-socks --disable-aws-sigv4 --disable-dict --disable-cookies"

	exec('cd "' .. curlSrc .. '" && SHELL="' .. sh .. '" autoreconf -fi && ' .. curlEnv .. 'CFLAGS="-g0" CONFIG_SHELL="' .. sh .. '" ./configure ' .. curlMin .. curlHost .. ' && make -j$(nproc) -C lib')
	local builtLib = isMac and (curlSrc .. "/lib/.libs/libcurl.dylib") or (curlSrc .. "/lib/.libs/libcurl.so")
	exec('cp "' .. builtLib .. '" "' .. outLib .. '"')
	local strip = (isAndroid and ndkRoot) and (ndkRoot .. "/toolchains/llvm/prebuilt/linux-aarch64/bin/llvm-strip") or "strip"
	exec(strip .. ' --strip-unneeded --remove-section=.eh_frame --remove-section=.eh_frame_hdr "' .. outLib .. '"')

	-- generate embedded CA bundle as a Lua file
	local cacertLua = outDir .. "/cacert.lua"
	if not io.open(cacertLua, "rb") then
		local tmp = outDir .. "/cacert.pem"
		exec('curl -sSL https://curl.se/ca/cacert.pem -o "' .. tmp .. '"')
		local pem = assert(io.open(tmp, "rb")):read("*a")
		local f = assert(io.open(cacertLua, "wb"))
		f:write("return [=[\n" .. pem .. "]=]\n")
		f:close()
		os.remove(tmp)
	end
end
