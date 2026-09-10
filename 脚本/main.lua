local common = require("common")

-- 主流程函数（带检测与重试）
function findAndOpenWeChat()
    print("开始打开微信...")

    -- 直接使用 changeToWXWithCheck，该函数已包含完整的打开和校验逻辑
    local ok, success = pcall(common.changeToWXWithCheck)
    if ok and success then
        print("微信已成功打开")
        return true
    else
        print("changeToWXWithCheck 失败，尝试备用方式")

        -- 备用方式：直接调用 openWeChatOptimize
        ok, success = pcall(common.openWeChatOptimize)
        if ok and success then
            print("通过 openWeChatOptimize 成功打开微信")
            return true
        end
    end

    print("打开微信失败")
    return false
end

-- 执行主函数：保证 main.lua 自身也有重试
local maxRetry = 3
local success = false

for i = 1, maxRetry do
    print(string.format("第%d次尝试打开微信", i))
    local ok, ret = pcall(findAndOpenWeChat)
    if ok and ret then
        success = true
        break
    else
        print(string.format("第%d次启动微信失败，重试中...", i))
        sleep(1000)
    end
end

if not success then
    print("多次尝试仍未能打开微信，请检查图标是否存在")
    error("打开微信失败")
end

sleep(1500)
print("微信应已成功打开")
