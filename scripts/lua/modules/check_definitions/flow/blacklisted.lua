--
-- (C) 2019-24 - ntop.org
--

local checks = require("checks")
local alerts_api = require "alerts_api"
local alert_consts = require("alert_consts")
local flow_alert_keys = require "flow_alert_keys"

-- #################################################################

local script = {
   -- Script category
   category = checks.check_categories.security, 

   alert_id = flow_alert_keys.flow_alert_blacklisted,

   gui = {
      i18n_title = "flow_checks_config.blacklisted",
      i18n_description = "flow_checks_config.blacklisted_description",
   }
}

-- #################################################################

return script
