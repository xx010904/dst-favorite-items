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
        removed_suffix = "",
        cleared   = "All favorited items cleared.",
    },
    schinese = {
        favorited = " 已收藏到槽位 ",
        removed   = " 已从槽位 ",
        moved     = " 被移动到槽位 ",
        replaced  = " 替换了槽位 ",
        removed_suffix = " 移除",
        cleared   = "已清除所有收藏物品。",
    },
    tchinese = {
        favorited = " 已收藏到欄位 ",
        removed   = " 已從欄位 ",
        moved     = " 被移動到欄位 ",
        replaced  = " 替換了欄位 ",
        removed_suffix = " 移除",
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

local SHORTCUT_MESSAGES = {
    english = { hidden = "Favorite stars hidden. Press %s again to show them.", shown = "Favorite stars shown.", choose_slot = "Choose a slot to lock %s to." },
    schinese = { hidden = "星星已隐藏，再按 %s 显示。", shown = "星星已显示。", choose_slot = "选择一个槽位来锁定%s。" },
    tchinese = { hidden = "星星已隱藏，再按 %s 顯示。", shown = "星星已顯示。", choose_slot = "選擇一個欄位來鎖定%s。" },
    russian = { hidden = "Звёзды избранного скрыты. Нажмите %s ещё раз, чтобы показать их.", shown = "Звёзды избранного показаны.", choose_slot = "Выберите слот для закрепления предмета «%s»." },
    german = { hidden = "Favoritensterne ausgeblendet. Drücke %s erneut, um sie anzuzeigen.", shown = "Favoritensterne angezeigt.", choose_slot = "Wähle einen Platz für %s." },
    french = { hidden = "Étoiles masquées. Appuyez encore sur %s pour les afficher.", shown = "Étoiles affichées.", choose_slot = "Choisissez un emplacement pour verrouiller %s." },
    spanish = { hidden = "Estrellas ocultas. Pulsa %s otra vez para mostrarlas.", shown = "Estrellas visibles.", choose_slot = "Elige una casilla para fijar %s." },
    portuguese_br = { hidden = "Estrelas ocultas. Pressione %s novamente para mostrá-las.", shown = "Estrelas visíveis.", choose_slot = "Escolha um espaço para fixar %s." },
    korean = { hidden = "즐겨찾기 별표를 숨겼습니다. 다시 보려면 %s 키를 누르세요.", shown = "즐겨찾기 별표를 표시했습니다.", choose_slot = "%s을(를) 고정할 슬롯을 선택하세요." },
    japanese = { hidden = "お気に入りの星を隠しました。もう一度 %s を押すと表示します。", shown = "お気に入りの星を表示しました。", choose_slot = "%sを固定するスロットを選んでください。" },
    italian = { hidden = "Stelle nascoste. Premi di nuovo %s per mostrarle.", shown = "Stelle visibili.", choose_slot = "Scegli uno slot in cui bloccare %s." },
    polish = { hidden = "Gwiazdki ukryte. Naciśnij ponownie %s, aby je pokazać.", shown = "Gwiazdki widoczne.", choose_slot = "Wybierz miejsce do przypięcia przedmiotu %s." },
}

local LANGUAGE_BY_LOCALE = {
    en = "english",
    fr = "french",
    es = "spanish",
    mex = "spanish",
    de = "german",
    it = "italian",
    pt = "portuguese_br",
    pt_br = "portuguese_br",
    ["pt-br"] = "portuguese_br",
    pl = "polish",
    ru = "russian",
    ko = "korean",
    zh = "schinese",
    zhr = "schinese",
    zht = "tchinese",
    ja = "japanese",
}

local function GetLang()
    if GLOBAL.LanguageTranslator and GLOBAL.LanguageTranslator.defaultlang then
        local lang = string.lower(GLOBAL.LanguageTranslator.defaultlang)
        return LANGUAGE_BY_LOCALE[lang] or lang
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
    if player == nil or player.components == nil or player.components.inventory == nil then return true end
    local inv = player.components.inventory
    if inv:GetActiveItem() ~= nil then return false end -- retry after the active item is placed

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
    return true
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
                local userid = inst.userid
                if mod_fav._pending[userid] then return end
                mod_fav._pending[userid] = true

                local function reconcile(retries_left)
                    local favs = mod_fav.favs[userid]
                    if favs and #favs > 0 and not Reorganize(inst, favs) and retries_left > 0 then
                        inst:DoTaskInTime(0.2, function()
                            reconcile(retries_left - 1)
                        end)
                        return
                    end
                    mod_fav._pending[userid] = nil
                end

                inst:DoTaskInTime(0.2, function()
                    reconcile(10)
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
    local ImageButton = require("widgets/imagebutton")
    local Text = require("widgets/text")
    local FAVORITE_MARKER_FONT = GLOBAL.NEWFONT_OUTLINE or "spirequal_outline"
    local FAVORITE_KEY = GetModConfigData("FI_SWITCH_KEY"):lower():byte()
    local FAVORITED_ITEMS = {}
    local HAVE_FAVORITED = false
    local FAVITSAVE = "FAVORITEITEMS"
    local FAVORITE_SLOT_WIDGETS = {}
    local HOVERED_PLAYER_SLOT = nil
    local STAR_MARKERS_VISIBLE = true
    local STAR_SELECTION_MODE = false
    local STAR_SELECTION_PREFAB = nil
    local FAVORITES_SYNC_PENDING = true
    local CLIENT_INVENTORY_SYNC_PENDING = false

    local function GetFavoriteForSlot(slot_number)
        for _, favorite in ipairs(FAVORITED_ITEMS) do
            if favorite.slot == slot_number then
                return favorite
            end
        end
    end

    local function GetFavoriteDisplayName(prefab)
        local names = GLOBAL.STRINGS and GLOBAL.STRINGS.NAMES
        return names and names[string.upper(prefab)] or prefab
    end

    local function IsPlayerInventorySlot(invslot)
        local player = GLOBAL.ThePlayer
        return player ~= nil and player.replica ~= nil and player.replica.inventory ~= nil
            and tostring(invslot.container) == tostring(player.replica.inventory)
    end

    local function UpdateFavoriteStarAppearance(marker)
        if marker.focus then
            marker.star:SetScale(1.3)
            marker.star:SetColour(1, 0.9, 0.3, 1)
        else
            marker.star:SetScale(1)
            marker.star:SetColour(1, 0.82, 0.2, 0.58)
        end
    end

    local function CreateFavoriteMarker(invslot)
        if invslot.favorite_marker ~= nil then
            return invslot.favorite_marker
        end

        local parent = invslot:GetParent()
        if parent == nil then return nil end

        local slot_x, slot_y = invslot:GetPositionXYZ()
        local _, slot_height = invslot.bgimage:GetSize()
        local marker = parent:AddChild(ImageButton("images/ui.xml", "blank.tex"))
        marker:ForceImageSize(32, 32)
        marker.image:SetTint(0, 0, 0, 0)
        marker.scale_on_focus = false
        marker.move_on_click = false
        marker.focus_sound = nil
        marker:SetPosition(slot_x, slot_y + slot_height * 0.5 + 16) -- centered above the slot, lowered slightly
        marker.star = marker:AddChild(Text(FAVORITE_MARKER_FONT, 30, "★"))
        marker.star:SetColour(1, 0.82, 0.2, 0.58)
        marker.OnControl = function()
            return false
        end
        marker:Hide()
        invslot.favorite_marker = marker
        marker.favorite_marker_base_gain = marker.OnGainFocus
        marker.favorite_marker_base_lose = marker.OnLoseFocus
        marker.OnGainFocus = function(self)
            if self.favorite_marker_base_gain ~= nil then
                self.favorite_marker_base_gain(self)
            end
            UpdateFavoriteStarAppearance(self)
        end
        marker.OnLoseFocus = function(self)
            if self.favorite_marker_base_lose ~= nil then
                self.favorite_marker_base_lose(self)
            end
            UpdateFavoriteStarAppearance(self)
        end
        return marker
    end

    local function RefreshFavoriteMarkers()
        for invslot in pairs(FAVORITE_SLOT_WIDGETS) do
            local marker = invslot.favorite_marker
            if marker ~= nil then
                local favorite = IsPlayerInventorySlot(invslot) and GetFavoriteForSlot(invslot.num) or nil
                if favorite ~= nil and STAR_MARKERS_VISIBLE then
                    marker:SetHoverText(GetFavoriteDisplayName(favorite.item), {
                        font = FAVORITE_MARKER_FONT,
                        font_size = 44,
                        attach_to_parent = marker,
                        offset_x = 0,
                        offset_y = 28,
                    })
                    marker:Show()
                else
                    marker:Hide()
                end
                UpdateFavoriteStarAppearance(marker)
            end
        end
    end

    local function SendFavorites(force)
        if not HAVE_FAVORITED then return end
        if GLOBAL.ThePlayer == nil then
            FAVORITES_SYNC_PENDING = true
            return
        end
        if not force and not FAVORITES_SYNC_PENDING then return end
        SendModRPCToServer(GetModRPC(MOD_RPC, "SetFavorites"), TableToString(FAVORITED_ITEMS))
        FAVORITES_SYNC_PENDING = false
    end

    local function SendClear()
        SendModRPCToServer(GetModRPC(MOD_RPC, "ClearFavorites"))
    end

    local function SetFavoriteForSlot(prefab, slot_number)
        if prefab == nil then return false end

        local item_index = ContainsItemInTable(FAVORITED_ITEMS, prefab)
        local slot_index = SlotIsBusy(FAVORITED_ITEMS, slot_number)
        local message_key

        if item_index ~= false then
            if slot_index == item_index then
                table.remove(FAVORITED_ITEMS, item_index)
                message_key = "removed"
            else
                FAVORITED_ITEMS[item_index].slot = slot_number
                if slot_index ~= false then
                    table.remove(FAVORITED_ITEMS, slot_index)
                    message_key = "replaced"
                else
                    message_key = "moved"
                end
            end
        elseif slot_index ~= false then
            FAVORITED_ITEMS[slot_index].item = prefab
            message_key = "replaced"
        else
            table.insert(FAVORITED_ITEMS, { item = prefab, slot = slot_number })
            message_key = "favorited"
        end

        HAVE_FAVORITED = true
        GLOBAL.TheSim:SetPersistentString(FAVITSAVE, TableToString(FAVORITED_ITEMS), false)
        SendFavorites(true)
        RefreshFavoriteMarkers()

        local player = GLOBAL.ThePlayer
        if player ~= nil and player.components ~= nil and player.components.talker ~= nil then
            local message = GetFavoriteDisplayName(prefab) .. GetMsg(message_key) .. tostring(slot_number)
            if message_key == "removed" then
                message = message .. GetMsg("removed_suffix")
            end
            player.components.talker:Say(message)
        end
        return true
    end

    -- The server may not have received the saved favorite table yet when the
    -- first inventory event arrives. Resend it from the owning client's
    -- replicated inventory events so the server can reconcile immediately.
    local function QueueClientInventorySync(inst)
        if inst ~= GLOBAL.ThePlayer or not HAVE_FAVORITED or CLIENT_INVENTORY_SYNC_PENDING then return end
        CLIENT_INVENTORY_SYNC_PENDING = true
        inst:DoTaskInTime(0.2, function()
            CLIENT_INVENTORY_SYNC_PENDING = false
            if inst == GLOBAL.ThePlayer then
                SendFavorites(true)
            end
        end)
    end

    AddPlayerPostInit(function(inst)
        if inst:HasTag("player") then
            for _, event in ipairs({ "itemget", "itemlose", "gotnewitem", "dropitem", "equip", "unequip", "newactiveitem" }) do
                inst:ListenForEvent(event, function()
                    QueueClientInventorySync(inst)
                end)
            end
        end
    end)

    -- 读取本地收藏存档
    GLOBAL.TheSim:GetPersistentString(FAVITSAVE, function(success, str)
        if success then
            FAVORITED_ITEMS = StringToTable(str)
            if #FAVORITED_ITEMS > 0 then
                HAVE_FAVORITED = true
                SendFavorites()
            end
        end
        RefreshFavoriteMarkers()
    end)

    AddClassPostConstruct("widgets/invslot", function(invslot)
        if IsPlayerInventorySlot(invslot) then
            local oldOnGainFocus = invslot.OnGainFocus
            invslot.OnGainFocus = function(self, ...)
                if oldOnGainFocus ~= nil then oldOnGainFocus(self, ...) end
                HOVERED_PLAYER_SLOT = self
            end
            local oldOnLoseFocus = invslot.OnLoseFocus
            invslot.OnLoseFocus = function(self, ...)
                if oldOnLoseFocus ~= nil then oldOnLoseFocus(self, ...) end
                if HOVERED_PLAYER_SLOT == self then
                    HOVERED_PLAYER_SLOT = nil
                end
            end

            FAVORITE_SLOT_WIDGETS[invslot] = true
            invslot.inst:DoTaskInTime(0, function()
                if invslot.inst:IsValid() and invslot:GetParent() ~= nil then
                    invslot.favorite_marker = CreateFavoriteMarker(invslot)
                    RefreshFavoriteMarkers()
                else
                    FAVORITE_SLOT_WIDGETS[invslot] = nil
                end
            end)
            SendFavorites()
        end

        local oldClick = invslot.Click
        invslot.Click = function(invslot, stack_mod)
            local selected_prefab = STAR_SELECTION_MODE and STAR_SELECTION_PREFAB or nil
            local favorite_key_down = GLOBAL.TheInput:IsKeyDown(FAVORITE_KEY)
            local res = oldClick(invslot, stack_mod)

            if favorite_key_down and IsPlayerInventorySlot(invslot) then
                local function RecordDroppedItem()
                    local placed_item = invslot.tile ~= nil and invslot.tile.item or nil
                    if placed_item ~= nil and (selected_prefab == nil or placed_item.prefab == selected_prefab) then
                        SetFavoriteForSlot(selected_prefab or placed_item.prefab, invslot.num)
                    end
                end
                if selected_prefab ~= nil then
                    invslot.inst:DoTaskInTime(0.1, RecordDroppedItem)
                else
                    RecordDroppedItem()
                end
            end

            return res
        end
    end)

    if GLOBAL.TheInput ~= nil then
        GLOBAL.TheInput:AddKeyDownHandler(FAVORITE_KEY, function()
            if STAR_SELECTION_MODE then return end

            local player = GLOBAL.ThePlayer
            local hovered_slot = HOVERED_PLAYER_SLOT
            local on_player_inventory = hovered_slot ~= nil and IsPlayerInventorySlot(hovered_slot)
            local ctrl_down = GLOBAL.TheInput:IsKeyDown(GLOBAL.KEY_CTRL)
            local alt_down = GLOBAL.TheInput:IsKeyDown(GLOBAL.KEY_ALT)

            if on_player_inventory and ctrl_down and alt_down then
                HAVE_FAVORITED = false
                FAVORITED_ITEMS = {}
                GLOBAL.TheSim:ErasePersistentString(FAVITSAVE)
                SendClear()
                RefreshFavoriteMarkers()
                if player ~= nil and player.components ~= nil and player.components.talker ~= nil then
                    player.components.talker:Say(GetMsg("cleared"))
                end
                return
            end

            if on_player_inventory and ctrl_down then
                STAR_MARKERS_VISIBLE = not STAR_MARKERS_VISIBLE
                RefreshFavoriteMarkers()
                local prompt = SHORTCUT_MESSAGES[GetLang()] or SHORTCUT_MESSAGES.english
                if player ~= nil and player.components ~= nil and player.components.talker ~= nil then
                    if STAR_MARKERS_VISIBLE then
                        player.components.talker:Say(prompt.shown)
                    else
                        player.components.talker:Say(string.format(prompt.hidden,
                            "CTRL + " .. GetModConfigData("FI_SWITCH_KEY")))
                    end
                end
                return
            end

            if ctrl_down or alt_down then return end

            local inventory = player ~= nil and player.replica ~= nil and player.replica.inventory or nil
            local item = inventory ~= nil and inventory:GetActiveItem() or nil
            if item ~= nil then
                STAR_SELECTION_MODE = true
                STAR_SELECTION_PREFAB = item.prefab
                local prompt = SHORTCUT_MESSAGES[GetLang()] or SHORTCUT_MESSAGES.english
                if player ~= nil and player.components ~= nil and player.components.talker ~= nil then
                    player.components.talker:Say(string.format(prompt.choose_slot, GetFavoriteDisplayName(item.prefab)))
                end
            end
        end)

        GLOBAL.TheInput:AddKeyUpHandler(FAVORITE_KEY, function()
            if STAR_SELECTION_MODE then
                STAR_SELECTION_MODE = false
                STAR_SELECTION_PREFAB = nil
            end
        end)
    end
end
