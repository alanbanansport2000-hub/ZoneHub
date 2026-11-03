-- ZoneHub 4.3 AUTO ID / HATS TIER 1-5 / CONTINUOUS EGG QUEUE | based on working 4.2
-- Game protocol for paid present buy is inferred from Shop Buy Eggs; any purchase requires double confirmation.
-- Hat delete uses an inferred remote and requires server confirmation; OFF until manually armed.
-- No unverified pet duplication, infinite equip or gamepass ownership changes.
-- ZoneHub 4.0 ALPHA CLEAN | built from ZoneHub 3.7.0 with no companion or external UI libraries
-- Original v3.7 farming, eggs, upgrading, inventory and remote protocols preserved.
-- Clean Beta CLONER-SAFE: server Pet Cloner support and inventory-safe queue. No gamepass bypass.
-- Clean Beta FASTFIX: adaptive egg purchase queue and optional farm suspension; 1-6 egg targets, x100 and Teleport retained.
-- 4.0 clean-up: no redundant farm-here/teleport in FARM; native Teleport has its own tab;
-- simplified settings, diagnostics, small HP/s history and visible error notifications.
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
-- Remove any stale error banner from a prior failed ZoneHub start.
local priorErrorHint = workspace:FindFirstChild("ZoneHub_StartError")
if priorErrorHint then priorErrorHint:Destroy() end

-- Stop prior ZoneHub workers BEFORE destroying the old GUI.
if type(getgenv)=="function" then
    local env=getgenv()
    if type(env.ZoneHubShutdown)=="function" then pcall(env.ZoneHubShutdown) end
    -- Cleanly close the deprecated companion overlay when updating from 4.0 alpha.
    if type(env.ZoneHubAlphaShutdown)=="function" then pcall(env.ZoneHubAlphaShutdown) end
    -- Legacy v1.2-v1.4 capture could remain installed until Roblox fully restarts.
    -- At least disable recording; do not try to override or chain a second hook.
    if type(env.__ZoneHubManualCapture)=="table" then
        env.__ZoneHubManualCapture.recording=false
    end
end
local priorOverlay=pg:FindFirstChild("ZoneHub_40_Zoni")
if priorOverlay then priorOverlay:Destroy() end
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
Z25.farmWorld="Earth"
Z25.worldAnchors={}  -- legacy UI position points are NOT used for world-wide farming
Z25.farmZones={
 {id="earth1",name="Стартовая",world="Earth"},{id="earth2",name="Призрачный лес",world="Earth"},
 {id="earth3",name="Снежные горы",world="Earth"},{id="earth4",name="Лавовые пики",world="Earth"},
 {id="earth5",name="Плазменная",world="Earth"},{id="earth6",name="Аврора (грибы)",world="Earth"},
 {id="moon1",name="Лунная база",world="Moon"},{id="moon2",name="Розовая планета",world="Moon"},
 {id="moon3",name="Конфетная земля",world="Moon"},{id="moon4",name="Техно-долина",world="Moon"},
 {id="moon5",name="Храм Dominus",world="Moon"},
 {id="winter1",name="Зима 1",world="Winter"},{id="winter2",name="Зима 2",world="Winter"},
 {id="winter3",name="Зима 3",world="Winter"}
}
Z25.nearPoint=nil
Z25.currency={}
Z25.currencyStart={}
Z25.paused=false -- pause outgoing Mine/Movement while accessing native inventory
-- Farm area: default rectangle, or circle around a saved teleport point.
Z25.area="world" -- farm every loaded zone in one chosen world
Z25.point=nil
Z25.areaLabel=nil
Z25.radius=420
Z25.coverageVisits={}
Z25.coverageSectors=0
function Z25.areaDescription()
    if Z25.area=="world" then
        local names={Earth="Земля — все зоны",Moon="Луна — все зоны",Winter="Зима — все зоны"}
        return names[Z25.farmWorld] or "Выбери мир"
    end
    if not Z25.area then return "Локация не выбрана" end
    for _,zone in ipairs(Z25.farmZones) do if zone.id==Z25.area then return zone.name end end
    return "Неизвестная зона"
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
local eggAdditionalPets, eggConfirmedMultiplier = 0, nil -- read-only server observations
local eggPausedFarm=false -- compatibility only; no auto-pausing of farm
local eggPausePrevious=false
local eggPauseFarmEnabled=false
local eggPerfMode="auto" -- auto 12 / fast 24 / turbo 36 requests per verified wave; does not change server odds.
local eggActiveBatch=0
local eggWaveSeconds=0
local fpsValue=0 -- populated by read-only FPS monitor below
local eggPerfButton, eggFarmPauseButton
local eggMessage = "Выбери мир и яйцо. Покупка не запущена"

-- Pet type codes (p.n), not unique inventory IDs (p.id). Published original-game map.
-- Unknown p.n values are always protected, even in automatic delete mode.
Z25.PET_TYPE_NAMES={
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
-- Known obtainable regular egg types, not the full legacy catalog.
-- Rarity labels are shown only when individually verified (Tier 1).
Z25.EGG_CONTENTS={
 World1={
  [1]={1001,1002,1003,1004,1005},[2]={2001,2002,2003,2004,2005},
  [3]={3001,3002,3003,3004,3005},[4]={4001,4002,4003,4004,4005},
  [5]={5001,5002,5003,5004,5005},[6]={6001,6002,6003,6004},
  [7]={7001,7002,7003,7004},[8]={8001,8002,8003,8004,8005},
  [9]={9001,9002,9003,9004,9005},
  [10]={10001,10002,10003,10004,10005,10006,10007,10008},
  [11]={11001,11002,11003,11004,11005,11006},
  [12]={12001,12002,12003,12004,12005,12006,12007}},
 Moon={
  [13]={13001,13002,13003,13004,13005,13006,13007},
  [14]={14001,14002,14003,14004,14005,14006,14007,14008,14009},
  [15]={15001,15002,15003,15004,15005,15006,15007,15008,15009,15010,15011},
  [16]={16001,16002,16003,16004,16005,16006,16007,16008,16009,16010,16011,16012},
  [17]={17001,17002,17003,17004,17005,17006,17007,17008,17009},
  [18]={18001,18002,18003,18004,18005,18006}},
 Winter={
  [1]={76001,76002,76003,76004},[2]={77001,77002,77003,77004},
  [3]={78001,78002,78003,78004,78005},[4]={79001,79002,79003,78005}}
}
Z25.petTypesSorted={}
for code,name in pairs(Z25.PET_TYPE_NAMES) do
    Z25.petTypesSorted[#Z25.petTypesSorted+1]={code=tostring(code),name=name}
end
table.sort(Z25.petTypesSorted,function(a,b)
    local an,bn=string.lower(a.name),string.lower(b.name)
    return an==bn and tonumber(a.code)<tonumber(b.code) or an<bn
end)
Z25.eggFilter={mode="off",keep={},kept=0,deleted=0,protected=0,preview=0,
    limit=30,last="Фильтр выключен. Сначала выбери нужного питомца.",pendingAt=0}
Z25.eggFilterLabel=nil
-- Optional explicit long-running egg modes. Never change hatch probabilities.
-- Conversion tracking contains ONLY pets created in the current auto-fuse run.
Z25.eggFusion={tracked={},limit=math.huge,done=0,last="Автоскрещивание не запускалось",blocked=0,fuseType=nil,allowExisting=false}
Z25.eggFusionLabel=nil
function Z25.countKeepTypes()
    local count=0
    for _,selected in pairs(Z25.eggFilter.keep) do if selected then count+=1 end end
    return count
end
function Z25.keepSummary()
    local list={}
    for _,t in ipairs(Z25.petTypesSorted) do
        if Z25.eggFilter.keep[t.code] then list[#list+1]=t.name end
    end
    return table.concat(list,", ")
end
function Z25.petNameForType(typeCode)
    return Z25.PET_TYPE_NAMES[tonumber(typeCode)]
end
Z25.inventory={count=nil,capacity=nil,normal=0,gold=0,rainbow=0,dark=0,equipped=0,updated="не проверен",lines=""}
Z25.inventoryLabel, Z25.inventoryDetails, Z25.eggLabel = nil,nil,nil
-- A separate inventory viewer lists actual unique Save.Pets IDs. Native Roblox UI is left untouched.
Z25.petIDViewer={items={},page=1,selected=nil,refresh=nil,display=nil}
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
    -- Currency keys are optional: only exact numeric Save fields may be displayed.
    local currencies={Coins="Земля",MoonCoins="Луна",SnowCoins="Зима"}
    for key,_ in pairs(currencies) do
        if type(save[key])=="number" then
            Z25.currency[key]=save[key]
            if type(Z25.currencyStart[key])~="number" then Z25.currencyStart[key]=save[key] end
        end
    end
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
Z25.autoPets={mode="all",allVerified=false,checking=false,total=0,equipped=0,ready=0,rotated=0,
    last="Не проверен",rejected={},success={},pool={},activeCount=165,minLevel=30000000,
    manualIds={},probePassed=0,probeTried=0,probeDetails="проверка каждого ID по фактическому изменению HP"}
local autoPetsLabel,autoPetsStatusLabel
local lastInventorySignature=nil
Z25.dynamicPoolCursor=0
local PROFILE_FILE = "ZoneHub_profiles_v17.json" -- intentionally unchanged
local storageStatus = "Проверка сохранения..."
local function timestamp() return os.date("%H:%M:%S") end
local statusLabel
local showErrorToast
local function log(msg, bad)
    table.insert(logLines, 1, (bad and "! " or "• ")..timestamp().." "..tostring(msg))
    while #logLines>5 do table.remove(logLines) end
    if bad then
        stats.clientErrors+=1
        if showErrorToast then showErrorToast(tostring(msg)) end
    end
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
-- World-wide farming by the ORIGINAL Pet Simulator coin directory types:
-- Coins (Earth), MoonCoins (Moon), SnowCoins (Winter).
-- Historical PS1 coin names 1..6 are Earth, 7..10 Moon, Christmas1..3
-- Winter; named special chests are assigned explicitly. No zone/radius gate.
-- If CoinName is absent or unknown, skip rather than silently farm another world.
Z25.coinWorldCache=setmetatable({},{__mode="k"})
local function coinWorld(coin)
    if not coin then return nil end
    local cached=Z25.coinWorldCache[coin]
    if cached~=nil then return cached~=false and cached or nil end
    local marker=coin:FindFirstChild("CoinName",true)
    local coinName=nil
    if marker and marker:IsA("StringValue") then coinName=marker.Value end
    if not coinName then coinName=coin:GetAttribute("CoinName") end
    if type(coinName)~="string" then
        Z25.coinWorldCache[coin]=false
        return nil
    end
    local world=nil
    -- Server directory metadata is preferable if readable.
    local directory=Z25.coinDirectory
    local record=directory and directory[coinName]
    if type(record)=="table" then
        local t=record.Type
        if t=="Coins" then world="Earth"
        elseif t=="MoonCoins" then world="Moon"
        elseif t=="SnowCoins" then world="Winter" end
    end
    if not world then
        local lower=string.lower(coinName)
        if lower:find("christmas",1,true) then world="Winter"
        elseif lower=="dominus chest" or lower=="grim chest" then world="Moon"
        elseif lower=="super chest" or lower=="omega chest" then world="Earth"
        else
            local zone=tonumber(coinName:match("^(%d+)%s"))
            if zone and zone>=1 and zone<=6 then world="Earth"
            elseif zone and zone>=7 and zone<=10 then world="Moon" end
        end
    end
    Z25.coinWorldCache[coin]=world or false
    return world
end
local function inside(p,coin)
    if Z25.area=="world" then
        return coinWorld(coin)==Z25.farmWorld
    end
    return false
end
function Z25.loadCoinDirectory()
    if Z25.coinDirectoryChecked then return end
    Z25.coinDirectoryChecked=true
    local rem=workspace:FindFirstChild("__REMOTES")
    local core=rem and rem:FindFirstChild("Core")
    local getDir=core and core:FindFirstChild("Get Directory")
    if getDir and getDir:IsA("RemoteFunction") then
        local ok,result=pcall(function() return getDir:InvokeServer() end)
        if ok and type(result)=="table" then
            local coins=result.Coins or (result.Directory and result.Directory.Coins)
            if type(coins)=="table" then Z25.coinDirectory=coins end
        end
    end
end
-- Space-aware coverage: route newly available pets into the least served
-- 110-stud grid cells. HP priority applies within a cell, not at the expense
-- of leaving an entire corner untouched.
function Z25.coverageCell(pos)
    local base=(Z25.area=="world" and Z25.worldAnchors[Z25.farmWorld]) or
        (Z25.area=="near" and Z25.nearPoint) or
        (Z25.point and Z25.point(Z25.area))
    -- Stable world grid means different zones get fair turns even when the
    -- player is standing in one corner of a very large world.
    if not base then return tostring(math.floor(pos.X/290))..":"..tostring(math.floor(pos.Z/290)) end
    return tostring(math.floor((pos.X-base.x)/110))..":"..tostring(math.floor((pos.Z-base.z)/110))
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
        if part and inside(part.Position,coin) then
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
    local reference=(Z25.area=="world" and Z25.worldAnchors[Z25.farmWorld]) or
        (Z25.area=="near" and Z25.nearPoint) or (Z25.area and Z25.point and Z25.point(Z25.area))
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
    return part~=nil and inside(part.Position,o) and type(hp)=="number" and hp>0
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
        -- Never resume a farm that was already paused before egg purchases.
        if alive and farming then Z25.paused=eggPausePrevious end
    end
end
local function stopEggs(reason)
    local wasRunning=eggRunning
    eggRunning=false
    eggEpoch+=1
    Z25.eggFusion.collecting=false
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
    -- Get Other Stats can return a large table. Counting pets is cheaper than
    -- rebuilding/sorting names after EVERY server read. Refresh UI at most once
    -- per 1.5s; full Save remains available to the filter/fusion validators.
    local count=0
    for _,pet in pairs(save.Pets) do
        if type(pet)=="table" then count+=1 end
    end
    if not Z25.inventory or not Z25.lastEggInventoryUi or os.clock()-Z25.lastEggInventoryUi>=1.5 then
        Z25.updateInventory(save,"яйца")
        Z25.lastEggInventoryUi=os.clock()
    end
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
    if Z25.eggFilter.mode=="off" then return true,false,"" end
    if Z25.countKeepTypes()<1 then return false,false,"Не выбран ни один питомец для сохранения" end
    local prior=indexedPets(beforeSave)
    local after=indexedPets(afterSave)
    local newPets,unexpected={},0
    local allowed={}
    local eggCatalog=Z25.EGG_CONTENTS[eggWorld] and Z25.EGG_CONTENTS[eggWorld][eggTier]
    if type(eggCatalog)=="table" then
        for _,code in ipairs(eggCatalog) do allowed[tostring(code)]=true end
    end
    local knownCodes=next(allowed)~=nil
    for id,p in pairs(after) do
        if not prior[id] then
            local kind=tostring(p.n or "")
            if knownCodes and allowed[kind] and Z25.classify(p)=="normal" and not Z25.trueFlag(p.e) then
                newPets[#newPets+1]={id=id,data=p,kind=kind}
            else
                unexpected+=1 -- unknown/new variant: never delete or fuse
            end
        end
    end
    -- Use durable, unique server inventory IDs instead of relying on the
    -- sometimes missing/nested hatch data in Shop Buy return values.
    if #newPets+unexpected<confirmed or #newPets+unexpected>confirmed*3 then
        return false,false,"Число новых ID не соответствует подтверждённым покупкам; очистка остановлена"
    end
    if unexpected>0 then
        return false,false,"Найдены "..unexpected.." неожиданных ID/вариантов; очистка не будет удалять неизвестное"
    end
    -- Client Buy responses may identify only the main hatch, even when the
    -- server grants two additional Pet Cloner copies. Unknown new IDs MUST
    -- NOT be deleted or automatically fused without a verified source ID.
    local extraIds=0 -- all verified newly created IDs are in newPets; no ambiguous extras
    -- Another inventory operation could add unrelated pets. Do not clean them up.
    local wanted,removable,unknown=0,{},0
    local huntedRare=false
    for _,item in ipairs(newPets) do
        local p=item.data
        local name=Z25.petNameForType(item.kind)
        if Z25.eggFilter.keep[item.kind] then
            wanted+=1
            -- Hunting stops for ANY selected pet, including the primary fusion type.
            huntedRare=true
        elseif not name or Z25.trueFlag(p.e) or Z25.classify(p)~="normal" then
            unknown+=1 -- protect unfamiliar names, equipped, and gold/rainbow/dark variants
        else
            removable[#removable+1]=item.id
        end
    end
    -- Track only selected IDs freshly returned by Buy AND verified in the inventory.
    -- Old pets are never placed in this allowlist.
    if Z25.eggFusion.collecting then
        for _,item in ipairs(newPets) do
            if Z25.eggFusion.fuseType==item.kind and Z25.eggFilter.keep[item.kind] then
                Z25.eggFusion.tracked[item.id]=true
            end
        end
    end
    Z25.eggFilter.kept+=wanted
    Z25.eggFilter.protected+=unknown+extraIds
    if #removable==0 then
        return true,huntedRare,string.format("Оставлено %d, защищено %d, доп. ID %d не трогаю",wanted,unknown,extraIds)
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
            or Z25.eggFilter.keep[tostring(now.n)] or Z25.trueFlag(now.e) or Z25.classify(now)~="normal" then
            return false,wanted>0,"Контроль удаления не пройден. Питомцы сохранены."
        end
    end
    -- Known PS1 Delete protocol. Replace the expensive ~3 inventory round-trips
    -- PER PET with a fresh pre-wave snapshot and one shared post-wave verification.
    -- Parallel batches are limited to 3 independent IDs to reduce client stalls.
    local removed=0
    local batchSize=3
    for first=1,#removable,batchSize do
        if not eggSessionActive(epoch) then
            return false,wanted>0,"Остановлено перед следующей группой удаления"
        end
        local _,_,verifyErr,nowSave=getEggInventory()
        if verifyErr or not nowSave then
            return false,wanted>0,"Нет свежего инвентаря перед удалением: "..tostring(verifyErr)
        end
        local latest=indexedPets(nowSave)
        local batch={}
        for i=first,math.min(#removable,first+batchSize-1) do
            local id=removable[i]
            local orig=after[id]
            local now=latest[id]
            if not now or not orig or prior[id] or tonumber(now.id)~=id or
                tostring(now.n)~=tostring(orig.n) or Z25.eggFilter.keep[tostring(now.n)] or
                Z25.trueFlag(now.e) or Z25.classify(now)~="normal" or
                Z25.trueFlag(now.lock) or Z25.trueFlag(now.locked) or
                Z25.trueFlag(now.lk) or Z25.trueFlag(now.fav) then
                return false,wanted>0,"Защита: состояние ID "..id.." изменилось, удаление отменено"
            end
            batch[#batch+1]=id
        end
        local completed,failures=0,{}
        for _,id in ipairs(batch) do
            task.spawn(function()
                local ok,response=pcall(function() return inv:InvokeServer("Delete",id) end)
                if not ok or response==false then
                    failures[#failures+1]=tostring(id)..": "..tostring(response):sub(1,45)
                end
                completed+=1
            end)
            task.wait(.025)
        end
        local deadline=os.clock()+12
        while eggSessionActive(epoch) and completed<#batch and os.clock()<deadline do
            task.wait(.06)
        end
        if not eggSessionActive(epoch) then
            return false,wanted>0,"Удаление остановлено; часть отправленных команд может завершиться"
        end
        if completed<#batch then
            return false,wanted>0,"Тайм-аут удаления; повторов не будет"
        end
        -- Verify every ID before counting successful removals. Do not resend on error.
        local post,postErr
        local missing={}
        for retry=1,5 do
            task.wait(retry==1 and .12 or .24)
            local _,_,err,snapshot=getEggInventory()
            post=snapshot postErr=err
            if err or not snapshot then break end
            local map=indexedPets(snapshot)
            missing={}
            for _,id in ipairs(batch) do
                if not map[id] then missing[#missing+1]=id end
            end
            if #missing==#batch then break end
        end
        if postErr or not post then
            return false,wanted>0,"Не удалось проверить результат удаления: "..tostring(postErr)
        end
        removed+=#missing
        Z25.eggFilter.deleted+=#missing
        if #failures>0 or #missing~=#batch then
            return false,wanted>0,"Удалено "..#missing.."/"..#batch.." в группе; остановлено без повторов. "..table.concat(failures,"; ")
        end
    end
    return true,huntedRare,string.format("Оставлено %d, удалено %d, защищено %d, доп. ID %d не трогаю",wanted,removed,unknown,extraIds)
end

-- Implemented after UPGRADE declarations. The UI can invoke this only while
-- eggRunning; never execute an irreversible fusion automatically on script load.
local fuseNewEggPets
-- Determine whether enough freshly purchased, selected pets are available to
-- fuse. Reading this snapshot does not mutate the inventory or invoke a remote.
function Z25.eggFusionProgress(save)
    local normal,gold,rainbow,oldNormal,oldGold,oldRainbow=0,0,0,0,0,0
    if type(save)~="table" or type(save.Pets)~="table" then
        return false,"Не удалось прочитать инвентарь"
    end
    local chosen=Z25.eggFusion.fuseType
    if not chosen or not Z25.eggFilter.keep[chosen] then return false,"Не выбран питомец для скрещивания" end
    if not chosen then return false,"Не выбран вид" end
    for _,p in pairs(save.Pets) do
        if type(p)=="table" and tostring(p.n)==chosen then
            local id=tonumber(p.id)
            local stage=Z25.classify(p)
            local fresh=id and Z25.eggFusion.tracked[id]
            if stage=="normal" then
                if fresh then
                    normal+=1
                else
                    oldNormal+=1
                end
            elseif stage=="gold" then
                if fresh then
                    gold+=1
                else
                    oldGold+=1
                end
            elseif stage=="rainbow" then
                if fresh then
                    rainbow+=1
                else
                    oldRainbow+=1
                end
            end
        end
    end
    local includeOld=Z25.eggFusion.allowExisting
    local ready=(normal+(includeOld and oldNormal or 0))>=10 or (gold+(includeOld and oldGold or 0))>=7 or
        (rainbow+(includeOld and oldRainbow or 0))>=5
    local summary=string.format("Обычных %d+%d старых/10 • золото %d+%d старых/7 • радуга %d+%d старых/5",normal,oldNormal,gold,oldGold,rainbow,oldRainbow)
    if not includeOld and (oldGold>0 or oldRainbow>0) then
        summary=summary.." • старые НЕ расходуются (включи разрешение отдельно)"
    end
    if oldNormal>0 and not includeOld then
        summary=summary.." • старые обычные защищены"
    end
    return ready,summary
end

-- Only two continuous modes: hunt (until selected type is found) and auto
-- (purchase + verified deletion + stage conversion). Manual STOP is always active.
-- Server replies and capacity are verified between waves.
local function startEggs(mode)
    if (mode=="hunt" or mode=="auto") and Z25.eggFilter.mode~="active" then
        eggMessage="Для охоты и автоскрещивания включи автоудаление (дважды)" return
    end
    if mode=="auto" and (not Z25.eggFusion.fuseType or not Z25.eggFilter.keep[Z25.eggFusion.fuseType]) then
        eggMessage="Для автоскрещивания выбери основной вид питомца; второй сохранится без скрещивания" return
    end
    if Z25.eggFilter.mode~="off" and Z25.countKeepTypes()==0 then eggMessage="Сначала выбери питомцев, которых оставлять" return end
    if converting then eggMessage="Сначала останови преобразование питомцев" return end
    if eggRunning then eggMessage="Яйца уже покупаются; нажми СТОП" return end
    local _,shop=eggRemotes()
    if not shop then eggMessage="Не найден Game.Shop (RemoteFunction)" log(eggMessage,true) return end
    if mode~="hunt" and mode~="auto" then
        eggMessage="Неизвестный режим" return
    end
    eggEpoch+=1
    local epoch=eggEpoch
    local key=eggKey(eggWorld,eggTier)
    local totalRequested=type(mode)=="number" and mode or nil -- hunt/auto: no request cap, manual STOP
    -- Limit concurrent Buy requests to 9, never send 100 at once.
    -- Each wave is verified against the server inventory before sending another wave.
    -- Concurrency is per verified wave, NOT a gamepass multiple-hatch.
    -- Bigger waves are tested against actual server response and FPS.
    local maxWave=eggPerfMode=="turbo" and 36 or eggPerfMode=="fast" and 24 or 12
    local waveLimit=maxWave
    local adaptiveWave=eggPerfMode=="turbo" and 12 or eggPerfMode=="fast" and 10 or 8
    local responsiveWaves=0
    local waveDelay=.015
    Z25.eggFusion.collecting=(mode=="auto")
    Z25.eggFusion.tracked={}
    Z25.eggFusion.done=0
    Z25.eggFusion.blocked=0
    Z25.eggFusion.last=mode=="auto" and "Коплю новые одинаковые: 10 обычных / 7 золотых / 5 радужных" or "Автоскрещивание выключено"
    eggRunning=true
    Z25.eggFilter.kept,Z25.eggFilter.deleted,Z25.eggFilter.protected,Z25.eggFilter.preview=0,0,0,0
    eggAttempts,eggOpened,eggConfirmed,eggRejected,eggBatches=0,0,0,0,0
    eggAdditionalPets,eggConfirmedMultiplier=0,nil
    -- A Buy can grant up to three pets if the account owns Pet Cloner.
    -- Start conservatively and update only from confirmed inventory deltas.
    local expectedPetsPerBuy=3
    eggInventory,eggCapacity=nil,nil
    eggStarted=os.clock()
    eggMessage="Подготовка • "..key.." • "..(mode=="hunt" and "ОХОТА ДО НУЖНОГО" or "АВТОСКРЕЩИВАНИЕ")
    log("Яйца: "..key..", режим "..tostring(mode))
    -- Save the existing pause state. During eggs, suspend NEW mine packets,
    -- preserving target locks and the ability to continue afterwards.
    if farming then
        log("Яйца и фарм работают одновременно: скорость зависит от сервера и FPS")
    end
    task.spawn(function()
        local ok,err=pcall(function()
            local cachedBefore=nil
            local batchNumber=0
            while eggSessionActive(epoch) do
                batchNumber+=1
                local count,capacity,errorText,beforeSave
                -- The AFTER snapshot of the last verified batch is also the BEFORE
                -- snapshot of the next; skip a redundant remote read when recent.
                -- Force a fresh snapshot periodically for out-of-band changes.
                if cachedBefore and os.clock()-cachedBefore.at<1.25 and batchNumber%4~=0 then
                    count,capacity,beforeSave=cachedBefore.count,cachedBefore.capacity,cachedBefore.save
                    errorText=nil
                else
                    count,capacity,errorText,beforeSave=getEggInventory()
                end
                cachedBefore=nil
                if errorText then
                    -- Read-only retries are safe; never repeat a Buy/Delete/Fuse
                    -- whose result is unknown.
                    for retry=1,2 do
                        if not eggSessionActive(epoch) then break end
                        task.wait(.3*retry)
                        count,capacity,errorText,beforeSave=getEggInventory()
                        if not errorText then break end
                    end
                end
                if not eggSessionActive(epoch) then break end
                if errorText then eggMessage="Ошибка чтения инвентаря (после повторов): "..tostring(errorText).." • остановлено" break end
                eggInventory,eggCapacity=count,capacity
                -- Reuse verified snapshots; no global lastCount.
                local free=math.max(0,math.floor(capacity-count))
                if free<=0 then
                    if mode=="auto" and type(fuseNewEggPets)=="function" then
                        local ready,progress=Z25.eggFusionProgress(beforeSave)
                        Z25.eggFusion.last=progress
                        if ready then
                            local good,converted,detail=fuseNewEggPets(epoch)
                            Z25.eggFusion.last=detail
                            if not good or converted==0 then
                                eggMessage="Инвентарь полон: "..detail.." • остановлено"
                                break
                            end
                            eggMessage="Скрещено "..converted.." групп; продолжаю покупки"
                            task.wait(.12)
                            continue
                        end
                        eggMessage="Инвентарь полон: "..progress..". Не хватает одинаковых НОВЫХ питомцев; старые защищены."
                        break
                    end
                    eggMessage="Инвентарь заполнен ("..count.."/"..capacity..")"
                    break
                end
                local left=totalRequested and math.max(0,totalRequested-eggAttempts) or free
                if left<=0 then
                    eggMessage="Покупка завершена: "..eggOpened.." питомцев"
                    break
                end
                -- Reserve capacity for *pets*, not merely egg requests. This
                -- prevents 9 Buy calls with 9 slots from overrunning a cloner
                -- owner's inventory. For an unknown account, assume 3/Buy
                -- until a completed group proves 1/Buy instead.
                local safeRequests=math.floor(free/expectedPetsPerBuy)
                if safeRequests<1 then
                    eggMessage="Осталось "..free.." мест (возможный множитель "..expectedPetsPerBuy.." на покупку). Для безопасности очередь остановлена."
                    break
                end
                local n=math.min(adaptiveWave,safeRequests,left)
                if n<=0 then break end
                eggActiveBatch=n
                eggBatches+=1
                eggMessage=string.format("%s • группа %d: отправляю %d; свободно %d",key,eggBatches,n,free)
                local completed,confirmed,rejected,errors=0,0,0,0
                local waveStarted=os.clock()
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
                    if i<n then task.wait(.025) end
                end
                local sent=n
                local waitStarted=os.clock()
                while eggSessionActive(epoch) and completed<sent and os.clock()-waitStarted<22 do
                    task.wait(.08)
                end
                if not eggSessionActive(epoch) then break end
                if completed<sent then
                    eggMessage="Тайм-аут ответов сервера ("..completed.."/"..sent.."); остановлено. Ожидающие покупки ещё могут завершиться"
                    break
                end
                eggConfirmed+=confirmed
                eggRejected+=rejected
                eggWaveSeconds=os.clock()-waveStarted
                -- Too many concurrent requests can make the UI stutter and can
                -- worsen server response time. Adapt based on OBSERVED response
                -- times and FPS, not guessed hatch chances or fabricated rates.
                if waveLimit>1 then
                    local slowResponse=eggWaveSeconds>2.3
                    local fpsLow=fpsValue>0 and fpsValue<33
                    if slowResponse or fpsLow or rejected>0 then
                        adaptiveWave=math.max(2,math.min(waveLimit,adaptiveWave-1))
                        responsiveWaves=0
                    elseif eggWaveSeconds<1.1 and (fpsValue==0 or fpsValue>=43) then
                        responsiveWaves+=1
                        if responsiveWaves>=2 then
                            adaptiveWave=math.min(waveLimit,adaptiveWave+1)
                            responsiveWaves=0
                        end
                    else
                        responsiveWaves=0
                    end
                end
                -- Verify durable inventory rather than counting successful remote returns.
                local latest,cap,readErr,afterSave
                for tries=1,9 do
                    if not eggSessionActive(epoch) then break end
                    task.wait(tries==1 and .10 or .30)
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
                -- One accepted egg may create THREE pets (Pet Cloner pass).
                -- Do not mistake legitimate 3x grants for duplicate requests.
                -- Still stop on out-of-range changes to protect the inventory.
                if gained<confirmed or gained>confirmed*3 then
                    eggMessage=eggMessage.." • изменение инвентаря не соответствует 1–3 питомцам на подтверждённую покупку; остановлено без повторов"
                    break
                end
                if confirmed>0 then
                    eggAdditionalPets+=math.max(0,gained-confirmed)
                    if gained==confirmed*3 then
                        expectedPetsPerBuy=3
                        eggConfirmedMultiplier=3
                    elseif gained==confirmed then
                        expectedPetsPerBuy=1
                        eggConfirmedMultiplier=1
                    else
                        -- Mixed/partial grants: keep the conservative 3-slot
                        -- reservation rather than guessing Game Pass ownership.
                        expectedPetsPerBuy=3
                        eggConfirmedMultiplier=nil
                    end
                    if gained>confirmed then
                        eggMessage=eggMessage.." • доп. питомцы +"..(gained-confirmed).." (возможен Pet Cloner)"
                    end
                end
                if rejected>0 then
                    eggMessage=eggMessage.." • отказов: "..rejected.." ("..reason.."); остановлено"
                    break
                end
                if gained==0 then
                    eggMessage="Сервер подтвердил запросы, но не добавил ID: возможно, лимит, задержка или нехватка валюты. Остановлено без повторов"
                    break
                end
                local verifiedNextCount,verifiedNextCapacity,verifiedNextSave=latest,cap,afterSave
                if Z25.eggFilter.mode~="off" and afterSave then
                    local good,found,detail=filterHatchedPets(beforeSave,afterSave,buyResults,confirmed,epoch)
                    Z25.eggFilter.last=detail
                    eggMessage=eggMessage.." • "..detail
                    if not good then break end
                    if mode=="hunt" and found then
                        eggMessage=eggMessage.." • ЦЕЛЬ НАЙДЕНА, ОСТАНОВЛЕНО"
                        break
                    end
                    local postCount,postCap,postErr,postSave=getEggInventory()
                    if postErr then eggMessage="Ошибка инвентаря после фильтра: "..postErr break end
                    eggInventory,eggCapacity=postCount,postCap
                    verifiedNextCount,verifiedNextCapacity,verifiedNextSave=postCount,postCap,postSave
                    -- Critical v3.4 fix: do NOT wait for full inventory. The first
                    -- eligible group must be fused immediately so a small inventory
                    -- can keep hatching. This is only for the explicit auto mode.
                    if mode=="auto" then
                        local ready,progress=Z25.eggFusionProgress(postSave)
                        Z25.eggFusion.last=progress
                        if ready then
                            local good,converted,detail=fuseNewEggPets(epoch)
                            Z25.eggFusion.last=detail
                            if not good then
                                eggMessage=eggMessage.." • АВТОСКРЕЩИВАНИЕ ОСТАНОВЛЕНО: "..detail
                                break
                            end
                            eggMessage=eggMessage.." • скрещено "..converted.." групп"
                            if converted>0 then
                                local refreshed,refCap,refError,refSave=getEggInventory()
                                if refError then
                                    eggMessage="Скрещивание завершилось, но не удалось обновить инвентарь: "..tostring(refError)
                                    break
                                end
                                eggInventory,eggCapacity=refreshed,refCap
                                verifiedNextCount,verifiedNextCapacity,verifiedNextSave=refreshed,refCap,refSave
                            end
                        end
                    end
                end
                if totalRequested and eggAttempts>=totalRequested then
                    -- Early fusion has already run above on every eligible group.
                    -- Never send an additional conversion here without a fresh check.
                    eggMessage=eggMessage.." • достигнут лимит запросов"
                    break
                end
                if Z25.eggFilter.mode=="off" and latest>=cap then
                    eggMessage=eggMessage.." • инвентарь заполнен"
                    break
                end
                if verifiedNextSave then
                    cachedBefore={count=verifiedNextCount,capacity=verifiedNextCapacity,
                        save=verifiedNextSave,at=os.clock()}
                end
                task.wait(Z25.eggFilter.mode=="active" and .16 or waveDelay)
            end
        end)
        if epoch==eggEpoch then
            eggRunning=false
            eggActiveBatch=0
            Z25.eggFusion.collecting=false
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
                if (mode=="all" or equipped) and (tonumber(p.l) or 0)>=Z25.autoPets.minLevel then
                    local profile,trained=Z25.inventoryProfile(id,p,save)
                    if profile then
                        if not trained then untrained+=1 end
                        result[#result+1]={id=id,profile=profile,equipped=equipped,trained=trained,
                            manual=Z25.autoPets.manualIds[id]==true,level=tonumber(p.l) or 0}
                    end
                end
            end
        end
    end
    table.sort(result,function(a,b)
        -- Descending effective Mine argument approximates actual hit strength,
        -- including bonuses from equipped hats. Stable numeric ID tie-break.
        if a.manual~=b.manual then return a.manual==true end
        local aa=tonumber(a.profile.samples[1]) or 0
        local bb=tonumber(b.profile.samples[1]) or 0
        if aa~=bb then return aa>bb end
        return a.id<b.id
    end)
    -- Rebuild from the current server inventory: old fused/deleted IDs are never kept.
    local ids={}
    for _,v in ipairs(result) do ids[#ids+1]=tostring(v.id) end
    table.sort(ids)
    local signature=table.concat(ids,",")
    if signature~=lastInventorySignature then
        lastInventorySignature=signature
        Z25.autoPets.rejected={}
        Z25.dynamicPoolCursor=0
    end
    Z25.autoPets.total=count Z25.autoPets.equipped=eq Z25.autoPets.ready=#result
    Z25.autoPets.last="Инвентарь: "..count.." • экипировано: "..eq.." • ур. ≥30 млн: "..#result.." • в ротации: "..math.min(165,Z25.autoPets.activeCount).." • расчёт по уровню: "..untrained
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

-- Autoconvert ONLY the selected pet TYPE, from IDs verified to have hatched
-- during the current auto-fusion run. Do not assume that sending one pet ID
-- specifies all server-side materials: prohibit conversion if any untracked
-- same-type same-stage pets are present (even protected/equipped ones).
fuseNewEggPets=function(epoch)
    if not eggSessionActive(epoch) or not Z25.eggFusion.collecting then
        return false,0,"Автоскрещивание остановлено"
    end
    local kind=Z25.eggFusion.fuseType
    if not kind or not Z25.eggFilter.keep[kind] then return false,0,"Не выбран основной вид для скрещивания" end
    if not kind then return false,0,"Нет выбранного вида" end
    local remotes=workspace:FindFirstChild("__REMOTES")
    local gameRemotes=remotes and remotes:FindFirstChild("Game")
    if not gameRemotes then return false,0,"Отсутствуют Game Remotes" end
    local rules={
        {from="normal",to="gold",need=10,remote="Golden Pets",title="Золото"},
        {from="gold",to="rainbow",need=7,remote="Rainbow Pets",title="Радуга"},
        {from="rainbow",to="dark",need=5,remote="Dark Matter Pets",title="Dark Matter"}
    }
    local completed=0
    local messages={}
    for _,rule in ipairs(rules) do
        -- Limit per stage avoids a runaway or repeated non-progress loop.
        for operation=1,150 do
            if not eggSessionActive(epoch) then return false,completed,"Покупки остановлены" end
            local _,_,readErr,save=getEggInventory()
            if readErr or not save then return false,completed,"Инвентарь недоступен: "..tostring(readErr) end
            local stageIds,materialIds={},{}
            local existingOld=0
            local danger=false
            local before=indexedPets(save)
            for id,p in pairs(before) do
                if tostring(p.n)==kind and Z25.classify(p)==rule.from then
                                -- Explicit opt-in may include pre-existing normal/gold/rainbow
                    -- pets of the chosen type. Never consume locked/equipped IDs.
                    local allowed=Z25.eggFusion.tracked[id] or Z25.eggFusion.allowExisting
                    if allowed then
                        if Z25.trueFlag(p.e) or Z25.trueFlag(p.lock) or
                            Z25.trueFlag(p.locked) or Z25.trueFlag(p.lk) or
                            Z25.trueFlag(p.fav) then danger=true end
                        stageIds[#stageIds+1]=id
                        materialIds[id]=true
                    else
                        existingOld+=1
                    end
                end
            end
            if #stageIds<rule.need then break end
            -- A later-stage remote need not exist unless this stage is ready.
            local remote=gameRemotes:FindFirstChild(rule.remote)
            if not remote or not remote:IsA("RemoteFunction") then
                return false,completed,"Не найден "..rule.remote.." (есть подходящая группа)"
            end
            -- Server determines which duplicate pets to consume. No destructive
            -- conversion is safe if historical duplicates are in its pool.
            if existingOld>0 or danger then
                Z25.eggFusion.blocked+=1
                -- Do not let protected old NORMAL pets suppress a safe
                -- gold->rainbow/dark-matter conversion later in this pass.
                if rule.from=="normal" and existingOld>0 and not danger then
                    Z25.eggFusion.last="Обычные старые защищены; проверяю золотых и радужных"
                    break
                end
                return false,completed,"ЗАЩИТА: "..rule.title.." • есть "..existingOld..
                    " старых питомцев этого вида/этапа либо заблокированные. Не скрещиваю."
            end
            table.sort(stageIds)
            local oldDest={}
            local oldSrcCount=#stageIds
            for id,p in pairs(before) do
                if tostring(p.n)==kind and Z25.classify(p)==rule.to then
                    oldDest[id]=true
                end
            end
            local called,response=pcall(function() return remote:InvokeServer(stageIds[1]) end)
            if not called or response==false then
                return false,completed,"Сервер отклонил "..rule.title..": "..tostring(response):sub(1,60)
            end
            local changed=false
            local outputIds={}
            for verify=1,6 do
                if not eggSessionActive(epoch) then return false,completed,"Остановка во время проверки скрещивания" end
                task.wait(verify==1 and .20 or .28)
                local _,_,readError,after=getEggInventory()
                if readError or not after then return false,completed,"Не удалось проверить улучшение" end
                local afterMap=indexedPets(after)
                local remained=0
                local newlyProduced={}
                local oldLost=false
                for id,p in pairs(afterMap) do
                    if tostring(p.n)==kind and Z25.classify(p)==rule.from and materialIds[id] then
                        remained+=1
                    end
                    if tostring(p.n)==kind and Z25.classify(p)==rule.to and not oldDest[id] then
                        newlyProduced[#newlyProduced+1]=id
                    end
                end
                -- Any old item from before conversion that vanished is concerning.
                for id,p in pairs(before) do
                    if not afterMap[id] and not materialIds[id] and not Z25.eggFusion.tracked[id] then
                        oldLost=true break
                    end
                end
                if oldLost then
                    return false,completed,"Защита: неожиданно исчез старый питомец, автоулучшение остановлено"
                end
                if remained<oldSrcCount and #newlyProduced>0 then
                    outputIds=newlyProduced changed=true
                    for id,_ in pairs(before) do
                        if not afterMap[id] then Z25.eggFusion.tracked[id]=nil end
                    end
                    break
                end
            end
            if not changed then
                return false,completed,"Нет подтверждённого результата "..rule.title..". Не повторяю команду"
            end
            for _,id in ipairs(outputIds) do Z25.eggFusion.tracked[id]=true end
            -- Rebuild farming ID list promptly after any consumed pet IDs.
            Z25.autoPets.refreshAt=os.clock()
            completed+=1
            Z25.eggFusion.done+=1
            messages[#messages+1]=rule.title
            Z25.eggFusion.last="Успешно: "..completed.." групп • "..rule.title
            task.wait(.06)
        end
    end
    if completed==0 then
        return true,0,"Нет групп 10 обычных / 7 золотых / 5 радужных выбранного вида"
    end
    return true,completed,"Готово: "..completed.." групп ("..table.concat(messages,", ")..")"
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
    local zoneKey=tostring(Z25.area)..":"..tostring(Z25.farmWorld)
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
    -- Options are already ordered by requested HP priority. Among those,
    -- favour grid cells that have been assigned the fewest times.
    local chosen,chosenKey,least=nil,nil,math.huge
    for _,info in ipairs(options) do
        if not reserved[info.object] and validCoin(info.object) then
            local cell=Z25.coverageCell(info.pos)
            local visits=Z25.coverageVisits[cell] or 0
            if visits<least then
                chosen,chosenKey,least=info,cell,visits
            end
        end
    end
    if chosen then
        if Z25.coverageVisits[chosenKey]==nil then Z25.coverageSectors+=1 end
        Z25.coverageVisits[chosenKey]=(Z25.coverageVisits[chosenKey] or 0)+1
        reserved[chosen.object]=id
        return chosen.object
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
    local retryAt=os.clock()+45
    local pool={}
    while active(epoch) do
        if os.clock()>=retryAt then
            Z25.autoPets.rejected={}
            retryAt=os.clock()+45
        end
        if not Z25.waitWhilePaused(epoch) then break end
        local now=os.clock()
        -- Avoid contending with the game's inventory UI for Get Other Stats.
        if now-lastUpdate>=30 or #pool==0 or (Z25.autoPets.refreshAt and lastUpdate<Z25.autoPets.refreshAt) then
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
            Z25.autoPets.last="Питомцев с уровнем от 30 000 000 пока нет • повтор через 12 с"
            task.wait(12)
            continue
        end
        -- Strength-first but without starving weaker or locked workers: the
        -- strongest half is selected on every cycle, with the remaining slots
        -- rotating across all other live inventory IDs. No equip is required.
        local batch,picked={},{}
        local requested=math.min(165,Z25.autoPets.activeCount,#pool)
        local prioritySlots=math.min(#pool,math.max(1,math.floor(requested/2)))
        for n=1,#pool do
            local item=pool[n]
            if #batch>=prioritySlots then break end
            if (Z25.autoPets.rejected[item.id] or 0)<3 then
                batch[#batch+1]=item
                picked[item.id]=true
            end
        end
        for n=1,#pool do
            if #batch>=requested then break end
            Z25.dynamicPoolCursor=Z25.dynamicPoolCursor%#pool+1
            local item=pool[Z25.dynamicPoolCursor]
            if not picked[item.id] and (Z25.autoPets.rejected[item.id] or 0)<3 then
                batch[#batch+1]=item
                picked[item.id]=true
            end
        end
        if #batch==0 then
            -- No ID is discarded permanently just because a transient server
            -- failure or lack of coins prevented observing HP progress.
            Z25.autoPets.rejected={}
            log("Все ID временно без HP-прогресса; повтор через 8 с")
            task.wait(8)
            continue
        end
        local batchSuccess=0
        local pending=#batch
        stats.workers=math.min(pending,24)
        stats.peakWorkers=math.max(stats.peakWorkers,math.min(pending,24))
        local inFlight=0
        local parallelLimit=24 -- all 165 take part by rotation, not 165 concurrent workspace scans
        for _,item in ipairs(batch) do
            while active(epoch) and inFlight>=parallelLimit do task.wait(.05) end
            if not active(epoch) then break end
            inFlight+=1
            task.spawn(function()
                local succeeded,okOrErr,result=pcall(function()
                    return Z25.mineForOne(epoch,item.id,item.profile,nil)
                end)
                if succeeded and okOrErr==true then
                    batchSuccess+=1
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
                    Z25.autoPets.rejected[item.id]=(Z25.autoPets.rejected[item.id] or 0)+1
                end
                pending-=1
                inFlight=math.max(0,inFlight-1)
                if active(epoch) then stats.workers=inFlight end
            end)
        end
        while active(epoch) and pending>0 do task.wait(.12) end
        -- On an empty world or temporary server rejection, avoid hot-looping 165 jobs.
        task.wait(batchSuccess==0 and 3.5 or .16)
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
        if Z25.startAfterProbe then
            Z25.startAfterProbe=false
            if alive and Z25.autoPets.allVerified and Z25.startFarmCallable then
                task.defer(Z25.startFarmCallable)
            else
                log("Автозапуск не выполнен: сервер не подтвердил режим всех питомцев",true)
            end
        end
        if autoPetsStatusLabel then
            local state=Z25.autoPets.allVerified and "✅ ВЕСЬ ИНВЕНТАРЬ ВКЛЮЧЁН" or "Нет подтверждения для режима ВСЕ"
            autoPetsStatusLabel.Text=state.." • "..Z25.autoPets.probePassed.."/"..Z25.autoPets.probeTried.." • подробности в отчёте"
        end
        if Z25.autoPets.syncButtons then Z25.autoPets.syncButtons() end
    end)
end

local function startFarm()
    if not alive then return end
    if converting then log("Дождись окончания преобразования питомцев",true) return end
    if farming then return end
    if Z25.area~="world" then log("Выбери мир на вкладке «Фарм»",true) return end
    Z25.loadCoinDirectory()
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
    -- LAB 0.9–1.2 observed multiple unequipped IDs mining, but every new ID is
    -- independently checked for real HP progress here. No global all-ID approval.
    if Z25.autoPets.mode~="saved" then
        local list,err=Z25.inventorySnapshot(Z25.autoPets.mode)
        if not list or #list==0 then
            log("Авто-ID: "..tostring(err or "нет подходящих питомцев"),true) return
        end
    end


    local coins,mine,pets=nodes()
    if not coins or not mine or not pets then log("Монеты или RemoteEvent не найдены",true) return end
    local found=scan()
    if #found==0 then
        log("В мире пока нет загруженных подходящих монет — жду появления, фарм не закрываю")
    end
    session+=1
    local epoch=session
    farming=true
    Z25.paused=false
    table.clear(reserved)
    table.clear(lockedTargets)
    table.clear(Z25.coverageVisits)
    Z25.coverageSectors=0
    stats.damage=0 stats.gone=0 stats.noProgress=0 stats.mine=0 stats.move=0 stats.clientErrors=0
    stats.targetReused=0 stats.targetChanged=0 stats.perPet={} stats.peakWorkers=0 stats.started=os.clock()
    for key,current in pairs(Z25.currency) do if type(current)=="number" then Z25.currencyStart[key]=current end end
    if Z25.autoPets.mode~="saved" then
        Z25.autoPets.rejected={} Z25.autoPets.success={} Z25.autoPets.rotated=0
        stats.workers=0
        if progressLabel then progressLabel.Text="Авто-ID: "..Z25.autoPets.last.."\nПроверяю HP каждого питомца…" end
        log("Авто-ID: "..Z25.autoPets.ready.." с ур. от 30 млн; до "..Z25.autoPets.activeCount.." в ротации, максимум 24 запроса параллельно")
        task.spawn(function()
            while alive and farming and epoch==session do
                local ok,err=pcall(Z25.dynamicFarm,epoch)
                if not ok then
                    log("Ошибка фарма (автовосстановление через 5 с): "..tostring(err):sub(1,80),true)
                    task.wait(5)
                else
                    break -- regular exit only after explicit stop / session end
                end
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

Z25.startFarmCallable=startFarm

-- ZoneHub 4.2: separate UI setup to avoid exceeding main chunk local register limits.
local function createZoneHubUI()
-- ZoneHub 3.1 UI | original Roblox thumbnail icon, no third-party URL.
local shutdown
local C={
    bg=Color3.fromRGB(7,10,19), panel=Color3.fromRGB(17,24,40), panel2=Color3.fromRGB(30,43,67),
    inset=Color3.fromRGB(11,18,32), line=Color3.fromRGB(52,72,102), white=Color3.fromRGB(246,249,255),
    dim=Color3.fromRGB(164,184,211),blue=Color3.fromRGB(100,145,255), green=Color3.fromRGB(73,219,172),
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
local toast=Instance.new("TextLabel")
toast.Name="ErrorToast" toast.Visible=false
toast.AnchorPoint=Vector2.new(.5,0)
toast.Position=UDim2.new(.5,0,0,12)
toast.Size=UDim2.new(.85,0,0,45)
toast.BackgroundColor3=Color3.fromRGB(104,36,58)
toast.BackgroundTransparency=.08 toast.BorderSizePixel=0
toast.TextColor3=Color3.fromRGB(255,242,245)
toast.Font=Enum.Font.GothamSemibold toast.TextSize=12
toast.TextWrapped=true toast.ZIndex=80 toast.Parent=gui corner(toast,12)
local lastToastAt=-1e9
local toastVersion=0
showErrorToast=function(message)
    if not alive or not gui.Parent then return end
    local now=os.clock()
    if now-lastToastAt<4 then return end
    lastToastAt=now toastVersion+=1
    local token=toastVersion
    toast.Text="⚠ "..message:sub(1,145)
    toast.Visible=true toast.TextTransparency=0
    task.delay(3.6,function()
        if not alive or token~=toastVersion or not toast.Parent then return end
        tween(toast,{TextTransparency=1,BackgroundTransparency=1},.28)
        task.delay(.31,function()
            if alive and token==toastVersion and toast.Parent then
                toast.Visible=false toast.BackgroundTransparency=.08
            end
        end)
    end)
end
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
label(top,"4.1 FIX2  •  PET SIMULATOR 2018",49,20,10,C.dim,true)
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
local names={"Фарм","Яйца","Шапки","Улучшение","Телепорт","Настройки"}
-- Six tabs: tab labels scale to remain tappable on narrow Android screens.
local pill=Instance.new("Frame")
pill.Name="ActiveTabPill" pill.BackgroundColor3=C.panel2 pill.BorderSizePixel=0
pill.Position=UDim2.new(0,3,0,3) pill.Size=UDim2.new(1/#names,-6,1,-6)
pill.Parent=tabBar corner(pill,10) stroke(pill,C.line,.5)
pill.ZIndex=1
for i,name in ipairs(names) do
    local b=Instance.new("TextButton") b.Name=name b.Text=name b.TextSize=10
    b.Font=Enum.Font.GothamSemibold b.TextColor3=C.dim b.BackgroundTransparency=1
    b.TextScaled=true b.TextWrapped=false
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

-- FARM: one-tap all-inventory mode, region selection and compact diagnostics.
do
local farm=pages["Фарм"]
local hero=card(farm,114,C.blue)
label(hero,"⛏  Автофарм · весь инвентарь",9,27,16,C.white,true)
Z25.coinCount=label(hero,"Выбери мир ниже",40,25,11,C.dim)
Z25.workLabel=label(hero,"● ОСТАНОВЛЕН",73,26,13,C.red,true)
local controls=card(farm,72,C.green)
Z25.startButton=button(controls,"▶ ЗАПУСТИТЬ АВТОФАРМ",13,function()
    if farming then stopFarm() log("Фарм остановлен") else startFarm() end
end,C.green)
local areaCard=card(farm,129,C.purple)
label(areaCard,"🌍  Мир для фарма · ВСЕ зоны",7,27,14,C.white,true)
Z25.areaLabel=label(areaCard,"Земля — все зоны",36,23,12,C.gold,true)
label(areaCard,"Фильтр по CoinName/валюте: все монеты и сундуки этого мира.",70,45,11,C.dim)
local worldCard=card(farm,154,C.blue)
label(worldCard,"ВЫБОР МИРА",8,27,13,C.white,true)
local worldChoices={{"ЗЕМЛЯ","Earth",C.blue},{"ЛУНА","Moon",C.purple},{"ЗИМА","Winter",C.cyan}}
local worldButtons={}
local function syncWorlds()
    for _,v in ipairs(worldButtons) do
        v.b.BackgroundColor3=Z25.farmWorld==v.world and v.color or C.panel2
    end
    if Z25.areaLabel then Z25.areaLabel.Text=Z25.areaDescription() end
end
for i,choice in ipairs(worldChoices) do
    local w=choice[2]
    local b=button(worldCard,choice[1],43,function()
        if farming then log("Останови фарм для переключения мира",true) return end
        Z25.farmWorld=w
        Z25.area="world"
        Z25.coinCache={list={},at=-1e9,zone=nil}
        syncWorlds()
        log("Выбран мир: "..Z25.areaDescription()..". Монеты определяются по игровому типу, без привязки координат.")
    end,C.panel2)
    b.Position=UDim2.new((i-1)/3,5,0,44) b.Size=UDim2.new(1/3,-8,0,38)
    worldButtons[#worldButtons+1]={b=b,world=w,color=choice[3]}
end
button(worldCard,"🔎 ПРОВЕРИТЬ МОНЕТЫ ВСЕГО МИРА",94,function()
    if farming then log("Во время фарма проверка не требуется") return end
    Z25.loadCoinDirectory()
    local found,total=scan()
    log(Z25.areaDescription()..": доступно "..#found.." из "..total.." загруженных монет")
end,C.panel2)
syncWorlds()
local selection=card(farm,107)
label(selection,"Приоритет монет",9,24,14,C.white,true)
local modes={{"Ближайшие","Near"},{"Меньше HP","LowHP"},{"Больше HP","HighHP"}}
local priButtons={}
for i,item in ipairs(modes) do
    local mode=item[2]
    local b=button(selection,item[1],45,function()
        cfg.mode=mode
        for _,row in ipairs(priButtons) do tween(row.b,{BackgroundColor3=row.mode==mode and C.blue or C.panel2},.15) end
    end,mode==cfg.mode and C.blue or C.panel2)
    b.Position=UDim2.new((i-1)/3,5,0,45) b.Size=UDim2.new(1/3,-8,0,38) b.TextSize=10
    priButtons[#priButtons+1]={b=b,mode=mode}
end
local jobs=card(farm,230,C.green)
label(jobs,"🐾  Фарм до 165 ID · ур. от 30 млн",8,31,14,C.white,true)
label(jobs,"Каждый питомец попадёт в ротацию; для стабильности одновременно до 24 задач.",36,42,11,C.dim)
local values={8,32,64,128,165}
local jobButtons={}
for i,n in ipairs(values) do
    local b=button(jobs,tostring(n),85,function()
        Z25.autoPets.activeCount=n
        for _,row in ipairs(jobButtons) do tween(row.b,{BackgroundColor3=row.n==n and C.blue or C.panel2},.16) end
        log("Питомцев в ротации за круг: до "..n)
    end,n==165 and C.blue or C.panel2)
    b.Position=UDim2.new((i-1)%3/3,5,0,85+math.floor((i-1)/3)*42)
    b.Size=UDim2.new(1/3,-8,0,36)
    jobButtons[#jobButtons+1]={b=b,n=n}
end
local farmManual=entry(jobs,"ПРИОРИТЕТНЫЕ ID (через запятую; можно вписать позже)",177,"",function(value)
    local chosen={}
    for token in tostring(value):gmatch("%d+") do
        local id=tonumber(token)
        if id and id>=1 and id%1==0 then chosen[id]=true end
    end
    Z25.autoPets.manualIds=chosen
    Z25.autoPets.refreshAt=os.clock()
end)
farmManual.PlaceholderText="Пример: 12562926, 45267711"
local report=card(farm,308,C.blue)
label(report,"📊  Статистика",8,25,14,C.white,true)
progressLabel=label(report,"Сбор статистики после запуска",35,52,11,C.white)
Z25.simpleFarmStat=label(report,"Питомцев: ? • добыто: 0 HP • исчезло монет: 0",92,65,12,C.dim)
local function farmReport()
    local currency={}
    for key,name in pairs({Coins="Земля",MoonCoins="Луна",SnowCoins="Зима"}) do
        local now=Z25.currency[key]
        local baseline=Z25.currencyStart[key]
        if type(now)=="number" and type(baseline)=="number" then
            currency[#currency+1]=name..": "..string.format("%.0f",now-baseline).." (изменение баланса)"
        end
    end
    local perPet={}
    for id,d in pairs(stats.perPet) do perPet[#perPet+1]={id=id,damage=d.damage} end
    table.sort(perPet,function(a,b) return a.damage>b.damage end)
    local top={}
    for i=1,math.min(20,#perPet) do top[#top+1]=tostring(perPet[i].id).." -"..math.floor(perPet[i].damage).." HP" end
    return table.concat({
        "ZoneHub v4.3 | Фарм", "Активен="..tostring(farming).." | Зона="..Z25.areaDescription(),
        "Инвентарь="..Z25.autoPets.total.." | в очереди="..Z25.autoPets.ready.." | подтвердили урон="..Z25.autoPets.rotated,
        "Параллельность="..Z25.autoPets.activeCount.." | пик="..stats.peakWorkers.." | сейчас="..stats.workers,
        string.format("Урон HP=%.0f | HP/сек=%.1f | исчезло целей=%d",stats.damage,stats.damage/math.max(1,os.clock()-stats.started),stats.gone),
        "Mine="..stats.mine.." | PetMovement="..stats.move.." | без прогресса="..stats.noProgress,
        "Охват="..Z25.radius.." studs | ячеек обработано="..Z25.coverageSectors.." | повторных целей="..stats.targetReused,
        "Яйца="..(eggRunning and "идут вместе с фармом" or "не открываются").." | старые Gold/Rainbow="..(Z25.eggFusion.allowExisting and "разрешены для скрещивания" or "защищены"),
        "Проверка неэкипированных="..Z25.autoPets.probePassed.."/"..Z25.autoPets.probeTried.." | "..Z25.autoPets.probeDetails,
        "Валюта="..(#currency>0 and table.concat(currency,"; ") or "нет подтверждённых полей баланса в Save"),
        "Топ урона="..table.concat(top,"; "), "Логи="..table.concat(logLines," | ")},"\n")
end
button(report,"📋 СКОПИРОВАТЬ ОТЧЁТ",171,function()
    if type(setclipboard)~="function" then log("Буфер обмена Delta недоступен",true) return end
    local ok=pcall(setclipboard,farmReport())
    log(ok and "Отчёт скопирован" or "Ошибка копирования",not ok)
end,C.blue)
-- HP damage over time; does not claim to measure coins/EXP rates.
local bars={}
local history={}
local lastDamage, lastSampleAt=0,os.clock()
Z25.rateLabel=label(report,"HP/сек · история за последние ~48 секунд",222,18,11,C.dim)
local chart=Instance.new("Frame")
chart.Name="FarmHistory" chart.BackgroundColor3=C.inset chart.BorderSizePixel=0
chart.Size=UDim2.new(1,-28,0,49) chart.Position=UDim2.fromOffset(14,244)
chart.Parent=report corner(chart,8)
for i=1,24 do
    local b=Instance.new("Frame")
    b.Name="Bar" b.BackgroundColor3=C.blue b.BorderSizePixel=0
    b.AnchorPoint=Vector2.new(0,1)
    b.Position=UDim2.new((i-1)/24,2,1,-3)
    b.Size=UDim2.new(1/24,-4,0,3)
    b.Parent=chart corner(b,3)
    bars[i]=b
end
Z25.updateFarmChart=function(now)
    local damage=stats.damage
    local span=math.max(.1,now-lastSampleAt)
    local rate=(farming and damage>=lastDamage) and (damage-lastDamage)/span or 0
    lastDamage=damage lastSampleAt=now
    history[#history+1]=rate
    if #history>24 then table.remove(history,1) end
    local maximum=1
    for _,v in ipairs(history) do maximum=math.max(maximum,v) end
    local shift=24-#history
    for i,b in ipairs(bars) do
        local val=history[i-shift] or 0
        b.Size=UDim2.new(1/24,-4,0,math.max(3,math.floor(42*val/maximum)))
        b.BackgroundColor3=val>0 and C.blue or C.panel2
    end
    Z25.rateLabel.Text=string.format("Урон HP/сек: %.0f • окно ~48 секунд",rate)
end
end

-- EGGS: only actual types for the chosen regular egg; no obsolete event catalog.
do
local eggs=pages["Яйца"]
local worlds=card(eggs,102,C.purple)
label(worlds,"🥚 Мир",9,26,15,C.white,true)
local tierRefresh
local worldButtons={}
for i,item in ipairs({{"Земля","World1",C.blue},{"Луна","Moon",C.purple},{"Зима","Winter",C.cyan}}) do
    local world=item[2]
    local b=button(worlds,item[1],45,function()
        if eggRunning then eggMessage="Сначала останови покупку" return end
        eggWorld=world eggTier=EGG_WORLDS[world].min
        Z25.eggFilter.keep={} Z25.eggFusion.fuseType=nil Z25.eggFilter.mode="off" Z25.eggFilter.pendingAt=0
        tierRefresh()
    end,item[3])
    b.Position=UDim2.new((i-1)/3,5,0,45) b.Size=UDim2.new(1/3,-8,0,37)
    worldButtons[#worldButtons+1]={b=b,world=world,color=item[3]}
end
local tiers=card(eggs,315,C.blue)
label(tiers,"Выбери яйцо",8,27,14,C.white,true)
local tierRows={}
for i=1,12 do
    local idx=i
    local b=button(tiers,"",46+math.floor((i-1)/3)*46,function()
        if eggRunning then eggMessage="Сначала останови покупку" return end
        local item=EGG_WORLDS[eggWorld]
        if item.min+idx-1>item.max then return end
        eggTier=item.min+idx-1
        Z25.eggFilter.keep={} Z25.eggFusion.fuseType=nil Z25.eggFilter.mode="off" Z25.eggFilter.pendingAt=0
        tierRefresh()
    end,C.panel2)
    b.Position=UDim2.new((i-1)%3/3,5,0,46+math.floor((i-1)/3)*46)
    b.Size=UDim2.new(1/3,-8,0,40) b.TextSize=11
    tierRows[i]=b
end
local tierInfo=label(tiers,"",270,40,12,C.gold,true)
local pets=card(eggs,426,C.gold)
label(pets,"🎯 Кого оставлять из этого яйца (1–6)",8,27,14,C.white,true)
label(pets,"Выбирай от 1 до 6 видов; все 6 не обязательны. Покупка без фильтра не требует выбора.",35,39,11,C.dim)
local petRows={}
local listCodes={}
local chosenLabel=label(pets,"",350,69,11,C.gold,true)
local fusionTypeButton
local function updatePets()
    listCodes=Z25.EGG_CONTENTS[eggWorld][eggTier] or {}
    local rows=math.ceil(#listCodes/2)
    pets.Size=UDim2.new(1,0,0,78+rows*44+135)
    for i,b in ipairs(petRows) do
        local code=listCodes[i]
        b.Visible=code~=nil
        if code then
            local selected=Z25.eggFilter.keep[tostring(code)]
            local name=Z25.PET_TYPE_NAMES[code] or ("Код "..code)
            local rarity=(eggWorld=="World1" and eggTier==1) and (code==1005 and " · редкий" or " · базовый") or ""
            b.Text=(selected and "✓ " or "○ ")..name..rarity
            b.BackgroundColor3=selected and C.green or C.panel2
        end
    end
    chosenLabel.Position=UDim2.fromOffset(14,80+rows*44)
    local selectedCount=Z25.countKeepTypes()
    local fuse=Z25.eggFusion.fuseType
    local fuseName=fuse and (Z25.petNameForType(fuse) or fuse) or "не выбран"
    local preview=Z25.keepSummary()
    local charCount=utf8.len(preview)
    if charCount and charCount>52 then
        local cut=utf8.offset(preview,53)
        if cut then preview=preview:sub(1,cut-1).."…" end
    end
    chosenLabel.Text=selectedCount==0 and "Выбрано 0/6 • без фильтра можно покупать яйца" or ("Оставить ("..selectedCount.."/6): "..preview.."\nСкрещивать: "..fuseName.." • остальные защищены")
    if fusionTypeButton then
        fusionTypeButton.Visible=selectedCount>0
        fusionTypeButton.Position=UDim2.fromOffset(8,155+rows*44)
        fusionTypeButton.Text="♻ Основной для скрещивания: "..fuseName.." (сменить)"
    end
end
for i=1,12 do
    local ix=i
    local b=button(pets,"",78+math.floor((i-1)/2)*44,function()
        if eggRunning then eggMessage="Нельзя менять выбор во время покупки" return end
        local code=listCodes[ix]
        if not code then return end
        local key=tostring(code)
        local chosen=Z25.countKeepTypes()
        if not Z25.eggFilter.keep[key] and chosen>=6 then
            eggMessage="Можно выбрать максимум 6 видов. Уже выбранные можно снять."
            return
        end
        Z25.eggFilter.keep[key]=not Z25.eggFilter.keep[key]
        local selected={}
        for _,v in ipairs(listCodes) do if Z25.eggFilter.keep[tostring(v)] then selected[#selected+1]=tostring(v) end end
        -- One selected type: safe default. Two to six: explicit fusion choice.
        Z25.eggFusion.fuseType=#selected==1 and selected[1] or nil
        Z25.eggFilter.mode="off" -- user must re-arm deletion after changing selection
        Z25.eggFilter.pendingAt=0
        updatePets()
    end,C.panel2)
    b.Position=UDim2.new((i-1)%2/2,5,0,78+math.floor((i-1)/2)*44)
    b.Size=UDim2.new(.5,-8,0,37) b.TextSize=10
    petRows[i]=b
end
fusionTypeButton=button(pets,"♻ Основной для скрещивания (выбрать)",390,function()
    if eggRunning then eggMessage="Сначала останови покупку" return end
    local selected={}
    for _,code in ipairs(listCodes) do if Z25.eggFilter.keep[tostring(code)] then selected[#selected+1]=tostring(code) end end
    if #selected==0 then return end
    -- Rotate through ALL selected types; do not assume there are only two.
    local nextIndex=1
    for i,code in ipairs(selected) do
        if code==Z25.eggFusion.fuseType then nextIndex=i%#selected+1 break end
    end
    Z25.eggFusion.fuseType=selected[nextIndex]
    Z25.eggFilter.mode="off" Z25.eggFilter.pendingAt=0
    updatePets()
end,C.purple)
local actions=card(eggs,149,C.green)
label(actions,"⚡ Быстрое открытие · серверные серии",8,27,14,C.white,true)
eggPerfButton=button(actions,"СКОРОСТЬ: АВТО · до 12 запросов",44,function()
    if eggRunning then eggMessage="Останови покупки перед переключением скорости" return end
    eggPerfMode=eggPerfMode=="auto" and "fast" or eggPerfMode=="fast" and "turbo" or "auto"
end,C.blue)
label(actions,"АВТО 12 / БЫСТРО 24 / ТУРБО 36 за группу. Фарм не ставится на паузу. Сервер может ограничить скорость.",96,43,10,C.dim)
local filter=card(eggs,355,C.gold)
label(filter,"🛡 Фильтр новых питомцев",9,26,14,C.white,true)
label(filter,"Оставляем 1–6 выбранных видов. Скрещиваем только основной.",36,38,11,C.dim)
Z25.activeFilterButton=button(filter,"🗑 АВТОУДАЛЕНИЕ (2 НАЖАТИЯ)",82,function()
    if eggRunning then eggMessage="Сначала останови покупку" return end
    if Z25.countKeepTypes()<1 then Z25.eggFilter.last="Выбери питомца для сохранения" return end
    if Z25.eggFilter.mode=="active" then
        Z25.eggFilter.mode="off" Z25.eggFilter.pendingAt=0
        Z25.eggFilter.last="Автоудаление выключено"
    elseif Z25.eggFilter.pendingAt>0 and os.clock()-Z25.eggFilter.pendingAt<9 then
        Z25.eggFilter.mode="active" Z25.eggFilter.pendingAt=0
        Z25.eggFilter.last="Автоудаление новых питомцев включено"
    else
        Z25.eggFilter.pendingAt=os.clock()
        Z25.eggFilter.last="ПОДТВЕРЖДЕНИЕ: нажми кнопку ещё раз в течение 9 секунд"
    end
end,C.red)
button(filter,"🎯 БЕСКОНЕЧНАЯ ОХОТА ДО НУЖНОГО",133,function()
    startEggs("hunt")
end,C.purple)
button(filter,"♻ БЕСКОНЕЧНЫЕ ЯЙЦА + СКРЕЩИВАНИЕ",183,function()
    startEggs("auto")
end,C.green)
Z25.legacyFusionButton=button(filter,"",237,function()
    if eggRunning then eggMessage="Останови покупки перед изменением разрешения" return end
    Z25.eggFusion.allowExisting=not Z25.eggFusion.allowExisting
    Z25.legacyFusionButton.Text=Z25.eggFusion.allowExisting and
        "⚠ СТАРЫЕ ВИДЫ: МОЖНО РАСХОДОВАТЬ" or
        "🛡 СТАРЫЕ ПИТОМЦЫ: НЕ ТРОГАТЬ"
    eggMessage=Z25.eggFusion.allowExisting and
        "Разрешено расходовать старых питомцев выбранного вида для скрещивания; экипированные/избранные защищены" or
        "Старые питомцы защищены"
end,C.panel2)
Z25.legacyFusionButton.Text="🛡 СТАРЫЕ ПИТОМЦЫ: НЕ ТРОГАТЬ"
label(filter,"10 обычных → Gold; 7 Gold → Rainbow; 5 Rainbow → Dark. БЕЗ лимита попыток, до СТОП/ошибки/заполнения.",293,56,10,C.dim)
local stopCard=card(eggs,77)
button(stopCard,"■ СТОП ПОКУПОК И ФИЛЬТРА",13,function()
    stopEggs("Покупки остановлены")
    Z25.eggFilter.mode="off" Z25.eggFilter.pendingAt=0
    log("Покупки и автоудаление выключены")
end,C.red)
local state=card(eggs,290)
label(state,"📋 Итог покупок",9,25,14,C.white,true)
eggStatusLabel=label(state,"Ожидание",36,76,12,C.dim)
eggCountLabel=label(state,"Получено: 0",110,24,11,C.gold,true)
Z25.eggFilterLabel=label(state,"Фильтр выключен",140,47,10,C.dim)
Z25.eggFusionLabel=label(state,"Автоскрещивание: выключено",189,42,10,C.gold)
button(state,"📋 СКОПИРОВАТЬ ИТОГ ЯИЦ",240,function()
    if type(setclipboard)~="function" then eggMessage="Буфер обмена Delta недоступен" return end
    local report=table.concat({
        "ZoneHub v4.3 | Яйца",
        "Работает="..tostring(eggRunning).." | Мир="..tostring(eggWorld).." | Tier="..tostring(eggTier),
        "Запросов="..eggAttempts.." | подтверждений Buy="..eggConfirmed.." | отказов="..eggRejected,
        "Новых питомцев="..eggOpened.." | Дополнительные="..eggAdditionalPets.." | Наблюдаемый множитель="..tostring(eggConfirmedMultiplier or "не определён").." | Серверный инвентарь="..tostring(eggInventory).."/"..tostring(eggCapacity),
        "Фильтр="..Z25.eggFilter.mode.." | оставлено="..Z25.eggFilter.kept.." | удалено="..Z25.eggFilter.deleted,
        "Тип для скрещивания="..tostring(Z25.eggFusion.fuseType).." | старые Gold/Rainbow="..tostring(Z25.eggFusion.allowExisting),
        "Скрещено групп="..Z25.eggFusion.done.." | заблокировано="..Z25.eggFusion.blocked,
        "Причина/статус="..eggMessage,
        "Скрещивание="..Z25.eggFusion.last,
        "Фильтр="..Z25.eggFilter.last,
        "Фарм одновременно="..tostring(farming).." | пауза="..tostring(Z25.paused),
        "Профиль очереди="..eggPerfMode.." (максимум 36) | текущая партия="..eggActiveBatch.." | ответ партии (с)="..string.format("%.2f",eggWaveSeconds).." | FPS="..fpsValue
    },"\n")
    local ok=pcall(setclipboard,report)
    log(ok and "Итог яиц скопирован" or "Не удалось скопировать итог",not ok)
end,C.panel2)
function tierRefresh()
    local conf=EGG_WORLDS[eggWorld]
    local accent=eggWorld=="Moon" and C.purple or eggWorld=="Winter" and C.cyan or C.blue
    for _,w in ipairs(worldButtons) do tween(w.b,{BackgroundColor3=w.world==eggWorld and w.color or C.panel2},.16) end
    local n=conf.max-conf.min+1
    local rows=math.ceil(n/3)
    tiers.Size=UDim2.new(1,0,0,46+rows*46+54)
    for i,b in ipairs(tierRows) do
        local valid=i<=n
        b.Visible=valid
        if valid then
            local tier=conf.min+i-1
            b.Text=conf.prefix..tier
            b.BackgroundColor3=tier==eggTier and accent or C.panel2
        end
    end
    tierInfo.Position=UDim2.fromOffset(14,46+rows*46+4)
    tierInfo.Text="Цена: "..(conf.prices[eggTier-conf.min+1] or "?").." · питомцев в яйце: "..#(Z25.EGG_CONTENTS[eggWorld][eggTier] or {})
    updatePets()
end
tierRefresh()
end

-- UPGRADES: one full chain; any available stage runs even if earlier stages are empty.
do
local upgrades=pages["Улучшение"]
local hero=card(upgrades,86,C.gold)
label(hero,"✦ Улучшение всей цепочкой",9,30,16,C.white,true)
label(hero,"Обычные → золотые → радужные → Dark Matter",42,30,11,C.dim)
local check=card(upgrades,138)
upgradePreviewLabel=label(check,"Нажми «Проверить»",12,77,12,C.dim)
button(check,"⟳ ПРОВЕРИТЬ ГРУППЫ",87,function() refreshUpgradePreview() end,C.blue)
local actions=card(upgrades,130,C.gold)
button(actions,"⇧ УЛУЧШИТЬ ВСЮ ЦЕПОЧКУ",12,function()
    confirmUpgrade({"gold","rainbow","dark"})
end,C.gold)
button(actions,"■ СТОП",71,function()
    stopUpgrades("Остановлено. Уже отправленное улучшение могло завершиться.")
end,C.red)
local st=card(upgrades,118)
label(st,"Результат",7,24,14,C.white,true)
upgradeStatusLabel=label(st,"Готово",32,72,12,C.dim)
end

local function loadZoneStorage()
    local PLACE_FILE="ZoneHub_teleports_v23.json" -- preserve prior v2.3 saved zones
    local points={}
    local allowed={}
    for _,z in ipairs(Z25.farmZones) do allowed[z.id]=z.world end
    local function valid(n) return type(n)=="number" and n==n and math.abs(n)<10000000 end
    local function ingest(t)
        if type(t)~="table" or type(t.points)~="table" then return end
        for id,p in pairs(t.points) do
            if allowed[id] and type(p)=="table" and p.world==allowed[id] and
                valid(p.x) and valid(p.y) and valid(p.z) then
                points[id]={x=p.x,y=p.y,z=p.z,world=p.world}
            end
        end
    end
    if type(readfile)=="function" then
        local ok,raw=pcall(readfile,PLACE_FILE)
        if ok and type(raw)=="string" then
            local success,t=pcall(function() return HttpService:JSONDecode(raw) end)
            if success then ingest(t) end
        end
    end
    if type(getgenv)=="function" then
        local e=getgenv()
        if type(e.ZoneHubTeleportPoints)=="table" then ingest({points=e.ZoneHubTeleportPoints}) end
        e.ZoneHubTeleportPoints=points
    end
    Z25.point=function(id) return points[id] end
    local function persist()
        if type(writefile)~="function" then return false end
        local ok,raw=pcall(function() return HttpService:JSONEncode({schema=1,points=points}) end)
        return ok and pcall(writefile,PLACE_FILE,raw)
    end
    function Z25.bindFarmZone(id)
        if not allowed[id] then return false,"Сначала выбери конкретную зону" end
        local r=root()
        if not r then return false,"Персонаж ещё не загрузился" end
        local folder=nodes()
        if not folder then return false,"Игровые монеты ещё не появились" end
        -- Guard against binding a zone from the wrong world/empty lobby.
        local pos=r.Position
        local nearby=0
        for _,coin in ipairs(folder:GetChildren()) do
            local part=partOf(coin)
            if part and (part.Position-pos).Magnitude<=260 then nearby+=1 if nearby>=2 then break end end
        end
        if nearby<2 then return false,"Нет монет рядом. Перейди в нужную игровую зону перед привязкой." end
        points[id]={x=pos.X,y=pos.Y,z=pos.Z,world=allowed[id]}
        local saved=persist()
        return true,"Зона записана: "..Z25.areaDescription()..(saved and " • сохранено на телефон" or " • только до перезапуска")
    end
    -- Coordinates are retained for farm zone binding, while game teleport is a separate tab.
    local count=0
    for _ in pairs(points) do count+=1 end
    return count
end
local countTeleports=loadZoneStorage()
if Z25.refreshZoneButtons then Z25.refreshZoneButtons() end

-- Standalone TELEPORT tab. This restores ONLY the native game's teleport window.
-- It is not placed in the farm tab, and does not change the saved farm coordinates.
do
    local teleportPage=pages["Телепорт"]
    local teleportCard=card(teleportPage,159,C.cyan)
    label(teleportCard,"🗺 Игровой телепорт",10,28,16,C.white,true)
    label(teleportCard,"Открывает стандартное меню игры. Это не кнопка запуска фарма.",38,32,11,C.dim)
    function Z25.openGameTeleport()
        local native=pg:FindFirstChild("Teleport",true)
        if not native then
            log("Стандартный телепорт не найден в PlayerGui. Возможно, игра ещё не загрузила меню.",true)
            return
        end
        if native:IsA("ScreenGui") then
            native.Enabled=true
        elseif native:IsA("GuiObject") then
            native.Visible=true
            local parent=native.Parent
            -- Some game updates hide a parent container as well.
            while parent and parent~=pg do
                if parent:IsA("ScreenGui") then parent.Enabled=true
                elseif parent:IsA("GuiObject") then parent.Visible=true end
                parent=parent.Parent
            end
        else
            log("Найден объект Teleport неподдерживаемого типа: "..native.ClassName,true)
            return
        end
        log("Открыто штатное меню телепорта игры")
    end
    button(teleportCard,"ОТКРЫТЬ ИГРОВОЙ ТЕЛЕПОРТ",88,Z25.openGameTeleport,C.blue)
    local hint=card(teleportPage,101)
    label(hint,"📍 Связь с автофармом",9,28,13,C.white,true)
    label(hint,"В разделе «Фарм» выбери Земля/Луна/Зима: скрипт найдёт монеты во всех загруженных зонах выбранного мира.",38,53,11,C.dim)
end

-- HATS 4.2: choose desired hat, browse real inventory, protect favorites,
-- and optionally remove non-favorite hats only after explicit confirmation.
-- The Hats Delete protocol is inferred and verified by a subsequent server read.
-- Auto-delete is OFF by default, protects equipped, unknown, rare and the top 3.
local hatBusy,hatEpoch=false,0
local HAT_TYPES={
    [10001]="Lei",[10002]="Apple",[10003]="Black Winter Cap",[10004]="Pot",
    [20001]="Paper Hat",[20002]="Cheese",[20003]="Princess Hat",[20004]="Propeller Beanie",
    [20005]="Cowboy Hat",[20006]="Viking",[20007]="Giant Cheese",
    [30001]="Traffic Cone",[30002]="Pirate Hat",[30003]="Chessboard",
    [30004]="Horns",[30005]="Green Banded Top Hat",[30006]="Yellow Banded Top Hat",
    [30007]="White Top Hat",[30008]="Blue Traffic Cone",
    [40001]="Neon Pink Banded Top Hat",[40002]="Rubber Duckie",[40003]="Noob Sign",
    [40004]="Bling Top Hat",[40005]="Hat Stack",[40006]="Blue Top Hat",[40007]="Robux",
    [99001]="Rain Cloud",[99002]="Crown",[99003]="Duke of the Federation",
    [99004]="Lord of the Federation",[99005]="Domino Crown",[99006]="Black Iron Domino Crown"
}
do
    local H={tier="Tier 1",qty=1,items={},count=0,slots=0,used=0,
        selected=nil,target=40007,targetPos=1,keep={},protected={},
        auto=false,maxTrashLevel=0,purchaseStopOnTarget=true,
        purchaseArmed=0,deleteArmed=0,cleanupArmed=0,autoArmed=0,
        last="Сначала обнови шапки. Все удаления выключены.",
        page=1,deleted=0,failed=false,ui={}}
    -- The original 2018 game has four regular present tiers and a fifth
    -- GOLDEN present. Robux may occur in both Tier 4 and Golden.
    local HAT_TIER_CODES={
        ["Tier 1"]={10001,10002,10003,10004},
        ["Tier 2"]={20001,20002,20003,20004,20005,20006,20007},
        ["Tier 3"]={30001,30002,30003,30004,30005,30006,30007,30008},
        ["Tier 4"]={40001,40002,40003,40004,40005,40006,40007},
        ["Golden"]={99001,99002,99003,99004,99005,99006,40007}
    }
    H.target=10001
    H.targetPos=1
    local function tierChoices() return HAT_TIER_CODES[H.tier] or {} end
    local function nameFor(code)
        return HAT_TYPES[code] or ("Неизвестный тип "..tostring(code or "?"))
    end
    local function status(msg,isError)
        H.last=msg
        if H.ui.status then H.ui.status.Text=msg end
        if isError then log("Шапки: "..msg,true) end
    end
    local function snapshot()
        local save,err=readPetSave()
        if not save or type(save.Hats)~="table" then return nil,tostring(err or "Нет Save.Hats") end
        local wear={}
        for _,p in pairs(save.Pets or {}) do
            if type(p)=="table" then
                local hatId=Z25.numberId(p.h)
                if hatId then wear[hatId]=Z25.petNameForType(p.n) or tostring(p.n or "питомец") end
            end
        end
        local items={}
        local seen={}
        for _,hat in pairs(save.Hats) do
            if type(hat)=="table" then
                local id=Z25.numberId(hat.id)
                if id and not seen[id] then
                    seen[id]=true
                    items[#items+1]={id=id,typecode=tonumber(hat.n),level=tonumber(hat.l) or 0,wear=wear[id]}
                end
            end
        end
        table.sort(items,function(a,b)
            if a.level==b.level then return a.id<b.id end
            return a.level>b.level
        end)
        local attached=0
        for _,item in ipairs(items) do if item.wear then attached+=1 end end
        return {items=items,count=#items,slots=tonumber(save.HatSlots) or 10,used=attached}
    end
    local function display()
        local ui=H.ui
        if ui.summary then
            ui.summary.Text=string.format("СЕРВЕР: %d/%d шапок • надето %d • удалено %d",H.count,H.slots,H.used,H.deleted)
        end
        if ui.target then ui.target.Text="🎯 НУЖНА: "..nameFor(H.target).." ["..H.target.."]" end
        if ui.keep then ui.keep.Text="⭐ ОСТАВЛЯТЬ ЭТОТ ТИП: "..(H.keep[H.target] and "ДА" or "НЕТ") end
        if ui.auto then ui.auto.Text=H.auto and "■ АВТОУДАЛЕНИЕ: ВКЛ (выключить)" or "🗑 АВТОУДАЛЕНИЕ: ВЫКЛ (2 НАЖАТИЯ)" end
        if ui.level then ui.level.Text="УДАЛЯТЬ МУСОР С УРОВНЕМ ДО: "..(H.maxTrashLevel==0 and "ЛЮБОГО" or tostring(H.maxTrashLevel)) end
        if ui.stopTarget then ui.stopTarget.Text="СТОП ПРИ ВЫПАДЕНИИ НУЖНОЙ: "..(H.purchaseStopOnTarget and "ДА" or "НЕТ") end
        if ui.status then ui.status.Text=H.last end
        if ui.tier then ui.tier.Text="🎁 Выбран подарок: "..(H.tier=="Golden" and "Tier 5 / Golden" or H.tier) end
        if ui.tierButtons then
            for _,rec in ipairs(ui.tierButtons) do
                rec.button.BackgroundColor3=rec.tier==H.tier and C.purple or C.panel2
            end
        end
        if ui.hatChoices then
            local codes=tierChoices()
            for i,b in ipairs(ui.hatChoices) do
                local code=codes[i]
                b.Visible=code~=nil
                if code then
                    b.Text=(H.target==code and "● " or H.keep[code] and "✓ " or "○ ")..nameFor(code)
                    b.BackgroundColor3=H.target==code and C.blue or H.keep[code] and C.green or C.panel2
                end
            end
        end
        if ui.qty then ui.qty.Text="КОЛИЧЕСТВО: ×"..H.qty end
        local active=nil
        for _,r in ipairs(H.items) do if r.id==H.selected then active=r break end end
        if ui.selected then
            if active then
                ui.selected.Text=string.format("ВЫБРАНА: %s\nID %d • ур. %.0f • %s",nameFor(active.typecode),active.id,active.level,
                    active.wear and ("надета: "..active.wear) or "свободна")
            else
                ui.selected.Text="Нажми шапку в списке ниже — выберется конкретный ID"
            end
        end
        if ui.protect then ui.protect.Text=H.selected and ("ЗАЩИТА ВЫБРАННОЙ: "..(H.protected[H.selected] and "ДА" or "НЕТ")) or "ЗАЩИТА ВЫБРАННОЙ" end
        if ui.entries then
            local per=6
            local first=(H.page-1)*per+1
            for i,b in ipairs(ui.entries) do
                local r=H.items[first+i-1]
                b.Visible=r~=nil
                if r then
                    local flag=r.id==H.selected and "● " or ""
                    local lock=(r.wear or H.protected[r.id] or H.keep[r.typecode] or r.typecode==H.target) and " 🔒" or ""
                    b.Text=flag..nameFor(r.typecode).." | ур. "..math.floor(r.level)..lock
                    b.BackgroundColor3=r.id==H.selected and C.blue or C.panel2
                end
            end
            if ui.paging then
                ui.paging.Text=string.format("СТР. %d/%d · НАЖМИ ШАПКУ ДЛЯ ВЫБОРА",H.page,math.max(1,math.ceil(#H.items/per)))
            end
        end
    end
    local function refresh(origin)
        local snap,err=snapshot()
        if not snap then status("Нет данных шапок: "..tostring(err),true) return nil end
        H.items,H.count,H.slots,H.used=snap.items,snap.count,snap.slots,snap.used
        H.page=math.min(H.page,math.max(1,math.ceil(#H.items/6)))
        if origin~="purchase" and origin~="delete" then H.last="Инвентарь обновлён. Можно выбирать шапки и защиту." end
        display()
        return snap
    end
    local function isTrash(item,snap)
        if not item or not item.id or not item.typecode then return false end
        -- Never blindly delete equipped hats, unknown types, very rare hats,
        -- manually protected items, the chosen target type, and the 3 strongest.
        if item.wear or H.protected[item.id] or not HAT_TYPES[item.typecode] or item.typecode>=99000 then return false end
        -- Safeguard original-game high-rarity hats (Giant Cheese/Robux and special Tier 3/4).
        local rare={[20007]=true,[30007]=true,[30008]=true,[40001]=true,[40004]=true,[40007]=true}
        if rare[item.typecode] then return false end
        if H.keep[item.typecode] or item.typecode==H.target then return false end
        if H.maxTrashLevel>0 and item.level>H.maxTrashLevel then return false end
        for i=1,math.min(3,#snap.items) do
            if snap.items[i].id==item.id then return false end
        end
        return true
    end
    local function hatRemote()
        local wr=workspace:FindFirstChild("__REMOTES")
        local gameRemotes=wr and wr:FindFirstChild("Game")
        local remote=gameRemotes and gameRemotes:FindFirstChild("Hats")
        if remote and remote:IsA("RemoteFunction") then return remote end
        return nil
    end
    local function deleteOne(item,source)
        if not alive then return false,"Закрыто" end
        local before,err=snapshot()
        if not before then return false,"Нет данных: "..tostring(err) end
        local current=nil
        for _,row in ipairs(before.items) do if row.id==item.id then current=row break end end
        if not current then return true,"Уже отсутствует" end
        if not isTrash(current,before) then return false,"Шапка защищена. Удаление отменено" end
        local remote=hatRemote()
        if not remote then return false,"RemoteFunction Game.Hats не найдена" end
        -- Inferred from the original game's Inventory Delete convention. A
        -- response alone is never proof: we require the ID to vanish from Save.
        local ok,a,b=pcall(function() return remote:InvokeServer("Delete",current.id) end)
        if not ok then return false,"Hats.Delete: "..tostring(a):sub(1,90) end
        local after,why=nil,nil
        local exists=true
        for attempt=1,3 do
            task.wait(.32)
            after,why=snapshot()
            if not after then return false,"Невозможно проверить удаление: "..tostring(why) end
            exists=false
            for _,row in ipairs(after.items) do
                if row.id==current.id then exists=true break end
            end
            if not exists then break end
        end
        if exists then return false,"ID сохранился: сервер не подтвердил Delete. Ответ "..tostring(a):sub(1,35) end
        H.deleted+=1
        H.last="Подтверждено удаление: "..nameFor(current.typecode).." ID "..current.id
        refresh("delete")
        return true,H.last
    end
    local function runCleanup(existing)
        if hatBusy or farming or converting or eggRunning then
            status("Останови фарм, яйца и покупки перед очисткой",true) return
        end
        local snap=refresh("manual")
        if not snap then return end
        local trash={}
        for _,row in ipairs(snap.items) do
            if isTrash(row,snap) then trash[#trash+1]=row end
        end
        if #trash==0 then status("Мусора по выбранным правилам не найдено") return end
        local now=os.clock()
        if now-H.cleanupArmed>9 then
            H.cleanupArmed=now
            status("К УДАЛЕНИЮ "..#trash.." шапок. Повтори нажатие за 9 сек (за проход максимум 10).")
            return
        end
        H.cleanupArmed=0
        hatBusy=true hatEpoch+=1
        local epoch=hatEpoch
        task.spawn(function()
            local deleted=0
            for i=1,math.min(10,#trash) do
                if not alive or not hatBusy or hatEpoch~=epoch then break end
                local ok,msg=deleteOne(trash[i],"manual")
                if not ok then status("Очистка остановлена: "..msg,true) break end
                deleted+=1
                task.wait(.15)
            end
            if epoch==hatEpoch then
                hatBusy=false
                status("Очистка: подтверждено удалений "..deleted..". Остальное — следующий проход.")
                refresh("delete")
            end
        end)
    end
    local function purchase()
        if hatBusy or farming or eggRunning or converting then
            status("Останови другие режимы перед покупкой",true) return
        end
        local now=os.clock()
        if now-H.purchaseArmed>8 then
            H.purchaseArmed=now
            status("Подтверди покупку "..H.tier.." ×"..H.qty.." повторным нажатием за 8 сек")
            return
        end
        H.purchaseArmed=0
        local _,shop=eggRemotes()
        if not shop then status("Сервер Shop недоступен",true) return end
        hatBusy=true hatEpoch+=1
        local epoch=hatEpoch
        task.spawn(function()
            local bought,erased=0,0
            for i=1,H.qty do
                if not alive or not hatBusy or hatEpoch~=epoch then break end
                local before,err=snapshot()
                if not before then status("Нет инвентаря: "..tostring(err),true) break end
                if before.count>=before.slots then
                    status("Нет свободных слотов. Очисти мусор вручную или включи безопасный фильтр.",true)
                    break
                end
                local ok,a,b=pcall(function() return shop:InvokeServer("Buy","Presents",H.tier) end)
                if not ok then
                    status("Ошибка запроса подарка: "..tostring(a):sub(1,80),true)
                    break
                end
                -- Shop implementations return different values: only a NEW
                -- server inventory ID counts as a successfully opened present.
                local old={}
                for _,row in ipairs(before.items) do old[row.id]=true end
                local after,why=nil,nil
                local fresh={}
                for attempt=1,3 do
                    task.wait(.34)
                    after,why=snapshot()
                    if not after then break end
                    fresh={}
                    for _,row in ipairs(after.items) do if not old[row.id] then fresh[#fresh+1]=row end end
                    if #fresh>0 then break end
                end
                if not after then status("Не удалось подтвердить покупку: "..tostring(why),true) break end
                if #fresh==0 then
                    status("Новые ID в Save.Hats отсутствуют; остановка для безопасности",true)
                    break
                end
                bought+=1
                local found=false
                for _,row in ipairs(fresh) do
                    if row.typecode==H.target then found=true end
                end
                if H.auto then
                    for _,row in ipairs(fresh) do
                        if not alive or not hatBusy or hatEpoch~=epoch then break end
                        H.known[row.id]=true
                        if isTrash(row,after) then
                            local done,msg=deleteOne(row,"auto")
                            if done then erased+=1 else
                                H.auto=false
                                status("Автоудаление ОТКЛЮЧЕНО: "..msg,true)
                                display()
                                break
                            end
                        end
                    end
                end
                status(string.format("Открыто %d/%d • удалено %d%s",bought,H.qty,erased,found and " • ЦЕЛЬ НАЙДЕНА" or ""))
                refresh("purchase")
                if found and H.purchaseStopOnTarget then break end
                task.wait(.22)
            end
            if epoch==hatEpoch then
                hatBusy=false
                H.last=string.format("Покупок подтверждено %d/%d • удалено %d",bought,H.qty,erased)
                refresh("purchase")
            end
        end)
    end
    -- Watch for new hats from the game's normal shop too, not only hub purchases.
    -- Baseline all existing hats when armed; never automatically delete older items.
    H.known={}
    local function baselineHats()
        local snap,err=snapshot()
        if not snap then return false,err end
        H.known={}
        for _,row in ipairs(snap.items) do H.known[row.id]=true end
        return true
    end
    task.spawn(function()
        while alive do
            task.wait(5)
            if alive and H.auto and not hatBusy and not converting and not eggRunning then
                local snap=snapshot()
                if snap then
                    for _,row in ipairs(snap.items) do
                        if not alive or not H.auto or hatBusy then break end
                        if not H.known[row.id] then
                            H.known[row.id]=true
                            if isTrash(row,snap) then
                                local ok,msg=deleteOne(row,"watcher")
                                if not ok then
                                    H.auto=false
                                    status("Автоудаление остановлено: "..msg,true)
                                    display()
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
    end)
    local hatsPage=pages["Шапки"]
    local hero=card(hatsPage,121,C.cyan)
    label(hero,"🎩  Шапки · управление",8,28,15,C.white,true)
    H.ui.summary=label(hero,"Серверные шапки: ещё не загружено",37,34,12,C.green,true)
    button(hero,"↻ ОБНОВИТЬ ШАПКИ",74,function() refresh("manual") end,C.blue)

    -- Compact Android sub-navigation: only the selected hat workflow is shown.
    local tabsCard=card(hatsPage,61,C.blue)
    local hatTabButtons={}
    local hatTabMode="select"
    local showHatTab -- implemented after all cards are created
    for i,tab in ipairs({{"🎯 ВЫБОР","select"},{"🎁 ПОДАРКИ","shop"},{"🗑 ОЧИСТКА","clean"}}) do
        local mode=tab[2]
        local b=button(tabsCard,tab[1],11,function()
            hatTabMode=mode
            if showHatTab then showHatTab(mode) end
        end,C.panel2)
        b.Position=UDim2.new((i-1)/3,5,0,11)
        b.Size=UDim2.new(1/3,-8,0,39)
        b.TextSize=10
        hatTabButtons[#hatTabButtons+1]={b=b,mode=mode}
    end
    local targetCard=card(hatsPage,399,C.purple)
    label(targetCard,"🎩  Подарки: выбери один из 5 тиров",8,27,14,C.white,true)
    H.ui.tierButtons={}
    for i,tier in ipairs({"Tier 1","Tier 2","Tier 3","Tier 4","Golden"}) do
        local picked=tier
        local caption=tier=="Golden" and "TIER 5" or string.upper(tier)
        local b=button(targetCard,caption,42,function()
            if hatBusy then status("Останови открытие подарков") return end
            H.tier=picked
            H.target=tierChoices()[1]
            H.purchaseArmed=0
            display()
        end,C.panel2)
        b.Position=UDim2.new((i-1)%3/3,5,0,42+math.floor((i-1)/3)*44)
        b.Size=UDim2.new(1/3,-8,0,38)
        b.TextSize=10
        H.ui.tierButtons[#H.ui.tierButtons+1]={tier=tier,button=b}
    end
    label(targetCard,"Выбери нужную шапку из выбранного тира (как питомца в яйцах):",135,38,11,C.dim)
    H.ui.hatChoices={}
    for i=1,8 do
        local ix=i
        local b=button(targetCard,"",172+math.floor((i-1)/2)*39,function()
            local code=tierChoices()[ix]
            if not code then return end
            H.target=code
            H.purchaseArmed=0
            display()
        end,C.panel2)
        b.Position=UDim2.new((i-1)%2/2,5,0,172+math.floor((i-1)/2)*39)
        b.Size=UDim2.new(.5,-8,0,34)
        b.TextSize=9
        H.ui.hatChoices[#H.ui.hatChoices+1]=b
    end
    H.ui.target=label(targetCard,"",319,26,10,C.gold,true)
    H.ui.keep=button(targetCard,"⭐ ОСТАВЛЯТЬ ВЫБРАННЫЙ ТИП",354,function()
        if not H.target then return end
        H.keep[H.target]=not H.keep[H.target]
        display()
    end,C.green)
    H.ui.keep.Size=UDim2.new(1,-28,0,34)
    local inv=card(hatsPage,484,C.blue)
    label(inv,"📋  Мои шапки · нажми конкретный экземпляр",8,29,13,C.white,true)
    H.ui.paging=label(inv,"",37,24,11,C.dim)
    H.ui.entries={}
    for i=1,6 do
        local n=i
        local b=button(inv,"",65+(i-1)*44,function()
            local row=H.items[(H.page-1)*6+n]
            if row then H.selected=row.id display() end
        end,C.panel2)
        b.TextSize=11
        H.ui.entries[#H.ui.entries+1]=b
    end
    local p=button(inv,"◀ НАЗАД",334,function() H.page=math.max(1,H.page-1) display() end,C.panel2)
    p.Position=UDim2.new(0,14,0,334) p.Size=UDim2.new(.5,-18,0,39)
    local n=button(inv,"ВПЕРЁД ▶",334,function() H.page=math.min(math.max(1,math.ceil(#H.items/6)),H.page+1) display() end,C.panel2)
    n.Position=UDim2.new(.5,4,0,334) n.Size=UDim2.new(.5,-18,0,39)
    H.ui.selected=label(inv,"Шапка не выбрана",378,51,11,C.gold,true)
    H.ui.protect=button(inv,"🔒 ЗАЩИТА ВЫБРАННОЙ",431,function()
        if not H.selected then status("Сначала выбери шапку в списке") return end
        H.protected[H.selected]=not H.protected[H.selected]
        display()
    end,C.panel2)

    local shopCard=card(hatsPage,326,C.gold)
    label(shopCard,"🎁  Подарки · поиск нужной",8,27,14,C.white,true)
    label(shopCard,"Выбор по 5 тирам выше: Tier 1–4 или Golden (пятый). При выпадении остановится по выбору.",36,40,11,C.dim)
    H.ui.tier=label(shopCard,"",78,38,12,C.gold,true)
    H.ui.qty=button(shopCard,"",126,function()
        local choices={1,5,10,25}
        for i,value in ipairs(choices) do if value==H.qty then H.qty=choices[i%#choices+1] break end end
        H.purchaseArmed=0 display()
    end,C.panel2)
    H.ui.stopTarget=button(shopCard,"",174,function()
        H.purchaseStopOnTarget=not H.purchaseStopOnTarget
        display()
    end,C.panel2)
    button(shopCard,"▶ КУПИТЬ ПОДАРКИ (2 НАЖАТИЯ)",226,purchase,C.green)
    button(shopCard,"■ ОСТАНОВИТЬ",275,function()
        hatBusy=false hatEpoch+=1
        status("Остановлено. Запрос, уже отправленный серверу, мог завершиться.")
    end,C.red)

    local trashCard=card(hatsPage,269,C.red)
    label(trashCard,"🗑  Автоудаление мусорных шапок",8,28,14,C.white,true)
    label(trashCard,"Надетые, редкие, неизвестные, отмеченные и ТОП-3 по уровню не удаляются.",36,46,11,C.dim)
    H.ui.level=button(trashCard,"",87,function()
        local choices={0,1000,100000,10000000}
        for i,value in ipairs(choices) do
            if value==H.maxTrashLevel then H.maxTrashLevel=choices[i%#choices+1] break end
        end
        H.autoArmed=0 display()
    end,C.panel2)
    H.ui.auto=button(trashCard,"",137,function()
        if H.auto then
            H.auto=false
            status("Автоудаление новых шапок выключено")
        elseif os.clock()-H.autoArmed>9 then
            H.autoArmed=os.clock()
            status("ВНИМАНИЕ: новые незащищённые шапки будут удаляться. Нажми ещё раз за 9 секунд")
        else
            H.autoArmed=0
            local safe,why=baselineHats()
            if safe then
                H.auto=true
                status("Автоудаление включено: новые шапки, полученные любым способом; прежние не трогаю")
            else
                H.auto=false
                status("Автоудаление не включено: "..tostring(why),true)
            end
        end
        display()
    end,C.panel2)
    button(trashCard,"🧹 ОЧИСТИТЬ СТАРЫЙ МУСОР (2 НАЖАТИЯ)",189,function() runCleanup(true) end,C.red)
    label(trashCard,"ВКЛ отслеживает новые шапки и при обычном открытии. Delete экспериментальный.",236,29,10,C.dim)

    local statusCard=card(hatsPage,142,C.green)
    label(statusCard,"Статус",8,26,13,C.white,true)
    H.ui.status=label(statusCard,H.last,39,85,11,C.dim)
    H.ui.status.TextYAlignment=Enum.TextYAlignment.Top
    showHatTab=function(mode)
        targetCard.Visible=(mode=="select" or mode=="shop")
        inv.Visible=(mode=="select" or mode=="clean")
        shopCard.Visible=mode=="shop"
        trashCard.Visible=mode=="clean"
        for _,t in ipairs(hatTabButtons) do
            t.b.BackgroundColor3=t.mode==mode and C.blue or C.panel2
        end
    end
    showHatTab(hatTabMode)
    display()
end

-- SETTINGS: preserves 4/4 profile persistence and zone controls.
local settings=pages["Настройки"]
local profileCard=card(settings,126,C.green)
label(profileCard,"🐾  Обученные питомцы",10,27,15,C.white,true)
local profileLabel=label(profileCard,"Чтение профилей…",42,70,12,C.dim)
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
-- In-hub inventory list: unique pet IDs, level and stage, tap to copy.
local petListCard=card(settings,543,C.green)
label(petListCard,"🐾  ИНВЕНТАРЬ ПИТОМЦЕВ · ID",8,29,14,C.white,true)
local pv=Z25.petIDViewer
pv.summary=label(petListCard,"Нажми ОБНОВИТЬ СПИСОК",36,42,11,C.dim)
pv.entries={}
for i=1,8 do
    local ix=i
    local b=button(petListCard,"",89+(i-1)*44,function()
        local pet=pv.items[(pv.page-1)*8+ix]
        if not pet then return end
        pv.selected=pet.id
        if type(setclipboard)=="function" then pcall(setclipboard,tostring(pet.id)) end
        log("Выбран ID питомца "..tostring(pet.id).." • уровень "..tostring(pet.level))
        pv.display()
    end,C.panel2)
    b.TextSize=10
    pv.entries[#pv.entries+1]=b
end
local bPrev=button(petListCard,"◀ НАЗАД",447,function()
    pv.page=math.max(1,pv.page-1) pv.display()
end,C.panel2)
bPrev.Position=UDim2.new(0,14,0,447) bPrev.Size=UDim2.new(.5,-18,0,35)
local bNext=button(petListCard,"ДАЛЬШЕ ▶",447,function()
    pv.page=math.min(math.max(1,math.ceil(#pv.items/8)),pv.page+1) pv.display()
end,C.panel2)
bNext.Position=UDim2.new(.5,4,0,447) bNext.Size=UDim2.new(.5,-18,0,35)
button(petListCard,"↻ ОБНОВИТЬ СПИСОК ID",491,function() pv.refresh() end,C.blue)
function pv.display()
    pv.summary.Text=string.format("ID: %d • стр. %d/%d • выбран: %s",#pv.items,pv.page,
        math.max(1,math.ceil(#pv.items/8)),tostring(pv.selected or "нет"))
    for i,b in ipairs(pv.entries) do
        local pet=pv.items[(pv.page-1)*8+i]
        b.Visible=pet~=nil
        if pet then
            b.Text=string.format("%sID %d | %s | %s | ур. %.0f",
                pet.id==pv.selected and "● " or "",pet.id,pet.name,pet.stage,pet.level)
            b.BackgroundColor3=pet.id==pv.selected and C.blue or C.panel2
        end
    end
end
function pv.refresh()
    local save,err=readPetSave()
    if not save then pv.summary.Text="Ошибка: "..tostring(err) return end
    local items={}
    for _,p in pairs(save.Pets or {}) do
        if type(p)=="table" then
            local id=Z25.numberId(p.id)
            if id then
                items[#items+1]={id=id,level=tonumber(p.l) or 0,
                    name=Z25.petNameForType(p.n) or tostring(p.n or "?"),
                    stage=(p.e==true and "НАДЕТ " or "")..Z25.classify(p)}
            end
        end
    end
    table.sort(items,function(a,b) return a.level==b.level and a.id<b.id or a.level>b.level end)
    pv.items=items pv.page=1 pv.display()
end
local backup=card(settings,191,C.purple)
label(backup,"💾  Резервные копии",9,26,14,C.white,true)
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
local restorePanel=Instance.new("Frame")
restorePanel.Name="RestorePanel"
restorePanel.BackgroundTransparency=1
restorePanel.Size=UDim2.new(1,0,0,117)
restorePanel.Position=UDim2.fromOffset(0,181)
restorePanel.Visible=false
restorePanel.Parent=backup
local jsonInput=entry(restorePanel,"Импорт сохранённых профилей (JSON)",0,"",function()end)
jsonInput.Text="" jsonInput.PlaceholderText="Вставь сохранённый JSON"
button(restorePanel,"ВОССТАНОВИТЬ ПРОФИЛИ",67,function()
    if farming or converting or eggRunning then log("Для импорта останови фарм, яйца и улучшения",true) return end
    local ok,n=loadProfiles(jsonInput.Text)
    if not ok then log("Импорт: "..tostring(n),true) return end
    log("Восстановлено профилей: "..n)
    local saved,msg=saveProfiles()
    if saved then storageStatus=msg else log(msg,true) end
end,C.purple)
local restoreToggle
restoreToggle=button(backup,"▾ ВОССТАНОВЛЕНИЕ (ДОПОЛНИТЕЛЬНО)",135,function()
    restorePanel.Visible=not restorePanel.Visible
    backup.Size=UDim2.new(1,0,0,restorePanel.Visible and 308 or 191)
    restoreToggle.Text=restorePanel.Visible and "▴ СКРЫТЬ ВОССТАНОВЛЕНИЕ" or "▾ ВОССТАНОВЛЕНИЕ (ДОПОЛНИТЕЛЬНО)"
end,C.panel2)


-- Read-only diagnostics. Never triggers shop, equip, fusion, or farm remotes.
-- fpsValue is declared at the top so adaptive egg scheduler can read it.
local fpsFrames=0
local fpsDuration=0
connections[#connections+1]=RunService.RenderStepped:Connect(function(dt)
    if not alive then return end
    fpsFrames+=1
    fpsDuration+=dt
    if fpsDuration>=1 then
        fpsValue=math.floor(fpsFrames/math.max(.01,fpsDuration)+.5)
        fpsFrames=0
        fpsDuration=0
    end
end)
local diagnostics=card(settings,154,C.blue)
label(diagnostics,"🩺  Состояние и ошибки",8,27,14,C.white,true)
Z25.healthLabel=label(diagnostics,"Ожидание данных…",37,58,11,C.dim)
button(diagnostics,"СКОПИРОВАТЬ ЖУРНАЛ",99,function()
    if type(setclipboard)~="function" then log("Буфер обмена Delta недоступен",true) return end
    local lines={"ZoneHub 4.3", "FPS: "..tostring(fpsValue),
        "Фарм: "..tostring(farming),"Яйца: "..tostring(eggRunning),
        "Зона: "..Z25.areaDescription(),"Ошибки: "..stats.clientErrors}
    for _,line in ipairs(logLines) do lines[#lines+1]=line end
    local ok=pcall(setclipboard,table.concat(lines,"\n"))
    log(ok and "Журнал скопирован" or "Не удалось скопировать журнал",not ok)
end,C.blue)

local lastRefresh=0
local function refresh()
    -- Never scan thousands of Roblox coin objects while UI is merely open.
    -- The scan is needed for farm start / target selection, not inventory screens.
    -- Heavy periodic workspace scans were competing with the native inventory GUI.
    -- Mining still scans coins when it needs a new target, using a short cache.
    Z25.coinCount.Text=farming and "Цель удерживается до уничтожения" or "Готов к запуску"
    if Z25.areaLabel then Z25.areaLabel.Text=Z25.areaDescription() end
    if Z25.updateFarmChart then Z25.updateFarmChart(os.clock()) end
    if Z25.healthLabel then
        local coins,mine,pets=nodes()
        Z25.healthLabel.Text="FPS: "..fpsValue.." • ошибок: "..stats.clientErrors.."\nМонеты: "..(coins and "найдены" or "нет").." • Mine: "..(mine and "OK" or "нет").." • Pets: "..(pets and "OK" or "нет")
    end
    if Z25.simpleFarmStat then
        local balance={}
        for k,n in pairs({Coins="Земля",MoonCoins="Луна",SnowCoins="Зима"}) do
            if type(Z25.currency[k])=="number" and type(Z25.currencyStart[k])=="number" then
                balance[#balance+1]=n.." "..string.format("%+.0f",Z25.currency[k]-Z25.currencyStart[k])
            end
        end
        Z25.simpleFarmStat.Text=string.format("Питомцев в очереди: %d • с уроном: %d\nHP: %.0f • исчезло целей: %d • пик задач: %d\nБаланс: %s",Z25.autoPets.ready,Z25.autoPets.rotated,stats.damage,stats.gone,stats.peakWorkers,#balance>0 and table.concat(balance," | ") or "серверные значения не найдены")
    end
    local eggSymbol=eggRunning and "● ОТКРЫВАЕТ" or "● ОЖИДАНИЕ"
    eggStatusLabel.Text=eggSymbol.."\n"..eggMessage
    eggStatusLabel.TextColor3=eggRunning and C.green or C.dim
    local speed=eggStarted>0 and eggOpened/math.max(1,os.clock()-eggStarted) or 0
    eggCountLabel.Text="Покупок: "..eggAttempts.." • питомцев: "..eggOpened.." • доп.: "..eggAdditionalPets.." • "..string.format("%.1f",speed).." питомцев/с"
    if eggPerfButton then eggPerfButton.Text="СКОРОСТЬ: "..(eggPerfMode=="turbo" and "ТУРБО · до 36 запросов" or eggPerfMode=="fast" and "БЫСТРО · до 24 запросов" or "АВТО · до 12 запросов") end
    if Z25.eggFusionLabel then Z25.eggFusionLabel.Text="Скрещено групп: "..Z25.eggFusion.done.." • "..Z25.eggFusion.last end
    if Z25.eggFilterLabel then Z25.eggFilterLabel.Text="Режим: "..Z25.eggFilter.mode.." • оставить: "..Z25.countKeepTypes().." типов\nСохранено: "..Z25.eggFilter.kept.." • удалено: "..Z25.eggFilter.deleted.." • защищено: "..Z25.eggFilter.protected.."\n"..Z25.eggFilter.last end
    if Z25.eggFilterLabel then Z25.eggFilterLabel.TextColor3=Z25.eggFilter.mode=="active" and C.gold or C.dim end
    if Z25.activeFilterButton then Z25.activeFilterButton.Text=Z25.eggFilter.mode=="active" and "■ ВЫКЛЮЧИТЬ АВТОУДАЛЕНИЕ" or "🗑 АВТОУДАЛЕНИЕ (2 НАЖАТИЯ)" end
    
    Z25.workLabel.Text=farming and (Z25.paused and "Ⅱ  ФАРМ НА ПАУЗЕ" or ("●  ФАРМ: "..stats.workers.." ЗАДАЧ")) or "●  ОСТАНОВЛЕН"
    Z25.workLabel.TextColor3=farming and C.green or C.red
    livePill.Text=converting and "● UP" or farming and "● FARM" or eggRunning and "● EGGS" or "● IDLE"
    livePill.TextColor3=(farming or eggRunning or converting) and C.green or C.dim
    Z25.startButton.Text=farming and "■  ОСТАНОВИТЬ АВТОФАРМ" or "▶  ЗАПУСТИТЬ АВТОФАРМ"
    Z25.startButton.BackgroundColor3=farming and C.red or C.blue
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
    hatBusy=false hatEpoch+=1
    alive=false
    for _,conn in ipairs(connections) do pcall(function() conn:Disconnect() end) end
    pcall(function() gui:Destroy() end)
end
if type(getgenv)=="function" then getgenv().ZoneHubShutdown=shutdown end
switch("Фарм",true)
refresh()
log("ZoneHub 4.3: 5 tiers / Pet IDs / 165-pet rotation / continuous eggs; точек "..tostring(countTeleports))

end -- createZoneHubUI

-- A protected startup reports failure instead of silently leaving no UI.
local uiOk, uiErr = pcall(createZoneHubUI)
if not uiOk then
    warn("ZoneHub 4.3 | UI startup error: "..tostring(uiErr))
    pcall(function()
        local gui = game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")
        if gui then
            local message = Instance.new("Hint")
            message.Name="ZoneHub_StartError"
            message.Text="ZoneHub: ошибка запуска. Открой Delta Console: "..tostring(uiErr):sub(1,130)
            message.Parent=workspace
            task.delay(12,function() pcall(function() message:Destroy() end) end)
        end
    end)
end
