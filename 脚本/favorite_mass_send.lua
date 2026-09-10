-- favorite_mass_send.lua
-- 收藏群发流程（type=3）
-- 从微信收藏中获取内容并群发给指定联系人

local M = {}

local common = require("common")
local mass_send = require("mass_send")
local global_config = require("config")

-- ==================== 步骤1: 进入收藏页面 ====================
-- 打开微信 → 检测右下角"我" → 点击 → 查找"收藏" → 点击
-- @return boolean 是否成功进入收藏页面
local function step1_enterFavorites()
    print("========== 步骤1: 进入收藏页面 ==========")

    -- 1.1 打开微信
    common.openWeChatSimple()
    sleep(1500)

    -- 1.2 导航到"我"页面（右下角区域检测是否存在"我"）
    local meClicked = false
    for retry = 1, 5 do
        local mePos = ocr_start(727, 1820, 930, 1930, "我")
        if mePos then
            randomTap(mePos[1], mePos[2], 5, 5, "点击'我'")
            print("步骤1: 点击'我'成功")
            meClicked = true
            sleep(1500)
            break
        else
            -- 检测左上角返回按钮
            local backPos = ocr_start(30, 50, 120, 100, "返回")
            if backPos then
                randomTap(backPos[1], backPos[2], 5, 5, "点击返回")
                print("步骤1: 未找到'我'，点击返回")
                sleep(1500)
            else
                -- 尝试点击固定返回位置
                randomTap(50, 60, 5, 5, "固定位置返回")
                sleep(1500)
            end
        end
    end

    if not meClicked then
        print("步骤1失败: 无法找到'我'按钮")
        return false
    end

    -- 1.3 在"我"页面查找"收藏"并点击
    local favFound = false
    for retry = 1, 5 do
        local favPos = ocr_start(84, 548, 786, 1053, "收藏")
        if favPos then
            randomTap(favPos[1], favPos[2], 5, 5, "点击收藏")
            print("步骤1: 点击'收藏'成功")
            favFound = true
            sleep(2000)
            break
        end
        print("步骤1: 第" .. retry .. "次未找到收藏，等待重试")
        sleep(1000)
    end

    if not favFound then
        print("步骤1失败: 无法找到'收藏'")
        return false
    end

    print("========== 步骤1完成: 已进入收藏页面 ==========")
    return true
end

-- ==================== 步骤2: 查找并选中收藏内容 ====================
-- 解析 template_contents，用 box OCR 查找 content_segment，
-- 找到第一个长按 y-30 唤醒多选 → 点击多选 → 继续选中其余匹配项
-- @param contentSegments 内容片段列表 [{content_segment, content_type, ...}]
-- @return boolean 是否成功选中内容
local function step2_selectFavoriteContents(contentSegments)
    print("========== 步骤2: 查找并选中收藏内容 ==========")

    if not contentSegments or #contentSegments == 0 then
        print("步骤2: 无内容片段，跳过")
        return false
    end

    -- 构建待查找的内容集合
    local pendingSegments = {}
    for _, seg in ipairs(contentSegments) do
        if seg.content_segment and seg.content_segment ~= "" then
            pendingSegments[#pendingSegments + 1] = seg.content_segment
        end
    end

    if #pendingSegments == 0 then
        print("步骤2: 无有效内容片段")
        return false
    end

    print(string.format("步骤2: 待查找内容片段 %d 个", #pendingSegments))

    -- 2.1 查找第一个匹配项所在页面
    local firstFound = false
    local maxScroll = 30

    for scroll = 0, maxScroll do
        if scroll > 0 then
            print(string.format("步骤2: 下滑查找第 %d 次", scroll))
            -- 下滑加载更多收藏内容
            randomSwipe(500, 1400, 500, 500, 800)
            sleep(1500)
        end

        local textBlocks = ocr_start_with_boxes(84, 200, 940, 1800)
        if textBlocks and #textBlocks > 0 then
            -- 坐标取整
            for _, item in ipairs(textBlocks) do
                item.x = math.floor(item.x or 0)
                item.y = math.floor(item.y or 0)
            end
            -- 按 y 升序
            table.sort(textBlocks, function(a, b) return a.y < b.y end)

            print(string.format("步骤2: 识别到 %d 个文字块", #textBlocks))

            for i, item in ipairs(textBlocks) do
                print(string.format("  文字块[%d]: %s (x:%d, y:%d)", i, tostring(item.words), item.x, item.y))
            end

            -- 查找第一个匹配 content_segment 的文字块
            for _, item in ipairs(textBlocks) do
                if item.words then
                    for j, seg in ipairs(pendingSegments) do
                        if string.find(item.words, seg, 1, true) or string.find(seg, item.words, 1, true) then
                            print(string.format("步骤2: 找到第一个匹配项 '%s' pos=(%d,%d)", item.words, item.x, item.y))
                            -- 点击 y-30 位置
                            --randomTap(item.x, item.y - 50, 5, 5, "点击第一个匹配收藏项")
                            sleep(1500)
                            -- 长按唤醒菜单
                            longTap(item.x, item.y - 50, 500)
                            sleep(1500)
                            -- 查找并点击"多选"
                            local multiSelectOk = false
                            for retry = 1, 5 do
                                local multiPos = ocr_start(134,213,907,1902, "多选")
                                if multiPos then
                                    randomTap(multiPos[1], multiPos[2], 5, 3, "点击多选")
                                    print("步骤2: 点击多选成功")
                                    multiSelectOk = true
                                    sleep(1500)
                                    break
                                end
                                sleep(500)
                            end

                            if multiSelectOk then
                                firstFound = true
                                -- 标记第一个已找到，从待匹配列表移除
                                table.remove(pendingSegments, j)
                                break
                            else
                                print("步骤2: 未找到多选选项，重试")
                                -- 点空白处关闭菜单
                                randomTap(100, 100, 10, 10, "关闭菜单")
                                sleep(1000)
                            end
                        end
                    end
                end
                if firstFound then break end
            end
        end

        if firstFound then break end
    end

    if not firstFound then
        print("步骤2失败: 无法找到第一个匹配收藏项")
        return false
    end

    -- 2.2 继续查找并选中其余匹配项（已进入多选模式）
    if #pendingSegments > 0 then
        print(string.format("步骤2.2: 继续选中剩余 %d 个内容片段", #pendingSegments))

        local selectedCount = 1  -- 第一个已选中

        for scroll = 0, maxScroll do
            if scroll > 0 then
                randomSwipe(500, 1400, 500, 500, 800)
                sleep(1500)
            end

            local textBlocks = ocr_start_with_boxes(84, 200, 940, 1800)
            if textBlocks and #textBlocks > 0 then
                for _, item in ipairs(textBlocks) do
                    item.x = math.floor(item.x or 0)
                    item.y = math.floor(item.y or 0)
                end
                table.sort(textBlocks, function(a, b) return a.y < b.y end)

                local matchedAny = false
                for _, item in ipairs(textBlocks) do
                    if item.words then
                        for j = #pendingSegments, 1, -1 do
                            local seg = pendingSegments[j]
                            if string.find(item.words, seg, 1, true) or string.find(seg, item.words, 1, true) then
                                print(string.format("步骤2.2: 匹配到 '%s' pos=(%d,%d)", item.words, item.x, item.y))
                                randomTap(item.x, item.y, 5, 5, "选中收藏项")
                                sleep(800)
                                selectedCount = selectedCount + 1
                                table.remove(pendingSegments, j)
                                matchedAny = true
                            end
                        end
                    end
                end

                if #pendingSegments == 0 then
                    print(string.format("步骤2.2: 所有内容片段已选中，共 %d 个", selectedCount))
                    break
                end
            end
        end

        if #pendingSegments > 0 then
            print(string.format("步骤2.2: 剩余 %d 个未找到，继续流程", #pendingSegments))
        end
    end

    print("========== 步骤2完成 ==========")
    return true
end

-- ==================== 步骤3: 点击转发按钮 ====================
-- 在区域查找 forward_btn.png，点击 x+26, y+30
-- @return boolean 是否成功点击转发
local function step3_clickForward()
    print("========== 步骤3: 点击转发按钮 ==========")

    for retry = 1, 5 do
        local idx, fx, fy = findImage(155, 1774, 395, 1938, "forward_btn.png", 0.8)
        if idx ~= -1 then
            local tx = fx + 26
            local ty = fy + 30
            randomTap(tx, ty, 5, 5, "点击转发按钮")
            print(string.format("步骤3: 点击转发按钮 pos=(%d,%d)", tx, ty))
            sleep(1500)

            -- 验证：检查相同位置是否还存在 forward_btn.png（存在说明前一次点击没生效）
            local idx2 = findImage(155, 1774, 395, 1938, "forward_btn.png", 0.8)
            if idx2 ~= -1 then
                print("步骤3: 转发按钮仍存在，再次点击")
                randomTap(tx, ty, 5, 5, "再次点击转发")
                sleep(1500)
            end

            print("========== 步骤3完成 ==========")
            return true
        end
        print("步骤3: 第" .. retry .. "次未找到转发按钮，等待重试")
        sleep(1000)
    end

    print("步骤3失败: 无法找到转发按钮")
    return false
end

-- ==================== 发送失败回退导航 ====================
-- 发送后检测到"选择联系人"说明未选中任何人，逐层回退到微信列表
local function recoverAfterEmptySend()
    print("步骤4.6: 回退导航 - 开始")

    -- a. 检测 wx_detail_back.png → 点击返回
    local backIdx, backX, backY = findImage(88,199,195,317, "wx_detail_back.png", 0.9)
    if backIdx ~= -1 then
        print("步骤4.6a: 找到返回图片，点击返回")
        randomTap(backX, backY, 5, 5, "点击返回(wx_detail_back)")
        sleep(1000)
    else
        -- b. 检测"取消"并点击两次
        print("步骤4.6b: 未找到返回图片，检测取消")
        local cancelPos = ocr_start(88,199,195,317, "取消")
        if cancelPos then
            randomTap(cancelPos[1], cancelPos[2], 5, 5, "点击取消(第1次)")
            sleep(1000)
            randomTap(cancelPos[1], cancelPos[2], 5, 5, "点击取消(第2次)")
            sleep(1000)
        end
    end

    -- c. 检测并点击"取消"
    print("步骤4.6c: 检测取消按钮")
    for retry = 1, 3 do
        local cancelPos2 = ocr_start(815,216,951,308, "取消")
        if cancelPos2 then
            randomTap(cancelPos2[1], cancelPos2[2], 5, 5, "点击取消")
            sleep(1000)
            break
        end
        sleep(500)
    end

    -- d. 再次检测 wx_detail_back.png
    local backIdx2, backX2, backY2 = findImage(88,199,195,317, "wx_detail_back.png", 0.9)
    if backIdx2 ~= -1 then
        print("步骤4.6d: 找到返回图片，点击返回")
        randomTap(backX2, backY2, 5, 5, "点击返回(wx_detail_back)")
        sleep(1000)
    end

    -- e. 验证已回到"我"页面
    print("步骤4.6e: 验证回到'我'页面")
    for retry = 1, 5 do
        local svc = ocr_start(101,617,902,928, "服务")
        local fav = ocr_start(101,617,902,928, "收藏")
        if svc or fav then
            print("已回到'我'页面")
            break
        end
        sleep(500)
    end

    -- f. 点击底部"微信"tab 回到微信列表
    print("步骤4.6f: 点击微信Tab")
    local wxTab = ocr_start(102,1755,288,1979, "微信")
    if wxTab then
        randomTap(wxTab[1], wxTab[2], 5, 5, "点击微信Tab")
        sleep(1000)
    end

    print("步骤4.6: 回退导航 - 完成")
end

-- ==================== 步骤4: 选择联系人并发送 ====================
-- 多选 → 从通讯录选择 → 勾选最多9个联系人 → 完成 → 发送
-- @param records 待发送记录列表 [{phone, msg, id, ...}]
-- @return selected_ids 被勾选的记录ID列表
local function step4_selectContactsAndSend(records)
    print("========== 步骤4: 选择联系人并发送 ==========")

    if not records or #records == 0 then
        print("步骤4: 无联系人记录")
        return {}
    end

    local maxPerBatch = 9  -- 微信一次最多选9个
    local selectedIds = {}

    print(string.format("步骤4: 待匹配联系人 %d 个，每轮最多选 %d 个", #records, maxPerBatch))

    -- 4.1 查找并点击"多选"
    local multiFound = false
    for retry = 1, 5 do
        local multiPos = ocr_start(712, 213, 961, 354, "多选")
        if multiPos then
            randomTap(multiPos[1], multiPos[2], 5, 3, "点击多选")
            print("步骤4.1: 点击多选成功")
            multiFound = true
            sleep(1500)
            break
        end
        sleep(500)
    end

    if not multiFound then
        print("步骤4.1失败: 未找到多选按钮")
        return {}
    end

    -- 4.2 查找并点击"从通讯录选择"
    local contactSelectFound = false
    for retry = 1, 5 do
        local contactRes = ocr_start(658, 786, 954, 953, "从通讯录选择")
        if contactRes then
            randomTap(contactRes[1], contactRes[2], 10, 10, "点击从通讯录选择")
            print("步骤4.2: 点击从通讯录选择成功")
            contactSelectFound = true
            sleep(2000)

            -- 验证：检查相同位置是否还存在"从通讯录选择"（存在说明前一次点击没生效）
            local stillExist = ocr_start(658, 786, 954, 953, "从通讯录选择")
            if stillExist then
                print("步骤4.2: 从通讯录选择仍存在，再次点击")
                randomTap(stillExist[1], stillExist[2], 10, 10, "再次点击从通讯录选择")
                sleep(2000)
            end
            break
        end
        sleep(500)
    end

    if not contactSelectFound then
        print("步骤4.2失败: 未找到从通讯录选择")
        return {}
    end

    -- 4.3 滑动查找并勾选联系人
    -- matchDict 从全部 records 构建（不限于前9个），这样 OCR 扫到的任一待发联系人都能匹配
    print("步骤4.3: 滑动查找并勾选联系人")
    local matchedRecordIds = {}
    local matchDict = {}
    for _, rec in ipairs(records) do
        -- 同时用 msg（名字）和 phone（手机号）作为匹配 key
        if rec.msg and rec.msg ~= "" then
            matchDict[tostring(rec.msg)] = rec.id
        end
        if rec.phone then
            local phoneKey = tostring(rec.phone)
            if not matchDict[phoneKey] then
                matchDict[phoneKey] = rec.id
            end
        end
    end
    print(string.format("步骤4.3: matchDict 包含 %d 个匹配 key", #records))

    local maxSwipe = 15
    local lastOcrSig = ""       -- 上一次 OCR 内容签名
    local stableCount = 0       -- 连续相同次数
    for swipe = 0, maxSwipe do
        if swipe > 0 then
            randomSwipe(500, 1600, 500, 600, 800)
            sleep(1500)
        end

        sleep(1000)
        local ocrResult = ocr_start_with_boxes(304,480,869,1899)
        if ocrResult and #ocrResult > 0 then
            for _, item in ipairs(ocrResult) do
                item.x = math.floor(item.x or 0)
                item.y = math.floor(item.y or 0)
            end

            print(string.format("步骤4.3: 第%d次OCR识别到 %d 个条目", swipe + 1, #ocrResult))
            -- 打印每个文字块内容
            for i, item in ipairs(ocrResult) do
                print(string.format("  [%d] '%s' (x:%d, y:%d)", i, tostring(item.words), item.x, item.y))
            end

            -- 检测是否已滑到列表底部（连续2次 OCR 内容完全相同）
            local currSig = ""
            for _, item in ipairs(ocrResult) do
                currSig = currSig .. (item.words or "") .. "|"
            end
            if swipe > 0 and currSig == lastOcrSig then
                stableCount = stableCount + 1
                if stableCount >= 2 then
                    print(string.format("步骤4.3: 连续%d次OCR内容相同，已到列表底部，停止滑动", stableCount + 1))
                    break
                end
            else
                stableCount = 0
            end
            lastOcrSig = currSig

            local stopMatching = false
            for _, item in ipairs(ocrResult) do
                if stopMatching then break end
                local ocrText = item.words or ""
                local ocrX = item.x
                local ocrY = item.y

                for key, recId in pairs(matchDict) do
                    if string.find(ocrText, key, 1, true) or string.find(key, ocrText, 1, true) then
                        print(string.format("步骤4.3: 匹配联系人 %s pos=(%d,%d)", key, ocrX, ocrY))
                        randomTap(ocrX - 100, ocrY, 10, 10, "勾选联系人:" .. key)
                        sleep(500)
                        table.insert(matchedRecordIds, recId)
                        -- 从本地缓存中移除，避免重复匹配
                        matchDict[key] = nil
                        -- 达到上限立即停止，不多选
                        if #matchedRecordIds >= maxPerBatch then
                            stopMatching = true
                            break
                        end
                        break
                    end
                end
            end
        end

        if #matchedRecordIds >= maxPerBatch then
            print(string.format("步骤4.3: 已勾选 %d 个（达上限），停止滑动", #matchedRecordIds))
            break
        end
    end

    selectedIds = matchedRecordIds

    if #selectedIds == 0 then
        print("步骤4.3失败: 未勾选任何联系人")
        return {}
    end

    -- 4.4 点击"完成" → 检测"发送"出现 → 点击"发送"
    print("步骤4.4: 点击完成并等待发送按钮出现")
    local sendOk = false
    for retry = 1, 8 do
        -- 查找并点击"完成"
        local completeRes = ocr_start(710, 195, 980, 344, "完成")
        if completeRes then
            randomTap(completeRes[1], completeRes[2], 3, 3, "点击完成")
            print(string.format("步骤4.4: 第%d次点击完成", retry))
        end
        sleep(2000)

        -- 检测"发送"是否出现
        local sendRes = ocr_start(468,1599,892,1871, "发送")
        if sendRes then
            print("步骤4.5: 检测到发送按钮，点击发送")
            randomTap(sendRes[1], sendRes[2], 5, 5, "点击发送")
            sendOk = true
            sleep(1500)

            -- 检测"发送"是否消失
            local stillExist = ocr_start(468,1599,892,1871, "发送")
            if stillExist then
                print("步骤4.5: 发送按钮仍存在，再次点击")
                randomTap(stillExist[1], stillExist[2], 5, 5, "再次点击发送")
                sleep(1500)
            end
            break
        end
        print(string.format("步骤4.4: 第%d次未检测到发送按钮，重试", retry))
    end

    if not sendOk then
        print("步骤4.4/4.5: 最终未找到发送按钮（可能已发送成功）")
    end

    -- 4.6 发送后验证：检测"选择联系人"判断是否实际选中了人
    if sendOk then
        sleep(2000)
        local emptyCheck = ocr_start(239,207,836,346, "选择联系人")
        if emptyCheck then
            print("步骤4.6: 检测到'选择联系人'，发送未生效（未选中任何联系人）")
            recoverAfterEmptySend()
            print(string.format("========== 步骤4完成: 实际发送 0 个联系人 =========="))
            return {}
        end
    end

    print(string.format("========== 步骤4完成: 已发送 %d 个联系人 ==========", #selectedIds))
    return selectedIds
end

-- ==================== 步骤6: 上划回到收藏页顶部 ====================
-- 两次上划 OCR 相似度 > 90% 认为已到顶部
-- @return boolean
local function step6_scrollToTop()
    print("========== 步骤6: 上划回到收藏页顶部 ==========")

    local lastWords = {}        -- 上一轮的词集合
    local consecutiveStable = 0  -- 连续稳定次数
    for swipe = 1, 12 do
        -- 上划（反向滑动）
        randomSwipe(500, 550, 500, 1400, 800)
        sleep(2500)

        local textBlocks = ocr_start_with_boxes(84, 200, 940, 1800)
        if not textBlocks then textBlocks = {} end

        -- 构建当前词集合
        local currWords = {}
        for _, item in ipairs(textBlocks) do
            if item.words and #item.words >= 2 then
                currWords[item.words] = true
            end
        end

        -- 主检测：顶部关键词（收藏标题 + 搜索/最近使用），命中即确认到顶
        local hasTitle = currWords["收藏"] or false
        local hasTopTag = currWords["搜索"] or currWords["最近使用"] or currWords["小程序"] or currWords["图片与视频"] or false
        if hasTitle and hasTopTag then
            print(string.format("步骤6: 第%d次上划，检测到顶部标记词，已到达顶部", swipe))
            return true
        end

        -- 辅助检测：词级别相似度（两轮 OCR 内容对比）
        if #lastWords > 0 then
            local matchCount = 0
            local totalPrev = 0
            for w, _ in pairs(lastWords) do
                totalPrev = totalPrev + 1
                if currWords[w] then
                    matchCount = matchCount + 1
                end
            end
            local similarity = totalPrev > 0 and (matchCount / totalPrev) or 0
            print(string.format("步骤6: 第%d次上划，词相似度=%.2f (匹配%d/%d)", swipe, similarity, matchCount, totalPrev))

            if similarity >= 0.75 then
                consecutiveStable = consecutiveStable + 1
                if consecutiveStable >= 2 then
                    print("步骤6: 连续稳定，已到达顶部")
                    return true
                end
            else
                consecutiveStable = 0
            end
        end

        -- 保存当前词集合用于下轮比较
        lastWords = {}
        for w, _ in pairs(currWords) do
            lastWords[w] = true
        end
    end

    print("步骤6: 达到最大上划次数，视为已到顶部")
    return true
end

-- ==================== 收藏群发流程主函数 ====================
-- @param options table {
--   robot_code: 机器人编码
--   channel_num: 通道编号
--   task_data: /api/mass_send/task 返回的 data 对象
--   records: 联系人记录列表 [{phone, msg, id, ...}]
-- }
-- @return boolean 是否成功
function M.run(options)
    options = options or {}

    local robot_code = options.robot_code or ""
    local channel_num = options.channel_num or 0
    local task_data = options.task_data
    local records = options.records or {}

    print("========== 开始收藏群发流程(type=3) ==========")
    print(string.format("robot_code: %s, channel_num: %d", robot_code, channel_num))

    if not task_data then
        print("收藏群发流程: task_data为空，流程中断")
        return false
    end

    print(string.format("任务名称: %s, 联系人数量: %d", task_data.task_name or "", #records))

    if #records == 0 then
        print("收藏群发流程: 无待发送联系人，流程结束")
        return false
    end

    -- 解析 template_contents 获取 content_segment 列表
    local templateContents = task_data.template_contents or {}
    print(string.format("模板内容片段数: %d", #templateContents))

    -- ===== 步骤1: 进入收藏页面 =====
    if not step1_enterFavorites() then
        print("收藏群发流程: 步骤1失败")
        return false
    end

    -- 本地 records 列表（批量发送过程中逐步移除已发送的）
    local pendingRecords = {}
    for _, rec in ipairs(records) do
        pendingRecords[#pendingRecords + 1] = rec
    end

    local allSelectedIds = {}
    local roundCount = 0
    local maxRounds = math.ceil(#records / 9) + 3  -- 保险上限

    while #pendingRecords > 0 and roundCount < maxRounds do
        roundCount = roundCount + 1
        print(string.format("\n===== 第 %d 轮发送 =====", roundCount))

        -- ===== 步骤2: 查找并选中收藏内容（每轮都需要重新选中） =====
        if not step2_selectFavoriteContents(templateContents) then
            print("收藏群发流程: 步骤2失败")
            break
        end

        -- ===== 步骤3: 点击转发按钮 =====
        if not step3_clickForward() then
            print("收藏群发流程: 步骤3失败")
            break
        end

        -- ===== 步骤4: 选择联系人并发送 =====
        local selectedIds = step4_selectContactsAndSend(pendingRecords)
        if #selectedIds == 0 then
            print("收藏群发流程: 列表匹配完成，无更多联系人可选")
            break
        end

        -- 将已发送的ID加入总列表
        for _, id in ipairs(selectedIds) do
            table.insert(allSelectedIds, id)
        end

        -- ===== 步骤5: 更新发送状态 =====
        print(string.format("步骤5: 更新 %d 条记录发送状态", #selectedIds))
        local statusIds = {}
        for _, id in ipairs(selectedIds) do
            table.insert(statusIds, tostring(id))
        end
        local records = {}
        for _, id in ipairs(selectedIds) do
            table.insert(records, {id = tonumber(id), status = 1})
        end
        mass_send.updateMassSendRecordStatus(records, robot_code, channel_num)
        sleep(1000)

        -- 从本地 records 列表中移除已发送的
        local newPending = {}
        for _, rec in ipairs(pendingRecords) do
            local removed = false
            for _, sid in ipairs(selectedIds) do
                if rec.id == sid then
                    removed = true
                    break
                end
            end
            if not removed then
                newPending[#newPending + 1] = rec
            end
        end
        pendingRecords = newPending
        print(string.format("剩余待发送: %d 个", #pendingRecords))

        if #pendingRecords == 0 then
            print("所有联系人已发送完毕")
            -- 人员已全部匹配，用累计ID列表更新
            local finalRecords = {}
            for _, id in ipairs(allSelectedIds) do
                table.insert(finalRecords, {id = tonumber(id), status = 1})
            end
            mass_send.updateMassSendRecordStatus(finalRecords, robot_code, channel_num)
            -- 跳出循环，不再进入收藏选中流程
            break
        end

        -- 本批次选中不足9人，说明通讯录列表已遍历完毕，剩余人员不可达
        if #selectedIds < 9 then
            print(string.format("最后一次选中 %d 人（不足9人），列表匹配完成，剩余 %d 人未匹配视为完成", #selectedIds, #pendingRecords))
            local finalRecords = {}
            for _, id in ipairs(allSelectedIds) do
                table.insert(finalRecords, {id = tonumber(id), status = 1})
            end
            mass_send.updateMassSendRecordStatus(finalRecords, robot_code, channel_num)
            break
        end

        -- ===== 步骤6: 上划回到收藏页顶部（后续轮次用） =====
        -- 非首轮发送后，回到收藏页重新选中内容再转发
        step6_scrollToTop()
        sleep(1000)
    end

    -- ===== 步骤8: 回到微信列表 =====
    print("========== 步骤8: 回到微信列表 ==========")
    for retry = 1, 10 do
        -- 检测 wx_detail_back.png，存在则点击返回
        local backIdx, backX, backY = findImage(100,232,172,308, "wx_detail_back.png", 0.9)
        if backIdx ~= -1 then
            print(string.format("步骤8: 第%d次检测到返回图片，点击返回", retry))
            randomTap(backX+6, backY+10, 1, 1, "点击返回(wx_detail_back)")
            sleep(1000)
        else
            -- 检测是否在"我"页面
            local svc = ocr_start(101,617,902,928, "服务")
            local fav = ocr_start(101,617,902,928, "收藏")
            if svc or fav then
                print(string.format("步骤8: 第%d次检测到'我'页面，点击微信Tab", retry))
                local wxTab = ocr_start(102,1755,288,1979, "微信")
                if wxTab then
                    randomTap(wxTab[1], wxTab[2], 5, 5, "点击微信Tab")
                    sleep(1000)
                end
            else
                -- 检测是否已在微信列表				
                local wxTitle = ocr_start(77,1739,378,1962, "微信")
                if wxTitle then
					randomTap(wxTitle[1],wxTitle[2],1,1,"点击回到微信列表")
                    print("步骤8: 已回到微信列表")
                    break
                end
            end
        end
        sleep(500)
    end

    print(string.format("========== 收藏群发流程结束: 成功 %d 条 ==========", #allSelectedIds))
    return #allSelectedIds > 0
end

return M
