--[[
    收藏物品 / Favorite Items
    版本: 1.2.0
    修复说明:
      - 修复换槽位复制/崩溃: 重入锁 + 实例级去重, 杜绝同一物品被多次 GiveItem 而复制。
      - 修复 "记录了但不锁定" (专用服务器场景): 改为服务器权威架构。
        客户端点收藏时, 把完整收藏表通过 RPC 同步给服务器; 服务器持有自己的收藏表,
        并在自身背包事件上主动把物品锁回槽位 (服务器是权威端, 移动会同步回客户端)。
      - 单机/主机: 客户端即服务器, 直接生效。
      - 仅在背包静止态 (未手持 activeitem) 执行重组, 避免拖拽中途介入。
      - 修掉专用服务器上 ThePlayer / TheInput 为 nil 的崩溃。
]]

GLOBAL.MOD_FAVORITE_ITEM = {}

GLOBAL.MOD_FAVORITE_ITEM.INVENTORY_UPDATE_TIME = GLOBAL.tonumber(GetModConfigData("INVENTORY_UPDATE_TIME")) or 0.2
GLOBAL.MOD_FAVORITE_ITEM.HAVE_FAVORITED = GLOBAL.MOD_FAVORITE_ITEM.HAVE_FAVORITED or false
GLOBAL.FAVORITED_ITEMS = {}

GLOBAL.FAVITSAVE = "FAVORITEITEMS"
GLOBAL.SHOWTABLE = ""

local mod_fav = GLOBAL.MOD_FAVORITE_ITEM

-- ---------------------------------------------------------------------------
-- 多语言提示语 (in-game talker)
-- 依据 LanguageTranslator.defaultlang 选择, 默认 english
-- ---------------------------------------------------------------------------
local MESSAGES = {
    english = {
        favorited = " favorited to slot ",
        removed   = " removed from slot ",
        moved     = " moved to slot ",
        replaced  = " replaced the item in slot ",
        cleared   = "All favorited items cleared.",
    },
    schinese = {
        favorited = " 已收藏到槽位 ",
        removed   = " 已从槽位 ",
        moved     = " 被移动到槽位 ",
        replaced  = " 替换了槽位 ",
        cleared   = "已清除所有收藏物品。",
    },
    tchinese = {
        favorited = " 已收藏到欄位 ",
        removed   = " 已從欄位 ",
        moved     = " 被移動到欄位 ",
        replaced  = " 替換了欄位 ",
        cleared   = "已清除所有收藏物品。",
    },
    russian = {
        favorited = " добавлен в слот ",
        removed   = " удалён из слота ",
        moved     = " перемещён в слот ",
        replaced  = " заменил предмет в слоте ",
        cleared   = "Все избранные предметы очищены.",
    },
    german = {
        favorited = " in Slot ",
        removed   = " aus Slot ",
        moved     = " wurde in Slot ",
        replaced  = " ersetzte den Gegenstand in Slot ",
        cleared   = "Alle favorisierten Gegenstände entfernt.",
    },
    french = {
        favorited = " enregistré dans l'emplacement ",
        removed   = " retiré de l'emplacement ",
        moved     = " déplacé vers l'emplacement ",
        replaced  = " a remplacé l'objet dans l'emplacement ",
        cleared   = "Tous les objets favoris ont été effacés.",
    },
    spanish = {
        favorited = " guardado en el espacio ",
        removed   = " eliminado del espacio ",
        moved     = " movido al espacio ",
        replaced  = " reemplazó el objeto en el espacio ",
        cleared   = "Se han borrado todos los objetos favoritos.",
    },
    portuguese_br = {
        favorited = " favoritado no slot ",
        removed   = " removido do slot ",
        moved     = " movido para o slot ",
        replaced  = " substituiu o item no slot ",
        cleared   = "Todos os itens favoritados foram limpos.",
    },
    korean = {
        favorited = " 슬롯 에 즐겨찾기 됨 ",
        removed   = " 슬롯 에서 제거됨 ",
        moved     = " 슬롯 로 이동됨 ",
        replaced  = " 슬롯 의 아이템을 교체함 ",
        cleared   = "모든 즐겨찾기 아이템이 초기화되었습니다.",
    },
    japanese = {
        favorited = " をスロット にお気に入り登録",
        removed   = " をスロット から削除",
        moved     = " をスロット に移動",
        replaced  = " がスロット のアイテムを置換",
        cleared   = "すべてのお気に入りアイテムを削除しました。",
    },
    italian = {
        favorited = " salvato nello slot ",
        removed   = " rimosso dallo slot ",
        moved     = " spostato nello slot ",
        replaced  = " ha sostituito l'oggetto nello slot ",
        cleared   = "Tutti gli oggetti preferiti sono stati cancellati.",
    },
    polish = {
        favorited = " dodano do slotu ",
        removed   = " usunięto ze slotu ",
        moved     = " przeniesiono do slotu ",
        replaced  = " zastąpił przedmiot w slocie ",
        cleared   = "Wszystkie ulubione przedmioty zostały wyczyszczone.",
    },
}

local function GetLang()
    if GLOBAL.LanguageTranslator and GLOBAL.LanguageTranslator.defaultlang then
        return GLOBAL.LanguageTranslator.defaultlang
    end
    return "english"
end

local M = MESSAGES[GetLang()] or MESSAGES.english

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

-- 仅在背包静止态 (未手持) 时执行; 由调用方保证
local function PlaceFavoriteInSlot(inventory, prefab, slot)
    if inventory == nil then return end
    if inventory.activeitem ~= nil then return end

    local current = inventory:GetItemInSlot(slot)
    if current ~= nil and current.prefab == prefab then
        return -- 已经在正确位置
    end

    local found = inventory:FindItem(function(i)
        return i.prefab == prefab and inventory:GetItemSlot(i) ~= slot
    end)
    if found == nil then return end

    local fromSlot = inventory:GetItemSlot(found)
    if fromSlot == nil or fromSlot == slot then return end

    local occupant = inventory:GetItemInSlot(slot)

    -- 先把目标物品从原槽位取出, 避免 GiveItem 时重复计入
    inventory:RemoveItemBySlot(fromSlot)

    if occupant ~= nil then
        -- 目标槽位被占: 先把占位取出, 放回目标物品原来的槽位
        inventory:RemoveItemBySlot(slot)
        inventory:GiveItem(occupant, fromSlot)
    end

    inventory:GiveItem(found, slot)
end

-- ---------------------------------------------------------------------------
-- 重组 (服务器权威端 / 主机): 把每个收藏物品锁回其槽位
-- 重入锁保护, 杜绝重入导致的重复 GiveItem / 复制
-- ---------------------------------------------------------------------------
local isReconciling = false

local function Reconcile(player)
    if isReconciling then return end

    local inventory = player and player.components and player.components.inventory
    if inventory == nil then return end
    if inventory.activeitem ~= nil then return end -- 正在拖拽, 等待释放

    local favorites = GLOBAL.FAVORITED_ITEMS
    if favorites == nil or #favorites == 0 then return end

    isReconciling = true
    for _, v in pairs(favorites) do
        if v.item ~= nil and v.slot ~= nil then
            PlaceFavoriteInSlot(inventory, v.item, v.slot)
        end
    end
    isReconciling = false
end

-- ---------------------------------------------------------------------------
-- 事件合并: 任意背包事件 -> 下一帧统一重组 (服务器/主机执行权威移动)
-- 专用服务器客户端不在此处移动 (客户端背包是副本, 移动无效), 由服务器完成。
-- ---------------------------------------------------------------------------
local pending = {}

local function ScheduleReconcile(player)
    if player == nil or player.components == nil or player.components.inventory == nil then return end
    if pending[player] then return end
    pending[player] = true

    player:DoTaskInTime(0, function()
        pending[player] = false

        if not GLOBAL.TheNet:GetIsServer() then
            -- 专用服务器客户端: 不本地移动 (副本), 服务器权威端会处理
            return
        end

        if player.components.inventory.activeitem ~= nil then
            ScheduleReconcile(player) -- 等玩家放下手中物品再处理
            return
        end

        if mod_fav.HAVE_FAVORITED and #GLOBAL.FAVORITED_ITEMS > 0 then
            Reconcile(player)
        end
    end)
end

-- 立即把收藏表同步给服务器 (专用服务器客户端点击收藏时调用)
local function SyncFavoritesToServer()
    if GLOBAL.TheNet:GetIsServer() then return end -- 主机无需同步
    local data = TableToString(GLOBAL.FAVORITED_ITEMS)
    GLOBAL.SendModRPCToServer(GLOBAL.MOD_RPC[modname]["fiSync"], data)
end

-- ---------------------------------------------------------------------------
-- 收藏交互 (点击槽位 + 收藏键)
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
                                tostring(selectedItem.name) .. M.removed .. tostring(clickedSlotNumber))
                        else
                            GLOBAL.FAVORITED_ITEMS[existsItem].slot = clickedSlotNumber
                            table.remove(GLOBAL.FAVORITED_ITEMS, itemInSlotBusy)
                            GLOBAL.ThePlayer.components.talker:Say(
                                tostring(selectedItem.name) .. M.replaced .. tostring(clickedSlotNumber))
                        end
                    else
                        GLOBAL.FAVORITED_ITEMS[existsItem].slot = clickedSlotNumber
                        GLOBAL.ThePlayer.components.talker:Say(
                            tostring(selectedItem.name) .. M.moved .. tostring(clickedSlotNumber))
                    end
                else
                    if itemInSlotBusy ~= false then
                        GLOBAL.FAVORITED_ITEMS[itemInSlotBusy].item = prefab
                        GLOBAL.ThePlayer.components.talker:Say(
                            tostring(selectedItem.name) .. M.replaced .. tostring(clickedSlotNumber))
                    else
                        table.insert(GLOBAL.FAVORITED_ITEMS, { item = prefab, slot = clickedSlotNumber })
                        GLOBAL.ThePlayer.components.talker:Say(
                            tostring(selectedItem.name) .. M.favorited .. tostring(clickedSlotNumber))
                    end
                end

                mod_fav.HAVE_FAVORITED = true
                GLOBAL.SHOWTABLE = TableToString(GLOBAL.FAVORITED_ITEMS)
                SavePersistentData(GLOBAL.FAVITSAVE, GLOBAL.FAVORITED_ITEMS)

                if GLOBAL.TheNet:GetIsServer() then
                    -- 主机: 直接重组, 立即生效
                    ScheduleReconcile(GLOBAL.ThePlayer)
                else
                    -- 专用服务器客户端: 同步给服务器, 由服务器锁回
                    SyncFavoritesToServer()
                end
            end
        end

        return res
    end
end)

-- ---------------------------------------------------------------------------
-- RPC: 服务器接收客户端同步的收藏表, 更新权威收藏表并立即锁回
-- ---------------------------------------------------------------------------
AddModRPCHandler(modname, "fiSync", function(player, data)
    local inventory = player and player.components and player.components.inventory
    if inventory == nil then return end

    GLOBAL.FAVORITED_ITEMS = StringToTable(data)
    mod_fav.HAVE_FAVORITED = (#GLOBAL.FAVORITED_ITEMS > 0)
    SavePersistentData(GLOBAL.FAVITSAVE, GLOBAL.FAVORITED_ITEMS)

    -- 立即锁回 (静止态才执行)
    if inventory.activeitem == nil then
        Reconcile(player)
    end
end)

-- ---------------------------------------------------------------------------
-- 玩家初始化: 监听背包事件 + 读取本地收藏存档
-- ---------------------------------------------------------------------------
AddPlayerPostInit(function(inst)
    local function onInventoryEvent(inst, data)
        ScheduleReconcile(inst)
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
                end
            end
        end)
end)

-- ---------------------------------------------------------------------------
-- 清除所有收藏: CTRL + SHIFT + Z
-- (专用服务器上 TheInput 可能为 nil, 加守卫避免加载报错)
-- ---------------------------------------------------------------------------
if GLOBAL.TheInput ~= nil then
    GLOBAL.TheInput:AddKeyDownHandler(GLOBAL.KEY_Z, function()
        if GLOBAL.TheInput:IsKeyDown(GLOBAL.KEY_CTRL) and GLOBAL.TheInput:IsKeyDown(GLOBAL.KEY_SHIFT) then
            mod_fav.HAVE_FAVORITED = false
            GLOBAL.FAVORITED_ITEMS = {}

            GLOBAL.TheSim:ErasePersistentString(GLOBAL.FAVITSAVE)

            -- 专用服务器: 同步清空给服务器
            if not GLOBAL.TheNet:GetIsServer() then
                GLOBAL.SendModRPCToServer(GLOBAL.MOD_RPC[modname]["fiSync"], "")
            end

            if GLOBAL.ThePlayer and GLOBAL.ThePlayer.components and GLOBAL.ThePlayer.components.talker then
                GLOBAL.ThePlayer.components.talker:Say(M.cleared)
            end
        end
    end)
end
