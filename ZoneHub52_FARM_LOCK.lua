-- ZoneHub 5.2 SAFE - Fixed Farm Roster
-- Loads the original public script and applies small, checked patches in memory.
-- No changes to the GitHub repository or to egg odds.

local URL = "https://raw.githubusercontent.com/alanbanansport2000-hub/ZoneHub/main/ZoneHub52_SAFE.lua"
local ok, source = pcall(function()
    return game:HttpGet(URL)
end)
assert(ok and type(source) == "string" and #source > 20000,
    "ZoneHub: не удалось получить оригинальный ZoneHub52_SAFE.lua")

local function replaceExactlyOnce(label, original, updated)
    local first, last = source:find(original, 1, true)
    assert(first, "ZoneHub: исходник изменился, не найден блок " .. label)
    assert(not source:find(original, last + 1, true),
        "ZoneHub: неоднозначный блок " .. label)
    source = source:sub(1, first - 1) .. updated .. source:sub(last + 1)
end

-- 1. At the first farm start, remember the unique IDs of the CURRENT eligible pets.
-- Keep the same roster after stop/start until the user presses the update button.
replaceExactlyOnce("farm roster init", [[
        if not list or #list==0 then
            log("Авто-ID: "..tostring(err or "нет подходящих питомцев"),true) return
        end
]], [[
        if not list or #list==0 then
            log("Авто-ID: "..tostring(err or "нет подходящих питомцев"),true) return
        end
        if not Z25.autoPets.farmLockedIDs then
            local locked={}
            for _,pet in ipairs(list) do locked[pet.id]=true end
            Z25.autoPets.farmLockedIDs=locked
            Z25.autoPets.farmLockedCount=#list
            log("🔒 Зафиксированы "..#list.." питомцев. Новые игнорируются")
        end
        local available=0
        for _,pet in ipairs(list) do
            if Z25.autoPets.farmLockedIDs[pet.id] then available+=1 end
        end
        if available==0 then
            log("🔒 Нет оставшихся питомцев из фиксированного списка. Обнови список во вкладке Фарм",true)
            return
        end
        Z25.autoPets.ready=available
        if Z25.farmLockLabel then
            Z25.farmLockLabel.Text="В списке: "..Z25.autoPets.farmLockedCount.." • доступно: "..available.." • новые игнорируются"
        end
]])

-- 2. The dynamic worker may refresh pet levels/profiles, but NEVER admits new IDs.
replaceExactlyOnce("farm refresh filter", [[
            if newPool then
                pool=newPool
]], [[
            if newPool then
                local locked=Z25.autoPets.farmLockedIDs
                if locked then
                    local filtered={}
                    for _,pet in ipairs(newPool) do
                        if locked[pet.id] then filtered[#filtered+1]=pet end
                    end
                    newPool=filtered
                end
                Z25.autoPets.ready=#newPool
                if autoPetsLabel and locked then
                    autoPetsLabel.Text="🔒 В фарме: "..#newPool.." / "..(Z25.autoPets.farmLockedCount or 0).." • новые ID исключены"
                end
                pool=newPool
]])

-- 3. A freshly bought pet no longer changes the farm-roster signature/cursor.
replaceExactlyOnce("stable farm signature", [[
    for _,v in ipairs(result) do ids[#ids+1]=tostring(v.id) end
]], [[
    for _,v in ipairs(result) do
        if not Z25.autoPets.farmLockedIDs or Z25.autoPets.farmLockedIDs[v.id] then
            ids[#ids+1]=tostring(v.id)
        end
    end
]])

-- 4. Protect farm pets from the optional bulk upgrade operation.
replaceExactlyOnce("protect locked pets", [[
    local id=tonumber(p.id)
    for _,farmId in ipairs(cfg.ids) do if id==farmId then return true end end
]], [[
    local id=tonumber(p.id)
    if Z25.autoPets.farmLockedIDs and Z25.autoPets.farmLockedIDs[id] then return true end
    for _,farmId in ipairs(cfg.ids) do if id==farmId then return true end end
]])

-- 5. Add a control to the existing Farm tab. It only changes the list when stopped.
replaceExactlyOnce("farm UI update button", [[
farmManual.PlaceholderText="12562926, 45267711"
end
]], [[
farmManual.PlaceholderText="12562926, 45267711"
local farmLockCard=card(farm,106,C.green)
label(farmLockCard,"🔒 Фиксированный состав фарма",8,24,13,C.white,true)
Z25.farmLockLabel=label(farmLockCard,
    "Список создаётся при первом запуске фарма",31,18,11,C.dim)
button(farmLockCard,"↻ ОБНОВИТЬ СПИСОК ПЕТОВ",57,function()
    if farming then
        log("Сначала останови фарм, потом обнови список",true)
        return
    end
    Z25.autoPets.farmLockedIDs=nil
    Z25.autoPets.farmLockedCount=0
    Z25.farmLockLabel.Text="Сброшен • новый список создастся при запуске"
    log("🔄 Список сброшен. При следующем запуске будут взяты актуальные питомцы")
end,C.blue)
end
]])

local compile = loadstring or load
assert(type(compile)=="function", "ZoneHub: Delta не предоставила loadstring")
local chunk, problem = compile(source)
assert(chunk, "ZoneHub: ошибка компиляции обновлённого кода: " .. tostring(problem))
return chunk()
