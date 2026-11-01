-- ZoneHub 2.5 | Pet Simulator 2018 | Three egg worlds + polished mobile UI
-- No diagnostic probes, hooks, external libraries or client-side pet PivotTo.
-- Original PS1 shop protocol, no automatic purchases on load.
-- Winter Wonderland eggs are seasonal; server availability is not guaranteed.
-- Uses observed numeric Mine packets. Server behavior can change; client HP is only a proxy.
-- Keeps the v1.7 on-device profile format and filename for all four pets.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")

-- Stop prior ZoneHub workers BEFORE destroying the old GUI.
if type(getgenv)=="function" then
    local env=getgenv()
    if type(env.ZoneHubShutdown)=="function" then pcall(env.ZoneHubShutdown) end
end
local old = pg:FindFirstChild("ZoneHub_PetSim")
if old then old:Destroy() end

local alive, farming, session = true, false, 0
local converting, convertEpoch = false, 0
local convertMessage = "Готово к проверке инвентаря"
local convertCompleted = 0
local protectFarmPets = true
local eggRunning, eggEpoch, eggTier = false, 0, 1
local eggWorld="World1"
local Z25={}
-- Farm area: default rectangle, or circle around a saved teleport point.
Z25.area=nil
Z25.point=nil
Z25.areaLabel=nil
Z25.radius=125
function Z25.areaDescription()
    if not Z25.area then return "Исходная зона (прямоугольник)" end
    return "Сохранённая точка "..Z25.area.." • радиус "..tostring(Z25.radius)
end
local EGG_WORLDS={
    World1={title="Первый мир",sub="Обычные монеты",prefix="Tier ",min=1,max=12,accent="blue",prices={"275","2 500","12 500","46 000","175 000","450 000","1,5 млн","3,75 млн","8 млн","50 млн","350 млн","5 млрд"}},
    Moon={title="Moon Egg",sub="Лунные монеты",prefix="Tier ",min=13,max=18,accent="purple",prices={"65 000","475 000","2,375 млн","8 млн","26,5 млн","165 млн"}},
    Winter={title="Winter Wonderland",sub="Снежные монеты • сезонный мир",prefix="Christmas Tier ",min=1,max=4,accent="cyan",prices={"165","90 000","15 млн","8 млрд"}},
}
local function eggKey(world,tier)
    return EGG_WORLDS[world].prefix..tostring(tier)
end
local eggOpened, eggAttempts, eggInventory, eggCapacity = 0, 0, nil, nil
local eggMessage = "Выбери мир и яйцо. Покупка не запущена"
Z25.inventory={count=nil,capacity=nil,normal=0,gold=0,rainbow=0,dark=0,equipped=0,updated="не проверен",lines=""}
Z25.inventoryLabel, Z25.inventoryDetails, Z25.eggLabel = nil,nil,nil
function Z25.trueFlag(value)
    return value~=nil and value~=false and value~=0
end
function Z25.classify(p)
    if Z25.trueFlag(p.dm) then return "dark" end
    if Z25.trueFlag(p.r) then return "rainbow" end
    if Z25.trueFlag(p.g) then return "gold" end
    return "normal"
end
function Z25.updateInventory(save, context)
    if type(save)~="table" or type(save.Pets)~="table" then return end
    local snap={count=0,capacity=save.PetSlots,normal=0,gold=0,rainbow=0,dark=0,equipped=0,updated=os.date("%H:%M:%S"),lines=""}
    local names={}
    for _,p in pairs(save.Pets) do
        if type(p)=="table" then
            snap.count+=1
            local stage=Z25.classify(p)
            snap[stage]+=1
            if Z25.trueFlag(p.e) then snap.equipped+=1 end
            local name=tostring(p.n or "?")
            names[name]=(names[name] or 0)+1
        end
    end
    local list={}
    for name,n in pairs(names) do list[#list+1]={name=name,n=n} end
    table.sort(list,function(a,b) return a.n>b.n or (a.n==b.n and a.name<b.name) end)
    local fragments={}
    for i=1,math.min(5,#list) do fragments[#fragments+1]=list[i].name.." ×"..list[i].n end
    snap.lines=table.concat(fragments,"  •  ")
    Z25.inventory=snap
    if Z25.inventoryLabel then
        Z25.inventoryLabel.Text=string.format("Сервер: %d/%s • экипировано: %d\nОбычных: %d | золотых: %d | радужных: %d | Dark: %d",snap.count,tostring(snap.capacity or "?"),snap.equipped,snap.normal,snap.gold,snap.rainbow,snap.dark)
    end
    if Z25.inventoryDetails then Z25.inventoryDetails.Text="Обновлено "..snap.updated.." ("..(context or "чтение")..")\n"..snap.lines end
    if Z25.eggLabel then Z25.eggLabel.Text="Сервер: "..snap.count.." / "..tostring(snap.capacity or "?").." • "..snap.updated end
end
local connections, reserved, learned = {}, {}, {}
local logLines = {}
local cfg = {
    ids={15883528,25214651,92565120,95608754},
    minX=-3218.733,maxX=-2832.849,minZ=-1747.956,maxZ=-1468.381,
    groundY=144.810,interval=.42,mode="Near"
}
local stats = {mine=0, move=0, clientErrors=0, damage=0, gone=0, noProgress=0, workers=0}
local PROFILE_FILE = "ZoneHub_profiles_v17.json" -- intentionally unchanged
local storageStatus = "Проверка сохранения..."
local function timestamp() return os.date("%H:%M:%S") end
local statusLabel
local function log(msg, bad)
    table.insert(logLines, 1, (bad and "! " or "• ")..timestamp().." "..tostring(msg))
    while #logLines>5 do table.remove(logLines) end
    if bad then stats.clientErrors+=1 end
    if statusLabel then statusLabel.Text=table.concat(logLines,"\n") end
end
local function partOf(o)
    if not o then return nil end
    if o:IsA("BasePart") then return o end
    if o:IsA("Model") then return o.PrimaryPart or o:FindFirstChildWhichIsA("BasePart",true) end
    return o:FindFirstChildWhichIsA("BasePart",true)
end
local function root()
    return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
end
local function nodes()
    local things=workspace:FindFirstChild("__THINGS")
    local coins=things and things:FindFirstChild("Coins")
    local remotes=workspace:FindFirstChild("__REMOTES")
    local gameRemotes=remotes and remotes:FindFirstChild("Game")
    local mine=gameRemotes and gameRemotes:FindFirstChild("Coins")
    local pets=gameRemotes and gameRemotes:FindFirstChild("Pets")
    if mine and not mine:IsA("RemoteEvent") then mine=nil end
    if pets and not pets:IsA("RemoteEvent") then pets=nil end
    return coins,mine,pets
end
local function inside(p)
    if Z25.area then
        local point=Z25.point and Z25.point(Z25.area)
        if not point then return false end
        -- Vertical gate excludes floors from other loaded worlds at the same X/Z.
        if math.abs(p.Y-point.y)>65 then return false end
        local dx,dz=p.X-point.x,p.Z-point.z
        return dx*dx+dz*dz<=Z25.radius*Z25.radius
    end
    return p.X>=cfg.minX and p.X<=cfg.maxX and p.Z>=cfg.minZ and p.Z<=cfg.maxZ
end
local function health(o)
    if not o then return nil end
    for _,name in ipairs({"Health","HP","Hp","health"}) do
        local v=o:FindFirstChild(name,true)
        if v and (v:IsA("NumberValue") or v:IsA("IntValue")) then return v.Value end
        local attr=o:GetAttribute(name)
        if type(attr)=="number" then return attr end
    end
    return nil
end
local function scan()
    local folder=nodes()
    local result,total={},0
    if not folder then return result,0 end
    for _,coin in ipairs(folder:GetChildren()) do
        total+=1
        local part=partOf(coin)
        if part and inside(part.Position) then
            local hp=health(coin)
            if type(hp)=="number" and hp>0 then
                result[#result+1]={object=coin,pos=part.Position,hp=hp}
            end
        end
    end
    return result,total
end
local function orderCoins(items)
    local r=root()
    local reference=Z25.area and Z25.point and Z25.point(Z25.area)
    local o=reference and Vector3.new(reference.x,reference.y,reference.z) or
        (r and r.Position or Vector3.new((cfg.minX+cfg.maxX)/2,cfg.groundY,(cfg.minZ+cfg.maxZ)/2))
    table.sort(items,function(a,b)
        if cfg.mode=="LowHP" and a.hp~=b.hp then return a.hp<b.hp end
        if cfg.mode=="HighHP" and a.hp~=b.hp then return a.hp>b.hp end
        return (a.pos-o).Magnitude<(b.pos-o).Magnitude
    end)
end
local function validCoin(o)
    if not o or not o.Parent then return false end
    local part=partOf(o)
    local hp=health(o)
    return part~=nil and inside(part.Position) and type(hp)=="number" and hp>0
end
local function availablePets()
    local result={}
    for _,id in ipairs(cfg.ids) do
        local p=learned[id]
        if p and p.movement and type(p.movement.speed)=="number" and type(p.samples)=="table" and #p.samples>0 then
            result[#result+1]=id
        end
    end
    return result
end
local function profileCount() return #availablePets() end

-- Same strict schema as v1.7; no fabricated Mine samples for pet 92565120.
local function loadProfiles(raw)
    if type(raw)~="string" or #raw>160000 then return false,"Неверный размер JSON" end
    local ok,obj=pcall(function() return HttpService:JSONDecode(raw) end)
    if not ok or type(obj)~="table" or obj.schema~=1 or type(obj.profiles)~="table" then
        return false,"Формат профиля не распознан"
    end
    local allowed={}
    for _,id in ipairs(cfg.ids) do allowed[id]=true end
    local count=0
    for _,p in ipairs(obj.profiles) do
        if type(p)=="table" and allowed[p.id] and type(p.samples)=="table" and type(p.frame)=="table" and #p.frame==12
            and type(p.speed)=="number" then
            local comps,samples={},{}
            for j=1,12 do
                if type(p.frame[j])~="number" then comps=nil break end
                comps[j]=p.frame[j]
            end
            for j=1,math.min(30,#p.samples) do
                if type(p.samples[j])=="number" then samples[#samples+1]=p.samples[j] end
            end
            if comps and #samples>0 then
                local okFrame,frame=pcall(function() return CFrame.new(table.unpack(comps)) end)
                if okFrame then
                    learned[p.id]={samples=samples,movement={frame=frame,speed=p.speed}}
                    count+=1
                end
            end
        end
    end
    return count>0, count>0 and count or "Не найдено корректных профилей"
end
local function toJson()
    local payload={schema=1,profiles={}}
    for _,id in ipairs(cfg.ids) do
        local p=learned[id]
        if p and p.movement and typeof(p.movement.frame)=="CFrame" and #p.samples>0 then
            local item={id=id,samples={},frame={p.movement.frame:GetComponents()},speed=p.movement.speed,sources={}}
            for j=1,math.min(#p.samples,30) do
                if type(p.samples[j])=="number" then item.samples[#item.samples+1]=p.samples[j] end
            end
            payload.profiles[#payload.profiles+1]=item
        end
    end
    return HttpService:JSONEncode(payload)
end
local function saveProfiles()
    -- A missing fourth profile must never overwrite a valid saved 4/4 file.
    if profileCount()<4 then return false,"Сохранение заблокировано: найдено меньше 4/4 профилей" end
    if type(writefile)~="function" then return false,"Запись файлов недоступна" end
    local ok,err=pcall(writefile,PROFILE_FILE,toJson())
    if ok then return true,"Сохранено "..profileCount().."/4 профилей" end
    return false,"Ошибка сохранения: "..tostring(err):sub(1,80)
end
-- Three profiles come from the supplied successful manual captures.
local known={
    {id=25214651,speed=3.5815804004669189,frame=CFrame.new(-3031,141.9644012,-1597),samples={145.05895256996155,175907.17931485176,176728.10179138184,176806.94916629791,176403.91777682304,176601.13730049133,176758.326618433,176452.94467020035}},
    {id=95608754,speed=4.7751576900482178,frame=CFrame.new(-3033,141.9645081,-1566),samples={122.49581408500671,168272.95349677405,168949.72115047774,168528.27377120656}},
    {id=15883528,speed=4.7751576900482178,frame=CFrame.new(-3051,141.9645081,-1533),samples={140.39686107635498,189985.11974716187,190698.23972892761,190765.38130712509,190999.33968448639}},
}
for _,p in ipairs(known) do
    learned[p.id]={samples=p.samples,movement={frame=p.frame,speed=p.speed}}
end
-- Load saved file; do not overwrite it if only 3 fallback profiles are available.
if type(readfile)=="function" then
    local readOk,raw=pcall(readfile,PROFILE_FILE)
    if readOk then
        local ok,n=loadProfiles(raw)
        storageStatus=ok and ("Загружено сохранение ("..n.." проф.)") or ("Сохранение повреждено: "..tostring(n))
    else storageStatus="Файл сохранения не найден" end
else storageStatus="Чтение файлов недоступно" end
-- Optional current-session recovery from v1.7, without requiring diagnostic controls.
if type(getgenv)=="function" then
    local env=getgenv()
    if type(env.ZoneHubLearnedProfiles)=="table" then
        for _,id in ipairs(cfg.ids) do
            local p=env.ZoneHubLearnedProfiles[id]
            if p and type(p.samples)=="table" and #p.samples>0 and p.movement
                and typeof(p.movement.frame)=="CFrame" and type(p.movement.speed)=="number" then
                learned[id]=p
            end
        end
    end
    env.ZoneHubLearnedProfiles=learned -- preserve profiles for a reload in this session
end

-- Egg purchase and capacity: original Pet Simulator 1 protocol, distinct from newer PSX/PS99.
-- Known community client calls:
--   workspace.__REMOTES.Game.Shop:InvokeServer("Buy", "Eggs", "Tier 12")
--   workspace.__REMOTES.Core["Get Other Stats"]:InvokeServer()[player.Name].Save
-- These are tested defensively here; no buy commands are issued on script load.
local eggStatusLabel, eggSelectedLabel, eggCountLabel
local function stopEggs(reason)
    eggRunning=false
    eggEpoch+=1
    if reason then eggMessage=reason end
end
local function eggRemotes()
    local r=workspace:FindFirstChild("__REMOTES")
    local core=r and r:FindFirstChild("Core")
    local gr=r and r:FindFirstChild("Game")
    local statsRemote=core and core:FindFirstChild("Get Other Stats")
    local shopRemote=gr and gr:FindFirstChild("Shop")
    if not statsRemote or not statsRemote:IsA("RemoteFunction") then statsRemote=nil end
    if not shopRemote or not shopRemote:IsA("RemoteFunction") then shopRemote=nil end
    return statsRemote,shopRemote
end
local function getEggInventory()
    local statsRemote=eggRemotes()
    if not statsRemote then return nil,nil,"Не найден Core / Get Other Stats" end
    local ok,data=pcall(function() return statsRemote:InvokeServer() end)
    if not ok then return nil,nil,"Ошибка получения инвентаря: "..tostring(data):sub(1,75) end
    local own=type(data)=="table" and data[player.Name]
    local save=type(own)=="table" and own.Save
    if type(save)~="table" or type(save.Pets)~="table" or type(save.PetSlots)~="number" then
        return nil,nil,"Сервер не вернул Save.Pets / Save.PetSlots"
    end
    Z25.updateInventory(save,"яйца")
    local count=Z25.inventory.count
    return count,save.PetSlots,nil
end
local function eggSessionActive(epoch)
    return alive and eggRunning and eggEpoch==epoch
end
local function startEggs(onlyOne)
    if converting then eggMessage="Сначала останови преобразование питомцев" return end
    if eggRunning then
        eggMessage="Открытие уже запущено; сначала останови его"
        return
    end
    local _,shop=eggRemotes()
    if not shop then
        eggMessage="Не найден Game.Shop (RemoteFunction)"
        log(eggMessage,true)
        return
    end
    eggEpoch+=1
    local epoch=eggEpoch
    local tier=eggTier
    local world=eggWorld
    local key=eggKey(world,tier)
    eggRunning=true
    eggAttempts=0
    eggOpened=0
    eggMessage=(onlyOne and "Открываю одно яйцо" or "Открываю до полного инвентаря").." • "..key
    log("Яйца: "..(onlyOne and "одно" or "до заполнения")..", "..key)
    task.spawn(function()
        local ok,err=pcall(function()
            local failures=0
            while eggSessionActive(epoch) do
                local count,capacity,errorText=getEggInventory()
                if not eggSessionActive(epoch) then break end
                if errorText then
                    eggMessage=errorText
                    break
                end
                eggInventory,eggCapacity=count,capacity
                if count>=capacity then
                    eggMessage="Инвентарь заполнен ("..count.."/"..capacity.."). Остановлено."
                    break
                end
                eggAttempts+=1
                local invoked,result,extra=pcall(function()
                    local success,pet=shop:InvokeServer("Buy","Eggs",key)
                    return success,pet
                end)
                if not eggSessionActive(epoch) then break end
                if not invoked then
                    eggMessage="Ошибка открытия: "..tostring(result):sub(1,95)
                    break
                end
                if result~=true then
                    eggMessage="Покупка не подтверждена сервером ("..tostring(result):sub(1,40).."). Возможно, не хватает монет или яйцо недоступно."
                    break
                end
                -- Give the server stats time to reflect the new pet. Count increase proves receipt.
                local latest,cap,newErr
                for tries=1,4 do
                    task.wait(.38)
                    if not eggSessionActive(epoch) then break end
                    latest,cap,newErr=getEggInventory()
                    if newErr or (latest and latest>count) then break end
                end
                if not eggSessionActive(epoch) then break end
                if newErr then
                    eggMessage="Открытие вызвано, но проверить инвентарь не удалось: "..newErr
                    break
                end
                eggInventory,eggCapacity=latest,cap
                if not latest or latest<=count then
                    failures+=1
                    eggMessage="Сервер вернул успех, но питомец в инвентаре не появился; остановлено во избежание повторных покупок"
                    break
                end
                failures=0
                eggOpened+=latest-count
                eggMessage=string.format("%s • получено: %d • инвентарь: %d/%d",key,eggOpened,latest,cap)
                if onlyOne then
                    eggMessage=eggMessage.." • готово (одно открытие)"
                    break
                end
                if latest>=cap then
                    eggMessage=eggMessage.." • инвентарь заполнен"
                    break
                end
                -- Conservative delay to avoid excessive purchases and allow UI/server updates.
                task.wait(.65)
            end
        end)
        if epoch==eggEpoch then
            eggRunning=false
            if not ok then
                eggMessage="Ошибка цикла яиц: "..tostring(err):sub(1,90)
                log(eggMessage,true)
            else log("Яйца: "..eggMessage) end
        end
    end)
end

local stopFarm -- predeclare for upgrade worker
-- Pet upgrades | Original Pet Simulator (2018), not PSX/PS99.
-- 10 normal -> golden; 7 golden -> rainbow; 5 rainbow -> dark matter.
-- Source of remote names/argument: published original-game Lua client example;
 -- every purchase/upgrade requires explicit interaction. No destructive call on load.
local UPGRADE={
    gold={title="Золото",need=10,remote="Golden Pets",from="normal",to="gold"},
    rainbow={title="Радуга",need=7,remote="Rainbow Pets",from="gold",to="rainbow"},
    dark={title="Dark Matter",need=5,remote="Dark Matter Pets",from="rainbow",to="dark"}
}
local upgradeStatusLabel, upgradePreviewLabel, upgradeProtectButton
local upgradeEpochConfirmed=nil
local upgradeConfirmDeadline=0
local lastUpgradePreview="Нажми «Проверить инвентарь»"
local function readPetSave()
    local statsRemote=eggRemotes()
    if not statsRemote then return nil,"Не найден Get Other Stats" end
    local ok,data=pcall(function() return statsRemote:InvokeServer() end)
    if not ok then return nil,"Ошибка данных: "..tostring(data):sub(1,80) end
    local own=type(data)=="table" and data[player.Name]
    local save=type(own)=="table" and own.Save
    if type(save)~="table" or type(save.Pets)~="table" then
        return nil,"Сервер не вернул Save.Pets"
    end
    Z25.updateInventory(save,"улучшения/инвентарь")
    return save
end
local function petStage(p)
    if type(p)~="table" then return nil end
    return Z25.classify(p)
end
local function farmIdProtected(p)
    if not protectFarmPets then return false end
    if Z25.trueFlag(p.e) then return true end
    local id=tonumber(p.id)
    for _,farmId in ipairs(cfg.ids) do if id==farmId then return true end end
    return false
end
local function petGroups(save,from)
    local groups={}
    for _,p in pairs(save.Pets) do
        if type(p)=="table" and p.id~=nil and p.n~=nil and petStage(p)==from and not farmIdProtected(p) then
            local kind=tostring(p.n)
            local bucket=groups[kind]
            if not bucket then bucket={} groups[kind]=bucket end
            bucket[#bucket+1]=p
        end
    end
    return groups
end
local function groupCount(save,kind,stage)
    local n=0
    for _,p in pairs(save.Pets) do
        if type(p)=="table" and tostring(p.n)==kind and petStage(p)==stage then n+=1 end
    end
    return n
end
local function selectReady(save,stage)
    local rule=UPGRADE[stage]
    local groups=petGroups(save,rule.from)
    local candidates={}
    for kind,bucket in pairs(groups) do
        if #bucket>=rule.need then candidates[#candidates+1]={kind=kind,pets=bucket} end
    end
    table.sort(candidates,function(a,b) return a.kind<b.kind end)
    if #candidates==0 then return nil end
    local candidate=candidates[1]
    table.sort(candidate.pets,function(a,b)
        local aa,bb=tonumber(a.id),tonumber(b.id)
        return aa and bb and aa<bb or tostring(a.id)<tostring(b.id)
    end)
    return candidate.kind,candidate.pets[1].id
end
local function upgradePlan(save)
    local lines={}
    for _,stage in ipairs({"gold","rainbow","dark"}) do
        local rule=UPGRADE[stage]
        local batches=0
        for _,group in pairs(petGroups(save,rule.from)) do batches+=math.floor(#group/rule.need) end
        lines[#lines+1]=rule.title..": "..batches.." преобразований ("..rule.need.." одинаковых)"
    end
    return table.concat(lines,"\n")
end
local function refreshUpgradePreview()
    local save,err=readPetSave()
    if not save then
        convertMessage=err
        log(err,true)
        return false
    end
    lastUpgradePreview=upgradePlan(save)
    local all=0
    for _,rule in pairs(UPGRADE) do
        for _,g in pairs(petGroups(save,rule.from)) do all+=math.floor(#g/rule.need) end
    end
    convertMessage=all>0 and ("Доступно групп: "..all.." • защита: "..(protectFarmPets and "ВКЛ" or "ВЫКЛ")) or
        "Нет подходящих групп: нужны 10/7/5 одинаковых одного уровня; экипированные защищены"
    if upgradePreviewLabel then upgradePreviewLabel.Text=lastUpgradePreview end
    return true
end
local function stopUpgrades(reason)
    convertEpoch+=1
    converting=false
    upgradeEpochConfirmed=nil
    if reason then convertMessage=reason end
end
local function runUpgrade(stages)
    if converting then convertMessage="Преобразование уже запущено" return end
    if eggRunning then convertMessage="Сначала останови открытие яиц" return end
    -- Check remotes before requesting any conversion.
    local remotes=workspace:FindFirstChild("__REMOTES")
    local gameR=remotes and remotes:FindFirstChild("Game")
    for _,stage in ipairs(stages) do
        local rule=UPGRADE[stage]
        local remote=gameR and gameR:FindFirstChild(rule.remote)
        if not remote or not remote:IsA("RemoteFunction") then
            convertMessage="Не найден серверный вызов «"..rule.remote.."»"
            log(convertMessage,true)
            return
        end
    end
    if farming then stopFarm() log("Автофарм приостановлен на время преобразования") end
    converting=true
    convertCompleted=0
    convertEpoch+=1
    local epoch=convertEpoch
    convertMessage="Запущено. Проверяю каждый результат по инвентарю…"
    task.spawn(function()
        local ok,err=pcall(function()
            local operations=0
            for _,stage in ipairs(stages) do
                local rule=UPGRADE[stage]
                while alive and converting and epoch==convertEpoch do
                    if operations>=500 then
                        convertMessage="Достигнут лимит 500 преобразований за запуск. Остановлено."
                        break
                    end
                    local save,readErr=readPetSave()
                    if not save then convertMessage=readErr break end
                    local kind,petId=selectReady(save,stage)
                    if not kind then
                        convertMessage="Этап «"..rule.title.."»: нет групп из "..rule.need.." одинаковых питомцев с защитой"
                        break
                    end
                    local beforeCount=groupCount(save,kind,rule.from)
                    local targetCount=groupCount(save,kind,rule.to)
                    local remote=gameR:FindFirstChild(rule.remote)
                    if not remote or not remote:IsA("RemoteFunction") then
                        convertMessage="Серверный вызов исчез: "..rule.remote
                        break
                    end
                    local invoked,response=pcall(function() return remote:InvokeServer(petId) end)
                    if not alive or not converting or epoch~=convertEpoch then break end
                    if not invoked then
                        convertMessage="Ошибка «"..rule.title.."»: "..tostring(response):sub(1,65)
                        break
                    end
                    if response==false then
                        convertMessage="Сервер отклонил «"..rule.title.."». Остановлено."
                        break
                    end
                    local changed=false
                    for attempt=1,5 do
                        task.wait(.45)
                        if not alive or not converting or epoch~=convertEpoch then break end
                        local newer=readPetSave()
                        if newer then
                            local src=groupCount(newer,kind,rule.from)
                            local dest=groupCount(newer,kind,rule.to)
                            if src<beforeCount and dest>targetCount then
                                changed=true
                                lastUpgradePreview=upgradePlan(newer)
                                if upgradePreviewLabel then upgradePreviewLabel.Text=lastUpgradePreview end
                                break
                            end
                        end
                    end
                    if not alive or not converting or epoch~=convertEpoch then break end
                    if not changed then
                        convertMessage="Сервер не показал изменения после «"..rule.title.."» (ID="..tostring(petId).."). Остановлено. Проверь игровой инвентарь после повторного входа."
                        break
                    end
                    operations+=1
                    convertCompleted+=1
                    convertMessage=rule.title.." • успешно преобразовано: "..convertCompleted
                    task.wait(.25)
                end
                if not alive or not converting or epoch~=convertEpoch then break end
                if convertMessage:find("Остановлено",1,true) or convertMessage:find("Ошибка",1,true) or
                    convertMessage:find("отклонил",1,true) then break end
            end
        end)
        if epoch==convertEpoch then
            converting=false
            if not ok then convertMessage="Ошибка цикла: "..tostring(err):sub(1,85) end
            log(convertMessage,not ok)
        end
    end)
end
local function confirmUpgrade(stages)
    if converting then convertMessage="Преобразование уже идёт" return end
    local key=table.concat(stages,"+")..(protectFarmPets and ":safe" or ":all")
    local now=os.clock()
    if upgradeEpochConfirmed~=key or now>upgradeConfirmDeadline then
        local save,err=readPetSave()
        if not save then convertMessage=err return end
        lastUpgradePreview=upgradePlan(save)
        if upgradePreviewLabel then upgradePreviewLabel.Text=lastUpgradePreview end
        upgradeEpochConfirmed=key
        upgradeConfirmDeadline=now+9
        convertMessage="Подтверждение: нажми ЭТУ ЖЕ кнопку ещё раз в течение 9 сек. Питомцы будут израсходованы!"
        return
    end
    upgradeEpochConfirmed=nil
    runUpgrade(stages)
end

stopFarm=function()
    farming=false
    session+=1
    table.clear(reserved)
end
local function claimCoin(id)
    local options=scan()
    orderCoins(options)
    for _,info in ipairs(options) do
        if not reserved[info.object] and validCoin(info.object) then
            reserved[info.object]=id
            return info.object
        end
    end
    return nil
end
local function active(epoch)
    return alive and farming and epoch==session
end
local progressLabel
local function worker(epoch,id)
    local profile=learned[id]
    local target=nil
    local misses,totalMisses=0,0
    while active(epoch) do
        if not validCoin(target) then
            if target and reserved[target]==id then reserved[target]=nil end
            target=claimCoin(id)
            misses=0
            if not target then task.wait(.8) continue end
        end
        local _,mineRemote,petRemote=nodes()
        if not mineRemote or not petRemote then
            log("Игровые события пропали, фарм остановлен",true)
            stopFarm()
            break
        end
        local part=partOf(target)
        local before=health(target)
        if not part or not before then
            if reserved[target]==id then reserved[target]=nil end
            target=nil
            task.wait(.15)
            continue
        end
        local coinName=target.Name
        local location=part.Position -- preserve v1.7 zero-offset behavior when unknown
        local ok,err=pcall(function()
            petRemote:FireServer({{"PetMovement",player,id,CFrame.new(location),false,profile.movement.speed}})
        end)
        if not ok then log("Movement "..id..": "..tostring(err):sub(1,70),true) break end
        stats.move+=1
        task.wait(.06)
        local sent=0
        for j=1,math.min(#profile.samples,5) do
            if not active(epoch) or not validCoin(target) then break end
            local value=profile.samples[j]
            if type(value)~="number" then break end
            local mineOk,mineErr=pcall(function()
                mineRemote:FireServer("Mine",coinName,value,id)
            end)
            if not mineOk then
                log("Mine "..id..": "..tostring(mineErr):sub(1,70),true)
                break
            end
            sent+=1
            stats.mine+=1
            task.wait(cfg.interval)
        end
        task.wait(.55)
        if not active(epoch) then break end
        local after=health(target)
        if validCoin(target) and type(after)=="number" and after<before then
            local delta=before-after
            stats.damage+=delta
            misses=0
            if progressLabel then
                progressLabel.Text=string.format("4/4 профилей: %d | HP снято: %.0f\n%s → %s (−%.0f HP, %d Mine)",profileCount(),stats.damage,id,coinName,delta,sent)
            end
        elseif not validCoin(target) then
            stats.gone+=1 -- target could disappear for multiple reasons
            if reserved[target]==id then reserved[target]=nil end
            target=nil
            misses=0
        else
            misses+=1
            if misses>=2 then
                stats.noProgress+=1
                totalMisses+=1
                if reserved[target]==id then reserved[target]=nil end
                target=nil
                misses=0
                if totalMisses>=3 then
                    log("Питомец "..id.." остановлен после 3 неудачных целей",true)
                    break
                end
            end
        end
    end
    if target and reserved[target]==id then reserved[target]=nil end
    if epoch==session then
        stats.workers=math.max(0,stats.workers-1)
        if stats.workers==0 then
            farming=false
            log("Все потоки завершили работу")
        end
    end
end
local function startFarm()
    if converting then log("Дождись окончания преобразования питомцев",true) return end
    if farming then return end
    local ids=availablePets()
    if #ids==0 then log("Нет сохранённых профилей питомцев",true) return end
    if Z25.area and not (Z25.point and Z25.point(Z25.area)) then
        log("Точка выбранной локации не сохранена. Открой «Телепорт» и запомни её.",true) return
    end
    if not Z25.area and (cfg.minX>=cfg.maxX or cfg.minZ>=cfg.maxZ) then log("Неверные границы зоны",true) return end
    local coins,mine,pets=nodes()
    if not coins or not mine or not pets then log("Монеты или RemoteEvent не найдены",true) return end
    local found=scan()
    if #found==0 then
        log(Z25.area and "В выбранной локации нет загруженных монет с HP: телепортируйся туда и попробуй снова" or "В зоне нет монет с HP",true)
        return
    end
    session+=1
    local epoch=session
    farming=true
    table.clear(reserved)
    stats.damage=0 stats.gone=0 stats.noProgress=0 stats.mine=0 stats.move=0 stats.clientErrors=0
    stats.workers=#ids
    if progressLabel then progressLabel.Text="Фарм запущен: "..#ids.." питомца. Отслеживаю HP..." end
    log("Запущен фарм: "..#ids.."/4 • "..Z25.areaDescription())
    for _,id in ipairs(ids) do
        task.spawn(function()
            local ok,err=pcall(worker,epoch,id)
            if not ok then
                log("Ошибка потока "..id..": "..tostring(err):sub(1,80),true)
                if epoch==session then
                    stats.workers=math.max(0,stats.workers-1)
                    if stats.workers==0 then farming=false end
                end
            end
        end)
    end
end

-- ZoneHub 2.4 UI | original Roblox thumbnail icon, no third-party URL.
local shutdown
local C={
    bg=Color3.fromRGB(10,15,26), panel=Color3.fromRGB(20,27,43), panel2=Color3.fromRGB(30,40,59),
    inset=Color3.fromRGB(13,21,36), line=Color3.fromRGB(55,68,91), white=Color3.fromRGB(244,248,255),
    dim=Color3.fromRGB(158,176,199),blue=Color3.fromRGB(91,143,255), green=Color3.fromRGB(70,218,180),
    red=Color3.fromRGB(240,104,130),gold=Color3.fromRGB(255,204,113), purple=Color3.fromRGB(173,124,255),
    cyan=Color3.fromRGB(102,207,244)
}
local TI=TweenInfo.new(.20,Enum.EasingStyle.Quint,Enum.EasingDirection.Out)
local function tween(obj,props,duration,style)
    local tw=TweenService:Create(obj,TweenInfo.new(duration or .20,style or Enum.EasingStyle.Quint,Enum.EasingDirection.Out),props)
    tw:Play()
    return tw
end
local function corner(o,r)
    local c=Instance.new("UICorner") c.CornerRadius=UDim.new(0,r or 12) c.Parent=o return c
end
local function stroke(o,col,trans)
    local x=Instance.new("UIStroke") x.Color=col or C.line x.Thickness=1 x.Transparency=trans or .2 x.Parent=o return x
end
local function gradient(o,a,b,rotation)
    local g=Instance.new("UIGradient") g.Color=ColorSequence.new(a,b) g.Rotation=rotation or 90 g.Parent=o return g
end
local function label(p,text,y,h,size,col,bold)
    local l=Instance.new("TextLabel") l.Name="Label"
    l.BackgroundTransparency=1 l.Position=UDim2.fromOffset(14,y) l.Size=UDim2.new(1,-28,0,h)
    l.Font=bold and Enum.Font.GothamBold or Enum.Font.Gotham
    l.Text=text l.TextSize=size or 12 l.TextColor3=col or C.white
    l.TextWrapped=true l.TextXAlignment=Enum.TextXAlignment.Left l.TextYAlignment=Enum.TextYAlignment.Center
    l.Parent=p return l
end
local orderCounts={}
local function card(p,h,highlight)
    local f=Instance.new("Frame") f.BackgroundColor3=C.panel f.BorderSizePixel=0
    f.Size=UDim2.new(1,0,0,h)
    orderCounts[p]=(orderCounts[p] or 0)+1
    f.LayoutOrder=orderCounts[p]
    f.Parent=p corner(f,14)
    stroke(f,highlight or C.line,.38)
    gradient(f,C.panel,C.inset,88)
    return f
end
local function button(p,txt,y,fn,bg)
    local b=Instance.new("TextButton") b.Text=txt b.Font=Enum.Font.GothamSemibold b.TextSize=12
    b.TextColor3=C.white b.BackgroundColor3=bg or C.panel2 b.BorderSizePixel=0
    b.Size=UDim2.new(1,-28,0,42) b.Position=UDim2.fromOffset(14,y)
    b.AutoButtonColor=false b.Parent=p corner(b,10)
    local scale=Instance.new("UIScale") scale.Parent=b
    local original=b.BackgroundColor3
    connections[#connections+1]=b.MouseButton1Down:Connect(function() tween(scale,{Scale=.965},.10) end)
    connections[#connections+1]=b.MouseButton1Up:Connect(function() tween(scale,{Scale=1},.16) end)
    connections[#connections+1]=b.MouseLeave:Connect(function() tween(scale,{Scale=1},.16) end)
    connections[#connections+1]=b.MouseButton1Click:Connect(function()
        if not alive then return end
        tween(scale,{Scale=.985},.08)
        task.delay(.10,function() if b.Parent then tween(scale,{Scale=1},.14) end end)
        local ok,err=pcall(fn)
        if not ok then log("Кнопка: "..tostring(err):sub(1,85),true) end
    end)
    return b
end
local function entry(p,title,y,value,changed)
    label(p,title,y,17,11,C.dim)
    local e=Instance.new("TextBox") e.ClearTextOnFocus=false
    e.Size=UDim2.new(1,-28,0,34) e.Position=UDim2.fromOffset(14,y+19)
    e.Text=tostring(value) e.TextColor3=C.white e.BackgroundColor3=C.inset e.BorderSizePixel=0
    e.PlaceholderColor3=C.dim e.Font=Enum.Font.Code e.TextSize=12 e.TextXAlignment=Enum.TextXAlignment.Left
    e.Parent=p corner(e,9) stroke(e,C.line,.58)
    connections[#connections+1]=e.FocusLost:Connect(function()
        if not alive then return end
        local ok,err=pcall(changed,e.Text)
        if not ok then log("Поле: "..tostring(err):sub(1,75),true) end
    end)
    return e
end
local function numeric(s,default) return tonumber((tostring(s):gsub(",","."))) or default end
local gui=Instance.new("ScreenGui") gui.Name="ZoneHub_PetSim" gui.ResetOnSpawn=false
 gui.IgnoreGuiInset=true gui.DisplayOrder=260 gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling gui.Parent=pg
local shadow=Instance.new("Frame") shadow.BackgroundColor3=Color3.fromRGB(3,6,14)
shadow.BackgroundTransparency=.37 shadow.BorderSizePixel=0 shadow.AnchorPoint=Vector2.new(.5,.5)
shadow.Position=UDim2.fromScale(.5,.505) shadow.Size=UDim2.fromOffset(408,588) shadow.Parent=gui corner(shadow,24)
local main=Instance.new("Frame") main.Name="Window" main.BackgroundColor3=C.bg main.BorderSizePixel=0
main.AnchorPoint=Vector2.new(.5,.5) main.Position=UDim2.fromScale(.5,.5)
main.Size=UDim2.fromOffset(396,576) main.Parent=gui corner(main,20) stroke(main,C.line,.10)
gradient(main,C.bg,Color3.fromRGB(15,22,37),90)
local scale=Instance.new("UIScale") scale.Scale=.92 scale.Parent=main
local shadowScale=Instance.new("UIScale") shadowScale.Parent=shadow
local folded, inTransition, transitionId, baseScale = false, false, 0, 1
local openPosition=main.Position
local openShadowPosition=shadow.Position
local function fit()
    local camera=workspace.CurrentCamera
    if not camera then return end
    local v=camera.ViewportSize
    baseScale=math.clamp(math.min((v.X-24)/405,(v.Y-24)/592),.45,1)
    if not folded and not inTransition then tween(scale,{Scale=baseScale},.25) end
    shadowScale.Scale=baseScale
end
fit()
connections[#connections+1]=workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(fit)
if workspace.CurrentCamera then
    connections[#connections+1]=workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
end
local top=Instance.new("Frame") top.BackgroundColor3=Color3.fromRGB(25,36,62)
top.BorderSizePixel=0 top.Size=UDim2.new(1,0,0,90) top.Parent=main corner(top,20)
gradient(top,Color3.fromRGB(29,51,90),Color3.fromRGB(19,28,48),15)
local headSeparator=Instance.new("Frame") headSeparator.BorderSizePixel=0 headSeparator.BackgroundColor3=C.line
headSeparator.BackgroundTransparency=.55 headSeparator.Position=UDim2.new(0,16,1,-1) headSeparator.Size=UDim2.new(1,-32,0,1) headSeparator.Parent=top
label(top,"✦  Z O N E H U B",13,32,21,C.white,true)
label(top,"2.4  •  PET SIMULATOR 2018",49,20,10,C.dim,true)
local livePill=Instance.new("TextLabel") livePill.Size=UDim2.fromOffset(65,24)
livePill.Position=UDim2.new(1,-173,0,21) livePill.Text="● IDLE"
livePill.Font=Enum.Font.GothamBold livePill.TextSize=10 livePill.TextColor3=C.dim
livePill.BackgroundColor3=C.inset livePill.Parent=top corner(livePill,13)
local collapse=Instance.new("TextButton") collapse.Name="Collapse"
-- Only collapse is user-facing. Full shutdown is internal, used on re-execute only.
collapse.Size=UDim2.fromOffset(37,37) collapse.Position=UDim2.new(1,-48,0,14)
collapse.Text="−" collapse.Font=Enum.Font.GothamBold collapse.TextSize=20
collapse.TextColor3=C.white collapse.BackgroundColor3=C.panel2 collapse.AutoButtonColor=false
collapse.Parent=top corner(collapse,12)
-- Roblox loads the official icon of the running game via rbxthumb. No unverified asset ID.
local gameIcon="rbxthumb://type=GameIcon&id="..tostring(game.GameId).."&w=150&h=150"
local float=Instance.new("TextButton") float.Name="FloatingButton" float.Visible=false
float.Size=UDim2.fromOffset(70,70) float.AnchorPoint=Vector2.new(1,.5)
float.Position=UDim2.new(1,-10,.5,0) float.Text="" float.AutoButtonColor=false
float.BackgroundColor3=Color3.fromRGB(42,68,120) float.Parent=gui corner(float,20)
stroke(float,C.cyan,.10) gradient(float,C.blue,C.purple,65)
local floatScale=Instance.new("UIScale") floatScale.Scale=.7 floatScale.Parent=float
local paw=Instance.new("TextLabel") paw.BackgroundTransparency=1 paw.Size=UDim2.new(1,0,1,-4)
paw.Position=UDim2.fromOffset(0,0) paw.Text="🐾" paw.TextSize=32 paw.TextColor3=C.white
paw.Font=Enum.Font.GothamBold paw.Parent=float
local iconArt=Instance.new("ImageLabel") iconArt.Name="OfficialPetSimulatorIcon"
iconArt.BackgroundTransparency=1 iconArt.Size=UDim2.fromOffset(54,54)
iconArt.Position=UDim2.fromOffset(8,5) iconArt.Image=gameIcon
iconArt.ScaleType=Enum.ScaleType.Crop iconArt.Parent=float corner(iconArt,15)
local iconCaption=Instance.new("TextLabel") iconCaption.BackgroundColor3=C.inset
iconCaption.Size=UDim2.new(1,-10,0,14) iconCaption.Position=UDim2.new(0,5,1,-17)
iconCaption.Text="ZONEHUB" iconCaption.TextSize=8 iconCaption.TextColor3=C.white
iconCaption.Font=Enum.Font.GothamBold iconCaption.Parent=float corner(iconCaption,7)
local function moveToFloat()
    return UDim2.new(1,-45,.5,0)
end
local keepOnScreen -- forward declaration for completion callback
local function setCollapsed(state)
    if inTransition or folded==state or not alive then return end
    folded=state
    inTransition=true
    transitionId+=1
    local token=transitionId
    if state then
        openPosition=main.Position
        openShadowPosition=shadow.Position
        float.Visible=true
        float.BackgroundTransparency=1
        floatScale.Scale=.65
        iconArt.ImageTransparency=1
        paw.TextTransparency=1
        iconCaption.TextTransparency=1
        tween(scale,{Scale=baseScale*.10},.42,Enum.EasingStyle.Quart)
        tween(main,{Position=moveToFloat(),Rotation=5,BackgroundTransparency=.78},.42,Enum.EasingStyle.Quart)
        tween(shadow,{Position=moveToFloat(),BackgroundTransparency=1},.36,Enum.EasingStyle.Quart)
        task.delay(.18,function()
            if not alive or transitionId~=token or not float.Parent then return end
            tween(float,{BackgroundTransparency=0},.28,Enum.EasingStyle.Quart)
            tween(floatScale,{Scale=1},.36,Enum.EasingStyle.Back)
            tween(iconArt,{ImageTransparency=0},.25)
            tween(paw,{TextTransparency=0},.25)
            tween(iconCaption,{TextTransparency=0},.25)
        end)
        task.delay(.45,function()
            if not alive or transitionId~=token or not folded then return end
            main.Visible=false shadow.Visible=false
            main.BackgroundTransparency=0 main.Rotation=0
            inTransition=false
        end)
    else
        main.Visible=true shadow.Visible=true
        main.Position=moveToFloat() main.Rotation=5 main.BackgroundTransparency=.78
        shadow.Position=moveToFloat() shadow.BackgroundTransparency=1
        scale.Scale=baseScale*.10
        tween(float,{BackgroundTransparency=1},.25)
        tween(floatScale,{Scale=.70},.32,Enum.EasingStyle.Quart)
        tween(iconArt,{ImageTransparency=1},.18)
        tween(paw,{TextTransparency=1},.18)
        tween(iconCaption,{TextTransparency=1},.18)
        tween(main,{Position=openPosition,Rotation=0,BackgroundTransparency=0},.45,Enum.EasingStyle.Quart)
        tween(shadow,{Position=openShadowPosition,BackgroundTransparency=.37},.40,Enum.EasingStyle.Quart)
        tween(scale,{Scale=baseScale},.45,Enum.EasingStyle.Quart)
        task.delay(.46,function()
            if not alive or transitionId~=token or folded then return end
            float.Visible=false
            inTransition=false
            keepOnScreen()
        end)
    end
end
connections[#connections+1]=collapse.MouseButton1Click:Connect(function() setCollapsed(true) end)
connections[#connections+1]=float.MouseButton1Click:Connect(function() setCollapsed(false) end)
-- Drag via header or lower-right grip. Pixel-center clamping keeps the whole window visible.
local function viewportSize()
    local cam=workspace.CurrentCamera
    return cam and cam.ViewportSize or Vector2.new(1280,720)
end
local function clampWindowCenter(x,y)
    local screen=viewportSize()
    local halfWidth=main.Size.X.Offset*baseScale/2
    local halfHeight=main.Size.Y.Offset*baseScale/2
    local margin=5
    local minX,maxX=halfWidth+margin,screen.X-halfWidth-margin
    local minY,maxY=halfHeight+margin,screen.Y-halfHeight-margin
    if maxX<minX then minX,maxX=screen.X/2,screen.X/2 end
    if maxY<minY then minY,maxY=screen.Y/2,screen.Y/2 end
    return math.clamp(x,minX,maxX),math.clamp(y,minY,maxY)
end
local function repositionWindow(x,y)
    x,y=clampWindowCenter(x,y)
    main.Position=UDim2.fromOffset(x,y)
    shadow.Position=UDim2.fromOffset(x,y+5)
end
local function currentWindowCenter()
    local v=viewportSize()
    local p=main.Position
    return v.X*p.X.Scale+p.X.Offset,v.Y*p.Y.Scale+p.Y.Offset
end
local grip=Instance.new("TextButton")
grip.Name="MoveGrip" grip.Size=UDim2.fromOffset(56,45)
grip.Position=UDim2.new(1,-59,1,-50)
grip.Text="⇲" grip.TextSize=26 grip.Font=Enum.Font.GothamBold
grip.TextColor3=C.cyan grip.BackgroundColor3=C.panel2 grip.BorderSizePixel=0
 grip.AutoButtonColor=false grip.ZIndex=8 grip.Parent=main corner(grip,12)
local gripHint=Instance.new("TextLabel")
gripHint.Size=UDim2.new(1,0,0,13) gripHint.Position=UDim2.new(0,0,1,-14)
gripHint.BackgroundTransparency=1 gripHint.Text="ТЯНИ" gripHint.Font=Enum.Font.GothamBold
 gripHint.TextColor3=C.dim gripHint.TextSize=9 gripHint.ZIndex=9 gripHint.Parent=grip
local dragging,dragInput,dragStart,dragCenter=false,nil,nil,nil
local function startDrag(input)
    if folded or inTransition or not alive then return end
    if input.UserInputType~=Enum.UserInputType.Touch and input.UserInputType~=Enum.UserInputType.MouseButton1 then return end
    dragging=true dragInput=input dragStart=input.Position
    local x,y=currentWindowCenter()
    dragCenter=Vector2.new(x,y)
end
connections[#connections+1]=top.InputBegan:Connect(function(input)
    -- Header action occupies the last 54px; exclude it from dragging.
    if input.Position.X>=top.AbsolutePosition.X+top.AbsoluteSize.X-58*baseScale then return end
    startDrag(input)
end)
connections[#connections+1]=grip.InputBegan:Connect(startDrag)
connections[#connections+1]=UserInputService.InputChanged:Connect(function(input)
    if not dragging or not dragCenter or not dragStart then return end
    if input~=dragInput and input.UserInputType~=Enum.UserInputType.MouseMovement then return end
    local delta=input.Position-dragStart
    repositionWindow(dragCenter.X+delta.X,dragCenter.Y+delta.Y)
end)
connections[#connections+1]=UserInputService.InputEnded:Connect(function(input)
    if input==dragInput then
        dragging=false dragInput=nil dragStart=nil dragCenter=nil
    end
end)
-- Clamping also works on rotation / viewport changes and restores the window to screen.
keepOnScreen=function()
    if not alive or folded or inTransition then return end
    local x,y=currentWindowCenter()
    local cx,cy=clampWindowCenter(x,y)
    if math.abs(cx-x)>.5 or math.abs(cy-y)>.5 then repositionWindow(cx,cy) end
end
if workspace.CurrentCamera then
    connections[#connections+1]=workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
        task.defer(keepOnScreen)
    end)
end
local tabBar=Instance.new("Frame") tabBar.BackgroundColor3=C.inset tabBar.BorderSizePixel=0
tabBar.Size=UDim2.new(1,-24,0,43) tabBar.Position=UDim2.fromOffset(12,100) tabBar.Parent=main corner(tabBar,12)
local tabs,pages,views={}, {}, {}
local names={"Фарм","Яйца","Улучшение","Телепорт","Настройки"}
local pill=Instance.new("Frame")
pill.Name="ActiveTabPill" pill.BackgroundColor3=C.panel2 pill.BorderSizePixel=0
pill.Position=UDim2.new(0,3,0,3) pill.Size=UDim2.new(1/#names,-6,1,-6)
pill.Parent=tabBar corner(pill,10) stroke(pill,C.line,.5)
pill.ZIndex=1
for i,name in ipairs(names) do
    local b=Instance.new("TextButton") b.Name=name b.Text=name b.TextSize=10
    b.Font=Enum.Font.GothamSemibold b.TextColor3=C.dim b.BackgroundTransparency=1
    b.BorderSizePixel=0 b.AutoButtonColor=false b.ZIndex=2
    b.Position=UDim2.new((i-1)/#names,2,0,3) b.Size=UDim2.new(1/#names,-4,1,-6)
    b.Parent=tabBar tabs[name]=b
    local group=Instance.new("CanvasGroup")
    group.Name=name.."View" group.BackgroundTransparency=1 group.BorderSizePixel=0
    group.ClipsDescendants=true group.Visible=false group.GroupTransparency=1
    group.Position=UDim2.fromOffset(12,151)
    group.Size=UDim2.new(1,-24,1,-219)
    group.Parent=main views[name]=group
    local sc=Instance.new("ScrollingFrame") sc.Name=name
    sc.Position=UDim2.fromScale(0,0) sc.Size=UDim2.fromScale(1,1)
    sc.BackgroundTransparency=1 sc.BorderSizePixel=0 sc.CanvasSize=UDim2.new()
    sc.AutomaticCanvasSize=Enum.AutomaticSize.Y
    sc.ScrollBarThickness=3 sc.ScrollBarImageColor3=C.blue sc.ScrollingDirection=Enum.ScrollingDirection.Y
    sc.Parent=group
    local pad=Instance.new("UIPadding") pad.PaddingTop=UDim.new(0,2)
    pad.PaddingBottom=UDim.new(0,8) pad.Parent=sc
    local layout=Instance.new("UIListLayout") layout.Padding=UDim.new(0,10)
    layout.SortOrder=Enum.SortOrder.LayoutOrder layout.Parent=sc
    pages[name]=sc
end
local activePage=nil
local pageVersion=0
local function switch(name,instant)
    if activePage==name then return end
    pageVersion+=1
    local version=pageVersion
    local previous=activePage
    local oldView=previous and views[previous]
    local nextView=views[name]
    if not nextView then return end
    local from=1
    local to=1
    for i,v in ipairs(names) do
        if v==name then to=i end
        if v==previous then from=i end
    end
    activePage=name
    tween(pill,{Position=UDim2.new((to-1)/#names,3,0,3)},instant and .01 or .42,Enum.EasingStyle.Quart)
    for n,b in pairs(tabs) do
        tween(b,{TextColor3=n==name and C.white or C.dim},instant and .01 or .30)
    end
    nextView.Visible=true
    nextView.ZIndex=4
    nextView.GroupTransparency=instant and 0 or 1
    nextView.Position=UDim2.fromOffset(instant and 12 or (to>=from and 34 or -10),151)
    if not instant then
        tween(nextView,{Position=UDim2.fromOffset(12,151),GroupTransparency=0},.42,Enum.EasingStyle.Quart)
    end
    if oldView and oldView~=nextView then
        oldView.ZIndex=3
        tween(oldView,{Position=UDim2.fromOffset(to>=from and -10 or 34,151),GroupTransparency=1},.32,Enum.EasingStyle.Quart)
        task.delay(.34,function()
            if pageVersion==version and oldView~=views[activePage] then oldView.Visible=false end
        end)
    end
    -- Hide any stale views after rapid switching (old tweens may overlap).
    task.delay(.46,function()
        if pageVersion~=version or not alive then return end
        for n,view in pairs(views) do
            if n~=activePage then view.Visible=false view.GroupTransparency=1 end
        end
    end)
end
for name,b in pairs(tabs) do
    connections[#connections+1]=b.MouseButton1Click:Connect(function() switch(name,false) end)
end
local footer=card(main,54)
footer.Position=UDim2.new(0,12,1,-62) footer.Size=UDim2.new(1,-24,0,53)
statusLabel=label(footer,"Готово",6,41,10,C.dim)
statusLabel.TextYAlignment=Enum.TextYAlignment.Top
statusLabel.Size=UDim2.new(1,-84,0,41)

-- FARM: existing network behavior remains unchanged.
local farm=pages["Фарм"]
local hero=card(farm,112,C.blue)
label(hero,"⛏  Автоматическая добыча",10,28,16,C.white,true)
local coinCount=label(hero,"Сканирую монеты…",41,19,12,C.dim)
local workLabel=label(hero,"●  ОСТАНОВЛЕН",71,26,13,C.red,true)
local farmActions=card(farm,80)
local startButton=button(farmActions,"▶  ЗАПУСТИТЬ АВТОФАРМ",17,function()
    if farming then stopFarm() log("Автофарм остановлен") else startFarm() end
end,C.blue)
Z25.uiCard=card(farm,196,C.green)
label(Z25.uiCard,"📍  Локация для Auto Farm",9,26,14,C.white,true)
Z25.areaLabel=label(Z25.uiCard,"Исходная зона (прямоугольник)",35,42,12,C.gold,true)
button(Z25.uiCard,"ФАРМИТЬ В ИСХОДНОЙ ЗОНЕ",80,function()
    if farming then stopFarm() end
    Z25.area=nil
    log("Выбрана исходная прямоугольная зона")
end,C.blue)
label(Z25.uiCard,"Другую локацию выбери в «Телепорт» → «Фармить здесь». Сохрани точку заранее. Радиус меняется в настройках.",130,53,11,C.dim)
local selection=card(farm,110)
label(selection,"Приоритет выбора монет",10,24,14,C.white,true)
local choose={{"Ближайшие","Near"},{"Меньше HP","LowHP"},{"Больше HP","HighHP"}}
local priorities={}
for i,item in ipairs(choose) do
    local mode=item[2]
    local b=button(selection,item[1],47,function()
        cfg.mode=mode
        for _,v in ipairs(priorities) do
            tween(v.b,{BackgroundColor3=v.mode==mode and C.blue or C.panel2},.18)
        end
        log("Приоритет: "..item[1])
    end,mode=="Near" and C.blue or C.panel2)
    b.Position=UDim2.new((i-1)/3,6,0,48) b.Size=UDim2.new(1/3,-9,0,40)
    b.TextSize=11 priorities[#priorities+1]={b=b,mode=mode}
end
local report=card(farm,158)
label(report,"Статистика фарма",9,24,14,C.white,true)
progressLabel=label(report,"Профилей: "..profileCount().."/4",40,63,12,C.white)
local function farmReport()
    return table.concat({
        "ZoneHub v2.5 | Автофарм",
        "Активен: "..tostring(farming).." | Потоков: "..stats.workers,
        string.format("HP снято: %.3f | исчезло целей: %d | без прогресса: %d",stats.damage,stats.gone,stats.noProgress),
        "Mine: "..stats.mine.." | PetMovement: "..stats.move,
        "Профилей: "..profileCount().."/4 | "..storageStatus,
        "Зона: "..Z25.areaDescription().." | прямоугольник X: "..cfg.minX..".."..cfg.maxX.."; Z: "..cfg.minZ..".."..cfg.maxZ,
        "Состояние: "..progressLabel.Text,
        "Журнал: "..table.concat(logLines," | ")
    },"\n")
end
button(report,"Копировать отчёт фарма",103,function()
    if type(setclipboard)~="function" then log("Буфер Delta недоступен",true) return end
    local ok=pcall(setclipboard,farmReport())
    log(ok and "Отчёт скопирован" or "Ошибка копирования",not ok)
end)
local note=card(farm,106)
label(note,"ℹ  Визуальное движение",8,24,13,C.gold,true)
label(note,"Фарм уменьшает HP через серверные команды. Принудительный полёт питомцев отключён: он вызывал дрожание моделей. Это не мешает добыче.",34,63,11,C.dim)

-- EGGS: Worlds 1, Moon, and seasonal Winter Wonderland.
local eggs=pages["Яйца"]
local worldCard=card(eggs,122,C.purple)
label(worldCard,"🥚  Мир для открытия яиц",9,26,15,C.white,true)
label(worldCard,"Выбери источник яиц и нужный Tier",35,20,11,C.dim)
local worldButtons={}
local worldDefs={{"Земля","World1",C.blue},{"Луна","Moon",C.purple},{"Зима","Winter",C.cyan}}
local updateTierMenu
for i,item in ipairs(worldDefs) do
    local world=item[2]
    local b=button(worldCard,item[1],67,function()
        if eggRunning then eggMessage="Останови открытие, прежде чем менять мир" return end
        eggWorld=world eggTier=EGG_WORLDS[world].min
        updateTierMenu()
    end,world=="World1" and C.blue or C.panel2)
    b.Position=UDim2.new((i-1)/3,6,0,67)
    b.Size=UDim2.new(1/3,-9,0,39)
    worldButtons[#worldButtons+1]={button=b,world=world,accent=item[3]}
end
local tiers=card(eggs,322,C.blue)
local eggTitle=label(tiers,"Первый мир · яйца",10,25,15,C.white,true)
local eggDesc=label(tiers,"Обычная валюта • Tier 1–12",34,20,11,C.dim)
local tierButtons={}
local tierPrice=label(tiers,"Выбран: Tier 1 • 275 монет",282,25,12,C.gold,true)
for i=1,12 do
    local idx=i
    local r=math.floor((i-1)/3)
    local col=(i-1)%3
    local b=button(tiers,"Tier "..i,63+r*51,function()
        if eggRunning then eggMessage="Сначала останови открытие яиц" return end
        local conf=EGG_WORLDS[eggWorld]
        local chosen=conf.min+idx-1
        if chosen>conf.max then return end
        eggTier=chosen
        updateTierMenu()
    end,i==1 and C.blue or C.panel2)
    b.Position=UDim2.new(col/3,6,0,63+r*51)
    b.Size=UDim2.new(1/3,-9,0,43)
    b.TextSize=11
    tierButtons[i]=b
end
function updateTierMenu()
    local conf=EGG_WORLDS[eggWorld]
    local accent=eggWorld=="Moon" and C.purple or eggWorld=="Winter" and C.cyan or C.blue
    for _,v in ipairs(worldButtons) do
        tween(v.button,{BackgroundColor3=v.world==eggWorld and v.accent or C.panel2},.20)
    end
    local n=conf.max-conf.min+1
    local rows=math.ceil(n/3)
    local height=63+rows*51+42
    tween(tiers,{Size=UDim2.new(1,0,0,height)},.28)
    eggTitle.Text=conf.title.."  •  яйца"
    eggDesc.Text=conf.sub.."  ·  "..conf.min.."–"..conf.max
    for i,b in ipairs(tierButtons) do
        local visible=i<=n
        b.Visible=visible
        if visible then
            local tier=conf.min+i-1
            b.Text=conf.prefix..tier
            tween(b,{BackgroundColor3=tier==eggTier and accent or C.panel2},.17)
        end
    end
    local idx=eggTier-conf.min+1
    tierPrice.Text="Выбрано: "..conf.prefix..eggTier.."  •  "..(conf.prices[idx] or "?").." "..(eggWorld=="Moon" and "🌙" or eggWorld=="Winter" and "❄" or "●")
    tierPrice.Position=UDim2.fromOffset(14,63+rows*51+2)
end
updateTierMenu()
local eggActions=card(eggs,176,C.green)
label(eggActions,"Режим открытия",9,26,14,C.white,true)
button(eggActions,"🥚  ОТКРЫТЬ ОДНО ЯЙЦО",36,function() startEggs(true) end,C.blue)
button(eggActions,"▶  ОТКРЫВАТЬ ДО ПОЛНОГО",82,function() startEggs(false) end,C.green)
button(eggActions,"■  ОСТАНОВИТЬ",128,function() stopEggs("Открытие остановлено вручную") log("Яйца остановлены") end,C.red)
local eggStats=card(eggs,142)
label(eggStats,"Открытие · статус",9,24,14,C.white,true)
eggStatusLabel=label(eggStats,"Ожидаю запуска",34,58,12,C.dim)
eggCountLabel=label(eggStats,"Покупок: 0 • Инвентарь: ?",98,27,11,C.gold,true)
Z25.uiCard=card(eggs,90,C.cyan)
label(Z25.uiCard,"Серверный счётчик питомцев",7,24,13,C.white,true)
Z25.eggLabel=label(Z25.uiCard,"Данные появятся после первой проверки или покупки",32,49,12,C.green)
local eggNote=card(eggs,108)
label(eggNote,"Защита от повторных покупок",8,25,13,C.gold,true)
label(eggNote,"Автостоп при полном инвентаре, отказе сервера или если новый питомец не появился. Moon и Winter используют отдельные валюты; Winter — сезонный мир.",35,64,11,C.dim)

-- UPGRADES: one tap selects, second tap confirms, no hidden mass conversion.
local upgrades=pages["Улучшение"]
local uHero=card(upgrades,119,C.gold)
label(uHero,"✦  Улучшение питомцев",10,30,17,C.white,true)
label(uHero,"Превращение одинаковых питомцев: золото, радуга, Dark Matter.",42,52,12,C.dim)
local ratios=card(upgrades,144,C.purple)
label(ratios,"Правила преобразования",10,28,14,C.white,true)
label(ratios,"10 обычных  →  1 золотой",40,25,12,C.gold,true)
label(ratios,"7 золотых  →  1 радужный",70,25,12,C.purple,true)
label(ratios,"5 радужных  →  1 Dark Matter",100,25,12,C.cyan,true)
local previewCard=card(upgrades,158,C.blue)
label(previewCard,"Возможные улучшения",10,26,14,C.white,true)
upgradePreviewLabel=label(previewCard,"Нажми «Проверить инвентарь»",41,79,12,C.dim)
button(previewCard,"Обновить инвентарь",114,function() refreshUpgradePreview() end,C.panel2)
local protectCard=card(upgrades,124,C.green)
label(protectCard,"Защита питомцев автофарма",9,24,14,C.white,true)
upgradeProtectButton=button(protectCard,"●  ЗАЩИТА 4 ПИТОМЦЕВ: ВКЛ",39,function()
    if converting then convertMessage="Сначала останови преобразование" return end
    protectFarmPets=not protectFarmPets
    upgradeEpochConfirmed=nil
    upgradeProtectButton.Text=protectFarmPets and "●  ЗАЩИТА 4 ПИТОМЦЕВ: ВКЛ" or "○  ЗАЩИТА 4 ПИТОМЦЕВ: ВЫКЛ"
    tween(upgradeProtectButton,{BackgroundColor3=protectFarmPets and C.green or C.red},.25)
    refreshUpgradePreview()
end,C.green)
label(protectCard,"Также защищаются ВСЕ экипированные питомцы. После снятия экипировки нажми «Обновить инвентарь».",85,34,11,C.dim)
local actionCard=card(upgrades,280,C.gold)
label(actionCard,"Преобразовать все доступные группы",10,28,14,C.white,true)
button(actionCard,"★  ВСЕХ В ЗОЛОТО",44,function() confirmUpgrade({"gold"}) end,C.gold)
button(actionCard,"✦  ВСЕХ В РАДУЖНЫХ",94,function() confirmUpgrade({"rainbow"}) end,C.purple)
button(actionCard,"◆  ВСЕХ В DARK MATTER",144,function() confirmUpgrade({"dark"}) end,C.cyan)
button(actionCard,"⇧  ВСЯ ЦЕПОЧКА: ЗОЛОТО → РАДУГА → DARK",194,function()
    confirmUpgrade({"gold","rainbow","dark"})
end,C.blue)
local stopUpButton=button(actionCard,"■  ОСТАНОВИТЬ ПРЕОБРАЗОВАНИЕ",242,function()
    stopUpgrades("Остановлено вручную. Текущий запрос мог завершиться на сервере.")
end,C.red)
stopUpButton.Size=UDim2.new(1,-28,0,32)
local stateCard=card(upgrades,154)
label(stateCard,"Статус преобразования",9,26,14,C.white,true)
upgradeStatusLabel=label(stateCard,"Готово к проверке",40,104,12,C.dim)
local caution=card(upgrades,130)
label(caution,"Перед началом",8,24,13,C.gold,true)
label(caution,"Питомцы расходуются необратимо. Для запуска нужно дважды нажать одну кнопку за 9 секунд. После каждого преобразования проверяется серверный инвентарь. Не отключай защиту, если хочешь сохранить 4 питомцев фарма.",31,95,11,C.dim)

local function buildTeleportUI()
-- TELEPORT v2.3: validate walkable ground before teleporting.
-- Find nearby walkable collision geometry with a downward ray; do nothing if absent.
local teleport=pages["Телепорт"]
local teleHero=card(teleport,94)
label(teleHero,"📍  Телепорт",9,28,15,C.white,true)
label(teleHero,"Центр зоны: поиск пола перед перемещением. Не разблокирует миры.",38,48,11,C.dim)
local savedPoint
local function go(pos)
    local r=root()
    local ch=player.Character
    if not r or not ch then log("Персонаж не найден",true) return false end
    local yaw=math.atan2(-r.CFrame.LookVector.X,-r.CFrame.LookVector.Z)
    local ok,err=pcall(function()
        ch:PivotTo(CFrame.new(pos)*CFrame.Angles(0,yaw,0))
        r.AssemblyLinearVelocity=Vector3.zero
        r.AssemblyAngularVelocity=Vector3.zero
    end)
    if not ok then log("Телепорт: "..tostring(err):sub(1,80),true) return false end
    log(string.format("Телепорт: %.1f / %.1f / %.1f",pos.X,pos.Y,pos.Z))
    return true
end
local function safeCenterTarget()
    local ch=player.Character
    local r=root()
    local hum=ch and ch:FindFirstChildOfClass("Humanoid")
    if not r or not hum then return nil,"Персонаж ещё не загружен" end
    local cx=(cfg.minX+cfg.maxX)/2
    local cz=(cfg.minZ+cfg.maxZ)/2
    -- Search near center, not at the low world-Y of a coin model.
    local offsets={
        {0,0},{8,0},{-8,0},{0,8},{0,-8},
        {16,0},{-16,0},{0,16},{0,-16},
        {16,16},{-16,-16},{16,-16},{-16,16},
        {32,0},{-32,0},{0,32},{0,-32}
    }
    local excluded={ch}
    local things=workspace:FindFirstChild("__THINGS")
    if things then
        local coinFolder=things:FindFirstChild("Coins")
        if coinFolder then excluded[#excluded+1]=coinFolder end
    end
    local debris=workspace:FindFirstChild("__DEBRIS")
    if debris then excluded[#excluded+1]=debris end
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Exclude
    params.IgnoreWater=true
    local topY=math.max(cfg.groundY+160,r.Position.Y+80)
    for _,offset in ipairs(offsets) do
        local x,z=cx+offset[1],cz+offset[2]
        if x>=cfg.minX+3 and x<=cfg.maxX-3 and z>=cfg.minZ+3 and z<=cfg.maxZ-3 then
            local origin=Vector3.new(x,topY,z)
            local ignoreHere={table.unpack(excluded)}
            for iteration=1,18 do
                params.FilterDescendantsInstances=ignoreHere
                local cast=workspace:Raycast(origin,Vector3.new(0,-480,0),params)
                if not cast then break end
                local hit=cast.Instance
                -- Reject decorative objects, thin triggers, steep walls, and floors far beneath the actual map.
                if hit.CanCollide and cast.Normal.Y>=0.78 and
                   math.abs(cast.Position.Y-cfg.groundY)<=40 then
                    local rootClearance=math.max(3.5,hum.HipHeight+r.Size.Y/2+2)
                    return Vector3.new(x,cast.Position.Y+rootClearance,z)
                end
                ignoreHere[#ignoreHere+1]=hit
            end
        end
    end
    return nil,"Не найдена безопасная поверхность у центра зоны. Телепорт отменён."
end
-- 14 original PS1 biome names verified in the 2018 game's biome list.
-- Exact player coordinates are not publicly verified. The user saves each location once;
-- afterwards teleport buttons are one-tap and persistent. No invented coordinates.
local PLACE_FILE="ZoneHub_teleports_v23.json"
local TELEPORT_AREAS={
    {id="earth1",title="Стартовая зона",world="Earth"},
    {id="earth2",title="Призрачный лес",world="Earth"},
    {id="earth3",title="Снежные горы",world="Earth"},
    {id="earth4",title="Лавовые пики",world="Earth"},
    {id="earth5",title="Плазменная зона",world="Earth"},
    {id="earth6",title="Аврора (грибы)",world="Earth"},
    {id="moon1",title="Лунная база",world="Moon"},
    {id="moon2",title="Розовая планета",world="Moon"},
    {id="moon3",title="Конфетная земля",world="Moon"},
    {id="moon4",title="Техно-долина",world="Moon"},
    {id="moon5",title="Храм Dominus",world="Moon"},
    {id="winter1",title="Зимний мир 1",world="Winter"},
    {id="winter2",title="Зимний мир 2",world="Winter"},
    {id="winter3",title="Зимний мир 3",world="Winter"},
}
local teleportPoints={}
local allowedArea={}
for _,a in ipairs(TELEPORT_AREAS) do allowedArea[a.id]=a.world end
local function validCoord(n)
    return type(n)=="number" and n==n and math.abs(n)<10000000
end
local function restoreTeleportData(raw)
    if type(raw)~="string" or #raw>20000 then return false end
    local ok,t=pcall(function() return HttpService:JSONDecode(raw) end)
    if not ok or type(t)~="table" or t.schema~=1 or type(t.points)~="table" then return false end
    local imported=0
    for id,p in pairs(t.points) do
        if allowedArea[id] and type(p)=="table" and p.world==allowedArea[id]
            and validCoord(p.x) and validCoord(p.y) and validCoord(p.z) then
            teleportPoints[id]={x=p.x,y=p.y,z=p.z,world=p.world}
            imported+=1
        end
    end
    return true,imported
end
if type(readfile)=="function" then
    local ok,data=pcall(readfile,PLACE_FILE)
    if ok then restoreTeleportData(data) end
end
if type(getgenv)=="function" then
    local env=getgenv()
    if type(env.ZoneHubTeleportPoints)=="table" then
        for id,p in pairs(env.ZoneHubTeleportPoints) do
            if allowedArea[id] and type(p)=="table" and p.world==allowedArea[id]
                and validCoord(p.x) and validCoord(p.y) and validCoord(p.z) then
                teleportPoints[id]={x=p.x,y=p.y,z=p.z,world=p.world}
            end
        end
    end
    env.ZoneHubTeleportPoints=teleportPoints
end
Z25.point=function(id)
    return teleportPoints[id]
end
local function persistTeleports()
    if type(writefile)~="function" then return false end
    local ok,raw=pcall(function()
        return HttpService:JSONEncode({schema=1,points=teleportPoints})
    end)
    return ok and pcall(writefile,PLACE_FILE,raw)
end
local pointStatus=label(teleHero,"Готовые точки: загрузка...",68,19,11,C.green)
local function countPoints()
    local n=0
    for _,a in ipairs(TELEPORT_AREAS) do if teleportPoints[a.id] then n+=1 end end
    return n
end
local nativeCard=card(teleport,148,C.cyan)
label(nativeCard,"🗺  Телепорты игры",8,26,14,C.white,true)
label(nativeCard,"Открой штатный список локаций: он учитывает игровые переходы между мирами и разблокировку.",35,56,11,C.dim)
local function openGameTeleport()
    local g=pg:FindFirstChild("Teleport",true)
    if g and g:IsA("ScreenGui") then
        g.Enabled=true
        log("Открыт игровой телепорт")
    elseif g and g:IsA("GuiObject") then
        g.Visible=true
        log("Открыт игровой телепорт")
    else
        log("Игровое меню Teleport не найдено. Открой телепорт в самой игре.",true)
    end
end
button(nativeCard,"ОТКРЫТЬ ИГРОВОЙ ТЕЛЕПОРТ",95,openGameTeleport,C.blue)
local goCard=card(teleport,177)
button(goCard,"Центр зоны фарма (проверка пола)",15,function()
    local pos,err=safeCenterTarget()
    if not pos then log(err,true) return end
    go(pos)
end,C.blue)
button(goCard,"Сохранить мою позицию",65,function()
    local r=root() if r then savedPoint=r.Position log("Позиция сохранена до закрытия игры") end
end)
button(goCard,"Вернуться к сохранённой",115,function()
    if savedPoint then go(savedPoint) else log("Нет сохранённой позиции",true) end
end)
local locationsIntro=card(teleport,105,C.purple)
label(locationsIntro,"📌  Быстрые точки • 14 локаций",8,26,14,C.white,true)
label(locationsIntro,"В нужной локации нажми «+ Запомнить здесь». После этого кнопка «→ Перейти» будет доступна и после перезапуска. Без выдуманных координат.",34,65,11,C.dim)
local rowStatuses={}
local function safeSavedPosition(p)
    local r=root()
    local ch=player.Character
    local hum=ch and ch:FindFirstChildOfClass("Humanoid")
    if not r or not hum then return nil,"Персонаж не загружен" end
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Exclude
    params.IgnoreWater=true
    local ignore={ch}
    local things=workspace:FindFirstChild("__THINGS")
    if things and things:FindFirstChild("Coins") then ignore[#ignore+1]=things.Coins end
    if workspace:FindFirstChild("__DEBRIS") then ignore[#ignore+1]=workspace.__DEBRIS end
    params.FilterDescendantsInstances=ignore
    local hit=workspace:Raycast(Vector3.new(p.x,p.y+10,p.z),Vector3.new(0,-36,0),params)
    if not hit or not hit.Instance.CanCollide or hit.Normal.Y<.65 or math.abs(hit.Position.Y-p.y)>15 then
        return nil,"Пол в этой точке не загружен. Перейди в её мир через игровой телепорт."
    end
    return Vector3.new(p.x,hit.Position.Y+math.max(3.5,hum.HipHeight+r.Size.Y/2+2),p.z)
end
local function updatePointText()
    for _,a in ipairs(TELEPORT_AREAS) do
        local row=rowStatuses[a.id]
        if row then
            local p=teleportPoints[a.id]
            row.Text=p and ("● СОХРАНЕНО  |  "..math.floor(p.x)..", "..math.floor(p.y)..", "..math.floor(p.z)) or "○ Не задана точка"
            row.TextColor3=p and C.green or C.dim
        end
    end
    pointStatus.Text="Запомнено локаций: "..countPoints().." / 14"
end
for _,world in ipairs({"Earth","Moon","Winter"}) do
    local caption=world=="Earth" and "🌎  ЗЕМЛЯ • 6 ЛОКАЦИЙ" or world=="Moon" and "🌙  ЛУНА • 5 ЛОКАЦИЙ" or "❄  ЗИМА • 3 ЛОКАЦИИ"
    local heading=card(teleport,42,world=="Earth" and C.blue or world=="Moon" and C.purple or C.cyan)
    label(heading,caption,7,27,13,C.white,true)
    for _,a in ipairs(TELEPORT_AREAS) do
        if a.world==world then
            local cell=card(teleport,146)
            label(cell,a.title,5,24,13,C.white,true)
            rowStatuses[a.id]=label(cell,"○ Не задана точка",27,17,10,C.dim)
            local goBtn=button(cell,"→ ПЕРЕЙТИ",53,function()
                local p=teleportPoints[a.id]
                if not p then
                    log("Точка ещё не сохранена: "..a.title..". Выбери локацию в игровом телепорте.")
                    openGameTeleport()
                    return
                end
                local pos,err=safeSavedPosition(p)
                if not pos then log(err,true) return end
                go(pos)
            end,C.blue)
            goBtn.Size=UDim2.new(.49,-14,0,36)
            goBtn.TextSize=10
            local saveBtn=button(cell,"+ ЗАПОМНИТЬ",53,function()
                local r=root()
                if not r then log("Персонаж не найден",true) return end
                local v=r.Position
                teleportPoints[a.id]={x=v.X,y=v.Y,z=v.Z,world=a.world}
                local ok=persistTeleports()
                updatePointText()
                log(a.title..": позиция записана"..(ok and " на телефон" or " только до перезапуска"),not ok)
            end,C.panel2)
            saveBtn.Position=UDim2.new(.51,0,0,53)
            saveBtn.Size=UDim2.new(.49,-14,0,36)
            saveBtn.TextSize=10
            local pickFarm=button(cell,"⛏ ФАРМИТЬ ЗДЕСЬ",98,function()
                if not teleportPoints[a.id] then
                    log("Для фарма сначала сохрани точку: "..a.title,true)
                    return
                end
                if farming then stopFarm() end
                Z25.area=a.id
                if Z25.areaLabel then Z25.areaLabel.Text=a.title.." • радиус "..Z25.radius.." studs" end
                log("Выбрана зона фарма: "..a.title..". Если монеты не найдены, перейди в эту локацию.")
                switch("Фарм",false)
            end,C.green)
            pickFarm.Size=UDim2.new(1,-28,0,35)
            pickFarm.TextSize=11
        end
    end
end
updatePointText()
local xyz=card(teleport,267)
label(xyz,"Свои координаты",8,24,14,C.white,true)
local rr=root()
local xEntry=entry(xyz,"X",39,rr and rr.Position.X or 0,function()end)
local yEntry=entry(xyz,"Y",96,rr and rr.Position.Y or cfg.groundY,function()end)
local zEntry=entry(xyz,"Z",153,rr and rr.Position.Z or 0,function()end)
button(xyz,"Телепортироваться",214,function()
    local x,y,z=numeric(xEntry.Text),numeric(yEntry.Text),numeric(zEntry.Text)
    if not x or not y or not z then log("Укажи 3 координаты",true) return end
    go(Vector3.new(x,y,z))
end,C.blue)

return countPoints
end -- buildTeleportUI
local countTeleports = buildTeleportUI()

-- SETTINGS: preserves 4/4 profile persistence and zone controls.
local settings=pages["Настройки"]
local profileCard=card(settings,126,C.green)
label(profileCard,"🐾  Обученные питомцы",10,27,15,C.white,true)
local profileLabel=label(profileCard,"Чтение профилей…",42,70,12,C.dim)
local info=card(settings,92)
label(info,"Профили сохранены",8,23,13,C.gold,true)
label(info,"Файл ZoneHub_profiles_v17.json содержит данные четырёх питомцев. Не удаляй его с телефона.",33,52,11,C.dim)
local inventoryCard=card(settings,230,C.cyan)
label(inventoryCard,"🐾  Инвентарь по данным сервера",8,26,13,C.white,true)
Z25.inventoryLabel=label(inventoryCard,"Не проверен. Нажми кнопку ниже.",37,65,12,C.green,true)
Z25.inventoryDetails=label(inventoryCard,"Обычный инвентарь игры может не обновляться после прямых запросов. Это отдельный серверный счётчик.",105,54,11,C.dim)
button(inventoryCard,"ОБНОВИТЬ ДАННЫЕ СЕРВЕРА",168,function()
    local save,err=readPetSave()
    if not save then
        Z25.inventoryLabel.Text="Ошибка чтения: "..tostring(err)
        log("Инвентарь: "..tostring(err),true)
        return
    end
    local count,knownIds=0,0
    local knownSet={}
    for _,id in ipairs(cfg.ids) do knownSet[id]=true end
    for _,pet in pairs(save.Pets) do
        if type(pet)=="table" then
            count+=1
            if knownSet[tonumber(pet.id)] then knownIds+=1 end
        end
    end
    Z25.updateInventory(save,"ручная проверка")
    log("Инвентарь проверен: "..count.." питомцев")
end,C.blue)
Z25.uiCard=card(settings,115,C.green)
entry(Z25.uiCard,"Радиус фарма вокруг сохранённой точки (30–250)",10,Z25.radius,function(value)
    Z25.radius=math.clamp(numeric(value,Z25.radius),30,250)
    if farming then stopFarm() log("Фарм остановлен: радиус изменён") end
    log("Радиус локального фарма: "..Z25.radius)
end)
local intervalCard=card(settings,95)
entry(intervalCard,"Интервал Mine (секунды, минимум 0.40)",9,cfg.interval,function(t)
    cfg.interval=math.clamp(numeric(t,cfg.interval),.4,5)
    log("Интервал Mine: "..cfg.interval)
end)
local boundsCard=card(settings,270)
label(boundsCard,"Границы зоны фарма",9,26,14,C.white,true)
for i,v in ipairs({{"minX","X минимум"},{"maxX","X максимум"},{"minZ","Z минимум"},{"maxZ","Z максимум"}}) do
    local key=v[1]
    entry(boundsCard,v[2],41+(i-1)*56,cfg[key],function(t)
        local old=cfg[key]
        cfg[key]=numeric(t,cfg[key])
        if cfg.minX>=cfg.maxX or cfg.minZ>=cfg.maxZ then cfg[key]=old log("Неверные границы",true)
        else log("Изменена граница "..key) end
    end)
end
local backup=card(settings,230)
label(backup,"Резервная копия 4/4",9,26,14,C.white,true)
button(backup,"Сохранить на телефон",41,function()
    local ok,msg=saveProfiles()
    if ok then storageStatus=msg end
    log(msg,not ok)
end,C.blue)
button(backup,"Копировать JSON",88,function()
    if type(setclipboard)~="function" then log("Буфер Delta недоступен",true) return end
    local ok=pcall(setclipboard,toJson())
    log(ok and "JSON скопирован" or "Ошибка копирования",not ok)
end)
local jsonInput=entry(backup,"Вставить JSON для восстановления",134,"",function()end)
jsonInput.Text="" jsonInput.PlaceholderText="Вставь сохранённую копию"
button(backup,"Восстановить JSON",181,function()
    if farming then log("Сначала останови фарм",true) return end
    local ok,n=loadProfiles(jsonInput.Text)
    if not ok then log("Импорт: "..tostring(n),true) return end
    log("Восстановлено профилей: "..n)
    if profileCount()==4 then
        local saved,msg=saveProfiles()
        if saved then storageStatus=msg else log(msg,true) end
    end
end)

local lastRefresh=0
local function refresh()
    local options,total=scan()
    coinCount.Text=string.format("Монет: %d всего  •  %d в зоне",total,#options)
    if Z25.areaLabel then Z25.areaLabel.Text=Z25.areaDescription() end
    local eggSymbol=eggRunning and "● ОТКРЫВАЕТ" or "● ОЖИДАНИЕ"
    eggStatusLabel.Text=eggSymbol.."\n"..eggMessage
    eggStatusLabel.TextColor3=eggRunning and C.green or C.dim
    eggCountLabel.Text="Покупок: "..eggAttempts.." • новых: "..eggOpened.." • инвентарь: "..(eggInventory and (eggInventory.."/"..(eggCapacity or "?")) or "не проверен")
    workLabel.Text=farming and ("●  ФАРМ: "..stats.workers.." ПИТОМЦА") or "●  ОСТАНОВЛЕН"
    workLabel.TextColor3=farming and C.green or C.red
    livePill.Text=converting and "● UP" or farming and "● FARM" or eggRunning and "● EGGS" or "● IDLE"
    livePill.TextColor3=(farming or eggRunning or converting) and C.green or C.dim
    startButton.Text=farming and "■  ОСТАНОВИТЬ АВТОФАРМ" or "▶  ЗАПУСТИТЬ АВТОФАРМ"
    startButton.BackgroundColor3=farming and C.red or C.blue
    profileLabel.Text="Готово: "..profileCount().."/4\n"..storageStatus
    upgradeStatusLabel.Text=(converting and "● ИДЁТ • " or "● ГОТОВО • ")..convertMessage.."\nПодтверждено улучшений: "..convertCompleted
    upgradeStatusLabel.TextColor3=converting and C.green or C.dim
    if not farming then
        progressLabel.Text=string.format("Профили: %d/4  •  HP за прошлый запуск: %.0f\nMine: %d  •  Movement: %d  •  Ошибок: %d",profileCount(),stats.damage,stats.mine,stats.move,stats.clientErrors)
    end
end
connections[#connections+1]=RunService.Heartbeat:Connect(function()
    if not alive or not gui.Parent then return end
    local now=os.clock()
    if now-lastRefresh>=1.2 then lastRefresh=now refresh() end
end)
shutdown=function()
    stopEggs()
    stopUpgrades()
    stopFarm()
    alive=false
    for _,conn in ipairs(connections) do pcall(function() conn:Disconnect() end) end
    pcall(function() gui:Destroy() end)
end
if type(getgenv)=="function" then getgenv().ZoneHubShutdown=shutdown end
switch("Фарм",true)
refresh()
log("v2.5: профили "..profileCount().."/4; локаций сохранено: "..countTeleports().."/14")
