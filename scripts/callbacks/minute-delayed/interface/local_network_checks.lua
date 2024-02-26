--
-- (C) 2019-24 - ntop.org
--

local dirs = ntop.getDirs()
package.path = dirs.installdir .. "/scripts/lua/modules/?.lua;" .. package.path

local checks = require "checks"

-- #################################################################
-- Just like for interface_checks.lua, here periodic local network 
-- checks are executed with the right granularity
-- #################################################################

local checks_var = {
   ifid = nil,
   pools_instance = nil,
   network_entity = nil, 
   configset = nil,
   available_modules = nil,
}

local granularity = "min"
local do_trace = false

-- #################################################################

local local_networks = interface.getNetworksStats()

for _, net_stats in pairs(local_networks) do
   network.select(net_stats.network_id)
   
   checks.localNetworkChecks(granularity, checks_var, do_trace) 
end
