-- ZoneHub LevelProbe v3 (Pet Simulator 2018)
-- READ ONLY: observes server Save.Pets pet level and XP while normal gameplay/farm runs.
-- No Mine, Fuse, Shop, Inventory, PetMovement or unknown remote calls.
local Players = game:GetService('Players')
local player = Players.LocalPlayer
if not player then return end
local pg = player:WaitForChild('PlayerGui', 10)
if not pg then return end
local prev = pg:FindFirstChild('ZoneHub_LevelProbe_v3')
if prev then prev:Destroy() end

local function make(cls, props, parent)
    local obj = Instance.new(cls)
    for k,v in pairs(props) do obj[k]=v end
    obj.Parent=parent
    return obj
end
local C={bg=Color3.fromRGB(17,22,34), panel=Color3.fromRGB(31,39,60),
  btn=Color3.fromRGB(78,93,187), stop=Color3.fromRGB(148,65,78),
  text=Color3.fromRGB(240,245,255), dim=Color3.fromRGB(181,194,217)}
local gui = make('ScreenGui', {Name='ZoneHub_LevelProbe_v3', ResetOnSpawn=false,
  IgnoreGuiInset=true, DisplayOrder=10015}, pg)
local panel=make('Frame',{Size=UDim2.fromOffset(452,468),AnchorPoint=Vector2.new(.5,.5),
  Position=UDim2.fromScale(.5,.5),BorderSizePixel=0,BackgroundColor3=C.bg},gui)
make('UICorner',{CornerRadius=UDim.new(0,12)},panel)
local scale=make('UIScale',{},panel)
local function fit()
  local camera=workspace.CurrentCamera
  local s=camera and camera.ViewportSize or Vector2.new(700,600)
  scale.Scale=math.clamp(math.min((s.X-16)/452,(s.Y-16)/468),.45,1)
end
fit()
local function lbl(t,x,y,w,h,size,color)
 return make('TextLabel',{Text=t,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),
  BackgroundTransparency=1,TextColor3=color or C.text,Font=Enum.Font.Gotham,
  TextSize=size or 12,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center,
  TextWrapped=true},panel)
end
local function btn(t,x,y,w,h,color,callback)
 local b=make('TextButton',{Text=t,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),
  BackgroundColor3=color or C.btn,BorderSizePixel=0,TextColor3=C.text,
  TextWrapped=true,TextSize=12,Font=Enum.Font.GothamBold},panel)
 make('UICorner',{CornerRadius=UDim.new(0,8)},b)
 b.MouseButton1Click:Connect(callback)
 return b
end
lbl('ZONEHUB LEVEL PROBE v3',14,8,355,27,18)
lbl('Наблюдение за серверным XP и уровнем. Ничего не меняет.',14,36,424,34,11,C.dim)
local close=btn('✕',401,9,36,30,C.stop,function() end)
local box=make('TextBox',{Position=UDim2.fromOffset(14,77),Size=UDim2.fromOffset(203,36),
 Text='92565120',PlaceholderText='Pet ID',TextColor3=C.text,BackgroundColor3=C.panel,
 TextSize=15,Font=Enum.Font.Code,BorderSizePixel=0,ClearTextOnFocus=false},panel)
make('UICorner',{CornerRadius=UDim.new(0,7)},box)
lbl('ID питомца (из отчёта v2)',227,77,212,36,12,C.dim)
local status=lbl('Сначала нажми «СНИМОК», затем запусти наблюдение и обычный фарм.',14,120,424,49,12,C.dim)
local info=lbl('Серверный снимок: нет',14,172,424,128,13,C.text)
local details=lbl('Опрос: каждые 5 секунд, только Get Other Stats.',14,301,424,31,11,C.dim)
local baseline,latest,started,ended,runId,lastError,observations,changes,selected
local ongoing=false
local function f(n)
 if type(n)~='number' then return tostring(n) end
 if n==math.floor(n) then return string.format('%.0f',n) end
 return string.format('%.3f',n)
end
local function fetch(id)
 local all=workspace:FindFirstChild('__REMOTES')
 local core=all and all:FindFirstChild('Core')
 local rf=core and core:FindFirstChild('Get Other Stats')
 if not rf or not rf:IsA('RemoteFunction') then return nil,'Get Other Stats не найден' end
 local ok,result=pcall(function() return rf:InvokeServer() end)
 if not ok then return nil,'Remote: '..tostring(result) end
 local playerData=type(result)=='table' and result[player.Name]
 local save=type(playerData)=='table' and playerData.Save
 if type(save)~='table' or type(save.Pets)~='table' then return nil,'Save.Pets не найден' end
 local count=0
 local pet
 for _,p in pairs(save.Pets) do
  if type(p)=='table' and tonumber(p.id) then
   count=count+1
   if tonumber(p.id)==id then pet=p end
  end
 end
 if not pet then return nil,'Питомец ID '..f(id)..' отсутствует; серверный инвентарь '..f(count) end
 return {id=id,level=tonumber(pet.l),xp=tonumber(pet.xp),name=tostring(pet.cn or pet.n or '?'),
   count=count,slots=tonumber(save.PetSlots),time=os.clock()}
end
local function diff()
 if not baseline or not latest then return '' end
 local dl=(latest.level and baseline.level) and latest.level-baseline.level
 local dx=(latest.xp and baseline.xp) and latest.xp-baseline.xp
 return 'Δ level: '..f(dl)..' | Δ XP: '..f(dx)
end
local function draw()
 if not latest then return end
 local secs=started and math.max(0,math.floor((ended or os.clock())-started)) or 0
 info.Text=('Питомец: %s | ID %s\nУровень: %s → %s\nXP: %s → %s\n%s\nИнвентарь: %s/%s | наблюдение: %s c'):format(
  latest.name,f(latest.id),f(baseline and baseline.level),f(latest.level),
  f(baseline and baseline.xp),f(latest.xp),diff(),f(latest.count),f(latest.slots),f(secs))
end
local function report()
 local a={'ZONEHUB LEVEL PROBE v3 | ОТЧЁТ',
 'Режим: пассивное чтение серверного Save.Pets; вызовов Mine/Shop/Fuse нет.',
 'Pet ID='..f(selected),'Работает='..tostring(ongoing),
 'Снимков='..f(observations or 0),'Изменений='..f(changes or 0)}
 if baseline then
  a[#a+1]='До: level='..f(baseline.level)..' | XP='..f(baseline.xp)
 end
 if latest then
  a[#a+1]='После: level='..f(latest.level)..' | XP='..f(latest.xp)
  a[#a+1]=diff()
  a[#a+1]='Инвентарь='..f(latest.count)..'/'..f(latest.slots)
 end
 a[#a+1]='Продолжительность, сек='..f(started and math.floor((ended or os.clock())-started) or 0)
 a[#a+1]='Ошибка='..tostring(lastError or 'нет')
 a[#a+1]='Интерпретация: изменения XP/уровня при обычном фарме подтверждают естественную прокачку, но не возможность задать произвольный уровень.'
 return table.concat(a,'\n')
end
local function selectId()
 local id=tonumber(box.Text)
 if not id or id<1 or id~=math.floor(id) then
   status.Text='Укажи числовой Pet ID (например 92565120).'
   return nil
 end
 return id
end
local function refresh()
 if ongoing then status.Text='Сначала останови наблюдение.'; return end
 local id=selectId()
 if not id then return end
 local snap,err=fetch(id)
 if not snap then status.Text='Ошибка: '..tostring(err);lastError=err;return end
 selected=id;baseline=snap;latest=snap;started=nil;ended=nil;observations=1;changes=0;lastError=nil
 status.Text='Снимок готов. Нажми «НАЧАТЬ» и включи обычный Auto Farm.'
 draw()
end
btn('1. СНИМОК',14,345,133,40,C.btn,refresh)
btn('2. НАЧАТЬ',159,345,132,40,C.btn,function()
 if ongoing then status.Text='Уже наблюдаю.';return end
 if not baseline then refresh() end
 if not baseline then return end
 local id=selectId()
 if id~=selected then status.Text='ID изменён. Сначала новый снимок.';return end
 ongoing=true;runId=(runId or 0)+1
 local myRun=runId
 started=os.clock();ended=nil;changes=0;observations=1
 status.Text='Наблюдаю. Фарми обычным ZoneHub 1–3 минуты.'
 task.spawn(function()
  while ongoing and runId==myRun and gui.Parent do
   task.wait(5)
   if not ongoing or runId~=myRun or not gui.Parent then break end
   local snap,err=fetch(id)
   if snap then
    observations=observations+1
    if latest and ((snap.level~=latest.level) or (snap.xp~=latest.xp)) then changes=changes+1 end
    latest=snap;draw()
    status.Text=('Опрос #%s: %s'):format(f(observations),diff())
   else
    lastError=err;status.Text='Ошибка чтения: '..tostring(err):sub(1,100)
   end
  end
 end)
end)
btn('3. СТОП',303,345,135,40,C.stop,function()
 ongoing=false;runId=(runId or 0)+1;ended=os.clock()
 draw();status.Text='Остановлено. Нажми «КОПИРОВАТЬ ОТЧЁТ».'
end)
btn('4. КОПИРОВАТЬ ОТЧЁТ',14,395,424,44,C.btn,function()
 local r=report()
 if type(setclipboard)=='function' then
  local ok=pcall(setclipboard,r)
  status.Text=ok and 'Отчёт скопирован. Вставь его в чат.' or 'Ошибка буфера; отчёт выведен в консоль.'
 else status.Text='Нет setclipboard; отчёт выведен в консоль.' end
 print(r)
end)
close.MouseButton1Click:Connect(function()
 ongoing=false;runId=(runId or 0)+1
 gui:Destroy()
end)
print('[ZoneHub LevelProbe v3] Запущен (только чтение).')
