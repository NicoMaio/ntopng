--
-- (C) 2019-24 - ntop.org
--

local dirs = ntop.getDirs()
package.path = dirs.installdir .. "/scripts/lua/modules/?.lua;" .. package.path

local checks = require("checks")

local syslog_module = {
  -- Script category
  category = checks.check_categories.security,

  key = "host_log",

  default_value = {
    operator = "lt",
    threshold = 5,
  },

  gui = {
    i18n_title = "host_log_collector.title",
    i18n_description = "host_log_collector.description",
    input_builder = "threshold_cross",
    field_max = 7,
    field_min = 0,
    field_operator = "lt"
  },

  -- See below
  hooks = {},
}

-- #################################################################

-- The function below is called once (#pragma once)
function syslog_module.setup()
   return true
end

-- #################################################################

-- The function below is called for each received alert
function syslog_module.hooks.handleEvent(syslog_conf, message, host, priority)
   local syslog_utils = require "syslog_utils"
   local num_unhandled = 0
   local num_alerts = 0

   if not isEmptyString(host) then
      local is_alert = syslog_utils.handle_event(message, host, priority,
         syslog_conf.host_log.all.script_conf.threshold)
      if is_alert then
         num_alerts = num_alerts + 1
      end
   else
      num_unhandled = num_unhandled + 1
   end

   interface.incSyslogStats(1, 0, num_unhandled, num_alerts, 0, 0)
end 

-- #################################################################

-- The function below is called once (#pragma once)
function syslog_module.teardown()
   return true
end

-- #################################################################

return syslog_module
