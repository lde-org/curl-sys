local ffi = require("ffi")
local curl = require("curl-sys")

if ffi.os == "Windows" then
	ffi.cdef [[
		typedef union { struct { uint32_t lo, hi; }; uint64_t val; } LARGE_INTEGER;
		int QueryPerformanceCounter(LARGE_INTEGER *lpPerformanceCount);
		int QueryPerformanceFrequency(LARGE_INTEGER *lpFrequency);
	]]
	local freq = ffi.new("LARGE_INTEGER")
	ffi.C.QueryPerformanceFrequency(freq)
	local f = tonumber(freq.val)
	function now()
		local t = ffi.new("LARGE_INTEGER")
		ffi.C.QueryPerformanceCounter(t)
		return tonumber(t.val) * 1e9 / f
	end
else
	ffi.cdef [[
		typedef struct { long tv_sec; long tv_nsec; } timespec;
		int clock_gettime(int clk_id, timespec *tp);
	]]
	function now()
		local t = ffi.new("timespec")
		ffi.C.clock_gettime(1, t)
		return tonumber(t.tv_sec) * 1e9 + tonumber(t.tv_nsec)
	end
end

---@param label string
---@param fn fun()
local function bench(label, fn, iterations)
	iterations = iterations or 10
	-- warmup
	fn()
	local start = now()
	for _ = 1, iterations do fn() end
	local elapsed = (now() - start) / 1e9
	print(string.format("%-40s %dx  avg %.3fs  total %.3fs", label, iterations, elapsed / iterations, elapsed))
end

print(string.format("%-40s %s", "benchmark", "results"))
print(string.rep("-", 70))

bench("GET https://example.com", function()
	curl.get("https://example.com")
end)

bench("GET https://httpbin.org/get", function()
	curl.get("https://httpbin.org/get")
end)

bench("POST https://httpbin.org/post", function()
	curl.post("https://httpbin.org/post", "hello=world", {
		headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
	})
end, 5)
