-- Helper functions
local function matchCriteria(fn, criteria)
    local isArray = false
    local arrayMatch = false
    for k, v in pairs(criteria) do
        if math.type(k) ~= nil then
            isArray = true
            if fn.id == v then
                arrayMatch = true
                break
            end
        else
            if k == 'id' then
                if fn.id ~= v then
                    return false
                end
            end
            if k == 'type' then
                if fn.type:match('^' .. v .. '$') == nil then
                    return false
                end
            end
            if fn.meta[k] == nil then
                return false
            end
            if fn.meta[k] ~= v then
                return false
            end
        end
    end
    if isArray then
        return arrayMatch
    end
    return true
end

local function findDevice(criteria)
    local devices, err = lynx.getDevices()
    if err ~= nil then
        log.d("could not fetch devices: %s", err.message)
        return nil
    end
    if math.type(criteria) ~= nil then
        for _, dev in ipairs(devices) do
            if dev.id == criteria then
                return dev
            end
        end
    elseif type(criteria) == 'table' then
        for _, dev in ipairs(devices) do
            if matchCriteria(dev, criteria) then
                return dev
            end
        end
    end
    return nil
end

local function findFunction(criteria)
    if math.type(criteria) ~= nil then
        for _, fn in ipairs(functions) do
            if fn.id == criteria then
                return fn
            end
        end
    elseif type(criteria) == 'table' then
        for _, fn in ipairs(functions) do
            if matchCriteria(fn, criteria) then
                return fn
            end
        end
    end
    return nil
end

local function findFunctions(criteria)
    local res = {}
    if type(criteria) == 'table' then
        for _, fn in ipairs(functions) do
            if matchCriteria(fn, criteria) then
                table.insert(res, fn)
            end
        end
    end
    return res
end

-- Real logic

function onAnnounce(topic, payload, retained)
    log.d("looking for device and functions")
    local data = json:decode(payload)
    local dev = findDevice({ type = 'shelly', mac = data.mac })
    if dev == nil then
        dev = {
            type = "shelly",
            meta = {
                name = "Shelly - " .. data.id,
                mac = data.mac,
                ["shelly.id"] = data.id
            }
        }
        local err
        dev, err = lynx.createDevice(dev)
        if err ~= nil then
            log.d('created device error: %s', err.message)
            return
        end
    end

    local existingFunctions = findFunctions({ device_id = tostring(dev.id) })
    local newFunctions = {}

    if data.model == "SHPLG-S" then
        -- The device is a Plug-S
        if #existingFunctions == 4 then
            return
        end

        newFunctions = {
            {
                type = "temperature",
                meta = {
                    device_id = tostring(dev.id),
                    name = data.id .. " - Temperature",
                    format = "%.2f°C",
                    topic_read = "obj/shelly/" .. dev.meta.mac .. "/temperature",
                    ["shelly.type"] = "temperature",
                    ["shelly.id"] = dev.meta["shelly.id"]
                }
            },
            {
                type = "switch",
                meta = {
                    device_id = tostring(dev.id),
                    name = data.id .. " - Switch",
                    topic_read = "obj/shelly/" .. dev.meta.mac .. "/0/switch",
                    topic_write = "set/obj/shelly/" .. dev.meta.mac .. "/0/switch",
                    state_on = "1",
                    state_off = "0",
                    ["shelly.type"] = "switch",
                    ["shelly.id"] = dev.meta["shelly.id"]
                }
            }, {
                type = "energy",
                meta = {
                    device_id = tostring(dev.id),
                    name = data.id .. " - Energy",
                    topic_read = "obj/shelly/" .. dev.meta.mac .. "/0/energy",
                    ["shelly.type"] = "energy",
                    ["shelly.id"] = dev.meta["shelly.id"]
                }
            }, {
                type = "power",
                meta = {
                    device_id = tostring(dev.id),
                    name = data.id .. " - Power",
                    topic_read = "obj/shelly/" .. dev.meta.mac .. "/0/power",
                    ["shelly.type"] = "power",
                    ["shelly.id"] = dev.meta["shelly.id"]
                }
            }
        }
    elseif data.model == "SHMOS-01" then
        -- The device is a Motion
        if #existingFunctions == 4 then
            return
        end
        newFunctions = {
            {
                type = "motion",
                meta = {
                    device_id = tostring(dev.id),
                    name = data.id .. " - Movement",
                    topic_read = "obj/shelly/" .. dev.meta.mac .. "/motion",
                    state_movement = "1",
                    state_nomovement = "0",
                    ["shelly.type"] = "motion",
                    ["shelly.id"] = dev.meta["shelly.id"]
                }
            }, {
                type = "vibration",
                meta = {
                    device_id = tostring(dev.id),
                    name = data.id .. " - Vibration",
                    topic_read = "obj/shelly/" .. dev.meta.mac .. "/vibration",
                    state_vibration = "1",
                    state_novibration = "0",
                    ["shelly.type"] = "vibration",
                    ["shelly.id"] = dev.meta["shelly.id"]
                }
            }, {
                type = "light",
                meta = {
                    device_id = tostring(dev.id),
                    name = data.id .. " - Light",
                    topic_read = "obj/shelly/" .. dev.meta.mac .. "/light",
                    format = "%.0fLux",
                    ["shelly.type"] = "lux",
                    ["shelly.id"] = dev.meta["shelly.id"]
                }
            }, {
                type = "battery",
                meta = {
                    device_id = tostring(dev.id),
                    name = data.id .. " - Battery",
                    topic_read = "obj/shelly/" .. dev.meta.mac .. "/battery",
                    format = "%.0f%%",
                    ["shelly.type"] = "bat",
                    ["shelly.id"] = dev.meta["shelly.id"]
                }
            }
        }
    end

    for _, newFun in ipairs(newFunctions) do
        local found = false
        for _, fun in ipairs(existingFunctions) do
            if fun.meta.shelly_type == newFun.shelly_type then
                found = true
                break
            end
        end
        if not found then
            lynx.createFunction(newFun)
        end
    end
end

function onShellyMessage(topic, payload, retained)
    if string.find(topic, "announce") then
        return
    end

    local topicParts = topic:split("/")
    local id = topicParts[2]
    if topicParts[3] == "status" then
        local data = json:decode(payload)
        local ts = edge:time()

        if data.motion ~= nil then
            local fn = findFunction({ ["shelly.type"] = "motion", ["shelly.id"] = id })
            if fn ~= nil then
                local val = 0
                if data.motion then
                    val = 1
                end
                local payloadData = { timestamp = ts, value = val }
                mq:pub(fn.meta.topic_read, json:encode(payloadData), false, 0)
            end
        end
        if data.vibration ~= nil then
            local fn = findFunction({ ["shelly.type"] = "vibration", ["shelly.id"] = id })
            if fn ~= nil then
                local val = 0
                if data.motion then
                    val = 1
                end
                local payloadData = { timestamp = ts, value = val }
                mq:pub(fn.meta.topic_read, json:encode(payloadData), false, 0)
            end
        end
        if data.lux ~= nil then
            local fn = findFunction({ ["shelly.type"] = "lux", ["shelly.id"] = id })
            if fn ~= nil then
                local payloadData = { timestamp = ts, value = data.lux }
                mq:pub(fn.meta.topic_read, json:encode(payloadData), false, 0)
            end
        end
        if data.bat ~= nil then
            local fn = findFunction({ ["shelly.type"] = "bat", ["shelly.id"] = id })
            if fn ~= nil then
                local payloadData = { timestamp = ts, value = data.bat }
                mq:pub(fn.meta.topic_read, json:encode(payloadData), false, 0)
            end
        end
    else
        local data
        if payload == "on" then
            data = 1
        elseif payload == "off" then
            data = 0
        else
            data = tonumber(payload)
        end

        local type
        if topicParts[3] == "relay" and #topicParts == 4 then
            type = "switch"
        else
            type = topicParts[#topicParts]
        end
        local fn = findFunction({ ["shelly.type"] = type, ["shelly.id"] = id })
        if fn ~= nil then
            local payloadData = { timestamp = edge:time(), value = data }
            mq:pub(fn.meta.topic_read, json:encode(payloadData), false, 0)
        end
    end
end

function onLynxMessage(topic, payload, retained)
    if retained then
        return
    end
    local fn = findFunction({ topic_write = topic })
    if fn == nil then
        return
    end

    local data = json:decode(payload)
    local topic = "shellies/" .. fn.meta["shelly.id"] .. "/relay/0/command"
    local val = "off"
    if data.value == 1 then val = "on" end
    mq:pub(topic, val, false, 0)
end

-- State handling

function onCreate()

end

function onDestroy()

end

function onStart()
    mq:bind("shellies/+/announce", onAnnounce)
    mq:bind("shellies/+/#", onShellyMessage)
    mq:sub("shellies/#", 0)

    mq:bind("set/obj/shelly/#", onLynxMessage)
    mq:sub("set/obj/shelly/#", 0)
end