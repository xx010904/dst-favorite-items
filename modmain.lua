--[[
    收藏物品 / Favorite Items
    版本: 1.3.0
    架构: 纯客户端 mod (client_only_mod = true)
      参考 TMIR (Too-Many-Items-Rearrange) 的 "客户端发命令 -> 服务端执行" 模式:
      - 客户端只负责: 记录收藏映射 + 把收藏表拼成一段自带完整逻辑的原生 Lua 命令字符串。
      - 命令通过 TheNet:SendRemoteExecute (远程服务器管理员) 或 ExecuteConsoleCommand
        (单机/主机, 客户端即服务器) 发到服务器执行; 服务器不加载本 mod, 只执行这段
        原生 Lua, 用 UserToPlayer + inventory 原生 API 把物品锁回指定槽位。
      - 因此本 mod 不在服务器侧运行任何代码, 彻底避免 "steam 订阅/校验覆盖本地修改" 的问题。
    注意:
      - 专用服务器下, 使用该功能的玩家必须是服务器管理员 (SendRemoteExecute 要求 admin),
        否则只会看到提示而无法锁位 (非 admin 客户端无法驱动服务器)。
      - 命令字符串只使用 DST 原生 API, 不依赖本 mod 在服务器的任何全局, 故服务器无需装本 mod。
    修复历史:
      - 1.1.0/1.2.x: 早期为服务端 mod, 存在换槽复制/崩溃、strict 模式加载报错、tonumber 缺失、
        提示语不随语言切换等问题, 均已在客户端化过程中一并修正。
]]

GLOBAL.MOD_FAVORITE_ITEM = {}

GLOBAL.MOD_FAVORITE_ITEM.INVENTORY_UPDATE_TIME = GLOBAL.tonumber(GetModConfigData("INVENTORY_UPDATE_TIME")) or 0.2
GLOBAL.MOD_FAVORITE_ITEM.HAVE_FAVORITED = GLOBAL.MOD_FAVORITE_ITEM.HAVE_FAVORITED or false
GLOBAL.FAVORITED_ITEMS = {}

GLOBAL.FAVITSAVE = "FAVORITEITEMS"
GLOBAL.SHOWTABLE = ""

local mod_fav = GLOBAL.MOD_FAVORITE_ITEM

-- ---------------------------------------------------------------------------
-- 捕获标准库函数
-- 注意: DST 给 mod 注入的 env 环境表 (scripts/mods.lua CreateEnvironment)
-- 只注入了 pairs/ipairs/print/math/table/type/string/tostring/require/Class/GLOBAL
-- 等, 并没有 tonumber/setmetatable 等。直接用裸 tonumber(...) / ExecuteConsoleCommand
-- 会在 env 里查到 nil -> 报错。这里统一从 GLOBAL(即 _G) 捕获本 mod 实际用到的函数。
-- ---------------------------------------------------------------------------
local tonumber  = GLOBAL.tonumber
local tostring  = GLOBAL.tostring
local math      = GLOBAL.math
local table     = GLOBAL.table
local string    = GLOBAL.string
local pairs     = GLOBAL.pairs
local ipairs    = GLOBAL.ipairs
local type      = GLOBAL.type
local ExecuteConsoleCommand = GLOBAL.ExecuteConsoleCommand

-- ---------------------------------------------------------------------------
-- 多语言提示语 (in-game talker) — 全部在客户端生成, 实时按当前语言取
-- ---------------------------------------------------------------------------
local MESSAGES = {
    english = {
        favorited = " favorited to slot ",
        removed   = " removed from slot ",
        moved     = " moved to slot ",
        replaced  = " replaced the item in slot ",
        cleared   = "All favorited items cleared.",
        need_admin = " favorites require server admin to lock",
    },
    schinese = {
        favorited = " 已收藏到槽位 ",
        removed   = " 已从槽位 ",
        moved     = " 被移动到槽位 ",
        replaced  = " 替换了槽位 ",
        cleared   = "已清除所有收藏物品。",
        need_admin = " 收藏锁定需要服务器管理员权限",
    },
    tchinese = {
        favorited = " 已收藏到欄位 ",
        removed   = " 已從欄位 ",
        moved     = " 被移動到欄位 ",
        replaced  = " 替換了欄位 ",
        cleared   = "已清除所有收藏物品。",
        need_admin = " 收藏鎖定需要伺服器管理員權限",
    },
    russian = {
        favorited = " добавлен в слот ",
        removed   = " удалён из слота ",
        moved     = " перемещён в слот ",
        replaced  = " заменил предмет в слоте ",
        cleared   = "Все избранные предметы очищены.",
        need_admin = " избранное требует прав администратора",
    },
    german = {
        favorited = " in Slot ",
        removed   = " aus Slot ",
        moved     = " wurde in Slot ",
        replaced  = " ersetzte den Gegenstand in Slot ",
        cleared   = "Alle favorisierten Gegenstände entfernt.",
        need_admin = " Favoriten erfordern Server-Admin",
    },
    french = {
        favorited = " enregistré dans l'emplacement ",
        removed   = " retiré de l'emplacement ",
        moved     = " déplacé vers l'emplacement ",
        replaced  = " a remplacé l'objet dans l'emplacement ",
        cleared   = "Tous les objets favoris ont été effacés.",
        need_admin = " les favoris requièrent admin serveur",
    },
    spanish = {
        favorited = " guardado en el espacio ",
        removed   = " eliminado del espacio ",
        moved     = " movido al espacio ",
        replaced  = " reemplazó el objeto en el espacio ",
        cleared   = "Se han borrado todos los objetos favoritos.",
        need_admin = " favoritos requiere admin del servidor",
    },
    portuguese_br = {
        favorited = " favoritado no slot ",
        removed   = " removido do slot ",
        moved     = " movido para o slot ",
        replaced  = " substituiu o item no slot ",
        cleared   = "Todos os itens favoritados foram limpos.",
        need_admin = " favoritos exigem admin do servidor",
    },
    korean = {
        favorited = " 슬롯 에 즐겨찾기 됨 ",
        removed   = " 슬롯 에서 제거됨 ",
        moved     = " 슬롯 로 이동됨 ",
        replaced  = " 슬롯 의 아이템을 교체함 ",
        cleared   = "모든 즐겨찾기 아이템이 초기화되었습니다.",
        need_admin = " 즐겨찾기는 서버 관리자 권한이 필요합니다",
    },
    japanese = {
        favorited = " をスロット にお気に入り登録",
        removed   = " をスロット から削除",
        moved     = " をスロット に移動",
        replaced  = " がスロット のアイテムを置換",
        cleared   = "すべてのお気に入りアイテムを削除しました。",
        need_admin = " お気に入りにはサーバー管理者権限が必要です",
    },
    italian = {
        favorited = " salvato nello slot ",
        removed   = " rimosso dallo slot ",
        moved     = " spostato nello slot ",
        replaced  = " ha sostituito l'oggetto nello slot ",
        cleared   = "Tutti gli oggetti preferiti sono stati cancellati.",
        need_admin = " i preferiti richiedono admin server",
    },
    polish = {
        favorited = " dodano do slotu ",
        removed   = " usunięto ze slotu ",
        moved     = " przeniesiono do slotu ",
        replaced  = " zastąpił przedmiot w slocie ",
        cleared   = "Wszystkie ulubione przedmioty zostały wyczyszczone.",
        need_admin = " ulubione wymagają admina serwera",
    },
}

-- 关键: 不能一次性锁定语言。DST 在 modmain 加载阶段 defaultlang 往往还是 english,
-- 之后才设成玩家语言, 故每次取提示时实时解析。
local function GetLang()
    if GLOBAL.LanguageTranslator and GLOBAL.LanguageTranslator.defaultlang then
        return GLOBAL.LanguageTranslator.defaultlang
    end
    return "english"
end

local function GetMsg(key)
    local tbl = MESSAGES[GetLang()]
    if tbl == nil then tbl = MESSAGES.english end
    return tbl[key] or MESSAGES.english[key] or key
end

-- ---------------------------------------------------------------------------
-- 基础工具函数
-- ---------------------------------------------------------------------------
function StringSplit(s, delimiter)
    local result = {}
    if s == nil then return result end
    for match in (s .. delimiter):gmatch("(.-)" .. delimiter) do
        table.insert(result, match)
    end
    return result
end

function TableToString(tbl)
    local uniqueString = ""
    for k, v in pairs(tbl) do
        uniqueString = uniqueString .. tostring(v.item) .. "," .. tostring(v.slot) .. ";"
    end
    return uniqueString
end

function StringToTable(s)
    local result = {}
    if s == nil or s == "" then return result end
    for _, pair in ipairs(StringSplit(s, ";")) do
        if pair ~= "" then
            local parts = StringSplit(pair, ",")
            local it = parts[1]
            local sl = tonumber(parts[2])
            if it and sl then
                table.insert(result, { item = it, slot = math.floor(sl) })
            end
        end
    end
    return result
end

function SavePersistentData(name, data)
    GLOBAL.TheSim:SetPersistentString(name, TableToString(data), false)
end

function ContainsItemInTable(tbl, item)
    if tbl == nil or tbl[1] == nil then return false end
    for k, v in pairs(tbl) do
        if v.item == item then return k end
    end
    return false
end

function SlotIsBusy(tbl, slot)
    if tbl == nil or tbl[1] == nil then return false end
    for k, v in pairs(tbl) do
        if v.slot == slot then return k end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- 构建发往服务器的命令字符串
-- 注意: 该字符串在服务器上以原生 Lua 执行, 本 mod 不在服务器加载, 因此只能使用
-- DST 原生 API。逻辑与之前的服务端重组一致: 先腾空目标槽, 再放回, 杜绝 GiveItem
-- 进入被占槽位时改放他处 (GiveItem 对占用的非堆叠槽会找下一个空槽)。
-- ---------------------------------------------------------------------------
local function BuildServerCommand(userid, favorites)
    local entries = {}
    for _, v in ipairs(favorites) do
        if v.item ~= nil and v.slot ~= nil then
            entries[#entries + 1] = string.format('{item=%q,slot=%d}', v.item, v.slot)
        end
    end
    local tbl = "{" .. table.concat(entries, ",") .. "}"

    local cmd = string.format([[
local fi_userid = %q
local fi_fav = %s
local fi_p = UserToPlayer(fi_userid)
if fi_p and fi_p.components and fi_p.components.inventory then
  local fi_inv = fi_p.components.inventory
  if fi_inv:GetActiveItem() == nil then
    local function fi_find(prefab, exclude)
      for s=1,fi_inv:GetNumSlots() do
        local it = fi_inv:GetItemInSlot(s)
        if it and it.prefab == prefab and s ~= exclude then return it, s end
      end
      return nil
    end
    for _,fi_f in ipairs(fi_fav) do
      local fi_slot = fi_f.slot
      local fi_cur = fi_inv:GetItemInSlot(fi_slot)
      if not (fi_cur and fi_cur.prefab == fi_f.item) then
        local fi_found, fi_fs = fi_find(fi_f.item, fi_slot)
        if fi_found then
          fi_inv:RemoveItemBySlot(fi_fs)
          if fi_cur then
            local fi_occ = fi_inv:RemoveItemBySlot(fi_slot)
            fi_inv:GiveItem(fi_occ, fi_fs)
          end
          fi_inv:GiveItem(fi_found, fi_slot)
        end
      end
    end
  end
end
]], userid, tbl)

    return cmd
end

-- ---------------------------------------------------------------------------
-- 把收藏表发送到服务器 (客户端驱动)
--   - 远程服务器管理员 -> TheNet:SendRemoteExecute (发到服务器执行)
--   - 单机 / 主机 (客户端即服务器) -> ExecuteConsoleCommand (本地执行)
--   - 非管理员客户端 -> 提示需要权限, 无法锁位
-- ---------------------------------------------------------------------------
local function SendFavoritesToServer()
    if GLOBAL.ThePlayer == nil then return end

    local userid = tostring(GLOBAL.ThePlayer.userid or "")
    local cmd = BuildServerCommand(userid, GLOBAL.FAVORITED_ITEMS)

    local is_remote_admin = GLOBAL.TheNet:GetIsClient()
        and GLOBAL.TheNet:GetIsServerAdmin()
        and not GLOBAL.TheNet:GetIsServer()

    if is_remote_admin then
        local x, y, z = GLOBAL.TheSim:ProjectScreenPos(GLOBAL.TheSim:GetPosition())
        GLOBAL.TheNet:SendRemoteExecute(cmd, x, z)
    elseif not GLOBAL.TheNet:GetIsServer() then
        -- 客户端但非管理员: 无法驱动服务器锁位
        if GLOBAL.ThePlayer.components and GLOBAL.ThePlayer.components.talker then
            GLOBAL.ThePlayer.components.talker:Say(GetMsg("need_admin"))
        end
    else
        -- 单机 / 主机: 本地即服务器, 直接执行
        ExecuteConsoleCommand(cmd)
    end
end

-- 背包变化后防抖同步 (客户端驱动服务器重组)
local pending_sync = false
local function ScheduleServerSync()
    if GLOBAL.ThePlayer == nil then return end
    if pending_sync then return end
    pending_sync = true
    GLOBAL.ThePlayer:DoTaskInTime(0.15, function()
        pending_sync = false
        SendFavoritesToServer()
    end)
end

-- ---------------------------------------------------------------------------
-- 收藏交互 (点击槽位 + 收藏键) — 纯客户端 UI
-- ---------------------------------------------------------------------------
AddClassPostConstruct("widgets/invslot", function(invslot)
    local nClick = invslot.Click

    invslot.Click = function(invslot, stack_mod)
        local res = nClick(invslot, stack_mod)

        if GLOBAL.TheInput:IsKeyDown(GetModConfigData("FI_SWITCH_KEY"):lower():byte()) then
            if tostring(invslot.container) ~= tostring(GLOBAL.ThePlayer.replica.inventory) then
                return res
            end

            if invslot.tile and invslot.tile.item then
                local clickedSlotNumber = invslot.num
                local selectedItem = invslot.tile.item
                local prefab = selectedItem.prefab

                local existsItem = ContainsItemInTable(GLOBAL.FAVORITED_ITEMS, prefab)
                local itemInSlotBusy = SlotIsBusy(GLOBAL.FAVORITED_ITEMS, clickedSlotNumber)

                if mod_fav.HAVE_FAVORITED and existsItem ~= false then
                    if itemInSlotBusy ~= false then
                        if itemInSlotBusy == existsItem then
                            table.remove(GLOBAL.FAVORITED_ITEMS, itemInSlotBusy)
                            GLOBAL.ThePlayer.components.talker:Say(
                                tostring(selectedItem.name) .. GetMsg("removed") .. tostring(clickedSlotNumber))
                        else
                            GLOBAL.FAVORITED_ITEMS[existsItem].slot = clickedSlotNumber
                            table.remove(GLOBAL.FAVORITED_ITEMS, itemInSlotBusy)
                            GLOBAL.ThePlayer.components.talker:Say(
                                tostring(selectedItem.name) .. GetMsg("replaced") .. tostring(clickedSlotNumber))
                        end
                    else
                        GLOBAL.FAVORITED_ITEMS[existsItem].slot = clickedSlotNumber
                        GLOBAL.ThePlayer.components.talker:Say(
                            tostring(selectedItem.name) .. GetMsg("moved") .. tostring(clickedSlotNumber))
                    end
                else
                    if itemInSlotBusy ~= false then
                        GLOBAL.FAVORITED_ITEMS[itemInSlotBusy].item = prefab
                        GLOBAL.ThePlayer.components.talker:Say(
                            tostring(selectedItem.name) .. GetMsg("replaced") .. tostring(clickedSlotNumber))
                    else
                        table.insert(GLOBAL.FAVORITED_ITEMS, { item = prefab, slot = clickedSlotNumber })
                        GLOBAL.ThePlayer.components.talker:Say(
                            tostring(selectedItem.name) .. GetMsg("favorited") .. tostring(clickedSlotNumber))
                    end
                end

                mod_fav.HAVE_FAVORITED = true
                GLOBAL.SHOWTABLE = TableToString(GLOBAL.FAVORITED_ITEMS)
                SavePersistentData(GLOBAL.FAVITSAVE, GLOBAL.FAVORITED_ITEMS)

                -- 立即把收藏布局发往服务器锁位
                SendFavoritesToServer()
            end
        end

        return res
    end
end)

-- ---------------------------------------------------------------------------
-- 玩家初始化 (仅客户端): 读取本地收藏存档 + 监听背包副本变化以驱动服务器重组
-- ---------------------------------------------------------------------------
AddPlayerPostInit(function(inst)
    local function onInventoryEvent(inst, data)
        if mod_fav.HAVE_FAVORITED and #GLOBAL.FAVORITED_ITEMS > 0 then
            ScheduleServerSync()
        end
    end

    inst:ListenForEvent("itemget", onInventoryEvent)
    inst:ListenForEvent("itemlose", onInventoryEvent)
    inst:ListenForEvent("gotnewitem", onInventoryEvent)
    inst:ListenForEvent("dropitem", onInventoryEvent)
    inst:ListenForEvent("equip", onInventoryEvent)
    inst:ListenForEvent("unequip", onInventoryEvent)
    inst:ListenForEvent("newactiveitem", onInventoryEvent)

    GLOBAL.TheSim:GetPersistentString(GLOBAL.FAVITSAVE,
        function(load_success, str)
            if load_success then
                local sTable = StringToTable(str)
                if #sTable > 0 then
                    GLOBAL.FAVORITED_ITEMS = sTable
                    mod_fav.HAVE_FAVORITED = true
                    SendFavoritesToServer()
                end
            end
        end)
end)

-- ---------------------------------------------------------------------------
-- 清除所有收藏: CTRL + SHIFT + Z
-- ---------------------------------------------------------------------------
if GLOBAL.TheInput ~= nil then
    GLOBAL.TheInput:AddKeyDownHandler(GLOBAL.KEY_Z, function()
        if GLOBAL.TheInput:IsKeyDown(GLOBAL.KEY_CTRL) and GLOBAL.TheInput:IsKeyDown(GLOBAL.KEY_SHIFT) then
            mod_fav.HAVE_FAVORITED = false
            GLOBAL.FAVORITED_ITEMS = {}

            GLOBAL.TheSim:ErasePersistentString(GLOBAL.FAVITSAVE)

            SendFavoritesToServer()

            if GLOBAL.ThePlayer and GLOBAL.ThePlayer.components and GLOBAL.ThePlayer.components.talker then
                GLOBAL.ThePlayer.components.talker:Say(GetMsg("cleared"))
            end
        end
    end)
end
