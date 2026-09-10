-- ============================================================
-- manual.lua - 主动干预话术处理模块
-- 从服务端拉取待干预消息，逐条复制到微信粘贴发送
-- ============================================================

local M = {_VERSION = 0.1}

local config = require("config")
local common = require("common")

-- 保存第一次进入ID时最后一条消息的位置（供第二次直接复制使用）
local savedLastMsgPos = nil
-- 缓存消息气泡查找结果，避免重复findPicAllPoint
local cachedIDMsgArr = nil

-- URL编码
local function urlEncode(s)
    if not s then return "" end
    s = tostring(s)
    s = string.gsub(s, "\n", "\r\n")
    s = string.gsub(s, "([^%w%-%.%_%~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    return s
end

-- ==================== 接口调用 ====================

-- 获取主动干预任务
-- @return table {success, data: {messages: [{msg_id, phone, msg, uid}], ...}} 或 nil
function M.fetchManualIntervention(robotCode, channelNum)
    local url = config.manual_intervention_url
        .. "?robot_code=" .. urlEncode(robotCode)
        .. "&channelNum=" .. tostring(channelNum)
    print("[Manual] 获取主动干预任务: " .. url)

    local ok, res = pcall(function()
        local http = require("socket.http")
        local ltn12 = require("ltn12")
        local body = {}
        local _, code = http.request{
            url = url,
            method = "GET",
            sink = ltn12.sink.table(body),
        }
        if code == 200 then
            return table.concat(body)
        end
        print("[Manual] 请求失败, HTTP: " .. tostring(code))
        return nil
    end)

    if not ok or not res then
        print("[Manual] 获取干预任务失败")
        return nil
    end

    local decoded = jsonLib.decode(res)
    if decoded and decoded.success and decoded.data and decoded.data.messages and #decoded.data.messages > 0 then
        print(string.format("[Manual] 找到 %d 条待干预消息", #decoded.data.messages))
        return decoded.data
    end
    print("[Manual] 无待干预消息")
    return nil
end

-- 更新干预消息状态
-- @param msgIds 逗号分隔的msg_id字符串，如 "5863,5864"
-- @param state 状态，1=已发送
function M.updateMsgState(msgIds, state)
    state = state or 1
    local url = config.manual_update_msg_state_url
    local data = {
        msg_id = msgIds,
        state = state
    }
    local json_str = jsonLib.encode(data)

    local maxRetry = 3
    for retry = 1, maxRetry do
        print(string.format("[Manual] 更新消息状态(第%d次): %s", retry, url))
        local ok, res = pcall(function()
            local http = require("socket.http")
            local ltn12 = require("ltn12")
            local body = {}
            local _, code = http.request{
                url = url,
                method = "POST",
                headers = {
                    ["Content-Type"] = "application/json",
                    ["Content-Length"] = #json_str
                },
                source = ltn12.source.string(json_str),
                sink = ltn12.sink.table(body),
            }
            if code == 200 then
                return table.concat(body)
            end
            print(string.format("[Manual] 更新状态HTTP失败, code: %s", tostring(code)))
            return nil
        end)

        if ok and res then
            print("[Manual] 更新消息状态成功")
            return
        end
        if retry < maxRetry then
            sleep(1000)
        end
    end
    print("[Manual] 更新消息状态重试3次均失败")
end

-- ==================== 辅助函数 ====================

-- 确保在微信列表界面
local function ensureWxList()
    local isInWxList = ocr_start(374, 224, 678, 292, "微信")
    if isInWxList then
        print("[Manual] 已在微信列表")
        return true
    end
    print("[Manual] 不在微信列表，尝试返回...")
    common.changeToWXWithCheck()
    sleep(1000)
    local retry = 0
    while retry < 3 do
        retry = retry + 1
        isInWxList = ocr_start(374, 224, 678, 292, "微信")
        if isInWxList then
            print("[Manual] 已回到微信列表")
            return true
        end
        print("[Manual] 第" .. retry .. "次重试返回微信列表...")
        common.changeToWXWithCheck()
        sleep(1500)
    end
    print("[Manual] 无法回到微信列表")
    return false
end

-- 在ID应用中查找"发消息"并点击进入聊天
-- @return 是否成功
local function enterIDChat()
    local maxRetry = 3
    for retry = 1, maxRetry do
        print(string.format("[Manual] 第%d次查找发消息", retry))
        local msgPos = ocr_start(115, 379, 908, 1728, config.id_ai_project_config.name)
        if msgPos then
            randomTap(msgPos[1], msgPos[2] - 10, 5, 1, "点击发消息")
            sleep(1500)
            -- 验证是否进入聊天（mark仅作确认日志，不阻断流程）
            local mark = ocr_start(115, 379, 908, 1728, config.id_ai_project_config.mark)
            if mark then
                print("[Manual] 已进入ID聊天(mark验证通过)")
            else
                print("[Manual] mark验证未通过，但已点击发消息，视为成功进入聊天")
            end
            return true
        else
            print("[Manual] 未找到发消息，重试...")
            common.changeToID()
            sleep(1500)
        end
    end
    print("[Manual] 进入ID聊天失败")
    return false
end

-- 复制ID中倒数第N条消息（长按→复制）
-- @param reverseIndex 倒序索引: 1=最后一条, 2=倒数第二条
-- @return 是否成功
local function copyIDMessage(reverseIndex)
    reverseIndex = reverseIndex or 1

    -- 每次调用重新识别消息气泡位置（避免缓存坐标偏移）
    sleep(2000)
    local arr = findPicAllPoint(224,286,669,1816, "id_yifang_logo2.png", 0.9)
    print("[Manual] 消息气泡查找", arr)
    if not arr or #arr == 0 then
        print("[Manual] 未找到消息气泡")
        return false
    end
    -- 按y正序排序（从上到下），更新缓存
    cachedIDMsgArr = arrSortByY(arr)
    print("[Manual] 识别到消息气泡", #cachedIDMsgArr, "条")

    local arr = cachedIDMsgArr
    -- reverseIndex=2 → 倒数第二条 (arr[#arr-1]), reverseIndex=1 → 最后一条 (arr[#arr])
    local targetIdx = #arr - reverseIndex + 1
    if targetIdx < 1 or targetIdx > #arr then
        print(string.format("[Manual] 消息索引越界: reverseIndex=%d, total=%d", reverseIndex, #arr))
        return false
    end
    local targetMsg = arr[targetIdx]
    local msg_x = targetMsg.x + 200
    local msg_y = targetMsg.y + 60
    print(string.format("[Manual] 复制第%d/%d条消息, 原始坐标(%d,%d), 长按坐标(%d,%d)",
        targetIdx, #arr, targetMsg.x, targetMsg.y, msg_x, msg_y))

    -- 长按消息
    longTap(msg_x, msg_y)
    sleep(1000)

    -- 查找复制按钮
    for n = 1, 5 do
        local rey, cx, cy = findImage(0, 0, 0, 0,
            "id_msg_copy2.png|id_msg_copy1.png|id_msg_copy.png|id_msg_copy3.png|id_msg_copy4.png", 0.8)
        if rey ~= -1 then
            randomTap(cx, cy, 10, 10, "点击复制")
            sleep(1000)
            print("[Manual] 已复制消息")
            return true
        end
        if n == 5 then
            -- 图片识别兜底：OCR找"复制"
            local ocrCopy = ocr_start(94, 217, 267, 1744, "复制")
            if ocrCopy then
                randomTap(ocrCopy[1], ocrCopy[2] - 35, 5, 5, "OCR点击复制")
                sleep(1000)
                return true
            end
        end
        sleep(300)
    end
    print("[Manual] 复制消息失败")
    return false
end

-- 用保存的位置直接长按复制（跳过enterIDChat）
local function copyByPosition(pos)
    longTap(pos.x, pos.y)
    sleep(1000)
    for n = 1, 5 do
        local rey, cx, cy = findImage(0, 0, 0, 0,
            "id_msg_copy2.png|id_msg_copy1.png|id_msg_copy.png|id_msg_copy3.png|id_msg_copy4.png", 0.8)
        if rey ~= -1 then
            randomTap(cx, cy, 10, 10, "点击复制(保存位置)")
            sleep(1000)
            print("[Manual] 已复制消息(用保存位置)")
            return true
        end
        if n == 5 then
            local ocrCopy = ocr_start(94, 217, 267, 1744, "复制")
            if ocrCopy then
                randomTap(math.floor(ocrCopy[1]), math.floor(ocrCopy[2]) - 35, 5, 5, "OCR点击复制")
                sleep(1000)
                return true
            end
        end
        sleep(300)
    end
    return false
end

-- 前置声明（函数定义在后面）
local pasteAndSendInWx
local backToWxList

-- 切到微信并在搜索框中粘贴，然后查找联系人并打开聊天
-- @param phone 联系人手机号
-- @param msgIds 消息ID列表
local function pasteAndFindContact(phone, msgIds)
    -- 回到桌面并切到微信（不检测是否在列表）
    local maxRetry = 3
    for retry = 1, maxRetry do
        print(string.format("[Manual] 第%d次切到微信并搜索", retry))
        common.backToHomeWithCheck(3)
        sleep(500)
        common.changeToWX()
        sleep(1500)

        -- box OCR找"搜索"
        local searchBlocks = ocr_start_with_boxes(108, 200, 906, 500)
         local searchPos = nil
        if searchBlocks then
            for _, block in ipairs(searchBlocks) do
                if block.words and string.find(block.words, "搜索") then
                    searchPos = {x = math.floor(block.x), y = math.floor(block.y)}
                    print(string.format("[Manual] 找到搜索位置: (%.0f, %.0f)", block.x, block.y))
                    break
                end
            end
        end

        if not searchPos then
            print("[Manual] 未找到搜索，重试...")
            sleep(1000)
        else
            -- 长按唤醒粘贴
			print("搜索位置坐标",searchPos)
            longTap(searchPos.x, searchPos.y)
           

            -- 查找粘贴并点击
			 sleep(4000)
            local pasteRes = ocr_start(138,225,927,521, "粘贴")
			print("查找粘贴",pasteRes)
            if pasteRes then
                randomTap(pasteRes[1], pasteRes[2], 10, 5, "点击粘贴")
                sleep(1000)
            else
                print("[Manual] 未找到粘贴选项")
                sleep(1000)
            end
			sleep(1500)
            -- OCR查找联系人位置
           local contactBlocks = ocr_start_with_boxes(209,416,753,588)
			print("联系人区域信息",contactBlocks)
            local contactPos = nil
            if contactBlocks then
                -- 方式1: 用phone数字串精确匹配
                local phoneDigits = phone and phone:gsub("%D", "") or ""
                print(string.format("[Manual] phone原始值='%s' phoneDigits='%s'(len=%d)", tostring(phone), phoneDigits, #phoneDigits))
                for _, block in ipairs(contactBlocks) do
                    if block.words and phoneDigits ~= "" then
                        local blockDigits = block.words:gsub("%D", "")
                        print(string.format("[Manual] 对比 block='%s' blockDigits='%s' vs phoneDigits='%s'", block.words, blockDigits, phoneDigits))
                        if string.find(blockDigits, phoneDigits, 1, true) then
                            contactPos = {x = math.floor(block.x), y = math.floor(block.y)}
                            print(string.format("[Manual] phone匹配找到联系人: (%.0f, %.0f)", block.x, block.y))
                            break
                        end
                    end
                end
                -- 方式2(兜底): phone匹配失败时，找"联系人"label上方的纯数字block
                if not contactPos then
                    print("[Manual] phone匹配失败，启用结构定位兜底...")
                    local contactLabelY = nil
                    for _, block in ipairs(contactBlocks) do
                        if block.words and string.find(block.words, "联系人") then
                            contactLabelY = block.y
                            break
                        end
                    end
                    if contactLabelY then
                        for _, block in ipairs(contactBlocks) do
                            if block.words and block.y < contactLabelY then
                                local digitsOnly = block.words:gsub("%D", "")
                                if #digitsOnly >= 7 then
                                    contactPos = {x = math.floor(block.x), y = math.floor(block.y)}
                                    print(string.format("[Manual] 结构定位找到联系人: (%.0f, %.0f) digits=%s", block.x, block.y, digitsOnly))
                                    break
                                end
                            end
                        end
                    end
                end
            end

            if contactPos then
                local tapX = contactPos.x + math.random(0, 100)
                local tapY = contactPos.y - 20
                randomTap(tapX, tapY, 5, 5, "点击联系人打开聊天")
                sleep(1500)

                -- 切回桌面 → 打开ID复制最后一条消息 → 回到ID列表
                print("[Manual] --- 回到桌面打开ID复制消息(用保存位置) ---")
                common.backToHomeWithCheck(3)
                sleep(500)
                common.changeToID()
                sleep(1500)

                if not savedLastMsgPos then
                    print("[Manual] 无保存的消息位置")
                    return false
                end
                if not copyByPosition(savedLastMsgPos) then
                    print("[Manual] 用保存位置复制失败")
                    return false
                end
                sleep(1000)

                -- 回退ID列表
                local backIdx, bbx, bby = findImage(99, 211, 187, 292, "wx_back.png", 0.9)
                if backIdx ~= -1 then
                    randomTap(bbx + 12, bby + 20, 3, 5, "ID回退列表")
                else
                    randomTap(125, 252, 5, 5, "ID固定回退")
                end
                sleep(1000)

                -- 回到桌面打开微信（不检测微信列表，当前在聊天界面）
                print("[Manual] --- 打开微信粘贴发送 ---")
                common.backToHomeWithCheck(3)
                sleep(500)
                common.changeToWX()
                sleep(1500)

                -- 粘贴发送
                if not pasteAndSendInWx() then
                    print("[Manual] 粘贴发送失败")
                    return false
                end
                sleep(1000)

                -- 更新消息状态
                if msgIds then
                    local msgIdStr = table.concat(msgIds, ",")
                    M.updateMsgState(msgIdStr, 1)
                end

                -- 返回微信列表
                backToWxList()
                return true
            else
                print("[Manual] 未找到联系人，重试...")
                sleep(1000)
            end
        end
    end
    print("[Manual] 粘贴查找联系人失败")
    return false
end

-- 在微信聊天中粘贴并发送消息
-- @return 是否成功
pasteAndSendInWx = function()
    local maxRetry = 3
    for retry = 1, maxRetry do
        print(string.format("[Manual] 第%d次粘贴发送", retry))

        -- ====== 阶段1: 检测并打开输入法 ======
        local inputOpen = ocr_start(616, 1617, 972, 1905, "换行")
        if not inputOpen then
            inputOpen = ocr_start(118, 1431, 554, 1944, "符号")
        end
        if not inputOpen then
            local idx, ix, iy = findImage(112, 1780, 194, 1891, "chat_box_left_btn.png|chat_box_left_btn1.png", 0.9)
            if idx ~= -1 then
                randomTap(ix + 180, iy + 35, 10, 10, "点击输入框")
            else
                randomTap(475, 1794, 30, 30, "点击输入框固定位置")
            end
            sleep(1500)
        end

        -- ====== 阶段2: 粘贴操作 ======
        local pasteSuccess = false
        local pasteRetry = 0
        while pasteRetry < 5 and not pasteSuccess do
            pasteRetry = pasteRetry + 1

            -- 方式1: 检测剪切板快捷方式
            local quickReply = ocr_start(496, 1187, 925, 1354, "高情商回复")
            local pasteShotIdx, pSx, pSy = findImage(98, 1059, 428, 1483, "mate30_search_friend_paste.png", 0.9)

            if quickReply then
                randomTap(quickReply[1] - 500, quickReply[2], 150, 5, "点击剪切板内容")
                print("[Manual] 高情商回复快捷粘贴")
            elseif pasteShotIdx ~= -1 then
                randomTap(pSx + 80, pSy + 20, 30, 10, "点击粘贴图标")
                print("[Manual] 快捷文字图片块粘贴")
            else
                -- 优先动态查找输入框位置
                local idx, ix, iy = findImage(112, 1780, 194, 1891, "chat_box_left_btn.png|chat_box_left_btn1.png", 0.9)
                if idx ~= -1 then
                    randomTap(ix + 180, iy + 35, 10, 10, "动态点击输入框")
                else
                    randomTap(263, 1157, 50, 30, "固定位置点击输入框")
                end
                sleep(2000)
                -- 方式2: 直接OCR查找"粘贴"
                local pasteRes = ocr_start(120, 948, 893, 1888, "粘贴")
                if pasteRes then
                    randomTap(pasteRes[1], pasteRes[2], 10, 5, "点击粘贴")
                    print("[Manual] OCR粘贴")
                else
                    -- 方式3: 长按唤醒粘贴菜单
                    longTap(263, 1157)
                    sleep(2000)
                    -- 多区域查找"粘贴"（窄→宽）
                    pasteRes = ocr_start(50, 950, 300, 1300, "粘贴")
                    if not pasteRes then
                        pasteRes = ocr_start(105, 800, 804, 1840, "粘贴")
                    end
                    if pasteRes then
                        randomTap(math.floor(pasteRes[1]), math.floor(pasteRes[2]), 10, 5, "点击粘贴(长按)")
                        print("[Manual] 长按粘贴")
                    else
                        print("[Manual] 未找到粘贴选项")
                        randomTap(500, 1500, 50, 50, "点击空白关闭菜单")
                        sleep(1000)
                    end
                end
            end

            -- 验证粘贴是否成功：查找"发送"按钮
            sleep(1200)
            local sendCheck = ocr_start(645, 1073, 972, 1296, "发送")
            if sendCheck then
                pasteSuccess = true
                print("[Manual] 粘贴成功")
            else
                print("[Manual] 粘贴未生效，重试...")
            end
        end

        if not pasteSuccess then
            print("[Manual] 粘贴失败，重试整个流程...")
            sleep(1000)
        else
            -- ====== 阶段3: 发送操作 ======
            local sendRetry = 0
            while sendRetry < 3 do
                sendRetry = sendRetry + 1
                local sendPos = ocr_start(645, 1073, 972, 1296, "发送")
                if sendPos then
                    randomTap(sendPos[1], sendPos[2], 5, 5, "点击发送")
                else
                    sendPos = ocr_start(656, 930, 936, 1917, "发送")
                    if sendPos then
                        randomTap(sendPos[1], sendPos[2], 5, 5, "点击发送(宽范围)")
                    else
                        randomTap(859, 1165, 30, 10, "固定位置发送")
                    end
                end
                sleep(1000)
                -- 验证发送成功：发送按钮消失
                local sendCheck = ocr_start(645, 1073, 972, 1296, "发送")
                if not sendCheck then
                    print("[Manual] 消息已发送")
                    sleep(1000)
                    return true
                end
                print("[Manual] 发送按钮仍在，重试发送...")
            end
            print("[Manual] 发送失败")
        end
    end
    print("[Manual] 粘贴发送失败")
    return false
end

-- 返回微信列表（点击wx_back.png直到消失，并OCR验证）
backToWxList = function()
    local maxRetry = 10
    for retry = 1, maxRetry do
        local idx, bx, by = findImage(99, 211, 187, 292, "wx_back.png", 0.9)
        if idx ~= -1 then
            randomTap(bx + 12, by + 20, 3, 5, "点击返回")
            sleep(1000)
        else
            -- 返回按钮消失，等待页面稳定后OCR验证
            sleep(500)
            local inWxList = ocr_start(300, 200, 800, 350, "微信")
            if inWxList then
                print("[Manual] 已回到微信列表")
                return true
            end
            print("[Manual] 返回按钮消失但未检测到微信列表，继续尝试返回...")
            randomTap(150, 260, 5, 5, "固定位置返回")
            sleep(1000)
        end
    end
    print("[Manual] 返回微信列表异常")
    return false
end

-- ==================== 主流程 ====================

-- 执行主动干预任务
-- @param robotCode 机器人编码
-- @param channelNum 通道编号
-- @return true/false
function M.runManualIntervention(robotCode, channelNum)
    print(string.format("[Manual] ====== 开始主动干预, 通道%d ======", channelNum))

    -- 1. 拉取待干预任务
    local interventionData = M.fetchManualIntervention(robotCode, channelNum)
    if not interventionData or not interventionData.messages or #interventionData.messages == 0 then
        print("[Manual] 无待干预任务，跳过")
        return false
    end

    local messages = interventionData.messages
    local msgCount = #messages
    print(string.format("[Manual] 共 %d 条待干预消息", msgCount))

    -- 收集所有msg_id用于后续状态更新
    local msgIds = {}
    for _, msg in ipairs(messages) do
        table.insert(msgIds, tostring(msg.msg_id))
    end

    -- 第一步消息的phone用于查找联系人
    local firstMsg = messages[1]
    local targetPhone = tostring(firstMsg.phone or "")
    print(string.format("[Manual] 目标手机号: '%s' (len=%d)", targetPhone, #targetPhone))

    -- ========== 步骤1：确保在微信列表，点击搜索按钮 ==========
    print("[Manual] === 步骤1: 确保微信列表并点击搜索 ===")
    if not ensureWxList() then
        print("[Manual] 步骤1失败")
        return false
    end
    sleep(1000)

    -- 点击搜索按钮（带重试：点击后检测"微信"未消失则重新点击）
    for retrySearch = 1, 3 do
        local idx, sx, sy = findImage(699, 203, 906, 339, "wx_search_btn.png", 0.9)
        if idx ~= -1 then
            randomTap(sx+25, sy+25, 8, 8, "点击搜索")
        else
            randomTap(791, 253, 10, 10, "固定位置点击搜索")
        end
        sleep(1500)
        local wxStill = ocr_start(304, 205, 763, 311, "微信")
        if not wxStill then
            print("[Manual] 搜索按钮点击成功（微信已消失）")
            break
        end
        print("[Manual] 微信仍存在，第" .. retrySearch .. "次重试点击搜索...")
    end
    sleep(2000)

    -- ========== 步骤2：回到桌面 → 打开ID → 查找发消息 → 点击进入 ==========
    print("[Manual] === 步骤2: 打开ID进入聊天 ===")
    common.backToHomeWithCheck(3)
    sleep(500)
    common.changeToID()
    sleep(1500)

    if not enterIDChat() then
        print("[Manual] 步骤2失败")
        return false
    end
    sleep(1000)

    -- ========== 步骤3：复制倒数第二条消息 → 切微信 → 搜索粘贴 → 找联系人打开聊天 ==========
    print("[Manual] === 步骤3: 复制倒数第二条 → 微信搜索联系人 ===")
    if not copyIDMessage(2) then
        print("[Manual] 步骤3复制失败")
        return false
    end
    sleep(1000)

    -- 保存最后一条消息位置供后续直接使用（基于copyIDMessage最新识别坐标）
    savedLastMsgPos = nil
    if cachedIDMsgArr and #cachedIDMsgArr > 0 then
        local lastMsg = cachedIDMsgArr[#cachedIDMsgArr]
        savedLastMsgPos = {x = lastMsg.x + 200, y = lastMsg.y + 60}
        print(string.format("[Manual] 保存最后消息位置(最新识别): (%d, %d)", savedLastMsgPos.x, savedLastMsgPos.y))
    else
        print("[Manual] 警告: cachedIDMsgArr为空，无法保存消息位置")
    end

    if not pasteAndFindContact(targetPhone, msgIds) then
        print("[Manual] 步骤3搜索联系人失败")
        return false
    end
    sleep(1000)

    -- ========== 步骤4：复制第二条消息 → 粘贴发送 ==========
    if msgCount >= 2 then
        print("[Manual] === 步骤4: 复制第二条消息 → 发送 ===")

        -- 回到桌面打开ID
        common.backToHomeWithCheck(3)
        sleep(500)
        common.changeToID()
        sleep(1500)

        -- 确保在ID聊天中
        if not enterIDChat() then
            print("[Manual] 步骤4进入ID聊天失败")
            return false
        end
        sleep(1000)

        -- 复制最后一条消息
        if not copyIDMessage(1) then
            print("[Manual] 步骤4复制失败")
            return false
        end
        sleep(1000)

        -- 回退ID列表
        local backIdx, bbx, bby = findImage(99, 211, 187, 292, "wx_back.png", 0.9)
        if backIdx ~= -1 then
            randomTap(bbx + 12, bby + 20, 3, 5, "ID回退列表")
            sleep(1000)
        else
            randomTap(125, 252, 5, 5, "ID固定回退")
            sleep(1000)
        end

        -- 回到桌面再打开微信（不检测是否在列表）
        common.backToHomeWithCheck(3)
        sleep(500)
        common.changeToWX()
        sleep(1500)

        -- 粘贴发送
        if not pasteAndSendInWx() then
            print("[Manual] 步骤4粘贴发送失败")
            return false
        end
        sleep(1000)
    end

    -- ========== 步骤5：返回微信列表 ==========
    print("[Manual] === 步骤5: 返回微信列表 ===")
    backToWxList()
    sleep(500)

    -- 更新消息状态
    local msgIdStr = table.concat(msgIds, ",")
    M.updateMsgState(msgIdStr, 1)

    print("[Manual] ====== 主动干预完成 ======")
    return true
end

return M
