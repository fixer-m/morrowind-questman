-- questman: resolve quest givers from dialogue resultScripts (pure, engine-free -> unit-tested).
-- A quest's giver ~= the NPC (filterActorId) on the dialogue line whose resultScript sets the
-- quest's LOWEST journal stage. Validated at ~94% coverage on a full Morrowind+Tribunal+Bloodmoon load.

local M = {}

-- Parse `Journal "<id>" <stage>` commands out of a resultScript (quoted ids may contain spaces;
-- also the unquoted single-token form). Returns { {id=lower, stage=n}, ... }.
function M.parseJournal(s)
    local out = {}
    if type(s) ~= 'string' or s == '' then return out end
    for id, stage in s:gmatch('[Jj][Oo][Uu][Rr][Nn][Aa][Ll][%s,]+"([^"]+)"[%s,]*(%-?%d+)') do
        out[#out + 1] = { id = id:lower(), stage = tonumber(stage) }
    end
    for id, stage in s:gmatch('[Jj][Oo][Uu][Rr][Nn][Aa][Ll][%s,]+([%a][%w_]*)[%s,]+(%-?%d+)') do
        out[#out + 1] = { id = id:lower(), stage = tonumber(stage) }
    end
    return out
end

-- Infos processed between frame-budget polls while slicing (see the `shouldYield` param). Polling every info
-- would swamp the scan with clock reads; polling too rarely overshoots the frame budget.
local YIELD_INTERVAL = 128

-- Build the giver map from dialogue record stores.
-- `stores` = array of { records = iterable of { infos = iterable of
--    { resultScript, filterActorId, filterActorFaction } } }.
-- Returns { [questIdLower] = { actor, faction, stage } }, keeping the LOWEST-stage setter.
-- `shouldYield` (optional): a predicate polled during the scan; when it returns true, resolve calls
-- coroutine.yield() so a driver can spread the (heavy) scan across frames on a time budget. Omit it (tests /
-- synchronous callers) to run the whole scan in one uninterrupted pass -- coroutine.yield is then never reached.
-- Only pass it when running resolve inside a coroutine.
function M.resolve(stores, shouldYield)
    local map = {}
    local sincePoll = 0
    for _, store in ipairs(stores or {}) do
        if store and store.records then
            for _, rec in pairs(store.records) do
                if rec.infos then
                    for _, info in pairs(rec.infos) do
                        local rs = info.resultScript
                        if type(rs) == 'string' and rs:find('[Jj]ournal') then
                            for _, cmd in ipairs(M.parseJournal(rs)) do
                                local cur = map[cmd.id]
                                if not cur or (cmd.stage or 0) < (cur.stage or 0) then
                                    map[cmd.id] = {
                                        actor = info.filterActorId,
                                        faction = info.filterActorFaction,
                                        stage = cmd.stage,
                                    }
                                end
                            end
                        end
                        if shouldYield then
                            sincePoll = sincePoll + 1
                            if sincePoll >= YIELD_INTERVAL then
                                sincePoll = 0
                                if shouldYield() then coroutine.yield() end
                            end
                        end
                    end
                end
            end
        end
    end
    return map
end

-- Resolve a quest's giver NPC id from a derived map (+ optional curated overrides).
-- Returns the npc id string, or nil when unresolved (faction-only / script-started).
function M.giverId(map, questId, overrides)
    if type(questId) ~= 'string' then return nil end
    local key = questId:lower()
    if overrides and overrides[key] then return overrides[key] end
    local e = map and map[key]
    if e and e.actor and e.actor ~= '' then return e.actor end
    return nil
end

-- The OPENER across several ids sharing a quest name: the map entry with the LOWEST journal stage (the actor
-- who set the quest's first entry). Ids are compared in the order given, so ties resolve deterministically
-- when the caller passes a sorted list. Returns the npc id, or nil when none of the ids has a derived giver.
function M.giverForIds(map, ids)
    if type(map) ~= 'table' or type(ids) ~= 'table' then return nil end
    local best
    for _, id in ipairs(ids) do
        local e = map[tostring(id):lower()]
        if e and e.actor and e.actor ~= '' and (not best or (e.stage or 0) < (best.stage or 0)) then
            best = e
        end
    end
    return best and best.actor or nil
end

return M
