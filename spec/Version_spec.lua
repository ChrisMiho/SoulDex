describe("Version", function()
	local Version

	before_each(function()
		Version = LoadAddonFile("src/Version.lua", {}).Version
	end)

	describe("parse", function()
		it("reads releases with and without the v", function()
			assert.same({ major = 1, minor = 4, patch = 0 }, Version.parse("v1.4.0"))
			assert.same({ major = 1, minor = 4, patch = 12 }, Version.parse("1.4.12"))
		end)

		it("reads prereleases", function()
			assert.same({ major = 1, minor = 4, patch = 0, pre = "beta", preNum = 1 }, Version.parse("v1.4.0-beta.1"))
			assert.same({ major = 1, minor = 4, patch = 0, pre = "alpha", preNum = 0 }, Version.parse("1.4.0-Alpha"))
			assert.same({ major = 1, minor = 4, patch = 0, pre = "beta", preNum = 2 }, Version.parse("1.4.0-beta2"))
		end)

		it("refuses anything else", function()
			for _, junk in ipairs({ "dev", "", "1.4", "v1.4.0 ", "1.4.0-beta.1.2", "1.4.0+build", "99999.0.0", "a.b.c" }) do
				assert.is_nil(Version.parse(junk), junk)
			end
			assert.is_nil(Version.parse(nil))
			assert.is_nil(Version.parse(140))
			assert.is_nil(Version.parse("1.0.0-" .. string.rep("b", 40)))
		end)
	end)

	describe("isNewer", function()
		it("compares number by number, not as text", function()
			assert.is_true(Version.isNewer("v1.10.0", "v1.9.9"))
			assert.is_true(Version.isNewer("2.0.0", "v1.99.99"))
			assert.is_true(Version.isNewer("1.4.1", "1.4.0"))
			assert.is_false(Version.isNewer("1.4.0", "1.4.0"))
			assert.is_false(Version.isNewer("v1.4.0", "1.4.0"))
			assert.is_false(Version.isNewer("1.3.9", "1.4.0"))
		end)

		it("puts a prerelease before its release", function()
			assert.is_true(Version.isNewer("1.4.0", "1.4.0-beta.3"))
			assert.is_true(Version.isNewer("1.4.0-beta.2", "1.4.0-beta.1"))
			assert.is_true(Version.isNewer("1.4.0-beta.1", "1.4.0-alpha.9"))
			assert.is_false(Version.isNewer("1.4.0-beta.1", "1.4.0-beta.1"))
		end)

		it("never tells a release player about a prerelease", function()
			assert.is_false(Version.isNewer("1.5.0-beta.1", "1.4.0"))
			assert.is_true(Version.isNewer("1.5.0-beta.1", "1.4.0-beta.1"))
		end)

		it("is false when either side can't be read", function()
			assert.is_false(Version.isNewer("9.9.9", "dev"))
			assert.is_false(Version.isNewer("dev", "1.0.0"))
			assert.is_false(Version.isNewer(nil, "1.0.0"))
		end)
	end)

	it("displays with one v", function()
		assert.equal("v1.4.0", Version.display("1.4.0"))
		assert.equal("v1.4.0-beta.1", Version.display("v1.4.0-beta.1"))
		assert.is_nil(Version.display("dev"))
	end)
end)
