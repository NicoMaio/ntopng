--
-- (C) 2013-23 - ntop.org
--
dirs = ntop.getDirs()
package.path = dirs.installdir .. "/scripts/lua/modules/?.lua;" .. package.path
package.path = dirs.installdir .. "/scripts/lua/modules/vulnerability_scan/?.lua;" .. package.path

require "lua_utils"
local rest_utils = require "rest_utils"
local vs_utils = require "vs_utils"

local host = _GET["host"]

local function retrieve_host(host) 
    return vs_utils.retrieve_hosts_to_scan(host)
end

rest_utils.answer(rest_utils.consts.success.ok, retrieve_host(host))
