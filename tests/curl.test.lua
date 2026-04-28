local test = require("lde-test")
local curl = require("curl-sys")

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
		headers = { ["Content-Type"] = "application/x-www-form-urlencoded" }
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

test.it("request calls progress callback", function()
	local called = 0
	local res, err = curl.request({
		url = "https://httpbin.org/get",
		progress = function(dltotal, dlnow, ultotal, ulnow)
			called = called + 1
		end,
	})
	test.falsy(err)
	test.equal(res.status, 200)
	test.truthy(called > 0)
end)

test.it("request progress callback can abort", function()
	local count = 0
	local res, err = curl.request({
		url = "https://httpbin.org/get",
		progress = function(dltotal, dlnow, ultotal, ulnow)
			count = count + 1
			return true -- abort immediately
		end,
	})
	test.truthy(err)
	test.falsy(res)
	test.equal(count, 1)
end)

test.it("download calls progress callback", function()
	local path = os.tmpname()
	local called = 0
	local ok, err = curl.download("https://httpbin.org/get", path, {
		progress = function(dltotal, dlnow, ultotal, ulnow)
			called = called + 1
		end,
	})
	os.remove(path)
	test.falsy(err)
	test.truthy(ok)
	test.truthy(called > 0)
end)

test.it("download progress callback can abort", function()
	local path = os.tmpname()
	local count = 0
	local ok, err = curl.download("https://httpbin.org/get", path, {
		progress = function(dltotal, dlnow, ultotal, ulnow)
			count = count + 1
			return true -- abort immediately
		end,
	})
	os.remove(path)
	test.truthy(err)
	test.falsy(ok)
	test.equal(count, 1)
end)
