local _, ns = ...

-- Pure module: the self-whisper that names a soul when the client hides the target's
-- name. The addon whispers the player "SDX1:<token>:%t"; the client expands %t to the
-- target's name, and the whisper that comes back carries it. No WoW API.

local Whisper = {}
ns.Whisper = Whisper

Whisper.MARKER = "SDX1"
Whisper.TIMEOUT = 60 -- seconds of unrestricted time to wait for the reply
Whisper.CEILING = 600 -- seconds after sending, whatever the state
Whisper.MAX_NAME = 64

local PREFIX = Whisper.MARKER .. ":"

-- The text to whisper; the client replaces %t with the target's name.
function Whisper.message(token)
	return PREFIX .. token .. ":%t"
end

function Whisper.isMarker(text)
	return type(text) == "string" and text:sub(1, #PREFIX) == PREFIX
end

local function validName(name)
	return name ~= ""
		and #name <= Whisper.MAX_NAME
		and name ~= "%t"
		and not name:find("[:|%c]")
end

-- Returns token, name. token is set for any well-formed "SDX1:<token>:<rest>"; name is
-- set only when <rest> looks like a real name (not empty, not the unexpanded "%t").
function Whisper.parse(text)
	if not Whisper.isMarker(text) then
		return nil, nil
	end
	local token, rest = text:match("^" .. PREFIX .. "([^:]+):(.*)$")
	if not token then
		return nil, nil
	end
	if validName(rest) then
		return token, rest
	end
	return token, nil
end

-- Whether to send the whisper now. Every field must be exactly as listed; nil (could
-- not be read) means no.
function Whisper.shouldAsk(s)
	return s.nameHidden == true
		and s.hasTarget == true
		and s.mouseoverOther == false
		and s.focusOther == false
		and s.chatLocked == false
		and s.afk == false
		and s.dnd == false
end
