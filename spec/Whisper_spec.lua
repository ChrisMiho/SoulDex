describe("Whisper", function()
	local W

	before_each(function()
		W = LoadAddonFile("src/Whisper.lua", {}).Whisper
	end)

	it("has the constants", function()
		assert.equal("SDX1", W.MARKER)
		assert.equal(60, W.TIMEOUT)
		assert.equal(600, W.CEILING)
		assert.equal(64, W.MAX_NAME)
	end)

	it("builds the message", function()
		assert.equal("SDX1:a1:%t", W.message("a1"))
	end)

	describe("parse", function()
		it("reads a token and a name", function()
			local token, name = W.parse("SDX1:a1:Scarlet Chaplain")
			assert.equal("a1", token)
			assert.equal("Scarlet Chaplain", name)
		end)

		it("keeps the token but no name when unexpanded", function()
			local token, name = W.parse("SDX1:a1:%t")
			assert.equal("a1", token)
			assert.is_nil(name)
		end)

		it("rejects invalid names but keeps the token", function()
			local bad = {
				"SDX1:a1:",
				"SDX1:a1:Bad|cffname",
				"SDX1:a1:a:b",
				"SDX1:a1:line\nbreak",
				"SDX1:a1:" .. string.rep("x", 65),
			}
			for _, text in ipairs(bad) do
				local token, name = W.parse(text)
				assert.equal("a1", token, text)
				assert.is_nil(name, text)
			end
		end)

		it("accepts a 64 character name", function()
			local long = string.rep("x", 64)
			local _, name = W.parse("SDX1:a1:" .. long)
			assert.equal(long, name)
		end)

		it("returns nil, nil for anything else", function()
			for _, v in ipairs({ "hello", "SDX1:", "SDX1::name", "SDX1:a1", 42, true }) do
				local token, name = W.parse(v)
				assert.is_nil(token)
				assert.is_nil(name)
			end
			local token, name = W.parse(nil)
			assert.is_nil(token)
			assert.is_nil(name)
		end)
	end)

	describe("isMarker", function()
		it("recognises the marker at the start only", function()
			assert.is_true(W.isMarker("SDX1:x:y"))
			assert.is_false(W.isMarker("sdx1:x"))
			assert.is_false(W.isMarker("hi SDX1:"))
			assert.is_false(W.isMarker(nil))
			assert.is_false(W.isMarker(7))
		end)
	end)

	describe("shouldAsk", function()
		local function base()
			return {
				nameHidden = true,
				hasTarget = true,
				mouseoverOther = false,
				focusOther = false,
				chatLocked = false,
				afk = false,
				dnd = false,
			}
		end

		it("asks only when every condition holds", function()
			assert.is_true(W.shouldAsk(base()))
		end)

		for _, field in ipairs({ "nameHidden", "hasTarget", "mouseoverOther", "focusOther", "chatLocked", "afk", "dnd" }) do
			it("does not ask when " .. field .. " is flipped", function()
				local s = base()
				s[field] = not s[field]
				assert.is_false(W.shouldAsk(s))
			end)

			it("does not ask when " .. field .. " is unreadable", function()
				local s = base()
				s[field] = nil
				assert.is_false(W.shouldAsk(s))
			end)
		end
	end)
end)
