--[[
    收藏物品 / Favorite Items
    版本: 2.0.0
    架构: 服务器 mod (client_only_mod = false)
      - 客户端 (TheNet:GetIsClient()): 捕获按键、维护收藏表、本地存档、按玩家语言显示提示、
        通过 Mod RPC 把收藏表发给服务器 (SendModRPCToServer)。
      - 服务器 (TheWorld.ismastersim): 收到 RPC 后, 由服务器权威地把物品锁回指定槽位
        (inventory 组件), 并监听背包变化持续校准。无需管理员权限 (RPC 由玩家本人发出, 自带身份)。
    多语言:
      - 提示在客户端用 talker:Say 显示, 实时取 LanguageTranslator.defaultlang (与 TMIR 同款做法),
        因此必定与玩家游戏语言一致。
      - 之前纯客户端版里仍显示英文, 是因为 Steam 工坊把你本地改动的 workshop 文件夹同步回最早
        发布的旧版 (旧版在加载时就锁死成英文)。本版建议作为本地 mod 运行 (见说明), 或重新上传到
        工坊, 以免被覆盖。
    修复历史:
      - 1.3.0 纯客户端 mod: 用 SendRemoteExecute 发命令 (要求管理员), 且依赖 workshop 文件夹易被覆盖。
      - 2.0.0 回到服务器 mod: 用 Mod RPC 通信, 普通玩家即可锁位, 不再需要管理员; 提示在客户端显示, 语言随玩家。
]]

GLOBAL.MOD_FAVORITE_ITEM = {}
local mod_fav = GLOBAL.MOD_FAVORITE_ITEM

-- 捕获标准库 (DST mod env 未注入 tonumber/next 等)
local tonumber = GLOBAL.tonumber
local tostring = GLOBAL.tostring
local math     = GLOBAL.math
local table    = GLOBAL.table
local string   = GLOBAL.string
local pairs    = GLOBAL.pairs
local ipairs   = GLOBAL.ipairs
local type     = GLOBAL.type

local MOD_RPC = "FAVORITE_ITEMS"

-- 跨端共享的运行时表 (服务器用; 客户端不触碰)
mod_fav.favs = mod_fav.favs or {}
mod_fav._pending = mod_fav._pending or {}

-- ---------------------------------------------------------------------------
-- 多语言提示语
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

local function GetMsg(key)
    local tbl = MESSAGES[GetLang()]
    if tbl == nil then tbl = MESSAGES.english end
    return tbl[key] or MESSAGES.english[key] or key
end

-- ---------------------------------------------------------------------------
-- 工具函数
-- ---------------------------------------------------------------------------
local function StringSplit(s, delimiter)
    local result = {}
    if s == nil then return result end
    for match in (s .. delimiter):gmatch("(.-)" .. delimiter) do
        table.insert(result, match)
    end
    return result
end

local function TableToString(tbl)
    local s = ""
    for k, v in pairs(tbl) do
        s = s .. tostring(v.item) .. "," .. tostring(v.slot) .. ";"
    end
    return s
end

local function StringToTable(s)
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

local function ContainsItemInTable(tbl, item)
    if tbl == nil or tbl[1] == nil then return false end
    for k, v in pairs(tbl) do
        if v.item == item then return k end
    end
    return false
end

local function SlotIsBusy(tbl, slot)
    if tbl == nil or tbl[1] == nil then return false end
    for k, v in pairs(tbl) do
        if v.slot == slot then return k end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- 服务器权威重组
-- ---------------------------------------------------------------------------
local function Reorganize(player, favorites)
    if player == nil or player.components == nil or player.components.inventory == nil then return end
    local inv = player.components.inventory
    if inv:GetActiveItem() ~= nil then return end  -- 手上有东西时不打扰

    for _, f in ipairs(favorites) do
        local slot = f.slot
        if type(slot) ~= "number" then slot = tonumber(slot) end
        if slot and slot >= 1 and slot <= inv:GetNumSlots() then
            local cur = inv:GetItemInSlot(slot)
            if not (cur and cur.prefab == f.item) then
                local found, fs = nil, nil
                for s = 1, inv:GetNumSlots() do
                    local it = inv:GetItemInSlot(s)
                    if it and it.prefab == f.item and s ~= slot then
                        found, fs = it, s
                        break
                    end
                end
                if found then
                    inv:RemoveItemBySlot(fs)
                    local occ = inv:RemoveItemBySlot(slot)
                    if occ then inv:GiveItem(occ, fs) end
                    inv:GiveItem(found, slot)
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Mod RPC 注册 (必须在顶层, 客户端/服务器都要注册 id 才能收发)
--   处理函数只在服务器真正执行; 客户端注册后仅用于取 id, 不会被调用。
-- ---------------------------------------------------------------------------
AddModRPCHandler(MOD_RPC, "SetFavorites", function(player, data)
    if player == nil or player.userid == nil then return end
    local tbl = StringToTable(data)
    mod_fav.favs[player.userid] = tbl
    Reorganize(player, tbl)
end)

AddModRPCHandler(MOD_RPC, "ClearFavorites", function(player)
    if player == nil or player.userid == nil then return end
    mod_fav.favs[player.userid] = {}
end)

-- ---------------------------------------------------------------------------
-- 服务器部分 (权威重组 + 背包变化校准)
-- ---------------------------------------------------------------------------
if GLOBAL.TheWorld and GLOBAL.TheWorld.ismastersim then
    AddPlayerPostInit(function(inst)
        if inst:HasTag("player") then
            local function onInv()
                if inst.userid == nil then return end
                if mod_fav._pending[inst.userid] then return end
                mod_fav._pending[inst.userid] = true
                inst:DoTaskInTime(0.2, function()
                    mod_fav._pending[inst.userid] = nil
                    local favs = mod_fav.favs[inst.userid]
                    if favs and #favs > 0 then
                        Reorganize(inst, favs)
                    end
                end)
            end
            inst:ListenForEvent("itemget", onInv)
            inst:ListenForEvent("itemlose", onInv)
            inst:ListenForEvent("gotnewitem", onInv)
            inst:ListenForEvent("dropitem", onInv)
            inst:ListenForEvent("equip", onInv)
            inst:ListenForEvent("unequip", onInv)
            inst:ListenForEvent("newactiveitem", onInv)
        end
    end)
end

-- ---------------------------------------------------------------------------
-- 客户端部分 (含主机: 主机既是客户端也是服务器)
--   负责: 输入捕获 / 收藏表维护 / 本地存档 / 按玩家语言显示提示 / 发 RPC 给服务器
-- ---------------------------------------------------------------------------
if GLOBAL.TheNet:GetIsClient() then
    local FAVORITED_ITEMS = {}
    local HAVE_FAVORITED = false
    local FAVITSAVE = "FAVORITEITEMS"

    local function SendFavorites()
        if GLOBAL.ThePlayer == nil then return end
        SendModRPCToServer(GetModRPC(MOD_RPC, "SetFavorites"), TableToString(FAVORITED_ITEMS))
    end

    local function SendClear()
        SendModRPCToServer(GetModRPC(MOD_RPC, "ClearFavorites"))
    end

    -- 读取本地收藏存档
    GLOBAL.TheSim:GetPersistentString(FAVITSAVE, function(success, str)
        if success then
            FAVORITED_ITEMS = StringToTable(str)
            if #FAVORITED_ITEMS > 0 then
                HAVE_FAVORITED = true
                SendFavorites()
            end
        end
    end)

    AddClassPostConstruct("widgets/invslot", function(invslot)
        local oldClick = invslot.Click
        invslot.Click = function(invslot, stack_mod)
            local res = oldClick(invslot, stack_mod)

            if GLOBAL.TheInput:IsKeyDown(GetModConfigData("FI_SWITCH_KEY"):lower():byte()) then
                if tostring(invslot.container) ~= tostring(GLOBAL.ThePlayer.replica.inventory) then
                    return res
                end

                if invslot.tile and invslot.tile.item then
                    local clickedSlotNumber = invslot.num
                    local selectedItem = invslot.tile.item
                    local prefab = selectedItem.prefab

                    local existsItem = ContainsItemInTable(FAVORITED_ITEMS, prefab)
                    local itemInSlotBusy = SlotIsBusy(FAVORITED_ITEMS, clickedSlotNumber)

                    if HAVE_FAVORITED and existsItem ~= false then
                        if itemInSlotBusy ~= false then
                            if itemInSlotBusy == existsItem then
                                table.remove(FAVORITED_ITEMS, itemInSlotBusy)
                                GLOBAL.ThePlayer.components.talker:Say(
                                    tostring(selectedItem.name) .. GetMsg("removed") .. tostring(clickedSlotNumber))
                            else
                                FAVORITED_ITEMS[existsItem].slot = clickedSlotNumber
                                table.remove(FAVORITED_ITEMS, itemInSlotBusy)
                                GLOBAL.ThePlayer.components.talker:Say(
                                    tostring(selectedItem.name) .. GetMsg("replaced") .. tostring(clickedSlotNumber))
                            end
                        else
                            FAVORITED_ITEMS[existsItem].slot = clickedSlotNumber
                            GLOBAL.ThePlayer.components.talker:Say(
                                tostring(selectedItem.name) .. GetMsg("moved") .. tostring(clickedSlotNumber))
                        end
                    else
                        if itemInSlotBusy ~= false then
                            FAVORITED_ITEMS[itemInSlotBusy].item = prefab
                            GLOBAL.ThePlayer.components.talker:Say(
                                tostring(selectedItem.name) .. GetMsg("replaced") .. tostring(clickedSlotNumber))
                        else
                            table.insert(FAVORITED_ITEMS, { item = prefab, slot = clickedSlotNumber })
                            GLOBAL.ThePlayer.components.talker:Say(
                                tostring(selectedItem.name) .. GetMsg("favorited") .. tostring(clickedSlotNumber))
                        end
                    end

                    HAVE_FAVORITED = true
                    GLOBAL.TheSim:SetPersistentString(FAVITSAVE, TableToString(FAVORITED_ITEMS), false)
                    SendFavorites()
                end
            end

            return res
        end
    end)

    if GLOBAL.TheInput ~= nil then
        GLOBAL.TheInput:AddKeyDownHandler(GLOBAL.KEY_Z, function()
            if GLOBAL.TheInput:IsKeyDown(GLOBAL.KEY_CTRL) and GLOBAL.TheInput:IsKeyDown(GLOBAL.KEY_SHIFT) then
                HAVE_FAVORITED = false
                FAVORITED_ITEMS = {}
                GLOBAL.TheSim:ErasePersistentString(FAVITSAVE)
                SendClear()
                if GLOBAL.ThePlayer and GLOBAL.ThePlayer.components and GLOBAL.ThePlayer.components.talker then
                    GLOBAL.ThePlayer.components.talker:Say(GetMsg("cleared"))
                end
            end
        end)
    end
end
