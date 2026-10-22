local tern = require("tern")
local identity = require("./lib/tool_identity")

tern.on("spawn", identity.spawn)
