local m, s

m = Map("kai", translate("KAI"), translate("KAI is an efficient AI tool."))
m:section(SimpleSection).template  = "kai/kai_status"

s=m:section(TypedSection, "kai", translate("Global settings"))
s.addremove=false
s.anonymous=true

s:option(Flag, "enabled", translate("Enable")).rmempty=false

local cwd = s:option(Value, "cwd", translate("Working directory"))
cwd.default = "/tmp/kai"
cwd.rmempty = false

local data_dir = s:option(Value, "data_dir", translate("Data directory"))
data_dir.placeholder = ""
data_dir.rmempty = true
data_dir.description = translate("Optional. If set, KAI session will store cache/data/config/state under this directory. If empty, everything falls back to the working directory.")

return m
