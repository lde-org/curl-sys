local build = require("lde-build")

local sep = string.sub(package.config, 1, 1)
local isWindows = jit.os == "Windows"
local isMac = jit.os == "OSX"
local libName = isWindows and "curl.dll" or (isMac and "libcurl.dylib" or "libcurl.so")
local outLib = build.outDir .. sep .. libName

if io.open(outLib, "rb") then return end

local url = "https://github.com/curl/curl/releases/download/curl-8_19_0/curl-8.19.0.tar.gz"
local tarball = "curl-8.19.0.tar.gz"

local content = build:fetch(url)
build:write(tarball, content)
build:extract(tarball, ".")
build:move("curl-8.19.0", "curl")

local srcDir = build.outDir .. "/curl"
local buildDir = srcDir .. "/build"

if isWindows then
	---@format disable-next
	build:sh('cmake -S "' .. srcDir .. '" -B "' .. buildDir .. '" -GNinja -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON -DBUILD_CURL_EXE=OFF -DENABLE_MANUAL=OFF -DCURL_USE_LIBPSL=OFF -DCURL_USE_SCHANNEL=ON -DCURL_ZLIB=OFF')
	build:sh('cmake --build "' .. buildDir .. '" --parallel')
	build:copy("curl/build/lib/libcurl.dll", libName)
else
	---@format disable-next
	build:sh('cmake -S "' .. srcDir .. '" -B "' .. buildDir .. '" -GNinja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS=-g0 -DBUILD_SHARED_LIBS=ON -DBUILD_CURL_EXE=OFF -DENABLE_CURL_MANUAL=OFF -DBUILD_LIBCURL_DOCS=OFF -DCURL_USE_OPENSSL=ON -DCURL_USE_LIBPSL=OFF -DCURL_ZSTD=OFF -DCURL_BROTLI=OFF -DCURL_ZLIB=OFF -DUSE_NGHTTP2=OFF -DUSE_LIBIDN2=OFF -DCURL_DISABLE_LDAP=ON -DCURL_DISABLE_FTP=ON -DCURL_DISABLE_FILE=ON -DCURL_DISABLE_TELNET=ON -DCURL_DISABLE_TFTP=ON -DCURL_DISABLE_SMTP=ON -DCURL_DISABLE_POP3=ON -DCURL_DISABLE_IMAP=ON -DCURL_DISABLE_GOPHER=ON -DCURL_DISABLE_MQTT=ON -DCURL_DISABLE_RTSP=ON -DCURL_DISABLE_DICT=ON -DCURL_DISABLE_COOKIES=ON')
	build:sh('cmake --build "' .. buildDir .. '" --parallel')
	build:copy("curl/build/lib/" .. libName, libName)
	local stripFlags = isMac and "-x" or "--strip-unneeded --remove-section=.eh_frame --remove-section=.eh_frame_hdr"
	build:sh('strip ' .. stripFlags .. ' "' .. build.outDir .. '/' .. libName .. '"')

	local cacertLua = build.outDir .. "/cacert.lua"
	if not io.open(cacertLua, "rb") then
		local tmp = build.outDir .. "/cacert.pem"
		build:sh('curl -sSL https://curl.se/ca/cacert.pem -o "' .. tmp .. '"')
		local pem = build:read("cacert.pem")
		build:write("cacert.lua", "return [=[\n" .. pem .. "]=]\n")
		build:delete("cacert.pem")
	end
end
