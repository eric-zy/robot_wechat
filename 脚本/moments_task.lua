-- 朋友圈任务流程模块
-- 从 common.lua 独立出来，处理完整的朋友圈发送流程

local M = {_VERSION = 0.1}

-- 引用（由外部传入或直接 require）
local C
local config
local Req

-- 初始化依赖
function M.init(_C, _config, _Req)
    C = _C or require("common")
    config = _config or require("config")
    Req = _Req or require("requests")
end

-- 确保依赖已加载
local function ensureDeps()
    if not C then C = require("common") end
    if not config then config = require("config") end
    if not Req then Req = require("requests") end
end

-- ==================== 步骤1：读取朋友圈任务 ====================
-- GET /device/moments/tasks/read?robot_code=xxx&channel_num=1
-- @param robot_code 机器人编号
-- @param channel_num 通道编号
-- @return task_data {task_id, task_name, task_status, total_count, remaining_count, contents, ...} 或 nil
function M.readMomentsTask(robot_code, channel_num)
    ensureDeps()

    if not robot_code or not channel_num then
        print("readMomentsTask: robot_code或channel_num为空")
        return nil
    end

    local url = config.moments_task_read_url .. "?robot_code=" .. tostring(robot_code) .. "&channel_num=" .. tostring(channel_num)
    print("调用读取朋友圈任务接口: " .. url)

    local http = require("socket.http")
    local ltn12 = require("ltn12")

    local response_body = {}
    local res, code = http.request{
        url = url,
        method = "GET",
        sink = ltn12.sink.table(response_body),
    }

    if not res or code ~= 200 then
        print("读取朋友圈任务失败, HTTP状态码: " .. tostring(code))
        return nil
    end

    local body = table.concat(response_body)
    print("读取朋友圈任务接口返回: " .. body)

    local ok, decoded = pcall(jsonLib.decode, body)
    if not ok then
        print("解析朋友圈任务响应失败")
        return nil
    end

    if decoded and decoded.success and decoded.data then
        local data = decoded.data

        -- 检查 data 是否为有效 table（null/userdata 会被 decoded.data 判真但不可索引）
        if type(data) ~= "table" or not data.id then
            print("读取朋友圈任务: 无待执行任务 (data为空)")
            return nil
        end

        local contents = data.contents or {}

        -- 按 sort 字段排序确保顺序正确
        table.sort(contents, function(a, b)
            return (tonumber(a.sort) or 0) < (tonumber(b.sort) or 0)
        end)

        local totalCount = #contents
        print(string.format("获取到朋友圈任务: task_id=%s, task_name=%s, 内容%d条",
            tostring(data.id), tostring(data.task_name or ""), totalCount))
        return {
            task_id = tonumber(data.id),
            task_name = data.task_name,
            task_status = data.task_status,
            contents = contents,  -- 已按sort排序的内容列表 [{content_type, content, ...}]
        }
    else
        print("读取朋友圈任务返回失败或无数据: " .. tostring(decoded and decoded.message))
    end

    return nil
end

-- ==================== 步骤3：发送朋友圈内容到ID ====================
-- POST /device/moments/send 参数 {task_id: int}
-- 每次发送2条，循环调用直到 remaining_count=0
-- @param task_id 任务ID
-- @return results 所有发送结果组成的数组 [{type, content, seq, ...}] 或 nil
function M.sendMomentsContent(task_id)
    ensureDeps()

    if not task_id then
        print("sendMomentsContent: task_id为空")
        return nil
    end

    local allResults = {}
    local maxLoops = 50  -- 安全限制，防止无限循环
    local loopCount = 0

    while loopCount < maxLoops do
        loopCount = loopCount + 1

        local url = config.moments_send_url
        local post_data = jsonLib.encode({task_id = task_id})

        print(string.format("调用发送朋友圈内容接口 [第%d次]: %s", loopCount, url))
        print("参数: " .. post_data)

        local http = require("socket.http")
        local ltn12 = require("ltn12")

        local response_body = {}
        local res, code = http.request{
            url = url,
            method = "POST",
            sink = ltn12.sink.table(response_body),
            headers = {
                ["Content-Type"] = "application/json",
                ["Content-Length"] = tostring(#post_data),
            },
            source = ltn12.source.string(post_data),
        }

        if not res or code ~= 200 then
            print("发送朋友圈内容失败, HTTP状态码: " .. tostring(code))
            return #allResults > 0 and allResults or nil
        end

        local body = table.concat(response_body)
        print("发送朋友圈内容接口返回: " .. body)

        local ok, decoded = pcall(jsonLib.decode, body)
        if not ok then
            print("解析发送朋友圈内容响应失败")
            return #allResults > 0 and allResults or nil
        end

        if not decoded or not decoded.success then
            print("发送朋友圈内容返回失败: " .. tostring(decoded and decoded.message))
            return #allResults > 0 and allResults or nil
        end

        -- 收集本次返回的结果
        local data = decoded.data
        if data and data.results then
            for _, item in ipairs(data.results) do
                table.insert(allResults, item)
            end
            print(string.format("  本次获取到%d条内容，累计%d条", #data.results, #allResults))
        end

        -- 检查 remaining_count
        local remaining = tonumber(data and data.remaining_count) or 0
        print(string.format("  剩余待发送内容: %d", remaining))

        if remaining <= 0 then
            print("所有内容已发送完毕，退出循环")
            break
        end

        sleep(500)
    end

    if loopCount >= maxLoops then
        print(string.format("警告：发送循环达到最大次数限制(%d)，强制退出", maxLoops))
    end

    return #allResults > 0 and allResults or nil
end

-- ==================== 步骤4：处理图片消息 ====================
-- 打开图片预览 → 点击三点菜单 → "保存到"（重试直到消失） → 退出预览
-- @return boolean 是否成功
function M.handleImageMessage()
    ensureDeps()
    sleep(500)

    -- 1. 点击图片区域打开预览（点击当前图片所在区域）
    --    消息气泡通常在屏幕右侧，点击中间区域打开预览
    --randomTap(500, 1000, 100, 100, "点击图片消息打开预览")
    --sleep(1500)

    -- 2. 打开选项栏（三点菜单，通常在右上角）
    randomTap(869,1834, 5, 5, "打开选项栏（三点菜单）")
    sleep(1500)

    -- 3. 查找"保存到"并点击（点击后检测是否仍存在，存在则再次点击直到消失）
    local saveSuccess = false
    local maxRetry = 8
    for retry = 1, maxRetry do
		sleep(1000)
        local savePos = ocr_start(279, 1543, 528, 1826, "保存到")
        if savePos then
            randomTap(savePos[1], savePos[2] - 20, 5, 5, "保存到手机")
            print(string.format("handleImageMessage: 第%d次点击保存到手机", retry))
            sleep(1000)

            -- 点击后再检测，如果"保存到"仍存在则继续下一轮重试
            local recheck = ocr_start(279, 1543, 528, 1826, "保存到")
            if not recheck then
                print("handleImageMessage: 保存到手机点击成功（已消失）")
                saveSuccess = true
                break
            end
            print("handleImageMessage: 保存到手机仍存在，继续重试")
        else
            print(string.format("handleImageMessage: 第%d次未找到保存到手机按钮", retry))
            -- 重新点击三点菜单尝试
            randomTap(873, 1829, 5, 5, "重新打开选项栏")
            sleep(1500)
        end
    end

    -- 最终确认：保存到按钮是否已消失
    if not saveSuccess then
        local finalCheck = ocr_start(279, 1543, 528, 1826, "保存到")
        if finalCheck then
            print("handleImageMessage: 保存到手机选项仍然存在，可能未成功")
        end
    end
    sleep(2000)

    -- 4. 退出预览（点击屏幕中间区域）
    for exitRetry = 1, 5 do
        randomTap(467, 1063, 5, 5, "退出图片预览")
        sleep(1000)

        -- 检测是否回到聊天界面（检测输入框或ID名）
        local backToChat = ocr_start(230, 207, 858, 325, config.id_ai_project_config.name) or
                           ocr_start(400, 1720, 600, 1800, "发消息")
        if backToChat then
            print("handleImageMessage: 已退出预览，回到聊天界面")
            return true
        end

        print(string.format("handleImageMessage: 第%d次未回到聊天界面，继续尝试退出", exitRetry))
    end

    print("handleImageMessage: 退出预览超时")
    return false
end

-- ==================== 步骤4：处理视频消息 ====================
-- 保存逻辑同图片，但退出预览方式不同
-- @return boolean 是否成功
function M.handleVideoMessage()
    ensureDeps()
    sleep(500)

    -- 1. 打开选项栏（三点菜单）
    randomTap(869, 1834, 5, 5, "打开选项栏（三点菜单）")
    sleep(1500)

    -- 2. 查找"保存到"并点击（点击后检测是否仍存在，存在则再次点击直到消失）
    local saveSuccess = false
    local maxRetry = 8
    for retry = 1, maxRetry do
        sleep(1000)
        local savePos = ocr_start(279, 1543, 528, 1826, "保存到")
        if savePos then
            randomTap(savePos[1], savePos[2] - 20, 5, 5, "保存到手机")
            print(string.format("handleVideoMessage: 第%d次点击保存到手机", retry))
            sleep(1000)

            local recheck = ocr_start(279, 1543, 528, 1826, "保存到")
            if not recheck then
                print("handleVideoMessage: 保存到手机点击成功（已消失）")
                saveSuccess = true
                break
            end
            print("handleVideoMessage: 保存到手机仍存在，继续重试")
        else
            print(string.format("handleVideoMessage: 第%d次未找到保存到手机按钮", retry))
            randomTap(873, 1829, 5, 5, "重新打开选项栏")
            sleep(1500)
        end
    end

    if not saveSuccess then
        local finalCheck = ocr_start(279, 1543, 528, 1826, "保存到")
        if finalCheck then
            print("handleVideoMessage: 保存到手机选项仍然存在，可能未成功")
        end
    end
    sleep(2000)

    -- 3. 退出视频预览（先点中间 → 再点返回按钮）
    for exitRetry = 1, 5 do
        -- 先点击屏幕中间退出全屏
        randomTap(467, 1063, 5, 5, "点击视频中间退出全屏")
        sleep(1000)
        -- 再点击左上角返回按钮退出预览
        randomTap(155, 1833, 5, 5, "点击返回退出视频预览")
        sleep(1000)

        -- 检测是否回到聊天界面
        local backToChat = ocr_start(230, 207, 858, 325, config.id_ai_project_config.name) or
                           ocr_start(400, 1720, 600, 1800, "发消息")
        if backToChat then
            print("handleVideoMessage: 已退出预览，回到聊天界面")
            return true
        end

        print(string.format("handleVideoMessage: 第%d次未回到聊天界面，继续尝试退出", exitRetry))
    end

    print("handleVideoMessage: 退出预览超时")
    return false
end

-- ==================== 步骤4：处理文字消息（长按复制） ====================
-- @param msg 消息对象 {x, y}
-- @return boolean 是否成功复制
function M.handleTextMessage(msg)
    ensureDeps()

    if not msg or not msg.x or not msg.y then
        print("handleTextMessage: 消息坐标为空")
        return false
    end

    local tapX = msg.x + 200
    local tapY = msg.y + 60
    print(string.format("handleTextMessage: 长按复制消息 (x:%d, y:%d)", tapX, tapY))

    longTap(tapX, tapY)
    sleep(1000)

    -- 查找复制按钮（图片匹配 + OCR兜底）
    local copySuccess = false
    for _ = 1, 3 do
        local idx, copyX, copyY = findImage(0, 0, 0, 0,
            "id_msg_copy2.png|id_msg_copy1.png|id_msg_copy.png|id_msg_copy3.png|id_msg_copy4.png", 0.8)
        if idx ~= -1 then
            randomTap(copyX, copyY, 10, 10, "点击复制")
            sleep(1000)
            copySuccess = true
            break
        end

        -- OCR 兜底：查找"复制"文字
        local copyText = ocr_start(79, 259, 353, 1762, "复制")
        if copyText then
            randomTap(copyText[1], copyText[2], 30, 30, "OCR点击复制")
            sleep(1000)
            copySuccess = true
            break
        end

        sleep(300)
    end

    if copySuccess then
        print("handleTextMessage: 复制成功")
    else
        print("handleTextMessage: 复制失败")
    end

    return copySuccess
end

-- ==================== 分批处理ID中刚发送的消息 ====================
-- 每批send后立即调用，处理该批次在ID聊天中的消息
-- @param batchResults 本批次发送结果数组 [{type, content_id, content_type, sort, ...}]
-- @param batchCount 本批次发送数量（用于定位ID中最新的N条消息）
function M.processIDBatch(batchResults, batchCount)
    ensureDeps()

    if not batchResults or #batchResults == 0 then
        print("processIDBatch: 无待处理消息")
        return
    end

    local n = batchCount or #batchResults
    print(string.format("processIDBatch: 处理本批次%d条消息", n))

    -- 等待消息到达
    sleep(1500)

    -- 获取ID聊天中最新的消息列表
    local msgs = nil
    for msgRetry = 1, 5 do
        msgs = C.getIDMessages()
        if msgs and #msgs >= n then
            break
        end
        print(string.format("ID消息不足, 获取到%d条, 需要%d条, 重试第%d次",
            msgs and #msgs or 0, n, msgRetry))

        -- 第3次：退出并重新进入聊天（强制重新加载）
        if msgRetry == 3 then
            print("processIDBatch: 刷新无效，退出并重新进入聊天")
            C.backToIDMessageList()
            sleep(800)
            if C.searchIDOptimize(config.id_ai_project_config.name, false) then
                print("processIDBatch: 重新进入聊天成功")
                sleep(2000)
                msgs = C.getIDMessages()
                if msgs and #msgs >= n then
                    break
                end
            else
                print("processIDBatch: 重新进入聊天失败")
            end
        end
        sleep(1000)
    end

    if not msgs or #msgs < n then
        print(string.format("processIDBatch: 消息不足, 获取到%d条, 需要%d条",
            msgs and #msgs or 0, n))
        -- 有多少处理多少
    end

    -- 按 y 坐标排序（从上到下）
    if msgs and #msgs > 0 then
        msgs = arrSortByY(msgs)
    else
        print("processIDBatch: 无法获取ID消息")
        return
    end

    -- 取最新的 n 条消息
    local startIdx = math.max(1, #msgs - n + 1)
    print(string.format("processIDBatch: 消息总数%d条, 取最新%d条(索引%d-%d)",
        #msgs, n, startIdx, #msgs))

    for i = 1, math.min(n, #msgs - startIdx + 1) do
        local msgIdx = startIdx + i - 1
        if msgIdx > #msgs then break end

        local msg = msgs[msgIdx]
        -- 取对应 batchResults 项
        local resultItem = batchResults[i]
        local rtype = resultItem and resultItem.type or ""

        print(string.format("processIDBatch: [%d/%d] type=%s, pos=(%d,%d)",
            i, n, rtype, msg.x, msg.y))

        if rtype == "image" then
            -- 图片：点击消息 → 预览 → 三点菜单 → "保存到" → 退出
            print("  处理图片消息...")
            randomTap(msg.x + 300, msg.y + 100, 10, 10, "点击图片消息")
            sleep(1000)
            M.handleImageMessage()
        elseif rtype == "video" then
            -- 视频：同样保存处理
            print("  处理视频消息...")
            randomTap(msg.x + 300, msg.y + 100, 10, 10, "点击视频消息")
            sleep(1000)
            M.handleVideoMessage()
        elseif rtype == "text" then
            -- 文字：长按复制
            print("  处理文字消息...")
            M.handleTextMessage(msg)
        else
            print(string.format("  未知类型 '%s'，跳过", rtype))
        end

        sleep(800)
    end

    print("processIDBatch: 本批次处理完成")
end

-- ==================== 步骤5+6：完整朋友圈发布流程 ====================
-- 回到ID列表 → 桌面 → 微信 → "我" → "朋友圈" → 相机 → "从相册选择"
-- → 根据contents选图 → "完成" → 文字粘贴 → "发表" → 返回 → 微信列表
-- @param taskData 任务数据（含 task_id, contents 等）
-- @return boolean 是否成功
function M.publishToMoments(taskData)
    ensureDeps()

    print("========== 开始朋友圈发布流程 ==========")

    local taskId = taskData.task_id
    local contents = taskData.contents or {}

    -- 统计图片/视频/文字数量
    local imageCount = 0
    local videoCount = 0
    local hasText = false
    for _, item in ipairs(contents) do
        local ctype = tonumber(item.content_type) or 0
        if ctype == 2 then
            imageCount = imageCount + 1
        elseif ctype == 3 then
            videoCount = videoCount + 1
        elseif ctype == 1 then
            hasText = true
        end
    end
    print(string.format("publishToMoments: 图片%d张, 视频%d个, 文字:%s",
        imageCount, videoCount, hasText and "有" or "无"))

    -- ====== 5a. 回退到ID消息列表 ======
    print("步骤5a：回退到ID消息列表")
    C.backToIDMessageList()
    sleep(800)

    -- ====== 5b. 回到桌面 → 打开微信 ======
    print("步骤5b：回到桌面 → 打开微信")
    C.backToHomeWithCheck(3)
    sleep(500)
    C.openWeChatOptimize(1)
    sleep(2000)

    -- ====== 5c+5d. 点击"我"→"朋友圈"（外层可重试） ======
    local momentsEntry = nil
    for outerRetry = 1, 3 do
        -- 5c. 点击"我"标签
        print(string.format("步骤5c：点击'我'标签 (第%d次)", outerRetry))
        local meTab = nil
        for _ = 1, 3 do
            meTab = ocr_start(660, 1780, 933, 1934, "我")
            if meTab then
                randomTap(meTab[1], meTab[2]-10, 10, 10, "点击'我'")
                break
            end
            randomTap(860, 1786, 10, 10, "点击'我'(默认位置)")
            sleep(800)
        end
        sleep(1500)

        -- 5d. 点击"朋友圈"
        print("步骤5d：点击'朋友圈'")
        for retry = 1, 3 do
            sleep(1000)
            momentsEntry = ocr_start(107, 403, 938, 987, "朋友圈")
            if momentsEntry then
                randomTap(momentsEntry[1], momentsEntry[2], 10, 10, "朋友圈")
                break
            end
            print("未找到朋友圈入口，重试第" .. retry .. "次...")
            sleep(800)
        end

        if momentsEntry then
            break  -- 找到了，退出外层循环
        end
        print("未找到朋友圈入口，重新点击'我'标签" .. " (外层重试" .. outerRetry .. "/3)")
    end

    if not momentsEntry then
        print("未找到朋友圈入口")
        return false
    end
    sleep(1500)
	
	-- ====== 5d.1 点击我的朋友圈 ======
	print("步骤5d.1：查找并点击我的朋友圈")
	 for retry = 1, 3 do
		sleep(1000)
		local myMomentEntry = ocr_start(570,401,940,576,"我的朋友圈")

        if myMomentEntry then
            randomTap(myMomentEntry[1], myMomentEntry[2], 10, 10, "点击我的朋友圈")
            break
        end
        print("未找到朋友圈入口，重试第" .. retry .. "次...")
        sleep(800)
    end
    if not momentsEntry then
        print("未找到朋友圈入口")
        return false
    end

	

    -- ====== 5e. 点击右上角相机图标 ======
    print("步骤5e：点击右上角相机图标")
	sleep(2000)
    local cameraIdx, cameraX, cameraY = findImage(194,1003,600,1315, "moments_camera.png|wx_camera.png", 0.8)
    if cameraIdx ~= -1 then
        randomTap(cameraX, cameraY, 5, 5, "点击相机图标")
    else
        randomTap(361,1192, 10, 10, "点击相机图标(固定位置)")
    end
    sleep(1500)

    -- ====== 5f. 选择"从相册选择" ======
    print("步骤5f：选择'从相册选择'或'从手机相册选择'")
    local fromAlbum = nil
    for retry = 1, 5 do
        fromAlbum = ocr_start(163,1477,849,1919, "从手机相册选择")
        if not fromAlbum then
            fromAlbum = ocr_start(163,1477,849,1919, "从相册选择")
        end
        if fromAlbum then
            randomTap(fromAlbum[1], fromAlbum[2], 10, 10, "从相册选择")
            sleep(1500)
            break
        end
        print("未找到'从相册选择'，重试第" .. retry .. "次...")
        sleep(800)
    end

    if not fromAlbum then
        print("未找到'从相册选择'选项")
        return false
    end

    -- ====== 5g. 根据contents选择图片/视频 ======
    print("步骤5g：根据contents选择图片/视频")
    local albumCfg = config.moments_album_config
    local clickIdx = 1  -- 当前点击序号（用于定位图片坐标数组）

    -- 先点击所有图片
    for _ = 1, imageCount do
        local pos
        if clickIdx <= #albumCfg.images then
            pos = albumCfg.images[clickIdx]
        else
            pos = albumCfg.images[#albumCfg.images]  -- 超出用最后一个兜底
        end
        print(string.format("  点击第%d张图片: (%d, %d)", clickIdx, pos.x, pos.y))
        randomTap(pos.x, pos.y, 10, 10, "选择图片" .. clickIdx)
        sleep(500)
        clickIdx = clickIdx + 1
    end

    -- 再点击所有视频
    for v = 1, videoCount do
        local pos = albumCfg.video
        print(string.format("  点击第%d个视频: (%d, %d)", v, pos.x, pos.y))
        randomTap(pos.x, pos.y, 10, 10, "选择视频" .. v)
        sleep(500)
        clickIdx = clickIdx + 1
    end

    -- ====== 5h. 点击"完成"（点后检测是否消失，未消失则重试） ======
    print("步骤5h：点击'完成'按钮")
    local foundComplete = false
    for retry = 1, 5 do
        sleep(1500)
        local completePos = ocr_start(723, 1773, 958, 1899, "完成")
        if completePos then
            foundComplete = true
            print(string.format("找到完成按钮: (%d, %d)，点击", completePos[1], completePos[2]))
            randomTap(completePos[1], completePos[2], 10, 10, "点击完成")
            -- 继续循环检测：点击后如果"完成"还在，说明未生效，再点
        else
            if foundComplete then
                print("完成按钮已消失，点击成功")
            else
                print("未找到完成按钮，重试第" .. retry .. "次...")
            end
            break  -- 按钮已消失，退出
        end
    end

    if not foundComplete then
        print("未找到完成按钮")
    end
    sleep(2000)

    -- ====== 5i. 处理文字内容（如果存在） ======
    if hasText then
        print("步骤5i：处理文字内容（这一刻的想法）")

        -- 等1-2秒后查找"这一刻的想法"
        sleep(math.random(1000, 2000))

        local thoughtPos = nil
        for retry = 1, 5 do
            thoughtPos = ocr_start(117, 317, 758, 466, "这一刻的想法")
            if thoughtPos then
                print(string.format("找到'这一刻的想法': (%d, %d)", thoughtPos[1], thoughtPos[2]))
                randomTap(thoughtPos[1], thoughtPos[2], 10, 10, "点击这一刻的想法")
                break
            end
            print(string.format("未找到'这一刻的想法'，重试第%d次(等1s)...", retry))
            sleep(1000)
        end

        if thoughtPos then
            sleep(1000)

            -- 长按唤醒粘贴
            print("长按唤醒粘贴...")
            longTap(thoughtPos[1], thoughtPos[2])
            sleep(1500)

            -- 查找粘贴位置并点击
            local pasteClicked = false
            for retry = 1, 3 do
                local pastePos = ocr_start(89, 183, 903, 610, "粘贴")
                if pastePos then
                    print(string.format("找到粘贴按钮: (%d, %d)", pastePos[1], pastePos[2]))
                    randomTap(pastePos[1], pastePos[2], 5, 5, "点击粘贴")
                    sleep(1000)
                    pasteClicked = true
                    break
                end
                print("未找到粘贴按钮，重试第" .. retry .. "次...")
                sleep(500)
            end

            if not pasteClicked then
                print("粘贴失败")
            end
        else
            print("未找到'这一刻的想法'，跳过文字粘贴")
        end
    end

    -- ====== 5j. 查找"发表"并点击 ======
    print("步骤5j：查找'发表'按钮")
    sleep(1000)
    local publishPos = nil
    for retry = 1, 5 do
        publishPos = ocr_start(633, 191, 963, 372, "发表")
        if publishPos then
            print(string.format("找到发表按钮: (%d, %d)", publishPos[1], publishPos[2]))
            randomTap(publishPos[1], publishPos[2], 10, 10, "点击发表")
            break
        end
        print("未找到发表按钮，重试第" .. retry .. "次...")
        sleep(800)
    end

    if not publishPos then
        print("未找到发表按钮，可能发布失败")
        return false
    end

    -- ====== 5k. 等待后检测并点击返回图标直到消失 ======
    print("步骤5k：等待返回 → 循环点击返回图标")
    sleep(math.random(1000, 2000))

    local backGoneCount = 0
    for _ = 1, 20 do
        local backIdx, backX, backY = findImage(0, 0, 0, 0, "wx_detail_back.png", 0.9)
        if backIdx ~= -1 then
            print(string.format("找到返回图标: (%d, %d)，点击返回", backX, backY))
            randomTap(backX, backY, 5, 5, "点击返回图标")
            sleep(1200)
            backGoneCount = 0
        else
            backGoneCount = backGoneCount + 1
            print(string.format("未找到返回图标(第%d次连续检测)", backGoneCount))
            if backGoneCount >= 2 then
                print("返回图标已连续消失2次，退出检测")
                break
            end
            sleep(1000)
        end
    end

    -- ====== 5l. 查找右下角"微信"回到列表 ======
    print("步骤5l：查找右下角'微信'回到列表")
    sleep(500)
    local wxBottomPos = nil
    for retry = 1, 5 do
        wxBottomPos = ocr_start(99, 1784, 387, 1939, "微信")
        if wxBottomPos then
            print(string.format("找到底部微信: (%d, %d)", wxBottomPos[1], wxBottomPos[2]))
            randomTap(wxBottomPos[1], wxBottomPos[2], 5, 5, "点击微信回到列表")
            sleep(1500)
            -- 验证是否回到微信列表
            local wxTitle = ocr_start(300, 204, 797, 320, "微信")
            if wxTitle then
                print("已回到微信列表")
                break
            end
            print("点击底部微信后未检测到列表，重试...")
        else
            -- 兜底：尝试点击"发现"再找"微信"
            local faxian = ocr_start(300, 1784, 650, 1939, "发现")
            if faxian then
                randomTap(faxian[1], faxian[2], 10, 10, "点击发现")
                sleep(1000)
            end
            print("未找到底部微信，重试第" .. retry .. "次...")
        end
        sleep(800)
    end

    -- 再验证一次
    local wxListCheck = ocr_start(300, 204, 797, 320, "微信")
    if not wxListCheck then
        print("警告：可能未回到微信列表")
    end

    -- ====== 步骤6：标记任务完成 ======
    print("步骤6：标记任务完成")
    M.markTaskComplete(taskId, 2)

    print("========== 朋友圈发布流程结束 ==========")
    return true
end

-- ==================== 步骤6：标记任务完成 ====================
-- POST /device/moments/task/status 参数 {task_id: int, task_status: 2}
-- @param task_id 任务ID
-- @param status 任务状态，默认2(完成)
-- @return boolean 是否成功
function M.markTaskComplete(task_id, status)
    ensureDeps()

    status = status or 2
    if not task_id then
        print("markTaskComplete: task_id为空")
        return false
    end

    local url = config.moments_task_status_url
    local post_data = jsonLib.encode({
        task_id = task_id,
        task_status = status
    })

    print("调用标记朋友圈任务完成接口: " .. url)
    print("参数: " .. post_data)

    local http = require("socket.http")
    local ltn12 = require("ltn12")

    local response_body = {}
    local res, code = http.request{
        url = url,
        method = "POST",
        sink = ltn12.sink.table(response_body),
        headers = {
            ["Content-Type"] = "application/json",
            ["Content-Length"] = tostring(#post_data),
        },
        source = ltn12.source.string(post_data),
    }

    if not res or code ~= 200 then
        print("标记朋友圈任务完成失败, HTTP状态码: " .. tostring(code))
        return false
    end

    local body = table.concat(response_body)
    print("标记朋友圈任务完成接口返回: " .. body)

    local ok, decoded = pcall(jsonLib.decode, body)
    if ok and decoded and decoded.success then
        print("朋友圈任务标记完成成功")
        return true
    end

    print("朋友圈任务标记完成失败")
    return false
end

-- ==================== 完整朋友圈任务流程 ====================
-- @param robot_code 机器人编号
-- @param channel_num 通道编号
-- @return string 执行结果描述
function M.run(robot_code, channel_num)
    ensureDeps()

    print("========== 开始执行朋友圈任务流程 ==========")
    print(string.format("robot_code=%s, channel_num=%s",
        tostring(robot_code), tostring(channel_num)))

    -- 步骤1：读取朋友圈任务
    print("\n== 步骤1：读取朋友圈任务 ==")
    local taskData = M.readMomentsTask(robot_code, channel_num)
    if not taskData then
        print("无有效朋友圈任务数据，退出流程")
        return "无有效朋友圈任务"
    end

    local taskId = taskData.task_id
    local contentsCount = taskData.contents and #taskData.contents or 0
    print(string.format("获取到任务: task_id=%s, task_name=%s, 内容%d条",
        tostring(taskId), tostring(taskData.task_name), contentsCount))

    -- 步骤2：确保在微信列表 → 回到桌面 → 打开ID
    print("\n== 步骤2：打开智企ID ==")
    -- 先回到桌面
    C.backToHomeWithCheck(3)
    sleep(500)

    -- 打开ID
    local idOpened = false
    for idRetry = 1, 3 do
        C.openIDOptimize()
        sleep(1000)
        if C.searchIDOptimize(config.id_ai_project_config and config.id_ai_project_config.name or "", false) then
            sleep(1500)
            idOpened = true
            break
        end
        print("打开ID失败，重试第" .. idRetry .. "次...")
    end

    if not idOpened then
        print("打开智企ID失败，退出流程")
        return "打开智企ID失败"
    end

    print("已成功打开ID并进入聊天")

    -- 步骤3+4：分批发送并立即处理（send→process 交错循环）
    print("\n== 步骤3+4：分批发送并处理消息 ==")
    local maxLoops = 50
    local loopCount = 0

    while loopCount < maxLoops do
        loopCount = loopCount + 1

        -- ===== 发送一批 =====
        local url = config.moments_send_url
        local post_data = jsonLib.encode({task_id = taskId})

        print(string.format("发送朋友圈内容 [第%d批]: %s", loopCount, url))
        print("参数: " .. post_data)

        local http = require("socket.http")
        local ltn12 = require("ltn12")

        local response_body = {}
        local res, code = http.request{
            url = url,
            method = "POST",
            sink = ltn12.sink.table(response_body),
            headers = {
                ["Content-Type"] = "application/json",
                ["Content-Length"] = tostring(#post_data),
            },
            source = ltn12.source.string(post_data),
        }

        if not res or code ~= 200 then
            print("发送失败, HTTP状态码: " .. tostring(code))
            M.markTaskComplete(taskId, 2)
            return "发送朋友圈内容失败"
        end

        local body = table.concat(response_body)
        print("发送接口返回: " .. body)

        local ok, decoded = pcall(jsonLib.decode, body)
        if not ok or not decoded or not decoded.success then
            print("发送解析失败: " .. tostring(decoded and decoded.message))
            M.markTaskComplete(taskId, 2)
            return "发送朋友圈内容失败"
        end

        local data = decoded.data
        local batchResults = data.results or {}
        local batchCount = #batchResults

        print(string.format("  本批发送%d条", batchCount))

        -- ===== 立即处理本批次 =====
        if batchCount > 0 then
            print(string.format("  开始处理本批次%d条消息...", batchCount))
            M.processIDBatch(batchResults, batchCount)
        end

        -- 检查是否还有剩余
        local remaining = tonumber(data.remaining_count) or 0
        print(string.format("  剩余待发送: %d", remaining))

        if remaining <= 0 then
            print("所有内容发送并处理完毕")
            break
        end

        sleep(500)
    end

    if loopCount >= maxLoops then
        print(string.format("警告：发送循环达到上限(%d)，强制退出", maxLoops))
    end

    print("步骤3+4完成：内容已分批发送并下载/复制")

    -- 步骤5+6：完整朋友圈发布流程（导航→选图→文字→发表→返回→标记完成）
    print("\n== 步骤5+6：发布朋友圈并标记完成 ==")
    local publishOk = M.publishToMoments(taskData)
    if not publishOk then
        print("朋友圈发布流程失败")
        M.markTaskComplete(taskId, 2)
        return "朋友圈发布流程失败"
    end

    print("========== 朋友圈任务流程执行完毕 ==========")
    return "朋友圈任务流程执行完成"
end

return M
