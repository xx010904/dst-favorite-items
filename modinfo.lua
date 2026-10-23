-- This information tells other players more about the mod
name = "Favorite Items"
description = [[
Favorite your items and keep them locked to the slots you choose.

How to use:
    - Pick up an item with the mouse, press the favorite key (default V), then click the slot you want to lock it to.
    - Press the favorite key + click again to remove the favorite.
    - Pick up an item, press the favorite key + click another slot to move it.
    - Press CTRL + SHIFT + Z to clear all favorited items. (Useful when something goes wrong)

- You can favorite multiple items, each on its own slot.
- Items inside backpacks cannot be favorited.
]]

author = "XJS"
version = "2.0.0"

icon_atlas = "modicon.xml"
icon = "modicon.tex"

forumthread = ""

-- This lets other players know if your mod is out of date, update it to match the current version in the game
api_version_dst = 10

priority = 100

-- Only compatible with DST
dont_starve_compatible = false
reign_of_giants_compatible = false
shipwrecked_compatible = false
dst_compatible = true


--This lets clients know if they need to get the mod from the Steam Workshop to join the game
-- 设为 false: 普通玩家无需强制订阅也能进服 (只是没有这个 mod 的 UI); 若要 friends 自动下载, 上传工坊后改为 true
all_clients_require_mod = false

-- 本 mod 为服务器 mod: 客户端 + 服务器都加载 (客户端负责 UI/提示, 服务器负责权威锁位)
client_only_mod = false

--These tags allow the server running this mod to be found with filters from the server listing screen
server_filter_tags = {""}

ScaleValues = {}
for i=1, 15 do
	ScaleValues[i] = {description = "" .. (i/10), data = (i/10)}
end

configuration_options =
{
    {
        name = "FI_SWITCH_KEY",
        label = "Favorite key",
        hover = "Choose the key you want to use to favorite items.",
        options = {
            {description = "R", data = "R"},
            {description = "T", data = "T"},
            {description = "O", data = "O"},
            {description = "P", data = "P"},
            {description = "G", data = "G"},
            {description = "H", data = "H"},
            {description = "J", data = "J"},
            {description = "K", data = "K"},
            {description = "L", data = "L"},
            {description = "Z", data = "Z"},
            {description = "X", data = "X"},
            {description = "C", data = "C"},
            {description = "V", data = "V"},
            {description = "B", data = "B"},
            {description = "N", data = "N"},
        },
        default = "V",
    }
}
