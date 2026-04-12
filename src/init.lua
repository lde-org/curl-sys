local ffi = require("ffi")
local buffer = require("string.buffer")

ffi.cdef [[
  typedef void CURL;
  typedef int CURLcode;
  typedef int CURLoption;
  typedef int CURLINFO;
  typedef long long curl_off_t;

  typedef struct curl_slist {
    char *data;
    struct curl_slist *next;
  } curl_slist;

  typedef size_t (*curl_write_callback)(char *ptr, size_t size, size_t nmemb, void *userdata);

  /* CURLoption values (CINIT macro: type*10000 + num) */
  /* OBJECTPOINT = 10000, FUNCTIONPOINT = 20000, LONG = 0, OFF_T = 30000 */

  CURL *curl_easy_init(void);
  CURLcode curl_easy_setopt(CURL *curl, CURLoption option, ...);
  CURLcode curl_easy_perform(CURL *curl);
  void curl_easy_cleanup(CURL *curl);
  CURLcode curl_easy_getinfo(CURL *curl, CURLINFO info, ...);
  void curl_easy_reset(CURL *curl);
  const char *curl_easy_strerror(CURLcode errornum);

  struct curl_slist *curl_slist_append(struct curl_slist *list, const char *string);
  void curl_slist_free_all(struct curl_slist *list);

  CURLcode curl_global_init(long flags);
  void curl_global_cleanup(void);

  typedef struct FILE FILE;
  FILE *fopen(const char *path, const char *mode);
  int fclose(FILE *f);

  struct curl_blob {
    void *data;
    size_t len;
    unsigned int flags;
  };
]]

local here = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or ""
local libname = jit.os == "Windows" and "curl.dll" or (jit.os == "OSX" and "libcurl.dylib" or "libcurl.so")
local lib = ffi.load(here .. libname)

lib.curl_global_init(3) -- CURL_GLOBAL_ALL

-- CURLoption constants
local OPT = {
	URL            = 10002,
	WRITEFUNCTION  = 20011,
	WRITEDATA      = 10001,
	HTTPHEADER     = 10023,
	POSTFIELDS     = 10015,
	CUSTOMREQUEST  = 10036,
	FOLLOWLOCATION = 52,
	TIMEOUT        = 13,
	VERBOSE        = 41,
	USERAGENT      = 10018,
	USERNAME       = 10173,
	PASSWORD       = 10174,
	SSL_VERIFYPEER = 64,
	SSL_VERIFYHOST = 81,
	CAINFO         = 10065,
	CAINFO_BLOB    = 40309,
}

-- on non-Windows, point curl at a CA bundle (bundled cacert.pem next to the lib, or system fallback)
local defaultCainfo
local defaultCainfoBlob
if jit.os ~= "Windows" then
	local bundled = here .. "cacert.pem"

	if io.open(bundled, "rb") then
		defaultCainfo = bundled
	else
		for _, p in ipairs({ "/etc/ssl/certs/ca-certificates.crt", "/etc/pki/tls/certs/ca-bundle.crt", "/etc/ssl/cert.pem" }) do
			if io.open(p, "rb") then
				defaultCainfo = p
				break
			end
		end

		if not defaultCainfo then
			local ok, pem = pcall(require, "cacert")
			if ok then
				defaultCainfoBlob       = ffi.new("struct curl_blob")
				defaultCainfoBlob.data  = ffi.cast("void *", pem)
				defaultCainfoBlob.len   = #pem
				defaultCainfoBlob.flags = 0
			end
		end
	end
end

-- CURLINFO constants
local INFO      = {
	RESPONSE_CODE = 0x200002,
	TOTAL_TIME    = 0x300003,
	CONTENT_TYPE  = 0x100012,
	EFFECTIVE_URL = 0x100001,
}

--- @class CurlResponse
--- @field status number HTTP status code
--- @field body string Response body
--- @field contentType string|nil Content-Type header value
--- @field effectiveUrl string|nil Final URL after redirects
--- @field totalTime number Total request time in seconds

--- @class CurlOptions
--- @field url string Request URL
--- @field method string|nil HTTP method (default: GET)
--- @field headers table<string,string>|nil Extra request headers
--- @field body string|nil Request body (sets POST if method not specified)
--- @field timeout number|nil Timeout in seconds
--- @field followRedirects boolean|nil Follow redirects (default: true)
--- @field verbose boolean|nil Enable verbose output
--- @field useragent string|nil User-Agent string
--- @field username string|nil Username for auth
--- @field password string|nil Password for auth
--- @field verifySsl boolean|nil Verify SSL cert (default: true)

-- pre-allocated output slots reused across requests
local statusOut = ffi.new("long[1]")
local timeOut   = ffi.new("double[1]")
local ctOut     = ffi.new("char*[1]")
local urlOut    = ffi.new("char*[1]")

-- persistent write buffer and callback
local buf       = buffer.new()
local writeCb   = ffi.cast("curl_write_callback", function(ptr, size, nmemb, _)
	local len = size * nmemb
	buf:putcdata(ptr, len)
	return len
end)

-- persistent curl handle reused across requests
local handle    = lib.curl_easy_init()
assert(handle ~= nil, "curl_easy_init failed")

local function setlong(opt, val)
	lib.curl_easy_setopt(handle, opt, ffi.cast("long", val))
end

--- Perform an HTTP request.
--- @param opts CurlOptions
--- @return CurlResponse|nil, string|nil
local function request(opts)
	lib.curl_easy_reset(handle)
	buf:reset()

	lib.curl_easy_setopt(handle, OPT.URL, opts.url)
	lib.curl_easy_setopt(handle, OPT.WRITEFUNCTION, writeCb)
	setlong(OPT.FOLLOWLOCATION, (opts.followRedirects == false) and 0 or 1)
	setlong(OPT.SSL_VERIFYPEER, (opts.verifySsl == false) and 0 or 1)
	setlong(OPT.SSL_VERIFYHOST, (opts.verifySsl == false) and 0 or 2)
	if defaultCainfo then
		lib.curl_easy_setopt(handle, OPT.CAINFO, defaultCainfo)
	elseif defaultCainfoBlob then
		lib.curl_easy_setopt(handle, OPT.CAINFO_BLOB, defaultCainfoBlob)
	end

	if opts.timeout then setlong(OPT.TIMEOUT, opts.timeout) end
	if opts.verbose then setlong(OPT.VERBOSE, 1) end
	if opts.useragent then lib.curl_easy_setopt(handle, OPT.USERAGENT, opts.useragent) end
	if opts.username then lib.curl_easy_setopt(handle, OPT.USERNAME, opts.username) end
	if opts.password then lib.curl_easy_setopt(handle, OPT.PASSWORD, opts.password) end

	-- headers
	local slist = nil
	if opts.headers then
		for k, v in pairs(opts.headers) do
			slist = lib.curl_slist_append(slist, k .. ": " .. v)
		end
		lib.curl_easy_setopt(handle, OPT.HTTPHEADER, slist)
	end

	-- method / body
	local method = opts.method and opts.method:upper()
	if opts.body then
		lib.curl_easy_setopt(handle, OPT.POSTFIELDS, opts.body)
		if method and method ~= "POST" then
			lib.curl_easy_setopt(handle, OPT.CUSTOMREQUEST, method)
		end
	elseif method and method ~= "GET" then
		lib.curl_easy_setopt(handle, OPT.CUSTOMREQUEST, method)
	end

	local code = lib.curl_easy_perform(handle)
	if code ~= 0 then
		if slist then lib.curl_slist_free_all(slist) end
		return nil, ffi.string(lib.curl_easy_strerror(code))
	end

	lib.curl_easy_getinfo(handle, INFO.RESPONSE_CODE, statusOut)
	lib.curl_easy_getinfo(handle, INFO.TOTAL_TIME, timeOut)
	lib.curl_easy_getinfo(handle, INFO.CONTENT_TYPE, ctOut)
	lib.curl_easy_getinfo(handle, INFO.EFFECTIVE_URL, urlOut)

	local result = {
		status       = tonumber(statusOut[0]),
		body         = buf:tostring(),
		totalTime    = tonumber(timeOut[0]),
		contentType  = ctOut[0] ~= nil and ffi.string(ctOut[0]) or nil,
		effectiveUrl = urlOut[0] ~= nil and ffi.string(urlOut[0]) or nil,
	}

	if slist then lib.curl_slist_free_all(slist) end

	return result, nil
end

local curl = {}

--- @param opts CurlOptions
--- @return CurlResponse|nil, string|nil
curl.request = request

--- @param url string
--- @param opts CurlOptions|nil
--- @return CurlResponse|nil, string|nil
function curl.get(url, opts)
	local o = opts or {}
	o.url = url
	o.method = "GET"

	return request(o)
end

--- @param url string
--- @param body string
--- @param opts CurlOptions|nil
--- @return CurlResponse|nil, string|nil
function curl.post(url, body, opts)
	local o = opts or {}
	o.url = url
	o.method = "POST"
	o.body = body

	return request(o)
end

--- @param url string
--- @param path string
--- @param opts CurlOptions|nil
--- @return boolean, string|nil
function curl.download(url, path, opts)
	local f = ffi.C.fopen(path, "wb")
	if f == nil then
		return false, "fopen failed: " .. path
	end

	lib.curl_easy_reset(handle)
	lib.curl_easy_setopt(handle, OPT.URL, url)
	setlong(OPT.FOLLOWLOCATION, 1)
	setlong(OPT.SSL_VERIFYPEER, (opts and opts.verifySsl == false) and 0 or 1)
	setlong(OPT.SSL_VERIFYHOST, (opts and opts.verifySsl == false) and 0 or 2)
	if defaultCainfo then
		lib.curl_easy_setopt(handle, OPT.CAINFO, defaultCainfo)
	elseif defaultCainfoBlob then
		lib.curl_easy_setopt(handle, OPT.CAINFO_BLOB, defaultCainfoBlob)
	end
	lib.curl_easy_setopt(handle, OPT.WRITEDATA, f)
	local code = lib.curl_easy_perform(handle)
	ffi.C.fclose(f)

	if code ~= 0 then
		return false, ffi.string(lib.curl_easy_strerror(code))
	end

	return true, nil
end

return curl
