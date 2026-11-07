-- ZoneHub v5.3 | ALL-PETS ROSTER | WINTER 3+4 / MOON 17 | FASTER VERIFIED EGG WAVES
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")
local priorErrorHint = workspace:FindFirstChild("ZoneHub_StartError")
if priorErrorHint then priorErrorHint:Destroy() end

if type(getgenv)=="function" then
    local env=getgenv()
    if type(env.ZoneHubShutdown)=="function" then pcall(env.ZoneHubShutdown) end
    if type(env.ZoneHubAlphaShutdown)=="function" then pcall(env.ZoneHubAlphaShutdown) end
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
Z25.area="world" -- farm every loaded zone in one chosen world
Z25.point=nil
Z25.areaLabel=nil
Z25.radius=420
Z25.sleighCache={coin=nil,at=-1e9}
Z25.sleighState={coin=nil,hp=nil,killed=false}
Z25.coverageVisits={}
Z25.coverageSectors=0
function Z25.areaDescription()
    if Z25.area=="world" then
        local names={Earth="Земля — все зоны",Moon="Луна — все зоны",Winter="Зима — все зоны",Sleigh="Сани — одна общая цель"}
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
local eggPerfMode="fast" -- faster default; adaptive backoff on slow responses/rejections. Never modifies server odds.
local eggActiveBatch=0
local eggWaveSeconds=0
local fpsValue=0 -- populated by read-only FPS monitor below
local eggPerfButton, eggFarmPauseButton
local eggMessage = "Выбери мир и яйцо. Покупка не запущена"
-- Independent presets for a two-egg opening session. No second autonomous Shop loop:
-- both eggs share the verified inventory snapshot and request budget.
local dualEggMode=false
local dualEgg={
    winter3={["78005"]=true},winter4={["78005"]=true,["79003"]=true},moon={["17009"]=true},
    includeT3=true,merged={},fuseEnabled=false,fuseType=nil,
    winter3Sent=0,winter4Sent=0,moonSent=0,confirmationUntil=0,
    savedFusionType=nil,message="Выбирай питомцев для сохранения. Рандольф защищён в T3/T4."
}

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
-- Safety-first: never auto-delete these rare new pets even if omitted from keep list.
-- p.n is the PET TYPE code. p.id is a unique inventory ID, do not confuse them.
Z25.protectedEggTypes={['78005']='Randolph',['79003']='Giant Penguin',['17009']='Dominus Huge'}
Z25.eggFilter={mode="off",keep={},kept=0,deleted=0,rainbowDeleted=0,goldDeleted=0,protected=0,preview=0,
    rareDrops={},limit=30,last="Фильтр выключен. Сначала выбери нужного питомца.",pendingAt=0}
Z25.eggFilterLabel=nil
function Z25.dualKeepRebuild()
    local merged={}
    if dualEgg.includeT3 then
        for code,enabled in pairs(dualEgg.winter3) do if enabled then merged[code]=true end end
    end
    for code,enabled in pairs(dualEgg.winter4) do if enabled then merged[code]=true end end
    for code,enabled in pairs(dualEgg.moon) do if enabled then merged[code]=true end end
    dualEgg.merged=merged
end
function Z25.activeEggKeep()
    return dualEggMode and dualEgg.merged or Z25.eggFilter.keep
end
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
Z25.inventoryLabel, Z25.eggLabel = nil,nil
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
    for _,p in pairs(save.Pets) do
        if type(p)=="table" then
            snap.count+=1
            local stage=Z25.classify(p)
            snap[stage]+=1
            if Z25.trueFlag(p.e) then snap.equipped+=1 end
        end
    end
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
    if Z25.eggLabel then Z25.eggLabel.Text="Сервер: "..snap.count.." / "..tostring(snap.capacity or "?").." • "..snap.updated end
end
local connections, reserved, learned = {}, {}, {}
local lockedTargets={}
local logLines = {}
local cfg = {
    ids={15883528,25214651,92565120,95608754}, -- archival IDs, not current equipped list
    minX=-3218.733,maxX=-2832.849,minZ=-1747.956,maxZ=-1468.381,
    groundY=144.810,interval=.42,mode="Near"
}
local stats = {mine=0, move=0, clientErrors=0, damage=0, gone=0, noProgress=0, workers=0,
    targetReused=0,targetChanged=0,started=0,perPet={},peakWorkers=0}
Z25.autoPets={mode="all",allVerified=false,checking=false,total=0,equipped=0,ready=0,rotated=0,
    last="Не проверен",rejected={},success={},pool={},activeCount=165,minLevel=0,lockedIDs=nil,lockedCount=0,
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
-- Cache parts across hits/scans; keep weak keys so destroyed coins are not retained.
local partCache=setmetatable({},{__mode="kv"})
local function partOf(o)
    if not o then return nil end
    if o:IsA("BasePart") then return o end
    local cached=partCache[o]
    if cached and cached.Parent and cached:IsDescendantOf(o) then return cached end
    local part=(o:IsA("Model") and o.PrimaryPart) or o:FindFirstChildWhichIsA("BasePart",true)
    if part then partCache[o]=part else partCache[o]=nil end
    return part
end
local function root()
    return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
end
local cachedNodes={coins=nil,mine=nil,pets=nil}
local function nodes()
    local cached=cachedNodes
    if cached.coins and cached.coins.Parent and cached.mine and cached.mine.Parent
        and cached.pets and cached.pets.Parent then
        return cached.coins,cached.mine,cached.pets
    end
    local things=workspace:FindFirstChild("__THINGS")
    local coins=things and things:FindFirstChild("Coins")
    local remotes=workspace:FindFirstChild("__REMOTES")
    local gameRemotes=remotes and remotes:FindFirstChild("Game")
    local mine=gameRemotes and gameRemotes:FindFirstChild("Coins")
    local pets=gameRemotes and gameRemotes:FindFirstChild("Pets")
    if mine and not mine:IsA("RemoteEvent") then mine=nil end
    if pets and not pets:IsA("RemoteEvent") then pets=nil end
    cached.coins,cached.mine,cached.pets=coins,mine,pets
    return coins,mine,pets
end
Z25.coinWorldCache=setmetatable({},{__mode="k"})
Z25.coinWorldMissingAt=setmetatable({},{__mode="k"})
local function coinWorld(coin)
    if not coin then return nil end
    local cached=Z25.coinWorldCache[coin]
    if cached~=nil then return cached~=false and cached or nil end
    local lastMiss=Z25.coinWorldMissingAt[coin]
    if lastMiss and os.clock()-lastMiss<4 then return nil end
    local marker=coin:FindFirstChild("CoinName",true)
    local coinName=nil
    if marker and marker:IsA("StringValue") then coinName=marker.Value end
    if not coinName then coinName=coin:GetAttribute("CoinName") end
    if type(coinName)~="string" then
        local raw=string.lower(tostring(coin.Name))
        if raw:find("sleigh",1,true) then return "Sleigh" end
        Z25.coinWorldMissingAt[coin]=os.clock()
        return nil
    end
    local world=nil
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
        if lower:find("sleigh",1,true) then world="Sleigh"
        elseif lower:find("christmas",1,true) then world="Winter"
        elseif lower=="dominus chest" or lower=="grim chest" then world="Moon"
        elseif lower=="super chest" or lower=="omega chest" then world="Earth"
        else
            local zone=tonumber(coinName:match("^(%d+)%s"))
            if zone and zone>=1 and zone<=6 then world="Earth"
            elseif zone and zone>=7 and zone<=10 then world="Moon" end
        end
    end
    if string.lower(coinName):find("sleigh",1,true) then world="Sleigh" end
    if world then Z25.coinWorldCache[coin]=world
    else Z25.coinWorldMissingAt[coin]=os.clock() end
    return world
end
local function inside(p,coin)
    if Z25.area=="world" then
        local world=coinWorld(coin)
        if Z25.farmWorld=="Winter" then return world=="Winter" or world=="Sleigh" end
        return world==Z25.farmWorld
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
function Z25.coverageCell(pos)
    local base=(Z25.area=="world" and Z25.worldAnchors[Z25.farmWorld]) or
        (Z25.area=="near" and Z25.nearPoint) or
        (Z25.point and Z25.point(Z25.area))
    if not base then return tostring(math.floor(pos.X/290))..":"..tostring(math.floor(pos.Z/290)) end
    return tostring(math.floor((pos.X-base.x)/110))..":"..tostring(math.floor((pos.Z-base.z)/110))
end
local healthValues=setmetatable({},{__mode="k"})
local HEALTH_NAMES={"Health","HP","Hp","health"}
local function health(o)
    if not o then return nil end
    local ref=healthValues[o]
    if ref and ref.Parent then return ref.Value end
    for _,name in ipairs(HEALTH_NAMES) do
        local v=o:FindFirstChild(name,true)
        if v and (v:IsA("NumberValue") or v:IsA("IntValue")) then
            healthValues[o]=v
            return v.Value
        end
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
function Z25.findSleigh()
    local now=os.clock()
    local cached=Z25.sleighCache
    if cached.coin and cached.coin.Parent and (health(cached.coin) or 0)>0 and
        coinWorld(cached.coin)=="Sleigh" then
        return cached.coin
    end
    if now-cached.at<2.0 then return nil end
    cached.at=now
    cached.coin=nil
    local coins=nodes()
    if not coins then return nil end
    local best,bestHP=nil,-1
    for _,coin in ipairs(coins:GetChildren()) do
        if coinWorld(coin)=="Sleigh" then
            local hp=health(coin)
            if type(hp)=="number" and hp>0 and partOf(coin) and hp>bestHP then
                best,bestHP=coin,hp
            end
        end
    end
    if not best then
        local things=workspace:FindFirstChild("__THINGS")
        local spawns=things and things:FindFirstChild("Coin Spawns")
        local anchor=spawns and spawns:FindFirstChild("Sleigh")
        local anchorPart=partOf(anchor)
        if anchorPart then
            local pos=anchorPart.Position
            local closest=100
            for _,coin in ipairs(coins:GetChildren()) do
                local hp=health(coin)
                local world=coinWorld(coin)
                if type(hp)=="number" and hp>0 and (world=="Winter" or world==nil) then
                    local part=partOf(coin)
                    if part then
                        local distance=(part.Position-pos).Magnitude
                        local limit=world=="Winter" and 65 or 35
                        if distance<math.min(closest,limit) and (world=="Winter" or hp>=1e9) then
                            best=coin
                            closest=distance
                        end
                    end
                end
            end
        end
    end
    if best then Z25.coinWorldCache[best]="Sleigh" end
    cached.coin=best
    return best
end
local function orderCoins(items)
    local r=root()
    local reference=Z25.area=="world" and Z25.worldAnchors[Z25.farmWorld] or nil
    local o=reference and Vector3.new(reference.x,reference.y,reference.z) or
        (r and r.Position or Vector3.new((cfg.minX+cfg.maxX)/2,cfg.groundY,(cfg.minZ+cfg.maxZ)/2))
    for _,item in ipairs(items) do
        local delta=item.pos-o
        item.sortDistance=delta:Dot(delta) -- squared distance; no sqrt per sort comparison
    end
    local mode=cfg.mode
    if mode=="LowHP" then
        table.sort(items,function(a,b)
            return a.hp==b.hp and a.sortDistance<b.sortDistance or a.hp<b.hp
        end)
    elseif mode=="HighHP" then
        table.sort(items,function(a,b)
            return a.hp==b.hp and a.sortDistance<b.sortDistance or a.hp>b.hp
        end)
    else
        table.sort(items,function(a,b) return a.sortDistance<b.sortDistance end)
    end
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
    if profileCount()<4 then return false,"Сохранение заблокировано: найдено меньше 4/4 профилей" end
    if type(writefile)~="function" then return false,"Запись файлов недоступна" end
    local ok,err=pcall(writefile,PROFILE_FILE,toJson())
    if ok then return true,"Сохранено "..profileCount().."/4 профилей" end
    return false,"Ошибка сохранения: "..tostring(err):sub(1,80)
end
local known={
    {id=25214651,speed=3.5815804004669189,frame=CFrame.new(-3031,141.9644012,-1597),samples={145.05895256996155,175907.17931485176,176728.10179138184,176806.94916629791,176403.91777682304,176601.13730049133,176758.326618433,176452.94467020035}},
    {id=95608754,speed=4.7751576900482178,frame=CFrame.new(-3033,141.9645081,-1566),samples={122.49581408500671,168272.95349677405,168949.72115047774,168528.27377120656}},
    {id=15883528,speed=4.7751576900482178,frame=CFrame.new(-3051,141.9645081,-1533),samples={140.39686107635498,189985.11974716187,190698.23972892761,190765.38130712509,190999.33968448639}},
}
for _,p in ipairs(known) do
    learned[p.id]={samples=p.samples,movement={frame=p.frame,speed=p.speed}}
end
if type(readfile)=="function" then
    local readOk,raw=pcall(readfile,PROFILE_FILE)
    if readOk then
        local ok,n=loadProfiles(raw)
        storageStatus=ok and ("Загружено сохранение ("..n.." проф.)") or ("Сохранение повреждено: "..tostring(n))
    else storageStatus="Файл сохранения не найден" end
else storageStatus="Чтение файлов недоступно" end
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

local eggStatusLabel, eggSelectedLabel, eggCountLabel
local function finishEggFarmPause()
    if eggPausedFarm then
        eggPausedFarm=false
        if alive and farming then Z25.paused=eggPausePrevious end
    end
end
local function stopEggs(reason)
    local wasRunning=eggRunning
    eggRunning=false
    eggEpoch+=1
    Z25.eggFusion.collecting=false
    if dualEggMode then
        dualEggMode=false
        Z25.eggFusion.fuseType=dualEgg.savedFusionType
        if reason then dualEgg.message=reason end
    end
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
    if Z25.eggFilter.mode=="off" and not dualEggMode then return true,false,"" end
    local keep=Z25.activeEggKeep()
    if not next(keep) then return false,false,"Не выбран ни один питомец для сохранения" end
    local prior=indexedPets(beforeSave)
    local after=indexedPets(afterSave)
    local newPets,unexpected={},0
    local allowed={}
    if dualEggMode then
        if dualEgg.includeT3 then
            for _,code in ipairs(Z25.EGG_CONTENTS.Winter[3]) do allowed[tostring(code)]=true end
        end
        for _,code in ipairs(Z25.EGG_CONTENTS.Winter[4]) do allowed[tostring(code)]=true end
        for _,code in ipairs(Z25.EGG_CONTENTS.Moon[17]) do allowed[tostring(code)]=true end
    else
        local eggCatalog=Z25.EGG_CONTENTS[eggWorld] and Z25.EGG_CONTENTS[eggWorld][eggTier]
        if type(eggCatalog)=="table" then
            for _,code in ipairs(eggCatalog) do allowed[tostring(code)]=true end
        end
    end
    local knownCodes=next(allowed)~=nil
    for id,p in pairs(after) do
        if not prior[id] then
            local kind=tostring(p.n or "")
            local stage=Z25.classify(p)
            if knownCodes and allowed[kind] and
                (stage=="normal" or stage=="gold" or stage=="rainbow") and
                not Z25.trueFlag(p.e) then
                newPets[#newPets+1]={id=id,data=p,kind=kind,stage=stage}
            else
                unexpected+=1 -- unknown type, equipped or Dark Matter: protect
            end
        end
    end
    -- Count newly observed rare pets before considering deletion. This is a server-ID
    -- observation, not a probability claim; reset when each opening session begins.
    for _,item in ipairs(newPets) do
        if Z25.protectedEggTypes[item.kind] then
            Z25.eggFilter.rareDrops[item.kind]=(Z25.eggFilter.rareDrops[item.kind] or 0)+1
        end
    end
    if #newPets+unexpected<confirmed or #newPets+unexpected>confirmed*3 then
        return false,false,"Число новых ID не соответствует подтверждённым покупкам; очистка остановлена"
    end
    if unexpected>0 then
        return false,false,"Найдены "..unexpected.." неожиданных ID/вариантов; очистка не будет удалять неизвестное"
    end
    local extraIds=0 -- all verified newly created IDs are in newPets; no ambiguous extras
    local wanted,removable,unknown=0,{},0
    local variantById={}
    local huntedRare=false
    for _,item in ipairs(newPets) do
        local p=item.data
        local name=Z25.petNameForType(item.kind)
        if keep[item.kind] or Z25.protectedEggTypes[item.kind] then
            wanted+=1
            huntedRare=true
        elseif not name or Z25.trueFlag(p.e) or
            (item.stage~="normal" and item.stage~="gold" and item.stage~="rainbow") then
            unknown+=1 -- unknown/equipped/Dark Matter: never delete
        else
            removable[#removable+1]=item.id
            variantById[item.id]=item.stage
        end
    end
    if Z25.eggFusion.collecting then
        for _,item in ipairs(newPets) do
            if Z25.eggFusion.fuseType==item.kind and keep[item.kind] then
                Z25.eggFusion.tracked[item.id]=true
            end
        end
    end
    Z25.eggFilter.kept+=wanted
    Z25.eggFilter.protected+=unknown+extraIds
    if #removable==0 then
        return true,huntedRare,string.format("Оставлено %d, защищено %d, доп. ID %d не трогаю",wanted,unknown,extraIds),0
    end
    if not eggSessionActive(epoch) then return false,wanted>0,"Покупки остановлены до удаления" end
    local gameRemotes=workspace:FindFirstChild("__REMOTES")
    gameRemotes=gameRemotes and gameRemotes:FindFirstChild("Game")
    local inv=gameRemotes and gameRemotes:FindFirstChild("Inventory")
    if not inv or not inv:IsA("RemoteFunction") then
        return false,wanted>0,"Нет Game.Inventory: серверное удаление недоступно"
    end
    local _,_,err,fresh=getEggInventory()
    if err or not fresh then return false,wanted>0,"Ошибка контрольного чтения: "..tostring(err) end
    local current=indexedPets(fresh)
    for _,id in ipairs(removable) do
        local orig=after[id]
        local now=current[id]
        if not now or prior[id] or tonumber(now.id)~=id or tostring(now.n)~=tostring(orig.n)
            or keep[tostring(now.n)] or Z25.protectedEggTypes[tostring(now.n)] or Z25.trueFlag(now.e) or
            Z25.classify(now)~=Z25.classify(orig) or
            (Z25.classify(now)~="normal" and Z25.classify(now)~="gold" and Z25.classify(now)~="rainbow") or
            Z25.trueFlag(now.lock) or Z25.trueFlag(now.locked) or
            Z25.trueFlag(now.lk) or Z25.trueFlag(now.fav) then
            return false,wanted>0,"Контроль удаления не пройден. Питомцы сохранены."
        end
    end
    local removed=0
    local batchSize=6 -- fewer server snapshot round-trips; each ID remains verified
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
                tostring(now.n)~=tostring(orig.n) or keep[tostring(now.n)] or
                Z25.protectedEggTypes[tostring(now.n)] or Z25.trueFlag(now.e) or Z25.classify(now)~=Z25.classify(orig) or
                (Z25.classify(now)~="normal" and Z25.classify(now)~="gold" and Z25.classify(now)~="rainbow") or
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
            task.wait(.014)
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
        local post,postErr
        local missing={}
        for retry=1,5 do
            task.wait(retry==1 and .08 or .20)
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
        for _,removedId in ipairs(missing) do
            if variantById[removedId]=="rainbow" then Z25.eggFilter.rainbowDeleted+=1 end
            if variantById[removedId]=="gold" then Z25.eggFilter.goldDeleted+=1 end
        end
        if #failures>0 or #missing~=#batch then
            return false,wanted>0,"Удалено "..#missing.."/"..#batch.." в группе; остановлено без повторов. "..table.concat(failures,"; ")
        end
    end
    return true,huntedRare,string.format("Оставлено %d, удалено %d (включая невыбранные Rainbow/Gold), защищено %d, доп. ID %d не трогаю",wanted,removed,unknown,extraIds),removed
end

local fuseNewEggPets
function Z25.eggFusionProgress(save)
    local normal,gold,rainbow,oldNormal,oldGold,oldRainbow=0,0,0,0,0,0
    if type(save)~="table" or type(save.Pets)~="table" then
        return false,"Не удалось прочитать инвентарь"
    end
    local chosen=Z25.eggFusion.fuseType
    if not chosen or not Z25.activeEggKeep()[chosen] then return false,"Не выбран питомец для скрещивания" end
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

local function startEggs(mode)
    local isDual=(mode=="dual")
    if isDual then Z25.dualKeepRebuild() end
    if isDual then
        if not next(dualEgg.winter4) or not next(dualEgg.moon) or (dualEgg.includeT3 and not next(dualEgg.winter3)) then
            dualEgg.message="Выбери хотя бы один вид в каждом активном яйце"
            return
        end
        if dualEgg.fuseEnabled and (not dualEgg.fuseType or not dualEgg.merged[dualEgg.fuseType]) then
            dualEgg.message="Выбери вид для скрещивания или выключи его"
            return
        end
    end
    if (mode=="hunt" or mode=="auto") and Z25.eggFilter.mode~="active" then
        eggMessage="Для охоты и автоскрещивания включи автоудаление (дважды)" return
    end
    if mode=="auto" and (not Z25.eggFusion.fuseType or not Z25.eggFilter.keep[Z25.eggFusion.fuseType]) then
        eggMessage="Для автоскрещивания выбери основной вид питомца; второй сохранится без скрещивания" return
    end
    if not isDual and Z25.eggFilter.mode~="off" and Z25.countKeepTypes()==0 then eggMessage="Сначала выбери питомцев, которых оставлять" return end
    if converting then eggMessage="Сначала останови преобразование питомцев" if isDual then dualEgg.message=eggMessage end return end
    if eggRunning then eggMessage="Яйца уже покупаются; нажми СТОП" if isDual then dualEgg.message=eggMessage end return end
    local _,shop=eggRemotes()
    if not shop then eggMessage="Не найден Game.Shop (RemoteFunction)" if isDual then dualEgg.message=eggMessage end log(eggMessage,true) return end
    if mode~="hunt" and mode~="auto" and mode~="dual" then
        eggMessage="Неизвестный режим" return
    end
    eggEpoch+=1
    local epoch=eggEpoch
    local key=isDual and (dualEgg.includeT3 and "Christmas Tier 3 + Christmas Tier 4 + Tier 17" or "Christmas Tier 4 + Tier 17") or eggKey(eggWorld,eggTier)
    local fuseEnabled=(mode=="auto") or (isDual and dualEgg.fuseEnabled)
    if isDual then
        dualEgg.winter3Sent,dualEgg.winter4Sent,dualEgg.moonSent=0,0,0
        dualEgg.savedFusionType=Z25.eggFusion.fuseType
        Z25.eggFusion.fuseType=dualEgg.fuseEnabled and dualEgg.fuseType or nil
        dualEggMode=true
    end
    local totalRequested=type(mode)=="number" and mode or nil -- hunt/auto: no request cap, manual STOP
    local maxWave=isDual and 30 or eggPerfMode=="turbo" and 36 or eggPerfMode=="fast" and 24 or 12
    local waveLimit=maxWave
    local adaptiveWave=isDual and 15 or eggPerfMode=="turbo" and 16 or eggPerfMode=="fast" and 14 or 8
    local responsiveWaves=0
    local waveDelay=.015
    Z25.eggFusion.collecting=fuseEnabled
    Z25.eggFusion.tracked={}
    Z25.eggFusion.done=0
    Z25.eggFusion.blocked=0
    Z25.eggFusion.last=fuseEnabled and "Коплю выбранный вид: 10 обычных / 7 золотых / 5 радужных" or "Автоскрещивание выключено"
    eggRunning=true
    Z25.eggFilter.kept,Z25.eggFilter.deleted,Z25.eggFilter.protected,Z25.eggFilter.preview=0,0,0,0
    Z25.eggFilter.rainbowDeleted,Z25.eggFilter.goldDeleted=0,0
    Z25.eggFilter.rareDrops={}
    eggAttempts,eggOpened,eggConfirmed,eggRejected,eggBatches=0,0,0,0,0
    eggAdditionalPets,eggConfirmedMultiplier=0,nil
    local expectedPetsPerBuy=3
    eggInventory,eggCapacity=nil,nil
    eggStarted=os.clock()
    eggMessage="Подготовка • "..key.." • "..(isDual and (dualEgg.includeT3 and "ТРИ ЯЙЦА ПО ОЧЕРЕДИ" or "ДВА ЯЙЦА 50/50") or mode=="hunt" and "ОХОТА ДО НУЖНОГО" or "АВТОСКРЕЩИВАНИЕ")
    log("Яйца: "..key..", режим "..tostring(mode))
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
                if cachedBefore and os.clock()-cachedBefore.at<1.25 and batchNumber%4~=0 then
                    count,capacity,beforeSave=cachedBefore.count,cachedBefore.capacity,cachedBefore.save
                    errorText=nil
                else
                    count,capacity,errorText,beforeSave=getEggInventory()
                end
                cachedBefore=nil
                if errorText then
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
                local free=math.max(0,math.floor(capacity-count))
                if free<=0 then
                    if fuseEnabled and type(fuseNewEggPets)=="function" then
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
                local safeRequests=math.floor(free/expectedPetsPerBuy)
                if safeRequests<1 then
                    if fuseEnabled and type(fuseNewEggPets)=="function" then
                        local ready,progress=Z25.eggFusionProgress(beforeSave)
                        if ready then
                            local good,converted,detail=fuseNewEggPets(epoch)
                            Z25.eggFusion.last=detail
                            if good and converted>0 then
                                cachedBefore=nil
                                task.wait(.12)
                                continue -- fusion freed slots; refresh inventory next cycle
                            end
                        end
                    end
                    eggMessage="Осталось "..free.." мест; недостаточно для безопасной серии (до "..expectedPetsPerBuy.." питомцев). Сохранён инвентарь."
                    break
                end
                local n=math.min(adaptiveWave,safeRequests,left)
                if n<=0 then break end
                eggActiveBatch=n
                eggBatches+=1
                eggMessage=string.format("%s • группа %d: отправляю %d%s; свободно %d",key,eggBatches,n,isDual and (dualEgg.includeT3 and " (1/3 каждое)" or " (50/50)") or "",free)
                local completed,confirmed,rejected,errors=0,0,0,0
                local waveStarted=os.clock()
                local buyResults={}
                local reason=""
                for i=1,n do
                    if not eggSessionActive(epoch) then break end
                    eggAttempts+=1
                    local purchaseKey=key
                    if isDual then
                        -- Fair round-robin across independent server purchases.
                        local seq=eggAttempts
                        if dualEgg.includeT3 then
                            local k=(seq-1)%3
                            if k==0 then
                                purchaseKey=eggKey("Winter",3) dualEgg.winter3Sent+=1
                            elseif k==1 then
                                purchaseKey=eggKey("Winter",4) dualEgg.winter4Sent+=1
                            else
                                purchaseKey=eggKey("Moon",17) dualEgg.moonSent+=1
                            end
                        else
                            if seq%2==1 then
                                purchaseKey=eggKey("Winter",4) dualEgg.winter4Sent+=1
                            else
                                purchaseKey=eggKey("Moon",17) dualEgg.moonSent+=1
                            end
                        end
                    end
                    task.spawn(function()
                        local invoked,accepted,details=pcall(function()
                            return shop:InvokeServer("Buy","Eggs",purchaseKey)
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
                    if i<n then task.wait(.012) end
                end
                local sent=n
                local waitStarted=os.clock()
                while eggSessionActive(epoch) and completed<sent and os.clock()-waitStarted<22 do
                    task.wait(.045)
                end
                if not eggSessionActive(epoch) then break end
                if completed<sent then
                    eggMessage="Тайм-аут ответов сервера ("..completed.."/"..sent.."); остановлено. Ожидающие покупки ещё могут завершиться"
                    break
                end
                eggConfirmed+=confirmed
                eggRejected+=rejected
                eggWaveSeconds=os.clock()-waveStarted
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
                if (isDual or Z25.eggFilter.mode~="off") and afterSave then
                    local good,found,detail,deletedCount=filterHatchedPets(beforeSave,afterSave,buyResults,confirmed,epoch)
                    Z25.eggFilter.last=detail
                    eggMessage=eggMessage.." • "..detail
                    if not good then break end
                    if mode=="hunt" and found then
                        eggMessage=eggMessage.." • ЦЕЛЬ НАЙДЕНА, ОСТАНОВЛЕНО"
                        break
                    end
                    -- When no pets were deleted, afterSave is already server-verified.
                    -- If removal happened, always re-read to protect subsequent fusion.
                    local postCount,postCap,postErr,postSave=latest,cap,nil,afterSave
                    if deletedCount~=0 then
                        postCount,postCap,postErr,postSave=getEggInventory()
                        if postErr then eggMessage="Ошибка инвентаря после фильтра: "..postErr break end
                        eggInventory,eggCapacity=postCount,postCap
                        verifiedNextCount,verifiedNextCapacity,verifiedNextSave=postCount,postCap,postSave
                    end
                    if fuseEnabled then
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
                    eggMessage=eggMessage.." • достигнут лимит запросов"
                    break
                end
                if not isDual and Z25.eggFilter.mode=="off" and latest>=cap then
                    eggMessage=eggMessage.." • инвентарь заполнен"
                    break
                end
                if verifiedNextSave then
                    cachedBefore={count=verifiedNextCount,capacity=verifiedNextCapacity,
                        save=verifiedNextSave,at=os.clock()}
                end
                task.wait(isDual and .025 or Z25.eggFilter.mode=="active" and .045 or waveDelay)
            end
        end)
        if epoch==eggEpoch then
            eggRunning=false
            eggActiveBatch=0
            Z25.eggFusion.collecting=false
            if isDual then
                dualEggMode=false
                Z25.eggFusion.fuseType=dualEgg.savedFusionType
                dualEgg.message=eggMessage
            end
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
local UPGRADE={
    gold={title="Золото",need=10,remote="Golden Pets",from="normal",to="gold"},
    rainbow={title="Радуга",need=7,remote="Rainbow Pets",from="gold",to="rainbow"},
    dark={title="Dark Matter",need=5,remote="Dark Matter Pets",from="rainbow",to="dark"}
}
local upgradeStatusLabel, upgradePreviewLabel, upgradeProtectButton
local upgradeEpochConfirmed=nil
local upgradeConfirmDeadline=0
local lastUpgradePreview="Нажми «Проверить инвентарь»"
local lastSaveUiRefresh=0
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
    local now=os.clock()
    if now-lastSaveUiRefresh>=1.5 then
        Z25.updateInventory(save,"улучшения/инвентарь")
        lastSaveUiRefresh=now
    end
    return save
end
Z25.readCurrentPetSave=readPetSave
function Z25.numberId(v)
    local n=tonumber(v)
    if not n or n~=n or n<1 or n%1~=0 then return nil end
    return n
end
function Z25.numericPetLevel(p, save, hatLevels)
    local level=tonumber(p.l)
    if not level or level~=level or level<=0 then return nil end
    local hatId=Z25.numberId(p.h)
    if hatId then
        if hatLevels then
            level+=hatLevels[hatId] or 0
        elseif type(save.Hats)=="table" then
            -- Compatibility for callers outside the optimized inventory snapshot.
            for _,hat in pairs(save.Hats) do
                if type(hat)=="table" and Z25.numberId(hat.id)==hatId then
                    local bonus=tonumber(hat.l)
                    if bonus and bonus>0 and bonus==bonus then level+=bonus end
                    break
                end
            end
        end
    end
    return level
end
function Z25.inventoryProfile(id,p,save,hatLevels)
    if learned[id] and learned[id].movement and #learned[id].samples>0 then
        return learned[id],true
    end
    local level=Z25.numericPetLevel(p,save,hatLevels)
    if not level then return nil,false end
    local damageArgument=2*level-1
    if damageArgument<=0 or damageArgument~=damageArgument then return nil,false end
    return {samples={damageArgument,damageArgument,damageArgument},
            movement={speed=4.7751576900482178},derived=true},false
end
function Z25.inventorySnapshot(mode)
    local save,err=readPetSave()
    if not save then return nil,err end
    local result,seen={},{}
    -- Build hat bonus lookup once, not one linear search for each pet.
    local hatLevels={}
    if type(save.Hats)=="table" then
        for _,hat in pairs(save.Hats) do
            if type(hat)=="table" then
                local hid=Z25.numberId(hat.id)
                local bonus=tonumber(hat.l)
                if hid and bonus and bonus>0 and bonus==bonus and not hatLevels[hid] then
                    hatLevels[hid]=bonus
                end
            end
        end
    end
    local count,eq,untrained=0,0,0
    for _,p in pairs(save.Pets) do
        if type(p)=="table" then
            local id=Z25.numberId(p.id)
            if id and not seen[id] then
                seen[id]=true
                count+=1
                local equipped=p.e==true
                if equipped then eq+=1 end
                if (mode=="all" or equipped) and (not Z25.autoPets.lockedIDs or Z25.autoPets.lockedIDs[id]) and (tonumber(p.l) or 0)>0 then
                    local profile,trained=Z25.inventoryProfile(id,p,save,hatLevels)
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
        if a.manual~=b.manual then return a.manual==true end
        local aa=tonumber(a.profile.samples[1]) or 0
        local bb=tonumber(b.profile.samples[1]) or 0
        if aa~=bb then return aa>bb end
        return a.id<b.id
    end)
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
    Z25.autoPets.last="Инвентарь: "..count.." • экипировано: "..eq.." • в фарме: "..#result.." • лимит: "..math.min(165,Z25.autoPets.activeCount).." • расчёт силы: "..untrained
    if Z25.autoPets.lockedIDs then
        Z25.autoPets.last=Z25.autoPets.last.." • 🔒 исходно: "..Z25.autoPets.lockedCount.." • исчезли/недоступны: "..math.max(0,Z25.autoPets.lockedCount-#result)
    end
    if Z25.farmLockLabel then
        Z25.farmLockLabel.Text=Z25.autoPets.lockedIDs and ("🔒 В фарме: "..#result.." / "..Z25.autoPets.lockedCount.." • новые ID игнорируются") or "Список создаётся при первом запуске"
    end
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
    if farming then
        Z25.autoPets.refreshAt=os.clock()
        log("Автофарм продолжается во время улучшения; ID будут обновлены")
    end
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

fuseNewEggPets=function(epoch)
    if not eggSessionActive(epoch) or not Z25.eggFusion.collecting then
        return false,0,"Автоскрещивание остановлено"
    end
    local kind=Z25.eggFusion.fuseType
    if not kind or not Z25.activeEggKeep()[kind] then return false,0,"Не выбран основной вид для скрещивания" end
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
            local remote=gameRemotes:FindFirstChild(rule.remote)
            if not remote or not remote:IsA("RemoteFunction") then
                return false,completed,"Не найден "..rule.remote.." (есть подходящая группа)"
            end
            if existingOld>0 or danger then
                Z25.eggFusion.blocked+=1
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
local function releaseLockedTarget(id,epoch)
    if epoch~=session then return end
    local lock=lockedTargets[id]
    if lock then
        if reserved[lock.coin]==id then reserved[lock.coin]=nil end
        lockedTargets[id]=nil
    end
end
Z25.coinCache={list={},at=-1e9,zone=nil,cursor=0}
local function claimCoin(id,minHP)
    local zoneKey=tostring(Z25.area)..":"..tostring(Z25.farmWorld)..":"..tostring(cfg.mode)
    local cache=Z25.coinCache
    local now=os.clock()
    if now-cache.at>2.0 or cache.zone~=zoneKey then
        local fresh=scan()
        orderCoins(fresh)
        cache={list=fresh,at=now,zone=zoneKey,cursor=cache.cursor or 0}
        Z25.coinCache=cache
    end
    local list=cache.list
    local n=#list
    if n==0 then return nil end
    local start=cache.cursor%n+1
    local function choose(requireStrong)
        for offset=0,n-1 do
            local index=(start+offset-1)%n+1
            local info=list[index]
            local coin=info.object
            if not reserved[coin] and (not requireStrong or info.hp>=minHP) and validCoin(coin) then
                cache.cursor=index
                reserved[coin]=id
                local cell=Z25.coverageCell(info.pos)
                if Z25.coverageVisits[cell]==nil then Z25.coverageSectors+=1 end
                Z25.coverageVisits[cell]=(Z25.coverageVisits[cell] or 0)+1
                return coin
            end
        end
        return nil
    end
    if minHP then return choose(true) or choose(false) end
    return choose(false)
end
function Z25.mineForOne(epoch,id,profile,oneCoin)
    if not Z25.waitWhilePaused(epoch) then return nil,"Фарм уже остановлен" end
    local sleighMode=Z25.farmWorld=="Sleigh"
    local lock=not sleighMode and lockedTargets[id] or nil
    local coin
    if sleighMode then
        coin=Z25.findSleigh()
    elseif oneCoin then
        coin=oneCoin
    elseif lock and validCoin(lock.coin) and reserved[lock.coin]==id then
        coin=lock.coin
        stats.targetReused+=1
    else
        if lock then
            stats.gone+=1
            releaseLockedTarget(id,epoch)
        end
        coin=claimCoin(id,Z25.autoPets.mode=="all" and profile.samples[1]*2 or nil)
        if coin then
            lockedTargets[id]={coin=coin,misses=0}
            stats.targetChanged+=1
        end
    end
    if not coin then
        return nil,sleighMode and "Сани не найдены в загруженных монетах — ожидаю появления" or "Нет свободных монет в зоне"
    end
    local p=partOf(coin)
    local before=health(coin)
    if not p or type(before)~="number" or before<=0 then
        if not sleighMode then releaseLockedTarget(id,epoch) end
        return nil,"Нет доступного HP"
    end
    if sleighMode then
        local shared=Z25.sleighState
        if shared.coin~=coin then
            shared.coin=coin
            shared.hp=before
            shared.killed=false
        elseif type(shared.hp)=="number" and before<shared.hp then
            stats.damage+=shared.hp-before
            shared.hp=before
        end
    end
    local _,mineRemote,petRemote=nodes()
    if not mineRemote or not petRemote then
        releaseLockedTarget(id,epoch)
        return nil,"Серверные события недоступны"
    end
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
    if sleighMode then
        local shared=Z25.sleighState
        if shared.coin==coin then
            if not vanished and type(after)=="number" and type(shared.hp)=="number" and after<shared.hp then
                stats.damage+=shared.hp-after
                shared.hp=after
            elseif vanished and not shared.killed then
                shared.killed=true
                stats.gone+=1
                Z25.sleighCache.coin=nil
                Z25.sleighCache.at=os.clock()-2.1
            end
        end
        if vanished then return nil,"Сани исчезли — ищу появление новых" end
        if delta>0 then return true,delta end
        return nil,"Общий HP саней пока не изменился"
    end
    local petStats=stats.perPet[id]
    if delta>0 then
        stats.damage+=delta
        if petStats then
            petStats.damage+=delta
            petStats.batches+=1
        end
    end
    if vanished then
        stats.gone+=1
        releaseLockedTarget(id,epoch)
        if delta>0 then return true,delta end
        return nil,"Цель исчезла: HP за удар не подтверждён"
    end
    if delta>0 then
        if lockedTargets[id] then lockedTargets[id].misses=0 end
        return true,delta
    end
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
-- Continuous fair dispatch. A completed request frees its slot immediately;
-- remaining pets do not wait for the slowest pet in a batch.
function Z25.dynamicFarm(epoch)
    local pool={}
    local busy={}
    local cooldown={}
    local inFlight=0
    local nextRefresh=0
    local lastSeenTrigger=0
    local nextWarning=0
    local cursor=Z25.dynamicPoolCursor or 0
    local function capacity()
        if fpsValue>0 and fpsValue<32 then return 4 end
        if fpsValue>0 and fpsValue<40 then return 7 end
        if fpsValue>0 and fpsValue<50 then return 12 end
        return 24
    end
    local function obtain(now)
        local total=math.min(165,Z25.autoPets.activeCount,#pool)
        if total==0 then return nil end
        for _=1,total do
            cursor=cursor%total+1
            local item=pool[cursor]
            if item and not busy[item.id] and (cooldown[item.id] or 0)<=now then
                Z25.dynamicPoolCursor=cursor
                return item
            end
        end
        return nil
    end
    local function dispatch(item)
        busy[item.id]=true
        inFlight+=1
        stats.workers=inFlight
        stats.peakWorkers=math.max(stats.peakWorkers,inFlight)
        task.spawn(function()
            local executed,success,detail=pcall(Z25.mineForOne,epoch,item.id,item.profile,nil)
            busy[item.id]=nil
            inFlight=math.max(0,inFlight-1)
            if not active(epoch) then return end
            stats.workers=inFlight
            if executed and success==true then
                if not Z25.autoPets.success[item.id] then Z25.autoPets.rotated+=1 end
                Z25.autoPets.success[item.id]=(Z25.autoPets.success[item.id] or 0)+1
                Z25.autoPets.rejected[item.id]=0
                cooldown[item.id]=0
            elseif executed and success==false then
                local failures=math.min(5,(Z25.autoPets.rejected[item.id] or 0)+1)
                Z25.autoPets.rejected[item.id]=failures
                stats.noProgress+=1
                cooldown[item.id]=os.clock()+math.min(12,2*failures)
                releaseLockedTarget(item.id,epoch)
            elseif executed then
                -- Missing targets, shared HP contention, temporary errors:
                -- retry fairly without blacklisting the pet.
                cooldown[item.id]=os.clock()+(Z25.farmWorld=="Sleigh" and .50 or 1.2)
            else
                Z25.autoPets.rejected[item.id]=(Z25.autoPets.rejected[item.id] or 0)+1
                cooldown[item.id]=os.clock()+5
                releaseLockedTarget(item.id,epoch)
                if os.clock()>=nextWarning then
                    nextWarning=os.clock()+8
                    log("Фарм ID "..tostring(item.id)..": "..tostring(success):sub(1,90),true)
                end
            end
        end)
    end
    while active(epoch) do
        if not Z25.waitWhilePaused(epoch) then break end
        local now=os.clock()
        if now>=nextRefresh or (Z25.autoPets.refreshAt and Z25.autoPets.refreshAt>lastSeenTrigger) then
            local newPool,err=Z25.inventorySnapshot("all")
            nextRefresh=now+((eggRunning or converting) and 4 or 10) -- quickly forget fused/deleted IDs
            lastSeenTrigger=Z25.autoPets.refreshAt or 0
            if newPool then
                pool=newPool
                cursor=math.min(cursor,#pool)
                local present={}
                for _,item in ipairs(pool) do present[item.id]=true end
                for id,_ in pairs(lockedTargets) do
                    if not present[id] and not busy[id] then releaseLockedTarget(id,epoch) end
                end
                for id,_ in pairs(cooldown) do
                    if not present[id] then cooldown[id]=nil end
                end
            elseif now>=nextWarning then
                nextWarning=now+8
                log("Не удалось обновить питомцев: "..tostring(err):sub(1,75),true)
            end
        end
        if #pool==0 then
            stats.workers=inFlight
            task.wait(1.5)
            continue
        end
        if Z25.farmWorld=="Sleigh" and not Z25.findSleigh() then
            -- One shared target; wait for its respawn without switching worlds.
            stats.workers=inFlight
            task.wait(1)
            continue
        end
        local limit=capacity()
        while active(epoch) and inFlight<limit do
            local item=obtain(os.clock())
            if not item then break end
            dispatch(item)
        end
        stats.workers=inFlight
        task.wait(inFlight==0 and .22 or .085)
    end
    if epoch==session then
        stats.workers=0
        farming=false
    end
end
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
                log("Проверка ВСЕ: "..Z25.autoPets.probePassed.."/"..Z25.autoPets.probeTried.."; режим не включён")
            end
        end)
        if not ok then
            Z25.autoPets.allVerified=false
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
    if Z25.autoPets.mode~="saved" then
        Z25.autoPets.mode="all" -- every valid pre-locked inventory pet, regardless of level
        local list,err=Z25.inventorySnapshot("all")
        if not list or #list==0 then
            log("Авто-ID: "..tostring(err or (Z25.autoPets.lockedIDs and "в зафиксированном списке не осталось действующих питомцев — обнови список" or "нет питомцев с допустимым уровнем")),true) return
        end
        if not Z25.autoPets.lockedIDs then
            local locked={}
            for _,pet in ipairs(list) do locked[pet.id]=true end
            Z25.autoPets.lockedIDs=locked
            Z25.autoPets.lockedCount=#list
            log("🔒 Зафиксированы "..#list.." ID (любой уровень > 0). Новые питомцы не участвуют")
            if Z25.farmLockLabel then Z25.farmLockLabel.Text="🔒 В фарме: "..#list.." / "..#list.." • новые игнорируются" end
        end
    end

    local coins,mine,pets=nodes()
    if not coins or not mine or not pets then log("Монеты или RemoteEvent не найдены",true) return end
    local found=scan()
    if #found==0 then
        log(Z25.farmWorld=="Sleigh" and "Сани не загружены — фарм ждёт появления, другие цели не трогаю" or
            "В мире пока нет загруженных подходящих монет — жду появления, фарм не закрываю")
    end
    session+=1
    local epoch=session
    farming=true
    Z25.paused=false
    table.clear(reserved)
    table.clear(lockedTargets)
    table.clear(Z25.coverageVisits)
    Z25.coverageSectors=0
    Z25.sleighState={coin=nil,hp=nil,killed=false}
    Z25.sleighCache={coin=nil,at=-1e9}
    stats.damage=0 stats.gone=0 stats.noProgress=0 stats.mine=0 stats.move=0 stats.clientErrors=0
    stats.targetReused=0 stats.targetChanged=0 stats.perPet={} stats.peakWorkers=0 stats.started=os.clock()
    for key,current in pairs(Z25.currency) do if type(current)=="number" then Z25.currencyStart[key]=current end end
    if Z25.autoPets.mode~="saved" then
        Z25.autoPets.rejected={} Z25.autoPets.success={} Z25.autoPets.rotated=0
        stats.workers=0
        log("Авто-ID: "..Z25.autoPets.ready.." из зафиксированных "..Z25.autoPets.lockedCount.." (любой уровень); до "..Z25.autoPets.activeCount.." в ротации, максимум 24 задачи параллельно")
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

local function createZoneHubUI()
local shutdown
local C={
    bg=Color3.fromRGB(11,14,20), panel=Color3.fromRGB(23,28,36), panel2=Color3.fromRGB(37,44,55),
    inset=Color3.fromRGB(17,21,28), line=Color3.fromRGB(52,62,76), white=Color3.fromRGB(245,247,250),
    dim=Color3.fromRGB(161,170,184),blue=Color3.fromRGB(91,139,220), green=Color3.fromRGB(75,180,143),
    red=Color3.fromRGB(213,105,116),gold=Color3.fromRGB(209,174,107), purple=Color3.fromRGB(149,124,190),
    cyan=Color3.fromRGB(111,178,207)
}
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
    f.Parent=p corner(f,10)
    return f
end
local function button(p,txt,y,fn,bg)
    local b=Instance.new("TextButton") b.Text=txt b.Font=Enum.Font.GothamSemibold b.TextSize=12
    b.TextColor3=C.white b.BackgroundColor3=bg or C.panel2 b.BorderSizePixel=0
    b.Size=UDim2.new(1,-28,0,42) b.Position=UDim2.fromOffset(14,y)
    b.AutoButtonColor=true b.Parent=p corner(b,8)
    connections[#connections+1]=b.MouseButton1Click:Connect(function()
        if not alive then return end
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
toast.BackgroundColor3=Color3.fromRGB(85,41,51)
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
shadow.BackgroundTransparency=.80 shadow.BorderSizePixel=0 shadow.AnchorPoint=Vector2.new(.5,.5)
shadow.Position=UDim2.fromScale(.5,.505) shadow.Size=UDim2.fromOffset(408,588) shadow.Parent=gui corner(shadow,24)
local main=Instance.new("Frame") main.Name="Window" main.BackgroundColor3=C.bg main.BorderSizePixel=0
main.AnchorPoint=Vector2.new(.5,.5) main.Position=UDim2.fromScale(.5,.5)
main.Size=UDim2.fromOffset(396,576) main.Parent=gui corner(main,14)
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
local top=Instance.new("Frame") top.BackgroundColor3=C.panel
top.BorderSizePixel=0 top.Size=UDim2.new(1,0,0,90) top.Parent=main corner(top,14)
local headSeparator=Instance.new("Frame") headSeparator.BorderSizePixel=0 headSeparator.BackgroundColor3=C.line
headSeparator.BackgroundTransparency=.55 headSeparator.Position=UDim2.new(0,16,1,-1) headSeparator.Size=UDim2.new(1,-32,0,1) headSeparator.Parent=top
label(top,"ZONEHUB",13,32,19,C.white,true)
label(top,"5.2 SAFE • PET SIMULATOR 2018",49,20,10,C.dim,true)
local livePill=Instance.new("TextLabel") livePill.Size=UDim2.fromOffset(65,24)
livePill.Position=UDim2.new(1,-173,0,21) livePill.Text="● IDLE"
livePill.Font=Enum.Font.GothamBold livePill.TextSize=10 livePill.TextColor3=C.dim
livePill.BackgroundColor3=C.inset livePill.Parent=top corner(livePill,13)
local collapse=Instance.new("TextButton") collapse.Name="Collapse"
collapse.Size=UDim2.fromOffset(37,37) collapse.Position=UDim2.new(1,-48,0,14)
collapse.Text="−" collapse.Font=Enum.Font.GothamBold collapse.TextSize=20
collapse.TextColor3=C.white collapse.BackgroundColor3=C.panel2 collapse.AutoButtonColor=false
collapse.Parent=top corner(collapse,12)
local gameIcon="rbxthumb://type=GameIcon&id="..tostring(game.GameId).."&w=150&h=150"
local float=Instance.new("TextButton") float.Name="FloatingButton" float.Visible=false
float.Size=UDim2.fromOffset(70,70) float.AnchorPoint=Vector2.new(1,.5)
float.Position=UDim2.new(1,-10,.5,0) float.Text="" float.AutoButtonColor=false
float.BackgroundColor3=C.panel2 float.Parent=gui corner(float,20)

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
    if folded==state or not alive then return end
    folded=state
    inTransition=false
    main.Visible=not state
    shadow.Visible=not state
    float.Visible=state
    if not state then
        main.Position=openPosition
        shadow.Position=openShadowPosition
        keepOnScreen()
    else
        openPosition=main.Position
        openShadowPosition=shadow.Position
    end
end
connections[#connections+1]=collapse.MouseButton1Click:Connect(function() setCollapsed(true) end)
connections[#connections+1]=float.MouseButton1Click:Connect(function() setCollapsed(false) end)
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
local tabs,pages={},{}
local names={"Фарм","Яйца","3 яйца","Шапки","Улучшение","Телепорт","Настройки"}
local pill=Instance.new("Frame")
pill.BackgroundColor3=C.panel2 pill.BorderSizePixel=0
pill.Position=UDim2.new(0,3,0,3) pill.Size=UDim2.new(1/#names,-6,1,-6)
pill.Parent=tabBar corner(pill,8)
for i,name in ipairs(names) do
    local b=Instance.new("TextButton")
    b.Name=name b.Text=name b.TextSize=10 b.TextScaled=true
    b.Font=Enum.Font.GothamSemibold b.TextColor3=C.dim
    b.BackgroundTransparency=1 b.BorderSizePixel=0 b.AutoButtonColor=false b.ZIndex=2
    b.Position=UDim2.new((i-1)/#names,2,0,3)
    b.Size=UDim2.new(1/#names,-4,1,-6)
    b.Parent=tabBar tabs[name]=b
    local sc=Instance.new("ScrollingFrame") sc.Name=name sc.Visible=false
    sc.Position=UDim2.fromOffset(12,151)
    sc.Size=UDim2.new(1,-24,1,-219)
    sc.BackgroundTransparency=1 sc.BorderSizePixel=0
    sc.CanvasSize=UDim2.new() sc.AutomaticCanvasSize=Enum.AutomaticSize.Y
    sc.ScrollBarThickness=3 sc.ScrollBarImageColor3=C.blue
    sc.ScrollingDirection=Enum.ScrollingDirection.Y sc.Parent=main
    local pad=Instance.new("UIPadding")
    pad.PaddingTop=UDim.new(0,2) pad.PaddingBottom=UDim.new(0,8) pad.Parent=sc
    local layout=Instance.new("UIListLayout")
    layout.Padding=UDim.new(0,8)
    layout.SortOrder=Enum.SortOrder.LayoutOrder layout.Parent=sc
    pages[name]=sc
end
local activePage=nil
local function switch(name)
    if not pages[name] or activePage==name then return end
    activePage=name
    for i,n in ipairs(names) do
        pages[n].Visible=(n==name)
        tabs[n].TextColor3=n==name and C.white or C.dim
        if n==name then pill.Position=UDim2.new((i-1)/#names,3,0,3) end
    end
end
for name,b in pairs(tabs) do
    connections[#connections+1]=b.MouseButton1Click:Connect(function() switch(name,false) end)
end
local footer=card(main,54)
footer.Position=UDim2.new(0,12,1,-62) footer.Size=UDim2.new(1,-24,0,53)
statusLabel=label(footer,"Готово",6,41,10,C.dim)
statusLabel.TextYAlignment=Enum.TextYAlignment.Top
statusLabel.Size=UDim2.new(1,-84,0,41)

do
local farm=pages["Фарм"]
local hero=card(farm,88,C.blue)
label(hero,"Автофарм",9,25,16,C.white,true)
Z25.coinCount=label(hero,"Готов к запуску",34,21,11,C.dim)
Z25.workLabel=label(hero,"● ОСТАНОВЛЕН",60,19,11,C.dim,true)
local controls=card(farm,70,C.green)
Z25.startButton=button(controls,"▶ ЗАПУСТИТЬ ФАРМ",13,function()
    if farming then stopFarm() log("Фарм остановлен") else startFarm() end
end,C.green)
local worldCard=card(farm,200,C.blue)
label(worldCard,"Мир · все зоны / сани",8,27,13,C.white,true)
local worldChoices={{"ЗЕМЛЯ","Earth",C.blue},{"ЛУНА","Moon",C.purple},{"ЗИМА","Winter",C.cyan},{"🛷 САНИ","Sleigh",C.gold}}
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
        Z25.coinCache={list={},at=-1e9,zone=nil,cursor=0}
        Z25.sleighCache={coin=nil,at=-1e9}
        syncWorlds()
        log(w=="Sleigh" and "Выбраны САНИ: все зафиксированные питомцы атакуют одну цель, без деления на разные монеты" or
            "Выбран мир: "..Z25.areaDescription()..". Монеты определяются по игровому типу.")
    end,C.panel2)
    b.Position=UDim2.new((i-1)%2/2,5,0,42+math.floor((i-1)/2)*43)
    b.Size=UDim2.new(.5,-8,0,37)
    worldButtons[#worldButtons+1]={b=b,world=w,color=choice[3]}
end
button(worldCard,"🔎 ПРОВЕРИТЬ ЦЕЛИ",141,function()
    Z25.loadCoinDirectory()
    if Z25.farmWorld=="Sleigh" then
        local sleigh=Z25.findSleigh()
        log(sleigh and ("Сани: CoinID="..sleigh.Name.." • HP="..tostring(health(sleigh))) or
            "Сани не найдены в __THINGS.Coins: возможно, зимний мир ещё не загрузился",not sleigh)
    else
        local found,total=scan()
        log(Z25.areaDescription()..": доступно "..#found.." из "..total.." загруженных монет")
    end
end,C.panel2)
syncWorlds()
local selection=card(farm,107)
label(selection,"Приоритет",9,24,13,C.white,true)
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
local jobs=card(farm,206,C.green)
label(jobs,"Питомцы · любой уровень",9,27,14,C.white,true)
local values={8,32,64,128,165}
local jobButtons={}
for i,n in ipairs(values) do
    local b=button(jobs,tostring(n),49,function()
        Z25.autoPets.activeCount=n
        for _,row in ipairs(jobButtons) do tween(row.b,{BackgroundColor3=row.n==n and C.blue or C.panel2},.16) end
        log("Питомцев в ротации за круг: до "..n)
    end,n==165 and C.blue or C.panel2)
    b.Position=UDim2.new((i-1)%3/3,5,0,49+math.floor((i-1)/3)*42)
    b.Size=UDim2.new(1/3,-8,0,36)
    jobButtons[#jobButtons+1]={b=b,n=n}
end
local farmManual=entry(jobs,"Приоритетные ID (необязательно)",143,"",function(value)
    local chosen={}
    for token in tostring(value):gmatch("%d+") do
        local id=tonumber(token)
        if id and id>=1 and id%1==0 then chosen[id]=true end
    end
    Z25.autoPets.manualIds=chosen
    Z25.autoPets.refreshAt=os.clock()
end)
farmManual.PlaceholderText="12562926, 45267711"
local lockCard=card(farm,113,C.green)
label(lockCard,"🔒 Состав автофарма",8,26,13,C.white,true)
Z25.farmLockLabel=label(lockCard,"Фиксация при первом запуске",35,22,11,C.dim)
button(lockCard,"↻ ОБНОВИТЬ СОСТАВ (ПОСЛЕ СТОП)",62,function()
    if farming then log("Сначала останови фарм",true) return end
    Z25.autoPets.lockedIDs=nil
    Z25.autoPets.lockedCount=0
    Z25.autoPets.success={} Z25.autoPets.rejected={} Z25.autoPets.rotated=0
    Z25.dynamicPoolCursor=0 lastInventorySignature=nil
    Z25.farmLockLabel.Text="Список сброшен: новый состав при запуске"
    log("🔓 Состав сброшен. Следующий запуск захватит всех текущих питомцев")
end,C.blue)
end

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
label(filter,"Оставляем выбранные виды, включая Rainbow/Gold. Не выбранные Rainbow/Gold новых яиц удаляем. Старые ID не трогаем.",36,56,10,C.dim)
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
        "Работает="..tostring(eggRunning).." | Мир="..tostring(eggWorld).." | Tier="..tostring(eggTier).." | Тройное="..tostring(dualEggMode and dualEgg.includeT3).." | Зима3="..dualEgg.winter3Sent.." | Зима4="..dualEgg.winter4Sent.." | Луна17="..dualEgg.moonSent,
        "Запросов="..eggAttempts.." | подтверждений Buy="..eggConfirmed.." | отказов="..eggRejected,
        "Новых питомцев="..eggOpened.." | Дополнительные="..eggAdditionalPets.." | Наблюдаемый множитель="..tostring(eggConfirmedMultiplier or "не определён").." | Серверный инвентарь="..tostring(eggInventory).."/"..tostring(eggCapacity),
        "Фильтр="..Z25.eggFilter.mode.." | оставлено="..Z25.eggFilter.kept.." | удалено="..Z25.eggFilter.deleted,
        "Тип для скрещивания="..tostring(Z25.eggFusion.fuseType).." | старые Gold/Rainbow="..tostring(Z25.eggFusion.allowExisting),
        "Скрещено групп="..Z25.eggFusion.done.." | заблокировано="..Z25.eggFusion.blocked,
        "Причина/статус="..eggMessage,
        "Скрещивание="..Z25.eggFusion.last,
        "Фильтр="..Z25.eggFilter.last.." | удалено Rainbow="..Z25.eggFilter.rainbowDeleted.." / Gold="..Z25.eggFilter.goldDeleted,
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

do
local dualPage=pages["3 яйца"]
local lead=card(dualPage,139)
label(lead,"ТРИ ЯЙЦА · Winter T3/T4 + Moon T17",8,28,15,C.white,true)
label(lead,"Открытие по очереди: Winter Tier 3 (Рандольф), Winter Tier 4, Moon Tier 17. Редкие питомцы защищены.",36,44,11,C.dim)
local triToggle=button(lead,"РЕЖИМ: 3 ЯЙЦА · ПОРОВНУ",88,function()
    if eggRunning then dualEgg.message="Останови покупки для смены режима" return end
    dualEgg.includeT3=not dualEgg.includeT3
    Z25.dualKeepRebuild()
    dualEgg.confirmationUntil=0
    if Z25.dualUiUpdate then Z25.dualUiUpdate() end
end,C.blue)
local dualRows={}
local updateDualUI
local function buildDualCard(title,world,tier,color)
    local codes=Z25.EGG_CONTENTS[world][tier]
    local height=64+math.ceil(#codes/2)*45
    local panel=card(dualPage,height,color)
    if tier==3 then Z25.triEggTier3Card=panel end
    label(panel,title,8,28,14,C.white,true)
    label(panel,"Оставить до 6 видов • остальные новые удаляются",34,24,10,C.dim)
    for i,code in ipairs(codes) do
        local key=tostring(code)
        local b=button(panel,"",62+math.floor((i-1)/2)*45,function()
            if eggRunning then dualEgg.message="Останови открытие перед изменением выбора" return end
            local keep=(world=="Moon") and dualEgg.moon or tier==3 and dualEgg.winter3 or dualEgg.winter4
            local amount=0
            for _,yes in pairs(keep) do if yes then amount+=1 end end
            if not keep[key] and amount>=6 then dualEgg.message="Можно выбрать максимум 6 видов для этого яйца" return end
            keep[key]=not keep[key] or nil
            Z25.dualKeepRebuild()
            if dualEgg.fuseType and not dualEgg.merged[dualEgg.fuseType] then dualEgg.fuseType=nil dualEgg.fuseEnabled=false end
            dualEgg.confirmationUntil=0
            updateDualUI()
        end,C.panel2)
        b.Position=UDim2.new((i-1)%2/2,5,0,62+math.floor((i-1)/2)*45)
        b.Size=UDim2.new(.5,-8,0,39) b.TextSize=10
        dualRows[#dualRows+1]={button=b,code=key,world=world,tier=tier}
    end
end
buildDualCard("❄ ЗИМА · CHRISTMAS TIER 3","Winter",3,C.cyan)
buildDualCard("❄ ЗИМА · CHRISTMAS TIER 4","Winter",4,C.cyan)
buildDualCard("🌙 ЛУНА · TIER 17","Moon",17,C.purple)
local fcard=card(dualPage,167)
label(fcard,"♻ Скрещивание (по желанию)",8,28,14,C.white,true)
local fuseToggle=button(fcard,"СКРЕЩИВАНИЕ: ВЫКЛ",40,function()
    if eggRunning then dualEgg.message="Сначала останови открытие" return end
    if not dualEgg.fuseEnabled and not dualEgg.fuseType then
        dualEgg.message="Сначала выбери вид для скрещивания"
        return
    end
    dualEgg.fuseEnabled=not dualEgg.fuseEnabled
    dualEgg.confirmationUntil=0
    updateDualUI()
end,C.panel2)
local fuseChoose=button(fcard,"Вид: не выбран (нажми для выбора)",88,function()
    if eggRunning then dualEgg.message="Сначала останови открытие" return end
    local options={}
    local used={}
    if dualEgg.includeT3 then
        for _,code in ipairs(Z25.EGG_CONTENTS.Winter[3]) do
            local k=tostring(code)
            if dualEgg.winter3[k] then options[#options+1]=k used[k]=true end
        end
    end
    for _,code in ipairs(Z25.EGG_CONTENTS.Winter[4]) do
        local k=tostring(code)
        if dualEgg.winter4[k] and not used[k] then options[#options+1]=k used[k]=true end
    end
    for _,code in ipairs(Z25.EGG_CONTENTS.Moon[17]) do
        if dualEgg.moon[tostring(code)] then options[#options+1]=tostring(code) end
    end
    if #options==0 then dualEgg.message="Сначала отметь питомцев для сохранения" return end
    local pos=0
    for i,k in ipairs(options) do if dualEgg.fuseType==k then pos=i end end
    dualEgg.fuseType=options[pos%#options+1]
    dualEgg.confirmationUntil=0
    updateDualUI()
end,C.panel2)
label(fcard,"Если выключено — яйца открываются без скрещивания. Старые питомцы защищены настройкой обычных яиц.",133,33,10,C.dim)
local run=card(dualPage,166)
label(run,"⚡ Открытие двух или трёх яиц",8,29,14,C.white,true)
local startDual=button(run,"▶ ЗАПУСТИТЬ 3 ЯЙЦА",40,function()
    if eggRunning then dualEgg.message="Яйца уже открываются. Сначала СТОП" return end
    local now=os.clock()
    if dualEgg.confirmationUntil<now then
        dualEgg.confirmationUntil=now+9
        dualEgg.message="Подтверди удаление невыбранных новых питомцев: нажми ЗАПУСТИТЬ ещё раз"
        updateDualUI()
        return
    end
    dualEgg.confirmationUntil=0
    startEggs("dual")
    updateDualUI()
end,C.green)
button(run,"■ СТОП ПОКУПОК",89,function()
    if dualEggMode then stopEggs("Покупки остановлены") else dualEgg.message="Открытие не запущено" end
    dualEgg.confirmationUntil=0
    updateDualUI()
end,C.red)
local report=card(dualPage,202)
label(report,"Состояние",9,26,14,C.white,true)
local dualStatus=label(report,"Не запущено",37,150,10,C.dim)
updateDualUI=function()
    if Z25.triEggTier3Card then Z25.triEggTier3Card.Visible=dualEgg.includeT3 end
    for _,item in ipairs(dualRows) do
        local keep=(item.world=="Moon") and dualEgg.moon or item.tier==3 and dualEgg.winter3 or dualEgg.winter4
        local selected=keep[item.code]==true
        item.button.Visible=(item.tier~=3 or dualEgg.includeT3)
        item.button.Text=(selected and "✓ " or "○ ")..(Z25.PET_TYPE_NAMES[tonumber(item.code)] or item.code)
        item.button.BackgroundColor3=selected and C.green or C.panel2
    end
    local chosen=dualEgg.fuseType and (Z25.petNameForType(dualEgg.fuseType) or dualEgg.fuseType) or "не выбран"
    fuseToggle.Text="СКРЕЩИВАНИЕ: "..(dualEgg.fuseEnabled and "ВКЛ" or "ВЫКЛ")
    fuseToggle.BackgroundColor3=dualEgg.fuseEnabled and C.green or C.panel2
    fuseChoose.Text="Выбрать вид: "..chosen
    triToggle.Text=dualEgg.includeT3 and "РЕЖИМ: 3 ЯЙЦА · ПОРОВНУ" or "РЕЖИМ: 2 ЯЙЦА · 50/50"
    if dualEgg.confirmationUntil>os.clock() then
        startDual.Text="ПОДТВЕРДИТЬ ОТКРЫТИЕ И ФИЛЬТР"
    else
        startDual.Text=dualEgg.includeT3 and "▶ ЗАПУСТИТЬ 3 ЯЙЦА" or "▶ ЗАПУСТИТЬ 2 ЯЙЦА"
    end
end
Z25.dualUiUpdate=updateDualUI
Z25.dualUiStatus=dualStatus
Z25.dualUiStart=startDual
updateDualUI()
end

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
    local count=0
    for _ in pairs(points) do count+=1 end
    return count
end
local countTeleports=loadZoneStorage()
if Z25.refreshZoneButtons then Z25.refreshZoneButtons() end

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
end

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
                    items[#items+1]={id=id,typecode=tonumber(hat.n),level=tonumber(hat.l) or 0,wear=wear[id],
                        locked=Z25.trueFlag(hat.lock) or Z25.trueFlag(hat.locked) or
                        Z25.trueFlag(hat.lk) or Z25.trueFlag(hat.fav)}
                end
            end
        end
        table.sort(items,function(a,b)
            if a.level==b.level then return a.id<b.id end
            return a.level>b.level
        end)
        local attached=0
        for _,item in ipairs(items) do if item.wear then attached+=1 end end
        -- HatSlots counts wearable slots, not necessarily storage capacity.
        -- Only enforce a storage limit if the save exposes it explicitly.
        local storage=tonumber(save.HatInventorySlots) or tonumber(save.HatCapacity)
            or tonumber(save.MaxHats) or tonumber(save.HatStorageSlots)
        if storage and storage<#items then storage=nil end
        return {items=items,count=#items,slots=storage,used=attached}
    end
    local function display()
        local ui=H.ui
        if ui.summary then
            ui.summary.Text=string.format("Шапки: %d/%s • надето %d • удалено %d",H.count,tostring(H.slots or "?"),H.used,H.deleted)
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
                    b.Text=(H.keep[code] and "✓ " or "○ ")..nameFor(code)
                    b.BackgroundColor3=H.keep[code] and C.green or C.panel2
                end
            end
        end
        if ui.keepCount then
            local total,selected=0,0
            for _,code in ipairs(tierChoices()) do
                total+=1
                if H.keep[code] then selected+=1 end
            end
            ui.keepCount.Text=string.format("Выбрано для сохранения %d/%d • шапки других видов при выпадении удаляются",selected,total)
        end
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
    local function isTrash(item,snap,source)
        if not item or not item.id or not item.typecode then return false end
        if item.wear or item.locked or H.protected[item.id] or not HAT_TYPES[item.typecode] then return false end
        if source=="cycle" then
            return not H.keep[item.typecode]
        end
        if item.wear or H.protected[item.id] or not HAT_TYPES[item.typecode] or item.typecode>=99000 then return false end
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
        if not isTrash(current,before,source) then return false,"Шапка защищена. Удаление отменено" end
        local remote=hatRemote()
        if not remote then return false,"RemoteFunction Game.Hats не найдена" end
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
    local function selectedHatsCount()
        local count=0
        for _,typeCode in ipairs(tierChoices()) do
            if H.keep[typeCode] then count+=1 end
        end
        return count
    end
    local function startHatCycle()
        if hatBusy then status("Шапки уже открываются. Нажми СТОП") return end
        if selectedHatsCount()==0 then status("Выбери хотя бы одну шапку, которую оставлять",true) return end
        local now=os.clock()
        if now-H.purchaseArmed>8 then
            H.purchaseArmed=now
            status("ПОДТВЕРДИ: все новые НЕВЫБРАННЫЕ шапки, включая редкие, будут удалены. Повтори нажатие за 8 секунд")
            return
        end
        H.purchaseArmed=0
        local _,shop=eggRemotes()
        if not shop then status("RemoteFunction Game.Shop не найдена",true) return end
        hatBusy=true hatEpoch+=1
        local epoch=hatEpoch
        task.spawn(function()
            local bought,erased,kept=0,0,0
            local ok,err=pcall(function()
                while alive and hatBusy and hatEpoch==epoch do
                    local before,why=snapshot()
                    if not before then status("Нет серверного инвентаря шапок: "..tostring(why),true) break end
                    if before.slots and before.count>=before.slots then
                        status(string.format("Инвентарь полон: %d/%s • оставлено %d, удалено %d",before.count,tostring(before.slots or "?"),kept,erased))
                        break
                    end
                    local invoked,accepted=pcall(function()
                        return shop:InvokeServer("Buy","Presents",H.tier)
                    end)
                    if not invoked or accepted==false then
                        status("Сервер не принял подарок: "..tostring(accepted):sub(1,90),true)
                        break
                    end
                    local prior={}
                    for _,row in ipairs(before.items) do prior[row.id]=true end
                    local after,whyAfter,fresh=nil,nil,{}
                    for attempt=1,7 do
                        if not alive or not hatBusy or hatEpoch~=epoch then break end
                        task.wait(attempt==1 and .16 or .30)
                        after,whyAfter=snapshot()
                        if not after then break end
                        fresh={}
                        for _,row in ipairs(after.items) do
                            if not prior[row.id] then fresh[#fresh+1]=row end
                        end
                        if #fresh>0 then break end
                    end
                    if not alive or not hatBusy or hatEpoch~=epoch then break end
                    if not after then status("Не удалось проверить покупку: "..tostring(whyAfter),true) break end
                    if #fresh==0 then
                        status("Запрос отправлен, но новых ID нет. Остановлено без повторной покупки",true)
                        break
                    end
                    bought+=1
                    local bad=false
                    for _,row in ipairs(fresh) do
                        if not alive or not hatBusy or hatEpoch~=epoch then break end
                        if H.keep[row.typecode] then
                            kept+=1
                        elseif row.wear or row.locked or not HAT_TYPES[row.typecode] then
                            bad=true
                            status("Неизвестная/заблокированная новая шапка ID "..tostring(row.id)..". Сохранена; стоп для безопасности",true)
                            break
                        else
                            local gone,reason=deleteOne(row,"cycle")
                            if not gone then
                                bad=true
                                status("Удаление ID "..tostring(row.id).." НЕ подтверждено: "..tostring(reason)..". Стоп шапок",true)
                                break
                            end
                            erased+=1
                        end
                    end
                    if bad then break end
                    local freshSnap=refresh("purchase")
                    if not freshSnap then status("Инвентарь шапок после серии недоступен",true) break end
                    status(string.format("%s • открыто %d • оставлено %d • удалено %d • %d/%s",H.tier,bought,kept,erased,freshSnap.count,tostring(freshSnap.slots or "?")))
                    task.wait(.12)
                end
            end)
            if epoch==hatEpoch then
                hatBusy=false
                if not ok then status("Ошибка цикла шапок: "..tostring(err):sub(1,120),true) end
                display()
            end
        end)
    end
    local function stopHatCycle()
        if not hatBusy then status("Открытие шапок не выполняется") return end
        hatBusy=false hatEpoch+=1
        status("Шапки остановлены. Уже отправленная покупка могла завершиться")
        display()
    end
    local hatsPage=pages["Шапки"]
    local hero=card(hatsPage,125,C.cyan)
    label(hero,"Шапки",8,28,15,C.white,true)
    H.ui.summary=label(hero,"Серверный инвентарь ещё не загружен",39,35,12,C.green,true)
    button(hero,"↻ ОБНОВИТЬ ИНВЕНТАРЬ",77,function() refresh("manual") end,C.blue)

    local tiers=card(hatsPage,148,C.purple)
    label(tiers,"Тир",9,29,14,C.white,true)
    H.ui.tierButtons={}
    for i,tier in ipairs({"Tier 1","Tier 2","Tier 3","Tier 4","Golden"}) do
        local selectedTier=tier
        local b=button(tiers,tier=="Golden" and "TIER 5" or string.upper(tier),50,function()
            if hatBusy then status("Останови только открытие шапок, чтобы сменить тир") return end
            H.tier=selectedTier H.purchaseArmed=0
            display()
        end,C.panel2)
        b.Position=UDim2.new((i-1)%3/3,5,0,50+math.floor((i-1)/3)*43)
        b.Size=UDim2.new(1/3,-8,0,37)
        b.TextSize=10
        H.ui.tierButtons[#H.ui.tierButtons+1]={tier=tier,button=b}
    end
    local types=card(hatsPage,351,C.green)
    label(types,"Оставлять",9,30,14,C.white,true)
    label(types,"Выбранные остаются, остальные удаляются",37,35,11,C.dim)
    H.ui.hatChoices={}
    for i=1,8 do
        local idx=i
        local b=button(types,"",77+math.floor((i-1)/2)*48,function()
            if hatBusy then status("Останови открытие шапок для смены выбора") return end
            local code=tierChoices()[idx]
            if not code then return end
            H.keep[code]=not H.keep[code]
            H.purchaseArmed=0
            display()
        end,C.panel2)
        b.Position=UDim2.new((i-1)%2/2,5,0,77+math.floor((i-1)/2)*48)
        b.Size=UDim2.new(.5,-8,0,42)
        b.TextSize=10
        H.ui.hatChoices[#H.ui.hatChoices+1]=b
    end
    H.ui.keepCount=label(types,"",282,54,11,C.gold,true)

    local controls=card(hatsPage,259,C.gold)
    label(controls,"Автооткрытие",9,28,13,C.white,true)
    label(controls,"До заполнения нужными шапками · параллельно с фармом и яйцами",40,51,11,C.dim)
    button(controls,"▶ КРУТИТЬ БЕЗ ЛИМИТА (2 НАЖАТИЯ)",100,startHatCycle,C.green)
    button(controls,"■ СТОП ШАПКИ",151,stopHatCycle,C.red)
    H.ui.status=label(controls,"",203,47,11,C.dim)
    H.ui.status.TextYAlignment=Enum.TextYAlignment.Top
    refresh("manual")
    display()
end

local settings=pages["Настройки"]
local inventoryCard=card(settings,160,C.cyan)
label(inventoryCard,"Инвентарь",9,27,15,C.white,true)
Z25.inventoryLabel=label(inventoryCard,"Не проверен",39,54,12,C.dim)
button(inventoryCard,"ОБНОВИТЬ",102,function()
    local save,err=readPetSave()
    if not save then log("Инвентарь: "..tostring(err),true) return end
    Z25.updateInventory(save,"ручная проверка")
end,C.blue)

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
local diagnostics=card(settings,125,C.blue)
label(diagnostics,"Состояние",9,27,15,C.white,true)
Z25.healthLabel=label(diagnostics,"FPS: —",38,25,12,C.dim)
button(diagnostics,"КОПИРОВАТЬ ОШИБКИ",75,function()
    if type(setclipboard)~="function" then log("Буфер обмена Delta недоступен",true) return end
    local lines={"ZoneHub 5.2", "FPS: "..tostring(fpsValue),
        "Фарм: "..tostring(farming),"Яйца: "..tostring(eggRunning),
        "Зона: "..Z25.areaDescription(),"Ошибки: "..stats.clientErrors}
    for _,line in ipairs(logLines) do lines[#lines+1]=line end
    local ok=pcall(setclipboard,table.concat(lines,"\n"))
    log(ok and "Журнал скопирован" or "Не удалось скопировать журнал",not ok)
end,C.blue)

local function uiText(obj,value)
    if obj and obj.Text~=value then obj.Text=value end
end
local function uiColor(obj,value)
    if obj and obj.TextColor3~=value then obj.TextColor3=value end
end
local function uiBackground(obj,value)
    if obj and obj.BackgroundColor3~=value then obj.BackgroundColor3=value end
end
local function refresh()
    if not main.Visible then return end
    local currentState=converting and "● UP" or farming and "● FARM" or eggRunning and "● EGGS" or "● IDLE"
    if livePill.Text~=currentState then livePill.Text=currentState end
    uiColor(livePill,(farming or eggRunning or converting) and C.green or C.dim)
    if activePage=="Фарм" then
        uiText(Z25.coinCount,farming and (Z25.farmWorld=="Sleigh" and "Сани · общая цель" or "Все зоны выбранного мира") or Z25.areaDescription())
        uiText(Z25.workLabel,farming and ("● ФАРМ · "..stats.workers.." задач") or "● ОСТАНОВЛЕН")
        uiColor(Z25.workLabel,farming and C.green or C.dim)
        uiText(Z25.startButton,farming and "■ ОСТАНОВИТЬ" or "▶ ЗАПУСТИТЬ ФАРМ")
        uiBackground(Z25.startButton,farming and C.red or C.blue)
    elseif activePage=="Яйца" then
        uiText(eggStatusLabel,(eggRunning and "● ОТКРЫТИЕ" or "● ОЖИДАНИЕ").."\n"..eggMessage)
        uiColor(eggStatusLabel,eggRunning and C.green or C.dim)
        local speed=eggStarted>0 and eggOpened/math.max(1,os.clock()-eggStarted) or 0
        uiText(eggCountLabel,"Покупок: "..eggAttempts.." • питомцев: "..eggOpened.." • "..string.format("%.1f",speed).."/с")
        if eggPerfButton then eggPerfButton.Text="СКОРОСТЬ: "..(eggPerfMode=="turbo" and "ТУРБО · до 36 запросов" or eggPerfMode=="fast" and "БЫСТРО · до 24 запросов" or "АВТО · до 12 запросов") end
        if Z25.eggFusionLabel then Z25.eggFusionLabel.Text="Скрещено групп: "..Z25.eggFusion.done.." • "..Z25.eggFusion.last end
        if Z25.eggFilterLabel then
            uiText(Z25.eggFilterLabel,"Оставить: "..Z25.countKeepTypes().." типов • сохранено: "..Z25.eggFilter.kept.." • удалено: "..Z25.eggFilter.deleted.."\n"..Z25.eggFilter.last)
            uiColor(Z25.eggFilterLabel,Z25.eggFilter.mode=="active" and C.gold or C.dim)
        end
        if Z25.activeFilterButton then Z25.activeFilterButton.Text=Z25.eggFilter.mode=="active" and "■ ВЫКЛЮЧИТЬ АВТОУДАЛЕНИЕ" or "🗑 АВТОУДАЛЕНИЕ (2 НАЖАТИЯ)" end
    elseif activePage=="3 яйца" then
        if Z25.dualUiStatus then
            local status=dualEggMode and eggMessage or dualEgg.message
            local rares=Z25.eggFilter.rareDrops or {}
            uiText(Z25.dualUiStatus,(dualEggMode and "● РАБОТАЕТ" or "○ ОЖИДАНИЕ").." • Зима T3: "..dualEgg.winter3Sent.." / T4: "..dualEgg.winter4Sent.." / Луна T17: "..dualEgg.moonSent.."\nОставлено: "..Z25.eggFilter.kept.." • удалено: "..Z25.eggFilter.deleted.."\nРедкие за запуск: олень "..(rares['78005'] or 0).." • пингвин "..(rares['79003'] or 0).." • Huge "..(rares['17009'] or 0).."\n"..status)
            uiColor(Z25.dualUiStatus,dualEggMode and C.green or C.dim)
        end
        if Z25.dualUiStart then
            local caption=dualEgg.confirmationUntil>os.clock() and "ПОДТВЕРДИТЬ ОТКРЫТИЕ И ФИЛЬТР" or (dualEgg.includeT3 and "▶ ЗАПУСТИТЬ 3 ЯЙЦА" or "▶ ЗАПУСТИТЬ 2 ЯЙЦА")
            if Z25.dualUiStart.Text~=caption then Z25.dualUiStart.Text=caption end
        end
    elseif activePage=="Улучшение" then
        uiText(upgradeStatusLabel,(converting and "● ИДЁТ • " or "● ГОТОВО • ")..convertMessage.."\nПодтверждено улучшений: "..convertCompleted)
        uiColor(upgradeStatusLabel,converting and C.green or C.dim)
    elseif activePage=="Настройки" and Z25.healthLabel then
        uiText(Z25.healthLabel,"FPS: "..fpsValue.."  •  ошибок: "..stats.clientErrors)
    end
end
task.spawn(function()
    while alive and gui.Parent do
        task.wait(1.5)
        if alive and gui.Parent then refresh() end
    end
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
log("ZoneHub 5.2: оптимизированы монеты, инвентарь и интерфейс")

end -- createZoneHubUI

local uiOk, uiErr = pcall(createZoneHubUI)
if not uiOk then
    warn("ZoneHub 5.2 | UI startup error: "..tostring(uiErr))
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification",{
            Title="ZoneHub 5.2: ошибка запуска",
            Text=tostring(uiErr):sub(1,115),Duration=7
        })
    end)
end
