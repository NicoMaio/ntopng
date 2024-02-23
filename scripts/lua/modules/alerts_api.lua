--
-- (C) 2013-24 - ntop.org
--
local clock_start = os.clock()

local dirs = ntop.getDirs()
package.path = dirs.installdir .. "/scripts/lua/modules/?.lua;" .. package.path
package.path = dirs.installdir .. "/scripts/lua/modules/alert_store/?.lua;" .. package.path
package.path = dirs.installdir .. "/scripts/lua/modules/pools/?.lua;" .. package.path
package.path = dirs.installdir .. "/scripts/lua/modules/notifications/?.lua;" .. package.path

require "ntop_utils"
local alert_entities = require "alert_entities"
local alert_consts = require "alert_consts"
local recipients = require "recipients"
local alert_entity_builders = require "alert_entity_builders"
local do_trace = false

local alerts_api = {}

-- #################################################

-- For backwards compatibility, redefine these alerts as part of alerts_api
alerts_api.hostAlertEntity = alert_entity_builders.hostAlertEntity
alerts_api.interfaceAlertEntity = alert_entity_builders.interfaceAlertEntity
alerts_api.networkAlertEntity = alert_entity_builders.networkAlertEntity
alerts_api.snmpInterfaceEntity = alert_entity_builders.snmpInterfaceEntity
alerts_api.snmpDeviceEntity = alert_entity_builders.snmpDeviceEntity
alerts_api.macEntity = alert_entity_builders.macEntity
alerts_api.userEntity = alert_entity_builders.userEntity
alerts_api.hostPoolEntity = alert_entity_builders.hostPoolEntity
alerts_api.amThresholdCrossEntity = alert_entity_builders.amThresholdCrossEntity
alerts_api.systemEntity = alert_entity_builders.systemEntity
alerts_api.iec104Entity = alert_entity_builders.iec104Entity

-- #################################################

local current_script
local current_configset -- The configset used for the generation of this alert

-- ##############################################

local function debug_print(msg)
    if not do_trace then
        return
    end

    traceError(TRACE_NORMAL, TRACE_CONSOLE, msg)
end

-- ##############################################

-- Returns a string which identifies an alert
function alerts_api.getAlertId(alert)
    return (string.format("%s_%s_%s_%s_%s", alert.alert_type, alert.subtype or "", alert.granularity or "",
        alert.entity_id, alert.entity_val))
end

-- ##############################################

-- @brief Returns a key containing a hashed string of the `alert` to quickly identify the alert notification
-- @param alert A triggered/released alert table
-- @return The key as a string
local function get_notification_key(alert)
    return string.format("ntopng.cache.alerts.notification.%s", ntop.md5(alerts_api.getAlertId(alert)))
end

-- ##############################################

-- @brief Checks whether the triggered `alert` has already been notified
-- @param alert A triggered alert table
-- @return True if the `alert` has already been notified, false otherwise
local function is_trigger_notified(alert)
    local k = get_notification_key(alert)
    local res = tonumber(ntop.getCache(k))

    return res ~= nil
end

-- ##############################################

-- @brief Marks the triggered `alert` as notified to the recipients
-- @param alert A triggered alert table
-- @return nil
local function mark_trigger_notified(alert)
    local k = get_notification_key(alert)
    ntop.setCache(k, "1")
end

-- ##############################################

-- @brief Marks the released `alert` as notificed to the recipients
-- @param alert A released alert table
-- @return nil
local function mark_release_notified(alert)
    local k = get_notification_key(alert)
    ntop.delCache(k)
end

-- ##############################################

local function alertErrorTraceback(msg)
    traceError(TRACE_ERROR, TRACE_CONSOLE, msg)
    traceError(TRACE_ERROR, TRACE_CONSOLE, debug.traceback())
end

-- ##############################################

local function get_alert_triggered_key(alert_id, subtype)
    if not alert_id or not subtype then
        if not subtype then
            traceError(TRACE_ERROR, TRACE_CONSOLE, "subtype is nil")
        end
        if not alert_id then
            traceError(TRACE_ERROR, TRACE_CONSOLE, "alert_id is nil")
        end
        traceError(TRACE_ERROR, TRACE_CONSOLE, debug.traceback())
    end

    local res = string.format("%d@%s", alert_id, subtype)

    return res
end

-- ##############################################

function alerts_api.addAlertGenerationInfo(alert_type_params, current_script)
    if alert_type_params and current_script then
        -- Add information about the script who generated this alert
        alert_type_params.alert_generation = {
            script_key = current_script.key,
            subdir = current_script.subdir
        }
    else
        -- NOTE: there are currently some internally generated alerts which
        -- do not use the checks api (e.g. the ntopng startup)
        -- tprint(debug.traceback())
    end
end

local function addAlertGenerationInfo(alert_type_params)
    alerts_api.addAlertGenerationInfo(alert_type_params, current_script)
end

-- ##############################################

-- ! @brief Adds pool information to the alert
-- ! @param entity_info data returned by one of the entity_info building functions
local function addAlertPoolAndNetworkInfo(entity_info, alert_json)
    local pools_alert_utils = require "pools_alert_utils"
    -- Add Pool ID
    if alert_json then
        alert_json.host_pool_id = pools_alert_utils.get_host_pool_id(entity_info)
    end

    -- Add Local Network ID
    if entity_info.alert_entity == alert_entities.host and entity_info.entity_val then
        local network_id = ntop.getAddressNetwork(entity_info.entity_val)
        alert_json.network = network_id
    end
end

-- ##############################################

-- ! @brief Push filter matching the alert to Smart Recording if enabled
-- ! See also Host::enqueueAlertToRecipients for alerts triggered from C++
-- ! @param entity_info data returned by one of the entity_info building functions
local function pushSmartRecordingFilter(entity_info, ifid)
    local recording_utils = require "recording_utils"
    if entity_info.alert_entity == alert_entities.host and recording_utils.isSmartEnabled(ifid) then
        local instance = recording_utils.getN2diskInstanceName(ifid)
        local ip = entity_info.entity_val

        if not isEmptyString(instance) and not isEmptyString(ip) then

            local filter = string.format("%s", ip)

            local key = string.format("n2disk.%s.filter.host.%s", instance, filter)
            local expiration = 30 * 60 -- 30 min
            ntop.setCache(key, "1", expiration)
        end
    end
end

-- ##############################################

-- ! @param entity_info data returned by one of the entity_info building functions
-- ! @param type_info data returned by one of the type_info building functions
-- ! @param when (optional) the time when the release event occurs
-- ! @return true if the alert was successfully stored, false otherwise
function alerts_api.store(entity_info, type_info, when)
    local json = require("dkjson")
    if (not areAlertsEnabled()) then
        return (false)
    end

    local force = false
    local ifid = interface.getId()
    local granularity_sec = type_info.granularity and type_info.granularity.granularity_seconds or 0
    local granularity_id = type_info.granularity and type_info.granularity.granularity_id or -1

    type_info.alert_type_params = type_info.alert_type_params or {}
    addAlertGenerationInfo(type_info.alert_type_params)

    local alert_json = json.encode(type_info.alert_type_params)
    local subtype = type_info.subtype or ""
    when = when or os.time()

    -- Here the alert is considered stored. The actual store will be performed
    -- asynchronously

    -- NOTE: keep in sync with SQLite alert format in AlertsManager.cpp
    local alert_to_store = {
        ifid = ifid,
        action = "store",
        alert_id = type_info.alert_type.alert_key,
        alert_category = type_info.alert_category and type_info.alert_category.id,
        subtype = subtype,
        granularity = granularity_sec,
        entity_id = entity_info.alert_entity.entity_id,
        entity_val = entity_info.entity_val,
        score = type_info.score,
        device_type = type_info.device_type,
        device_name = type_info.device_name,
        tstamp = when,
        tstamp_end = when,
        json = alert_json
    }

    addAlertPoolAndNetworkInfo(entity_info, alert_to_store)

    recipients.dispatch_notification(alert_to_store, current_script)

    pushSmartRecordingFilter(entity_info, ifid)

    return (true)
end

-- ##############################################

-- @brief Determine whether the alert has already been triggered
-- @param candidate_type the candidate alert type
-- @param candidate_granularity the candidate alert granularity
-- @param candidate_alert_subtype the candidate alert subtype
-- @param cur_alerts a table of currently triggered alerts
-- @return true on if the alert has already been triggered, false otherwise
--
-- @note Example of cur_alerts
-- cur_alerts table
-- cur_alerts.1 table
-- cur_alerts.1.alert_type number 2
-- cur_alerts.1.alert_subtype string min_bytes
-- cur_alerts.1.entity_val string 192.168.2.222@0
-- cur_alerts.1.alert_granularity number 60
-- cur_alerts.1.alert_json string {"metric":"bytes","threshold":1,"value":13727070,"operator":"gt"}
-- cur_alerts.1.alert_tstamp_end number 1571328097
-- cur_alerts.1.alert_tstamp number 1571327460
-- cur_alerts.1.alert_entity number 1
local function already_triggered(cur_alerts, candidate_type, candidate_granularity, candidate_alert_subtype,
    remove_from_cur_alerts)
    for i = #cur_alerts, 1, -1 do
        local cur_alert = cur_alerts[i]

        if candidate_type == cur_alert.alert_id and candidate_granularity == cur_alert.granularity and
            candidate_alert_subtype == cur_alert.subtype then
            if remove_from_cur_alerts then
                -- Remove from cur_alerts, this will save cycles for
                -- subsequent calls of this method.
                -- Using .remove is OK here as there won't unnecessarily move memory multiple times:
                -- we return immeediately
                -- NOTE: see un-removed alerts will be released by releaseEntityAlerts in interface.lua
                table.remove(cur_alerts, i)
            end

            return true
        end
    end

    return false
end

-- ##############################################

-- ! @brief Trigger an alert of given type on the entity
-- ! @param entity_info data returned by one of the entity_info building functions
-- ! @param type_info data returned by one of the type_info building functions
-- ! @param when (optional) the time when the release event occurs
-- ! @param cur_alerts (optional) a table containing triggered alerts for the current entity
-- ! @return true on if the alert was triggered, false otherwise
-- ! @note The actual trigger is performed asynchronously
-- ! @note false is also returned if an existing alert is found and refreshed
function alerts_api.trigger(entity_info, type_info, when, cur_alerts)
    local json = require("dkjson")
    if (not areAlertsEnabled()) then
        return (false)
    end

    local ifid = interface.getId()

    if (type_info.granularity == nil) then
        alertErrorTraceback("Missing mandatory 'granularity'")
        return (false)
    end

    -- Apply defaults
    local granularity_sec = type_info.granularity and type_info.granularity.granularity_seconds or 0
    local granularity_id = type_info.granularity and type_info.granularity.granularity_id or 0 --[[ 0 is aperiodic ]]
    local subtype = type_info.subtype or ""

    when = when or os.time()

    type_info.alert_type_params = type_info.alert_type_params or {}
    addAlertGenerationInfo(type_info.alert_type_params)

    if (cur_alerts and already_triggered(cur_alerts, type_info.alert_type.alert_key, granularity_sec, subtype, true) ==
        true) then
        -- tprint("Already triggered")
        -- Alert does not belong to an exclusion filter and it is already triggered. There's nothing to do, just return.
        return true
    end

    local alert_json = json.encode(type_info.alert_type_params)

    local triggered = nil
    local alert_key_name = get_alert_triggered_key(type_info.alert_type.alert_key, subtype)

    if not type_info.score then
        traceError(TRACE_ERROR, TRACE_CONSOLE, "Alert score is not set")
        type_info.score = 0
    end

    local device_ip, port, device_name
    if (entity_info.alert_entity.entity_id == alert_consts.alertEntity("snmp_device")) then
        local snmp_device_alert_store = require"snmp_device_alert_store".new()

        device_ip, port = snmp_device_alert_store:_entity_val_to_ip_and_port(entity_info.entity_val)
        device_name = snmp_device_alert_store:get_snmp_device_sysname(device_ip)
    end

    local params = {alert_key_name, granularity_id, type_info.score, type_info.alert_type.alert_key, subtype,
                    alert_json, device_ip, device_name, port}

    if (entity_info.alert_entity.entity_id == alert_consts.alertEntity("interface")) then
        if interface.checkContext(entity_info.entity_val) then
            triggered = interface.storeTriggeredAlert(table.unpack(params))
        end
    elseif (entity_info.alert_entity.entity_id == alert_consts.alertEntity("network")) then
        if network.checkContext(entity_info.entity_val) then
            triggered = network.storeTriggeredAlert(table.unpack(params))
        end
    else
        triggered = interface.triggerExternalAlert(entity_info.alert_entity.entity_id, entity_info.entity_val,
            table.unpack(params))
    end

    if (triggered == nil) then
        -- tprint("Alert not triggered (already triggered?) @ "..granularity_sec.."] ".. entity_info.entity_val .."@"..type_info.alert_type.i18n_title..":".. subtype .. "\n")
        return (false)
    else
        -- tprint("Alert triggered @ "..granularity_sec.." ".. entity_info.entity_val .."@"..type_info.alert_type.i18n_title..":".. subtype .. "\n")
    end

    triggered.ifid = ifid
    triggered.action = "engage"

    -- Emit the notification only if the notification hasn't already been emitted.
    -- This is to avoid alert storms when ntopng is restarted. Indeeed,
    -- if there are 100 alerts triggered when ntopng is switched off, chances are the
    -- same 100 alerts will be triggered again as soon as ntopng is restarted, causing
    -- 100 trigger notifications to be emitted twice. This check is to prevent such behavior.
    if not is_trigger_notified(triggered) then

        debug_print("Sending notification for alert " .. entity_info.entity_val)

        addAlertPoolAndNetworkInfo(entity_info, triggered)

        recipients.dispatch_notification(triggered, current_script)
        mark_trigger_notified(triggered)

        pushSmartRecordingFilter(entity_info, ifid)

    else
        debug_print("Alert already notified for " .. entity_info.entity_val)
    end

    return (true)
end

-- ##############################################

-- ! @brief Release an alert of given type on the entity
-- ! @param entity_info data returned by one of the entity_info building functions
-- ! @param type_info data returned by one of the type_info building functions
-- ! @param when (optional) the time when the release event occurs
-- ! @param cur_alerts (optional) a table containing triggered alerts for the current entity
-- ! @note The actual release is performed asynchronously
-- ! @return true on success, false otherwise
function alerts_api.release(entity_info, type_info, when, cur_alerts)
    if (not areAlertsEnabled()) then
        return (false)
    end

    -- Apply defaults
    local granularity_sec = type_info.granularity and type_info.granularity.granularity_seconds or 0
    local granularity_id = type_info.granularity and type_info.granularity.granularity_id or 0 --[[ 0 is aperiodic ]]
    local subtype = type_info.subtype or ""

    if (cur_alerts and
        (not already_triggered(cur_alerts, type_info.alert_type.alert_key, granularity_sec, subtype, true))) then
        -- tprint("Alert not triggered @ "..granularity_sec.." ".. entity_info.entity_val .."@"..type_info.alert_type.i18n_title..":".. subtype .. "\n")
        return (true)
    end

    when = when or os.time()
    local alert_key_name = get_alert_triggered_key(type_info.alert_type.alert_key, subtype)
    local ifid = interface.getId()
    local params = {alert_key_name, granularity_id, when}
    local released = nil

    if (entity_info.alert_entity.entity_id == alert_consts.alertEntity("interface")) then
        if (interface.checkContext(entity_info.entity_val) == false) then
            --            alertErrorTraceback("Invalid interface context detected for entity id " ..
            --                                    entity_info.alert_entity.entity_id)
            --            tprint(entity_info)
            return (false)
        else
            released = interface.releaseTriggeredAlert(table.unpack(params))
        end

    elseif (entity_info.alert_entity.entity_id == alert_consts.alertEntity("network")) then
        if (network.checkContext(entity_info.entity_val) == false) then
            alertErrorTraceback("Invalid network context detected for entity id " .. entity_info.alert_entity.entity_id)
            tprint(entity_info)
            return (false)
        else
            released = network.releaseTriggeredAlert(table.unpack(params))
        end

    else
        released = interface.releaseExternalAlert(entity_info.alert_entity.entity_id, entity_info.entity_val,
            table.unpack(params))
    end

    if (released == nil) then
        -- tprint("Alert not released (not triggered?) @ "..granularity_sec.." ".. entity_info.entity_val .."@"..type_info.alert_type.i18n_title..":".. subtype .. "\n")
        return (false)
    else
        -- tprint("Alert released @ "..granularity_sec.." ".. entity_info.entity_val .."@"..type_info.alert_type.i18n_title..":".. subtype .. "\n") 
    end

    released.ifid = ifid
    released.action = "release"

    addAlertPoolAndNetworkInfo(entity_info, released)

    mark_release_notified(released)

    recipients.dispatch_notification(released, current_script)

    return (true)
end

-- ##############################################

function alerts_api.releaseAllAlerts()
    local alert_management = require "alert_management"
    local alerts = interface.getEngagedAlerts()
    alert_management.releaseEntityAlerts(nil, alerts)
end

-- ##############################################
-- type_info building functions
-- ##############################################

function alerts_api.tooManyDropsType(drops, drop_perc, threshold)
    return ({
        alert_id = alert_consts.alert_types.alert_too_many_drops,
        granularity = alert_consts.alerts_granularities.min,
        alert_type_params = {
            drops = drops,
            drop_perc = drop_perc,
            edge = threshold
        }
    })
end

-- ##############################################

-- TODO document
function alerts_api.checkThresholdAlert(params, alert_type, value, attacker, victim)
    local checks = require "checks"
    local script = params.check
    local threshold_config = params.check_config
    local alarmed = false
    local threshold = threshold_config.threshold or threshold_config.default_contacts

    -- Retrieve the function to be used for the threshold check.
    -- The function depends on the operator, i.e., "gt", or "lt".
    -- When there's no operator, the default "gt" function is taken from the available
    -- operation functions
    local op_fn = checks.operator_functions[threshold_config.operator] or checks.operator_functions.gt
    if op_fn and op_fn(value, threshold) then
        alarmed = true
    end

    -- tprint({params.cur_alerts, alert_type.meta, params.granularity, script.key --[[ the subtype--]], alarmed})

    local alert = alert_type.new(params.check.key, value, threshold_config.operator, threshold)

    alert:set_info(params)
    alert:set_subtype(script.key)

    if attacker ~= nil then
        alert:set_attacker(attacker)
    end

    if victim ~= nil then
        alert:set_victim(victim)
    end

    if (alarmed) then
        -- calls Alert:trigger
        alert:trigger(params.alert_entity, nil, params.cur_alerts)
    else
        -- calls Alert:release
        alert:release(params.alert_entity, nil, params.cur_alerts)
    end
end

-- #####################################

function alerts_api.handlerPeerBehaviour(params, stats, tot_anomalies, host_ip, threshold, behaviour_type, subtype)
    local anomaly = stats["anomaly"]
    local lower_bound = stats["lower_bound"]
    local upper_bound = stats["upper_bound"]
    local value = stats["value"]
    local prediction = stats["prediction"]

    local alert_unexpected_behaviour = behaviour_type.new(value, prediction, upper_bound, lower_bound)

    -- Setting score (TODO check the score value)
    if threshold and tot_anomalies and tot_anomalies > threshold then
        alert_unexpected_behaviour:set_score_error()
    else
        alert_unexpected_behaviour:set_score_warning()
    end

    alert_unexpected_behaviour:set_granularity(params.granularity)

    if subtype then
        alert_unexpected_behaviour:set_subtype(subtype)
    end

    if anomaly then
        alert_unexpected_behaviour:trigger(params.alert_entity)
    else
        alert_unexpected_behaviour:release(params.alert_entity)
    end
end

-- ##############################################

-- An alert check function which checks for anomalies.
-- The check key is the type of the anomaly to check.
-- The check must implement a anomaly_type_builder(anomaly_key) function
-- which returns a type_info for the given anomaly.
function alerts_api.anomaly_check_function(params)
    local anomal_key = params.check.key
    local type_info = params.check.anomaly_type_builder()

    type_info:set_score_error() -- TODO check the score value
    type_info:set_granularity(params.granularity)
    type_info:set_subtype(anomal_key)

    if params.entity_info.anomalies[anomal_key] then
        type_info:trigger(params.alert_entity, nil, params.cur_alerts)
    else
        type_info:release(params.alert_entity, nil, params.cur_alerts)
    end
end

-- ##############################################

function alerts_api.interface_delta_val(metric_name, granularity, curr_val, skip_first)
    return (delta_val(interface --[[ the interface Lua reg ]] , metric_name, granularity, curr_val, skip_first))
end

function alerts_api.network_delta_val(metric_name, granularity, curr_val, skip_first)
    return (delta_val(network --[[ the network Lua reg ]] , metric_name, granularity, curr_val, skip_first))
end

-- ##############################################

function alerts_api.application_bytes(info, application_name)
    local curr_val = 0

    if info["ndpi"] and info["ndpi"][application_name] then
        curr_val = info["ndpi"][application_name]["bytes.sent"] + info["ndpi"][application_name]["bytes.rcvd"]
    end

    return curr_val
end

-- ##############################################

function alerts_api.category_bytes(info, category_name)
    local curr_val = 0

    if info["ndpi_categories"] and info["ndpi_categories"][category_name] then
        curr_val = info["ndpi_categories"][category_name]["bytes.sent"] +
                       info["ndpi_categories"][category_name]["bytes.rcvd"]
    end

    return curr_val
end

-- ##############################################

function alerts_api.setCheck(check)
    current_script = check
end

-- ##############################################

return (alerts_api)
