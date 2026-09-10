-- 初始化微信收藏同步模块
-- 在聊天流程开始前调用，将待同步资源收藏到微信
local M = {_VERSION = 0.1}
local Req = require("requests")
local config = require("config")

-- 模块级变量：保存当前同步的机器人和通道号
local M_robotCode = nil
local M_channelNum = nil

-- URL编码（本地实现，避免依赖common内部函数）
local function urlEncode(s)
    if not s then return "" end
    s = tostring(s)
    s = string.gsub(s, "([^\r])\n", "%1\r\n")
    s = string.gsub(s, "([^%w%-%_%.%~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    return s
end

-- 在聊天流程开始前调用，检查是否有待同步到微信收藏的资源文件
-- @param robot_code 机器人编号
-- @param channel_num 通道号
function M.initFavor(robot_code, channel_num)
    M_robotCode = robot_code
    M_channelNum = channel_num
    print("========== 开始初始化微信收藏同步 ==========")
    print("robot_code:", robot_code, "channel_num:", channel_num)

    -- 请求待同步资源列表
    local res = Req.getPendingSync(robot_code, channel_num)
    if not res or not res.success then
        print("initFavor: 获取待同步资源失败或无数据，跳过")
        return false
    end

    local data = res.data
    -- data为nil/json null(usertype)/空table均视为无数据，跳过同步流程
    if not data or type(data) ~= "table" then
        print("initFavor: 响应data为空，跳过同步")
        return false
    end

    -- API返回的data是单个资源对象，统一包装成数组方便遍历
    local resources
    if data[1] ~= nil then
        resources = data
    else
        resources = {data}
    end

    if not resources or #resources == 0 then
        print("initFavor: 无待同步资源，跳过")
        return false
    end

    print(string.format("initFavor: 获取到 %d 条待同步资源", #resources))

    -- 发送到文件传输助手（收藏前置步骤：确保已在微信群列表中）
    local helperOk = M.sendToFileHelper(robot_code, channel_num)
    if not helperOk then
        print("initFavor: 打开文件传输助手失败，跳过同步")
        return false
    end

    -- 进入微信收藏同步流程
    local syncSuccess = M.doSyncFavorites(resources)

    -- 同步完成后上报已同步的资源ID
    if syncSuccess then
        local syncedIds = {}
        for _, r in ipairs(resources) do
            if r.id then
                table.insert(syncedIds, tonumber(r.id))
            end
        end
        if #syncedIds > 0 then
            local updateRes = Req.updateSyncStatus(robot_code, channel_num, syncedIds)
            print("initFavor: 更新同步状态结果:", updateRes and (updateRes.success and "成功" or "失败") or "请求失败")
        end
    end

    print("========== 初始化微信收藏同步结束 ==========")
    return syncSuccess
end

-- 执行微信收藏同步：遍历资源列表，将每个资源收藏到微信
-- @param resources 待同步的资源列表 [{id, file_name, file_url, type, ...}]
-- @return boolean 是否全部同步成功
function M.doSyncFavorites(resources)
    local total = #resources
    local successCount = 0
    local common = require("common")

    for i, resource in ipairs(resources) do
        print(string.format("doSyncFavorites: [%d/%d] 处理资源 id=%s, name=%s",
            i, total, tostring(resource.id), tostring(resource.resource_name or "")))

        -- 调用/device/resource/send接口将资源及名称发送到ID
        -- resource_channel_id参数取sync_record.id
        local resourceChannelId = nil
        if resource.sync_record then
            resourceChannelId = tonumber(resource.sync_record.id)
        end
        if not resourceChannelId then
            resourceChannelId = tonumber(resource.id) -- 兜底
        end
        if not resourceChannelId then
            print("doSyncFavorites: 缺少resource_channel_id，跳过")
        else
            local sendRes = Req.sendResource(resourceChannelId)
            if not sendRes or not sendRes.success then
                print("doSyncFavorites: 发送资源到ID失败")
            else
                local rtype = tonumber(resource.resource_type) or 0
                if rtype == 1 or rtype == 2 then
                    -- 图片/视频：完整流程 ID保存→微信发送→收藏
                    local ok = M.processMediaResource(sendRes.data, resource)
                    if ok then
                        successCount = successCount + 1
                        print(string.format("doSyncFavorites: [%d/%d] 同步成功", i, total))
                    else
                        print(string.format("doSyncFavorites: [%d/%d] 同步失败", i, total))
                    end
                elseif rtype == 3 then
                    -- 定位：完整流程 ID发送→微信位置→收藏
                    local ok = M.processLocationResource(sendRes.data, resource)
                    if ok then
                        successCount = successCount + 1
                        print(string.format("doSyncFavorites: [%d/%d] 定位同步成功", i, total))
                    else
                        print(string.format("doSyncFavorites: [%d/%d] 定位同步失败", i, total))
                    end
                else
                    -- 小程序等其他类型暂标记成功
                    successCount = successCount + 1
                    print(string.format("doSyncFavorites: [%d/%d] 同步成功(其他类型)", i, total))
                end
            end
        end

        sleep(1000)
    end

    print(string.format("doSyncFavorites: 同步完成，成功 %d/%d", successCount, total))
    return successCount > 0
end

-- 处理媒体资源(图片/视频)完整流程：
-- ID端：打开资源预览→保存到手机→复制文本→回退
-- 微信端（文件传输助手）：发送刚保存的图片→长按→收藏
-- @param sendData /device/resource/send 返回的 data 对象 {im_id, results, resource_type, ...}
-- @param resource 原始资源对象
-- @return boolean 是否成功
function M.processMediaResource(sendData, resource)
    local common = require("common")
    local results = sendData.results
    if not results or #results == 0 then
        print("processMediaResource: results为空")
        return false
    end

    local resultCount = #results
    print(string.format("processMediaResource: results数量=%d", resultCount))

    -- ==================== ID端：处理已发送的资源 ====================

    -- 1. 回到桌面打开ID，搜索"发消息"进入聊天框
    common.backToHomeWithCheck(2)
    sleep(300)
    common.openIDOptimize()
    sleep(1000)
    common.searchIDOptimize(config.id_ai_project_config.name, false)
    sleep(1500)

    -- 2. 获取ID消息列表，取最后resultCount条（第一条是资源文件，第二条是文本名）
    local msgs = common.getIDMessages()
    if not msgs or #msgs < resultCount then
        print(string.format("processMediaResource: ID消息不足, 获取到%d条, 需要%d条",
            msgs and #msgs or 0, resultCount))
        return false
    end

    local mediaMsg = msgs[#msgs - resultCount + 1]
    print(string.format("processMediaResource: 点击第一个资源文件, pos=(%d,%d)", mediaMsg.x, mediaMsg.y))

    -- 3. 点击第一个资源文件展开预览
    randomTap(mediaMsg.x+300, mediaMsg.y+100, 10, 10, "点击资源文件预览")
    sleep(1000)

    -- 4. 打开选项栏
    sleep(500)
    randomTap(869, 1834, 5, 5, "打开选项栏（三点菜单）")
    sleep(1500)

    -- 5. 查找"保存到"并点击（点击后检测是否仍存在，存在则再次点击直到消失）
    local saveSuccess = false
    local maxRetry = 8
    for retry = 1, maxRetry do
        sleep(1000)
        savePos = ocr_start(279, 1543, 528, 1826, "保存到")
        if savePos then
            randomTap(savePos[1], savePos[2] - 20, 5, 5, "保存到手机")
            print(string.format("processMediaResource: 第%d次点击保存到手机", retry))
            sleep(1000)
            -- 点击后再检测，如果"保存到"仍存在则继续下一轮重试
            local recheck = ocr_start(279, 1543, 528, 1826, "保存到")
            if not recheck then
                print("processMediaResource: 保存到手机点击成功（已消失）")
                saveSuccess = true
                break
            end
            print("processMediaResource: 保存到手机仍存在，继续重试")
        else
            print(string.format("processMediaResource: 第%d次未找到保存到手机按钮", retry))
            -- 重新点击三点菜单尝试
            randomTap(873, 1829, 5, 5, "重新打开选项栏")
            sleep(1500)
        end
    end

    -- 最终确认：保存到按钮是否已消失
    if not saveSuccess then
        local finalCheck = ocr_start(279, 1543, 528, 1826, "保存到")
        if finalCheck then
            print("processMediaResource: 保存到手机选项仍然存在，可能未成功")
        end
    end
    sleep(2000)

    -- 6. 退出预览（点击屏幕中间区域，检测回到聊天界面）
    for exitRetry = 1, 5 do
        randomTap(467, 1063, 5, 5, "退出图片预览")
        sleep(1000)

        -- 检测是否回到聊天界面（检测输入框或ID名）
        local backToChat = ocr_start(230, 207, 858, 325, config.id_ai_project_config.name) or
                           ocr_start(400, 1720, 600, 1800, "发消息")
        if backToChat then
            print("processMediaResource: 已退出预览，回到聊天界面")
            break
        end

        print(string.format("processMediaResource: 第%d次未回到聊天界面，继续尝试退出", exitRetry))
    end

    -- 7. 长按第二条消息复制（文本消息，资源名称）
    if resultCount >= 2 then
        local textMsg = msgs[#msgs - resultCount + 2]
        print(string.format("processMediaResource: 长按第二条消息复制, pos=(%d,%d)", textMsg.x, textMsg.y))
        longTap(textMsg.x + 200, textMsg.y + 60)
        sleep(1000)

        local copySuccess = false
        for retry = 1, 3 do
            local idx, copyX, copyY = findImage(0, 0, 0, 0,
                "id_msg_copy2.png|id_msg_copy1.png|id_msg_copy.png|id_msg_copy3.png|id_msg_copy4.png", 0.8)
            if idx ~= -1 then
                randomTap(copyX, copyY, 10, 10, "点击复制")
                sleep(1000)
                copySuccess = true
                break
            end
            sleep(300)
        end
        if not copySuccess then
            print("processMediaResource: 复制消息失败，继续流程")
        end
    end

    -- 8. 回退ID消息列表
    common.backToIDMessageList()
    sleep(500)

    -- ==================== 微信端：发送图片并收藏 ====================

    -- 9. 回到桌面打开微信（当前在文件传输助手聊天界面，只点击一次不校验）
    common.backToHomeWithCheck(2)
    sleep(500)
    common.openWeChatSimple()
    sleep(1500)

    -- 10. 点击+号，按发送图片流程发送第一张图片（刚保存到手机的）
    local albumFound = false
    for retry = 1, 3 do
        -- 检查输入法状态
        local resA = ocr_start(692, 1685, 941, 1897, "换行")
        if resA then
            randomTap(889, 1165, 5, 5, "输入法打开-点击加号")
        else
            randomTap(897, 1821, 5, 5, "输入法关闭-点击加号")
        end
        sleep(1000)

        -- 查找相册按钮
        local album = ocr_start(121, 1432, 340, 1615, "相册")
        if album then
            randomTap(album[1], album[2] - 70, 10, 10, "点击相册")
            albumFound = true
            break
        end
        print(string.format("processMediaResource: 第%d次点击加号未找到相册", retry))
    end
    if not albumFound then
        print("processMediaResource: 未找到相册按钮")
        return false
    end
    sleep(1000)

    -- 选择第一张图片（最新保存的图片，在相册首位）
    randomTap(200, 400, 10, 10, "选择第一张图片")
    sleep(500)

    -- 点击发送
    local sendBtn = ocr_start(735, 1735, 964, 1862, "发送")
    if sendBtn then
        randomTap(sendBtn[1], sendBtn[2], 10, 10, "点击发送")
    else
        randomTap(850, 1794, 10, 10, "固定位置发送")
    end
    sleep(2000)

    -- 11. 发送文字消息（用于后续长按收藏），动态定位上一条消息
    -- 11.1 查找输入框位置，点击打开输入法
    local inputBox = ocr_start(120, 1770, 750, 1870, "")
    if inputBox then
        randomTap(inputBox[1], inputBox[2], 5, 5, "点击输入框")
        print("processMediaResource: 找到输入框并点击")
    else
        randomTap(450, 1820, 10, 10, "固定位置点击输入框")
        print("processMediaResource: 未找到输入框，使用固定位置")
    end
    sleep(800)

    -- 11.2 检查输入法上方是否存在"高情商回复"快捷文字区域
    local quickReply = ocr_start(100, 1650, 950, 1760, "高情商")
    local sentText = false
    if quickReply then
        -- 存在高情商回复按钮，直接点击发送快捷回复
        randomTap(quickReply[1], quickReply[2], 5, 5, "点击高情商回复")
        print("processMediaResource: 点击高情商回复")
        sentText = true
        sleep(500)
    else
        -- 不存在则长按输入框唤醒粘贴菜单
        longTap(450, 1820)
        sleep(1000)

        -- 尝试粘贴（OCR查找粘贴选项）
        local pasteOk = false
        for retry = 1, 3 do
            local pastePos = ocr_start(112,853,921,1882, "粘贴")
            if pastePos then
                randomTap(pastePos[1], pastePos[2], 5, 5, "点击粘贴")
                print("processMediaResource: 粘贴成功")
                pasteOk = true
                break
            end
            sleep(300)
        end
        if not pasteOk then
            print("processMediaResource: 未找到粘贴选项，跳过文字发送")
        else
            sentText = true
            sleep(300)
        end
    end

    -- 11.3 发送文字消息（使用已有的 clickWxSendMsg 函数）
    if sentText then
        clickWxSendMsg()
        print("processMediaResource: 已发送文字消息")
        sleep(1500)
    end

    -- 11.4 关闭输入法弹框（点击返回键或空白处收起键盘）
    local kbCheck = ocr_start(692, 1685, 941, 1897, "换行")
    if kbCheck then
        randomTap(50, 1400, 20, 20, "关闭输入法-点击空白处")
        print("processMediaResource: 关闭输入法弹框")
        sleep(500)
    end

    -- 11.5 用OCR文字块最右坐标查找最后一条文字消息，长按唤醒"收藏"菜单
    local textBlocks = ocr_start_with_box_rightmost(247, 283, 914, 1792)
    local lastMsgX, lastMsgY = 770, 1300  -- 默认位置
    if textBlocks and #textBlocks > 0 then
        -- 找最底部（Y坐标最大）的文字块
        table.sort(textBlocks, function(a, b) return a.y < b.y end)
        local lastBlock = textBlocks[#textBlocks]
        lastMsgX = math.floor(lastBlock.x_right)
        lastMsgY = math.floor(lastBlock.y)
        print(string.format("processMediaResource: 最后一条文字消息 '%s', 最右=(%.0f,%.0f)",
            lastBlock.words, lastBlock.x_right, lastBlock.y))
    else
        print("processMediaResource: 未检测到文字消息，使用默认位置")
    end
    -- 长按偏移 (x-70, y-240) 唤醒收藏菜单
    local longPressX = lastMsgX - 70
    local longPressY = lastMsgY - 240
    longTap(longPressX, longPressY)
    print(string.format("processMediaResource: 长按唤醒收藏 pos=(%d,%d)", longPressX, longPressY))
    sleep(1000)

    -- 12. 检测"收藏"位置并点击
    local favPos = nil
    for retry = 1, 5 do
        favPos = ocr_start(148,300,910,1745, "收藏")
        if favPos then
            randomTap(favPos[1], favPos[2], 5, 5, "点击收藏")
            print("processMediaResource: 已点击收藏")
            break
        end
        print(string.format("processMediaResource: 第%d次未找到收藏选项", retry))
        sleep(300)
    end
    if not favPos then
        print("processMediaResource: 未找到收藏选项")
        return false
    end

   -- 13. 等500ms点击确认(756,1710)
    sleep(500)
    randomTap(753,1710, 15, 1, "点击添加标签")
    sleep(1000)
	local addTagPos = nil
	local pastePos =  nil
	local completePos = nil
	
	-- 添加重试机制（外层：找"添加标签"）
	for retry = 1, 3 do
        addTagPos = ocr_start(99, 281, 608, 441, "添加标签")
		print(string.format("第%d次检查添加标签位置", retry), addTagPos)
        if addTagPos then
            randomTap(favPos[1], favPos[2], 5, 5, "点击收藏")
            print("processMediaResource: 已点击收藏")
			print(string.format("长按添加标签位置x=%d,y=%d", addTagPos[1], addTagPos[2]))

			-- 内层重试：粘贴可能延迟出现，没找到则重新长按
			local pasteFound = false
			for pasteRetry = 1, 5 do
				longTap(addTagPos[1], addTagPos[2])
				sleep(2000)
				pastePos = ocr_start(118, 194, 948, 445, "粘贴")
				print(string.format("检查粘贴位置(第%d次): %s", pasteRetry, tostring(pastePos)))
				if pastePos then
					print(string.format("点击粘贴位置x=%d,y=%d", pastePos[1], pastePos[2]))
					randomTap(pastePos[1], pastePos[2], 2, 1, "点击粘贴位置")
					pasteFound = true
					break
				end
				print(string.format("未找到粘贴，重新长按添加标签(第%d次)", pasteRetry))
			end

			if not pasteFound then
				print("processMediaResource: 粘贴重试5次均失败，跳过粘贴步骤")
			end

			completePos = ocr_start(780, 211, 948, 329, "完成")
			if completePos then
				randomTap(completePos[1], completePos[2], 1, 2, "点击完成")
			end
            -- 调用更新状态接口 用来更新通道收藏状态
            if M_robotCode and M_channelNum and resource and resource.id then
                local syncedIds = {tonumber(resource.id)}
                local updateRes = Req.updateSyncStatus(M_robotCode, M_channelNum, syncedIds)
                print("processMediaResource: 更新同步状态结果:", updateRes and (updateRes.success and "成功" or "失败") or "请求失败")
            end
			break
		end
		print(string.format("processMediaResource: 第%d次未找到收藏选项", retry))
		sleep(300)
    end
    print("processMediaResource: 流程完成")
    common.changeToWXWithCheck()
    
    return true
end

-- 处理定位资源完整流程：
-- ID端：发送定位内容→复制
-- 微信端：+号→位置→发送位置→搜索→粘贴→发送→复制资源名→粘贴→发送→收藏
-- @param sendData /device/resource/send 返回的 data 对象
-- @param resource 原始资源对象 {id, resouce_content, resource_name, ...}
-- @return boolean 是否成功
function M.processLocationResource(sendData, resource)
    local common = require("common")
    local resourceContent = resource.resouce_content or ""
    local resourceName = resource.resource_name or ""

    print(string.format("processLocationResource: content=%s, name=%s",
        resourceContent, resourceName))

    -- ==================== Step 1-2: ID端复制定位内容 ====================

    -- 1. 回到桌面打开ID，搜索进入聊天框
    common.backToHomeWithCheck(2)
    sleep(300)
    common.openIDOptimize()
    sleep(1000)
    -- searchIDOptimize 内联 + 打开检测重试
    local msgs = nil
    for outerRetry = 1, 3 do
        print(string.format("processLocationResource: 第%d次搜索联系人并进入聊天框", outerRetry))

        -- searchIDOptimize 内联：OCR查找联系人名称并点击（内部最多重试2次）
        local found = false
        for _ = 1, 2 do
            local ok = optimizedWait(function()
                local r = ocr_start(230, 416, 817, 1717, config.id_ai_project_config.name)
                if not r then return false end
                randomTap(r[1], r[2] + 5, 5, 5)
                sleep(1500)
                return true
            end, 4000, 2000)
            if ok then
                found = true
                break
            end
        end

        if not found then
            print("processLocationResource: 未找到联系人名称，等待后重试")
            sleep(1000)
        else
            sleep(1500)
            msgs = common.getIDMessages()
            if msgs and #msgs > 0 then
                print(string.format("processLocationResource: 成功进入聊天框，获取到%d条消息", #msgs))
                break
            end
            print("processLocationResource: 聊天框未打开或消息为空，重试")
            sleep(1000)
        end
    end

    if not msgs or #msgs == 0 then
        print("processLocationResource: 搜索联系人进入聊天框失败，消息为空")
        return false
    end

    local lastMsg = msgs[#msgs]
    print(string.format("processLocationResource: 长按复制定位内容 pos=(%d,%d)", lastMsg.x, lastMsg.y))
    longTap(lastMsg.x + 200, lastMsg.y + 60)
    sleep(1000)

    local copyOk = false
    for retry = 1, 3 do
        local idx, cx, cy = findImage(0, 0, 0, 0,
            "id_msg_copy2.png|id_msg_copy1.png|id_msg_copy.png|id_msg_copy3.png|id_msg_copy4.png", 0.8)
        if idx ~= -1 then
            randomTap(cx, cy, 10, 10, "点击复制定位内容")
            sleep(1000)
            copyOk = true
            break
        end
        sleep(300)
    end
    if not copyOk then
        print("processLocationResource: 复制定位内容失败")
        return false
    end

    common.backToIDMessageList()
    sleep(500)

    -- ==================== Step 3-7: 微信端发送定位 ====================

    -- 3. 回到桌面打开微信（已在文件传输助手）
    common.backToHomeWithCheck(2)
    sleep(500)
    common.openWeChatSimple()
    sleep(1500)

    -- 点击+号，查找"位置"→"发送位置"→"搜索地点"（点击后重试检测）
    local foundSendPos = false
    for retry = 1, 3 do
        -- 检查输入法状态
        local kbCheck = ocr_start(692, 1685, 941, 1897, "换行")
        if kbCheck then
            randomTap(889, 1165, 5, 5, "输入法打开-点击加号")
        else
            randomTap(897, 1821, 5, 5, "输入法关闭-点击加号")
        end
        sleep(2000)

        -- 点击"位置"，并检测点击是否生效
        local posBtn = ocr_start(241, 1256, 924, 1761, "位置")
        if posBtn then
            randomTap(posBtn[1], posBtn[2], 10, 10, "点击位置")
            sleep(1000)
            -- 重试检测：点击后若"发送位置"不存在，再次点击
            local posRecheck = ocr_start(100, 1200, 600, 1800, "发送位置")
            if not posRecheck then
			print(string.format("processLocationResource: 第%d次检测发送位置后仍不存在，再次点击", retry))
                randomTap(posRecheck[1], posRecheck[2], 10, 10, "再次点击位置")
                sleep(800)
            end

            -- 点击"发送位置"，并检测点击是否生效
            local sendPos = nil
            for r = 1, 3 do
				sleep(1000)
                sendPos = ocr_start(100, 1200, 600, 1800, "发送位置")
                if sendPos then
                    randomTap(sendPos[1], sendPos[2], 5, 5, "点击发送位置")
                    sleep(1500)
                    -- 重试检测：点击后若"发送位置"仍存在，再次点击
                    local sendRecheck = ocr_start(100, 1200, 600, 1800, "发送位置")
                    if sendRecheck then
                        print(string.format("processLocationResource: 第%d次点击发送位置后仍存在，再次点击", r))
                        randomTap(sendRecheck[1], sendRecheck[2], 5, 5, "再次点击发送位置")
                        sleep(500)
                    end
                    foundSendPos = true
                    break
                end
                sleep(300)
            end
            if foundSendPos then break end
        else
            print(string.format("processLocationResource: 第%d次未找到位置按钮", retry))
        end
    end
    if not foundSendPos then
        print("processLocationResource: 未找到发送位置")
        return false
    end
    sleep(1000)

    -- 查找"搜索地点"并点击(唤醒输入法)
    local searchPlace = nil
    for retry = 1, 3 do
        searchPlace = ocr_start(105,302,927,1936, "搜索地点")
        if searchPlace then
            randomTap(searchPlace[1], searchPlace[2], 5, 5, "点击搜索地点")
            break
        end
        sleep(1000)
    end
    if not searchPlace then
        print("processLocationResource: 未找到搜索地点")
        return false
    end
    sleep(800)

    -- 5. 检测输入法上方快捷文字 / 粘贴定位内容
    local foundText = false
    local quickReply = ocr_start(100, 1400, 950, 1700, "高情商")
    local pasteIdx, pasteX, pasteY = findImage(0, 0, 0, 0, "mate30_search_friend_paste.png", 0.8)

    if quickReply then
        randomTap(quickReply[1], quickReply[2], 5, 5, "点击高情商快捷文字")
        print("processLocationResource: 点击高情商快捷文字")
        foundText = true
        sleep(500)
    elseif pasteIdx ~= -1 then
        randomTap(pasteX, pasteY, 5, 5, "点击快捷文字图片")
        print("processLocationResource: 点击快捷文字图片块")
        foundText = true
        sleep(500)
    else
        -- 扩大范围检测"搜索地点"，长按唤醒粘贴
		sleep(1000)
        searchPlace = ocr_start(105,302,927,1936, "搜索地点")
        if searchPlace then
            longTap(searchPlace[1], searchPlace[2])
            sleep(1000)
            for retry = 1, 3 do
                local pastePos = ocr_start(125,422,782,1865, "粘贴")
                if pastePos then
                    randomTap(pastePos[1], pastePos[2], 5, 5, "点击粘贴定位内容")
                    print("processLocationResource: 粘贴定位内容到搜索框")
                    foundText = true
                    break
                end
                sleep(300)
            end
        end
    end
    if not foundText then
        print("processLocationResource: 未找到快捷文字或粘贴选项")
    end
    sleep(1500)

    -- 6. 检测已粘贴/搜索的文字位置，y+120点击选中搜索结果
    if foundText then
		--模糊匹配目标位置
        local searchResult = ocr_fuzzy_find(107,796,933,1017, resourceContent)
		print(string.format("查找【%s】位置结果:",resourceContent),searchResult)
        if searchResult then
            local tx = math.floor(searchResult[1])
            local ty = math.floor(searchResult[2] + 120)
            randomTap(tx, ty, 10, 10, "点击搜索结果")
            print(string.format("processLocationResource: 点击搜索结果 pos=(%d,%d)", tx, ty))
        else
            -- 模糊匹配
            for retry = 1, 3 do
                local textBlock = ocr_start(100, 100, 900, 600, "")
                if textBlock and type(textBlock) == "table" then
                    local tx = math.floor(textBlock[1])
                    local ty = math.floor(textBlock[2] + 120)
                    randomTap(tx, ty, 10, 10, "点击搜索结果")
                    print(string.format("processLocationResource: 模糊点击搜索结果 pos=(%d,%d)", tx, ty))
                    break
                end
                sleep(1000)
            end
        end
    end
    sleep(1000)

    -- 7. 在(731,201,956,364)查找"发送"并点击
    local sendBtn = nil
    for retry = 1, 5 do
        sendBtn = ocr_start(731, 201, 956, 364, "发送")
        if sendBtn then
            randomTap(sendBtn[1], sendBtn[2], 5, 5, "点击发送定位")
            print("processLocationResource: 已点击发送定位")
            break
        end
        print(string.format("processLocationResource: 第%d次未找到发送按钮", retry))
        sleep(300)
    end
    sleep(2000)

    -- 发送完查找输入框位置，并点击输入框唤醒输入法（循环检测输入法是否打开）
    local kbOpened = false
    for retry = 1, 3 do
		sleep(1000)
        local boxIdx, boxX, boxY = findImage(99,1025,350, 1891, "chat_box_left_btn.png|chat_box_left_btn1.png", 0.9)
        if boxIdx ~= -1 then
            randomTap(boxX, boxY, 5, 5, "点击输入框唤醒输入法")
            print(string.format("processLocationResource: 第%d次图片匹配点击输入框", retry))
        else
            randomTap(450, 1820, 10, 10, "固定位置点击输入框")
            print(string.format("processLocationResource: 第%d次固定位置点击输入框", retry))
        end
        sleep(1000)
        -- 检测输入法是否已打开
        local kbCheck = ocr_start(99,1025,350,2004, "换行")
        if kbCheck then
            print("processLocationResource: 输入法已打开")
            kbOpened = true
            break
        end
        print(string.format("processLocationResource: 第%d次输入法未打开，重试", retry))
    end
    if not kbOpened then
        print("processLocationResource: 多次重试后输入法仍未打开，继续流程")
    end

    -- 请求发送消息到ID 接口将resource_name发送到发消息
    if M_robotCode and M_channelNum and resourceName and resourceName ~= "" then
        local sendUrl = config.send_msg_to_id_url .. "?robotCode=" .. urlEncode(tostring(M_robotCode))
            .. "&channelNum=" .. urlEncode(tostring(M_channelNum))
            .. "&msg=" .. urlEncode(resourceName)
        print("processLocationResource: 请求发送resource_name到ID:", sendUrl)

        local http = require("socket.http")
        local ltn12 = require("ltn12")
        local respBody = {}
        local res, code = http.request{
            url = sendUrl,
            method = "GET",
            sink = ltn12.sink.table(respBody),
        }
        if res and code == 200 then
            print("processLocationResource: resource_name发送成功, 响应:", table.concat(respBody))
        else
            print("processLocationResource: resource_name发送失败, code:", tostring(code))
        end
    end
    sleep(2000)
    -- ==================== Step 8: ID端复制资源名称 ====================

    -- 8. 回到桌面打开ID，复制最后一条消息（资源名称），回退到列表
    common.backToHomeWithCheck(2)
    sleep(300)
    common.openIDOptimize()
    sleep(1000)
    common.searchIDOptimize(config.id_ai_project_config.name, false)
    sleep(1500)

    local msgs2 = common.getIDMessages()
    if not msgs2 or #msgs2 == 0 then
        print("processLocationResource: 第二次获取ID消息为空，跳过名称复制")
    else
        local nameMsg = msgs2[#msgs2]
        print(string.format("processLocationResource: 长按复制资源名 pos=(%d,%d)", nameMsg.x, nameMsg.y))
        longTap(nameMsg.x + 200, nameMsg.y + 60)
        sleep(1000)

        local nameCopyOk = false
        for retry = 1, 3 do
            local idx, cx, cy = findImage(0, 0, 0, 0,
                "id_msg_copy2.png|id_msg_copy1.png|id_msg_copy.png|id_msg_copy3.png|id_msg_copy4.png", 0.8)
            if idx ~= -1 then
                randomTap(cx, cy, 10, 10, "点击复制资源名")
                sleep(1000)
                nameCopyOk = true
                break
            end
            sleep(300)
        end
        if not nameCopyOk then
            print("processLocationResource: 复制资源名失败，继续流程")
        end
    end

    common.backToIDMessageList()
    sleep(500)

    -- ==================== Step 9-10: 微信端粘贴资源名并收藏 ====================

    -- 9. 回到微信(文件传输助手)，长按输入框→粘贴→发送
    common.backToHomeWithCheck(2)
    sleep(500)
    common.openWeChatSimple()
    sleep(1500)

	-- 查找输入框，长按唤醒粘贴
    findWxMsgInputPaste()
	clickWxSendMsg()
	--关闭输入法
   common.closeInputMethodIfNeeded()

    -- 10. 按图片/视频方式：查找最后文字消息，长按唤醒收藏菜单
    -- 关闭输入法
    local kbCheck = ocr_start(692, 1685, 941, 1897, "换行")
    if kbCheck then
        randomTap(50, 1400, 20, 20, "关闭输入法-点击空白处")
        sleep(500)
    end

    local textBlocks = ocr_start_with_box_rightmost(247, 283, 914, 1792)
    local lastMsgX, lastMsgY = 770, 1300
    if textBlocks and #textBlocks > 0 then
        table.sort(textBlocks, function(a, b) return a.y < b.y end)
        local lastBlock = textBlocks[#textBlocks]
        lastMsgX = math.floor(lastBlock.x_right)
        lastMsgY = math.floor(lastBlock.y)
        print(string.format("processLocationResource: 最后一条文字消息 '%s', 最右=(%.0f,%.0f)",
            lastBlock.words, lastBlock.x_right, lastBlock.y))
    else
        print("processLocationResource: 未检测到文字消息，使用默认位置")
    end

    local longPressX = lastMsgX - 70
    local longPressY = lastMsgY - 240
    longTap(longPressX, longPressY)
    print(string.format("processLocationResource: 长按唤醒收藏 pos=(%d,%d)", longPressX, longPressY))
    sleep(1000)

    -- 检测"收藏"并点击
    local favPos = nil
    for retry = 1, 5 do
        favPos = ocr_start(148, 300, 910, 1745, "收藏")
        if favPos then
            randomTap(favPos[1], favPos[2], 5, 5, "点击收藏")
            print("processLocationResource: 已点击收藏")
            break
        end
        print(string.format("processLocationResource: 第%d次未找到收藏选项", retry))
        sleep(300)
    end
    if not favPos then
        print("processLocationResource: 未找到收藏选项")
        return false
    end

    -- 点击确认→添加标签→粘贴→完成
    sleep(1500)
    randomTap(753, 1710, 15, 1, "点击添加标签")
    sleep(800)

    for retry = 1, 3 do
        local addTagPos = ocr_start(99, 281, 608, 441, "添加标签")
        if addTagPos then
            randomTap(favPos[1], favPos[2], 5, 5, "点击收藏")
            print("processLocationResource: 已点击收藏")
            longTap(addTagPos[1], addTagPos[2])
            sleep(2000)

            local pastePos = ocr_start(118, 194, 948, 445, "粘贴")
            if pastePos then
                randomTap(pastePos[1], pastePos[2], 2, 1, "点击粘贴位置")
            end

            local completePos = ocr_start(780, 211, 948, 329, "完成")
            if completePos then
                randomTap(completePos[1], completePos[2], 1, 2, "点击完成")
            end

            -- 调用更新状态接口
            if M_robotCode and M_channelNum and resource and resource.id then
                local syncedIds = {tonumber(resource.id)}
                local updateRes = Req.updateSyncStatus(M_robotCode, M_channelNum, syncedIds)
                print("processLocationResource: 更新同步状态结果:", updateRes and (updateRes.success and "成功" or "失败") or "请求失败")
            end
            break
        end
        print(string.format("processLocationResource: 第%d次未找到添加标签", retry))
        sleep(300)
    end

    print("processLocationResource: 流程完成")
    common.changeToWXWithCheck()

    return true
end

-- 收藏单个资源到微信（旧流程，非媒体类型保留使用）
-- @param resource {id, file_name, file_url, type, ...}
-- @return boolean 是否成功
function M.syncSingleFavorite(resource)
    -- API字段：resource_type(int) 1=图片, 2=视频, 3=定位, 4=小程序
    local rtype = resource.resource_type or 0
    local rtypeText = resource.resource_type_text or ""
    local fileName = resource.resource_name or ""

    if rtype == 1 or rtypeText == "图片" or string.match(fileName, "%.(png|jpg|jpeg)$") then
        return M.favoriteImage(resource)
    elseif rtype == 2 or rtypeText == "视频" or string.match(fileName, "%.(mp4|avi)$") then
        return M.favoriteVideo(resource)
    elseif rtype == 3 or rtypeText == "定位" then
        return M.favoriteLocation(resource)
    elseif rtype == 4 or rtypeText == "小程序" then
        return M.favoriteMiniProgram(resource)
    else
        print("syncSingleFavorite: 未知资源类型(rtype=" .. tostring(rtype) .. ")，按文件处理")
        return M.favoriteFile(resource)
    end
end

-- 收藏图片到微信
function M.favoriteImage(resource)
    local fileUrl = resource.resouce_content
    if not fileUrl or fileUrl == "" then
        print("favoriteImage: resouce_content为空，跳过")
        return false
    end

    -- TODO: 下载图片 → 进入微信收藏 → 添加图片到收藏
    print("favoriteImage: 下载并收藏图片, url:", fileUrl)
    -- 示例流程：1.下载图片 2.进入微信"我→收藏" 3.点击"+"添加 4.选择图片 5.保存
    return true
end

-- 收藏视频到微信
function M.favoriteVideo(resource)
    local fileUrl = resource.resouce_content
    if not fileUrl or fileUrl == "" then
        print("favoriteVideo: resouce_content为空，跳过")
        return false
    end

    -- TODO: 下载视频 → 进入微信收藏 → 添加视频到收藏
    print("favoriteVideo: 下载并收藏视频, url:", fileUrl)
    return true
end

-- 收藏文件到微信
function M.favoriteFile(resource)
    local fileUrl = resource.resouce_content
    if not fileUrl or fileUrl == "" then
        print("favoriteFile: resouce_content为空，跳过")
        return false
    end

    -- TODO: 下载文件 → 进入微信收藏 → 添加文件到收藏
    print("favoriteFile: 下载并收藏文件, url:", fileUrl)
    return true
end

-- ==================== 文件传输助手流程 ====================

-- 发送消息到ID并打开微信文件传输助手聊天框
-- 当前需已在微信聊天列表，收藏流程前置步骤
-- @param robot_code 机器人编号
-- @param channel_num 通道号
-- @return boolean 是否成功
function M.sendToFileHelper(robot_code, channel_num)
    print("========== sendToFileHelper: 发送到文件传输助手 ==========")

    -- 1. 请求 /api/send_msg_to_id 发送"文件传输助手"消息到ID
    local sendUrl = config.send_msg_to_id_url .. "?robotCode=" .. tostring(robot_code) .. "&channelNum=" .. tostring(channel_num) .. "&msg=" .. urlEncode("文件传输助手")
    print("sendToFileHelper: 请求发送消息到ID:", sendUrl)

    local http = require("socket.http")
    local ltn12 = require("ltn12")
    local response_body = {}
    local res, code = http.request{
        url = sendUrl,
        method = "GET",
        sink = ltn12.sink.table(response_body),
    }

    if not res or code ~= 200 then
        print("sendToFileHelper: 发送消息到ID失败, code:", tostring(code))
        return false
    end
    print("sendToFileHelper: 消息发送成功, 响应:", table.concat(response_body))

    -- 2. 回到桌面打开ID
    local common = require("common")
    print("sendToFileHelper: 切换到ID获取消息...")
    common.backToHomeWithCheck(2)
    sleep(300)
    common.openIDOptimize()
    sleep(1000)

    -- 3. 搜索联系人进入聊天框（searchIDOptimize 内联 + 打开检测重试）
    local msgs = nil
    for outerRetry = 1, 3 do
        print(string.format("sendToFileHelper: 第%d次搜索联系人并进入聊天框", outerRetry))

        -- searchIDOptimize 内联：OCR查找联系人名称并点击（内部最多重试2次）
        local found = false
        for _ = 1, 2 do
            local ok = optimizedWait(function()
                local r = ocr_start(230, 416, 817, 1717, config.id_ai_project_config.name)
                if not r then return false end
                randomTap(r[1], r[2] + 5, 5, 5)
                sleep(1500)
                return true
            end, 4000, 2000)
            if ok then
                found = true
                break
            end
        end

        if not found then
            print("sendToFileHelper: 未找到联系人名称，等待后重试")
            sleep(1000)
        else
            sleep(1500)
            msgs = common.getIDMessages()
            if msgs and #msgs > 0 then
                print(string.format("sendToFileHelper: 成功进入聊天框，获取到%d条消息", #msgs))
                break
            end
            print("sendToFileHelper: 聊天框未打开或消息为空，重试")
            sleep(1000)
        end
    end

    if not msgs or #msgs == 0 then
        print("sendToFileHelper: 搜索联系人进入聊天框失败，消息为空")
        return false
    end
    print("sendToFileHelper: 获取到", #msgs, "条ID消息")

    local lastMsg = msgs[#msgs]
    local msg_x = lastMsg.x + 200
    local msg_y = lastMsg.y + 60

    -- 长按最后一条消息复制
    print("sendToFileHelper: 长按复制消息")
    longTap(msg_x, msg_y)
    sleep(1000)

    local copySuccess = false
    for retry = 1, 3 do
        local idx, copy_x, copy_y = findImage(0, 0, 0, 0, "id_msg_copy2.png|id_msg_copy1.png|id_msg_copy.png|id_msg_copy3.png|id_msg_copy4.png", 0.8)
        if idx ~= -1 then
            randomTap(copy_x, copy_y, 10, 10, "点击复制")
            sleep(1000)
            copySuccess = true
            break
        end
        sleep(300)
    end

    if not copySuccess then
        print("sendToFileHelper: 复制消息失败")
        return false
    end

    -- 5. 返回ID消息列表
    common.backToIDMessageList()
    sleep(500)

    -- 6. 回到桌面打开微信
    common.backToHomeWithCheck()
    sleep(500)
    common.openWeChatSimple()
    sleep(1500)

    -- 7. 点击微信右上角搜索
    local idx, x, y = findImage(699, 203, 906, 339, "wx_search_btn.png", 0.9)
    if idx ~= -1 then
        randomTap(x, y, 10, 10, "图片识别点击搜索")
    else
        randomTap(791, 253, 10, 10, "固定位置点击搜索")
    end
    sleep(2000)

    -- 8. 处理粘贴：高情商回复 优先，否则长按唤醒粘贴
    local smartReply = ocr_start(496, 1187, 925, 1354, "高情商回复")
    if smartReply then
        -- 有高情商回复说明剪切板有内容，点击文字块
        print("sendToFileHelper: 检测到高情商回复，点击文字块")
        randomTap(smartReply[1] - 500, smartReply[2], 150, 5, "点击剪切板内容")
        sleep(1000)
    else
        -- 通过图片查找粘贴图标
        local pasteIdx, pasteX, pasteY = findImage(93, 1220, 512, 1851, "mate30_search_friend_paste.png", 0.9)
        if pasteIdx ~= -1 then
            print("sendToFileHelper: 图片识别到粘贴图标")
            randomTap(pasteX + 80, pasteY + 20, 30, 10, "点击粘贴")
            sleep(1000)
        else
            -- 长按搜索输入框唤醒粘贴（带重试：长按→找粘贴未果则关闭弹窗重新长按）
            local pastePos = nil
            for outerRetry = 1, 3 do
                print("sendToFileHelper: 未检测到快捷粘贴，长按输入框唤醒粘贴 (第" .. outerRetry .. "次)")
                local searchBox = ocr_start(102, 196, 869, 438, "搜索")
                if searchBox then
                    longTap(searchBox[1], searchBox[2], 500)
                else
                    longTap(445, 361, 500)
                end
                sleep(2000)
                -- 查找粘贴选项
                for retry = 1, 5 do
                    pastePos = ocr_start(105, 146, 804, 1840, "粘贴")
                    if pastePos then
                        randomTap(pastePos[1] - 3, pastePos[2] - 5, 5, 5, "点击粘贴")
                        print("sendToFileHelper: 已点击粘贴")
                        break
                    end
                    print("sendToFileHelper: 第" .. retry .. "次未找到粘贴，重试")
                    sleep(800)
                end
                if pastePos then
                    break
                end
                print("sendToFileHelper: 第" .. outerRetry .. "次长按未找到粘贴，关闭弹窗重试长按")
                tap(100, 100) -- 点击空白区域关闭可能弹出的菜单
                sleep(500)
            end
            if not pastePos then
                print("sendToFileHelper: 未找到粘贴选项")
                return false
            end
        end
    end

    sleep(1500)

    -- 9. 查找"文件传输助手"并点击打开
    local fileHelperPos = nil
    for retry = 1, 5 do
        fileHelperPos = ocr_start(109,378,931,642, "文件传输助手")
        if fileHelperPos then
            print("sendToFileHelper: 找到文件传输助手, 位置:", fileHelperPos[1], fileHelperPos[2])
            randomTap(fileHelperPos[1], fileHelperPos[2], 10, 10, "点击文件传输助手")
            sleep(1500)
            print("========== sendToFileHelper 完成 ==========")
            return true
        end
        print("sendToFileHelper: 第" .. retry .. "次未找到文件传输助手")
        sleep(1000)
    end

    print("sendToFileHelper: 未找到文件传输助手")
    return false
end

-- 收藏定位到微信
function M.favoriteLocation(resource)
    local fileUrl = resource.resouce_content
    print("favoriteLocation: 收藏定位, content:", tostring(fileUrl))
    -- TODO: 进入微信收藏 → 添加定位到收藏
    return true
end

-- 收藏小程序到微信
function M.favoriteMiniProgram(resource)
    local fileUrl = resource.resouce_content
    print("favoriteMiniProgram: 收藏小程序, content:", tostring(fileUrl))
    -- TODO: 进入微信收藏 → 添加小程序到收藏
    return true
end

return M
