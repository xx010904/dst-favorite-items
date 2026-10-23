--[[
    收藏物品 / Favorite Items
    版本: 1.1.0
    修复说明:
      - 将原 "每次背包事件都同步遍历所有收藏项并强制移动" 的逻辑, 改为:
        事件合并 -> 每帧最多一次延迟重组 (DoTaskInTime(0)) + 重入锁,
        从根本上消除重入导致的同一物品被多次 GiveItem 而复制/崩溃的问题。
      - 仅在背包处于静止态 (未手持 activeitem) 时执行重组, 避免拖拽中途介入。
      - 按物品实例匹配, 同一物品在一次重组内只移动一次, 杜绝 "占位" 复制。
      - 修掉专用服务器上 ThePlayer 为 nil 的崩溃: 重组作用在事件所属玩家实体上。
]]

GLOBAL.MOD_FAVORITE_ITEM = GLOBAL.MOD_FAVORITE_ITEM or {}

GLOBAL.MOD_FAVORITE_ITEM.INVENTORY_UPDATE_TIME = GLOBAL.tonumber(GetModConfigData("INVENTORY_UPDATE_TIME")) or 0.2
GLOBAL.MOD_FAVORITE_ITEM.HAVE_FAVORITED = GLOBAL.MOD_FAVORITE_ITEM.HAVE_FAVORITED or false
GLOBAL.FAVORITED_ITEMS = GLOBAL.FAVORITED_ITEMS or {}

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

-- ---------------------------------------------------------------------------
-- 稳定的单物品移动 (用于 RPC: 专用服务器按客户端指令移动具体物品)
-- 只在物品当前不在目标槽位时才移动, 且使用重入锁, 避免重复 GiveItem
-- ---------------------------------------------------------------------------
local isMoving = false

local function MoveItemToSlot(inventory, item_prefab, slot)
    if inventory == nil or inventory.activeitem ~= nil then return end
    if item_prefab == nil or slot == nil then return end

    local current = inventory:GetItemInSlot(slot)
    if current ~= nil and current.prefab == item_prefab then
        return -- 已在正确位置
    end

    local found = inventory:FindItem(function(i)
        return i.prefab == item_prefab and inventory:GetItemSlot(i) ~= slot
    end)
    if found == nil then return end

    local fromSlot = inventory:GetItemSlot(found)
    if fromSlot == nil or fromSlot == slot then return end

    local occupant = inventory:GetItemInSlot(slot)

    isMoving = true
    inventory:RemoveItemBySlot(fromSlot)
    if occupant ~= nil then
        inventory:RemoveItemBySlot(slot)
    end
    inventory:GiveItem(found, slot)
    if occupant ~= nil then
        inventory:GiveItem(occupant, fromSlot)
    end
    isMoving = false
end

-- ---------------------------------------------------------------------------
-- 本地权威重组 (单机 / 主机): 每帧最多一次, 重入锁保护
-- 按物品实例匹配, 一次重组内每个物品只移动一次, 杜绝复制
-- ---------------------------------------------------------------------------
local isReconciling = false
local pendingReconcile = false

local function Reconcile(player)
    if isReconciling then return end

    local inventory = player and player.components and player.components.inventory
    if inventory == nil then return end
    if inventory.activeitem ~= nil then return end -- 正在拖拽, 等待释放

    local favorites = GLOBAL.FAVORITED_ITEMS
    if favorites == nil or #favorites == 0 then return end

    isReconciling = true

    local used = {} -- 本帧已处理的物品实例, 防止重复移动
    for _, v in pairs(favorites) do
        local itemPrefab = v.item
        local slot = v.slot
        if itemPrefab ~= nil and slot ~= nil then
            local current = inventory:GetItemInSlot(slot)
            if current == nil or current.prefab ~= itemPrefab then
                local found = inventory:FindItem(function(i)
                    return i.prefab == itemPrefab
                        and inventory:GetItemSlot(i) ~= slot
                        and not used[i]
                end)
                if found ~= nil then
                    used[found] = true
                    local fromSlot = inventory:GetItemSlot(found)
                    if fromSlot ~= nil and fromSlot ~= slot then
                        local occupant = inventory:GetItemInSlot(slot)
                        inventory:RemoveItemBySlot(fromSlot)
                        if occupant ~= nil then
                            inventory:RemoveItemBySlot(slot)
                        end
                        inventory:GiveItem(found, slot)
                        if occupant ~= nil then
                            used[occupant] = true
                            inventory:GiveItem(occupant, fromSlot)
                        end
                    end
                end
            end
        end
    end

    isReconciling = false
end

-- ---------------------------------------------------------------------------
-- 事件合并: 任意背包事件 -> 延迟到下一帧统一重组 (客户端则通知服务器)
-- ---------------------------------------------------------------------------
local function ScheduleReconcile(player)
    if player == nil or player.components == nil or player.components.inventory == nil then return end
    if pendingReconcile then return end
    pendingReconcile = true

    player:DoTaskInTime(0, function()
        pendingReconcile = false

        if isReconciling then
            ScheduleReconcile(player)
            return
        end
        if player.components.inventory.activeitem ~= nil then
            ScheduleReconcile(player) -- 等玩家放下手中物品再处理
            return
        end

        if GLOBAL.TheNet:GetIsServer() then
            -- 单机 / 主机: 本地权威重组
            if mod_fav.HAVE_FAVORITED then
                Reconcile(player)
            end
        else
            -- 客户端连接专用服务器: 把收藏指令发给服务器
            if mod_fav.HAVE_FAVORITED then
                for k, v in pairs(GLOBAL.FAVORITED_ITEMS) do
                    SendModRPCToServer(MOD_RPC[modname]["fiRemoteTask"], v.item, v.slot)
                end
            end
        end
    end)
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
            end
        end

        return res
    end
end)

-- ---------------------------------------------------------------------------
-- RPC: 服务器按客户端指令把具体物品放回目标槽位
-- ---------------------------------------------------------------------------
AddModRPCHandler(modname, "fiRemoteTask", function(player, item, slot)
    local inventory = player and player.components and player.components.inventory
    if inventory == nil then return end
    MoveItemToSlot(inventory, item, slot)
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
-- ---------------------------------------------------------------------------
GLOBAL.TheInput:AddKeyDownHandler(GLOBAL.KEY_Z, function()
    if GLOBAL.TheInput:IsKeyDown(GLOBAL.KEY_CTRL) and GLOBAL.TheInput:IsKeyDown(GLOBAL.KEY_SHIFT) then
        mod_fav.HAVE_FAVORITED = false
        GLOBAL.FAVORITED_ITEMS = {}

        GLOBAL.TheSim:ErasePersistentString(GLOBAL.FAVITSAVE)

        if GLOBAL.ThePlayer and GLOBAL.ThePlayer.components and GLOBAL.ThePlayer.components.talker then
            GLOBAL.ThePlayer.components.talker:Say(M.cleared)
        end
    end
end)
