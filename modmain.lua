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

local REMOVE_CONFIRM_MESSAGES = {
    english = { title = "Remove favorite?", body = "Remove %s from favorites?", yes = "Remove", no = "Cancel" },
    schinese = { title = "移除收藏？", body = "确定移除 %s 的槽位收藏标记吗？", yes = "移除", no = "取消" },
    tchinese = { title = "移除收藏？", body = "確定移除 %s 的欄位收藏標記嗎？", yes = "移除", no = "取消" },
    russian = { title = "Убрать из избранного?", body = "Убрать отметку избранного для «%s»?", yes = "Убрать", no = "Отмена" },
    german = { title = "Favorit entfernen?", body = "Favoritenmarkierung für %s entfernen?", yes = "Entfernen", no = "Abbrechen" },
    french = { title = "Retirer des favoris ?", body = "Retirer la marque de favori de %s ?", yes = "Retirer", no = "Annuler" },
    spanish = { title = "¿Quitar de favoritos?", body = "¿Quitar la marca de favorito de %s?", yes = "Quitar", no = "Cancelar" },
    portuguese_br = { title = "Remover dos favoritos?", body = "Remover a marca de favorito de %s?", yes = "Remover", no = "Cancelar" },
    korean = { title = "즐겨찾기를 삭제할까요?", body = "%s의 즐겨찾기 표시를 삭제할까요?", yes = "삭제", no = "취소" },
    japanese = { title = "お気に入りを解除しますか？", body = "「%s」のお気に入りマークを解除しますか？", yes = "解除", no = "キャンセル" },
    italian = { title = "Rimuovere dai preferiti?", body = "Rimuovere il contrassegno preferito di %s?", yes = "Rimuovi", no = "Annulla" },
    polish = { title = "Usunąć z ulubionych?", body = "Usunąć oznaczenie ulubionego przedmiotu %s?", yes = "Usuń", no = "Anuluj" },
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

local function FindItemInContainer(container, prefab)
    if container == nil or container.readonlycontainer or container.GetNumSlots == nil then
        return nil, nil
    end
    for slot = 1, container:GetNumSlots() do
        local item = container:GetItemInSlot(slot)
        if item ~= nil and item.prefab == prefab then
            return item, slot
        end
    end
    return nil, nil
end

AddModRPCHandler(MOD_RPC, "PullFavoriteItem", function(player, slot_number)
    if player == nil or player.userid == nil or type(slot_number) ~= "number"
        or slot_number ~= math.floor(slot_number) then
        return
    end

    local inv = player.components ~= nil and player.components.inventory or nil
    local favorites = mod_fav.favs[player.userid]
    if inv == nil or favorites == nil or slot_number < 1 or slot_number > inv:GetNumSlots()
        or inv:GetActiveItem() ~= nil then
        return
    end

    local prefab
    for _, favorite in ipairs(favorites) do
        if favorite.slot == slot_number then
            prefab = favorite.item
            break
        end
    end
    if prefab == nil then return end

    local current = inv:GetItemInSlot(slot_number)
    if current ~= nil and current.prefab == prefab then return end

    local source, source_slot, item = nil, nil, nil
    local overflow = inv:GetOverflowContainer()
    item, source_slot = FindItemInContainer(overflow, prefab)
    if item ~= nil then
        source = overflow
    else
        for container_inst in pairs(inv.opencontainers or {}) do
            local container = container_inst.components ~= nil
                and (container_inst.components.container or container_inst.components.inventory)
                or nil
            if container ~= overflow and not (container and container.excludefromcrafting) then
                item, source_slot = FindItemInContainer(container, prefab)
                if item ~= nil then
                    source = container
                    break
                end
            end
        end
    end
    if item == nil or source == nil or not inv:CanTakeItemInSlot(item, slot_number) then return end

    -- Move one whole stack from the source container into the favorite slot.
    item = source:RemoveItemBySlot(source_slot)
    if item == nil then return end

    local displaced = inv:RemoveItemBySlot(slot_number)
    if displaced ~= nil then
        if not source:CanTakeItemInSlot(displaced, source_slot)
            or not source:GiveItem(displaced, source_slot, nil, false) then
            inv:GiveItem(displaced, slot_number)
            source:GiveItem(item, source_slot, nil, false)
            return
        end
    end

    if inv:GiveItem(item, slot_number) == nil then
        if displaced ~= nil then
            local restore = source:RemoveItemBySlot(source_slot)
            if restore ~= nil then inv:GiveItem(restore, slot_number) end
        end
        source:GiveItem(item, source_slot, nil, false)
        return
    end

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
    local PopupDialogScreen = require("screens/redux/popupdialog")
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
    local STAR_BLINK_VISIBLE = true
    local STAR_BLINK_TASK = nil
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

    local ShowRemoveFavoriteConfirmation
    local RequestPullFavoriteItem

    local function IsPlayerInventorySlot(invslot)
        local player = GLOBAL.ThePlayer
        return player ~= nil and player.replica ~= nil and player.replica.inventory ~= nil
            and tostring(invslot.container) == tostring(player.replica.inventory)
    end

    local function UpdateFavoriteStarAppearance(marker)
        if STAR_SELECTION_MODE then
            local alpha = STAR_BLINK_VISIBLE and 1 or 0.12
            local scale = marker.focus and 1.3 or 1
            marker.star:SetScale(scale)
            marker.star:SetColour(1, 0.9, 0.3, alpha)
        elseif marker.focus then
            marker.star:SetScale(1.3)
            marker.star:SetColour(1, 0.9, 0.3, 1)
        else
            marker.star:SetScale(1)
            marker.star:SetColour(1, 0.82, 0.2, 0.58)
        end
    end

    local function StartFavoriteStarBlink()
        if STAR_BLINK_TASK == nil and GLOBAL.ThePlayer ~= nil then
            STAR_BLINK_TASK = GLOBAL.ThePlayer:DoPeriodicTask(1, function()
                STAR_BLINK_VISIBLE = not STAR_BLINK_VISIBLE
                for invslot in pairs(FAVORITE_SLOT_WIDGETS) do
                    if invslot.favorite_marker ~= nil then
                        UpdateFavoriteStarAppearance(invslot.favorite_marker)
                    end
                end
            end)
        end
    end

    local function StopFavoriteStarBlink()
        if STAR_BLINK_TASK ~= nil then
            STAR_BLINK_TASK:Cancel()
            STAR_BLINK_TASK = nil
        end
        STAR_BLINK_VISIBLE = true
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
        marker:SetPosition(slot_x, slot_y + slot_height * 0.5 + 24) -- centered above the slot, slightly lower
        marker.star = marker:AddChild(Text(FAVORITE_MARKER_FONT, 30, "★"))
        marker.star:SetColour(1, 0.82, 0.2, 0.58)
        marker:SetOnClick(function()
            if RequestPullFavoriteItem ~= nil then
                RequestPullFavoriteItem(invslot.num)
            end
        end)
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
        local oldOnControl = marker.OnControl
        marker.OnControl = function(self, control, down)
            if control == GLOBAL.CONTROL_SECONDARY then
                if down and ShowRemoveFavoriteConfirmation ~= nil then
                    ShowRemoveFavoriteConfirmation(invslot.num)
                end
                return true
            end
            return oldOnControl(self, control, down)
        end
        return marker
    end

    local function RefreshFavoriteMarkers()
        for invslot in pairs(FAVORITE_SLOT_WIDGETS) do
            local marker = invslot.favorite_marker
            if marker ~= nil then
                local favorite = IsPlayerInventorySlot(invslot) and GetFavoriteForSlot(invslot.num) or nil
                local show_marker = favorite ~= nil and STAR_MARKERS_VISIBLE or STAR_SELECTION_MODE
                if show_marker then
                    local tooltip_text = favorite ~= nil
                        and GetFavoriteDisplayName(favorite.item)
                        or string.format((SHORTCUT_MESSAGES[GetLang()] or SHORTCUT_MESSAGES.english).choose_slot,
                            GetFavoriteDisplayName(STAR_SELECTION_PREFAB))
                    marker:SetHoverText(tooltip_text, {
                        font = FAVORITE_MARKER_FONT,
                        font_size = 44,
                        attach_to_parent = marker,
                        offset_x = 0,
                        offset_y = 28,
                    })
                    marker:Show()
                    UpdateFavoriteStarAppearance(marker)
                else
                    marker:Hide()
                end
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

    RequestPullFavoriteItem = function(slot_number)
        if GetFavoriteForSlot(slot_number) ~= nil then
            SendModRPCToServer(GetModRPC(MOD_RPC, "PullFavoriteItem"), slot_number)
        end
    end

    local function SetFavoriteForSlot(prefab, slot_number)
        if prefab == nil then return false end

        local item_index = ContainsItemInTable(FAVORITED_ITEMS, prefab)
        local slot_index = SlotIsBusy(FAVORITED_ITEMS, slot_number)
        local message_key

        if item_index ~= false then
            if slot_index == item_index then return false end
            FAVORITED_ITEMS[item_index].slot = slot_number
            if slot_index ~= false then
                table.remove(FAVORITED_ITEMS, slot_index)
                message_key = "replaced"
            else
                message_key = "moved"
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
            player.components.talker:Say(GetFavoriteDisplayName(prefab) .. GetMsg(message_key) .. tostring(slot_number))
        end
        return true
    end

    ShowRemoveFavoriteConfirmation = function(slot_number)
        local favorite = GetFavoriteForSlot(slot_number)
        if favorite == nil then return end

        local prompt = REMOVE_CONFIRM_MESSAGES[GetLang()] or REMOVE_CONFIRM_MESSAGES.english
        local body = string.format(prompt.body, GetFavoriteDisplayName(favorite.item))
        local popup = PopupDialogScreen(prompt.title, body, {
            {
                text = prompt.yes,
                cb = function()
                    GLOBAL.TheFrontEnd:PopScreen()
                    local index = SlotIsBusy(FAVORITED_ITEMS, slot_number)
                    if index ~= false then
                        local removed_prefab = FAVORITED_ITEMS[index].item
                        table.remove(FAVORITED_ITEMS, index)
                        HAVE_FAVORITED = true
                        GLOBAL.TheSim:SetPersistentString(FAVITSAVE, TableToString(FAVORITED_ITEMS), false)
                        SendFavorites(true)
                        HAVE_FAVORITED = #FAVORITED_ITEMS > 0
                        RefreshFavoriteMarkers()
                        local player = GLOBAL.ThePlayer
                        if player ~= nil and player.components ~= nil and player.components.talker ~= nil then
                            player.components.talker:Say(GetFavoriteDisplayName(removed_prefab)
                                .. GetMsg("removed") .. tostring(slot_number) .. GetMsg("removed_suffix"))
                        end
                    end
                end,
            },
            {
                text = prompt.no,
                cb = function()
                    GLOBAL.TheFrontEnd:PopScreen()
                end,
            },
        }, nil, "small", "dark")
        GLOBAL.TheFrontEnd:PushScreen(popup)
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
            if STAR_SELECTION_MODE
                and GLOBAL.TheInput:IsKeyDown(FAVORITE_KEY)
                and IsPlayerInventorySlot(invslot) then
                SetFavoriteForSlot(STAR_SELECTION_PREFAB, invslot.num)
                return true
            end

            local res = oldClick(invslot, stack_mod)

            if GLOBAL.TheInput:IsKeyDown(FAVORITE_KEY) then
                if tostring(invslot.container) ~= tostring(GLOBAL.ThePlayer.replica.inventory) then
                    return res
                end

                if invslot.tile and invslot.tile.item then
                    local clickedSlotNumber = invslot.num
                    local selectedItem = invslot.tile.item
                    local prefab = selectedItem.prefab
                    SetFavoriteForSlot(prefab, clickedSlotNumber)
                end
            end

            return res
        end
    end)

    if GLOBAL.TheInput ~= nil then
        GLOBAL.TheInput:AddKeyDownHandler(FAVORITE_KEY, function()
            if STAR_SELECTION_MODE then return end

            local slot = HOVERED_PLAYER_SLOT
            if slot == nil then return end
            local item = slot ~= nil and slot.tile ~= nil and slot.tile.item or nil
            local player = GLOBAL.ThePlayer
            if item ~= nil then
                STAR_SELECTION_MODE = true
                STAR_SELECTION_PREFAB = item.prefab
                STAR_BLINK_VISIBLE = true
                RefreshFavoriteMarkers()
                StartFavoriteStarBlink()
                local prompt = SHORTCUT_MESSAGES[GetLang()] or SHORTCUT_MESSAGES.english
                if player ~= nil and player.components ~= nil and player.components.talker ~= nil then
                    player.components.talker:Say(string.format(prompt.choose_slot, GetFavoriteDisplayName(item.prefab)))
                end
            elseif GLOBAL.TheInput:IsKeyDown(GLOBAL.KEY_CTRL) then
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
            end
        end)

        GLOBAL.TheInput:AddKeyUpHandler(FAVORITE_KEY, function()
            if STAR_SELECTION_MODE then
                STAR_SELECTION_MODE = false
                STAR_SELECTION_PREFAB = nil
                StopFavoriteStarBlink()
                RefreshFavoriteMarkers()
            end
        end)

        GLOBAL.TheInput:AddKeyDownHandler(GLOBAL.KEY_Z, function()
            if GLOBAL.TheInput:IsKeyDown(GLOBAL.KEY_CTRL) and GLOBAL.TheInput:IsKeyDown(GLOBAL.KEY_SHIFT) then
                HAVE_FAVORITED = false
                FAVORITED_ITEMS = {}
                GLOBAL.TheSim:ErasePersistentString(FAVITSAVE)
                SendClear()
                RefreshFavoriteMarkers()
                if GLOBAL.ThePlayer and GLOBAL.ThePlayer.components and GLOBAL.ThePlayer.components.talker then
                    GLOBAL.ThePlayer.components.talker:Say(GetMsg("cleared"))
                end
            end
        end)
    end
end
