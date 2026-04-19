local outDir = os.getenv("LDE_OUTPUT_DIR")
local sep = string.sub(package.config, 1, 1)
local isWindows = jit.os == "Windows"
local isMac = jit.os == "OSX"
local scriptDir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])")
local curlSrc = scriptDir .. "vendor" .. sep .. "curl"
local curlBuild = curlSrc .. sep .. "build"
local libName = isWindows and "curl.dll" or isMac and "libcurl.dylib" or "libcurl.so"
local outLib = outDir .. sep .. libName

if io.open(outLib, "rb") then return end

local function exec(cmd)
	local ret = os.execute(cmd)
	assert(ret == 0 or ret == true, "command failed: " .. cmd)
end

---@format disable-next
if isWindows then
	exec('cmake -S "' .. curlSrc .. '" -B "' .. curlBuild .. '" -GNinja -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON -DBUILD_CURL_EXE=OFF -DENABLE_MANUAL=OFF -DCURL_USE_LIBPSL=OFF -DCURL_USE_SCHANNEL=ON -DCURL_ZLIB=OFF')
	exec('cmake --build "' .. curlBuild .. '" --parallel')
	exec('copy "' .. curlBuild .. '\\lib\\libcurl.dll" "' .. outLib .. '"')
else
	---@format disable-next
	exec('cmake -S "' .. curlSrc .. '" -B "' .. curlBuild .. '" -GNinja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS=-g0 -DBUILD_SHARED_LIBS=ON -DBUILD_CURL_EXE=OFF -DENABLE_CURL_MANUAL=OFF -DBUILD_LIBCURL_DOCS=OFF -DCURL_USE_OPENSSL=ON -DCURL_USE_LIBPSL=OFF -DCURL_ZSTD=OFF -DCURL_BROTLI=OFF -DCURL_ZLIB=OFF -DUSE_NGHTTP2=OFF -DUSE_LIBIDN2=OFF -DCURL_DISABLE_LDAP=ON -DCURL_DISABLE_FTP=ON -DCURL_DISABLE_FILE=ON -DCURL_DISABLE_TELNET=ON -DCURL_DISABLE_TFTP=ON -DCURL_DISABLE_SMTP=ON -DCURL_DISABLE_POP3=ON -DCURL_DISABLE_IMAP=ON -DCURL_DISABLE_GOPHER=ON -DCURL_DISABLE_MQTT=ON -DCURL_DISABLE_RTSP=ON -DCURL_DISABLE_DICT=ON -DCURL_DISABLE_COOKIES=ON')
	exec('cmake --build "' .. curlBuild .. '" --parallel')
	exec('cp "' .. curlBuild .. '/lib/' .. libName .. '" "' .. outLib .. '"')
	local stripFlags = isMac and "-x" or "--strip-unneeded --remove-section=.eh_frame --remove-section=.eh_frame_hdr"
	exec('strip ' .. stripFlags .. ' "' .. outLib .. '"')

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
