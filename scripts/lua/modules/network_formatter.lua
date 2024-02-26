--
-- (C) 2013-24 - ntop.org
--

require "check_redis_prefs"
require "label_utils"
local format_utils = require "format_utils"

local network_formatter = {}

-- ##############################################

function network_formatter.network2record(ifId, network)
   local record = {}
   local throughput_type = getThroughputType()
   
   record["key"] = tostring(network["network_id"])

   local network_link = "<A HREF='"..ntop.getHttpPrefix()..'/lua/hosts_stats.lua?network='..network["network_id"].."' title='"..network["network_key"].."'>"..getFullLocalNetworkName(network["network_key"])..'</A>'
   
   network["host_score_ratio"] = ternary(network["num_hosts"] and network["num_hosts"]>0, math.floor((network["score"] or 0) / (network["num_hosts"] or 0)) , '')

   record["column_id"] = network_link
   record["column_score"] = format_utils.format_high_num_value_for_tables(network, "score") 
   record["column_hosts"] = format_utils.format_high_num_value_for_tables(network, "num_hosts")
   record["column_alerted_flows"] = format_utils.format_high_num_value_for_tables(network["alerted_flows"], "total")
   record["column_host_score_ratio"] = format_utils.format_high_num_value_for_tables(network, "host_score_ratio")

   local sent2rcvd = round((network["bytes.sent"] * 100) / (network["bytes.sent"] + network["bytes.rcvd"]), 0)
   record["column_breakdown"] = "<div class='progress'><div class='progress-bar bg-warning' style='width: "
      .. sent2rcvd .."%;'>Sent</div><div class='progress-bar bg-success' style='width: " .. (100-sent2rcvd) .. "%;'>Rcvd</div></div>"

   if(throughput_type == "pps") then
      record["column_thpt"] = format_utils.pktsToSize(network["throughput_pps"])
   else
      record["column_thpt"] = format_utils.bitsToSize(8*network["throughput_bps"])
   end

   record["column_traffic"] = format_utils.bytesToSize(network["bytes.sent"] + network["bytes.rcvd"])

   if not areInterfaceTimeseriesEnabled(ifId) then
      record["column_chart"] = ""
   else
      record["column_chart"] = '<A HREF="'..ntop.getHttpPrefix()..'/lua/network_details.lua?network='..network["network_id"]..'&page=historical"><i class=\'fas fa-chart-area fa-lg\'></i></A>'
   end
   
   return record
end

return network_formatter
