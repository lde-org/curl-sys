local test = require("lde-test")
local curl = require("curl-sys")

test.it("GET returns 200 for example.com", function()
	local res = curl.get("https://example.com")
	test.equal(res.status, 200)
	test.truthy(res.body:find("<html"))
end)

test.it("GET populates effective_url and total_time", function()
	local res = curl.get("https://example.com")
	test.truthy(res.effective_url)
	test.truthy(res.total_time > 0)
end)

test.it("POST sends body and returns 200", function()
	local res = curl.post("https://httpbin.org/post", "hello=world", {
		headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
	})
	test.equal(res.status, 200)
	test.truthy(res.body:find("hello"))
end)

test.it("request follows redirects by default", function()
	local res = curl.get("http://example.com") -- http -> https redirect
	test.equal(res.status, 200)
end)

test.it("request with custom method works", function()
	local res = curl.request({ url = "https://httpbin.org/put", method = "PUT", body = "{}", headers = { ["Content-Type"] = "application/json" } })
	test.equal(res.status, 200)
end)

test.it("download writes file to disk", function()
	local path = "/tmp/curl-sys-test-download.html"
	curl.download("https://example.com", path)
	local f = io.open(path, "r")
	test.truthy(f)
	local content = f:read("*a")
	f:close()
	os.remove(path)
	test.truthy(content:find("<html"))
end)