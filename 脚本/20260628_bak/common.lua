-- 公用函数
local C = {_VERSION=0.1}
local Req = require("requests")
local monitor = require("performance_monitor")
local config = require("config")

-- ==================== URL编码函数 ====================
local function urlEncode(s)
    if not s then return "" end
    s = tostring(s)
    s = string.gsub(s, "\n", "\r\n")
    s = string.gsub(s, "([^%w%-%.%_%~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    return s
end

-- ==================== 工具函数 ====================
function optimizedWait(func, timeout, interval)
    local start = os.clock()
    while os.clock() - start < timeout/1000 do
        if func() then return true end
        sleep(interval)
    end
    return false
end

function arrSortByY(arr)
    if not arr or #arr == 0 then return arr end
    table.sort(arr, function(a,b) return a.y < b.y end)
    return arr
end

-- 带随机偏移的滑动函数
function randomSwipe(x, y, x2, y2, duration)
    local offsetX = math.random(-20, 20)
    local offsetY = math.random(-20, 20)
    local offsetX2 = math.random(-20, 20)
    local offsetY2 = math.random(-20, 20)
    swipe(x + offsetX, y + offsetY, x2 + offsetX2, y2 + offsetY2, duration)
end

-- 检测是否在聊天输入界面
function C.checkChatInput()
    -- 检测输入框或发消息按钮
    local input1 = findImage(350,1680,500,1790,"mate30_input_box.png",0.8)
    local input2 = ocr_start(400,1720,600,1800,"发消息")
    local input3 = findImage(800,1780,900,1850,"mate30_send_btn.png",0.8)
    return input1 ~= -1 or input2 or input3 ~= -1
end

-- ==================== 桌面/APP 切换 ====================
function C.backToHomeWithCheck(maxRetries)
    maxRetries = maxRetries or 3
    local retryCount = 0
    while retryCount < maxRetries do
        retryCount = retryCount + 1
        print("第"..retryCount.."次尝试回到桌面")
        randomTap(519, 1918, 3, 3, "回到桌面")
        sleep(1000)

        local wxIndex = findImage(144,1693,941,1938,"wx_logo_1.png|wxapp.png|wxapp_logo.png",0.9)
        local idIndex = findImage(144,1693,941,1938,"ld_logo9.png|idapp.png|ID_logo.png|ID_logo_03.png",0.9)
        if wxIndex ~= -1 or idIndex ~= -1 then
            print("回到桌面成功")
            return true
        end
        print("未检测到桌面图标，重试")
    end
    print("回到桌面失败")
    return false
end

function C.changeToWX()
    C.backToHomeWithCheck(3)
    local index, x, y = findImage(0,0,0,0,"wxapp_logo.png|wx_logo_1.png",0.8)
    if index == -1 then
        randomTap(420,1790,10,10,"直接打开微信")
        sleep(1500)
        local ok, inWxList = pcall(ocr_start,374,224,678,292,"微信")
        if ok and inWxList then return true end
        local ok2, wxTextPos = pcall(ocr_start,119,1761,360,1939,"微信")
        if ok2 and wxTextPos then
            randomTap(wxTextPos[1], wxTextPos[2]-20,20,10)
            sleep(1000)
            local ok3 = pcall(ocr_start,374,224,678,292,"微信")
            return ok3
        end
        return false
    else
        randomTap(x,y,30,30,"打开微信")
        sleep(800)
        return true
    end
end

-- 切换到微信并确保在列表界面
function C.changeToWXWithCheck()
	C.changeToWX()
	-- 检测当前是否在微信列表，若不在则点击左上角返回
	local maxRetry = 3
	local retryCount = 0
	while retryCount < maxRetry do
		sleep(800)
		local inWxList = ocr_start(374, 224, 678, 292, "微信")
		if inWxList then
			print("已在微信列表界面")
			return true
		else
			retryCount = retryCount + 1
			print("不在微信列表，点击左上角返回，第"..retryCount.."次")
			-- 点击左上角返回按钮
			local backIndex, backX, backY = findPicEx(99, 211, 187, 292, "wx_back.png", 0.9)
			if backIndex ~= -1 then
				randomTap(backX + 12, backY + 20, 3, 5, "点击返回按钮")
			else
				randomTap(125, 252, 3, 5, "点击固定位置返回")
			end
			sleep(800)
			cancelPos = ocr_start(809,195,950,305,"取消")
			print("检测取消位置",cancelPos)
			if cancelPos then
				randomTap(cancelPos[1],cancelPos[2],3,1,"点击取消")
				sleep(800)
				randomTap(125, 252, 3, 5, "点击固定位置返回")
			end
		end
	end
	print("已尝试"..maxRetry.."次返回，当前可能不在微信聊天详情页")
	return false
end

function C.changeToID()
    C.backToHomeWithCheck(3)
    local index, x, y = findPic(135,1688,952,1879,"ld_logo9.png|idapp.png|ID_logo.png","000000",0,0.8)
    randomTap(627,1790,10,10,"打开ID")
    sleep(800)
end

-- ==================== 微信返回 ====================
function C.weChatBack()
    local backIndex, bx, by = findPicEx(99,211,187,292,"wx_back.png",0.9)
    if backIndex ~=-1 then
        randomTap(bx+12,by+20,3,5)
        return true
    else
        randomTap(125,252,5,5)
        return false
    end
end

function C.weChatBackWithRetry(retryCount)
    retryCount = retryCount or 2
    for i=1,retryCount do
        C.weChatBack()
        sleep(800)
    end
    return true
end

-- ==================== 打开智企ID ====================
function C.openID(is_return_list_check)
    is_return_list_check = is_return_list_check or false
    local maxRetry = 3
    local retryCount = 0
    while retryCount < maxRetry do
        retryCount = retryCount +1
        sleep(1000)
        local mark = ocr_start(115,379,908,1728, config.id_ai_project_config.mark)
        local name = ocr_start(115,379,908,1728, config.id_ai_project_config.name)
        local receive = ocr_start(115,379,908,1728, config.id_ai_project_config.receive_name)
        if mark or name or receive then
            print("已在智企ID")
            if is_return_list_check then
                if name or receive then
                    C.backToIDMessageList()
                end
            end
            return true
        end
        C.backToHomeWithCheck(3)
        sleep(800)
        randomTap(630,1786,10,10,"打开智企ID")
    end
    print("打开智企ID失败")
    return false
end

function C.openIDOptimize()
    local maxRetries = 2
    local retryCount =0
    while retryCount < maxRetries do
        local ok = optimizedWait(function()
            local mark = ocr_start(115,379,908,1728, config.id_ai_project_config.mark)
            local name = ocr_start(115,379,908,1728, config.id_ai_project_config.name)
            local receive = ocr_start(115,379,908,1728, config.id_ai_project_config.receive_name)
            return mark or name or receive
        end,3000,500)
        if ok then return true end
        retryCount = retryCount +1
        C.backToHomeWithCheck(3)
        sleep(1000)
        randomTap(630,1786,10,10)
        sleep(1000)
    end
    return false
end

-- **************************** 优化版本开始 *********************************

-- *********** 打开微信模块 ***********
-- 打开微信（简化版）- 只从桌面点击微信，不检测顶部
function C.openWeChatSimple()
    local op_start = os.time()
    local maxRetries = 3
    local retryCount = 0

    while retryCount < maxRetries do
        retryCount = retryCount + 1
        print(string.format("第%d次尝试打开微信", retryCount))

        -- 直接查找桌面微信图标
        local wxIndex, wxX, wxY = findImage(221, 1664, 873, 1957, "wxapp_logo.png|wx_logo_1.png", 0.8)
        if wxIndex ~= -1 then
            print(string.format("找到桌面微信图标，位置: (%d, %d)", wxX, wxY))
            randomTap(wxX, wxY, 30, 30, "打开微信")
        else
            -- 未找到图标，回到桌面后点击固定位置
            print("未找到微信图标，点击桌面后打开")
            randomTap(519, 1918, 3, 3, "回到桌面")
            sleep(1000)
            randomTap(422, 1791, 10, 10, "打开微信")
        end
        sleep(1500)
    end

    local duration = os.time() - op_start
    monitor.record("打开微信：", duration)
    return true
end

-- type 回到微信类型 默认1 直接回到微信 2 回退一次 3 回退2次
-- 打开微信（优化版）不传参数默认 type=1
function C.openWeChatOptimize(type)
    -- 关键：如果没传 type，默认 = 1
    type = type or 1

    local op_start = os.time()
    local maxRetries = 3   -- 最大重试次数
    local retryCount = 0

    while retryCount < maxRetries do
        -- 检测当前页面是否是微信主页
        local isWechatLoaded = false
        local checkCount = 0

        while checkCount < 2 and not isWechatLoaded do
            checkCount = checkCount + 1
            -- OCR 检查顶部是否出现"微信"
            local res = ocr_start(300, 180, 750, 350, "微信")
            print("顶部搜索微信:", res)
            if res then
                isWechatLoaded = true
                break
            end
            sleep(500)
        end

        -- 已经在微信界面
        if isWechatLoaded then
            print("已经在微信聊天列表")
            local duration = os.time() - op_start
            monitor.record("打开微信：", duration)
            return true
        else
            -- 不在微信，直接检测桌面微信图标
            retryCount = retryCount + 1
            print(string.format("第%d次尝试打开微信", retryCount))

            -- 直接查找桌面微信图标
            local wxIndex, wxX, wxY = findImage(221,1664,873,1957, "wxapp_logo.png|wx_logo_1.png", 0.8)
            if wxIndex ~= -1 then
                print(string.format("找到桌面微信图标，位置: (%d, %d)", wxX, wxY))
                randomTap(wxX, wxY, 30, 30, "打开微信")
            else
                -- 未找到图标，回到桌面后点击固定位置
                print("未找到微信图标，点击桌面后打开")
                randomTap(519, 1918, 3, 3, "回到桌面")
                sleep(1000)
                randomTap(422, 1791, 10, 10, "打开微信")
            end
            sleep(1500)
        end
    end

    -- 所有重试失败
    print(string.format("打开微信失败，已重试%d次", maxRetries))
    local duration = os.time() - op_start
    monitor.record("打开微信失败：", duration)
    return false
end

-- ==================== 智企ID 搜索/复制 ====================
function C.searchID(name, red)
    C.openID()
    local id_list_pos = config.meta30_config.id_list_pos
    local res = ocr_start(id_list_pos.x1,id_list_pos.y1,id_list_pos.x2,id_list_pos.y2,name)
    if not res then return false end

    if red then
        local rx, ry = res[1] or 0, res[2] or 0
        if rx == 0 or ry == 0 then return false end
        local idx, x, y = findPic(rx+500, ry,937,ry+100,"ID_redp1.png|ID_redp1_1.png","101010",0,0.8)
        if idx ~=-1 then
            randomTap(rx,ry,3,5)
            sleep(2000)
            return true
        end
        local ret = findColor(rx+500,ry,937,ry+100,"9c2f2c|9b2e29|992c27|9a2c27|9a2a27",0,0.9)
        if ret ~=-1 then
            randomTap(rx,ry,3,5)
            sleep(2000)
            return true
        end
        return false
    else
        local check = ocr_start(359,209,728,311,name)
        if not check then
            randomTap(res[1],res[2]+5,5,5)
        end
        return true
    end
end

function C.getIDPhone(name)
    local maxRetry = 3
    local retryCount = 0

    while retryCount < maxRetry do
        retryCount = retryCount + 1
        print("=== 第" .. retryCount .. "次尝试获取ID好友信息 ===")

        -- 打开ID的列表
        local res = C.searchID(name, true)
        print("查找id列表加好友信息", res)

        if res then
            print("进入ID聊天框", name)

            -- 检测是否真正进入聊天界面（检测是否有输入框或发消息按钮）
            sleep(1000)
            local inChat = ocr_start(230,207,858,325, name)
            if inChat then
                print("已进入ID聊天界面")
                -- 复制消息
                local copyResult = C.AddFrientIDCopy()
                if copyResult then
                    return true
                else
                    print("复制失败，重试")
                    -- 返回ID列表准备重试
                    C.backToIDMessageList()
                    sleep(500)
                end
            else
                print("未检测到聊天界面，可能未成功进入，重试")
                -- 点击任意位置尝试进入
                randomTap(500, 800, 100, 100, "点击尝试进入聊天")
                sleep(1000)

                -- 再次检测
                inChat = ocr_start(134, 1715, 946, 1930, name) or
                         C.checkChatInput()

                if inChat then
                    print("第二次检测到聊天界面")
                    local copyResult = C.AddFrientIDCopy()
                    if copyResult then
                        return true
                    end
                end

                -- 返回ID列表准备重试
                C.backToIDMessageList()
                sleep(500)
            end
        else
            print("未找到ID联系人，重试")
        end
    end

    print("获取ID好友信息失败，已达最大重试次数")
    return false
end

-- 复制id加好友消息（参考unpaid实现）
function C.AddFrientIDCopy()
    local outerRetry = 0
    local maxOuterRetry = 3

    while outerRetry < maxOuterRetry do
        outerRetry = outerRetry + 1
        print("=== 第" .. outerRetry .. "次尝试复制加好友消息 ===")
        
        -- 查找多点坐标 相对精准
        print("根据头像查找加好友消息位置：213,312,367,1750")
        sleep(800)
        local chat_pos_arr = findPicAllPoint(218,257,972,1883,"id_add_friend.png",0.9)
        
        if next(chat_pos_arr) == nil then
            print("未找到加好友消息")
            if outerRetry < maxOuterRetry then
                print("等待后重试")
                sleep(500)
            end
        else
            chat_pos_arr = arrSortByY(chat_pos_arr) -- 按从上到下排序
            print("计算当前页消息数量", #chat_pos_arr)
            print("识别ID定位消息", chat_pos_arr[#chat_pos_arr])
            local x1 = chat_pos_arr[#chat_pos_arr].x + math.random(150,400)
            local y1 = chat_pos_arr[#chat_pos_arr].y + math.random(20,40)
            -- 长按
            print("长按复制按钮坐标", x1, y1)
            longTap(x1, y1)
            sleep(800)

            -- 内层查找复制按钮
            local copyFound = false
            local innerRetry = 0
            local maxInnerRetry = 5

            while innerRetry < maxInnerRetry and not copyFound do
                innerRetry = innerRetry + 1
                
                -- 查找复制按钮
                local rey, id_msg_copy_x, id_msg_copy_y = findImage(0, 0, 0, 0, "id_msg_copy.png|id_msg_copy1.png|id_msg_copy2.png|id_msg_copy3.png|id_msg_copy4.png", 0.8)
                print("第"..innerRetry.."次识别 id 复制按钮：", id_msg_copy_x, id_msg_copy_y)

                if rey ~= -1 then
                    copyFound = true
                    -- 点击复制按钮
                    randomTap(id_msg_copy_x, id_msg_copy_y, 60, 60, "点击复制按钮")
                    sleep(500)

                    -- 返回ID消息列表
                    local bak_msg_list_ret = -1
                    local bx = -1
                    local by = -1

                    while bak_msg_list_ret == -1 do
                        bak_msg_list_ret, bx, by = findImage(0, 0, 200, 350, "msg_bak.png|msg_back_1.png", 0.9)
                        print("id返回消息列表:", bak_msg_list_ret, bx, by)

                        if bak_msg_list_ret ~= -1 then
                            randomTap(bx+15, by+15, 5, 5, "id返回消息列表")
                        end
                    end

                    sleep(500)
                    return true
                else
                    -- 第3次内层识别失败时，检测是否还在ID详情页
                    if innerRetry == 3 then
                        print("第3次识别复制按钮失败，检测是否还在ID详情页")
                        local inIDList = ocr_start(134, 1715, 946, 1930, "消息") or
                                         ocr_start(134, 1715, 946, 1930, "通讯录") or
                                         ocr_start(134, 1715, 946, 1930, "工作") or
                                         ocr_start(134, 1715, 946, 1930, "发现")
                        if inIDList then
                            print("检测到已回到ID列表，跳出内层循环重新点击加好友")
                            break
                        else
                            -- 尝试OCR识别"复制"文字
                            local copyRes = ocr_start(79,259,353,1762,"复制")
                            if copyRes then
                                print("OCR识别到复制按钮", copyRes[1], copyRes[2])
                                randomTap(copyRes[1], copyRes[2], 30, 30, "点击复制按钮")
                                sleep(500)
                                
                                -- 返回ID消息列表
                                local ret_bak = -1
                                local rx, ry
                                while ret_bak == -1 do
                                    ret_bak, rx, ry = findImage(0, 0, 200, 350, "msg_bak.png|msg_back_1.png", 0.9)
                                    if ret_bak ~= -1 then
                                        randomTap(rx, ry, 5, 5, "id返回消息列表")
                                    end
                                end
                                sleep(500)
                                return true
                            end
                        end
                    end
                    sleep(300)
                end
            end
        end
    end

    print("复制加好友消息失败")
    return false
end

-- ==================== 微信添加好友 ====================
-- *********** 添加微信好友 ***********
function C.addWXFriendOptimize()
	local op_start = os.time()
	local maxRetries = 2
	local retryCount = 0
	local tagName = nil  -- 在函数作用域声明，避免块作用域导致下游使用时为nil

	-- 加好友流程开始时调用fetch_pending_phone接口
	local robotCode = config.robot_code
	local channelNum = _G.wechat_task_options and _G.wechat_task_options.taskId or 1
	local fetchUrl = config.fetch_pending_phone_url .. "?robotCode=" .. robotCode .. "&channelNum=" .. channelNum
	print("加好友流程开始，调用fetch_pending_phone接口:", fetchUrl)
	local fetchRes = getHttp(fetchUrl)
	if fetchRes and fetchRes ~= false then
		print("fetch_pending_phone接口返回:", fetchRes)
	
		local descUrl = config.sku_config_get_url .. "?robotCode=" .. robotCode .. "&channelNum=" .. channelNum
		local descRes = getHttp(descUrl)
		print("sku_config_get_url接口返回:", descRes)
		-- 解析返回数据，检查是否有待处理记录
		local jsonData = jsonLib.decode(fetchRes)
		-- 提取tag_name用于后续标签处理
		if jsonData then
			-- 判断是否有有效数据
			-- data为nil、false、null或空对象时跳过
			local dataValue = jsonData.data
			
			-- 检查data是否为null（JSON null在Lua中可能是特定值）
			if dataValue == nil or dataValue == false or dataValue == jsonLib.null then
				print("暂无待处理记录(data为null)，不进入加好友流程")
				uploadLog("暂无待处理记录(data为null)，不进入加好友流程")
				return true, false  -- 成功但无数据处理
			end
			
			if type(dataValue) == "table" then
				-- 如果是数组，检查长度；如果是对象，检查是否有内容
				if #dataValue == 0 and next(dataValue) == nil then
					print("暂无待处理记录(data为空)，不进入加好友流程")
					uploadLog("暂无待处理记录(data为空)，不进入加好友流程")
					return true, false  -- 成功但无数据处理
				end
				-- 提取tag_name
				if dataValue.tag_name and dataValue.tag_name ~= "" then
					tagName = tostring(dataValue.tag_name)
					print("获取到标签名称: " .. tagName)
				else
					print("tag_name为空，跳过标签处理")
				end
				-- 提取project，优先取接口返回值，否则取config.project
				if dataValue.project then
					_G.wechat_task_options.project = tonumber(dataValue.project) or dataValue.project
					print("获取到project: " .. tostring(_G.wechat_task_options.project))
				else
					_G.wechat_task_options.project = config.project
					print("接口未返回project，使用config.project: " .. tostring(config.project))
				end
				-- 提取phone，用于upstate上报（OCR检测不到手机号时使用）
				if dataValue.phone and dataValue.phone ~= "" then
					_G.wechat_task_options.pendingPhone = tostring(dataValue.phone)
					print("获取到待处理手机号: " .. _G.wechat_task_options.pendingPhone)
				end
			end
			
			print("获取到待处理好友数据，进入加好友流程")
		end
	else
		print("fetch_pending_phone接口调用失败，不进入加好友流程")
		uploadLog("fetch_pending_phone接口调用失败，不进入加好友流程")
		return false, false
	end

	while retryCount < maxRetries do
		retryCount = retryCount + 1
		print(string.format("第%d次尝试添加微信好友", retryCount))
		uploadLog(string.format("第%d次尝试添加微信好友", retryCount))
		local success = C.addWXFriendSingleAttempt(op_start, tagName)
		if success then
			return true, true  -- 成功且有数据处理
		end

		print(string.format("第%d次添加好友失败，准备重试", retryCount))
		uploadLog(string.format("第%d次添加好友失败，准备重试", retryCount))
		sleep(800) -- 重试前等待
	end

	print("添加微信好友失败，已达最大重试次数")
	uploadLog("添加微信好友失败，已达最大重试次数")
	monitor.record("添加微信好友失败：", os.time() - op_start)
	--失败后检测当前是否在微信 不在则返回微信 || 添加好友流程失败返回ID列表
	print("添加好友失败-ID返回到列表&切换回微信")
	C.openID(true)
	local checkInWxList = ocr_start(150,1825,257,1893,"微信")
	if checkInWxList == false then
		C.changeToWX()
	end

	return false, true  -- 失败但有数据处理
end

function C.addWXFriendSingleAttempt(op_start, tagName)
	-- 复制智企ID消息
	local res = C.getIDPhone(config.id_ai_project_config.receive_name)

	if not res then
		print("复制智企ID消息失败")
		return false
	end

	-- 打开微信
	if not C.openWeChatOptimize() then
		print("打开微信失败")
		return false
	end

	-- 点击加好友按钮
	local addFriendClicked = optimizedWait(function()
		randomTap(885,252, 3, 3, "添加微信好友加号")
		
		-- 等待"添加朋友"界面出现
		local found = optimizedWait(function()
			local resA = ocr_start(587, 430, 912, 528, "添加朋友")
			if resA then
				print("点击添加朋友")
				randomTap(resA[1], resA[2], 10, 10, "添加朋友")
				return true
			end
			return false
		end, 3000, 500)

		if not found then
			print("直接点击添加朋友")
			randomTap(737, 474, 20, 20, "直接点击添加朋友")
		end

		return true
	end, 6000, 500)

	if not addFriendClicked then
		print("点击加好友失败")
		return false
	end

	-- 等待添加朋友界面加载
	local addFriendPageLoaded = optimizedWait(function()
		local resL = ocr_start(164, 176, 820, 381, "添加朋友")
		print("添加朋友界面判断:", resL)

		if resL then
			return true
		end
		return false
	end, 4000, 2000)

	if not addFriendPageLoaded then
		print("添加朋友界面加载失败")
		return false
	end

	-- 点击输入搜索框并验证输入法是否打开
	print("添加朋友界面点击输入搜索的手机号")
	local inputBoxOpened = false
	local inputRetry = 0
	while inputRetry < 3 and not inputBoxOpened do
		inputRetry = inputRetry + 1
		print(string.format("第%d次点击输入搜索框", inputRetry))

		-- 使用OCR识别"搜索"位置并点击
		sleep(1000)
		local searchPos = ocr_start(102, 196, 869, 438, "搜索")
		if searchPos then
			print(string.format("OCR识别到搜索位置: (%d, %d)", searchPos[1], searchPos[2]))
			randomTap(searchPos[1], searchPos[2]-10, 20, 0, "点击搜索输入框")
		else
			print("OCR未识别到搜索位置，使用默认坐标")
			randomTap(445, 361, 20, 20, "输入手机号码搜索")
		end
		sleep(1500)

		-- 验证输入法是否打开（检测换行或搜索）
		local newlineRes = ocr_start(689, 1589, 951, 1914, "换行")
		local searchRes = ocr_start(102, 196, 869, 438, "搜索")
		print("检测输入法是否打开 - 换行:", newlineRes, "搜索:", searchRes)
		if newlineRes or searchRes then
			print("输入法已打开")
			inputBoxOpened = true
		else
			print(string.format("第%d次点击后输入法未打开", inputRetry))
		end
	end

	if not inputBoxOpened then
		print("输入法打开失败")
		return false
	end


	
	--粘贴手机号 mate30适配（添加重试和验证机制）
	sleep(500)
	local pasteSuccess = false
	local pasteRetry = 0
	local maxPasteRetry = 3

	while pasteRetry < maxPasteRetry and not pasteSuccess do
		pasteRetry = pasteRetry + 1
		print(string.format("第%d次尝试粘贴手机号", pasteRetry))

		--检查输入法左上方是否有粘贴图标
		local index,x,y=findImage(97,1148,252,1352,"mate30_search_friend_paste.png",0.9)
		print("检查输入法左上方是否有粘贴图标:",index,x,y)
		if index ~= -1 then
			x = x + 120 + math.random(5,120)
			y = y + 20
			randomTap(x,y,120,0,"点击输入法粘贴")
			sleep(1000)
		else
			print("未检测到输入法有粘贴图标,开始手动粘贴")
			-- 使用OCR查找账号/搜索位置进行长按（扩大搜索范围）
			sleep(1000)
			local accountPos = ocr_start(50, 150, 950, 600, "搜索")
			if accountPos then
				print(string.format("OCR识别到搜索位置，长按: (%d, %d)", accountPos[1], accountPos[2]))
				longTap(accountPos[1], accountPos[2]-20)
			else
				print("OCR未识别到搜索位置，使用默认坐标长按")
				longTap(259, 246)
			end
			sleep(800)

			-- 等待粘贴菜单出现，重试检测
			local pasteRes = nil
			local pasteDetectRetry = 0
			local maxPasteDetectRetry = 3
			while pasteDetectRetry < maxPasteDetectRetry and not pasteRes do
				pasteDetectRetry = pasteDetectRetry + 1
				print(string.format("第%d次检测粘贴按钮", pasteDetectRetry))
				pasteRes = ocr_start(50, 200, 900, 600, "粘贴")
				if pasteRes then
					print("检测到粘贴按钮:", pasteRes[1], pasteRes[2])
				else
					print("未检测到粘贴按钮，等待后重试")
					sleep(500)
				end
			end

			if pasteRes then
				randomTap(pasteRes[1], pasteRes[2], 20, 10, "点击粘贴位置")
				sleep(1000)
			else
				print("多次检测未找到粘贴按钮，点击固定粘贴位置")
				randomTap(181, 378, 20, 10, "点击固定粘贴位置")
				sleep(1000)
			end
		end

		-- 验证粘贴是否成功：检测搜索输入框中是否有内容
		sleep(500)
		local verifyPaste = ocr_start(100, 320, 600, 420, "")
		print("验证搜索输入框内容:", verifyPaste)
		if verifyPaste and string.len(verifyPaste) > 5 then
			-- 检测到内容，说明粘贴成功
			print("粘贴成功，搜索输入框中有内容")
			pasteSuccess = true
		else
			-- 另一种验证方式：检测换行是否消失（输入法可能已关闭）
			local newlineRes = ocr_start(689, 1589, 951, 1914, "换行")
			if not newlineRes then
				print("输入法已关闭，可能粘贴成功")
				-- 再次检测输入框
				verifyPaste = ocr_start(100, 320, 600, 420, "")
				if verifyPaste and string.len(verifyPaste) > 5 then
					print("确认粘贴成功")
					pasteSuccess = true
				end
			end

			if not pasteSuccess then
				print(string.format("第%d次粘贴验证失败，准备重试", pasteRetry))
				if pasteRetry < maxPasteRetry then
					sleep(500)
				end
			end
		end
	end

	if not pasteSuccess then
		print("粘贴手机号失败，已达最大重试次数")
		return false
	end

	-- 点击搜索并验证
	local searchClicked = false
	local searchRetry = 0
	while searchRetry < 3 and not searchClicked do
		searchRetry = searchRetry + 1
		print(string.format("第%d次点击搜索", searchRetry))

		-- 第一次识别搜索位置
		local searchPos1 = ocr_start(200, 250, 800, 450, "搜索")
		if searchPos1 then
			print(string.format("第一次识别搜索位置: (%d, %d)", searchPos1[1], searchPos1[2]))
		else
			print("第一次未识别到搜索位置")
		end

		-- 等待1秒后再次识别
		sleep(1000)
		local searchPos2 = ocr_start(200, 250, 800, 450, "搜索")
		if searchPos2 then
			print(string.format("第二次识别搜索位置: (%d, %d)", searchPos2[1], searchPos2[2]))
			-- 使用第二次识别结果作为点击坐标
			randomTap(searchPos2[1], searchPos2[2]-5, 20, 3, "点击搜索按钮")
		else
			print("第二次未识别到搜索位置，使用固定坐标")
			randomTap(475, 354, 20, 20, "直接点击搜索")
		end
		sleep(1500)

		-- 验证搜索结果页面是否出现（检测"添加到通讯录"或"发消息"）
		local addFriendRes = ocr_start(119, 810, 926, 1289, "添加到通讯录")
		local sendMsgRes = ocr_start(119, 810, 926, 1289, "发消息")
		if addFriendRes or sendMsgRes then
			print("搜索成功，检测到添加到通讯录或发消息")
			searchClicked = true
		else
			print(string.format("第%d次点击搜索后未检测到结果", searchRetry))
		end
	end

	-- 等待搜索结果
	local searchResult = optimizedWait(function()
		-- 检查是否已经是好友
		local isFriend = optimizedWait(function()
			local res1 = ocr_start(325, 686, 752, 1414, "发消息")
			local res2 = ocr_start(325, 686, 752, 1414, "视频通话")
			return res1 or res2
		end, 3000, 500)

		if isFriend then
			print("用户已经是好友")
			return C.handleAlreadyFriend(op_start)
		end

		-- 检查用户是否存在
		local userExists = optimizedWait(function()
			local resE = ocr_start(157, 308, 869, 480, "")
			
			-- 检查是否匹配不能加好友的配置
			if resE then
				local notAllow = config.not_allow_add_friend_config
				if notAllow then
					for _, pattern in pairs({notAllow.msg_pattern_1, notAllow.msg_pattern_2, notAllow.msg_pattern_3}) do
						if pattern and string.find(resE, pattern) then
							print("匹配到不能加好友提示:", pattern)
							return true
						end
					end
				end
			end
			return false
		end, 3000, 500)

		if userExists then
			print("用户不存在")
			return C.handleUserNotExists()
		else
			-- 默认情况：用户存在且不是好友
			print("处理新+好友业务")
			return C.handleNewFriend(op_start, tagName)
		end
	end, 3000, 1000) -- 搜索最多等待10秒

	return searchResult
end

-- ==================== 加好友结果处理 ====================
function C.handleAlreadyFriend(op_start)
    local msg = ocr_start(113,277,945,872,"")
    local project = _G.wechat_task_options and _G.wechat_task_options.project or config.project
    local phone = _G.wechat_task_options and _G.wechat_task_options.pendingPhone or ""
    local d = {msg=msg, state=2, project=project, phone=phone}
    Req.upstate(config.id_wx_ai_api_url, d)
    optimizedWait(function()
        sleep(1000)
        local b, bx, by = findPicEx(92,202,202,325,"wx_back.png|wx_back_2.png",0.9)
        if b~=-1 then randomTap(bx+12,by+20,3,5,"根据识别结果回退微信列表") else randomTap(125,252,3,5,"固定位置点击回退微信列表") end
        sleep(1000)
        local c = ocr_start(792,200,952,305,"取消")
        if c then randomTap(c[1],c[2],10,10) else randomTap(883,248,3,5) end
        return true
    end,3000,1000)
    monitor.record("已是好友：", os.time()-op_start)
    return true
end

function C.handleUserNotExists()
    local msg = ocr_start(113,277,945,872,"")
    local pay = _G.wechat_task_options and _G.wechat_task_options.payState or 1
    local project = _G.wechat_task_options and _G.wechat_task_options.project or config.project
    local phone = _G.wechat_task_options and _G.wechat_task_options.pendingPhone or ""
    local d = {msg=msg, state=7, project=project, payState=pay, phone=phone}
    Req.upstate(config.id_wx_ai_api_url, d)
    optimizedWait(function()
        local c = ocr_start(792,200,952,305,"取消")
        if c then randomTap(c[1],c[2],10,10) else randomTap(883,248,3,5) end
        local b = findPicEx(99,211,187,292,"wx_back.png",0.9)
        if b~=-1 then randomTap(b+12,b+20,3,5) else randomTap(125,252,3,5) end
        return true
    end,3000,500)
    return true
end

function C.handleUserError()
    local msg = ocr_start(113,277,945,872,"")
    local pay = _G.wechat_task_options and _G.wechat_task_options.payState or 1
    local project = _G.wechat_task_options and _G.wechat_task_options.project or config.project
    local phone = _G.wechat_task_options and _G.wechat_task_options.pendingPhone or ""
    local d = {msg=msg, state=9, project=project, payState=pay, phone=phone}
    Req.upstate(config.id_wx_ai_api_url, d)
    optimizedWait(function()
        local c = ocr_start(792,200,952,305,"取消")
        if c then randomTap(c[1],c[2],10,10) else randomTap(883,248,3,5) end
        local b = findPicEx(99,211,187,292,"wx_back.png",0.9)
        if b~=-1 then randomTap(b+12,b+20,3,5) else randomTap(125,252,3,5) end
        return true
    end,3000,500)
    return true
end

function C.handleNewFriend(op_start, tagName)
    sleep(500)
    local msg = ocr_start(90,283,947,943,"")
    local add = ocr_start(300,700,700,1200,"添加到通讯录")
    if add then randomTap(add[1],add[2],10,10) else randomTap(518,862,3,5) end
    sleep(1500)
    -- 先备注 → 再打招呼 → 再标签
    C.handleNewFriendRemark()
    C.handleInputBoxLineWrapFound()
	C.handleGreeting(config.robot_code, _G.wechat_task_options and _G.wechat_task_options.taskId or 1)
	-- 仅当tagName不为空时才处理标签
	if tagName and tagName ~= "" then
		C.handleNewFriendTag(tagName)
	else
		print("tagName为空，跳过标签处理")
	end
	sleep(300)
	C.clickSendButton()
    sleep(4000)

    -- 频繁/风险
    local freq = ocr_start(129,833,959,1288,config.add_friend_frequent_operation)
    if freq then
        msg = msg .. config.add_friend_frequent_operation
        local cf = ocr_start(166,601,915,1633,"确认")
        if cf then randomTap(cf[1]-50,cf[2]+45,20,5) end
    end

    local risk = ocr_start(111,547,954,856,config.add_friend_check_operation)
    if risk then
        msg = msg .. config.add_friend_check_operation
        local vr = ocr_start(317,1554,796,1681,"去验证")
        if vr then randomTap(vr[1]-50,vr[2]+45,20,5) end
    end

    -- 上报（先检测"添加到通讯录"或"发消息"是否存在，确保页面加载完成，最多检测5次）
    for i = 1, 5 do
        local hasAddContact = ocr_start(181, 740, 901, 1752, "添加到通讯录")
        local hasSendMsg = ocr_start(181, 740, 901, 1752, "发消息")
        if hasAddContact or hasSendMsg then
            print("检测到添加到通讯录或发消息，页面就绪，开始上报")
            break
        else
            local waitTime = math.random(2000, 3000)
            print(string.format("未检测到添加到通讯录或发消息，第%d次检测，等待%dms后重试", i, waitTime))
            sleep(waitTime)
        end
    end
	-- 等待1s后识别昵称区域
	sleep(1000)
	local nickname = ""
	local nicknameRaw = ocr_start(281, 294, 897, 501, "")
	print("昵称区域OCR原始结果:", nicknameRaw)
	if nicknameRaw and type(nicknameRaw) == "string" and nicknameRaw ~= "" then
		-- 如果包含"昵称"，保留"昵称"前面的部分作为nickname
		local idx = string.find(nicknameRaw, "昵称")
		if idx then
			nickname = string.sub(nicknameRaw, 1, idx - 1)
			print("截取昵称（保留'昵称'前部分）:", nickname)
		else
			nickname = nicknameRaw
			print("昵称区域完整内容:", nickname)
		end
	end
	local msg = ocr_start(90,283,947,943,"")
    local pay = _G.wechat_task_options and _G.wechat_task_options.payState or 1
    local project = _G.wechat_task_options and _G.wechat_task_options.project or config.project
    local phone = _G.wechat_task_options and _G.wechat_task_options.pendingPhone or ""
    local d = {msg=msg, state=3, project=project, payState=pay, nickname=nickname, phone=phone}
    Req.upstate(config.id_wx_ai_api_url, d)

    -- 返回列表
    optimizedWait(function()
        -- 先检查一次，有就直接返回
        if ocr_start(130,197,850,344,"微信") then return true end
        for i=1,3 do
            randomTap(119,252,3,2)
            sleep(800)
			if ocr_start(130,197,850,344,"微信") then return true end
            randomTap(876,250,3,5)
            sleep(800)
            -- 点击后检查，有就返回
            if ocr_start(130,197,850,344,"微信") then return true end
        end
        return false
    end,5000,500)

    monitor.record("添加好友成功：", os.time()-op_start)
    return true
end

-- ==================== 打招呼备注流程 ====================
-- @param robotCode 机器人编号
-- @param channelNum 通道编号
function C.handleGreeting(robotCode, channelNum)
    print("步骤: 处理打招呼备注流程")
    print("robotCode: " .. tostring(robotCode) .. ", channelNum: " .. tostring(channelNum))
    
    -- 参数检查
    if not robotCode or not channelNum then
        print("参数错误: robotCode和channelNum不能为空")
        return false
    end
    
    -- 调用 fetch_pending_phone 接口获取 greeting_content
    local fetchUrl = config.fetch_pending_phone_url .. "?robotCode=" .. tostring(robotCode) .. "&channelNum=" .. tostring(channelNum)
    print("请求打招呼配置: " .. fetchUrl)
    
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    
    local response_body = {}
    local res, code = http.request{
        url = fetchUrl,
        method = "GET",
        sink = ltn12.sink.table(response_body),
    }
    
    if not res or code ~= 200 then
        print("获取打招呼配置失败, HTTP状态码: " .. tostring(code))
        return false
    end
    
    local body = table.concat(response_body)
    print("打招呼配置响应: " .. body)
    
    local ok, data = pcall(jsonLib.decode, body)
    if not ok or not data or not data.success then
        print("解析打招呼配置响应失败")
        return false
    end
    
    -- 读取 greeting_content 作为招呼内容
    local greeting_value = nil
    if data.data and data.data.greeting_content and data.data.greeting_content ~= "" then
        greeting_value = data.data.greeting_content
    end
    
    if not greeting_value then
        print("greeting_content 为空，跳过打招呼")
        return false
    end
    
    print("获取到打招呼内容: " .. greeting_value)
    
    -- 调用send_msg_to_id接口发送打招呼消息
    local send_url2 = config.send_msg_to_id_url .. "?robotCode=" .. tostring(robotCode) .. "&channelNum=" .. tostring(channelNum) .. "&msg=" .. urlEncode(greeting_value)
    print("发送打招呼消息: " .. send_url2)
    
    -- GET请求发送消息
    local response_body2 = {}
    local res2, code2 = http.request{
        url = send_url2,
        method = "GET",
        sink = ltn12.sink.table(response_body2),
    }
    
    if not res2 or code2 ~= 200 then
        print("发送打招呼消息失败, HTTP状态码: " .. tostring(code2))
        return false
    end
    
    print("打招呼消息发送成功")
    
    -- 回到桌面打开ID
    print("切换回ID获取消息...")
    C.backToHomeWithCheck(2)
    sleep(300)
    C.openID(true)
    sleep(800)
    
    -- 搜索联系人获取消息
	C.searchIDOptimize(config.id_ai_project_config.name, false)
	sleep(1000)
	
	-- 获取ID消息列表
	local msgs = C.getIDMessages()
	if msgs and #msgs > 0 then
		print("获取到", #msgs, "条ID消息")
		
		-- 获取最后一条消息
		local lastMsg = msgs[#msgs]
		local msg_x = lastMsg.x + 200
		local msg_y = lastMsg.y + 60
		
		-- 长按最后一条消息复制
		print("长按复制消息")
		longTap(msg_x, msg_y)
		sleep(800)
		
		-- 查找并点击复制按钮
		local copySuccess = false
		for retry = 1, 2 do
			local idx, copy_x, copy_y = findImage(0, 0, 0, 0, "id_msg_copy2.png|id_msg_copy1.png|id_msg_copy.png|id_msg_copy3.png|id_msg_copy4.png", 0.8)
			if idx ~= -1 then
				print("点击复制按钮")
				randomTap(copy_x, copy_y, 10, 10, "点击复制")
				sleep(800)
				copySuccess = true
				break
			end
			sleep(200)
		end
		
		if copySuccess then
			print("复制成功，切回微信发送")
			-- 返回ID消息列表
			randomTap(119, 252, 3, 1)
			sleep(300)
			
			-- 切换到微信
			C.changeToWX()
			sleep(800)
			local greetingPos = ocr_start(87,325,894,891,"打招呼内容")
			if not greetingPos then
				for retry = 1, 3 do
					randomSwipe(500, 1200, 500, 600)
					sleep(1000)
					greetingPos = ocr_start(87,325,894,891,"打招呼内容")
					if greetingPos then
						print("滚动后找到打招呼内容")
						break
					end
				end
			end
			print("打招呼位置",greetingPos)
			
			if greetingPos then
				randomTap(greetingPos[1]+538, greetingPos[2]+85, 10, 3, "点击打招呼区域")
				sleep(1000)

				-- 111,484,750,730区域查找"添加图片"
				local addImgPos = ocr_start(111, 484, 750, 730, "添加图片")
				if addImgPos then
					print("找到添加图片，长按y-150位置")
					longTap(addImgPos[1], addImgPos[2] - 150)
					sleep(2000)

					-- 147,399,888,619查找"全选"
					local selectAllPos = nil
					for selRetry = 1, 3 do
						selectAllPos = ocr_start(110,307,900,671, "全选")
						if selectAllPos then break end
						sleep(500)
					end
					if selectAllPos then
						print("找到全选，点击全选")
						randomTap(selectAllPos[1], selectAllPos[2], 5, 5, "点击全选")
						sleep(2500)

						-- 113,274,914,734区域查找"粘贴"
						local pastePos = ocr_start(113, 274, 914, 734, "粘贴")
						if pastePos then
							print("找到粘贴，点击粘贴")
							randomTap(pastePos[1], pastePos[2], 5, 5, "点击粘贴")
							sleep(500)
						end
					else
						sleep(800)
						-- 没有全选，检测粘贴
						print("未找到全选，检测粘贴")
						local pastePos = ocr_start(147, 399, 888, 619, "粘贴")
						if pastePos then
							print("找到粘贴，点击粘贴")
							randomTap(pastePos[1], pastePos[2], 5, 5, "点击粘贴")
							sleep(500)
						end
					end
				end

				C.closeInputMethodIfNeeded()
			end
		end
	end
	
	print("打招呼备注流程完成")
	return true
end

-- 复制ID发消息下最新一条消息
function C.copyLatestIDMessage()
    print("复制ID发消息下最新一条消息")
    
    -- 点击消息输入框区域进入聊天
    randomTap(450, 1750, 10, 5)
    sleep(800)
    
    -- 获取最新消息位置
    local msg_region = {x1 = 100, y1 = 400, x2 = 900, y2 = 1600}
    local latest_msg = ocr_start(msg_region.x1, msg_region.y1, msg_region.x2, msg_region.y2, "")
    
    if latest_msg and latest_msg[1] then
        print("找到最新消息: " .. tostring(latest_msg))
        -- 长按复制消息
        longPress(latest_msg[1], latest_msg[2], 1000)
        sleep(800)
        
        -- 点击复制按钮
        local copy_btn = ocr_start(300, 1500, 700, 1700, "复制")
        if copy_btn then
            randomTap(copy_btn[1], copy_btn[2], 10, 10)
            print("已复制消息")
        else
            -- 尝试点击全选复制
            local select_all = ocr_start(300, 1500, 700, 1700, "全选")
            if select_all then
                randomTap(select_all[1], select_all[2], 10, 10)
                sleep(300)
                local copy_btn2 = ocr_start(300, 1500, 700, 1700, "复制")
                if copy_btn2 then
                    randomTap(copy_btn2[1], copy_btn2[2], 10, 10)
                end
            end
        end
    else
        print("未找到最新消息")
    end
    
    sleep(500)
    -- 回退
    randomTap(119, 252, 3, 5)
    sleep(500)
end

-- 回退到ID消息列表
function C.backToIDMessageList()
    print("回退到ID消息列表")
    optimizedWait(function()
        local id_list = ocr_start(100, 200, 400, 350, "发消息")
        if id_list then
            return true
        end
        randomTap(119, 252, 3, 5)
        sleep(800)
        return false
    end, 1000, 500)
end

-- ==================== 备注手机号 ====================
function C.handleNewFriendRemark()
		print("步骤：处理新好友备注")
    local res = ocr_start(111,618,957,898,"备注")

    local x1,y1,x2,y2
    if res then
        x1 = res[1]-50
        y1 = res[2]+60
        x2 = res[1]+640
        y2 = res[2]+150
		print("【备注】动态获取输入框范围查找",x1,y1,x2,y2)
    else
		print("【备注】固定输入框范围查找",x1,y1,x2,y2)
        x1,y1,x2,y2 = 172,776,882,881
    end
	sleep(1000)
    local txt = ocr_start(x1,y1,x2,y2,"")
	print("查找【备注】输入框对应内容",txt)
    if not txt or not string.match(txt, config.phone_pattern) then
        local lx = x1 + math.random(300,500)
        local ly = y1 + math.random(30,50)
        if utf8.length(txt or "")>1 and txt ~= "添加备注" then
            for _=1,3 do
                randomTap(x1+math.random(30,500),ly,5,0,"点击输入框")
                sleep(1000)
                local idx, mx, my = findPicEx(746,738,915,916,"wx_addFriend_del_name1.png",0.9)
                if idx~=-1  then
                    randomTap(mx+5,my,1,1,"点击删除已有备注")
                    sleep(1000)
                    local aft = ocr_start(x1,y1,x2,y2,"")
                    if utf8.length(aft or "")<=1 or string.match(aft, config.phone_remark_default) then break end
                end
            end
        end

        -- 粘贴
        local ok = false
        for _=1,5 do
            longTap(lx,ly)
            sleep(2000)
            local p = false
            -- 方式1: OCR在宽范围内搜索"粘贴"
            for __=1,3 do
                p = ocr_start(50, 400, 950, 1350, "粘贴")
                if p then
                    print("OCR找到'粘贴':", p[1], p[2])
                    break
                end
                sleep(500)
            end
            -- 方式2: OCR失败则用ocr_start_with_boxes精确获取粘贴坐标
            if not p then
                local boxes = ocr_start_with_boxes(50, 400, 950, 1350)
                if boxes then
                    for _, box in ipairs(boxes) do
                        if box.words and string.find(box.words, "粘贴") then
                            -- 取box右下角附近作为点击位置
                            p = {box.x + box.width - 20, box.y + box.height / 2}
                            print("box识别找到'粘贴':", p[1], p[2])
                            break
                        end
                    end
                end
            end
            if p then
                randomTap(p[1], p[2], 3, 3, "OCR识别到粘贴-点击粘贴")
                sleep(1000)
                local c = ocr_start(x1, y1, x2, y2, "")
                if c and string.match(c, config.phone_pattern) then
                    ok = true
                    break
                else
                    print("粘贴后未检测到手机号，OCR结果:", tostring(c))
                end
            else
                -- 方式3: 所有识别失败，尝试固定位置点击粘贴
                print("未识别到'粘贴'，使用固定位置")
                sleep(1000)
				local addRemarkPos = ocr_start(x1, y1, x2, y2, "添加备注")
				print("固定位置查找添加备注",addRemarkPos)
                if addRemarkPos then
					longTap(addRemarkPos[1],addRemarkPos[2],1,1,"点击添加备注位置查找粘贴")
					sleep(1000)
					local p = ocr_start(50, 400, 950, 1350, "粘贴")
					if p then
						randomTap(p[1],p[2],1,1,"保底点击粘贴")
						ok = true
						break
					end
                end
            end
        end
    end
end



-- 处理好友标签逻辑
-- ==================== 输入法关闭 ====================
function C.handleInputBoxLineWrapFound()
    for _=1,3 do
        sleep(1000)
        local nl = ocr_start(767,1583,961,1900,"换行")
        local sign = ocr_start(89,1646,443,1940,"符号")
        if not nl and not sign then return true end
        local idx, x, y = findPicEx(788,1218,969,1360,"hide_inputBox.png",0.9)
        if idx~=-1 then
            randomTap(x+45,y+35,5,5)
        else
            randomTap(500,1000,5,5)
        end
    end
    return false
end

-- ==================== 消息发送 ====================
function C.sendMsgOptimize(parts, img)
    local s = os.time()
    for i=1,2 do
        if C.sendMsgSingleAttempt(parts, img, s) then return true end
        sleep(1000)
    end
    monitor.record("发送消息失败", os.time()-s)
    return false
end

function C.sendMsgSingleAttempt(parts, img, s)
    C.openIDOptimize()
    if not C.searchIDOptimize(config.id_ai_project_config.name, false) then return false end
    local msgs = C.getIDMessages()
    if not msgs or #msgs <1 then return false end

    local base = #msgs - parts
    for i=1,parts do
        local idx = base + i
        if idx > #msgs then break end
        if not C.processSingleMessage(msgs[idx]) then return false end
    end

    C.backToIDMessageList()
    if img>0 then C.sendImageInWeChat(img) end
    C.backToWeChatMessageList()
    monitor.record("发送成功", os.time()-s)
    return true
end

function C.searchIDOptimize(name, red)
    for _=1,2 do
        local ok = optimizedWait(function()
            local r = ocr_start(230,416,817,1717,name)
            if not r then return false end
            if red then
                if C.checkRedPoint(r[1],r[2]) then
                    randomTap(r[1],r[2],3,5)
                    sleep(1500)
                    return true
                end
                return false
            else
                randomTap(r[1],r[2]+5,5,5)
                sleep(1500)
                return true
            end
        end,2000,1000)
        if ok then return true end
    end
    return false
end

function C.checkRedPoint(x,y)
    local idx = findPic(x+500,y,937,y+100,"ID_redp1.png|ID_redp1_1.png","101010",0,0.8)
    if idx~=-1 then return true end
    local ret = findColor(x+500,y,937,y+100,"9c2f2c|9b2e29|992c27|9a2c27|9a2a27",0,1)
    return ret~=-1
end

function C.getIDMessages()
	sleep(500)
    for _=1,2 do
        local arr = findPicAllPoint(209,289,368,1821,config.id_ai_project_config.logo,0.9)
		print("查找图标数组",arr)
        if arr and #arr>0 then return arrSortByY(arr) end
        sleep(1000)
    end
    return nil
end

function C.processSingleMessage(msg)
    local x = msg.x+200
    local y = msg.y+60
    longTap(x,y)
    sleep(1000)

    local copy = optimizedWait(function()
        local idx, cx, cy = findImage(0,0,0,0,"id_msg_copy2.png|id_msg_copy1.png|id_msg_copy.png|id_msg_copy3.png|id_msg_copy4.png",0.8)
        if idx~=-1 then
            randomTap(cx,cy,10,10)
            sleep(1000)
            return true
        end
        return false
    end,3000,1000)
    if not copy then return false end

    C.openWeChatOptimize()
    if not C.pasteAndSendInWeChat() then return false end
    C.openIDOptimize()
    return true
end

function C.pasteAndSendInWeChat()
    if not optimizedWait(function()
        local sp = ocr_start(393,1753,665,1845,"空格")
        if sp then return true end
        randomTap(475,1794,10,10)
        return false
    end,3000,1500) then return false end

    optimizedWait(function()
        local clip = ocr_start(90,202,630,535,"来自剪贴板")
        if clip then
            randomTap(457,1311,3,5)
        else
            randomTap(457,1311,3,5)
            sleep(1500)
            randomTap(169,1768,3,5)
        end
        sleep(1000)
        return true
    end,3000,500)

    return optimizedWait(function()
        local s = ocr_start(775,1122,945,1272,"发送")
        if s then randomTap(s[1],s[2],5,5) else randomTap(859,1196,5,5) end
        sleep(1000)
        return true
    end,3000,500)
end

function C.backToIDMessageList()
    return optimizedWait(function()
        local idx, x, y = findImage(0,0,200,350,"msg_bak.png|msg_back_1.png",0.9)
        if idx~=-1 then
            randomTap(x+10,y+25,5,2)
            sleep(800)
            return true
        end
        return false
    end,2400,800)
end

function C.backToWeChatMessageList()
	return optimizedWait(function()
		randomTap(126, 224, 10, 10, "返回微信消息列表")
		sleep(1000)
		return true
	end, 2000, 1000)
end

function C.sendImageInWeChat(n)
    if not optimizedWait(function()
        local a = ocr_start(145,1328,325,1538,"相册")
        if a then
            randomTap(a[1],a[2]-70,10,10)
            return true
        end
        local sp = ocr_start(393,1753,665,1845,"空格")
        if sp then randomTap(894,1199,5,5) else randomTap(897,1797,5,5) end
        sleep(1500)
        return false
    end,5000,1000) then return false end

    sleep(1000)
    if n==1 then randomTap(400,385,10,10) else randomTap(183,398,10,10) end
    sleep(1000)

    return optimizedWait(function()
        local s = ocr_start(735,1735,964,1862,"发送")
        if s then randomTap(s[1],s[2],10,10) else randomTap(850,1794,10,10) end
        sleep(1000)
        return true
    end,3000,500)
end

-- ==================== 主动联系未支付用户模块 ====================
C.reminderConfig = {
    next_url = "http://192.168.1.23:5001/api/reminder/next",
    send_url = "http://192.168.1.23:5001/api/reminder/send",
}

-- 辅助函数：输入文本到搜索框（参考已有粘贴代码）
function C.inputSearchText(search_content)
    -- 点击搜索框准备输入
    local acc = ocr_start(200, 250, 800, 450, "搜索")
    if acc then
        randomTap(acc[1], acc[2], 10, 10)
    else
        randomTap(500, 350, 50, 10)
    end
    sleep(800)
    
    -- 参考已有粘贴代码：先尝试粘贴图标
    local pasteIdx, pasteX, pasteY = findImage(97, 1148, 252, 1352, "mate30_search_friend_paste.png", 0.9)
    if pasteIdx ~= -1 then
        pasteX = pasteX + 120 + math.random(5, 120)
        pasteY = pasteY + 20
        randomTap(pasteX, pasteY, 120, 0, "点击输入法粘贴")
    else
        -- 未检测到粘贴图标，手动粘贴
        longTap(259, 246)
        sleep(1000)
        local pasteRes = ocr_start(108, 265, 906, 461, "粘贴")
        if pasteRes then
            randomTap(pasteRes[1], pasteRes[2], 20, 10, "点击粘贴位置")
        else
            randomTap(181, 378, 20, 10, "点击固定粘贴位置")
        end
    end
    sleep(1500)
end

-- 辅助函数：关闭输入法
function C.closeInputMethodIfNeeded()
    for i = 1, 3 do
        sleep(1500)
        local nl = ocr_start(767, 1583, 961, 1900, "换行")
        local sign = ocr_start(89, 1646, 443, 1940, "符号")
        if not nl and not sign then
            return true
        end
        local idx, x, y = findPicEx(788, 1218, 969, 1360, "hide_inputBox.png", 0.9)
		local idx1, x1, y1 = findPicEx(788, 1218, 969, 1360, "hide_inputBox1.png", 0.9)
		print("查找关闭输入法图标结果",idx,x,y)
        if idx ~= -1 then
            randomTap(x + 45, y + 35, 5, 5,"点击关闭输入法图标1")
		elseif idx1 ~= -1 then
			randomTap(x1+45,y1+50,5,5,"点击关闭输入法图标2")
	
        else
            randomTap(881,1290, 5, 5,"点击默认关闭输入法位置")
        end
    end
    return false
end

-- 辅助函数：粘贴文本到聊天框（参考已有粘贴代码）
function C.pasteToInputBox(msg_content)
    -- 点击输入框激活
    randomTap(500, 1100, 50, 20)
    sleep(1000)
    
    -- 参考已有粘贴代码
    local pasteIdx, pasteX, pasteY = findImage(97, 1148, 252, 1352, "mate30_search_friend_paste.png", 0.9)
    if pasteIdx ~= -1 then
        pasteX = pasteX + 120 + math.random(5, 120)
        pasteY = pasteY + 20
        randomTap(pasteX, pasteY, 120, 0, "点击输入法粘贴")
    else
        -- 未检测到粘贴图标，手动粘贴
        longTap(500, 1100)
        sleep(1000)
        local pasteRes = ocr_start(108, 265, 906, 461, "粘贴")
        if pasteRes then
            randomTap(pasteRes[1], pasteRes[2], 20, 10, "点击粘贴位置")
        else
            randomTap(350, 500, 20, 10, "点击固定粘贴位置")
        end
    end
    sleep(1500)
end

-- 辅助函数：点击发送按钮
function C.clickSendButton()
	sleep(1000)
    local sendBtn = ocr_start(775, 1122, 945, 1272, "发送")
    if sendBtn then
        randomTap(sendBtn[1], sendBtn[2], 5, 5)
    else
        randomTap(534,1750, 5, 5)
    end
    sleep(500)
end

function C.handleReminder(options)
    options = options or {}
    local robot_code = options.robot_code or ""
    local channel_num = options.channel_num or 1
    
    print("正在获取未支付用户信息...")
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    
    local url = string.format("%s?robot_code=%s&channel_num=%d", 
        C.reminderConfig.next_url, robot_code, channel_num)
    
    local response_body = {}
    local res, code = http.request{
        url = url,
        sink = ltn12.sink.table(response_body),
        method = "GET",
    }
    
    if not res or code ~= 200 then
        print("获取未支付用户失败，HTTP错误码: " .. tostring(code))
        return false
    end
    
    local response_text = table.concat(response_body)
    local api_data = jsonLib.decode(response_text)
    
    if not api_data or not api_data.success then
        print("获取未支付用户失败或无数据")
        return false
    end
    
    if not api_data.data or not api_data.data.uid then
        print("无待处理的未支付用户")
        return false
    end
    
    local user_data = api_data.data
	print("user_data"..jsonLib.encode(user_data))
    print(string.format("获取到用户: %s, UID: %d", user_data.nickname or "", user_data.uid))
    
    -- 获取手机号作为搜索条件
    local phone = tostring(user_data.phone or "")
    if phone == "" then
        print("用户手机号为空")
        return false
    end
    print("获取到手机号: " .. phone)
    
    -- ========== 流程：切到ID复制手机号 -> 切回微信搜索 ==========
    
    if not C.getIDPhone(config.id_ai_project_config.receive_name) then return false end
    if not C.openWeChatOptimize() then 
        print("openWeChatOptimize失败，使用changeToWXWithCheck")
        C.changeToWXWithCheck()
    end
    
    -- 5. 打开搜索框
    print("5. 打开微信搜索框...")
		local index,x,y = findImage(699,203,906,339,"wx_search_btn.png",0.9)
		if index ~= -1 then
			randomTap(x, y, 10, 10,"图片识别点击搜索")
		else
			randomTap(791,253, 10, 10,"固定位置点击搜索")
		end
		sleep(2000)
		
		-- 6. 粘贴手机号搜索（带验证重试）
		print("6. 粘贴手机号搜索...")
		local pasteSuccess = false
		for pasteTry = 1, 3 do
			print("粘贴尝试第" .. pasteTry .. "次")
			local pasteIdx, pasteX, pasteY = findImage(93,1220,512,1851, "mate30_search_friend_paste.png", 0.9)
			if pasteIdx ~= -1 then
				pasteX = pasteX + 120 + math.random(5, 120)
				pasteY = pasteY + 20
				randomTap(pasteX, pasteY, 120, 0, "点击输入法粘贴")
			else
				local search_pos = ocr_start(108, 265, 906, 461, "搜索")
				if search_pos then
					print("长按搜索位置")
					longTap(search_pos[1]+5, search_pos[2])
				else
					print("长按固定搜索位置")
					longTap(360,274)
				end
			end
			sleep(1500)
			
			-- 验证粘贴结果
			local verifyOcr = ocr_start(100, 300, 600, 450, "")
			if verifyOcr and #tostring(verifyOcr) > 3 then
				print("粘贴验证成功")
				pasteSuccess = true
				break
			end
			sleep(500)
		end
		
		if not pasteSuccess then
			print("粘贴失败")
			C.weChatBack()
			return false
		end
		sleep(500)
		
		-- 7. 点击搜索结果（带验证重试）
		print("7. 点击搜索结果...")
		local contactFound = false
		for contactTry = 1, 3 do
			print("查找联系人第" .. contactTry .. "次")
			sleep(1000)
			local contact = ocr_start(217,397,922,611, phone)
			if contact then
				print("找到联系人，点击，坐标:"..contact[1]..","..contact[2])
				randomTap(contact[1], contact[2], 10, 10,"点击联系人位置")
				sleep(1000)
				-- 验证是否进入聊天页面
				local chatVerify =  findImage(114,1770,271,1924,"chat_box_left_btn.png",0.9)
				if chatVerify ~= -1 then
					print("已进入聊天页面")
					contactFound = true
					break
				end
			end
			sleep(800)
		end
		
		if not contactFound then
			print("未找到联系人: " .. phone)
			C.weChatBack()
			return false
		end
		sleep(500)
		
		-- 获取消息内容
		local msg_to_send = user_data.message or user_data.msg or ""
		if msg_to_send == "" then
			print("消息内容为空")
			C.weChatBack()
			return false
		end
		
		-- 粘贴并发送
		C.closeInputMethodIfNeeded()
		C.pasteToInputBox(msg_to_send)
		sleep(300)
		C.clickSendButton()
		sleep(500)
		
		-- 调用 send_url 更新接口
		print("通知服务器发送成功...")
		local send_url = C.reminderConfig.send_url
		local post_data = jsonLib.encode({
			robot_code = robot_code,
			channel_num = channel_num,
			uid = user_data.uid
		})
		
		local response_body2 = {}
		local res2, code2 = http.request{
			url = send_url,
			sink = ltn12.sink.table(response_body2),
			method = "POST",
			headers = {
				["Content-Type"] = "application/json",
				["Content-Length"] = #post_data
			},
			source = ltn12.source.string(post_data),
		}
		
		if res2 and code2 == 200 then
			print("服务器更新成功")
		else
			print("服务器更新失败，错误码: " .. tostring(code2))
		end
		
		-- 回退列表
		print("回退列表...")
		C.weChatBack()
		sleep(300)
		C.weChatBack()
    sleep(300)
    
    print("主动联系未支付用户完成")
    return true
end

-- ==================== 发送多条微信消息 ====================
-- 发送多条微信消息
function C.sendMessages(msg_parts, send_img)
	local op_start = os.time()
	-- 打开id
	-- 进入聊天界面
	C.searchID(config.id_ai_project_config.name, false)
	
	
	local arr = nil
	local maxRetry = 3
	local retryCount = 0

	-- 带重试的消息记录检测
	while retryCount < maxRetry do
		sleep(1000)
		arr = findPicAllPoint(191,324,394,1738,"id_yifang_logo2.png",0.9)

		-- 检查数组是否为空
		if not arr or #arr == 0 then
			retryCount = retryCount + 1
			print("未找到消息记录，第"..retryCount.."次重试，等待1秒后重新检测")
		
			sleep(1000)
			msgPos = ocr_start(102,231,236,917,config.id_customer.customer_1)
			if msgPos then
				randomTap(msgPos[1],msgPos[2]-10,5,1,"点击发消息位置")
			end
		else
			break
		end
	end

	-- 最终检查
	if not arr or #arr == 0 then
		print("重试"..maxRetry.."次后仍未找到消息记录，跳过发送，返回微信")
		-- 返回微信界面并确保在列表
		C.changeToWXWithCheck()
		return false
	end

-- 方案1：当识别消息数小于api返回时只取实际识别的消息数
--	if #arr < msg_parts then
		-- msg_parts = #arr
--	end

	--方案2：计算消息数据小于msg_parts时且msg_part == 2时特殊处理

	print("识别消息条数",#arr,"AI回复消息条数",msg_parts,"识别坐标位置",arr)
	if (msg_parts == 2 and #arr == 1) then
		print(arr[1][x],arr[1][y])
		local x1 = arr[1].x
		local y1 = arr[1].y
		table.insert(arr,{x = x1,y = y1 - 200})
		print("新数组结果",arr)

	elseif #arr < msg_parts and msg_parts ~= 2	then
		 msg_parts = #arr
	end
	arr = arrSortByY(arr) -- 按从上到下排序
	print("查找ID-详情的记录数",arr)

	base_msg_nu = #arr - msg_parts -- 只取最后msg_parts条消息
	
	print("base_msg_nu", base_msg_nu)

	-- 循环发送
	for i = 1, msg_parts do
		msg_nu = base_msg_nu + i
		-- 检查索引是否有效
		if msg_nu < 1 or msg_nu > #arr then
			print("消息索引超出范围："..msg_nu.."，跳过")
		else
			-- 消息坐标
			print(arr[msg_nu])
			msg_x = arr[msg_nu]["x"] + 200
			msg_y = arr[msg_nu]["y"] + 60
			print("这是第 " .. i .. " 条消息", arr[msg_nu], msg_x, msg_y)

		-- 长按消息
		longTap(msg_x, msg_y)
		sleep(1000)

		-- 查找复制按钮
		local n = 0
		while true do
			n = n + 1
			if n <= 5 then
				local rey, id_msg_copy_x, id_msg_copy_y = findImage(0, 0, 0, 0, "id_msg_copy2.png|id_msg_copy1.png|id_msg_copy.png|id_msg_copy3.png|id_msg_copy4.png", 0.8)
				print("第"..n.."次查找id 复制按钮：", rey, id_msg_copy_x, id_msg_copy_y)

				if rey ~= -1 then
					print("点击复制")
					randomTap(id_msg_copy_x, id_msg_copy_y, 10, 10, "点击复制")
					sleep(1000)
					break
				end
			else
				sleep(1000)
				print("超过5次未识别到复制按钮,改为文字识别复制")
				local rey = ocr_start(94,217,267,1744,"复制")
				print("ocr识别复制结果",rey)
				if rey then
					randomTap(rey[1], rey[2] - 35, 5, 5, "点击复制按钮")
					break
				else
					-- OCR也未识别到，跳出循环避免死循环
					print("OCR也未识别到复制按钮，跳过此消息")
					break
				end
			end
		end

		-- 切换微信进行粘贴 并发送
		-- 切换到微信
		sleep(1000)
		C.changeToWX()

		-- 输入法粘贴  并发送
		sleep(1000)
		C.doPaste()

		-- 切换回id
		sleep(1000)
		C.changeToID()
		end
	end
	--获取返回按键配置
	local ret_pos =  config.meta30_config.ret_list_bt_pos
	sleep(500)
	-- 所有消息发完了，返回到了id，点击返回按钮
	--randomTap(ret_pos.x, ret_pos.y, ret_pos.offSetX, ret_pos.offsetY, "id返回消息列表")
	--返回ID列表保底
	--C.IDReChangeToList(ret_pos)

	local retIDListClicked = optimizedWait(function()
		-- OCR识别"转发"文字（通常在弹出菜单中）
		sleep(2000)
		local res = ocr_start(254,449,720,1747, config.id_ai_project_config.mark)
		--local res1 = ocr_start(109,398,690,1736, config.id_ai_project_config.name)
		print("校验当前是否在ID列表",res)
		if res then
			print("已经在智企ID列表")
			return true
		else
			randomTap(ret_pos.x, ret_pos.y, ret_pos.offSetX, ret_pos.offsetY, "id返回消息列表")
			sleep(800)
			local mark = ocr_start(254,449,720,1747, config.id_ai_project_config.mark)
			local msgMark = ocr_start(118,1731,406,1925,"消息")
			print("校验当前是否在ID列表",res)
			if res or msgMark then
				return true
			else
				randomTap(ret_pos.x, ret_pos.y, ret_pos.offSetX, ret_pos.offsetY, "id重新返回消息列表")
				return true
			end
		
		end
		return false
	end, 5000, 400)
	if not retIDListClicked then
		print("点击回退ID列表失败")
		return false
	end
	-- 返回微信
	sleep(1000)
	C.changeToWX()

	if send_img > 0 then
		print("发送图片")
		C.sendImages(send_img)
	end
	

	sleep(1000)
	
	-- 返回微信消息列表
	C.backToWeChatMessageList()

	local duration = os.time() - op_start
	monitor.record("发送多条微信消息：", duration)
	return true
end


-- 在微信聊天窗口，回复完消息后，发送图片，
function C.sendImages(send_img_nu)
	local op_start = os.time()
	-- 查找相册

	while true do
		sleep(1000)
		local res = ocr_start(121, 1432, 340, 1615, "相册")
		print("查找相册", res)
		sleep(1000)
		if res then
			randomTap(res[1], res[2] - 70, 10, 10, "相册")
			break
		else
			--local resA = ocr_start(393, 1753, 665, 1845, "空格")
			local resA = ocr_start(692,1685,941,1897, "换行")
			print("查找换行", resA)

			if resA then
				print("找到换行，说明输入框已经打开")
				randomTap(889,1165, 5, 5, "加号")
				sleep(1000)
			else
				print("没找到换行，点击加号")
				randomTap(897,1821, 5, 5, "输入法没打开时候的加号")
				sleep(1500)
			end
		end
	end

	sleep(1000)

	if send_img_nu == 1 then
		randomTap(400, 385, 10, 10, "选图1") -- 优惠
	elseif send_img_nu == 2 then
		randomTap(183, 398, 10, 10, "选图2") -- 押金
	end

	sleep(1000)

	-- 发送
	local res = ocr_start(735, 1735, 964, 1862, "发送")
	print("查找发送按钮", res)

	if res then
		randomTap(res[1], res[2], 10, 10, "发送")
	else
		randomTap(850, 1794, 10, 10, "发送")
	end

	sleep(1000)

	local duration = os.time() - op_start
	monitor.record("微信聊天窗口，回复完消息后，发送图片：", duration)
end

-- 微信聊天界面 输入法的粘贴
function C.doPaste()
	-- 点击输入框
	sleep(1000)

	-- 输入框点击重试机制
	local inputBoxRetry = 0
	local maxRetry = 3
	local inputBoxOpened = false

	while inputBoxRetry < maxRetry and not inputBoxOpened do
		inputBoxRetry = inputBoxRetry + 1
		print(string.format("第%d次尝试打开输入框", inputBoxRetry))

		-- 先检测是否已经打开
		local res = ocr_start(616,1617,972,1905, "换行")
		print("查找换行", res)

		if res then
			print("找到换行，说明输入框已经打开")
			inputBoxOpened = true
			break
		end

		-- 未打开，尝试点击输入框
		print("直接点击输入框")


		-- 方法1：图片识别点击
		local index = -1
		local x = -1
		local y = -1
		index,x,y = findImage(112,1780,194,1891,"chat_box_left_btn.png|chat_box_left_btn1.png",0.9)
		print("查找输入框左侧图标res:", index, x, y)

		if index ~= -1 then
			x = x + 180
			y = y + 35
			randomTap(x, y, 10, 10, "根据图片位置点击输入框")
		else
			-- 方法2：固定位置点击
			randomTap(475, 1794, 30, 30, "直接点击输入框")
		end

		-- 等待并验证是否打开
		sleep(1500)
		res = ocr_start(616,1617,972,1905, "换行")
		fuhao = ocr_start(118,1431,554,1944,"符号")
		print("点击后查找换行:", res)
		print("点击后查找符号",fuhao)

		if res or fuhao then
			print("输入框已打开")
			inputBoxOpened = true
		else
			print(string.format("第%d次点击输入框后仍未打开", inputBoxRetry))
			if inputBoxRetry < maxRetry then
				sleep(500)
			end
		end
	end

	if not inputBoxOpened then
		print("多次尝试后输入框仍未打开，继续执行粘贴操作")
	end
	sleep(1000)

	-- 粘贴操作统一重试机制
	local pasteSuccess = false
	local pasteRetry = 0
	local maxPasteRetry = 5

	while pasteRetry < maxPasteRetry and not pasteSuccess do
		pasteRetry = pasteRetry + 1
		print(string.format("=== 第%d次尝试粘贴 ===", pasteRetry))

		local res = ocr_start(496,1187,925,1354, "高情商回复")
		--查找剪切板内容
		local pasteRes,x,y = findPicEx(98,1059,428,1483,"mate30_search_friend_paste.png",0.9)
		print("高情商回复", res)
		print("查找到粘贴图标对应位置",pasteRes,x,y)

		if res then
			print("找到高情商回复，说明剪切板有内容")
			randomTap(res[1] - 500,res[2], 150, 5, "点击剪切板内容")
			sleep(1000)
		elseif pasteRes ~= -1 then
			randomTap(x+80,y+20,30,10,"点击图片查找的粘贴位置")
			sleep(1000)
		else
			-- 点击输入框后优先检测粘贴
			print("未找到快捷粘贴，点击输入框后检测粘贴")
			randomTap(263, 1157, 50, 30, "点击输入框")
			sleep(1500)
			
			-- 检测粘贴选项是否出现
			local ocrPasteRes = ocr_start(120,948,893,1888, "粘贴")
			if ocrPasteRes then
				print("找到粘贴选项，点击粘贴")
				randomTap(ocrPasteRes[1], ocrPasteRes[2], 10, 5, "点击粘贴")
				sleep(1000)
			else
				-- 尝试长按输入框唤醒粘贴选项
				print("点击未找到粘贴，尝试长按输入框唤醒粘贴")
				longTap(263, 1157)
				sleep(2000)
				-- 尝试扩大范围检测
				print("查找粘贴位置")
				ocrPasteRes = ocr_start(50, 950, 300, 1300, "粘贴")
				if ocrPasteRes then
					print("模糊匹配到粘贴选项，点击")
					randomTap(math.floor(ocrPasteRes[1]), math.floor(ocrPasteRes[2]), 10, 5, "点击粘贴(模糊匹配)")
					sleep(1000)
				else
					print("未检测到粘贴选项")
				end
			end
		end

		-- 每次点击粘贴后校验右侧区域是否有"发送"
		sleep(1500)  -- 粘贴后等待界面更新
		local sendCheck = ocr_start(645, 1073, 972, 1296, "发送")
		if sendCheck then
			print("粘贴成功，检测到发送按钮")
			pasteSuccess = true
		else
			print("粘贴后未检测到发送按钮，重试")
			-- 点击空白区域关闭可能的菜单
			randomTap(500, 1500, 50, 50, "点击空白关闭菜单")
			sleep(1000)
		end
	end

	if not pasteSuccess then
		print("多次尝试粘贴失败，继续执行后续操作")
	end

	-- 发送操作（带校验重试）
	local sendRetry = 0
	local maxSendRetry = 3
	local sendComplete = false

	while sendRetry < maxSendRetry and not sendComplete do
		sendRetry = sendRetry + 1
		print(string.format("=== 第%d次尝试发送 ===", sendRetry))

		-- 点击发送
		local resA = ocr_start(645, 1073, 972, 1296, "发送")
		print("发送按钮检测结果", resA)

		if resA then
			randomTap(resA[1], resA[2], 5, 5, "点击发送")
			sleep(1000)
		else
			-- 扩大范围查找
			resA = ocr_start(656, 930, 936, 1917, "发送")
			if resA then
				randomTap(resA[1], resA[2], 5, 5, "点击发送(扩大范围)")
				sleep(1000)
			else
				randomTap(859, 1165, 30, 10, "直接点击发送")
				sleep(1000)
			end
		end
		sleep(1000)
		-- 校验同一区域是否还存在"发送"按钮
		local sendCheck = ocr_start(645, 1073, 972, 1296, "发送")
		if sendCheck then
			print("发送按钮仍存在，说明消息未发送成功，重试")
		else
			print("发送按钮已消失，消息发送成功")
			sendComplete = true
		end
	end

	if not sendComplete then
		print("多次尝试发送失败")
	end

	return sendComplete
end


-- *********** 转发微信小程序（下划方式）***********
-- 参数：
--   targetContact: 要转发到的联系人名称
-- 返回：成功返回true，失败返回false
function C.forwardMiniApp(targetContact)
	print("昵称长度...",utf8.length(targetContact))
	if utf8.length(targetContact) > 24 then
		targetContact = utf8.mid(targetContact,1,10)
	end
	sleep(800)

	-- 检测并返回微信列表（带重试机制）
	local wxListRetry = 0
	local maxWxListRetry = 5
	while wxListRetry < maxWxListRetry do
		local wxListCheck = ocr_start(438,204,603,285,"微信")
		print("检测微信列表:", wxListCheck)
		if wxListCheck ~= false then
			break
		end
		wxListRetry = wxListRetry + 1
		print("第" .. wxListRetry .. "次尝试返回微信列表")
		randomTap(121,246,5,3,"点击返回微信列表,优先转发小程序")
		sleep(500)
	end

	local op_start = os.time()
	print("开始转发微信小程序（下划方式）")
	
	sleep(1000)
	print("识别并点击第一个小程序")
	local firstMiniProgramFound = optimizedWait(function()
		print("下划打开小程序列表")
		-- 从下往上滑动，打开小程序列表
		swipe(500, 400, 500, 900, 800)
		sleep(2000)
		-- 尝试OCR识别小程序列表中的小程序
		
		local topContent = ocr_start(306,201,722,316,"最近")
		if topContent then
			sleep(1000)
			local res = ocr_start(127,478,544,794, "家")
			print("通过OCR找到小程序列表")
			if res then
				-- 点击第一个小程序的位置（通常在识别位置附近）
				randomTap(res[1], res[2] + 40, 10, 10, "点击第一个小程序")
				return true
			else
				randomTap(234,800,10,10,"固定位置点击第一个小程序")
				return true
			end
			
		end
		return false
	end, 3000, 2000)
	
	if not firstMiniProgramFound then
		-- 如果OCR识别失败，尝试点击小程序列表的固定位置（第一个位置通常在650像素高度）
		print("OCR识别失败，尝试点击固定位置的小程序")
		randomTap(500, 650, 100, 50, "点击第一个小程序（固定位置）")
	end
	
	sleep(2000)

	print("点击右上角固定位置")
	randomTap(750,256, 10, 5, "点击三个点菜单（固定位置）")
	
	sleep(800)
	
	-- 步骤4: 在弹出菜单中选择"转发"
	print("点击转发选项")
	local n = 0
	local forwardOptionClicked = optimizedWait(function()
		-- OCR识别"转发"文字（通常在弹出菜单中）
		n = n + 1
		sleep(1000)
		local res = ocr_start(68,1158,445,1498, "转发给朋友")
		print("转发给朋友识别结果",res)
		if res then
			print("找到转发选项:", res[1], res[2])
			randomTap(res[1], res[2] - 70, 20, 20, "点击转发")
			return true
		elseif n == 3 then
			print("第"..n,"次识别不到转发给朋友,再次点击右上角固定位置")
			randomTap(750,256, 10, 5, "点击三个点菜单（固定位置）")
		end
		return false
	end, 8000, 400)
	
	if not forwardOptionClicked then
		print("点击转发选项失败")
		monitor.record("转发小程序失败（转发选项）：", os.time() - op_start)
		return false
	end
	
	sleep(1000)

	-- 步骤6: 选择转发联系人
	if targetContact and targetContact ~= "" then
		local findRes = false
		local n = 0

		-- 手机号正则：1开头，11位数字
		local phonePattern = "1[3-9]%d%d%d%d%d%d%d%d%d%d"
		local searchPhone = targetContact

		-- 判断传入的是否是手机号
		if not string.match(targetContact, "^" .. phonePattern .. "$") then
			-- 不是标准手机号，尝试从中提取手机号
			local extractedPhone = string.match(targetContact, phonePattern)
			if extractedPhone then
				print("从", targetContact, "中提取到手机号:", extractedPhone)
				searchPhone = extractedPhone
			else
				print("无法从", targetContact, "中提取手机号，使用原始值搜索")
			end
		end

		-- 计算中间部分用于模糊匹配
		local strLen = utf8.length(searchPhone)
		local middleParts = {}
		if strLen >= 5 then
			table.insert(middleParts, utf8.mid(searchPhone, 2, 4))
		end
		if strLen >= 6 then
			table.insert(middleParts, utf8.mid(searchPhone, 3, 4))
		end

		print("搜索号码:", searchPhone, "长度:", strLen, "模糊匹配候选:", table.concat(middleParts, ", "))

		while findRes == false and n < 10  do
			n = n + 1
			print("第"..n.."次搜索并选择联系人:", searchPhone)
			sleep(1000)

			-- 先尝试精确匹配（搜索手机号）
			local contactRes = ocr_start(200, 300, 900, 1800, searchPhone)

			if contactRes then
				print("精确匹配找到联系人:", searchPhone, contactRes[1], contactRes[2])
				randomTap(contactRes[1], contactRes[2], 10, 10, "选择联系人")
				findRes = true
				break
			end

			-- 如果原始号码和提取的手机号不同，也尝试用原始号码精确匹配
			if searchPhone ~= targetContact then
				contactRes = ocr_start(200, 300, 900, 1800, targetContact)
				if contactRes then
					print("精确匹配找到联系人(原始):", targetContact, contactRes[1], contactRes[2])
					randomTap(contactRes[1], contactRes[2], 10, 10, "选择联系人")
					findRes = true
					break
				end
			end

			-- 精确匹配失败，尝试中间部分模糊匹配
			for i, middlePart in ipairs(middleParts) do
				print("尝试模糊匹配["..i.."]，中间部分:", middlePart)
				contactRes = ocr_fuzzy_find(200, 300, 900, 1800, middlePart)
				if contactRes then
					print("模糊匹配找到联系人（中间部分）:", middlePart, contactRes[1], contactRes[2])
					randomTap(math.floor(contactRes[1]), math.floor(contactRes[2]), 10, 10, "选择联系人")
					findRes = true
					break
				end
			end

			-- 如果中间部分匹配都失败，尝试用原始昵称匹配
			if not findRes then
				print("尝试完整昵称模糊匹配:", targetContact)
				contactRes = ocr_fuzzy_find(200, 300, 900, 1800, targetContact)
				if contactRes then
					print("完整昵称匹配找到联系人:", targetContact, contactRes[1], contactRes[2])
					randomTap(math.floor(contactRes[1]), math.floor(contactRes[2]), 10, 10, "选择联系人")
					findRes = true
				end
			end

			-- 如果完整昵称也失败，尝试昵称前缀匹配
			if not findRes then
				local nicknamePart = utf8.mid(targetContact, 1, math.min(4, utf8.length(targetContact)))
				print("尝试昵称前缀模糊匹配:", nicknamePart)
				contactRes = ocr_fuzzy_find(200, 300, 900, 1800, nicknamePart)
				if contactRes then
					print("昵称前缀匹配找到联系人:", nicknamePart, contactRes[1], contactRes[2])
					randomTap(math.floor(contactRes[1]), math.floor(contactRes[2]), 10, 10, "选择联系人")
					findRes = true
				end
			end

			if findRes then
				break
			end
		end


		if not findRes then
			print("未找到指定联系人:", targetContact, "，请手动选择")
			sleep(2000)
		end
	else
		-- 如果没有指定联系人，等待用户手动选择
		print("未指定联系人，请手动选择转发对象")
		sleep(2000)
	end
	
	-- 步骤7: 确认转发（点击发送按钮）
	print("确认转发")
	clickWxSendButton()
	sleep(500)
	--点击返回聊天列表
	print("点击返回聊天列表")
	local returnList = randomTap(867,255,5,5, "点击返回聊天列表")
	
	if returnList then
		local duration = os.time() - op_start
		monitor.record("转发小程序成功（下划方式）：", duration)
		print("转发小程序成功")
		-- 回到聊天页
		sleep(1000)
	
		-- 提取手机号用于模糊匹配
		local targetPhone = string.match(targetContact, "%d+")
		-- 使用手机号中间6位（第3-8位）进行模糊匹配
		local phoneMiddle = targetPhone and #targetPhone >= 8 and string.sub(targetPhone, 3, 8) or nil
		
		local n = 0
		local maxRetry = 10
		local found = false
		while n < maxRetry do
			n = n + 1
			sleep(1000)
			
			-- 先尝试精确匹配
			local contactPos = ocr_start(206, 327, 858, 1763, targetContact)
			print("第"..n.."次识别"..targetContact.."--进入详情")
			
			if contactPos then
				randomTap(contactPos[1], contactPos[2], 100, 20, "点击"..targetContact.."位置")
				found = true
				break
			end
			
			-- 精确匹配失败，尝试手机号中间6位模糊匹配
			if phoneMiddle then
				contactPos = ocr_start(206, 327, 858, 1763, phoneMiddle)
				if contactPos then
					print("第"..n.."次模糊匹配（手机号中间6位）："..phoneMiddle)
					randomTap(contactPos[1], contactPos[2], 100, 20, "点击"..phoneMiddle.."位置")
					found = true
					break
				end
			end
		end
		
		if not found then
			print("未找到联系人："..targetContact.."，点击固定区域位置")
			-- 点击固定区域 (107,327,740,456) 的中间位置
			randomTap(423, 391, 50, 50, "点击固定区域位置")
		end
		return true
	else
		local duration = os.time() - op_start
		monitor.record("转发小程序失败（发送确认）：", os.time() - op_start)
		print("转发小程序失败：未找到发送按钮")
		return false
	end
end

-- ==================== 主动发起会话 ====================
-- @param robot_code 机器人编号，默认 HF-AT-1-001
-- @param channel_num 渠道编号，默认 1
function C.w_chat(robot_code, channel_num)
    robot_code = robot_code or 'HF-AT-1-001'
    channel_num = channel_num or 1
    
    -- 从config动态读取接口地址
    local next_url = config.reminder_next_url
    local send_url = config.reminder_send_url
    
    print("主动发起会话开始...")
    print("robot_code:", robot_code, "channel_num:", channel_num)
    
    -- ========== 1. 调用 next 接口获取待发送用户 ==========
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    
    local url = string.format("%s?robot_code=%s&channel_num=%d", next_url, robot_code, channel_num)
    print("请求next接口:", url)
    
    local response_body = {}
    local res, code = http.request{
        url = url,
        sink = ltn12.sink.table(response_body),
        method = "GET",
    }
    
    if not res or code ~= 200 then
        print("获取待发送用户失败，HTTP错误码: " .. tostring(code))
        return false
    end
    
    local response_text = table.concat(response_body)
    local api_data = jsonLib.decode(response_text)
    
    if not api_data or not api_data.success then
        print("next接口返回失败或无数据")
        return false
    end
    
    if not api_data.data or not api_data.data.uid then
        print("无待发送的用户")
        return false
    end
    
    local user_data = api_data.data
    print("获取到用户:", user_data.nickname or "", "UID:", user_data.uid)
    
    -- 获取手机号
    local phone = tostring(user_data.phone or "")
    if phone == "" then
        print("用户手机号为空")
        return false
    end
    print("用户手机号:", phone)
    
    -- ========== 2. 切到ID复制手机号 ==========
    if not C.getIDPhone(config.id_ai_project_config.receive_name) then 
        print("获取ID手机号失败")
        return false 
    end
    
    -- ========== 3. 切回微信搜索联系人 ==========
    if not C.openWeChatOptimize() then 
        print("openWeChatOptimize失败")
        C.changeToWXWithCheck()
    end
    sleep(500)
    
    -- 打开搜索框
    local idx, x, y = findImage(699,203,906,339,"wx_search_btn.png",0.9)
    if idx ~= -1 then
        randomTap(x, y, 10, 10, "图片识别点击搜索")
    else
        randomTap(791,253, 10, 10, "固定位置点击搜索")
    end
    sleep(2000)
    
    -- 粘贴手机号搜索
    local pasteSuccess = false
    for pasteTry = 1, 3 do
        print("粘贴手机号第" .. pasteTry .. "次")
        local pasteIdx, pasteX, pasteY = findImage(93,1220,512,1851, "mate30_search_friend_paste.png", 0.9)
        if pasteIdx ~= -1 then
            pasteX = pasteX + 120 + math.random(5, 120)
            pasteY = pasteY + 20
            randomTap(pasteX, pasteY, 120, 0, "点击输入法粘贴")
        else
            local search_pos = ocr_start(108, 265, 906, 461, "搜索")
            if search_pos then
                longTap(search_pos[1]+5, search_pos[2])
            else
                longTap(360,274)
            end
        end
        sleep(1500)
        
        local verifyOcr = ocr_start(100, 300, 600, 450, "")
        if verifyOcr and #tostring(verifyOcr) > 3 then
            print("粘贴成功")
            pasteSuccess = true
            break
        end
        sleep(500)
    end
    
    if not pasteSuccess then
        print("粘贴手机号失败")
        C.weChatBack()
        return false
    end
    sleep(500)
    
    -- 点击搜索结果
    local contactFound = false
    for contactTry = 1, 3 do
        print("查找联系人第" .. contactTry .. "次")
        sleep(1000)
        local contact = ocr_start(217,397,922,611, phone)
        if contact then
            print("找到联系人，坐标:", contact[1], contact[2])
            randomTap(contact[1], contact[2], 10, 10)
            sleep(1000)
            local chatVerify = findImage(114,1770,271,1924,"chat_box_left_btn.png",0.9)
            if chatVerify ~= -1 then
                print("已进入聊天页面")
                contactFound = true
                break
            end
        end
        sleep(800)
    end
    
    if not contactFound then
        print("未找到联系人:", phone)
        C.weChatBack()
        return false
    end
    sleep(500)
    
    -- ========== 4. 粘贴发送消息 ==========
    local msg_to_send = user_data.message or user_data.msg or ""
    if msg_to_send == "" then
        print("消息内容为空")
        C.weChatBack()
        return false
    end
    
    C.closeInputMethodIfNeeded()
    C.pasteToInputBox(msg_to_send)
    sleep(300)
    C.clickSendButton()
    sleep(500)
    
    -- ========== 5. 调用 send 接口更新状态 ==========
    print("通知服务器发送成功...")
    local post_data = jsonLib.encode({
        robot_code = robot_code,
        channel_num = channel_num,
        uid = user_data.uid
    })
    
    local response_body2 = {}
    local res2, code2 = http.request{
        url = send_url,
        sink = ltn12.sink.table(response_body2),
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Content-Length"] = #post_data
        },
        source = ltn12.source.string(post_data),
    }
    
    if res2 and code2 == 200 then
        print("服务器更新成功")
    else
        print("服务器更新失败，错误码:", code2)
    end
    
    -- 回退列表
    print("主动发起会话完成")
    C.weChatBack()
    return true
end

-- 主动发起聊天会话
-- 根据时间点坐标计算昵称所在区域
-- timePointY: 时间点的Y坐标
-- 返回: {x1, y1, x2, y2} 昵称区域坐标
function C.calcNicknameRegion(timePointY)
    -- 昵称区域计算规则
    -- 根据时间点Y坐标，计算出该聊天条目对应的昵称区域
    local x1 = 247        -- 昵称列左侧边界
    local y1 = timePointY - 35  -- 时间点上方约35像素
    local x2 = 849        -- 昵称列右侧边界
    local y2 = timePointY + 35  -- 时间点下方约35像素
    
    return {x1 = x1, y1 = y1, x2 = x2, y2 = y2}
end

-- 识别昵称区域内的昵称信息
function C.recognizeNickname(nicknameRegion)
    -- 在昵称区域内OCR识别
    local ocr_result = ocr_start_with_boxes(nicknameRegion.x1, nicknameRegion.y1, 
                                              nicknameRegion.x2, nicknameRegion.y2)
    if not ocr_result or #ocr_result == 0 then
        return nil
    end
    
    -- 合并识别结果为昵称文本
    local nickname = ""
    for i, item in ipairs(ocr_result) do
        nickname = nickname .. (item.words or "")
    end
    
    return {
        nickname = nickname,
        ocr_result = ocr_result,
        region = nicknameRegion
    }
end

-- 主动发起聊天
function C.initChat(robot_code, channel_num)
    robot_code = robot_code or 'HF-AT-1-001'
    channel_num = channel_num or 1

    --检测当前是否在微信聊天列表不在则切换到微信
    local maxRetry = 3
	local retryCount = 0
	while retryCount < maxRetry do
		sleep(500)
		local inWxList = ocr_start(374, 224, 678, 292, "微信")
		if inWxList then
			print("已在微信列表界面")
			return true
		else
			retryCount = retryCount + 1
			print("不在微信列表，点击左上角返回，第"..retryCount.."次")
			-- 点击左上角返回按钮
			local backIndex, backX, backY = findPicEx(99, 211, 187, 292, "wx_back.png", 0.9)
			if backIndex ~= -1 then
				randomTap(backX + 12, backY + 20, 3, 5, "点击返回按钮")
			else
				randomTap(125, 252, 3, 5, "点击固定位置返回")
			end
			sleep(500)
		end
	end
	print("已尝试"..maxRetry.."次返回，当前可能不在微信聊天详情页")

    -- 识别微信列表中的时间点
    local timePoints = C.getWechatListTimePoints()
    
    if timePoints and #timePoints > 0 then
        print("识别到时间点数量:", #timePoints)
        
        -- 存储结果：时间点 + 对应昵称
        local chatList = {}
        
		--
        for i, point in ipairs(timePoints) do
            local timeY = math.floor(point.y)
            print(string.format("时间点%d: 坐标(%d,%d), 内容:%s", i, math.floor(point.x), timeY, point.text or ""))
            
            -- 根据时间点Y坐标计算昵称区域
            local nicknameRegion = C.calcNicknameRegion(timeY)
            print(string.format("  -> 昵称区域: (%d,%d,%d,%d)", 
                nicknameRegion.x1, nicknameRegion.y1, nicknameRegion.x2, nicknameRegion.y2))
            
            -- 识别昵称
            local nicknameInfo = C.recognizeNickname(nicknameRegion)
            if nicknameInfo and nicknameInfo.nickname and nicknameInfo.nickname ~= "" then
                print("  -> 识别到昵称:", nicknameInfo.nickname)
				-- 判断昵称是否在黑名单中
				if C.isInBlacklist(nicknameInfo.nickname) then
					print("  -> 昵称在黑名单中，跳过")
					--goto continue
				end
                table.insert(chatList, {
                    timePoint = point,
                    nickname = nicknameInfo.nickname,
                    region = nicknameRegion
                })
            end
            
            -- 点击测试
			--randomTap(math.floor(point.x), timeY, 5, 0, "测试")
			--sleep(1000)
			--randomTap(126, 248, 1, 1, "回到列表")
        end
        
        print("共识别到", #chatList, "个聊天条目")
        return chatList
    else
        print("未识别到微信列表时间点")
        return nil
    end
end

--判断昵称是否在黑名单
function C.isInBlacklist(nickname)
	local blacklist = config.wx_ignore_list
	for _, name in ipairs(blacklist) do
		if nickname == name then
			return true
		end
	end
	
	return false
end

-- 获取微信列表时间点
function C.getWechatListTimePoints()
    -- 使用ocr_start_with_boxes获取带坐标的OCR结果
    local ocr_result = ocr_start_with_boxes(758, 303, 965, 1798)
    if not ocr_result or #ocr_result == 0 then
        print("OCR未识别到任何内容")
        return nil
    end
    
    print("OCR识别到", #ocr_result, "个文字块")
    
    local timePoints = {}
    local time_patterns = {
        "^%d%d:%d%d$",           -- 20:38 格式
        "^昨天$",                -- 昨天
        "^%d+月%d+日$",          -- 4月23日 格式
        "^%d+年%d+月%d+日$",     -- 2024年4月23日 格式
    }
    
    for i, item in ipairs(ocr_result) do
        local text = item.words or ""
        local x, y = item.x or 0, item.y or 0
        
        print("文字块["..i.."]:", text, "坐标:", x, y)
        
        for _, pattern in ipairs(time_patterns) do
            if string.match(text, pattern) then
                table.insert(timePoints, {
                    x = x,
                    y = y,
                    text = text,
                    index = i
                })
                print("  -> 匹配成功!")
                break
            end
        end
    end
    
    -- 按Y坐标排序
    table.sort(timePoints, function(a, b)
        return a.y > b.y
    end)
    
    return timePoints
end

--主动触发消息
function C.initChat_send(robot_code, channel_num)
	robot_code = robot_code or 'HF-AT-1-004'
    channel_num = channel_num or 1
	
	--构建带参数的URL
	local url = config.get_sender_list_url .. "?robot_code=" .. robot_code .. "&channel_num=" .. channel_num
	print("接口请求:", url)
	
	--使用 getHttp 请求
	local res = getHttp(url)
	if not res then
		print("获取发送列表失败")
		return nil
	end
	
	local data = jsonLib.decode(res)
	if not data or not data.success then
		print("接口返回失败")
		return nil
	end
	
	-- 获取steps数据
	local steps = data.steps
	if not steps or #steps == 0 then
		print("接口返回无待处理数据")
		return nil
	end
	
	print("接口返回有", #steps, "个步骤组待处理")
	
	-- 收集所有uid用于最后更新
	local all_uids = {}
	for _, step_data in ipairs(steps) do
		for _, user in ipairs(step_data.users) do
			table.insert(all_uids, user.uid)
		end
	end
	
	-- 构建用户字典方便查找
	local function buildUserDict(users)
		local dict = {}
		for _, user in ipairs(users) do
			dict[user.uid] = {
				uid = user.uid,
				phone = user.phone,
				msg = user.msg or "",
				user = user
			}
		end
		return dict
	end
	
	-- 已处理记录
	local processed_uids = {}
	
	-- 确保在微信列表页面
	C.changeToWXWithCheck()
	sleep(2000)
	
	-- 按步骤处理
	for step_idx, step_data in ipairs(steps) do
		print("========== 开始处理步骤", step_idx, ", step:", step_data.step, "==========")
		
		-- 先请求发送消息到ID接口（GET请求）
		local send_url = config.send_by_step_url .. "?robot_code=" .. robot_code .. "&channel_num=" .. channel_num .. "&step=" .. step_data.step
		print("[步骤", step_idx, "] 请求发送消息到ID:", send_url)
		local send_res = getHttp(send_url)
		if send_res then
			print("[步骤", step_idx, "] 发送消息到ID接口返回:", send_res)
		else
			print("[步骤", step_idx, "] 发送消息到ID接口失败")
		end
		
		sleep(1000)
		
		-- 构建用户列表和字典
		local user_list = step_data.users or {}
		local user_dict = {}
		print("[步骤", step_idx, "] 获取到用户数量:", #user_list)
		for _, user in ipairs(user_list) do
			print("[步骤", step_idx, "] 用户信息 - uid:", user.uid, "phone:", user.phone, "msg:", user.msg or "")
			user_dict[user.uid] = {
				uid = user.uid,
				phone = user.phone,
				msg = user.msg or "",
				user = user
			}
		end
		
		-- 如果没有用户，跳过此步骤
		if #user_list == 0 then
			print("[步骤", step_idx, "] 无用户，跳过此步骤")
		end
		
		-- 未匹配的用户列表
		local unmatched_users = {}
		for _, user in ipairs(user_list) do
			table.insert(unmatched_users, user)
		end
		print("[步骤", step_idx, "] 未匹配用户数:", #unmatched_users)
		
		-- 第一个用户是否已处理（用于判断是否需要切ID复制消息）
		local first_user_done = false
		local processed_count = 0  -- 已处理用户计数
		
		-- 处理当前步骤：滑动遍历列表，匹配所有未匹配的用户
		local max_swipe = 10  -- 最多滑动10次
		local swipe_count = 0
		
		while #unmatched_users > 0 and swipe_count < max_swipe do
			swipe_count = swipe_count + 1
			print("[步骤", step_idx, "] 滑动", swipe_count, "/", max_swipe, "- 剩余未匹配:", #unmatched_users)
			
			-- OCR识别当前列表
			local ocr_result = ocr_start_with_boxes(248, 305, 824, 1818)
			if not ocr_result or #ocr_result == 0 then
				print("[步骤", step_idx, "] 滑动", swipe_count, "- OCR未识别到内容")
			else
				print("[步骤", step_idx, "] 滑动", swipe_count, "- OCR识别到", #ocr_result, "个条目")
			end
			
			-- 在当前列表中匹配所有未匹配的用户
			local matched_this_scan = {}
			if ocr_result then
				for _, ocr_item in ipairs(ocr_result) do
					local ocr_text = ocr_item.words or ""
					local ocr_x = math.floor(ocr_item.x or 0)
					local ocr_y = math.floor(ocr_item.y or 0)
					
					-- 遍历未匹配的用户
					for idx, user in ipairs(unmatched_users) do
						local match_text = user_dict[user.uid].msg
						if string.find(ocr_text, match_text, 1, true) then
							print("[步骤", step_idx, "] 滑动", swipe_count, "- 匹配成功! uid:", user.uid, "msg:", match_text, "坐标:", ocr_x, ocr_y)
							table.insert(matched_this_scan, {
								user = user,
								x = ocr_x,
								y = ocr_y
							})
						end
					end
				end
			end
			
			print("[步骤", step_idx, "] 滑动", swipe_count, "- 本次扫描匹配到", #matched_this_scan, "个用户")
			
			-- 处理本次扫描匹配到的用户
			for _, match in ipairs(matched_this_scan) do
				local user = match.user
				local ocr_x, ocr_y = match.x, match.y
				processed_count = processed_count + 1
				
				-- 从未匹配列表中移除
				for i = #unmatched_users, 1, -1 do
					if unmatched_users[i].uid == user.uid then
						table.remove(unmatched_users, i)
						break
					end
				end
				
				print("[步骤", step_idx, "] 处理用户", processed_count, "/", #user_list, "- uid:", user.uid, "msg:", user_dict[user.uid].msg, "- 点击进入聊天")
				-- 点击打开聊天
				randomTap(ocr_x, ocr_y, 5, 5, "点击打开聊天")
				sleep(1500)
				
				-- 判断是否为第一个用户
				if not first_user_done then
					-- 第一个用户：完整流程（切ID复制消息）
					first_user_done = true
					print("[步骤", step_idx, "] 用户", user.uid, "msg:", user_dict[user.uid].msg, "- 第一个用户，执行切ID复制消息流程")
					
					-- 切到桌面打开ID
					print("[步骤", step_idx, "] 用户", user.uid, "- 切到桌面打开ID")
					C.backToHomeWithCheck()
					sleep(500)
					C.openIDOptimize()
					sleep(1000)
					
					-- 搜索联系人
					print("[步骤", step_idx, "] 用户", user.uid, "- 搜索联系人")
					C.searchIDOptimize(config.id_ai_project_config.name, false)
					sleep(1500)
					
					-- 获取ID消息列表
					local msgs = C.getIDMessages()
					if msgs and #msgs > 0 then
						print("[步骤", step_idx, "] 用户", user.uid, "- 获取到", #msgs, "条ID消息")
						-- 获取最后一条消息
						local lastMsg = msgs[#msgs]
						local msg_x = lastMsg.x + 200
						local msg_y = lastMsg.y + 60
						
						-- 长按最后一条消息复制
						print("[步骤", step_idx, "] 用户", user.uid, "- 长按复制消息")
						longTap(msg_x, msg_y)
						sleep(1000)
						
						-- 查找并点击复制按钮
						local copySuccess = false
						for retry = 1, 3 do
							local idx, copy_x, copy_y = findImage(0, 0, 0, 0, "id_msg_copy2.png|id_msg_copy1.png|id_msg_copy.png|id_msg_copy3.png|id_msg_copy4.png", 0.8)
							if idx ~= -1 then
								print("[步骤", step_idx, "] 用户", user.uid, "- 点击复制按钮")
								randomTap(copy_x, copy_y, 10, 10, "点击复制")
								sleep(1000)
								copySuccess = true
								break
							end
							sleep(300)
						end
						
						if copySuccess then
							print("[步骤", step_idx, "] 用户", user.uid, "- 复制成功，切回微信发送")
							-- 返回ID消息列表
							C.backToIDMessageList()
							sleep(500)
							
							-- 切换到微信
							C.openWeChatOptimize()
							sleep(1500)
							
							-- 粘贴并发送
							C.doPaste()
							C.backToWeChatMessageList()
							
							-- 标记已处理
							table.insert(processed_uids, user.uid)
							print("[步骤", step_idx, "] 用户", user.uid, "- 发送成功")
						else
							print("[步骤", step_idx, "] 用户", user.uid, "- 复制失败，跳过")
						end
					else
						print("[步骤", step_idx, "] 用户", user.uid, "- 未获取到ID消息")
					end
				else
					-- 后续用户：直接粘贴发送（消息已复制）
					print("[步骤", step_idx, "] 用户", user.uid, "msg:", user_dict[user.uid].msg, "- 后续用户，直接粘贴发送")
					C.doPaste()
					C.backToWeChatMessageList()
					
					-- 标记已处理
					table.insert(processed_uids, user.uid)
					print("[步骤", step_idx, "] 用户", user.uid, "- 发送成功")
				end
				
				-- 处理完一个用户后，确保回到微信列表
				print("[步骤", step_idx, "] 用户", user.uid, "- 回到微信列表")
				C.changeToWXWithCheck()
				sleep(500)
			end
			
			-- 如果还有未匹配的用户，滑动继续查找
			if #unmatched_users > 0 then
				print("[步骤", step_idx, "] 剩余", #unmatched_users, "个用户未匹配，继续滑动")
				randomSwipe(500, 1700, 500, 500, 500)
				sleep(1500)
			end
		end
		
		-- 记录未找到的用户
		print("[步骤", step_idx, "] 未找到的用户数量:", #unmatched_users)
		for _, user in ipairs(unmatched_users) do
			print("[步骤", step_idx, "] 未找到用户 - uid:", user.uid)
			table.insert(processed_uids, user.uid)
		end
		
		-- 步骤组处理完后回到微信列表顶部
		-- 用OCR检测"最近"确认到达顶部
		print("[步骤", step_idx, "] 开始滑动到微信列表顶部")
		for i = 1, 10 do
			randomSwipe(500, 500, 500,1700 , 500)
			sleep(1000)
			
			-- 检测是否到达顶部（识别"最近"）
			local recent_pos = ocr_start(267, 208, 779, 329, "最近")
			if recent_pos then
				print("[步骤", step_idx, "] 检测到'最近'，已到达微信列表顶部")
				-- 下滑一次
				randomSwipe(500, 600, 500, 1500, 500)
				sleep(1000)
				-- 确认在微信列表
				local inWxList = ocr_start(374, 224, 678, 292, "微信")
				if inWxList then
					print("[步骤", step_idx, "] 确认在微信列表，顶部检测通过")
					break
				end
			end
			sleep(500)
		end
		print("========== 步骤", step_idx, "处理完成 ==========")
	end
	
	-- 更新所有uid（不管是否全部处理完）
	print("更新所有uid，数量:", #all_uids)
	if #all_uids > 0 then
		local uid_str = table.concat(all_uids, ",")
		print("调用更新接口，uid列表:", uid_str)
		
		local update_url = config.update_reminder_url
		local update_data = '{"uid": "' .. uid_str .. '"}'
		local update_res = httpPost(update_url, update_data, 30000)
		if update_res then
			print("更新接口返回:", update_res)
		else
			print("更新接口调用失败")
		end
	end
	
	return {
		success = true,
		processed_count = #processed_uids,
		processed_uids = processed_uids,
		total_uids = #all_uids
	}
end


--通过文件传输助手 主动发消息群发
--type 1 主动发消息 2 群发 3 老数据回访
function C.initChat_send_by_file_helper(robot_code, channel_num, type, tool_name)
	tool_name = tool_name or "文件传输助手"
	type = type or 1
	
	-- 根据type区分不同行为
	if type == 1 then
		robot_code = robot_code or 'HF-AT-1-004'
		channel_num = channel_num or 1
		
		--构建带参数的URL获取发送列表
		local url = config.get_sender_list_url .. "?robot_code=" .. robot_code .. "&channel_num=" .. channel_num
		print("接口请求:", url)
		
		--使用 getHttp 请求
		local res = getHttp(url)
		if not res then
			print("获取发送列表失败")
			return nil
		end
		
		local data = jsonLib.decode(res)
		if not data or not data.success then
			print("接口返回失败")
			return nil
		end
		
		-- 获取steps数据
		local steps = data.steps
		if not steps or #steps == 0 then
			print("接口返回无待处理数据")
			return nil
		end
		
		print("接口返回有", #steps, "个步骤组待处理")
		
		-- 收集所有uid用于最后更新
		local all_uids = {}
		for _, step_data in ipairs(steps) do
			for _, user in ipairs(step_data.users) do
				table.insert(all_uids, user.uid)
			end
		end
		
		-- 构建用户字典方便查找
		local function buildUserDict(users)
			local dict = {}
			for _, user in ipairs(users) do
				dict[user.uid] = {
					uid = user.uid,
					phone = user.phone,
					msg = user.msg or "",
					user = user
				}
			end
			return dict
		end
		
		-- 确保在微信列表页面
		C.changeToWXWithCheck()
		sleep(2000)
		
		-- 按步骤处理
		for step_idx, step_data in ipairs(steps) do
			print("========== 开始处理步骤", step_idx, ", step:", step_data.step, "==========")
			
			-- 构建当前步骤的用户列表和字典
			local user_list = step_data.users or {}
			local user_dict = buildUserDict(user_list)
			print("[步骤", step_idx, "] 获取到用户数量:", #user_list)
			
			-- 如果没有用户，跳过此步骤
			if #user_list == 0 then
				print("[步骤", step_idx, "] 无用户，跳过此步骤")
			else
				-- 未匹配的用户列表
				local unmatched_users = {}
				for _, user in ipairs(user_list) do
					table.insert(unmatched_users, user)
				end
				
				-- 先请求发送消息到ID接口（GET请求）
				local send_url = config.send_by_step_url .. "?robot_code=" .. robot_code .. "&channel_num=" .. channel_num .. "&step=" .. step_data.step
				print("[步骤", step_idx, "] 请求发送消息到ID:", send_url)
				local send_res = getHttp(send_url)
				if send_res then
					print("[步骤", step_idx, "] 发送消息到ID接口返回:", send_res)
				else
					print("[步骤", step_idx, "] 发送消息到ID接口失败")
				end
				sleep(1000)
				
				-- 打开文件传输助手
				print("[步骤", step_idx, "] 打开文件传输助手")
				local file_helper_pos = ocr_start(115, 216, 804, 1270, tool_name)
				if file_helper_pos then
					print("检测到文件传输助手", file_helper_pos)
					randomTap(file_helper_pos[1], file_helper_pos[2], 10, 10, "点击文件传输助手")
					sleep(1500)
				end
				
				-- 打开ID应用复制消息
				print("[步骤", step_idx, "] 打开ID应用复制消息")
				C.backToHomeWithCheck()
				sleep(500)
				C.openIDOptimize()
				sleep(1000)
				C.searchIDOptimize(config.id_ai_project_config.name, false)
				sleep(1500)
				
				-- 获取ID消息列表
				local msgs = C.getIDMessages()
				if msgs and #msgs > 0 then
					local lastMsg = msgs[#msgs]
					local msg_x = lastMsg.x + 200
					local msg_y = lastMsg.y + 60
					
					-- 长按最后一条消息复制
					print("[步骤", step_idx, "] 长按复制消息")
					longTap(msg_x, msg_y)
					sleep(1000)
					
					-- 查找并点击复制按钮
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
					
					if copySuccess then
						-- 返回ID消息列表
						C.backToIDMessageList()
						sleep(500)
						
						-- 直接切换到微信打开文件传输助手
						C.backToHomeWithCheck()
						sleep(500)
						C.openWeChatSimple()
						sleep(1500)
						
						-- 打开文件传输助手
						file_helper_pos = ocr_start(115, 216, 804, 1270, tool_name)
						if file_helper_pos then
							randomTap(file_helper_pos[1], file_helper_pos[2], 10, 10, "点击文件传输助手")
							sleep(1500)
						end
						
						-- 粘贴消息
						C.doPaste()
						sleep(1000)
						
						-- 点击发送
						local send_pos = ocr_start(115, 216, 804, 1270, "发送")
						if send_pos then
							print("[步骤", step_idx, "] 点击发送按钮")
							randomTap(send_pos[1], send_pos[2], 10, 10, "点击发送按钮")
							sleep(1500)
						end
						
						-- 调用转发函数，传入用户列表进行勾选
						print("[步骤", step_idx, "] 开始转发给联系人")
						C.forwardLastMessageFromFileHelper(user_list)
					end
				end
				
				-- 更新当前步骤状态
				print("[步骤", step_idx, "] 更新步骤状态")
				local update_url = config.update_reminder_url
				local uid_str = ""
				for _, user in ipairs(user_list) do
					if uid_str ~= "" then uid_str = uid_str .. "," end
					uid_str = uid_str .. user.uid
				end
				local update_data = '{"uid": "' .. uid_str .. '"}'
				-- 使用正确的Content-Type发送POST请求
				local response_body = {}
				local http = require("socket.http")
				local ltn12 = require("ltn12")
				local res, code = http.request{
					url = update_url,
					method = "POST",
					headers = {
						["Content-Type"] = "application/json",
						["Content-Length"] = #update_data
					},
					source = ltn12.source.string(update_data),
					sink = ltn12.sink.table(response_body)
				}
				local update_res = table.concat(response_body)
				if update_res and update_res ~= "" then
					print("[步骤", step_idx, "] 更新接口返回:", update_res)
				else
					print("[步骤", step_idx, "] 更新接口调用失败, HTTP状态码:", code)
				end
				
				-- 回到微信列表顶部
				print("[步骤", step_idx, "] 回到微信列表顶部")
				C.backToHomeWithCheck()
				sleep(500)
				C.openWeChatSimple()
				sleep(1500)
				
				-- 打开群发助手进行下一step
				print("[步骤", step_idx, "] 打开群发助手")
				file_helper_pos = ocr_start(115, 216, 804, 1270, tool_name)
				if file_helper_pos then
					randomTap(file_helper_pos[1], file_helper_pos[2], 10, 10, "点击群发助手")
					sleep(1500)
				end
			end
			
			-- 流程完成后检查是否在微信列表界面
			print("[步骤", step_idx, "] 检查是否在微信列表界面")
			local inWXList = false
			for checkRetry = 1, 3 do
				local list_pos = ocr_start(115, 216, 804, 1270, tool_name)
				if list_pos then
					print("[步骤", step_idx, "] 已在微信列表界面")
					inWXList = true
					break
				end
				sleep(300)
			end
			
			-- 如果不在微信列表界面，回退到列表
			if not inWXList then
				print("[步骤", step_idx, "] 不在微信列表界面，执行回退")
				for backRetry = 1, 3 do
					goBack()
					sleep(1000)
					local list_pos = ocr_start(115, 216, 804, 1270, tool_name)
					if list_pos then
						print("[步骤", step_idx, "] 回退成功，已在微信列表界面")
						break
					end
				end
			end
			
			print("========== 步骤", step_idx, "处理完成 ==========")
		end
		
		return {
			success = true,
			total_steps = #steps
		}
	end
end
-- ==================== 文件传输助手转发函数 ====================
-- 转发文件传输助手中的最后一条消息
-- 流程：关闭输入法 -> 长按消息 -> 转发 -> 从通讯录选择 -> 下拉勾选联系人 -> 发送
function C.forwardLastMessageFromFileHelper(contactList)
	contactList = contactList or {}
	print("开始转发文件传输助手最后一条消息，联系人数量:", #contactList)
	
	-- 步骤0: 检查输入法是否被关闭，没有关闭则关闭
	print("步骤0: 检查并关闭输入法")
	C.closeInputMethodIfNeeded()
	sleep(500)
	
	-- 步骤1: 长按最后一条消息（固定位置）
	print("步骤1: 长按最后一条消息")
	longTap(500, 1600)
	sleep(1500)
	
	-- 步骤2: 查找并点击"转发给朋友"选项
	print("步骤2: 查找转发选项")
	local forwardClicked = false
	for retry = 1, 5 do
		local forwardRes = ocr_start(141,264,889,1764, "转发")
		if forwardRes then
			print("找到转发选项:", forwardRes[1], forwardRes[2])
			randomTap(forwardRes[1], forwardRes[2], 10, 10, "点击转发")
			sleep(1000)
			forwardClicked = true
			break
		end
		sleep(500)
	end
	

	--步骤2.5 多选
	for retry = 1, 5 do
		sleep(800)
		local selectsRes = ocr_start(689,188,990,387,"多选")
		print("多选位置",selectsRes)
		if selectsRes then
			print("找到多选选项:", selectsRes[1], selectsRes[2])
			randomTap(selectsRes[1], selectsRes[2], 5, 3, "点击多选")
			sleep(500)
			break
		end
	end
	-- 步骤3: 从通讯录选择
	sleep(800)
	print("步骤3: 从通讯录选择")
	local contactRes = ocr_start(636,778,961,933, "从通讯录选择")
	if contactRes then
		print("点击从通讯录选择")
		randomTap(contactRes[1], contactRes[2], 10, 10, "点击从通讯录选择")
		sleep(1500)
	else
		-- 备用：点击通讯录入口
		randomTap(812,886, 3, 3, "备用通讯录入口")
		sleep(1500)
	end
	
	-- 步骤4: 下拉查找联系人并勾选（相似度80%）
	print("步骤4: 下拉查找并勾选联系人")
	local matched_contacts = {}
	local matched_uids = {}
	local similarity = 0.9  -- 相似度90%
	
	-- 构建待匹配的联系人和消息字典
	local function buildMatchDict(users)
		local dict = {}
		for _, user in ipairs(users) do
			local match_key = user.msg or user.phone or user.uid
			if match_key and match_key ~= "" then
				dict[match_key] = user.uid
			end
		end
		return dict
	end
	
	local match_dict = buildMatchDict(contactList)
	local max_swipe = 15  -- 最多下拉15次
	
	for swipe_idx = 1, max_swipe do
		-- 打印待匹配的联系人信息
		local unmatched_msgs = {}
		for _, user in ipairs(contactList) do
			local is_matched = false
			for _, matched_uid in ipairs(matched_uids) do
				if matched_uid == user.uid then
					is_matched = true
					break
				end
			end
			if not is_matched then
				table.insert(unmatched_msgs, user.msg or user.phone or user.uid)
			end
		end
		print("[转发] 下拉第", swipe_idx, "/", max_swipe, "次，剩余待匹配:", #contactList - #matched_uids, "待匹配内容:", table.concat(unmatched_msgs, ", "))
		
		-- OCR识别当前页面联系人列表
		sleep(1000)
		local ocr_result = ocr_start_with_boxes(200, 300, 900, 1800)
		
		if ocr_result and #ocr_result > 0 then
			print("[转发] OCR识别到", #ocr_result, "个条目")
			
			-- 遍历OCR结果，匹配联系人
			for _, ocr_item in ipairs(ocr_result) do
				local ocr_text = ocr_item.words or ""
				local ocr_x = math.floor(ocr_item.x or 400)
				local ocr_y = math.floor(ocr_item.y or 400)
				
				-- 遍历待匹配的用户进行模糊匹配（相似度80%）
				for _, user in ipairs(contactList) do
					-- 检查是否已匹配
					local already_matched = false
					for _, matched_uid in ipairs(matched_uids) do
						if matched_uid == user.uid then
							already_matched = true
							break
						end
					end
					
					if not already_matched then
						local match_text = user.msg or user.phone or user.uid or ""
						if match_text ~= "" then
							-- 严格匹配：OCR文本必须包含匹配文本，或匹配文本必须包含OCR文本
							local match_ratio = 0
							if string.find(ocr_text, match_text, 1, true) or string.find(match_text, ocr_text, 1, true) then
								match_ratio = 1.0
							elseif #ocr_text >= 4 and #match_text >= 4 then
								-- 只有当OCR文本和match_text都在4字符以上时才计算字符包含相似度
								local matched_chars = 0
								for i = 1, #ocr_text do
									local char = string.sub(ocr_text, i, i)
									if string.find(match_text, char, 1, true) then
										matched_chars = matched_chars + 1
									end
								end
								match_ratio = matched_chars / #ocr_text
							end
							
							-- 相似度达到80%则匹配
							if match_ratio >= similarity then
								print("[转发] 匹配成功! uid:", user.uid, "匹配文本:", match_text, "OCR文本:", ocr_text, "相似度:", string.format("%.2f", match_ratio))
								table.insert(matched_uids, user.uid)
								table.insert(matched_contacts, {
									x = ocr_x,
									y = ocr_y,
									uid = user.uid
								})
								-- 点击勾选联系人
								randomTap(ocr_x - 100, ocr_y, 10, 10, "勾选联系人:" .. user.uid)
								sleep(500)
								break
							end
						end
					end
				end
			end
		else
			print("[转发] OCR未识别到内容")
		end
		
		-- 检查是否所有联系人都已匹配
		if #matched_uids >= #contactList then
			print("[转发] 所有联系人已匹配完成，共", #matched_contacts, "个")
			break
		end
		
		-- 下拉加载更多
		if swipe_idx < max_swipe then
			print("[转发] 下拉加载更多...")
			randomSwipe(500, 1600, 500, 600, 800)
			sleep(1500)
		end
	end
	
	-- 步骤5: 点击发送按钮
	for retry = 1, 5 do
		sleep(800)
		print("查找完成位置")
		local completeRes = ocr_start(692,203,977,357,"完成")
		local sendRes = ocr_start(440,1540,883,1857,"发送")
		print("查找完成位置",completeRes)
		print("查找发送位置",sendRes)
		if completeRes and sendRes then
			break
		elseif completeRes then
			randomTap(completeRes[1],completeRes[2],3,3,"点击完成")
			sleep(500)
		else
			print("未找到完成按钮，继续等待...")
		end
	end
	
	print("步骤5: 确认并发送")
	sleep(1000)
	
	local confirmRes = ocr_start(440,1540,883,1857, "发送")
	if confirmRes then
		print("点击发送按钮")
		randomTap(confirmRes[1], confirmRes[2], 10, 10, "点击发送")
		sleep(2000)
	else
		-- 备用点击发送
		randomTap(850, 1850, 10, 10, "备用发送按钮")
		sleep(2000)
	end
	
	print("转发流程完成，已勾选", #matched_contacts, "个联系人")
	return {
		success = true,
		matched_count = #matched_contacts,
		matched_uids = matched_uids
	}
end


--群发助手群发
function C.group_send(robotCode,channel_numcontactList)
	--
end

-- ==================== 群发助手 ====================
-- 打开群发助手
-- 返回: true 成功, false 失败
function C.clickMassSendHelper()
    print("步骤: 点击'群发助手'")
    local maxRetry = 3
    for i = 1, maxRetry do
        local helperPos = ocr_start(135, 421, 580, 1290, "群发助手")
        if helperPos then
            randomTap(helperPos[1] + math.random(-10, 10), helperPos[2] + math.random(-5, 5), 20, 5, "点击'群发助手'")
            sleep(1000)
            -- 验证页面是否跳转
            local checkPos = ocr_start(135, 421, 580, 1290, "群发助手")
            if not checkPos then
                print("已成功进入群发助手页面")
                return true
            else
                print("'群发助手'仍存在，重新点击")
            end
        else
            print("未找到'群发助手'，重试")
        end
        sleep(500)
    end
    print("点击'群发助手'失败")
    return false
end

-- 点击"开始群发"
-- 返回: true 成功, false 失败
function C.clickStartMassSend()
    print("步骤: 点击'开始群发'")
    local maxRetry = 3
    for i = 1, maxRetry do
        local startPos = ocr_start(68, 690, 735, 998, "开始群发")
        if startPos then
            randomTap(startPos[1], startPos[2], 20, 10, "点击'开始群发'")
            sleep(1000)
            -- 验证页面是否跳转
            local checkPos = ocr_start(68, 690, 735, 998, "开始群发")
            if not checkPos then
                print("已成功点击'开始群发'")
                return true
            else
                print("'开始群发'仍存在，重新点击")
            end
        else
            print("未找到'开始群发'，重试")
        end
        sleep(500)
    end
    print("点击'开始群发'失败")
    return false
end

-- 点击"新建群发"
-- 返回: true 成功, false 失败
function C.clickNewMassSend()
    print("步骤: 点击'新建群发'")
    local maxRetry = 3
    for i = 1, maxRetry do
        local newPos = ocr_start(261, 1763, 824, 1886, "新建群发")
        if newPos then
            randomTap(newPos[1], newPos[2], 20, 10, "点击'新建群发'")
            sleep(2000)
            -- 验证页面是否跳转
            local checkPos = ocr_start(261, 1763, 824, 1886, "新建群发")
            if not checkPos then
                print("已成功点击新建群发")
                return true
            else
                print("'新建群发'仍存在，重新点击")
            end
        else
            print("未找到'新建群发'，重试")
        end
        sleep(500)
    end
    print("点击'新建群发'失败")
    return false
end

-- 点击"选中"按钮
-- 返回: true 成功, false 失败
function C.clickSelectButton()
    print("步骤: 点击'选中'按钮")
    local maxRetry = 3
    for i = 1, maxRetry do
        local selectPos = ocr_start(680, 1753, 960, 1879, "选中")
        if selectPos then
            randomTap(selectPos[1], selectPos[2], 20, 10, "点击'选中'")
            sleep(1000)
            -- 验证是否跳转
            local checkPos = ocr_start(680, 1753, 960, 1879, "选中")
            if not checkPos then
                print("已成功点击选中按钮")
                return true
            else
                print("'选中'仍存在，重新点击")
            end
        else
            print("未找到'选中'，重试")
        end
        sleep(500)
    end
    print("点击'选中'失败")
    return false
end

-- ========== 模糊匹配相关函数 ==========
-- 常见OCR混淆字符表
local OCR_CONFUSIONS = {
    ["M"] = "N", ["N"] = "M",
    ["O"] = "0", ["0"] = "O",
    ["I"] = "1", ["1"] = "I", ["l"] = "1", ["1"] = "l", ["I"] = "l", ["l"] = "I",
    ["S"] = "5", ["5"] = "S",
    ["B"] = "8", ["8"] = "B",
    ["G"] = "6", ["6"] = "G",
    ["Z"] = "2", ["2"] = "Z",
    ["D"] = "O", ["O"] = "D",
    ["C"] = "G", ["G"] = "C",
    ["T"] = "7", ["7"] = "T",
}

-- 判断两个字符是否为OCR混淆字符
local function isOcrConfusion(char1, char2)
    return OCR_CONFUSIONS[char1] == char2 or OCR_CONFUSIONS[char2] == char1
end

-- 计算两个字符串的相似度（允许OCR误差）
-- 返回: 差异字符数
local function calculateDiff(str1, str2)
    local len1 = #str1
    local len2 = #str2
    local minLen = math.min(len1, len2)
    local diffCount = math.abs(len1 - len2)
    
    for i = 1, minLen do
        local char1 = string.sub(str1, i, i)
        local char2 = string.sub(str2, i, i)
        if char1 ~= char2 and not isOcrConfusion(char1, char2) then
            diffCount = diffCount + 1
        end
    end
    
    return diffCount
end

-- 跳过中间字符匹配：允许跳过1-2个中间字符
local function matchWithSkip(ocrText, contact, skipCount)
    local contactLen = #contact
    local ocrLen = #ocrText
    
    if contactLen < 4 then return false, nil end
    
    for skipPos = 2, contactLen - 2 do
        local prefixLen = skipPos - 1
        local suffixLen = contactLen - skipPos - skipCount + 1
        
        if suffixLen >= 2 then
            local prefix = string.sub(contact, 1, prefixLen)
            local suffix = string.sub(contact, skipPos + skipCount, contactLen)
            
            local prefixStart = string.find(ocrText, prefix)
            if prefixStart then
                local afterPrefix = string.sub(ocrText, prefixStart + prefixLen)
                if string.find(afterPrefix, suffix) then
                    local matchEnd = prefixStart + prefixLen + #afterPrefix - string.find(afterPrefix, suffix) + #suffix
                    return true, string.sub(ocrText, prefixStart, math.min(matchEnd, ocrLen))
                end
            end
        end
    end
    
    return false, nil
end

-- 模糊匹配函数：支持OCR识别误差和双向子串匹配
-- ocrText: OCR识别的完整文本
-- contact: 要匹配的联系人名称（可以是字符串或table）
-- 返回: 是否匹配, 匹配到的文本
function C.fuzzyMatchContact(ocrText, contact)
    if not ocrText or not contact then
        return false, nil
    end
    
    -- 如果contact是table，提取联系人名称
    local contactName = contact
    if type(contact) == "table" then
        contactName = contact.name or contact.nickname or contact.nick_name or contact.title or tostring(contact)
        if contactName == contact then
            -- 如果无法从table中提取有效名称，尝试转换为字符串
            contactName = tostring(contact)
        end
    end
    contactName = tostring(contactName)
    
    -- 如果ocrText是table（ocr_start_with_boxes返回的数组），合并所有words
    local fullOcrText = ocrText
    if type(ocrText) == "table" then
        local texts = {}
        for _, item in ipairs(ocrText) do
            if item.words then
                table.insert(texts, item.words)
            end
        end
        fullOcrText = table.concat(texts)
    end
    
    local contactLen = #contactName
    local ocrLen = #fullOcrText
    
    -- 如果长度太短，无法匹配
    if contactLen < 2 or ocrLen < 2 then
        return false, nil
    end
    
    -- 最小匹配长度
    local minMatchLen = math.max(3, math.ceil(contactLen * 0.6))
    
    -- 1. 精确匹配
    if string.find(fullOcrText, contactName, 1, true) then
        return true, contactName
    end
    
    -- 2. 双向子串匹配
    local maxSubLen = math.min(contactLen, ocrLen)
    for subLen = maxSubLen, minMatchLen, -1 do
        for startIdx = 1, contactLen - subLen + 1 do
            local subContact = string.sub(contactName, startIdx, startIdx + subLen - 1)
            if string.find(fullOcrText, subContact, 1, true) then
                return true, subContact
            end
        end
    end
    
    for subLen = math.min(ocrLen, contactLen), minMatchLen, -1 do
        for startIdx = 1, ocrLen - subLen + 1 do
            local subOcr = string.sub(fullOcrText, startIdx, startIdx + subLen - 1)
            if string.find(contactName, subOcr, 1, true) then
                return true, subOcr
            end
        end
    end
    
    -- 3. 滑动窗口模糊匹配（允许25%差异）
    for i = 1, math.max(1, ocrLen - contactLen + 1) do
        local substr = string.sub(fullOcrText, i, i + contactLen - 1)
        local diffCount = calculateDiff(contactName, substr)
        local maxDiff = math.max(1, math.floor(contactLen * 0.25))
        
        if diffCount <= maxDiff then
            return true, substr
        end
    end
    
    -- 4. 跳过中间字符匹配
    for skip = 1, 2 do
        local matched, matchText = matchWithSkip(fullOcrText, contactName, skip)
        if matched then
            print("跳过中间" .. skip .. "个字符匹配成功")
            return true, matchText
        end
    end
    
    -- 5. 前缀匹配
    local prefixLen = math.min(5, contactLen)
    if prefixLen >= minMatchLen then
        local prefix = string.sub(contactName, 1, prefixLen)
        if string.find(fullOcrText, prefix, 1, true) then
            return true, prefix
        end
        for i = 1, math.max(1, ocrLen - prefixLen + 1) do
            local substr = string.sub(fullOcrText, i, i + prefixLen - 1)
            if calculateDiff(prefix, substr) <= 1 then
                return true, substr
            end
        end
    end
    
    -- 6. 后缀匹配
    local suffixLen = math.min(5, contactLen)
    if suffixLen >= minMatchLen then
        local suffix = string.sub(contact, contactLen - suffixLen + 1, contactLen)
        if string.find(ocrText, suffix) then
            return true, suffix
        end
        for i = 1, math.max(1, ocrLen - suffixLen + 1) do
            local substr = string.sub(ocrText, i, i + suffixLen - 1)
            if calculateDiff(suffix, substr) <= 1 then
                return true, substr
            end
        end
    end
    
    return false, nil
end

-- 滑动查找并选中匹配的联系人
-- userdata: 联系人列表(tables数组)
-- 返回: matchedContacts, success
function C.selectContactsFromList(userdata)
    print("步骤: 滑动查找并选中联系人")
    if not userdata or #userdata == 0 then
        print("无联系人需要选中")
        return {}, false
    end
    
    local region = {x1 = 300, y1 = 405, x2 = 902, y2 = 1714}
    local maxSwipeRetry = 50
    local swipeCount = 0
    local lastOcrContent = ""
    local selectedCount = 0
    local consecutiveSimilarCount = 0
    
    -- 创建联系人查找集合
    local pendingContacts = {}
    for i, contact in ipairs(userdata) do
        pendingContacts[contact] = true
    end
    
    local matchedContacts = {}
    local clickedPositions = {}
    
    while swipeCount < maxSwipeRetry do
        if swipeCount > 0 then
            sleep(2000)
        end
        
        local ocrResult = ocr_start(region.x1, region.y1, region.x2, region.y2, "")
        print("OCR识别结果: " .. tostring(ocrResult))
        
        if ocrResult == lastOcrContent then
            print("已滑动到底部，OCR内容未变化")
            break
        end
        
        lastOcrContent = ocrResult or ""
        
        local contactsToRemove = {}
        for contact, _ in pairs(pendingContacts) do
            local matched, matchText = C.fuzzyMatchContact(ocrResult, contact)
            if matched then
                print("找到匹配联系人: " .. contact .. " (匹配文本: " .. tostring(matchText) .. ")")
                
                sleep(1000)
                local contactPos = ocr_start(region.x1, region.y1, region.x2, region.y2, matchText)
                if contactPos and contactPos[1] and contactPos[2] then
                    local posKey = math.floor(contactPos[1] / 50) .. "_" .. math.floor(contactPos[2] / 50)
                    if clickedPositions[posKey] then
                        print("位置(" .. contactPos[1] .. "," .. contactPos[2] .. ")已点击过，跳过: " .. contact)
                    else
                        randomTap(contactPos[1], contactPos[2], 20, 10, "选中联系人: " .. contact)
                        sleep(1000)
                        selectedCount = selectedCount + 1
                        clickedPositions[posKey] = true
                        table.insert(contactsToRemove, contact)
                    end
                end
            end
        end
        
        for _, contact in ipairs(contactsToRemove) do
            pendingContacts[contact] = nil
            table.insert(matchedContacts, contact)
        end
        
        local remaining = 0
        for _ in pairs(pendingContacts) do
            remaining = remaining + 1
        end
        
        if remaining == 0 then
            print("所有联系人均已选中，共选中: " .. selectedCount)
            return matchedContacts, true
        end
        
        -- 向下滑动
        local swipeY1 = 1550 + math.random(-50, 50)
        local swipeY2 = 800 + math.random(-30, 30)
        swipe(500, swipeY1, 500, swipeY2, 700)
        swipeCount = swipeCount + 1
        print("向下滑动查找联系人 第" .. swipeCount .. "次，剩余: " .. remaining .. "个")
    end
    
    local unmatchedList = {}
    for contact, _ in pairs(pendingContacts) do
        table.insert(unmatchedList, contact)
    end
    if #unmatchedList > 0 then
        print("未匹配到的联系人(" .. #unmatchedList .. "个): " .. table.concat(unmatchedList, ", "))
    end
    
    print("联系人选择完成，共选中: " .. selectedCount .. "个")
    return matchedContacts, selectedCount > 0
end



-- 发送定位
-- 参数: addressText - 要搜索的地址文本
function C.sendAddress(addressText)
	local op_start = os.time()
	print("=== 开始发送定位流程 ===")
	print("目标地址:", addressText)

	-- 步骤1: 点击输入框右侧+号图标，并验证页面跳转
	local maxRetry = 5
	local retryCount = 0
	local menuOpened = false

	while retryCount < maxRetry and not menuOpened do
		retryCount = retryCount + 1
		print(string.format("[步骤1] 第%d次尝试点击+号", retryCount))

		-- 先验证是否已经在菜单页面
		sleep(800)
		local menuCheck1 = ocr_start(24, 1006, 964, 1935, "相册")
		local menuCheck2 = ocr_start(24, 1006, 964, 1935, "拍摄")

		if menuCheck1 or menuCheck2 then
			print("[步骤1] 检测到菜单项已打开，无需重复点击")
			menuOpened = true
			break
		end

		-- 查找换行符号判断输入法状态
		local resA = ocr_start(692, 1685, 941, 1897, "换行")
		local resB = ocr_start(74,1656,375,1942, "符号")
		if resA or resB then
			print("找到换行/符号，说明输入框已经打开，点击输入框右侧+号")
			randomTap(889, 1165, 5, 5, "点击加号")
		else
			print("没找到换行，先点击输入框区域")
			randomTap(889, 1821, 5, 5, "点击加号区域")
			sleep(800)
			-- 再次检查输入法是否打开
			resA = ocr_start(692, 1685, 941, 1897, "换行")
			if resA then
				randomTap(889, 1165, 5, 5, "点击加号")
			end
		end

		-- 验证页面是否跳转成功：检测24,1006,964,1935区域内是否有 相册|拍摄
		sleep(1500)
		menuCheck1 = ocr_start(24, 1006, 964, 1935, "相册")
		menuCheck2 = ocr_start(24, 1006, 964, 1935, "拍摄")

		if menuCheck1 or menuCheck2 then
			print("[步骤1成功] 检测到菜单项，页面跳转成功")
			menuOpened = true
		else
			print("[步骤1] 未检测到菜单项，准备重试")
		end
	end

	if not menuOpened then
		print("[步骤1失败] 无法打开+号菜单")
		return false
	end

	-- 步骤2: OCR查找"位置"并点击
	sleep(800)
	local locationPos = nil
	retryCount = 0
	while retryCount < maxRetry and not locationPos do
		retryCount = retryCount + 1
		print(string.format("[步骤2] 第%d次查找位置选项", retryCount))
		locationPos = ocr_start(79, 1363, 948, 1876, "位置")
		if locationPos then
			-- 点击位置，y-20
			randomTap(locationPos[1], locationPos[2] - 20, 10, 10, "点击位置")
			print("[步骤2成功] 已点击位置选项，位置:", locationPos[1], locationPos[2] - 20)
		else
			print("[步骤2] 未找到位置选项，等待后重试")
			sleep(800)
		end
	end

	if not locationPos then
		print("[步骤2失败] 无法找到位置选项")
		return false
	end

	-- 步骤3: OCR查找"发送位置"并点击
	sleep(1500)
	local sendLocationPos = nil
	retryCount = 0
	while retryCount < maxRetry and not sendLocationPos do
		retryCount = retryCount + 1
		print(string.format("[步骤3] 第%d次查找发送位置", retryCount))
		sendLocationPos = ocr_start(84, 1190, 977, 1688, "发送位置")
		if sendLocationPos then
			randomTap(sendLocationPos[1], sendLocationPos[2], 10, 10, "点击发送位置")
			print("[步骤3成功] 已点击发送位置，位置:", sendLocationPos[1], sendLocationPos[2])
		else
			print("[步骤3] 未找到发送位置，等待后重试")
			sleep(800)
		end
	end

	if not sendLocationPos then
		print("[步骤3失败] 无法找到发送位置")
		return false
	end

	-- 步骤4: OCR查找"搜索地点"并点击
	sleep(1500)
	local searchPos = nil
	retryCount = 0
	while retryCount < maxRetry and not searchPos do
		retryCount = retryCount + 1
		print(string.format("[步骤4] 第%d次查找搜索地点", retryCount))
		searchPos = ocr_start(84, 1190, 977, 1688, "搜索地点")
		if searchPos then
			randomTap(searchPos[1], searchPos[2], 10, 10, "点击搜索地点")
			print("[步骤4成功] 已点击搜索地点，位置:", searchPos[1], searchPos[2])
		else
			print("[步骤4] 未找到搜索地点，等待后重试")
			sleep(800)
		end
	end

	if not searchPos then
		print("[步骤4失败] 无法找到搜索地点")
		return false
	end

	-- 步骤5: 等待1秒后再次查找"搜索地点"输入框，检测快捷文字粘贴
	sleep(1000)
	local searchPos2 = nil
	local quickPaste = false  -- 是否命中快捷文字粘贴（直接点击文字区域即可）
	retryCount = 0
	while retryCount < maxRetry and not searchPos2 do
		retryCount = retryCount + 1
		print(string.format("[步骤5] 第%d次查找搜索地点输入框", retryCount))
		searchPos2 = ocr_start(43, 666, 951, 1166, "搜索地点")
		if searchPos2 then
			-- 检测是否存在快捷文字粘贴：OCR高情商回复 或 图片mate30_search_friend_paste.png
			local quickReply = ocr_start(43, 666, 951, 1166, "高情商回复")
			local pasteIdx, pasteX, pasteY = findImage(74, 1153, 372, 1404, "mate30_search_friend_paste.png", 0.9)
			if quickReply then
				-- 存在高情商快捷文字，直接点击文字块
				quickPaste = true
				randomTap(quickReply[1], quickReply[2], 5, 5, "点击高情商快捷文字")
				print(string.format("[步骤5成功] 检测到高情商快捷文字，点击位置:(%d,%d)", quickReply[1], quickReply[2]))
				sleep(1500)
			elseif pasteIdx ~= -1 then
				-- 存在图片快捷文字块，直接点击图片位置
				quickPaste = true
				randomTap(pasteX, pasteY, 5, 5, "点击快捷文字图片块")
				print(string.format("[步骤5成功] 检测到快捷文字图片块，点击位置:(%d,%d)", pasteX, pasteY))
				sleep(1500)
			else
				-- 未检测到快捷文字粘贴，长按唤醒粘贴
				longTap(searchPos2[1], searchPos2[2], 500)
				print(string.format("[步骤5] 未检测到快捷文字粘贴，长按搜索地点输入框唤醒粘贴，位置:(%d,%d)", searchPos2[1], searchPos2[2]))
				sleep(3000)
			end
		else
			print("[步骤5] 未找到搜索地点输入框，等待后重试")
			sleep(800)
		end
	end

	if not searchPos2 then
		print("[步骤5失败] 无法找到搜索地点输入框")
		return false
	end

	-- 步骤6: 仅在未命中快捷文字粘贴（长按路径）时查找粘贴选项并点击
	if not quickPaste then
		sleep(800)  -- 减少等待，防止弹出粘贴菜单超时消失
		local pastePos = nil
		retryCount = 0
		while retryCount < maxRetry and not pastePos do
			retryCount = retryCount + 1
			print(string.format("[步骤6] 第%d次查找粘贴选项", retryCount))
			-- 扩展上边界，覆盖弹出菜单可能出现的区域
			pastePos = ocr_start(105,146,804,1840, "粘贴")
			if pastePos then
				-- 点击粘贴，y-5, x-3
				randomTap(pastePos[1] - 3, pastePos[2] - 5, 5, 5, "点击粘贴")
				print("[步骤6成功] 已点击粘贴，位置:", pastePos[1] - 3, pastePos[2] - 5)
			else
				print("[步骤6] 未找到粘贴选项，重新长按并等待后重试")
				-- 重新长按搜索地点输入框，确保弹出粘贴菜单
				longTap(searchPos2[1], searchPos2[2], 500)
				sleep(1500)
			end
		end

		if not pastePos then
			print("[步骤6失败] 无法找到粘贴选项")
			return false
		end
	else
		print("[步骤6跳过] 快捷文字粘贴路径，无需手动粘贴")
	end

	-- 步骤7: box查找文字块，按y轴正序，点击第一个匹配文字块的y+120位置
	sleep(1500)
	local addressClicked = false
	for retryCount = 1, maxRetry do
		print(string.format("[步骤7] 第%d次查找地址搜索结果", retryCount))

		local textBlocks = ocr_start_with_boxes(155, 588, 907, 1492)
		local candidates = {}
		if textBlocks and #textBlocks > 0 then
			-- 坐标取整
			for _, item in ipairs(textBlocks) do
				item.x = math.floor(item.x or 0)
				item.y = math.floor(item.y or 0)
			end
			print(string.format("[步骤7] 识别到%d个文字块, 查找子串: %s", #textBlocks, addressText))
			for i, item in ipairs(textBlocks) do
				print(string.format("  文字块[%d]: %s 坐标: %d %d", i, item.words, item.x, item.y))
				if item.words and (string.find(item.words, addressText, 1, true) or string.find(addressText, item.words, 1, true)) then
					table.insert(candidates, {x = item.x, y = item.y, words = item.words})
				end
			end
		end

		if #candidates > 0 then
			-- 按y轴正序排列，取第一个（最上方）的文字块
			table.sort(candidates, function(a, b) return a.y < b.y end)
			local firstBlock = candidates[1]
			local tx = firstBlock.x
			local ty = firstBlock.y + 120
			randomTap(tx, ty, 10, 10, "点击地址搜索结果")
			print(string.format("[步骤7成功] 匹配到%d个文字块，点击第1个 '%s', pos=(%d,%d)",
				#candidates, firstBlock.words, tx, ty))
			addressClicked = true
			break
		else
			print("[步骤7] 未找到地址搜索结果，等待后重试")
			sleep(800)
		end
	end

	if not addressClicked then
		print("[步骤7失败] 无法找到地址搜索结果")
		return false
	end

	-- 步骤8: 等待地址选择页面加载后，OCR识别"发送"文字并点击
	sleep(1500)
	local sendPos = nil
	local sendSuccess = false
	retryCount = 0
	while retryCount < maxRetry and not sendSuccess do
		retryCount = retryCount + 1
		print(string.format("[步骤8] 第%d次查找发送按钮", retryCount))
		-- 在右上角区域查找发送按钮
		sendPos = ocr_start(700, 150, 959, 400, "发送")
		if sendPos then
			-- 验证发送按钮位置在右侧，避免点击到取消
			if sendPos[1] > 700 then
				randomTap(sendPos[1], sendPos[2], 10, 10, "点击发送定位")
				print("[步骤8] 已点击发送，位置:", sendPos[1], sendPos[2])
				-- 验证发送是否成功：检测发送按钮是否消失
				sleep(1000)
				local stillExist = ocr_start(700, 150, 959, 400, "发送")
				if stillExist then
					print("[步骤8] 发送按钮仍存在，发送失败，准备重试")
				else
					print("[步骤8成功] 发送按钮已消失，发送成功")
					sendSuccess = true
				end
			else
				print("[步骤8] 发送按钮位置异常（偏左），重新查找")
			end
		else
			-- 找不到发送按钮，可能已经发送成功
			print("[步骤8] 未找到发送按钮，可能已发送成功")
			sendSuccess = true
		end
	end

	if not sendSuccess then
		print("[步骤8失败] 发送定位失败")
		return false
	end

	print("=== 发送定位流程完成 ===")
	local duration = os.time() - op_start
	monitor.record("发送定位：", duration)
	return true
end

-- 收藏转发流程
-- @param keyword 收藏关键词，根据关键词触发对应的收藏转发动作
function C.handleCollectForward(keyword)
	print("=== 开始收藏转发流程 === 关键词:", keyword or "")
	local startTime = os.time()

	-- 等待聊天界面稳定
	sleep(1000)
	-- 步骤0:点击+号
	local index1 = -1
	local x1 = -1
	local y1 = -1
	index1,x1,y1 = findImage(824,1100,947,1930,"wx_plus.png",0.9)
	print("检测+号位置结果",index1,x1,y1)
	
	if index ~= -1 then
		randomTap(x1,y1,5,5,"点击+号位置")
		sleep(1500)
		local nl = ocr_start(767, 1583, 961, 1900, "换行")
        local sign = ocr_start(89, 1646, 443, 1940, "符号")
		
		if nl or sign then
			randomTap(x1,y1,5,5,"点击+号位置")
			sleep(1500)
		end
		
		photoPos = ocr_start(119,1278,897,1794,"相册")
		print("检查相册是否存在",photoPos)
		if photoPos then
			swipe(774,1503,311,1532,500)
			sleep(800)
		end
	end
	sleep(1000)
	local collct = ocr_start(116,1253,855,1638,"收藏")
	print("查找收藏位置",collct)
	if collct then
		randomTap(collct[1],collct[2] - 20,5,5,"点击收藏")
		sleep(1000)
	end
	sleep(1000)
	keywordPos = ocr_start(96,515,913,1914,keyword)
	print("查找关键词"..keyword.."结果",keywordPos)
	
	if keywordPos then
		print("点击"..keyword.."位置")
		randomTap(keywordPos[1],keywordPos[2]-30,5,5,"点击分享"..keyword)
		sleep(1500)
		local sendPos = ocr_start(377,1453,927,1906,"发送")
		print("查找发送位置",sendPos)
		if sendPos then
			randomTap(sendPos[1],sendPos[2],15,5,"点击发送")
		end
	end
	--回到微信列表
	sleep(3000)
	local b,bx,by = findPicEx(99,211,187,292,"wx_back.png",0.9)
	print("回到微信列表图标查找",b,bx,by)
    if b~=-1 then randomTap(bx+12,by+20,3,5,"点击回到微信列表") else randomTap(125,252,3,5,"点击默认回到微信列表") end



	if not forwardSuccess then
		print("[收藏转发] 转发失败或未找到发送按钮")
	end

	-- 返回聊天界面

	sleep(500)

	local duration = os.time() - startTime
	print("=== 收藏转发流程完成，耗时:", duration, "秒 ===")
	return forwardSuccess
end


-- ======================================================
-- 【微信文件传输助手】获取最近 N 条消息坐标（全能版）
-- 通过 OCR 边缘小矩形推断头像位置 + 偏移定位
-- 无需传入头像图片，不依赖 findPicAllPoint 查找头像
-- @param needCount  需要获取的消息数量（默认3）
-- ======================================================
function C.getRecentMsgInFileHelper(needCount)
    needCount = needCount or 3
    print("获取文件传输助手最近 " .. needCount .. " 条消息")

    local reg = { x1 = 100, y1 = 280, x2 = 950, y2 = 1600 }
    local msgs = {}

    -- 辅助：去重插入/更新（50px 容差），avatar 类型不覆盖已有明确类型
    local function addPos(x, y, msgType)
        for _, m in ipairs(msgs) do
            if math.abs(m.x - x) < 50 and math.abs(m.y - y) < 50 then
                if m.type == "avatar" and msgType ~= "avatar" then
                    m.type = msgType
                end
                return
            end
        end
        table.insert(msgs, { x = x, y = y, type = msgType })
    end

    -- ==================== Step1：OCR 扫描全区域 ====================
    local blocks = ocr_start_with_boxes(reg.x1, reg.y1, reg.x2, reg.y2)
    if not blocks or #blocks == 0 then
        print("OCR 无结果")
        return {}
    end

    -- ==================== Step2：霍夫圆检测 → 圆形头像定位 ====================
    -- 微信头像为圆形，用 findCircle 在左右侧分别检测，圆心 + 偏移 = 消息气泡位置
    -- 左侧头像（x<540）→ 气泡在右 (+170,+45)；右侧头像 → 气泡在左 (-170,+45)
    -- findCircle 参数: dp=1, minDist=25, param1=100, param2=30, minRadius=15, maxRadius=30
    local hasAvatarHint = false
    local function detectCircles(x1, y1, x2, y2, offsetX, offsetY)
        local ok, circles = pcall(findCircle, x1, y1, x2, y2, 1, 25, 100, 30, 15, 30)
        if ok and circles and #circles > 0 then
            for _, c in ipairs(circles) do
                addPos(c.x + offsetX, c.y + offsetY, "avatar")
            end
            return true, #circles
        end
        return false, 0
    end

    -- 左侧边缘 (x: 5~120) 搜索圆形头像
    local lOk, lCnt = detectCircles(5, reg.y1, 120, reg.y2, 170, 45)
    -- 右侧边缘 (x: 850~980) 搜索圆形头像
    local rOk, rCnt = detectCircles(850, reg.y1, 980, reg.y2, -170, 45)

    if lOk or rOk then
        hasAvatarHint = true
        print(string.format("霍夫圆检测头像: 左%d个 右%d个 → 共%d个候选", lCnt, rCnt, #msgs))
    else
        -- 降级：findCircle 未命中 → 直接走 OCR 矩形聚类（不尝试 OCR 边缘文字）
        print("霍夫圆检测未命中，将使用 OCR 矩形聚类定位")
    end

    -- ==================== Step3：图标检测（视频/文件/图片） ====================
    local detections = {
        { img = "wx_video_play.png", sim = 0.7,  t = "video" },
        { img = "wx_file_icon.png",  sim = 0.8,  t = "file"  },
        { img = "chat_pic.png",      sim = 0.75, t = "image" },
    }
    for _, det in ipairs(detections) do
        local ok, pts = pcall(findPicAllPoint, reg.x1, reg.y1, reg.x2, reg.y2, det.img, det.sim)
        if ok and pts then
            for _, p in ipairs(pts) do
                addPos(p.x, p.y, det.t)
            end
        end
    end

    -- ==================== Step4：类型细化 / 矩形聚类 ====================
    if hasAvatarHint then
        -- 路径A：有头像 → OCR 细化消息类型
        for _, t in ipairs(blocks) do
            local words = tostring(t.words or ""):lower()
            local refined = nil
            for _, m in ipairs(msgs) do
                if m.type == "avatar" and math.abs(m.x - t.x) < 80 and math.abs(m.y - t.y) < 80 then
                    if words:find("语音") then refined = "voice"
                    elseif words:find("定位") or words:find("位置") then refined = "location"
                    else refined = "text" end
                    m.type = refined
                    break
                end
            end
            if not refined then
                addPos(t.x, t.y, "text")
            end
        end
    else
        -- 路径B：无头像 → OCR 矩形聚类自动定位
        print("启用 OCR 矩形聚类自动定位")
        local clusters = {}
        local Y_GAP = 35

        -- 按 Y 排序后聚类
        local sortedBlocks = {}
        for _, t in ipairs(blocks) do table.insert(sortedBlocks, t) end
        table.sort(sortedBlocks, function(a, b) return a.y < b.y end)

        for _, t in ipairs(sortedBlocks) do
            if t.y > 0 then
                local matched = false
                for _, c in ipairs(clusters) do
                    if math.abs(c.centerY - t.y) < Y_GAP then
                        c.count = c.count + 1
                        c.centerY = math.floor((c.centerY * (c.count - 1) + t.y) / c.count)
                        c.minX = math.min(c.minX, t.x)
                        c.maxX = math.max(c.maxX, t.x)
                        c.minY = math.min(c.minY, t.y - 18)
                        c.maxY = math.max(c.maxY, t.y + 18)
                        c.text = c.text .. (tostring(t.words or ""):lower())
                        matched = true
                        break
                    end
                end
                if not matched then
                    local w = tostring(t.words or ""):lower()
                    local msgType = "text"
                    if w:find("语音") then msgType = "voice"
                    elseif w:find("视频") then msgType = "video"
                    elseif w:find("文件") then msgType = "file"
                    elseif w:find("图片") or w:find("照片") or w:find("image") or w:find("pic") then msgType = "image"
                    elseif w:find("定位") or w:find("位置") then msgType = "location"
                    end
                    table.insert(clusters, {
                        count    = 1,
                        centerY  = t.y,
                        minX     = t.x,  maxX = t.x,
                        minY     = t.y - 18,  maxY = t.y + 18,
                        msgType  = msgType,
                        text     = w,
                    })
                end
            end
        end

        for _, c in ipairs(clusters) do
            if c.text then
                if c.text:find("语音") then c.msgType = "voice"
                elseif c.text:find("视频") then c.msgType = "video"
                elseif c.text:find("文件") then c.msgType = "file"
                elseif c.text:find("图片") or c.text:find("照片") or c.text:find("image") or c.text:find("pic") then c.msgType = "image"
                elseif c.text:find("定位") or c.text:find("位置") then c.msgType = "location"
                end
            end
            local cx = math.floor((c.minX + c.maxX) / 2)
            local cy = math.floor((c.minY + c.maxY) / 2)
            addPos(cx, cy, c.msgType)
        end

        -- 补充：文本聚类间空隙检测 → 填补图片/视频消息（无文字无法 OCR）
        if #clusters >= 2 then
            table.sort(clusters, function(a, b) return a.minY < b.minY end)
            local filled = 0
            for i = 1, #clusters - 1 do
                local gap = clusters[i + 1].minY - clusters[i].maxY
                if gap > 65 then
                    -- 检查空隙内是否已有 Step3 的图标条目
                    local gapMid = math.floor((clusters[i].maxY + clusters[i + 1].minY) / 2)
                    local hasIcon = false
                    for _, m in ipairs(msgs) do
                        if m.type ~= "text" and m.type ~= "avatar"
                           and m.y > clusters[i].maxY and m.y < clusters[i + 1].minY then
                            hasIcon = true
                            break
                        end
                    end
                    if not hasIcon then
                        local gx = math.floor((clusters[i].minX + clusters[i + 1].minX) / 2)
                        addPos(gx, gapMid, "image")
                        filled = filled + 1
                    end
                end
            end
            if filled > 0 then
                print(string.format("空隙检测: 补填 %d 条媒体消息", filled))
            end
        end
        print("OCR 矩形聚类完成，共识别 " .. #clusters .. " 条消息")
    end

    if #msgs == 0 then
        print("未识别到任何消息")
        return {}
    end

    -- 按 Y 降序（最新在前）
    table.sort(msgs, function(a, b) return a.y > b.y end)

    -- 截取前 N 条
    local result = {}
    for i = 1, math.min(needCount, #msgs) do
        local m = msgs[i]
        table.insert(result, { x = math.floor(m.x), y = math.floor(m.y), type = m.type })
        print(string.format("第%d条(%s): (%.0f, %.0f)", i, m.type, m.x, m.y))
    end
    return result
end




-- ==================== 初始化标签任务 ====================
do
	local tag_task = require("tag_task")
	tag_task.init(C, config)
	C.handleNewFriendTag = tag_task.handleNewFriendTag
	C.readTagTask = tag_task.readTagTask
	C.updateTagTaskStatus = tag_task.updateTagTaskStatus
	C.executeTagTask = tag_task.executeTagTask
end

-- ==================== 初始化朋友圈任务 ====================
do
	local moments_task = require("moments_task")
	moments_task.init(C, config)
	C.runMomentsTask = moments_task.run
end

-- ==================== 导出模块 ====================
return C