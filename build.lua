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
	-- build openssl statically
	local arch = jit.arch == "x64" and "x86_64" or "aarch64"
	local opensslTarget = isMac and ("darwin64-" .. arch .. "-cc") or ("linux-" .. arch)
	exec('cd "' .. opensslSrc .. '" && ./Configure ' .. opensslTarget .. ' no-shared no-tests --prefix="' .. opensslOut .. '" && make -j$(nproc) && make install_sw')

	exec('cd "' .. curlSrc .. '" && SHELL="' .. sh .. '" autoreconf -fi && CONFIG_SHELL="' .. sh .. '" ./configure --disable-static --enable-shared --with-openssl="' .. opensslOut .. '" --without-libpsl --disable-manual && make -j$(nproc) -C lib')
	local builtLib = isMac and (curlSrc .. "/lib/.libs/libcurl.dylib") or (curlSrc .. "/lib/.libs/libcurl.so")
	exec('cp "' .. builtLib .. '" "' .. outLib .. '"')

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
