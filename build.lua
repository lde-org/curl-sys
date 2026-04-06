local outDir = os.getenv("LDE_OUTPUT_DIR")
local sep = string.sub(package.config, 1, 1)
local isWindows = sep == "\\"
local scriptDir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])")
local curlSrc = scriptDir .. "vendor" .. sep .. "curl"
local outLib = outDir .. sep .. (isWindows and "curl.dll" or "libcurl.so")

-- skip if already built
if io.open(outLib, "rb") then return end

local function exec(cmd)
    local ret = os.execute(cmd)
    assert(ret == 0 or ret == true, "command failed: " .. cmd)
end

if isWindows then
    exec('cmake -S "' .. curlSrc .. '" -B "' .. curlSrc .. '\\build" -DBUILD_SHARED_LIBS=ON -DBUILD_CURL_EXE=OFF -DCURL_USE_LIBPSL=OFF')
    exec('cmake --build "' .. curlSrc .. '\\build" --config Release')
    exec('copy "' .. curlSrc .. '\\build\\lib\\Release\\libcurl.dll" "' .. outLib .. '"')
else
    exec('cd "' .. curlSrc .. '" && autoreconf -fi && ./configure --disable-static --enable-shared --with-openssl --without-libpsl && make -j$(nproc)')
    exec('cp "' .. curlSrc .. '/lib/.libs/libcurl.so" "' .. outLib .. '"')
end
