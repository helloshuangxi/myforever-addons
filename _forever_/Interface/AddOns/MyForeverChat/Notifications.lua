local _, NS = ...

local DEFAULT_SECONDS = 20
local MAX_VISIBLE = 4
local MAX_QUEUED = 12
local Notifications = {}
Notifications.__index = Notifications

local function visibleLimit(manager)
    local limit = manager.maxVisible()
    if type(limit) ~= "number" or limit ~= limit then return MAX_VISIBLE end
    return math.floor(math.max(1, math.min(MAX_VISIBLE, limit)))
end

local function priority(manager, item)
    local value = manager.priority and manager.priority(item.conversationId, item.message) or 0
    if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then return 0 end
    return value
end

local function before(first, second)
    if first.priority ~= second.priority then return first.priority > second.priority end
    return first.order < second.order
end

local function removeMatching(manager, matches)
    local changed = false
    for index = #manager.items, 1, -1 do
        local item = manager.items[index]
        if matches(item) then
            table.remove(manager.items, index)
            manager.timers[item] = nil
            changed = true
        end
    end
    return changed
end

local function sameItems(first, second)
    if #first ~= #second then return false end
    for index, item in ipairs(first) do if item ~= second[index] then return false end end
    return true
end

local function itemIndex(manager, item)
    for index, candidate in ipairs(manager.items) do if item == candidate then return index end end
end

local function clampOffset(manager, offset, limit)
    return math.max(0, math.min(offset, math.max(0, #manager.items - limit)))
end

local function startTimer(manager, item)
    if manager.timers[item] then return end
    local seconds = manager.duration and manager.duration(item.conversationId, item.message) or DEFAULT_SECONDS
    if type(seconds) ~= "number" or seconds ~= seconds or seconds <= 0 or seconds == math.huge then
        seconds = DEFAULT_SECONDS
    end
    local token = {}
    manager.timers[item] = token
    -- Lifetime begins on first display. Paging or priority changes never reset
    -- it, and a previously seen item still expires while it is offscreen.
    manager.after(seconds, function()
        if manager.timers[item] == token then manager:Dismiss(item) end
    end)
end

function Notifications:GetPageInfo()
    local total = #self.items
    return {
        offset = self.offset,
        total = total,
        first = total > 0 and self.offset + 1 or 0,
        last = self.offset + #self.visible,
        hasPrevious = self.offset > 0,
        hasNext = self.offset + #self.visible < total,
    }
end

local function refresh(manager, changed, requestedOffset)
    if removeMatching(manager, function(item)
        return not manager.canShow(item.conversationId, item.message)
    end) then changed = true end
    for _, item in ipairs(manager.items) do
        local value = priority(manager, item)
        if item.priority ~= value then item.priority = value; changed = true end
    end
    table.sort(manager.items, before)

    local limit = visibleLimit(manager)
    local offset = requestedOffset or manager.offset
    if requestedOffset == nil and manager.offset > 0 then
        -- Keep the first surviving viewed item in place when arrivals, removals
        -- or priority updates alter the items before the reader's current view.
        for _, item in ipairs(manager.visible) do
            local index = itemIndex(manager, item)
            if index then offset = index - 1; break end
        end
    end
    offset = clampOffset(manager, offset, limit)
    local anchor = offset > 0 and manager.items[offset + 1]
    while #manager.items > limit + MAX_QUEUED do
        -- Prefer the oldest lowest-priority offscreen item. Never evict a
        -- currently displayed item merely because the backlog reaches its cap.
        local victim
        for index, item in ipairs(manager.items) do
            if index <= offset or index > offset + limit then
                local old = victim and manager.items[victim]
                if not old or item.priority < old.priority
                    or (item.priority == old.priority and item.order < old.order) then victim = index end
            end
        end
        local item = table.remove(manager.items, victim)
        manager.timers[item] = nil
        if anchor then offset = itemIndex(manager, anchor) - 1 end
        offset = clampOffset(manager, offset, limit)
        changed = true
    end

    local visible, queued = {}, {}
    for index, item in ipairs(manager.items) do
        local destination = index > offset and index <= offset + limit and visible or queued
        destination[#destination + 1] = item
    end
    if offset ~= manager.offset or not sameItems(visible, manager.visible) or not sameItems(queued, manager.queued) then
        changed = true
    end
    manager.offset, manager.visible, manager.queued = offset, visible, queued
    for _, item in ipairs(visible) do startTimer(manager, item) end
    if changed and manager.onChange then manager.onChange(visible, queued, manager:GetPageInfo()) end
    return changed
end

function Notifications:Push(conversationId, message)
    if type(conversationId) ~= "string" or conversationId == "" or type(message) ~= "table" then return false end
    if self.seen[message] then return false end
    self.seen[message] = true
    if not self.canShow(conversationId, message) then return false end
    self.nextOrder = self.nextOrder + 1
    self.items[#self.items + 1] = { conversationId = conversationId, message = message, order = self.nextOrder }
    return refresh(self, true)
end

function Notifications:Dismiss(item)
    if not removeMatching(self, function(candidate) return candidate == item end) then return false end
    return refresh(self, true)
end

function Notifications:DismissConversation(conversationId)
    if not removeMatching(self, function(item) return item.conversationId == conversationId end) then return false end
    return refresh(self, true)
end

function Notifications:DismissAll()
    if not removeMatching(self, function() return true end) then return false end
    return refresh(self, true, 0)
end

function Notifications:Scroll(delta)
    if type(delta) ~= "number" or delta ~= delta or delta == 0 then return false end
    local direction = delta > 0 and 1 or -1
    return refresh(self, false, self.offset + direction * visibleLimit(self))
end

function Notifications:Refresh()
    return refresh(self, false)
end

function NS.CreateNotifications(options)
    return setmetatable({
        canShow = options.canShow,
        maxVisible = options.maxVisible,
        after = options.after,
        onChange = options.onChange,
        priority = options.priority,
        duration = options.duration,
        nextOrder = 0,
        offset = 0,
        items = {},
        visible = {},
        queued = {},
        timers = {},
        seen = setmetatable({}, { __mode = "k" }),
    }, Notifications)
end
