-- ZoneHub 3.2.1 | Pet Simulator 2018 | fixed top-level local pressure and isolated UI scopes
-- No hooks, metamethod modifications, external libraries, client-pet movement, or idle remote calls.
-- Native Roblox inventory UI is NOT patched; direct shop/upgrade remote calls may not refresh it.
-- The v1.2 recording hook is an old process-global hook: a full Roblox restart clears it.
-- Original PS1 shop protocol, no automatic purchases on load.
-- Winter Wonderland eggs are seasonal; server availability is not guaranteed.
-- Uses observed numeric Mine packets. Server behavior can change; client HP is only a proxy.
-- Reads legacy v1.7 profiles ONLY when their IDs are still in current inventory; never farms deleted pets.

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
    -- Legacy v1.2-v1.4 capture could remain installed until Roblox fully restarts.
    -- At least disable recording; do not try to override or chain a second hook.
    if type(env.__ZoneHubManualCapture)=="table" then
        env.__ZoneHubManualCapture.recording=false
    end
end
local old = pg:FindFirstChild("ZoneHub_PetSim")
if old then old:Destroy() end

local alive, farming, session = true, false, 0
local converting, convertEpoch = false, 0
local convertMessage = "Нажми «Проверить» для поиска групп"
local convertCompleted = 0
local protectFarmPets = true
local eggRunning, eggEpoch, eggTier = false, 0, 1
local eggWorld="World1"
local Z25={}
Z25.paused=false -- pause outgoing Mine/Movement while accessing native inventory
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
local eggConfirmed, eggRejected, eggBatches, eggStarted = 0, 0, 0, 0
local eggPausedFarm=false
local eggMessage = "Выбери мир и яйцо. Покупка не запущена"

-- Pet type codes (p.n), not unique inventory IDs (p.id). Published original-game map.
-- Unknown p.n values are always protected, even in automatic delete mode.
local PET_TYPE_NAMES={
    [77002]='Festive Dragon',
    [9004]='Wavy Cheeta',
    [7004]='Dragon',
    [8004]='Demon',
    [5004]='Bat',
    [6004]='Ladybug',
    [3004]='Pig',
    [4004]='Seal',
    [1004]='Lamb',
    [2004]='Mouse',
    [16012]='Cyborg Dominus',
    [16009]='Cyborg Demon',
    [77003]='Snow Spike',
    [15005]='Green Gummy Bear',
    [13007]='Space Dragon',
    [10004]='Electric Slime',
    [66002]='Zombie Dog',
    [15006]='Yellow Gummy Bear',
    [15008]='Rainbow',
    [16002]='Cyborg Dog',
    [12003]='Angel',
    [13001]='Alien',
    [15009]='Dark Candy Corn',
    [17003]='Dominus Noob',
    [66003]='Spider',
    [12007]='Mortuus',
    [12005]='Ice Queen',
    [11004]='Lava Watermelon',
    [76004]='Festive Racoon',
    [66004]='Pumpkin',
    [16006]='Red Space Ranger',
    [16001]='Cyborg Cat',
    [11002]='Sherbert',
    [76001]='Festive Cat',
    [66001]='Zombie Cat',
    [79003]='Giant Penguin',
    [15007]='Cookie',
    [1001]='Cat',
    [3001]='Dalmatian',
    [2001]='Brown Cat',
    [5001]='Owl',
    [4001]='Koala',
    [7001]='Watermelon',
    [6001]='Cheeta',
    [9001]='Fantasy Dragon',
    [8001]='Bomb',
    [66006]='Ghostdeeri',
    [12004]='Fire King',
    [90003]='Red Snake',
    [78002]='Gingerbread',
    [17006]='Dominus Damnee',
    [10003]='Lava Turtle',
    [15001]='Candy Cane',
    [18002]='Spike',
    [17009]='Dominus Huge',
    [14005]='Space Bear',
    [2005]='White Bunny',
    [1005]='Orange Cat',
    [10002]='Lava Dalmatian',
    [8005]='Cyclops',
    [9005]='Wavy Tiger',
    [4005]='Racoon',
    [3005]='Panda',
    [13004]='Space Cat',
    [5005]='Bee',
    [18006]='Agony',
    [18001]='Aesthetic Cat',
    [13002]='Puffer',
    [10001]='Lava Zebra',
    [17007]='Dominus Rainbow',
    [90001]='BIG Maskot',
    [11005]='Wavy Bee',
    [10006]='Dominus Messor',
    [14004]='Space Cyclops',
    [17001]='Dominus Pumpkin',
    [12002]='Reaper',
    [2002]='White Cat',
    [3002]='Bear',
    [4002]='Crocodile',
    [5002]='Monkey',
    [6002]='Tiger',
    [7002]='Yeti',
    [8002]='Ghost',
    [9002]='Cherry Bomb',
    [11006]='Unicorn',
    [90010]='Huge Cat',
    [15004]='Green Lollipop',
    [16011]='C0RE SH0CK',
    [90008]='Noob',
    [1002]='Dog',
    [12006]='Immortuos',
    [90009]='Love Cat',
    [14009]='1NE',
    [76002]='Festive Dog',
    [90006]='Dominus Partner',
    [90005]='Wavy Snake',
    [16004]='Cyborg',
    [90004]='Purple Snake',
    [10008]='Dominus Empyreus',
    [90002]='Green Snake',
    [79002]='Festive C0RE',
    [13003]='Wooga',
    [79001]='Festive Immortuos',
    [78005]='Randolph',
    [78004]='Festive Dominus',
    [12001]='Tank',
    [78003]='Reindeer',
    [78001]='Festive Ame Damnee',
    [18004]='Chimera',
    [77001]='Festive Seal',
    [13005]='Space Dog',
    [76003]='Festive Bunny',
    [90007]='Love Dog',
    [66010]='Skeleton Ghost',
    [66009]='Willow Wisp Green',
    [66008]='Willow Wisp',
    [66007]='Sorrow',
    [66005]='Skeleton',
    [18005]='Hydra',
    [77004]='Ice Spike',
    [18003]='Magic Fox',
    [17008]='Dominus Electric',
    [17005]='Dominus HeadStack',
    [13006]='Space Bunny',
    [16005]='Space Ranger',
    [17002]='Dominus Cherry',
    [16010]='C0RE',
    [16008]='RoVer',
    [16007]='Friendly Cyborg',
    [17004]='Dominus Wavy',
    [14002]='HeadStack',
    [16003]='Computer',
    [15011]='Domortuus',
    [15010]='Ame Damnee',
    [15003]='Red Lollipop',
    [15002]='Candy Corn',
    [10007]='Dominus Frigidus',
    [14008]='ZER0',
    [6003]='Zebra',
    [5003]='Turtle',
    [4003]='Platypus',
    [3003]='Polar Bear',
    [2003]='White Dog',
    [1003]='Bunny',
    [14007]='Dark Saturn',
    [10005]='Electric Ghost',
    [14006]='Saturn',
    [14003]='Space Owl',
    [14001]='Revurse',
    [11003]='Robot',
    [11001]='Zombie',
    [9003]='Wavy Zebra',
    [8003]='Cherry Monkey',
    [7003]='Slime',
}
local petTypesSorted={}
for code,name in pairs(PET_TYPE_NAMES) do
    petTypesSorted[#petTypesSorted+1]={code=tostring(code),name=name}
end
table.sort(petTypesSorted,function(a,b)
    local an,bn=string.lower(a.name),string.lower(b.name)
    return an==bn and tonumber(a.code)<tonumber(b.code) or an<bn
end)
local eggFilter={mode="off",keep={},kept=0,deleted=0,protected=0,preview=0,
    limit=30,last="Фильтр выключен. Сначала выбери нужного питомца.",pendingAt=0}
local eggFilterLabel=nil
local function countKeepTypes()
    local count=0
    for _,selected in pairs(eggFilter.keep) do if selected then count+=1 end end
    return count
end
local function keepSummary()
    local list={}
    for _,t in ipairs(petTypesSorted) do
        if eggFilter.keep[t.code] then list[#list+1]=t.name end
    end
    return table.concat(list,", ")
end
local function petNameForType(typeCode)
    return PET_TYPE_NAMES[tonumber(typeCode)]
end
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
-- Locked target for each ID: it must not be discarded only because it now has low HP.
local lockedTargets={}
local logLines = {}
local cfg = {
    ids={15883528,25214651,92565120,95608754}, -- archival IDs, not current equipped list
    minX=-3218.733,maxX=-2832.849,minZ=-1747.956,maxZ=-1468.381,
    groundY=144.810,interval=.42,mode="Near"
}
local stats = {mine=0, move=0, clientErrors=0, damage=0, gone=0, noProgress=0, workers=0,
    targetReused=0,targetChanged=0,started=0,perPet={},peakWorkers=0}
-- Modes: saved = legacy profiles if still present, equipped = current equipped,
-- all = rotation across every valid inventory ID after an independent multi-pet HP verification.
Z25.autoPets={mode="equipped",allVerified=false,checking=false,total=0,equipped=0,ready=0,rotated=0,
    last="Не проверен",rejected={},success={},pool={},activeCount=4,probePassed=0,probeTried=0,probeDetails="не выполнялся"}
local autoPetsLabel,autoPetsStatusLabel
local lastInventorySignature=nil
Z25.dynamicPoolCursor=0
local PROFILE_FILE = "ZoneHub_profiles_v17.json" -- intentionally unchanged
local storageStatus = "Проверка сохранения..."
local function timestamp() return os.date("%H:%M:%S") end
local statusLabel
local function log(msg, bad)
    table.insert(logLines, 1, (bad and "! " or "• ")..timestamp().." "..tostring(msg))
    while #logLines>5 do table.remove(logLines) end
    if bad then stats.clientErrors+=1 end
    if statusLabel then statusLabel.Text=logLines[1] or "Готово" end
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
-- A legacy profile only works for a pet that still exists. Fusing pets destroys their IDs.
local function existingRecordedPets()
    local save,err=Z25.readCurrentPetSave()
    if not save then return nil,err end
    local present={}
    for _,pet in pairs(save.Pets) do
        if type(pet)=="table" then
            local id=tonumber(pet.id)
            if id and pet.e==true then present[id]=true end
        end
    end
    local ids={}
    for _,id in ipairs(availablePets()) do
        if present[id] then ids[#ids+1]=id end
    end
    return ids
end

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
local function finishEggFarmPause()
    if eggPausedFarm then
        eggPausedFarm=false
        if alive and farming then Z25.paused=false end
    end
end
local function stopEggs(reason)
    local wasRunning=eggRunning
    eggRunning=false
    eggEpoch+=1
    if reason then
        eggMessage=reason..(wasRunning and " • уже отправленные покупки могут завершиться" or "")
    end
    finishEggFarmPause()
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
    return count,save.PetSlots,nil,save
end
local function eggSessionActive(epoch)
    return alive and eggRunning and eggEpoch==epoch
end

-- Only consider IDs returned by the current purchases AND absent from the pre-purchase snapshot.
-- No guessed IDs, no pre-existing inventory items, no equipped/variant pets.
local function indexedPets(save)
    local byId={}
    if type(save)~="table" or type(save.Pets)~="table" then return byId end
    for _,p in pairs(save.Pets) do
        if type(p)=="table" then
            local id=tonumber(p.id)
            if id and id>0 and id%1==0 then byId[id]=p end
        end
    end
    return byId
end
local function hatchResultPet(info)
    if type(info)~="table" then return nil end
    local candidate=info[1]
    if type(candidate)=="table" then candidate=candidate[1] end
    if type(candidate)~="table" then return nil end
    local id=tonumber(candidate.id)
    if not id or id<=0 or id%1~=0 then return nil end
    return {id=id,kind=tostring(candidate.n or "")}
end
local function filterHatchedPets(beforeSave,afterSave,buyResults,confirmed,epoch)
    if eggFilter.mode=="off" then return true,false,"" end
    if countKeepTypes()<1 then return false,false,"Не выбран ни один питомец для сохранения" end
    local prior=indexedPets(beforeSave)
    local after=indexedPets(afterSave)
    local seen,newPets={},{}
    local received=0
    for _,record in pairs(buyResults) do
        if record and record.accepted then
            received+=1
            local hatch=record.pet
            if not hatch or seen[hatch.id] then
                return false,false,"Покупка не вернула уникальный ID питомца. Автоудаление остановлено."
            end
            seen[hatch.id]=true
            local p=after[hatch.id]
            if prior[hatch.id] or not p or tostring(p.n)~=hatch.kind then
                return false,false,"ID или тип нового питомца не совпал с инвентарём. Удаление отменено."
            end
            newPets[#newPets+1]={id=hatch.id,data=p,kind=hatch.kind}
        end
    end
    if received~=confirmed then return false,false,"Ответы покупок неполные: удаление отменено" end
    -- Another inventory operation could add unrelated pets. Do not clean them up.
    local wanted,removable,unknown=0,{},0
    for _,item in ipairs(newPets) do
        local p=item.data
        local name=petNameForType(item.kind)
        if eggFilter.keep[item.kind] then
            wanted+=1
        elseif not name or Z25.trueFlag(p.e) or Z25.classify(p)~="normal" then
            unknown+=1 -- protect unfamiliar names, equipped, and gold/rainbow/dark variants
        else
            removable[#removable+1]=item.id
        end
    end
    eggFilter.kept+=wanted
    eggFilter.protected+=unknown
    if eggFilter.mode=="preview" then
        eggFilter.preview+=#removable
        return true,wanted>0,string.format("Предпросмотр: оставлено %d, к удалению %d, защищено %d (ничего не удалено)",wanted,#removable,unknown)
    end
    if #removable==0 then
        return true,wanted>0,string.format("Оставлено %d, защищено %d, удалять нечего",wanted,unknown)
    end
    if not eggSessionActive(epoch) then return false,wanted>0,"Покупки остановлены до удаления" end
    local gameRemotes=workspace:FindFirstChild("__REMOTES")
    gameRemotes=gameRemotes and gameRemotes:FindFirstChild("Game")
    local inv=gameRemotes and gameRemotes:FindFirstChild("Inventory")
    if not inv or not inv:IsA("RemoteFunction") then
        return false,wanted>0,"Нет Game.Inventory: серверное удаление недоступно"
    end
    -- A fresh read checks these exact IDs again immediately before destructive action.
    local _,_,err,fresh=getEggInventory()
    if err or not fresh then return false,wanted>0,"Ошибка контрольного чтения: "..tostring(err) end
    local current=indexedPets(fresh)
    for _,id in ipairs(removable) do
        local orig=after[id]
        local now=current[id]
        if not now or prior[id] or tonumber(now.id)~=id or tostring(now.n)~=tostring(orig.n)
            or eggFilter.keep[tostring(now.n)] or Z25.trueFlag(now.e) or Z25.classify(now)~="normal" then
            return false,wanted>0,"Контроль удаления не пройден. Питомцы сохранены."
        end
    end
    -- Published original PS1 protocol: Inventory:InvokeServer("Delete", petId).
    -- Do NOT send undocumented MultiDelete packets or delete old inventory items.
    local removed=0
    for _,id in ipairs(removable) do
        if not eggSessionActive(epoch) then
            return false,wanted>0,"Остановлено до удаления следующего питомца"
        end
        -- Recheck immediately before EACH irreversible Delete, not just once for a batch.
        local _,_,verifyErr,nowSave=getEggInventory()
        if verifyErr or not nowSave then
            return false,wanted>0,"Нет свежих данных перед удалением ID "..id
        end
        local now=indexedPets(nowSave)[id]
        local orig=after[id]
        if not now or not orig or prior[id] or tonumber(now.id)~=id or
            tostring(now.n)~=tostring(orig.n) or eggFilter.keep[tostring(now.n)] or
            Z25.trueFlag(now.e) or Z25.classify(now)~="normal" or
            Z25.trueFlag(now.lock) or Z25.trueFlag(now.locked) or
            Z25.trueFlag(now.lk) or Z25.trueFlag(now.fav) then
            return false,wanted>0,"Защита: ID "..id.." изменился. Удаление остановлено."
        end
        local invoked,response=pcall(function()
            return inv:InvokeServer("Delete",id)
        end)
        if not invoked or response==false then
            return false,wanted>0,"Сервер отклонил Delete ID "..id..": "..tostring(response):sub(1,55)
        end
        local gone=false
        for check=1,5 do
            if not eggSessionActive(epoch) then
                return false,wanted>0,"Проверка удаления прервана пользователем"
            end
            task.wait(check==1 and .25 or .4)
            local _,_,readError,afterDelete=getEggInventory()
            if readError or not afterDelete then
                return false,wanted>0,"Нет подтверждения удаления ID "..id..": "..tostring(readError)
            end
            if not indexedPets(afterDelete)[id] then gone=true break end
        end
        if not gone then
            return false,wanted>0,"ID "..id.." остался после Delete. Остановлено БЕЗ повторной команды."
        end
        removed+=1
        eggFilter.deleted+=1
    end
    return true,wanted>0,string.format("Оставлено %d, удалено %d, защищено %d",wanted,removed,unknown)
end

-- Modes: 1, 3, 9 = exact number of separate purchases; "fill" = waves of up to 6;
-- "slow" = previous one-at-a-time auto fill. This is NOT a gamepass triple-hatch.
-- Delete is called ONLY by the separately armed selective filter, for verified newly hatched IDs.
local function startEggs(mode)
    if mode=="hunt" and eggFilter.mode~="active" then eggMessage="Охота требует включённого фильтра удаления" return end
    if eggFilter.mode~="off" and countKeepTypes()==0 then eggMessage="Сначала выбери питомцев, которых оставлять" return end
    if converting then eggMessage="Сначала останови преобразование питомцев" return end
    if eggRunning then eggMessage="Яйца уже покупаются; нажми СТОП" return end
    local _,shop=eggRemotes()
    if not shop then eggMessage="Не найден Game.Shop (RemoteFunction)" log(eggMessage,true) return end
    if mode~="fill" and mode~="slow" and mode~="hunt" and mode~=1 and mode~=3 and mode~=9 then
        eggMessage="Неизвестный режим" return
    end
    eggEpoch+=1
    local epoch=eggEpoch
    local key=eggKey(eggWorld,eggTier)
    local totalRequested=type(mode)=="number" and mode or (mode=="hunt" or eggFilter.mode=="active" and mode=="fill") and eggFilter.limit or nil
    local waveLimit=mode=="slow" and 1 or mode=="fill" and 6 or mode==9 and 9 or mode==3 and 3 or 1
    local waveDelay=mode=="slow" and .65 or .10
    eggRunning=true
    eggFilter.kept,eggFilter.deleted,eggFilter.protected,eggFilter.preview=0,0,0,0
    eggAttempts,eggOpened,eggConfirmed,eggRejected,eggBatches=0,0,0,0,0
    eggInventory,eggCapacity=nil,nil
    eggStarted=os.clock()
    eggMessage="Подготовка • "..key.." • "..(mode=="hunt" and "ОХОТА" or totalRequested and ("×"..totalRequested) or mode=="fill" and "ТУРБО ДО ПОЛНОГО" or "обычный режим")
    log("Яйца: "..key..", режим "..tostring(mode))
    -- Native inventory / Get Other Stats has previously frozen during heavy mining.
    -- Suspend outgoing mining while fast buying; do not override a user-initiated pause.
    if farming and not Z25.paused then
        Z25.paused=true
        eggPausedFarm=true
        log("Фарм временно поставлен на паузу на время покупки яиц")
    end
    task.spawn(function()
        local ok,err=pcall(function()
            local lastCount=nil
            while eggSessionActive(epoch) do
                local count,capacity,errorText,beforeSave=getEggInventory()
                if not eggSessionActive(epoch) then break end
                if errorText then eggMessage=errorText break end
                eggInventory,eggCapacity=count,capacity
                if lastCount==nil then lastCount=count end
                local free=math.max(0,math.floor(capacity-count))
                if free<=0 then
                    eggMessage="Инвентарь заполнен ("..count.."/"..capacity..")"
                    break
                end
                local left=totalRequested and math.max(0,totalRequested-eggAttempts) or free
                if left<=0 then
                    eggMessage="Покупка завершена: "..eggOpened.." питомцев"
                    break
                end
                local n=math.min(waveLimit,free,left)
                if n<=0 then break end
                eggBatches+=1
                eggMessage=string.format("%s • группа %d: отправляю %d; свободно %d",key,eggBatches,n,free)
                local completed,confirmed,rejected,errors=0,0,0,0
                local buyResults={}
                local reason=""
                -- Each request is a separate Buy; parallel calls minimize animation / round-trip cost.
                -- Stagger slightly, keep an upper bound, and await all results before next group.
                for i=1,n do
                    if not eggSessionActive(epoch) then break end
                    eggAttempts+=1
                    task.spawn(function()
                        local invoked,accepted,details=pcall(function()
                            return shop:InvokeServer("Buy","Eggs",key)
                        end)
                        if invoked and accepted==true then
                            confirmed+=1
                            buyResults[i]={accepted=true,pet=hatchResultPet(details)}
                        else
                            rejected+=1
                            if not invoked then errors+=1 end
                            if reason=="" then reason=tostring(accepted):sub(1,70) end
                        end
                        completed+=1
                    end)
                    if i<n then task.wait(.06) end
                end
                local sent=n
                local waitStarted=os.clock()
                while eggSessionActive(epoch) and completed<sent and os.clock()-waitStarted<15 do
                    task.wait(.12)
                end
                if not eggSessionActive(epoch) then break end
                if completed<sent then
                    eggMessage="Тайм-аут ответов сервера ("..completed.."/"..sent.."); остановлено. Ожидающие покупки ещё могут завершиться"
                    break
                end
                eggConfirmed+=confirmed
                eggRejected+=rejected
                -- Verify durable inventory rather than counting successful remote returns.
                local latest,cap,readErr,afterSave
                for tries=1,6 do
                    if not eggSessionActive(epoch) then break end
                    task.wait(tries==1 and .16 or .32)
                    latest,cap,readErr,afterSave=getEggInventory()
                    if readErr then break end
                    if latest and latest>=count+confirmed then break end
                    if confirmed==0 and latest then break end
                end
                if not eggSessionActive(epoch) then break end
                if readErr or not latest then
                    eggMessage="Не удалось подтвердить инвентарь: "..tostring(readErr)
                    break
                end
                eggInventory,eggCapacity=latest,cap
                local gained=math.max(0,latest-count)
                eggOpened+=gained
                eggMessage=string.format("%s • +%d питомцев • %d/%d • подтверждено: %d/%d",key,gained,latest,cap,confirmed,sent)
                if gained<confirmed or gained>sent then
                    eggMessage=eggMessage.." • данные не совпали; безопасная остановка"
                    break
                end
                if rejected>0 then
                    eggMessage=eggMessage.." • отказов: "..rejected.." ("..reason.."); остановлено"
                    break
                end
                if gained==0 then
                    eggMessage="Покупки не появились в серверном инвентаре; остановлено без повторов"
                    break
                end
                if eggFilter.mode~="off" and afterSave then
                    local good,found,detail=filterHatchedPets(beforeSave,afterSave,buyResults,confirmed,epoch)
                    eggFilter.last=detail
                    eggMessage=eggMessage.." • "..detail
                    if not good then break end
                    if mode=="hunt" and found then
                        eggMessage=eggMessage.." • ЦЕЛЬ НАЙДЕНА, ОСТАНОВЛЕНО"
                        break
                    end
                    local postCount,postCap,postErr=getEggInventory()
                    if postErr then eggMessage="Ошибка инвентаря после фильтра: "..postErr break end
                    eggInventory,eggCapacity=postCount,postCap
                end
                lastCount=latest
                if totalRequested and eggAttempts>=totalRequested then
                    eggMessage=eggMessage.." • готово"
                    break
                end
                if (eggFilter.mode=="off" or eggFilter.mode=="preview") and latest>=cap then
                    eggMessage=eggMessage.." • инвентарь заполнен"
                    break
                end
                task.wait(eggFilter.mode=="active" and .3 or waveDelay)
            end
        end)
        if epoch==eggEpoch then
            eggRunning=false
            finishEggFarmPause()
            if not ok then
                eggMessage="Ошибка покупки яиц: "..tostring(err):sub(1,100)
                log(eggMessage,true)
            else
                log("Яйца: "..eggMessage)
            end
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
Z25.readCurrentPetSave=readPetSave
-- Inventory auto-discovery: p.id is the unique numerical pet ID; p.l is level,
-- p.e says if a pet is equipped. The player name / display name are NOT unique IDs.
-- Archived PS1 script uses (pet level + equipped hat level) * 2 - 1 for Mine.
-- For a new/untrained pet that formula is UNVERIFIED on this server.
function Z25.numberId(v)
    local n=tonumber(v)
    if not n or n~=n or n<1 or n%1~=0 then return nil end
    return n
end
function Z25.numericPetLevel(p, save)
    local level=tonumber(p.l)
    if not level or level~=level or level<=0 then return nil end
    -- Historical source says hats add to pet level; no hat -> no bonus.
    local hatId=Z25.numberId(p.h)
    if hatId and type(save.Hats)=="table" then
        for _,hat in pairs(save.Hats) do
            if type(hat)=="table" and Z25.numberId(hat.id)==hatId then
                local bonus=tonumber(hat.l)
                if bonus and bonus>0 and bonus==bonus then level+=bonus end
                break
            end
        end
    end
    return level
end
function Z25.inventoryProfile(id,p,save)
    if learned[id] and learned[id].movement and #learned[id].samples>0 then
        return learned[id],true
    end
    local level=Z25.numericPetLevel(p,save)
    if not level then return nil,false end
    local damageArgument=2*level-1
    if damageArgument<=0 or damageArgument~=damageArgument then return nil,false end
    -- A fallback movement speed was observed for OTHER pets. This is a trial,
    -- not a trained per-pet packet and may be rejected by the game server.
    return {samples={damageArgument,damageArgument,damageArgument},
            movement={speed=4.7751576900482178},derived=true},false
end
function Z25.inventorySnapshot(mode)
    local save,err=readPetSave()
    if not save then return nil,err end
    local result,seen={},{}
    local count,eq,untrained=0,0,0
    for _,p in pairs(save.Pets) do
        if type(p)=="table" then
            local id=Z25.numberId(p.id)
            if id and not seen[id] then
                seen[id]=true
                count+=1
                local equipped=p.e==true
                if equipped then eq+=1 end
                if mode=="all" or equipped then
                    local profile,trained=Z25.inventoryProfile(id,p,save)
                    if profile then
                        if not trained then untrained+=1 end
                        result[#result+1]={id=id,profile=profile,equipped=equipped,trained=trained}
                    end
                end
            end
        end
    end
    table.sort(result,function(a,b) return a.id<b.id end)
    -- Rebuild from the current server inventory: old fused/deleted IDs are never kept.
    local ids={}
    for _,v in ipairs(result) do ids[#ids+1]=tostring(v.id) end
    local signature=table.concat(ids,",")
    if signature~=lastInventorySignature then
        lastInventorySignature=signature
        Z25.autoPets.rejected={}
        Z25.dynamicPoolCursor=0
    end
    Z25.autoPets.total=count Z25.autoPets.equipped=eq Z25.autoPets.ready=#result
    Z25.autoPets.last="Инвентарь: "..count.." • экипировано: "..eq.." • доступно: "..#result.." • расчёт по уровню: "..untrained
    if autoPetsLabel then autoPetsLabel.Text=Z25.autoPets.last end
    return result,nil
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
    -- Strict total ordering: the old mixed numeric/lexical comparator could
    -- say BOTH a < b and b < a, causing "invalid order function for sorting".
    table.sort(candidate.pets,function(a,b)
        local aa,bb=tonumber(a.id) or math.huge,tonumber(b.id) or math.huge
        if aa~=bb then return aa<bb end
        return tostring(a.id)<tostring(b.id)
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
        local eligible=0
        for _,stage in ipairs(stages) do
            local rule=UPGRADE[stage]
            for _,bucket in pairs(petGroups(save,rule.from)) do
                eligible+=math.floor(#bucket/rule.need)
            end
        end
        if eligible==0 then
            convertMessage="Нет подходящих питомцев (экипированные защищены). Преобразование не запущено."
            return
        end
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
    Z25.paused=false
    session+=1
    stats.workers=0
    table.clear(reserved)
    table.clear(lockedTargets)
end
-- Reserve a specific coin across round-robin batches. A live coin is never dropped
-- just because its remaining HP is lower than the current "HighHP" preference.
-- Only disappearance, leaving the chosen area, or repeated lack of progress unlocks it.
local function releaseLockedTarget(id,epoch)
    if epoch~=session then return end
    local lock=lockedTargets[id]
    if lock then
        if reserved[lock.coin]==id then reserved[lock.coin]=nil end
        lockedTargets[id]=nil
    end
end
Z25.coinCache={list={},at=-1e9,zone=nil}
local function claimCoin(id,minHP)
    local zoneKey=tostring(Z25.area or "rectangle")..":"..tostring(Z25.radius)..":"..cfg.minX..":"..cfg.minZ..":"..cfg.maxX..":"..cfg.maxZ
    local now=os.clock()
    if now-Z25.coinCache.at>1.0 or Z25.coinCache.zone~=zoneKey then
        local fresh=scan()
        Z25.coinCache={list=fresh,at=now,zone=zoneKey}
    end
    -- Sort a fresh view. The original cached data is not mutated by different workers.
    local options={}
    for _,coin in ipairs(Z25.coinCache.list) do options[#options+1]=coin end
    orderCoins(options)
    -- For inventory-wide mode use durable coins, otherwise a one-hit disappearance
    -- looks like no progress and cannot be attributed to this particular ID.
    if minHP then
        table.sort(options,function(a,b)
            local aa,bb=a.hp>=minHP,b.hp>=minHP
            if aa~=bb then return aa end
            return a.hp>b.hp
        end)
    end
    for _,info in ipairs(options) do
        if not reserved[info.object] and validCoin(info.object) then
            reserved[info.object]=id
            return info.object
        end
    end
    return nil
end
function Z25.mineForOne(epoch,id,profile,oneCoin)
    if not Z25.waitWhilePaused(epoch) then return nil,"Фарм уже остановлен" end
    local lock=lockedTargets[id]
    local coin
    if oneCoin then
        coin=oneCoin
    elseif lock and validCoin(lock.coin) and reserved[lock.coin]==id then
        -- This coin may now have only 1 HP. Still complete it before selecting another.
        coin=lock.coin
        stats.targetReused+=1
    else
        if lock then
            -- The previous coin vanished or left the farming area.
            stats.gone+=1
            releaseLockedTarget(id,epoch)
        end
        coin=claimCoin(id,Z25.autoPets.mode=="all" and profile.samples[1]*2 or nil)
        if coin then
            lockedTargets[id]={coin=coin,misses=0}
            stats.targetChanged+=1
        end
    end
    if not coin then return nil,"Нет свободных монет в зоне" end
    local p=partOf(coin)
    local before=health(coin)
    if not p or type(before)~="number" or before<=0 then
        releaseLockedTarget(id,epoch)
        return nil,"Нет доступного HP"
    end
    local _,mineRemote,petRemote=nodes()
    if not mineRemote or not petRemote then
        releaseLockedTarget(id,epoch)
        return nil,"Серверные события недоступны"
    end
    -- Each batch sends the existing, experimentally verified Mine packet sequence.
    -- No equip or trade commands are sent.
    if not Z25.waitWhilePaused(epoch) then return nil,"Фарм остановлен" end
    local ok,err=pcall(function()
        petRemote:FireServer({{"PetMovement",player,id,CFrame.new(p.Position),false,profile.movement.speed}})
    end)
    if not ok then
        releaseLockedTarget(id,epoch)
        return nil,"Movement: "..tostring(err):sub(1,75)
    end
    stats.move+=1
    task.wait(.06)
    for i=1,math.min(#profile.samples,5) do
        if not Z25.waitWhilePaused(epoch) or not validCoin(coin) then break end
        local arg=profile.samples[i]
        local sent,problem=pcall(function() mineRemote:FireServer("Mine",coin.Name,arg,id) end)
        if not sent then
            releaseLockedTarget(id,epoch)
            return nil,"Mine: "..tostring(problem):sub(1,75)
        end
        stats.mine+=1
        local petStats=stats.perPet[id]
        if not petStats then
            petStats={mine=0,damage=0,batches=0}
            stats.perPet[id]=petStats
        end
        petStats.mine+=1
        task.wait(cfg.interval)
    end
    task.wait(.35)
    if epoch~=session or not farming then return nil,"Фарм остановлен" end
    local after=health(coin)
    local delta=type(after)=="number" and math.max(0,before-after) or 0
    local vanished=not validCoin(coin)
    local petStats=stats.perPet[id]
    if delta>0 then
        stats.damage+=delta
        if petStats then
            petStats.damage+=delta
            petStats.batches+=1
        end
    end
    if vanished then
        -- The coin is gone (or HP reached zero); next batch may select another.
        stats.gone+=1
        releaseLockedTarget(id,epoch)
        if delta>0 then return true,delta end
        return nil,"Цель исчезла: HP за удар не подтверждён"
    end
    if delta>0 then
        -- Crucial fix: do NOT unlock an unfinished coin when a mining batch ends.
        if lockedTargets[id] then lockedTargets[id].misses=0 end
        return true,delta
    end
    -- A target may be blocked or the remote may be rejected. Only switch after
    -- two full batches without progress; never reselect due to low remaining HP.
    if lockedTargets[id] then
        lockedTargets[id].misses+=1
        if lockedTargets[id].misses>=2 then
            releaseLockedTarget(id,epoch)
            return false,"HP не уменьшился два цикла — меняю недоступную цель"
        end
    end
    return nil,"HP пока не изменился — сохраняю текущую цель"
end

local function active(epoch)
    return alive and farming and epoch==session
end
function Z25.waitWhilePaused(epoch)
    while active(epoch) and Z25.paused do task.wait(.12) end
    return active(epoch)
end
local progressLabel
local function worker(epoch,id)
    local profile=learned[id]
    local target=nil
    local misses,totalMisses=0,0
    while active(epoch) do
        if not Z25.waitWhilePaused(epoch) then break end
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
        if not Z25.waitWhilePaused(epoch) then break end
        local ok,err=pcall(function()
            petRemote:FireServer({{"PetMovement",player,id,CFrame.new(location),false,profile.movement.speed}})
        end)
        if not ok then log("Movement "..id..": "..tostring(err):sub(1,70),true) break end
        stats.move+=1
        task.wait(.06)
        local sent=0
        for j=1,math.min(#profile.samples,5) do
            if not Z25.waitWhilePaused(epoch) or not validCoin(target) then break end
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
-- A bounded round-robin scheduler: configurable 4/6/8/12, not all at once; hundreds of
-- inventory IDs are processed in batches rather than 1 worker for each pet.
function Z25.dynamicFarm(epoch)
    local lastUpdate=-1e9
    local pool={}
    while active(epoch) do
        if not Z25.waitWhilePaused(epoch) then break end
        local now=os.clock()
        -- Avoid contending with the game's inventory UI for Get Other Stats.
        if now-lastUpdate>=30 or #pool==0 then
            local list,err=Z25.inventorySnapshot(Z25.autoPets.mode)
            lastUpdate=now
            if list then
                pool=list
                if Z25.dynamicPoolCursor>#pool then Z25.dynamicPoolCursor=0 end
                -- Don't keep assignments for pets that have been fused or deleted.
                local present={}
                for _,item in ipairs(pool) do present[item.id]=true end
                for id,lock in pairs(lockedTargets) do
                    if not present[id] then releaseLockedTarget(id,epoch) end
                end
            else
                log("Ошибка обновления питомцев: "..tostring(err),true)
            end
        end
        if #pool==0 then
            log("Нет питомцев с числовым ID и уровнем для автообнаружения",true)
            break
        end
        local batch={}
        for n=1,#pool do
            Z25.dynamicPoolCursor=Z25.dynamicPoolCursor%#pool+1
            local item=pool[Z25.dynamicPoolCursor]
            if (Z25.autoPets.rejected[item.id] or 0)<3 then
                batch[#batch+1]=item
                if #batch>=Z25.autoPets.activeCount then break end
            end
        end
        if #batch==0 then
            log("Новые питомцы не смогли уменьшить HP. Проверь экипировку и уровень в инвентаре.",true)
            break
        end
        local pending=#batch
        stats.workers=pending
        stats.peakWorkers=math.max(stats.peakWorkers,pending)
        for _,item in ipairs(batch) do
            task.spawn(function()
                local succeeded,okOrErr,result=pcall(function()
                    return Z25.mineForOne(epoch,item.id,item.profile,nil)
                end)
                if succeeded and okOrErr==true then
                    if not Z25.autoPets.success[item.id] then Z25.autoPets.rotated+=1 end
                    Z25.autoPets.success[item.id]=(Z25.autoPets.success[item.id] or 0)+1
                    Z25.autoPets.rejected[item.id]=0
                    if progressLabel then
                        progressLabel.Text=string.format("Авто-ID: %d в инвентаре • HP −%.0f\nПитомец %s: −%.0f HP",Z25.autoPets.total,stats.damage,tostring(item.id),result)
                    end
                elseif succeeded and okOrErr==false then
                    Z25.autoPets.rejected[item.id]=(Z25.autoPets.rejected[item.id] or 0)+1
                    stats.noProgress+=1
                    if Z25.autoPets.rejected[item.id]>=3 then
                        log("ID "..item.id.." без подтверждённого уменьшения HP: "..tostring(result).." (проверь экипировку)")
                    end
                elseif succeeded and okOrErr==nil then
                    -- Disappeared or unavailable targets are not a proof of server rejection.
                    -- Do not permanently disable this pet on an ambiguous outcome.
                    -- All targets gone: retry on a fresh scan next batch.
                elseif not succeeded then
                    stats.clientErrors+=1
                    log("Ошибка ID "..item.id..": "..tostring(okOrErr):sub(1,65),true)
                    Z25.autoPets.rejected[item.id]=3
                end
                pending-=1
                if active(epoch) then stats.workers=pending end
            end)
        end
        while active(epoch) and pending>0 do task.wait(.12) end
        task.wait(.16)
    end
    if epoch==session then
        stats.workers=0
        farming=false
        log("Автообнаружение остановлено")
    end
end
-- Before enabling "ALL" verify *different* unequipped IDs on durable coins.
-- This is a direct packet experiment, not an Equip call and not a trade bypass.
function Z25.probeOneInventoryPet()
    if Z25.autoPets.checking then return end
    if farming or converting or eggRunning then
        log("Для проверки останови фарм, яйца и улучшение",true) return
    end
    Z25.autoPets.checking=true
    Z25.autoPets.probePassed=0
    Z25.autoPets.probeTried=0
    Z25.autoPets.probeDetails=""
    if autoPetsStatusLabel then autoPetsStatusLabel.Text="Проверка до 3 разных неэкипированных питомцев…" end
    task.spawn(function()
        local ok,reason=pcall(function()
            local list,problem=Z25.inventorySnapshot("all")
            if not list then
                Z25.autoPets.probeDetails="Ошибка инвентаря: "..tostring(problem)
                return
            end
            local candidates={}
            for _,item in ipairs(list) do
                if not item.equipped and item.profile and item.profile.samples and item.profile.samples[1] then
                    candidates[#candidates+1]=item
                end
            end
            table.sort(candidates,function(a,b)
                return a.profile.samples[1]<b.profile.samples[1]
            end)
            if #candidates==0 then
                Z25.autoPets.probeDetails="Нет неэкипированных питомцев с корректным уровнем"
                return
            end
            local _,mineRemote,petRemote=nodes()
            if not mineRemote or not petRemote then
                Z25.autoPets.probeDetails="Не найдены Coins/Pets RemoteEvent"
                return
            end
            local evidence={}
            local reservedForProbe={}
            local attempts=math.min(3,#candidates)
            for i=1,attempts do
                if not alive or farming or converting or eggRunning then
                    evidence[#evidence+1]="Проверка прервана"
                    break
                end
                local item=candidates[i]
                local damage=item.profile.samples[1]
                local options=scan()
                local target=nil
                local maxHP=0
                local needed=math.max(1000,damage*3)
                for _,info in ipairs(options) do
                    maxHP=math.max(maxHP,info.hp)
                    if info.hp>=needed and not reservedForProbe[info.object] then
                        if not target or info.hp<target.hp then target=info end
                    end
                end
                if not target then
                    evidence[#evidence+1]=string.format("ID %s: нет монеты HP >= %.0f (макс %.0f)",tostring(item.id),needed,maxHP)
                    -- Avoid pretending a weaker target is sufficient proof.
                    continue
                end
                reservedForProbe[target.object]=true
                local coin=target.object
                local base=health(coin)
                task.wait(.65)
                if not alive or not validCoin(coin) or health(coin)~=base then
                    evidence[#evidence+1]="ID "..tostring(item.id)..": HP меняется без теста / монета пропала"
                    continue
                end
                local pre=health(coin)
                local moved=pcall(function()
                    petRemote:FireServer({{"PetMovement",player,item.id,CFrame.new(target.pos),false,item.profile.movement.speed}})
                end)
                if not moved then
                    evidence[#evidence+1]="ID "..tostring(item.id)..": ошибка PetMovement"
                    continue
                end
                stats.move+=1
                task.wait(.10)
                local sent=pcall(function()
                    mineRemote:FireServer("Mine",coin.Name,damage,item.id)
                end)
                if not sent then
                    evidence[#evidence+1]="ID "..tostring(item.id)..": ошибка Mine"
                    continue
                end
                stats.mine+=1
                task.wait(.50)
                local post=health(coin)
                Z25.autoPets.probeTried+=1
                local delta=(type(pre)=="number" and type(post)=="number") and pre-post or nil
                if delta and delta>0 and math.abs(delta-damage)<math.max(2,damage*.001) then
                    Z25.autoPets.probePassed+=1
                    evidence[#evidence+1]=string.format("ID %s (НЕ экип.): HP -%.0f = Mine %.0f",tostring(item.id),delta,damage)
                elseif delta then
                    evidence[#evidence+1]=string.format("ID %s: HP %.0f -> %.0f (ожидалось -%.0f)",tostring(item.id),pre,post,damage)
                else
                    evidence[#evidence+1]="ID "..tostring(item.id)..": монета исчезла/HP недоступен"
                end
                task.wait(.20)
            end
            Z25.autoPets.probeDetails=table.concat(evidence," | ")
            local neededPasses=math.min(2,#candidates)
            if Z25.autoPets.probePassed>=neededPasses then
                Z25.autoPets.allVerified=true
                Z25.autoPets.mode="all"
                log("Проверено разных неэкипированных ID: "..Z25.autoPets.probePassed.."/"..Z25.autoPets.probeTried.."; включён ВЕСЬ ИНВЕНТАРЬ")
            else
                Z25.autoPets.allVerified=false
                Z25.autoPets.mode="equipped"
                log("Проверка ВСЕ: "..Z25.autoPets.probePassed.."/"..Z25.autoPets.probeTried.."; режим не включён")
            end
        end)
        if not ok then
            Z25.autoPets.allVerified=false
            Z25.autoPets.mode="equipped"
            Z25.autoPets.probeDetails="Ошибка проверки: "..tostring(reason):sub(1,130)
            log(Z25.autoPets.probeDetails,true)
        end
        Z25.autoPets.checking=false
        if autoPetsStatusLabel then
            local state=Z25.autoPets.allVerified and "✅ ВЕСЬ ИНВЕНТАРЬ ВКЛЮЧЁН" or "Нет подтверждения для режима ВСЕ"
            autoPetsStatusLabel.Text=state.." • "..Z25.autoPets.probePassed.."/"..Z25.autoPets.probeTried.." • подробности в отчёте"
        end
        if Z25.autoPets.syncButtons then Z25.autoPets.syncButtons() end
    end)
end

local function startFarm()
    if eggRunning then log("Дождись окончания покупки яиц",true) return end
    if converting then log("Дождись окончания преобразования питомцев",true) return end
    if farming then return end
    local ids={}
    if Z25.autoPets.mode=="saved" then
        local legacy,err=existingRecordedPets()
        if not legacy then log("Не удалось проверить старых питомцев: "..tostring(err),true) return end
        ids=legacy
        if #ids==0 then
            log("Старые питомцы уже скрещены. Переключаюсь на актуальных экипированных.")
            Z25.autoPets.mode="equipped"
            if Z25.autoPets.syncButtons then Z25.autoPets.syncButtons() end
        end
    end
    if Z25.autoPets.mode=="all" and not Z25.autoPets.allVerified then
        log("Сначала проверь неэкипированного питомца",true) return
    end
    if Z25.autoPets.mode~="saved" then
        local list,err=Z25.inventorySnapshot(Z25.autoPets.mode)
        if not list or #list==0 then
            log("Авто-ID: "..tostring(err or "нет подходящих питомцев"),true) return
        end
    end
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
    Z25.paused=false
    table.clear(reserved)
    table.clear(lockedTargets)
    stats.damage=0 stats.gone=0 stats.noProgress=0 stats.mine=0 stats.move=0 stats.clientErrors=0
    stats.targetReused=0 stats.targetChanged=0 stats.perPet={} stats.peakWorkers=0 stats.started=os.clock()
    if Z25.autoPets.mode~="saved" then
        Z25.autoPets.rejected={} Z25.autoPets.success={} Z25.autoPets.rotated=0
        stats.workers=0
        if progressLabel then progressLabel.Text="Авто-ID: "..Z25.autoPets.last.."\nПроверяю HP каждого питомца…" end
        log("Авто-ID "..Z25.autoPets.mode..": "..Z25.autoPets.ready.." питомцев в очереди; до "..Z25.autoPets.activeCount.." задач одновременно; цель удерживается до завершения")
        task.spawn(function()
            local ok,err=pcall(Z25.dynamicFarm,epoch)
            if not ok then
                log("Ошибка динамического фарма: "..tostring(err):sub(1,70),true)
                if epoch==session then farming=false stats.workers=0 end
            end
        end)
        return
    end
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

-- ZoneHub 3.1 UI | original Roblox thumbnail icon, no third-party URL.
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
label(top,"3.2  •  PET SIMULATOR 2018",49,20,10,C.dim,true)
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
local farmActions=card(farm,129)
local startButton=button(farmActions,"▶  ЗАПУСТИТЬ АВТОФАРМ",13,function()
    if farming then stopFarm() log("Автофарм остановлен") else startFarm() end
end,C.blue)
Z25.pauseButton=button(farmActions,"Ⅱ  ПАУЗА ДЛЯ ИНВЕНТАРЯ",68,function()
    if eggRunning then log("Покупка яиц выполняется — фарм на автоматической паузе",true) return end
    if not farming then log("Фарм уже остановлен — можно открыть инвентарь") return end
    Z25.paused=not Z25.paused
    if Z25.paused then
        log("Фарм на паузе: исходящие Mine/Movement приостановлены; открой инвентарь")
    else
        log("Фарм продолжен после инвентаря")
    end
end,C.panel2)
Z25.uiCard=card(farm,196,C.green)
label(Z25.uiCard,"📍  Локация для Auto Farm",9,26,14,C.white,true)
Z25.areaLabel=label(Z25.uiCard,"Исходная зона (прямоугольник)",35,42,12,C.gold,true)
button(Z25.uiCard,"ФАРМИТЬ В ИСХОДНОЙ ЗОНЕ",80,function()
    if farming then stopFarm() end
    Z25.area=nil
    log("Выбрана исходная прямоугольная зона")
end,C.blue)
label(Z25.uiCard,"Другую локацию выбери в «Телепорт» → «Фармить здесь». Сохрани точку заранее. Радиус меняется в настройках.",130,53,11,C.dim)
do
local autoCard=card(farm,274,C.purple)
label(autoCard,"🐾  Питомцы для фарма",8,27,15,C.white,true)
autoPetsLabel=label(autoCard,"Авто: текущие экипированные питомцы (обновление каждые 8 сек)",38,45,12,C.dim)
local modeButtons={}
local function setPetMode(mode)
    if Z25.autoPets.checking then log("Дождись окончания теста питомца",true) return end
    if farming then stopFarm() log("Фарм остановлен для переключения питомцев") end
    Z25.autoPets.mode=mode
    if Z25.autoPets.syncButtons then Z25.autoPets.syncButtons() end
    autoPetsStatusLabel.Text=(mode=="saved" and "Только сохранившиеся старые экипированные ID — без удалённых" or
        mode=="equipped" and "Текущие экипированные определяются автоматически и обновляются каждые 8 сек" or
        "ВЕСЬ инвентарь: цель удерживается до исчезновения; задач: "..Z25.autoPets.activeCount)
end
local savedModeButton=button(autoCard,"СТАРЫЕ (ЕСЛИ ЕСТЬ)",91,function() setPetMode("saved") end,C.panel2)
savedModeButton.Position=UDim2.new(0,12,0,91)
savedModeButton.Size=UDim2.new(.5,-17,0,39)
modeButtons[#modeButtons+1]={button=savedModeButton,mode="saved"}
local equippedModeButton=button(autoCard,"АВТО: ЭКИП.",91,function() setPetMode("equipped") end,C.blue)
equippedModeButton.Position=UDim2.new(.5,5,0,91)
equippedModeButton.Size=UDim2.new(.5,-17,0,39)
modeButtons[#modeButtons+1]={button=equippedModeButton,mode="equipped"}
Z25.autoPets.syncButtons=function()
    for _,item in ipairs(modeButtons) do
        tween(item.button,{BackgroundColor3=item.mode==Z25.autoPets.mode and C.blue or C.panel2},.20)
    end
    if Z25.autoPets.allButton then
        tween(Z25.autoPets.allButton,{BackgroundColor3=Z25.autoPets.mode=="all" and C.blue or C.purple},.20)
    end
end
local allModeButton=button(autoCard,"АВТО: ВЕСЬ ИНВЕНТАРЬ",138,function()
    if Z25.autoPets.allVerified then setPetMode("all")
    else Z25.probeOneInventoryPet() end
end,C.purple)
Z25.autoPets.allButton=allModeButton
allModeButton.Position=UDim2.new(0,12,0,138)
allModeButton.Size=UDim2.new(1,-24,0,41)
button(autoCard,"ОБНОВИТЬ СПИСОК",186,function()
    if farming then log("Список автоматически обновляется каждые 8 сек") return end
    local list,err=Z25.inventorySnapshot(Z25.autoPets.mode=="saved" and "equipped" or Z25.autoPets.mode)
    if not list then log("Чтение питомцев: "..tostring(err),true)
    else log("Найдено питомцев: "..Z25.autoPets.total..", экипировано: "..Z25.autoPets.equipped) end
end,C.panel2)
autoPetsStatusLabel=label(autoCard,"ВСЕ: сначала тест 2 разных неэкипированных питомцев на прочных монетах",234,36,11,C.dim)
end -- auto-pet UI scope
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
local concurrencyCard=card(farm,122,C.green)
label(concurrencyCard,"⚙  Параллельные задачи (весь инвентарь)",9,29,13,C.white,true)
label(concurrencyCard,"При зависаниях инвентаря: 4 задачи и кнопка ПАУЗА.",33,32,10,C.dim)
local concurrencyOptions={4,6,8,12}
local concurrencyButtons={}
for i,count in ipairs(concurrencyOptions) do
    local b=button(concurrencyCard,tostring(count),76,function()
        if farming then log("Останови Auto Farm перед сменой параллельности",true) return end
        Z25.autoPets.activeCount=count
        for _,v in ipairs(concurrencyButtons) do
            tween(v.btn,{BackgroundColor3=v.count==count and C.blue or C.panel2},.18)
        end
        log("Одновременно задач: "..count.." (из всех питомцев в очереди)")
    end,count==4 and C.blue or C.panel2)
    b.Position=UDim2.new((i-1)/4,6,0,76)
    b.Size=UDim2.new(.25,-9,0,36)
    concurrencyButtons[#concurrencyButtons+1]={btn=b,count=count}
end
local report=card(farm,158)
label(report,"Статистика фарма",9,24,14,C.white,true)
progressLabel=label(report,"Профилей: "..profileCount().."/4",40,63,12,C.white)
local function farmReport()
    return table.concat({
        "ZoneHub v3.0 | Автофарм",
        "Активен: "..tostring(farming).." | Пауза: "..tostring(Z25.paused).." | Потоков: "..stats.workers,
        string.format("HP снято: %.3f | исчезло целей: %d | без прогресса: %d",stats.damage,stats.gone,stats.noProgress),
        "Mine: "..stats.mine.." | PetMovement: "..stats.move,
        string.format("HP/сек (среднее): %.1f | лимит задач: %d | пик задач: %d",stats.damage/math.max(1,os.clock()-stats.started),Z25.autoPets.activeCount,stats.peakWorkers),
        "Цели: назначено "..stats.targetChanged.." | продолжено "..stats.targetReused.." | закреплено сейчас "..(function() local n=0 for _ in pairs(lockedTargets) do n+=1 end return n end)(),
        "Режим: "..Z25.autoPets.mode.." | исторических профилей: "..profileCount().."/4 | "..storageStatus,
        "Инвентарь: "..Z25.autoPets.total.." | экипировано: "..Z25.autoPets.equipped.." | в очереди: "..Z25.autoPets.ready.." | ID с уменьшением HP: "..tostring(Z25.autoPets.rotated),
        "Проверка вне экипировки: "..Z25.autoPets.probePassed.."/"..Z25.autoPets.probeTried.." | "..Z25.autoPets.probeDetails,
        "Зона: "..Z25.areaDescription().." | прямоугольник X: "..cfg.minX..".."..cfg.maxX.."; Z: "..cfg.minZ..".."..cfg.maxZ,
        "Состояние: "..progressLabel.Text,
        "Урон по питомцам (топ-12): "..(function()
            local rows={}
            for id,data in pairs(stats.perPet) do
                rows[#rows+1]={id=id,damage=data.damage,mine=data.mine}
            end
            table.sort(rows,function(a,b) return a.damage>b.damage end)
            local out={}
            for i=1,math.min(12,#rows) do
                local v=rows[i]
                out[#out+1]=tostring(v.id).." −"..math.floor(v.damage).." HP ("..v.mine.." Mine)"
            end
            return #out>0 and table.concat(out,"; ") or "нет подтверждённого урона"
        end)(),
        "Журнал: "..table.concat(logLines," | ")
    },"\n")
end
button(report,"Копировать отчёт фарма",103,function()
    if type(setclipboard)~="function" then log("Буфер Delta недоступен",true) return end
    local ok=pcall(setclipboard,farmReport())
    log(ok and "Отчёт скопирован" or "Ошибка копирования",not ok)
end)

-- EGGS: Worlds 1, Moon, and seasonal Winter Wonderland.
do -- egg widgets have their own local scope; prevent main-chunk local overflow
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
local eggActions=card(eggs,341,C.green)
label(eggActions,"Быстрая покупка яиц",9,26,14,C.white,true)
button(eggActions,"🥚  ОДНО ЯЙЦО",37,function() startEggs(1) end,C.blue)
button(eggActions,"⚡  КУПИТЬ ×3",84,function() startEggs(3) end,C.purple)
button(eggActions,"⚡⚡  КУПИТЬ ×9 (9 ОТДЕЛЬНЫХ)",131,function() startEggs(9) end,C.purple)
button(eggActions,"🚀  ТУРБО: ДО ПОЛНОГО (ГРУППЫ ПО 6)",178,function() startEggs("fill") end,C.green)
button(eggActions,"▶  ОБЫЧНО: ДО ПОЛНОГО",225,function() startEggs("slow") end,C.blue)
button(eggActions,"■  ОСТАНОВИТЬ ПОКУПКИ",272,function() stopEggs("Покупки остановлены") log("Яйца остановлены") end,C.red)
label(eggActions,"×3/×9 — несколько отдельных запросов, не игровой тройной пропуск. При СТОП уже отправленные покупки могут завершиться.",311,27,10,C.dim)
local eggStats=card(eggs,157)
label(eggStats,"Открытие · статус",9,24,14,C.white,true)
eggStatusLabel=label(eggStats,"Ожидаю запуска",34,75,12,C.dim)
eggCountLabel=label(eggStats,"Попыток: 0 • Инвентарь: ?",116,27,11,C.gold,true)


-- SAFE EGG FILTER: chooses PET TYPE (p.n), not the random hatch outcome.
-- Default OFF; PREVIEW never deletes; ACTIVE needs double confirmation.
local filterCard=card(eggs,478,C.gold)
label(filterCard,"🎯  Оставлять выбранных питомцев",8,26,14,C.white,true)
label(filterCard,"Выбери типы ниже. Поиск по имени / коду.",34,21,11,C.dim)
local filterSearch=entry(filterCard,"Поиск в каталоге типов",61,"",function()end)
filterSearch.Text="" filterSearch.PlaceholderText="Например: Agony, Dominus, 18006"
local filterPage=1
local filteredTypes={}
local filterRows={}
local filterPerPage=5
local filterPageLabel=label(filterCard,"",367,20,11,C.dim)
local updateFilterCatalog
local function toggleKeeper(code)
    if eggRunning then eggFilter.last="Останови покупку перед выбором питомцев" return end
    eggFilter.keep[code]=not eggFilter.keep[code]
    eggFilter.pendingAt=0
    if eggFilter.mode=="active" then
        eggFilter.mode="preview" -- changes require re-confirmation
        eggFilter.last="Выбор изменён: автоудаление сброшено до предпросмотра"
    end
    updateFilterCatalog()
end
for i=1,filterPerPage do
    local b=button(filterCard,"",111+(i-1)*46,function()
        local choice=filteredTypes[(filterPage-1)*filterPerPage+i]
        if choice then toggleKeeper(choice.code) end
    end,C.panel2)
    b.Size=UDim2.new(1,-28,0,40)
    filterRows[i]=b
end
local filterPrev=button(filterCard,"◀",389,function()
    filterPage=math.max(1,filterPage-1) updateFilterCatalog()
end)
filterPrev.Size=UDim2.new(.49,-22,0,34)
local filterNext=button(filterCard,"▶",389,function()
    filterPage+=1 updateFilterCatalog()
end)
filterNext.Position=UDim2.new(.51,4,0,389)
filterNext.Size=UDim2.new(.49,-22,0,34)
local filterSelection=label(filterCard,"Ничего не выбрано",428,39,11,C.gold,true)
function updateFilterCatalog()
    local search=string.lower((filterSearch.Text:gsub("^%s+",""):gsub("%s+$","")))
    filteredTypes={}
    for _,item in ipairs(petTypesSorted) do
        if search=="" or string.find(string.lower(item.name),search,1,true) or string.find(item.code,search,1,true) then
            filteredTypes[#filteredTypes+1]=item
        end
    end
    local maxPage=math.max(1,math.ceil(#filteredTypes/filterPerPage))
    filterPage=math.clamp(filterPage,1,maxPage)
    for i,b in ipairs(filterRows) do
        local data=filteredTypes[(filterPage-1)*filterPerPage+i]
        b.Visible=data~=nil
        if data then
            local kept=eggFilter.keep[data.code]
            b.Text=(kept and "✓  " or "□  ")..data.name.."  ["..data.code.."]"
            b.BackgroundColor3=kept and C.green or C.panel2
        end
    end
    filterPageLabel.Text=string.format("Найдено: %d • страница %d/%d",#filteredTypes,filterPage,maxPage)
    filterSelection.Text=string.format("Сохранять (%d): %s",countKeepTypes(),keepSummary()~="" and keepSummary() or "не выбрано")
end
connections[#connections+1]=filterSearch:GetPropertyChangedSignal("Text"):Connect(function()
    filterPage=1 updateFilterCatalog()
end)
updateFilterCatalog()

local filterActions=card(eggs,309,C.gold)
label(filterActions,"Автофильтр после покупки",8,25,14,C.white,true)
local previewFilterButton=button(filterActions,"👁  ПРЕДПРОСМОТР (без удаления)",37,function()
    if eggRunning then eggFilter.last="Сначала останови открытие яиц" return end
    if countKeepTypes()<1 then eggFilter.last="Выбери хотя бы один тип" return end
    eggFilter.mode="preview" eggFilter.pendingAt=0
    eggFilter.last="Предпросмотр включён. Никаких удалений."
end,C.blue)
Z25.activeFilterButton=button(filterActions,"🗑  ВКЛЮЧИТЬ АВТОУДАЛЕНИЕ (2 НАЖАТИЯ)",84,function()
    if eggRunning then eggFilter.last="Сначала останови открытие яиц" return end
    if countKeepTypes()<1 then eggFilter.last="Сначала выбери тип питомца для сохранения" return end
    if eggFilter.mode=="active" then
        eggFilter.mode="off" eggFilter.last="Автоудаление выключено" eggFilter.pendingAt=0
    elseif eggFilter.pendingAt>0 and os.clock()-eggFilter.pendingAt<=9 then
        eggFilter.mode="active" eggFilter.pendingAt=0
        eggFilter.last="АВТОУДАЛЕНИЕ ВКЛ: только новые питомцы из покупки!"
    else
        eggFilter.pendingAt=os.clock()
        eggFilter.last="Для включения необратимого удаления НАЖМИ ЕЩЁ РАЗ в течение 9 секунд"
    end
end,C.red)
button(filterActions,"■  ВЫКЛЮЧИТЬ ФИЛЬТР",131,function()
    if eggRunning then stopEggs("Остановка: фильтр отключается после завершения запросов") end
    eggFilter.mode="off" eggFilter.pendingAt=0
    eggFilter.last="Фильтр выключен. Уже отправленные команды удаления нельзя отменить."
end,C.panel2)
button(filterActions,"🎯  ОХОТА ДО ПЕРВОГО НУЖНОГО",178,function()
    startEggs("hunt")
end,C.purple)
entry(filterActions,"Максимум покупок в охоте / турбо (1–200)",226,eggFilter.limit,function(value)
    if eggRunning then eggFilter.last="Изменяй лимит только после остановки покупок" return end
    eggFilter.limit=math.clamp(math.floor(tonumber(value) or eggFilter.limit),1,200)
    eggFilter.last="Лимит покупок за запуск: "..eggFilter.limit
end)
local filterStatus=card(eggs,152)
label(filterStatus,"Фильтр · статус",9,26,14,C.white,true)
eggFilterLabel=label(filterStatus,"Фильтр выключен",34,106,11,C.dim)

end -- egg widgets

-- UPGRADES: streamlined UI, no destructive action before explicit double tap.
do -- upgrade widgets (scoped locals)
local upgrades=pages["Улучшение"]
local upgradeHero=card(upgrades,70,C.gold)
label(upgradeHero,"✦  Улучшить питомцев",9,28,17,C.white,true)
label(upgradeHero,"10 обычных → Gold  •  7 Gold → Rainbow  •  5 Rainbow → Dark",35,27,11,C.dim)
local previewCard=card(upgrades,144,C.blue)
label(previewCard,"Доступно для объединения",8,25,13,C.white,true)
upgradePreviewLabel=label(previewCard,"Нажми «Проверить»",33,60,12,C.dim)
button(previewCard,"⟳  ПРОВЕРИТЬ",94,function() refreshUpgradePreview() end,C.blue)
local actionCard=card(upgrades,294,C.gold)
label(actionCard,"Преобразование",7,25,14,C.white,true)
button(actionCard,"★  В ЗОЛОТЫХ",37,function() confirmUpgrade({"gold"}) end,C.gold)
button(actionCard,"✦  В РАДУЖНЫХ",87,function() confirmUpgrade({"rainbow"}) end,C.purple)
button(actionCard,"◆  В DARK MATTER",137,function() confirmUpgrade({"dark"}) end,C.cyan)
button(actionCard,"⇧  ВСЯ ЦЕПОЧКА",187,function() confirmUpgrade({"gold","rainbow","dark"}) end,C.blue)
local stopUpButton=button(actionCard,"■  СТОП",239,function()
    stopUpgrades("Преобразование остановлено. Последняя операция могла завершиться на сервере.")
end,C.red)
stopUpButton.Size=UDim2.new(1,-28,0,35)
local stateCard=card(upgrades,126)
label(stateCard,"Результат",7,23,13,C.white,true)
upgradeStatusLabel=label(stateCard,"Готово",33,84,12,C.dim)
local protectNote=card(upgrades,65,C.green)
label(protectNote,"🛡  Экипированные и 4 питомца фарма защищены.",7,50,11,C.dim)

end -- upgrade widgets

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
    -- Never scan thousands of Roblox coin objects while UI is merely open.
    -- The scan is needed for farm start / target selection, not inventory screens.
    -- Heavy periodic workspace scans were competing with the native inventory GUI.
    -- Mining still scans coins when it needs a new target, using a short cache.
    coinCount.Text=farming and (Z25.paused and "Монеты: фарм на паузе" or "Монеты: проверка при выборе цели") or "Монеты проверяются при запуске фарма"
    if Z25.areaLabel then Z25.areaLabel.Text=Z25.areaDescription() end
    local eggSymbol=eggRunning and "● ОТКРЫВАЕТ" or "● ОЖИДАНИЕ"
    eggStatusLabel.Text=eggSymbol.."\n"..eggMessage
    eggStatusLabel.TextColor3=eggRunning and C.green or C.dim
    eggCountLabel.Text="Запросов: "..eggAttempts.." • новых: "..eggOpened.." • отказов: "..eggRejected.." • инв.: "..(eggInventory and (eggInventory.."/"..(eggCapacity or "?")) or "?")
    eggFilterLabel.Text="Режим: "..eggFilter.mode.." • оставить: "..countKeepTypes().." типов\nСохранено: "..eggFilter.kept.." • удалено: "..eggFilter.deleted.." • защищено: "..eggFilter.protected.." • без удаления: "..eggFilter.preview.."\n"..eggFilter.last
    eggFilterLabel.TextColor3=eggFilter.mode=="active" and C.gold or C.dim
    Z25.activeFilterButton.Text=eggFilter.mode=="active" and "■  АВТОУДАЛЕНИЕ ВКЛ (НАЖМИ ВЫКЛ)" or "🗑  ВКЛЮЧИТЬ АВТОУДАЛЕНИЕ (2 НАЖАТИЯ)"
    workLabel.Text=farming and (Z25.paused and "Ⅱ  ФАРМ НА ПАУЗЕ" or ("●  ФАРМ: "..stats.workers.." ЗАДАЧ")) or "●  ОСТАНОВЛЕН"
    Z25.pauseButton.Text=Z25.paused and "▶  ПРОДОЛЖИТЬ ФАРМ" or "Ⅱ  ПАУЗА ДЛЯ ИНВЕНТАРЯ"
    Z25.pauseButton.BackgroundColor3=Z25.paused and C.green or C.panel2
    workLabel.TextColor3=farming and C.green or C.red
    livePill.Text=converting and "● UP" or farming and "● FARM" or eggRunning and "● EGGS" or "● IDLE"
    livePill.TextColor3=(farming or eggRunning or converting) and C.green or C.dim
    startButton.Text=farming and "■  ОСТАНОВИТЬ АВТОФАРМ" or "▶  ЗАПУСТИТЬ АВТОФАРМ"
    startButton.BackgroundColor3=farming and C.red or C.blue
    profileLabel.Text="Старые профили: "..profileCount().."/4 (только при совпадении ID)\n"..storageStatus
    upgradeStatusLabel.Text=(converting and "● ИДЁТ • " or "● ГОТОВО • ")..convertMessage.."\nПодтверждено улучшений: "..convertCompleted
    upgradeStatusLabel.TextColor3=converting and C.green or C.dim
    if not farming then
        progressLabel.Text=string.format("Режим: %s • HP: %.0f\nMine: %d • Movement: %d • Ошибок: %d",Z25.autoPets.mode,stats.damage,stats.mine,stats.move,stats.clientErrors)
    end
end
connections[#connections+1]=RunService.Heartbeat:Connect(function()
    if not alive or not gui.Parent then return end
    local now=os.clock()
    if now-lastRefresh>=2.0 then lastRefresh=now refresh() end
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
log("v3.2.1: исправлен запуск; фильтр питомцев из яиц, удаление новых ID; старых профилей "..profileCount().."; локаций "..countTeleports().."/14")
