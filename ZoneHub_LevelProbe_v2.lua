-- ZoneHub LevelProbe v2 | Pet Simulator (2018)
-- READ-ONLY: reads Core/Get Other Stats, inspects remote names and compares server pet snapshots.
-- NEVER sends upgrade/coin/buy/equip/delete/fuse requests, changes local pet tables, or touches currency.
local Players = game:GetService('Players')
local UIS = game:GetService('UserInputService')
local plr = Players.LocalPlayer
if not plr then return end
local playerGui = plr:WaitForChild('PlayerGui', 10)
if not playerGui then return end
local prev = playerGui:FindFirstChild('ZoneHub_LevelProbe_v2')
if prev then prev:Destroy() end

local function create(class,properties,parent)
    local inst = Instance.new(class)
    for k,v in pairs(properties) do inst[k]=v end
    inst.Parent=parent
    return inst
end
local COLORS = {
    bg=Color3.fromRGB(16,20,33),panel=Color3.fromRGB(29,36,55),entry=Color3.fromRGB(42,51,76),
    accent=Color3.fromRGB(92,97,218),green=Color3.fromRGB(48,139,113),red=Color3.fromRGB(135,67,83),
    text=Color3.fromRGB(242,245,254),muted=Color3.fromRGB(177,190,216)
}
local function round(node,radius)
    create('UICorner',{CornerRadius=UDim.new(0,radius or 8)},node)
end
local gui=create('ScreenGui',{Name='ZoneHub_LevelProbe_v2',ResetOnSpawn=false,IgnoreGuiInset=true,DisplayOrder=10003},playerGui)
local panel=create('Frame',{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(486,620),BorderSizePixel=0,BackgroundColor3=COLORS.bg},gui)
round(panel,12)
local scale=create('UIScale',{},panel)
local function setScale()
    local cam=workspace.CurrentCamera
    local size=cam and cam.ViewportSize or Vector2.new(800,700)
    scale.Scale=math.clamp(math.min((size.X-22)/486,(size.Y-30)/620),.42,1)
end
setScale()
local camConn=workspace:GetPropertyChangedSignal('CurrentCamera'):Connect(setScale)
local function label(value,x,y,w,h,fontSize,color)
    return create('TextLabel',{
        Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),BackgroundTransparency=1,
        Text=value,TextColor3=color or COLORS.text,Font=Enum.Font.Gotham,TextSize=fontSize or 12,
        TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center
    },panel)
end
local function button(value,x,y,w,h,color,callback)
    local b=create('TextButton',{
        Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),BorderSizePixel=0,
        BackgroundColor3=color or COLORS.accent,Text=value,TextColor3=COLORS.text,
        Font=Enum.Font.GothamBold,TextSize=12,TextWrapped=true
    },panel)
    round(b,7)
    b.MouseButton1Click:Connect(callback)
    return b
end
label('ZONEHUB · LEVEL PROBE v2',16,9,422,28,18)
label('Проверка серверных уровней и доступных операций · без изменений',16,37,451,22,11,COLORS.muted)
local status=label('Нажми «1. СЕРВЕРНЫЙ СНИМОК».',16,66,451,43,12,COLORS.muted)
local selection=label('Выбран питомец: нет',16,115,451,24,12,COLORS.text)
local scroll=create('ScrollingFrame',{
    Position=UDim2.fromOffset(16,146),Size=UDim2.fromOffset(454,147),BorderSizePixel=0,
    BackgroundColor3=COLORS.panel,CanvasSize=UDim2.fromOffset(0,0),ScrollBarThickness=4
},panel)
round(scroll,8)
local layout=create('UIListLayout',{Padding=UDim.new(0,3),SortOrder=Enum.SortOrder.LayoutOrder},scroll)
local summary=label('Отчёт появится после первого серверного снимка.',16,301,450,67,11,COLORS.muted)
local busy=false
local selectedId=nil
local petRows={}
local baseline=nil
local after=nil
local discovery=nil
local latestError=''

local function fmt(v)
    if type(v)=='number' then
        if v==math.floor(v) then return string.format('%.0f',v) end
        return tostring(v)
    end
    if v==nil then return 'nil' end
    return tostring(v)
end
local function safeScalar(v)
    if type(v)=='string' then
        local clean=v:gsub('[\r\n]',' ')
        return (#clean>80) and clean:sub(1,80)..'...' or clean
    end
    if type(v)=='number' or type(v)=='boolean' or v==nil then return fmt(v) end
    return '['..type(v)..']'
end
local function getSave()
    local remotes=workspace:FindFirstChild('__REMOTES')
    local core=remotes and remotes:FindFirstChild('Core')
    local getStats=core and core:FindFirstChild('Get Other Stats')
    if not getStats or not getStats:IsA('RemoteFunction') then
        return nil,'Core / Get Other Stats не найден (RemoteFunction)'
    end
    local ok, result=pcall(function() return getStats:InvokeServer() end)
    if not ok then return nil,'Get Other Stats: '..tostring(result) end
    local ps=type(result)=='table' and result[plr.Name]
    local save=type(ps)=='table' and ps.Save
    if type(save)~='table' or type(save.Pets)~='table' then
        return nil,'Сервер не вернул '..plr.Name..'.Save.Pets'
    end
    return save
end
local function scalarRecord(p)
    local a={}
    if type(p)~='table' then return a end
    for k,v in pairs(p) do
        if type(v)=='number' or type(v)=='string' or type(v)=='boolean' then
            a[tostring(k)]=v
        end
    end
    return a
end
local function snapshot()
    local save,err=getSave()
    if not save then return nil,err end
    local data={pets={},count=0,slots=tonumber(save.PetSlots),saveKeys={},selected=nil}
    for k,v in pairs(save) do
        local name=tostring(k)
        if type(v)=='number' or type(v)=='boolean' or type(v)=='string' then
            data.saveKeys[#data.saveKeys+1]=name..'='..safeScalar(v)
        elseif type(v)=='table' then
            data.saveKeys[#data.saveKeys+1]=name..'=[table]'
        end
    end
    table.sort(data.saveKeys)
    for _,p in pairs(save.Pets) do
        local id=type(p)=='table' and tonumber(p.id)
        if id and id>0 then
            data.count=data.count+1
            local record=scalarRecord(p)
            data.pets[id]=record
            if id==selectedId then data.selected=record end
        end
    end
    return data
end
local function say(message)
    status.Text=message
    print('[ZoneHub LevelProbe v2] '..message)
end
local function renderRows()
    for _,ch in ipairs(scroll:GetChildren()) do
        if ch:IsA('TextButton') then ch:Destroy() end
    end
    for i,p in ipairs(petRows) do
        local active=(selectedId==p.id)
        local b=create('TextButton',{
            LayoutOrder=i,Size=UDim2.new(1,-8,0,33),BorderSizePixel=0,
            BackgroundColor3=active and COLORS.accent or COLORS.entry,
            TextColor3=COLORS.text,Font=Enum.Font.Code,TextSize=11,
            TextXAlignment=Enum.TextXAlignment.Left,
            Text=('  %s ID %s  ур. %s  тип %s'):format(active and '●' or '○',fmt(p.id),fmt(p.level),fmt(p.kind))
        },scroll)
        round(b,6)
        b.MouseButton1Click:Connect(function()
            selectedId=p.id
            selection.Text=('Выбран ID %s · уровень %s'):format(fmt(p.id),fmt(p.level))
            -- Capture a baseline only on an explicit snapshot click; avoid mixing pets.
            baseline=nil
            after=nil
            renderRows()
            say('Питомец выбран. Нажми «1. СЕРВЕРНЫЙ СНИМОК» заново.')
        end)
    end
    scroll.CanvasSize=UDim2.fromOffset(0,#petRows*36+8)
end
local function summarize(data)
    local p=selectedId and data.pets[selectedId]
    if p then
        summary.Text=('Сервер: %s/%s питомцев\nВыбран ID %s · уровень %s\nПоля: %s'):format(
            fmt(data.count),fmt(data.slots),fmt(selectedId),fmt(p.l),
            table.concat((function()
                local t={};for k in pairs(p) do t[#t+1]=k end;table.sort(t);return t
            end)(),', ')
        )
    else
        summary.Text=('Сервер: %s/%s питомцев\nВыбери питомца из списка и сними новый снимок.'):format(fmt(data.count),fmt(data.slots))
    end
end
local function doWork(work)
    if busy then say('Предыдущая проверка ещё выполняется.');return end
    busy=true
    task.spawn(function()
        local ok,err=pcall(work)
        if not ok then
            latestError=tostring(err)
            say('Ошибка проверки: '..latestError:sub(1,115))
        end
        busy=false
    end)
end
button('1. СЕРВЕРНЫЙ СНИМОК',16,376,222,43,COLORS.accent,function()
    doWork(function()
        local data,err=snapshot()
        if not data then say(err);return end
        petRows={}
        for id,p in pairs(data.pets) do
            petRows[#petRows+1]={id=id,level=tonumber(p.l) or 0,kind=p.n or p.t or p.name or '?'}
        end
        table.sort(petRows,function(a,b)
            if a.level~=b.level then return a.level>b.level end
            return a.id<b.id
        end)
        if not selectedId or not data.pets[selectedId] then
            selectedId=petRows[1] and petRows[1].id or nil
            -- First selected pet record already in this server response.
        end
        baseline=data
        after=nil
        renderRows()
        local p=selectedId and data.pets[selectedId]
        selection.Text=p and ('Выбран ID '..fmt(selectedId)..' · уровень '..fmt(p.l)) or 'Нет питомцев'
        summarize(data)
        say('Снимок готов. Теперь нажми «2. НАЙТИ ОПЕРАЦИИ».')
    end)
end)

local KEYWORDS={'level','upgrade','evolve','pet','xp','exp','train','power','stats','fusion','fuse','enchant','rebirth','mastery','hatch','egg'}
local function candidate(name)
    local low=string.lower(name)
    for _,s in ipairs(KEYWORDS) do if string.find(low,s,1,true) then return true end end
    return false
end
local function scanRemotes()
    local paths={}
    local candidates={}
    local counts={functions=0,events=0}
    local scanRoots={}
    local root=workspace:FindFirstChild('__REMOTES')
    if root then scanRoots[#scanRoots+1]=root end
    local rs=game:GetService('ReplicatedStorage')
    if rs then scanRoots[#scanRoots+1]=rs end
    local seen={}
    for _,dir in ipairs(scanRoots) do
        for _,inst in ipairs(dir:GetDescendants()) do
            if (inst:IsA('RemoteFunction') or inst:IsA('RemoteEvent')) and not seen[inst] then
                seen[inst]=true
                local path=inst:GetFullName()
                local kind=inst:IsA('RemoteFunction') and 'RF' or 'RE'
                if kind=='RF' then counts.functions=counts.functions+1 else counts.events=counts.events+1 end
                local line=kind..' '..path
                paths[#paths+1]=line
                if candidate(path) then candidates[#candidates+1]=line end
            end
        end
    end
    table.sort(paths)
    table.sort(candidates)
    return {all=paths,likely=candidates,rf=counts.functions,re=counts.events}
end
button('2. НАЙТИ ОПЕРАЦИИ',248,376,222,43,COLORS.accent,function()
    doWork(function()
        discovery=scanRemotes()
        say(('Найдено: %d RemoteFunction, %d RemoteEvent; потенциально связанных: %d.'):format(discovery.rf,discovery.re,#discovery.likely))
        local lines={}
        for i,v in ipairs(discovery.likely) do
            if i>3 then break end
            lines[#lines+1]=v:gsub('^%u%u ',''):sub(-60)
        end
        summary.Text='Операции обнаружены (не вызывались):\n'..table.concat(lines,'\n')
    end)
end)
button('3. ПОВТОРНЫЙ СНИМОК',16,426,222,43,COLORS.green,function()
    doWork(function()
        if not baseline then say('Сначала нажми кнопку 1.');return end
        local data,err=snapshot()
        if not data then say(err);return end
        after=data
        local old=baseline.pets[selectedId]
        local new=data.pets[selectedId]
        if not old then say('Выбранного ID не было на первом снимке.');return end
        if not new then say('Выбранный питомец исчез из инвентаря — проверь обычный игровой интерфейс.');return end
        summarize(data)
        local beforeL=tonumber(old.l)
        local afterL=tonumber(new.l)
        if beforeL and afterL and beforeL~=afterL then
            say('ИЗМЕНЕНИЕ УРОВНЯ: '..fmt(beforeL)..' → '..fmt(afterL)..'. Требуется перезаход для проверки сохранения.')
        else
            say('Повторный снимок: уровень не изменился ('..fmt(afterL)..').')
        end
    end)
end)

local function makeReport()
    local lines={
        'ZONEHUB LEVEL PROBE v2 | ОТЧЁТ',
        'Режим: только чтение Get Other Stats + имена RemoteFunction/RemoteEvent.',
        'Изменение питомцев, покупка, Fuse, Mine и вызовы неизвестных Remote: НЕТ.',
        'Предыдущий LevelProbe v1: подмена Mine не изменила серверный уровень.',
        'Последняя ошибка: '..(latestError~='' and latestError or 'нет')
    }
    if baseline then
        lines[#lines+1]='Снимок ДО: '..fmt(baseline.count)..'/'..fmt(baseline.slots)
        lines[#lines+1]='ID выбранного питомца: '..fmt(selectedId)
        local p=selectedId and baseline.pets[selectedId]
        if p then
            lines[#lines+1]='Уровень ДО: '..fmt(p.l)
            local keys={};for key in pairs(p) do keys[#keys+1]=key end;table.sort(keys)
            for _,key in ipairs(keys) do lines[#lines+1]='Pet.'..key..'='..safeScalar(p[key]) end
        end
        lines[#lines+1]='Доступные ключи Save (без содержимого таблиц):'
        for i,v in ipairs(baseline.saveKeys) do
            if i>100 then lines[#lines+1]='... остальные пропущены';break end
            lines[#lines+1]=v
        end
    else
        lines[#lines+1]='Снимок ДО: не выполнен'
    end
    if after then
        lines[#lines+1]='Снимок ПОСЛЕ: '..fmt(after.count)..'/'..fmt(after.slots)
        local old=baseline and baseline.pets[selectedId]
        local new=selectedId and after.pets[selectedId]
        if new then
            lines[#lines+1]='Уровень ПОСЛЕ: '..fmt(new.l)
            if old then
                local keys={}
                for k in pairs(old) do keys[k]=true end
                for k in pairs(new) do keys[k]=true end
                local sorted={};for k in pairs(keys) do sorted[#sorted+1]=k end;table.sort(sorted)
                local changes=0
                for _,k in ipairs(sorted) do
                    if old[k]~=new[k] then
                        lines[#lines+1]='ИЗМЕНЕНИЕ Pet.'..k..': '..safeScalar(old[k])..' => '..safeScalar(new[k])
                        changes=changes+1
                    end
                end
                if changes==0 then lines[#lines+1]='Изменённых полей выбранного питомца: 0' end
            end
        else
            lines[#lines+1]='Выбранного питомца нет на повторном снимке.'
        end
    else
        lines[#lines+1]='Снимок ПОСЛЕ: не выполнен'
    end
    if discovery then
        lines[#lines+1]=('Операции: RemoteFunction=%d, RemoteEvent=%d, потенциальных=%d'):format(discovery.rf,discovery.re,#discovery.likely)
        lines[#lines+1]='--- Названия потенциально связанных операций (только список) ---'
        for i,v in ipairs(discovery.likely) do
            if i>100 then lines[#lines+1]='... остальные пропущены';break end
            lines[#lines+1]=v
        end
        lines[#lines+1]='--- Остальные операции (для проверки структуры) ---'
        local count=0
        for _,v in ipairs(discovery.all) do
            if not candidate(v) then
                count=count+1
                if count<=100 then lines[#lines+1]=v end
            end
        end
        if count>100 then lines[#lines+1]='... ещё '..(count-100)..' операций' end
    else
        lines[#lines+1]='Сканирование операций: не выполнено'
    end
    lines[#lines+1]='ВЫВОД: найденные имена не подтверждают существование работающей команды изменения уровня.'
    return table.concat(lines,'\n')
end
button('4. КОПИРОВАТЬ ОТЧЁТ',248,426,222,43,COLORS.accent,function()
    local report=makeReport()
    print(report)
    if type(setclipboard)=='function' then
        local ok=pcall(function() setclipboard(report) end)
        say(ok and 'Отчёт скопирован. Пришли его в чат.' or 'Ошибка копирования, отчёт напечатан в консоль.')
    else
        say('Нет setclipboard; отчёт выведен в консоль.')
    end
end)
label('Порядок: 1 → 2 → 3 → 4. Между 1 и 3 можешь применить ОБЫЧНОЕ игровое улучшение, если оно существует. Скрипт сам ничего не улучшает.',16,482,451,67,12,COLORS.muted)
button('ЗАКРЫТЬ',16,562,454,40,COLORS.red,function()
    if camConn then camConn:Disconnect() end
    gui:Destroy()
end)
-- Drag the upper title bar with mouse/touch.
local dragging=false
local startPoint=nil
local startPosition=nil
panel.InputBegan:Connect(function(input)
    if input.Position.Y>panel.AbsolutePosition.Y+55 then return end
    if input.UserInputType~=Enum.UserInputType.Touch and input.UserInputType~=Enum.UserInputType.MouseButton1 then return end
    dragging=true
    startPoint=input.Position
    startPosition=panel.Position
    local connection
    connection=input.Changed:Connect(function()
        if input.UserInputState==Enum.UserInputState.End then
            dragging=false
            if connection then connection:Disconnect() end
        end
    end)
end)
local dragConn
 dragConn=UIS.InputChanged:Connect(function(input)
    if not dragging or not startPoint then return end
    if input.UserInputType~=Enum.UserInputType.Touch and input.UserInputType~=Enum.UserInputType.MouseMovement then return end
    local diff=input.Position-startPoint
    panel.Position=UDim2.new(startPosition.X.Scale,startPosition.X.Offset+diff.X,startPosition.Y.Scale,startPosition.Y.Offset+diff.Y)
end)
gui.Destroying:Connect(function()
    if dragConn then dragConn:Disconnect() end
    if camConn then camConn:Disconnect() end
end)
say('LevelProbe v2 загружен: только чтение. Нажми кнопку 1.')
