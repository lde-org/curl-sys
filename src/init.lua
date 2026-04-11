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
]]

local here = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or ""
local sep = string.sub(package.config, 1, 1)
local libname = sep == "\\" and "curl.dll" or (jit.os == "OSX" and "libcurl.dylib" or "libcurl.so")
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
}

-- CURLINFO constants
local INFO = {
	RESPONSE_CODE = 0x200002,
	TOTAL_TIME    = 0x300003,
	CONTENT_TYPE  = 0x100012,
	EFFECTIVE_URL = 0x100001,
}

--- @class CurlResponse
--- @field status number HTTP status code
--- @field body string Response body
--- @field content_type string|nil Content-Type header value
--- @field effective_url string|nil Final URL after redirects
--- @field total_time number Total request time in seconds

--- @class CurlOptions
--- @field url string Request URL
--- @field method string|nil HTTP method (default: GET)
--- @field headers table<string,string>|nil Extra request headers
--- @field body string|nil Request body (sets POST if method not specified)
--- @field timeout number|nil Timeout in seconds
--- @field follow_redirects boolean|nil Follow redirects (default: true)
--- @field verbose boolean|nil Enable verbose output
--- @field useragent string|nil User-Agent string
--- @field username string|nil Username for auth
--- @field password string|nil Password for auth
--- @field verify_ssl boolean|nil Verify SSL cert (default: true)

-- pre-allocated output slots reused across requests
local status_out = ffi.new("long[1]")
local time_out   = ffi.new("double[1]")
local ct_out     = ffi.new("char*[1]")
local url_out    = ffi.new("char*[1]")

-- persistent write buffer and callback
local buf = buffer.new()
local writecb = ffi.cast("curl_write_callback", function(ptr, size, nmemb, _)
	local len = size * nmemb
	buf:putcdata(ptr, len)
	return len
end)

--- Perform an HTTP request.
--- @param opts CurlOptions
--- @return CurlResponse
local function request(opts)
	local handle = lib.curl_easy_init()
	assert(handle ~= nil, "curl_easy_init failed")

	buf:reset()

	lib.curl_easy_setopt(handle, OPT.URL, opts.url)
	lib.curl_easy_setopt(handle, OPT.WRITEFUNCTION, writecb)
	lib.curl_easy_setopt(handle, OPT.FOLLOWLOCATION, (opts.follow_redirects == false) and 0 or 1)
	lib.curl_easy_setopt(handle, OPT.SSL_VERIFYPEER, (opts.verify_ssl == false) and 0 or 1)
	lib.curl_easy_setopt(handle, OPT.SSL_VERIFYHOST, (opts.verify_ssl == false) and 0 or 2)

	if opts.timeout then lib.curl_easy_setopt(handle, OPT.TIMEOUT, opts.timeout) end
	if opts.verbose then lib.curl_easy_setopt(handle, OPT.VERBOSE, 1) end
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
		if not method or method == "POST" then
			method = nil -- curl defaults to POST when POSTFIELDS is set
		else
			lib.curl_easy_setopt(handle, OPT.CUSTOMREQUEST, method)
		end
	elseif method and method ~= "GET" then
		lib.curl_easy_setopt(handle, OPT.CUSTOMREQUEST, method)
	end

	local code = lib.curl_easy_perform(handle)
	assert(code == 0, ffi.string(lib.curl_easy_strerror(code)))

	lib.curl_easy_getinfo(handle, INFO.RESPONSE_CODE, status_out)
	lib.curl_easy_getinfo(handle, INFO.TOTAL_TIME, time_out)
	lib.curl_easy_getinfo(handle, INFO.CONTENT_TYPE, ct_out)
	lib.curl_easy_getinfo(handle, INFO.EFFECTIVE_URL, url_out)

	local result = {
		status        = tonumber(status_out[0]),
		body          = buf:tostring(),
		total_time    = tonumber(time_out[0]),
		content_type  = ct_out[0] ~= nil and ffi.string(ct_out[0]) or nil,
		effective_url = url_out[0] ~= nil and ffi.string(url_out[0]) or nil,
	}

	if slist then lib.curl_slist_free_all(slist) end
	lib.curl_easy_cleanup(handle)

	return result
end

local function merge(base, over)
	local t = {}
	for k, v in pairs(base) do t[k] = v end
	for k, v in pairs(over) do t[k] = v end
	return t
end

--- @class curl
--- @field request fun(opts: CurlOptions): CurlResponse
--- @field get fun(url: string, opts: CurlOptions|nil): CurlResponse
--- @field post fun(url: string, body: string, opts: CurlOptions|nil): CurlResponse
return {
	request = request,
	get = function(url, opts) return request(merge({ url = url, method = "GET" }, opts or {})) end,
	post = function(url, body, opts) return request(merge({ url = url, method = "POST", body = body }, opts or {})) end,
}
