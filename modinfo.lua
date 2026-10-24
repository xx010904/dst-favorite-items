-- This information tells other players more about the mod
name = ChooseTranslationTable({
    [1] = "Favorite Items",
    zh = "收藏物品",
    zht = "收藏物品",
    zhr = "收藏物品",
})

description = ChooseTranslationTable({
    [1] = [[
Favorite your items and keep them locked to the slots you choose.

How to use:
    - Hold CTRL + the favorite key (default CTRL + V) over an empty slot to hide or show favorite stars.
    - Hold the favorite key over an item slot, then click the slot where you want to lock the item.
    - Left-click a favorite star to move one stack from your equipped backpack or an open container into that slot.
    - Right-click a favorite star and confirm to remove its marker.
    - Press CTRL + SHIFT + Z to clear all favorite markers.

- You can favorite multiple items, each in its own slot.
- Items stored inside backpacks cannot be marked directly; use the star to move a stack into the inventory first.
]],
    zh = [[
收藏物品，让它们固定在你选择的物品栏槽位中。

使用方法：
    - 在空槽位上按住 CTRL + 收藏键（默认 CTRL + V），可隐藏或显示所有收藏星星。
    - 将鼠标移到物品槽位并按住收藏键，然后点击要锁定到的槽位。
    - 左键点击收藏星星，可从装备的背包或当前打开的容器中移入一组物品。
    - 右键点击收藏星星，并确认移除该槽位的标记。
    - 按 CTRL + SHIFT + Z 可清除所有收藏标记。

- 可以收藏多个物品，每个物品占用一个槽位。
- 背包里的物品不能直接设置收藏；先点击星星将一组物品移入物品栏。
]],
    zht = [[
收藏物品，讓它們固定在你選擇的物品欄欄位中。

使用方法：
    - 在空欄位上按住 CTRL + 收藏鍵（預設 CTRL + V），可隱藏或顯示所有收藏星星。
    - 將滑鼠移到物品欄位並按住收藏鍵，然後點擊要鎖定的欄位。
    - 左鍵點擊收藏星星，可從裝備的背包或目前開啟的容器移入一組物品。
    - 右鍵點擊收藏星星，並確認移除該欄位的標記。
    - 按 CTRL + SHIFT + Z 可清除所有收藏標記。

- 可以收藏多個物品，每個物品佔用一個欄位。
- 背包裡的物品不能直接設定收藏；先點擊星星將一組物品移入物品欄。
]],
    zhr = [[
收藏物品，让它们固定在你选择的物品栏槽位中。

使用方法：
    - 在空槽位上按住 CTRL + 收藏键（默认 CTRL + V），可隐藏或显示所有收藏星星。
    - 将鼠标移到物品槽位并按住收藏键，然后点击要锁定到的槽位。
    - 左键点击收藏星星，可从装备的背包或当前打开的容器中移入一组物品。
    - 右键点击收藏星星，并确认移除该槽位的标记。
    - 按 CTRL + SHIFT + Z 可清除所有收藏标记。

- 可以收藏多个物品，每个物品占用一个槽位。
- 背包里的物品不能直接设置收藏；先点击星星将一组物品移入物品栏。
]],
})

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
