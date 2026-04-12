local test = require("lde-test")
local curl = require("curl-sys")

do
	local ffi = require("ffi")
	print("DEBUG jit.os=" .. jit.os .. " jit.arch=" .. jit.arch)
	print("DEBUG ANDROID_ROOT=" .. tostring(os.getenv("ANDROID_ROOT")))
	print("DEBUG TMPDIR=" .. tostring(os.getenv("TMPDIR")))
	print("DEBUG os.tmpname type=" .. type(os.tmpname))
	local ok, val = pcall(os.tmpname)
	print("DEBUG os.tmpname() ok=" .. tostring(ok) .. " val=" .. tostring(val))
	print("DEBUG package.path=" .. package.path)
	-- find where curl-sys init.lua lives
	local curlHere = debug.getinfo(curl.get, "S").source:sub(2):match("(.*[/\\])") or ""
	print("DEBUG curl-sys dir=" .. curlHere)
	print("DEBUG cacert.pem exists=" .. tostring(io.open(curlHere .. "cacert.pem", "rb") ~= nil))
	print("DEBUG cacert.lua exists=" .. tostring(io.open(curlHere .. "cacert.lua", "rb") ~= nil))
	local ok2, pem = pcall(require, "cacert")
	print("DEBUG require cacert ok=" .. tostring(ok2) .. " type=" .. type(pem))
	-- check system ca paths
	for _, p in ipairs({"/etc/ssl/certs/ca-certificates.crt", "/etc/pki/tls/certs/ca-bundle.crt", "/etc/ssl/cert.pem", "/data/data/com.termux/files/usr/etc/tls/cert.pem"}) do
		print("DEBUG ca path " .. p .. " exists=" .. tostring(io.open(p, "rb") ~= nil))
	end
end

do
	local here = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or ""
	local curlHere = debug.getinfo(curl.get, "S").source:sub(2):match("(.*[/\\])") or ""
	print("DEBUG test dir: " .. here)
	print("DEBUG curl-sys dir: " .. curlHere)
	print("DEBUG package.path: " .. package.path)
	local bundled = curlHere .. "cacert.pem"
	print("DEBUG cacert.pem exists: " .. tostring(io.open(bundled, "rb") ~= nil))
	print("DEBUG ANDROID_ROOT: " .. tostring(os.getenv("ANDROID_ROOT")))
	print("DEBUG TMPDIR: " .. tostring(os.getenv("TMPDIR")))
	print("DEBUG os.tmpname: " .. tostring(os.tmpname()))
end

test.it("GET returns 200 for lde.sh", function()
	local res, err = curl.get("https://lde.sh")
	test.falsy(err)
	test.equal(res.status, 200)
end)

test.it("GET returns 200 for httpbin.org", function()
	local res, err = curl.get("https://httpbin.org/get")
	test.falsy(err)
	test.equal(res.status, 200)
	test.truthy(res.body:find("url"))
end)

test.it("GET populates effectiveUrl and totalTime", function()
	local res, err = curl.get("https://httpbin.org/get")
	test.falsy(err)
	test.truthy(res.effectiveUrl)
	test.truthy(res.totalTime > 0)
end)

test.it("POST sends body and returns 200", function()
	local res, err = curl.post("https://httpbin.org/post", "hello=world", {
		headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
	})
	test.falsy(err)
	test.equal(res.status, 200)
	test.truthy(res.body:find("hello"))
end)

test.it("request follows redirects by default", function()
	local res, err = curl.get("http://example.com")
	test.falsy(err)
	test.equal(res.status, 200)
end)

test.it("request with custom method works", function()
	local res, err = curl.request({ url = "https://httpbin.org/put", method = "PUT", body = "{}", headers = { ["Content-Type"] = "application/json" } })
	test.falsy(err)
	test.equal(res.status, 200)
end)

test.it("download writes file to disk", function()
	local path = os.tmpname()
	local ok, err = curl.download("https://httpbin.org/get", path)
	test.falsy(err)
	test.truthy(ok)
	local f = io.open(path, "r")
	test.truthy(f)
	local content = f:read("*a")
	f:close()
	os.remove(path)
	test.truthy(content:find("url"))
end)

test.it("download follows redirects and writes a non-empty tar.gz", function()
	local path = os.tmpname() .. ".tar.gz"
	local ok, err = curl.download("https://github.com/hoelzro/lua-term/archive/0.08.tar.gz", path)
	test.falsy(err)
	test.truthy(ok)
	local f = io.open(path, "rb")
	test.truthy(f)
	local magic = f:read(2)
	f:close()
	os.remove(path)
	-- gzip magic bytes: 0x1f 0x8b
	test.equal(magic, "\31\139")
end)
