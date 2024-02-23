--
-- (C) 2019-24 - ntop.org
--

local checks = require ("checks")
local flow_alert_keys = require "flow_alert_keys"

-- #################################################################

-- NOTE: this module is always enabled
local script = {
  -- Script category
  category = checks.check_categories.network,
  default_enabled = false,

  -- This script is only for alerts generation
  alert_id = flow_alert_keys.flow_alert_tcp_packets_issues,

  default_value = {
    retransmissions = {
      default_value = 15, -- 15%,
      field_min = 0, -- 0%
      field_max = 99, -- 99%
      field_operator = "gt";
      i18n_fields_unit = checks.field_units.percentage,
      i18n_title = 'retransmission'
    },
    out_of_orders = {
      default_value = 15, -- 15%,
      field_min = 0, -- 0%
      field_max = 99, -- 99%
      field_operator = "gt";
      i18n_fields_unit = checks.field_units.percentage,
      i18n_title = 'out_of_order'
    },
    packet_loss = {
      default_value = 15, -- 15%,
      field_min = 0, -- 0%
      field_max = 99, -- 99%
      field_operator = "gt";
      i18n_fields_unit = checks.field_units.percentage,
      i18n_title = 'packet_loss'
    },
  },

  gui = {
    i18n_title = "flow_checks_config.tcp_packets_issues",
    i18n_description = "flow_checks_config.tcp_packets_issues_description",
    input_builder = "multi_threshold_cross",
  }
}

-- #################################################################

return script
