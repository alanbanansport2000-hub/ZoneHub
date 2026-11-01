-- ZoneHub Inventory Diagnostic v1 | original Pet Simulator (2018)
-- READ-ONLY. Only invokes known Core/Get Other Stats, reads PlayerGui and local client logs.
-- No Shop, Inventory, Pets, Delete, Equip, Fuse, Trade, Mine or changes to Save.
local Players = game:GetService('Players')
local UserInputService = game:GetService('UserInputService')
local LogService = game:GetService('LogService')
local player = Players.LocalPlayer
if not player then return end
local playerGui = player:WaitForChild('PlayerGui', 12)
if not playerGui then return end
local old = playerGui:FindFirstChild('ZoneHub_InventoryDiagnostic_v1')
if old then old:Destroy() end

local function new(class, properties, parent)
    local instance = Instance.new(class)
    for k, v in pairs(properties) do instance[k] = v end
    instance.Parent = parent
    return instance
end
local C = {
    background=Color3.fromRGB(16,22,36), panel=Color3.fromRGB(29,40,63),
    input=Color3.fromRGB(42,55,80), blue=Color3.fromRGB(61,107,190),
    green=Color3.fromRGB(48,135,111), muted=Color3.fromRGB(174,191,214),
    white=Color3.fromRGB(244,247,254), red=Color3.fromRGB(149,70,86)
}
local function round(obj, px)
    new('UICorner', {CornerRadius=UDim.new(0,px or 8)},obj)
end
local gui=new('ScreenGui', {Name='ZoneHub_InventoryDiagnostic_v1',ResetOnSpawn=false,IgnoreGuiInset=true,DisplayOrder=10012},playerGui)
local frame=new('Frame', {AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(478,545),BorderSizePixel=0,BackgroundColor3=C.background},gui)
round(frame,13)
local scale=new('UIScale',{},frame)
local function adapt()
    local camera=workspace.CurrentCamera
    local size=camera and camera.ViewportSize or Vector2.new(800,600)
    scale.Scale=math.clamp(math.min((size.X-16)/478,(size.Y-22)/545),.43,1)
end
adapt()
local function textLabel(text,x,y,w,h,sz,color)
    return new('TextLabel',{Text=text,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),BackgroundTransparency=1,
        TextColor3=color or C.white,Font=Enum.Font.Gotham,TextSize=sz or 12,TextWrapped=true,
        TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center},frame)
end
local function btn(text,x,y,w,h,callback,color)
    local b=new('TextButton',{Text=text,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),BorderSizePixel=0,
        BackgroundColor3=color or C.blue,TextColor3=C.white,Font=Enum.Font.GothamBold,
        TextSize=12,TextWrapped=true},frame)
    round(b,8)
    b.MouseButton1Click:Connect(callback)
    return b
end
textLabel('ZONEHUB · INVENTORY DIAGNOSTIC v1',14,8,446,30,17)
textLabel('Только чтение · ничего не удаляет и не скрещивает',14,37,445,21,11,C.muted)
local status=textLabel('1. Сними серверный снимок на ОСНОВЕ.',14,66,448,39,12,C.muted)
local out=new('TextBox',{Position=UDim2.fromOffset(14,176),Size=UDim2.fromOffset(448,302),BackgroundColor3=C.panel,
    BorderSizePixel=0,ClearTextOnFocus=false,MultiLine=true,TextEditable=false,Text='Отчёт появится после первого снимка.',
    TextWrapped=false,TextColor3=C.white,Font=Enum.Font.Code,TextSize=11,TextXAlignment=Enum.TextXAlignment.Left,
    TextYAlignment=Enum.TextYAlignment.Top},frame)
round(out,8)
local floating=new('TextButton',{Text='🔎 ДИАГНОСТИКА',Size=UDim2.fromOffset(167,42),Position=UDim2.fromOffset(9,130),
    BackgroundColor3=C.blue,TextColor3=C.white,Font=Enum.Font.GothamBold,TextSize=12,Visible=false,BorderSizePixel=0},gui)
round(floating,9)
local report, busy, serverSnapshot, serverAfter, inventoryGUI, tradeGUI, lastError = {}, false, nil, nil, nil, nil, 'нет'
local function fmt(value)
    if type(value)=='number' then
        if value ~= value then return 'NaN' end
        if value==math.huge then return '+Inf' end
        if value==-math.huge then return '-Inf' end
        if math.abs(value)<1e20 and value==math.floor(value) then return string.format('%.0f',value) end
    end
    return tostring(value)
end
local function add(s) report[#report+1]=s end
local function setStatus(s)
    status.Text=s
    print('[ZoneHub Inventory Diagnostic] '..s)
end
local function buildReport()
    report={}
    add('ZONEHUB INVENTORY DIAGNOSTIC v1')
    add('Режим: ТОЛЬКО ЧТЕНИЕ. Игровых изменений нет.')
    add('Время: '..os.date('!%Y-%m-%d %H:%M:%S UTC'))
    local function printSnap(tag,s)
        if not s then add(tag..': не выполнен');return end
        add(tag..': '..fmt(s.valid)..' корректных ID / '..fmt(s.slots or '?')..' слотов; записей '..fmt(s.entries))
        add('Экипировано='..fmt(s.equipped)..'; MaxPets='..fmt(s.maxPets or '?')..'; дубликатов ID='..fmt(s.duplicates))
        add('Типы: Gold='..fmt(s.gold)..' Rainbow='..fmt(s.rainbow)..' Dark='..fmt(s.dark))
        add('Диапазон уровней='..fmt(s.minLevel or '?')..' ... '..fmt(s.maxLevel or '?'))
        add('Невалидных записей='..fmt(s.bad)..'; подозрительных='..fmt(#s.issues))
        if #s.issues>0 then
            for i=1,math.min(#s.issues,24) do add('! '..s.issues[i]) end
            if #s.issues>24 then add('! ... ещё '..fmt(#s.issues-24)) end
        end
        if #s.high>0 then
            add('ТОП уровней (тип / уровень / ID):')
            for i=1,math.min(5,#s.high) do
                local p=s.high[i]
                add('  '..fmt(p.kind)..' / '..fmt(p.level)..' / '..fmt(p.id))
            end
        end
    end
    printSnap('Сервер ДО',serverSnapshot)
    printSnap('Сервер ПОВТОР',serverAfter)
    if serverSnapshot and serverAfter then
        add('Изменение числа питомцев: '..fmt(serverAfter.valid-serverSnapshot.valid))
        add('Изменение экипированных: '..fmt(serverAfter.equipped-serverSnapshot.equipped))
    end
    local function printUI(name,data)
        if not data then add(name..': не выполнено');return end
        add(name..': '..fmt(data.screens)..' ScreenGui, '..fmt(data.visibleScreens)..' видимых')
        add('Видимые элементы: Images='..fmt(data.images)..' Buttons='..fmt(data.buttons)..' Text='..fmt(data.texts))
        add('Совпадения pet/inventory/trade: '..fmt(data.matches))
        if #data.candidates>0 then
            add('Элементы интерфейса (до 14):')
            for _,v in ipairs(data.candidates) do add('  '..v) end
        end
    end
    printUI('UI ИНВЕНТАРЬ',inventoryGUI)
    printUI('UI ТРЕЙД',tradeGUI)
    add('Последняя ошибка='..lastError)
    add('ОТЧЁТ: никаких удалений/обменов/скрещиваний/покупок нет.')
    out.Text=table.concat(report,'\n')
end
local function getSave()
    local remotes=workspace:FindFirstChild('__REMOTES')
    local core=remotes and remotes:FindFirstChild('Core')
    local remote=core and core:FindFirstChild('Get Other Stats')
    if not remote or not remote:IsA('RemoteFunction') then
        return nil,'Не найден Core / Get Other Stats'
    end
    local ok,result=pcall(function() return remote:InvokeServer() end)
    if not ok then return nil,'Get Other Stats: '..tostring(result) end
    local user=type(result)=='table' and result[player.Name]
    local save=type(user)=='table' and user.Save
    if type(save)~='table' or type(save.Pets)~='table' then
        return nil,'Сервер не вернул Save.Pets (структура изменилась?)'
    end
    return save
end
local function readSnapshot()
    local save,err=getSave()
    if not save then return nil,err end
    local s={entries=0,valid=0,bad=0,slots=save.PetSlots,maxPets=save.MaxPets,equipped=0,
        duplicates=0,gold=0,rainbow=0,dark=0,issues={},high={},minLevel=nil,maxLevel=nil}
    local seen={}
    local function issue(txt)
        s.issues[#s.issues+1]=txt
    end
    for key,p in pairs(save.Pets) do
        s.entries=s.entries+1
        if type(p)~='table' then
            s.bad=s.bad+1
            issue('Запись '..fmt(key)..': не таблица ('..type(p)..')')
        else
            local id=tonumber(p.id)
            local level=tonumber(p.l)
            local xp=tonumber(p.xp)
            if not id or id<=0 or id~=math.floor(id) then
                s.bad=s.bad+1
                issue('Запись '..fmt(key)..': неверный id='..fmt(p.id))
            else
                s.valid=s.valid+1
                if seen[fmt(id)] then
                    s.duplicates=s.duplicates+1
                    issue('Повтор ID '..fmt(id))
                else seen[fmt(id)]=true end
            end
            if level==nil or level~=level or level<0 or level==math.huge then
                issue('ID '..fmt(id)..': неверный уровень '..fmt(p.l))
            elseif level>1e12 then
                issue('ID '..fmt(id)..': необычно большой уровень '..fmt(level))
            end
            if xp==nil or xp~=xp or xp<0 or xp==math.huge then
                issue('ID '..fmt(id)..': неверный XP '..fmt(p.xp))
            elseif xp>9007199254740992 then
                issue('ID '..fmt(id)..': XP больше 2^53 (возможна потеря точности)')
            end
            if p.n==nil then issue('ID '..fmt(id)..': нет поля типа n') end
            if p.e==true then s.equipped=s.equipped+1 end
            if p.g==true or p.gold==true then s.gold=s.gold+1 end
            if p.r==true or p.rainbow==true then s.rainbow=s.rainbow+1 end
            if p.dm==true or p.d==true or p.darkMatter==true then s.dark=s.dark+1 end
            if level and level>=0 and level<math.huge then
                if s.minLevel==nil or level<s.minLevel then s.minLevel=level end
                if s.maxLevel==nil or level>s.maxLevel then s.maxLevel=level end
                s.high[#s.high+1]={id=id or '?',level=level,kind=p.n or '?'}
            end
        end
    end
    table.sort(s.high,function(a,b) return a.level>b.level end)
    if s.slots and s.valid>s.slots then issue('Количество питомцев больше PetSlots') end
    if s.maxPets and s.equipped>s.maxPets then issue('Экипировано больше MaxPets') end
    return s
end
local function nodeVisible(node)
    local current=node
    while current and current~=playerGui do
        if current:IsA('GuiObject') and not current.Visible then return false end
        if current:IsA('ScreenGui') and not current.Enabled then return false end
        current=current.Parent
    end
    return true
end
local function captureUI()
    local data={screens=0,visibleScreens=0,images=0,buttons=0,texts=0,matches=0,candidates={}}
    local items=playerGui:GetDescendants()
    for _,item in ipairs(items) do
        if item:IsA('ScreenGui') and item~=gui then
            data.screens=data.screens+1
            if item.Enabled then data.visibleScreens=data.visibleScreens+1 end
        end
        if item~=gui and not item:IsDescendantOf(gui) and item:IsA('GuiObject') and nodeVisible(item) then
            if item:IsA('ImageLabel') or item:IsA('ImageButton') then data.images=data.images+1 end
            if item:IsA('TextButton') or item:IsA('ImageButton') then data.buttons=data.buttons+1 end
            if item:IsA('TextLabel') or item:IsA('TextButton') then data.texts=data.texts+1 end
            local name=string.lower(item.Name)
            local match=name:find('pet',1,true) or name:find('invent',1,true) or name:find('trad',1,true)
                or name:find('slot',1,true) or name:find('grid',1,true)
            if match then
                data.matches=data.matches+1
                if #data.candidates<14 then
                    local size=item.AbsoluteSize
                    data.candidates[#data.candidates+1]=item.ClassName..' '..item.Name..' '..fmt(size.X)..'x'..fmt(size.Y)
                end
            end
        end
    end
    return data
end
local working=false
local function run(fn)
    if working then setStatus('Идёт другая проверка.');return end
    working=true
    task.spawn(function()
        local ok,err=pcall(fn)
        if not ok then
            lastError=tostring(err)
            setStatus('Ошибка: '..lastError:sub(1,135))
        end
        buildReport()
        working=false
    end)
end
btn('1. СЕРВЕРНЫЙ СНИМОК',14,109,219,54,function()
    run(function()
        local data,err=readSnapshot()
        if not data then lastError=err;setStatus(err);return end
        serverSnapshot=data
        serverAfter=nil
        setStatus('Сервер: '..fmt(data.valid)..'/'..fmt(data.slots)..'. Теперь открой инвентарь и нажми 2.')
    end)
end)
btn('2. ИНВЕНТАРЬ',243,109,219,54,function()
    run(function()
        inventoryGUI=captureUI()
        setStatus('Интерфейс питомцев считан. Теперь открой Trade и нажми 3.')
    end)
end)
btn('3. ТРЕЙД',14,486,132,44,function()
    run(function()
        tradeGUI=captureUI()
        local data,err=readSnapshot()
        if data then serverAfter=data else lastError=err end
        setStatus('Данные обмена считаны. Нажми КОПИРОВАТЬ ОТЧЁТ.')
    end)
end)
btn('КОПИРОВАТЬ',156,486,150,44,function()
    buildReport()
    if type(setclipboard)=='function' then
        local ok=pcall(function() setclipboard(out.Text) end)
        setStatus(ok and 'Отчёт скопирован — пришли его в чат.' or 'Копирование недоступно. Выдели текст в отчёте.')
    else
        setStatus('Нет setclipboard. Выдели текст отчёта или сделай скриншоты.')
    end
end,C.green)
btn('СКРЫТЬ',316,486,146,44,function()
    frame.Visible=false
    floating.Visible=true
end,C.input)
floating.MouseButton1Click:Connect(function()
    frame.Visible=true
    floating.Visible=false
end)
buildReport()
setStatus('Готов. Нажми 1; затем открой инвентарь, верни панель и нажми 2.')
