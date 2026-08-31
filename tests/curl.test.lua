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

test.it("download honors opts.timeout instead of hanging", function()
	-- A blackhole IP drops the SYN, so the connect blocks until the total
	-- timeout fires. Without the timeout option this transfer would hang
	-- forever (regression: curl.download used to ignore opts.timeout).
	local path = os.tmpname()
	local ok, err = curl.download("http://10.255.255.1:81/stall", path, { timeout = 5 })
	os.remove(path)
	test.falsy(ok)
	test.truthy(err)
	test.truthy(err:find("Timeout", 1, true), "expected a timeout error, got: " .. tostring(err))
end)

-- ── Batch (multi) transfers ────────────────────────────────────────────────

test.it("batch runs parallel GETs and preserves add order", function()
	local b, err = curl.batch()
	test.falsy(err)
	test.truthy(b)
	test.equal(b:add("https://httpbin.org/get"), 1)
	test.equal(b:add("https://httpbin.org/get"), 2)
	test.equal(b:add("https://httpbin.org/get"), 3)

	local results = b:runAll()
	b:close()

	test.equal(#results, 3)
	for _, r in ipairs(results) do
		test.equal(r.ok, true)
		test.equal(r.status, 200)
		test.truthy(r.body:find("url"))
		test.truthy(r.effectiveUrl)
		test.truthy(r.totalTime > 0)
	end
end)

test.it("batch POST sends body and returns 200", function()
	local b = curl.batch()
	b:add("https://httpbin.org/post", {
		method = "POST",
		body = "hello=world",
		headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
	})
	local results = b:runAll()
	b:close()

	test.equal(results[1].ok, true)
	test.equal(results[1].status, 200)
	test.truthy(results[1].body:find("hello"))
end)

test.it("batch request with custom method works", function()
	local b = curl.batch()
	b:add("https://httpbin.org/put", {
		method = "PUT",
		body = "{}",
		headers = { ["Content-Type"] = "application/json" },
	})
	local results = b:runAll()
	b:close()

	test.equal(results[1].ok, true)
	test.equal(results[1].status, 200)
end)

test.it("batch follows redirects by default", function()
	local b = curl.batch()
	b:add("http://example.com")
	local results = b:runAll()
	b:close()

	test.equal(results[1].ok, true)
	test.equal(results[1].status, 200)
end)

test.it("batch download writes files to disk", function()
	local path1 = os.tmpname()
	local path2 = os.tmpname()
	local b = curl.batch()
	b:add("https://httpbin.org/get", { path = path1 })
	b:add("https://httpbin.org/get", { path = path2 })
	local results = b:runAll()
	b:close()

	test.equal(results[1].ok, true)
	test.equal(results[1].path, path1)
	test.equal(results[2].ok, true)
	test.equal(results[2].path, path2)

	for _, p in ipairs({ path1, path2 }) do
		local f = io.open(p, "r")
		test.truthy(f)
		if f then
			local content = f:read("*a")
			f:close()
			os.remove(p)
			test.truthy(content:find("url"))
		end
	end
end)

test.it("batch reports per-transfer errors", function()
	local b = curl.batch()
	b:add("https://httpbin.org/get")
	b:add("http://nonexistent.invalid.host/get", { timeout = 5 })
	local results = b:runAll()
	b:close()

	test.equal(results[1].ok, true)
	test.equal(results[1].status, 200)
	test.equal(results[2].ok, false)
	test.truthy(results[2].err)
end)

test.it("batch add with unwritable path reports error", function()
	local b = curl.batch()
	b:add("https://httpbin.org/get", { path = "/nonexistent-dir/foo.bin" })
	local results = b:runAll()
	b:close()

	test.equal(results[1].ok, false)
	test.truthy(results[1].err:find("fopen"))
end)

test.it("batch progress callback reports done/total", function()
	local done, total = 0, 0
	local b = curl.batch({
		progress = function(d, t)
			done = d
			total = t
		end,
	})
	b:add("https://httpbin.org/get")
	b:add("https://httpbin.org/get")
	local results = b:runAll()
	b:close()

	test.equal(#results, 2)
	test.equal(total, 2)
	test.equal(done, 2)
end)

test.it("batch per-transfer progress callback can abort", function()
	local count = 0
	local b = curl.batch()
	b:add("https://httpbin.org/get", {
		progress = function(dltotal, dlnow, ultotal, ulnow)
			count = count + 1
			return true -- abort immediately
		end,
	})
	local results = b:runAll()
	b:close()

	test.equal(results[1].ok, false)
	test.truthy(results[1].err)
	test.equal(count, 1)
end)

test.it("batch pump/wait drive transfers incrementally", function()
	local b = curl.batch()
	b:add("https://httpbin.org/get")
	b:add("https://httpbin.org/get")

	local running = b:pump()
	while running > 0 do
		b:wait(50)
		running = b:pump()
	end

	local results = b:results()
	b:close()
	test.equal(results[1].ok, true)
	test.equal(results[1].status, 200)
	test.equal(results[2].ok, true)
	test.equal(results[2].status, 200)
end)

test.it("batch results before completion report unfinished transfers", function()
	local b = curl.batch()
	b:add("https://httpbin.org/get")
	local results = b:results()
	b:close()

	test.equal(results[1].ok, false)
	test.equal(results[1].err, "transfer not finished")
end)
