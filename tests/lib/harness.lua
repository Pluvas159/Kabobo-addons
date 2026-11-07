-- Tiny test framework shared by every addon's tests. Loaded before the addon files.
--   test(name, fn)          run fn; a raised error fails the test
--   eq(actual, expected)    strict equality
--   near(actual, expected, tolerance)
--   truthy(value, msg)
local results = { passed = 0, failed = 0 }
_RESULTS = results

function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		results.passed = results.passed + 1
	else
		results.failed = results.failed + 1
		_REAL_PRINT("  FAIL  " .. name .. "\n        " .. tostring(err))
	end
end

function eq(actual, expected, msg)
	if actual ~= expected then
		error((msg and (msg .. ": ") or "") .. "expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
	end
end

function near(actual, expected, tolerance, msg)
	tolerance = tolerance or 1e-6
	if type(actual) ~= "number" or math.abs(actual - expected) > tolerance then
		error((msg and (msg .. ": ") or "") .. "expected " .. tostring(expected) .. " +/- " .. tolerance .. ", got " .. tostring(actual), 2)
	end
end

function truthy(value, msg)
	if not value then error(msg or "expected a truthy value", 2) end
end
