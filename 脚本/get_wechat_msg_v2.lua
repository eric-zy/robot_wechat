local global_config = require("config")
local monitor = require("performance_monitor")
local common = require("common")
local Req = require("requests")

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

-- 根据通道编号从 read 接口获取 pay_state
local function getChannelPayState(channelNum)
    local url = (global_config.robot_conf_url or "http://127.0.0.1:8095/api/robot/config") .. "?robotCode=" .. (global_config.robot_code or "")
    print("获取通道pay_state:", url)
    local res = getHttp(url)
    if res == false then
        print("获取pay_state失败，默认1")
        return 1
    end
    local ok, decoded = pcall(jsonLib.decode, res)
    if not ok or not decoded or not decoded.success or not decoded.data or not decoded.data.channels then
        print("pay_state解析失败，默认1")
        return 1
    end
    for _, ch in ipairs(decoded.data.channels) do
        if tonumber(ch.channel_num) == tonumber(channelNum) then
            local ps = tonumber(ch.pay_state) or 1
            print("通道", channelNum, "pay_state:", ps)
            return ps
        end
    end
    print("未找到通道", channelNum, "，默认pay_state=1")
    return 1
end


-- 配置参数（优化版）
local config = {
	templatePath = "red_dot1.png|red_dot2.png|wechat_dot_3.png",  -- 未读标记模板
	similarity = 0.88,               -- 图像识别相似度（小幅放宽，避免漏识别）
	baseLeft = 50,                   -- 左边界
	baseRight = 800,                 -- 右边界
	baseTop = 200,                   -- 初始上边界
	maxTotalHeight = 1770,           -- 屏幕最大高度
	segmentHeight = 190,             -- 滑动增量高度
	maxUnreadCount = 10,             -- 最大处理数量
	maxSwipeTimes = 8,               -- 最大滑动次数
	maxSwipes = true,                -- 无限次数滑动
	duplicateThreshold = 35,         -- 重复点阈值
	tapOffset = 30,                  -- 点击偏移量（避免点中红点边缘）
	-- 调试可视化
	debugMode = true,                -- 启用调试标记
	ocrRegion = {left = 100, top = 400, right = 900, bottom = 1500}, -- 消息识别区域
	maxMessageLength = 100,          -- 最大消息长度
	is_send_api = True,  -- 是否发送请求
	--chat_url = global_config.chat_url,
	chat_url = (function()
        local robot_code = global_config.robot_code or ""
        if robot_code == "HF-AT-1-001" or robot_code == "HF-AT-1-002"  or robot_code == "HF-AT-1-005" then
            return global_config.chat_url
        elseif robot_code == "HF-AT-1-003" then
            return global_config.chat_url_loacal or global_config.chat_url
        else
            -- 默认地址
            return global_config.chat_url
        end
    end)(),
	id_customer = global_config.id_customer,
	wx_ignore_list = global_config.wx_ignore_list
}

-- 状态跟踪
local state = {
	processedCount = 0,
	swipeCount = 0,
	processedPoints = {},
	currentTop = config.baseTop,
	lastFoundY = 0
}

-- 循环计数器（模块级局部变量）
local t = 0

-- 微信- 查找并处理当前区域的红点
function processCurrentSegment()
	print("检测当前微信页面是否正确")
	uploadLog("检测当前微信页面是否正确")
	beforeWxRedCheck()
	--优先检测微信左下角是否有红点
	local ret1 = -1
	local x1 = -1
	local y1 = -1
	sleep(600)
	local ret1,x1,y1 = findColor(204,1771,263,1825,"bd3338|bc2c41|be3039",2,0.9)
	print("检测左下角是否有红点标记",ret1,x1,y1)
	if ret1 ~= -1 then
		local debugtartTime = os.time() 
		local segmentBottom = 400
		print(string.format("扫描区域: (%d,%d) - (%d,%d)", config.baseLeft, state.currentTop, config.baseRight, segmentBottom))
		uploadLog(string.format("扫描区域: (%d,%d) - (%d,%d)", config.baseLeft, state.currentTop, config.baseRight, segmentBottom))
		local findResult, x, y = findPicEx( 173,313,289,1774, "red_dot1.png|red_dot2.png|red_dot3.png|red_dot4.png|red_dot2_1.png|ret_dot_1_min.png|red_dot1_1.png|red_dot_1_1.png|red_dot2_3.png|wechat_dot_3.png", config.similarity)
		local findPicExDuration = os.time() - debugtartTime
		print(string.format("查找红点区域：(%d,%d) - (%d,%d)， 结果：%d ,耗时：%d s", 120, 180, 800, 1600, findResult,findPicExDuration))
		uploadLog(string.format("查找红点区域：(%d,%d) - (%d,%d)， 结果：%d ,耗时：%d s", 120, 180, 800, 1600, findResult,findPicExDuration))
		if findResult ~= -1 then
			-- 颜色二次校验：确认匹配点附近确实存在红色像素，避免误识别
			-- 颜色只做小范围二次校验，避免把红色头像背景识别为红点
			-- 不扩大扫描区域，只在模板命中点附近确认红色像素
			local verifyRet = findColor(x - 10, y - 10, x + 10, y + 10, "bd3338|bc2c41|be3039|c92c3f|d43043|e03447", 2, 0.85)
			if verifyRet == -1 then
				print(string.format("颜色校验失败，误识别红点 @(%d, %d)，跳过", x, y))
				uploadLog(string.format("颜色校验失败，误识别红点 @(%d, %d)，跳过", x, y))
			else
				markPoint(x, y, config)
				print(string.format("新红点 @(%d, %d)", x, y))
				table.insert(state.processedPoints, {x = x, y = y})
				-- 点击对话（偏移避免点中红点）
				randomTap(x + config.tapOffset, y, 200, 50)
				sleep(math.random(2800, 3200))
				imgui.close()
				-- 处理消息：获取聊天内容
				if processMessage() then
					state.processedCount = state.processedCount + 1
				end
				local duration = os.time() - debugtartTime
				print(string.format("**微信- 查找并处理当前区域的红点耗时 %d S**",duration))
				uploadLog(string.format("**微信- 查找并处理当前区域的红点耗时 %d S**",duration))
				-- 返回列表 滑动
				sleep(1000)
				state.lastFoundY = y
				return true
			end
		end
	end
		print("当前区域没有红点消息",ret1,x1,y1)
		uploadLog("当前区域没有红点消息",ret1,x1,y1)
		--检查新加好友无消息通知消息
		
	return false
end

-- OCR识别对话框消息
function processMessage()
	-- 微信-检测是否最后一条消息结尾
	sleep(2000)
	local title = ocr_start(162,211,905,337, "")
	local nickname = trim(title)
	
	print(string.format("%s: %s", nickname, message))
	print(string.format("nickname-%s : message- %s", nickname, message))

	--过滤非联系人数据（模糊匹配）
	if config.wx_ignore_list and #config.wx_ignore_list > 0 then
		for _, ignoreName in ipairs(config.wx_ignore_list) do
			if string.find(nickname, ignoreName) then
				print("过滤非联系人数据(模糊匹配):", nickname, "匹配:", ignoreName)
				goBack()
				return false
			end
		end
	end
	--过滤群信息（昵称包含 (XX) 或 (XX人) 格式）
	if string.match(nickname, "%(%d%d?%d?%)") or string.match(nickname, "%(%d%d?%d?人%)") then
		print("过滤群信息",nickname)
		goBack()
		return false
	end
	
	local ret, x, y = findColor(200, 300, 820, 1830, "78be34", 2, 0.9)
	print("微信-检测是否最后一条消息结尾", ret, x, y)

	uploadLog("微信-检测是否最后一条消息结尾", ret, x, y)
	toast("开始定位查找微信消息")

	if y > 1600 then
		y = 1600
	end

	if ret == -1 then
		-- 没查到 或者 没有历史记录
		x = 190
		y = 310
	end

	-- 微信识别聊天内容
	print("190,", y, "930,1830")
	local message = nil
	--时间打印
	local debugStartTime1 = os.time()
	while true do
		sleep(1000)
		message = ocr_start(190, y, 930, 1830, "")
		print("聊天内容检测", y, message)
		handleVoiceMessage(message)
		message = ocr_start(190, y, 930, 1830, "")
		if message == nil or message == "" then
			print("未检测到聊天内容")
		else
			break
		end

		y = y - 50
	end
	local chatCheckTime = os.time() - debugStartTime1
	 print(string.format("**聊天内容检测耗时：%d 秒**",chatCheckTime))
	
	-- 统一提取手机号（仅一次，避免重复调用findContactPhone）
	local phone = string.match(nickname, global_config.phone_pattern)
	if phone == nil then
		print("昵称未找到手机号，点击头像查找")
		phone = string.match(findContactPhone(nickname), global_config.phone_pattern)
		print("findContactPhone查询到的手机号:", phone)
	end
	
	if message ~= nil then
		message = trim(message)
		local robot_code = global_config.robot_code
		local channel_num = _G.wechat_task_options and _G.wechat_task_options.taskId or 1
		local pay_state = getChannelPayState(channel_num)
		
		-- 红包/转载 检测
		print("红包检测", message, y, "pay_state:", pay_state)
		local res = chkWxRedBag(message, robot_code, channel_num, phone, pay_state)
		
		if res then
			local message1 = ";红包收到了"
			message = message..message1
			print("组合后消息内容是",message)
		end
		sleep(1500)
	end
	

	if nickname == "" or nickname == nil then
		nickname = "a"
	end
	print("nickname=",nickname)
	if message == "" then
		return false
	end


	local data = {
		name = nickname,
		ask = message,
		project = _G.wechat_task_options and _G.wechat_task_options.project or global_config.project,
		robot = global_config.robot_code,
		channel_num = _G.wechat_task_options and _G.wechat_task_options.taskId or 1
	}

	data.phone = phone
	print("用户手机号", data.phone)
	sleep(1000)
	local isUserInfo = ocr_start(123,699,960,1576,"音视频通话")
	print("搜索音视频通话结果",isUserInfo)
	if isUserInfo then
		goBack()
	end		


	-- 给后台大脑发送消息
	send_img = 0
	msg_parts = 0
	send_program = 0
	ticket_num = 0
	ticket_type = 0
	address_text = ""  -- 存储地址文本
	collect_content = "" --检测回复是否触发收藏操作关键词
	
	if config.is_send_api == True then
		-- 前置请求：判断走新版还是旧版聊天接口
		local useNewChat = false
		local userReadUrl = global_config.device_user_read_url
			.. "?robot_code=" .. urlEncode(global_config.robot_code)
			.. "&channel_num=" .. tostring(data.channel_num)
			.. "&phone=" .. urlEncode(phone or "")
		print("前置请求 device/user/read:", userReadUrl)
		local userReadRes = getHttp(userReadUrl)
		if userReadRes and userReadRes ~= false then
			local userReadJson = jsonLib.decode(userReadRes)
			if userReadJson and userReadJson.success and userReadJson.data then
				local userProject = tonumber(userReadJson.data.project) or 1
				if userProject ~= 1 then
					useNewChat = true
					print("device/user/read project=" .. tostring(userProject) .. "，使用新版聊天接口")
				else
					print("device/user/read project=1，使用旧版聊天接口")
				end
			end
		else
			print("device/user/read请求失败，默认使用旧版聊天接口")
		end
		
		local res
		if useNewChat then
			-- 新版聊天接口 GET
			local chatUrl = global_config.device_chat_url
				.. "?robot_code=" .. urlEncode(global_config.robot_code)
				.. "&channel_num=" .. tostring(data.channel_num)
				.. "&phone=" .. urlEncode(phone or "")
				.. "&ask=" .. urlEncode(data.ask or "")
			print("新版聊天请求URL:", chatUrl)
			local chatRes = getHttp(chatUrl)
			if chatRes and chatRes ~= false then
				res = jsonLib.decode(chatRes)
				print("新版聊天返回:", chatRes)
			else
				res = false
			end
		else
			res = sendMsg(config.chat_url, data)
		end
		
		if res == false then
			sleep(1000)
			return false
		end
		send_img = res.send_img or 0
		msg_parts = res.msg_parts or 0
		send_program = res.send_program or 0
		ticket_num = res.ticket_num or 0
		ticket_type = res.ticket_type or 0
		local send_address = res.send_address or 0
		print("发送http请求结果：", res, send_img)
		
		-- 获取地址文本（从answer字段提取）
		if res.data and res.data.answer then
			address_text = res.data.answer
		end

		-- 检查resource_name是否有值，有则触发收藏转发流程
		if res.resource_name and res.resource_name ~= "" then
			collect_content = res.resource_name
			print("检测到resource_name:", res.resource_name, "，将触发收藏转发")
		end
		print("发送http请求结果：", res, send_img, "send_address:", send_address, "address_text:", address_text)
		
		-- 获取payState用于判断是否走付费流程
		local payStateValue = _G.wechat_task_options and _G.wechat_task_options.payState or 1
		-- 如果add_user_state=3时更新为2
		if res.add_user_state == 3 then
			print("检测到add_user_state=3，调用updates接口更新为2")
			local ok, updateRes = pcall(function()
				local updateData = {
					project = _G.wechat_task_options and _G.wechat_task_options.project or global_config.project or 1,
					im = (res.data and res.data.im) or "",
					msg = (res.data and res.data.phone) or "",
					state = 2,
					payState = payStateValue,
				}
				return Req.upstate(global_config.id_wx_ai_api_url, updateData)
			end)
			if ok then
				if updateRes == false then
					print("updates接口返回失败，继续执行主流程")
				else
					print("updates接口返回结果：", updateRes)
				end
			else
				print("updates接口调用异常，继续执行主流程：", updateRes)
			end
		end
	else
		print("暂时跳过发送消息")
		sleep(2000)
	end
	
	-- 转发小程序给联系人（需要外层ticket_num=0且send_program=1）
	print("send_program value:",send_program,"ticket_num:",ticket_num,"ticket_type:",ticket_type)
	if send_program == 1 and ticket_num == 0 and (ticket_type == 1 or ticket_type == "1")  then
		print("开始转发小程序给联系人:", nickname)
		common.forwardMiniApp(nickname)
		sleep(1000)
	end
	
	-- 返回手机界面
	backHome()
	sleep(1000)

	-- 打开ID 获取指定对话框
	local msgPartsNum = tonumber(msg_parts)
	if msgPartsNum and msgPartsNum > 1 then
		print("两条以上的消息")
		common.sendMessages(msg_parts, send_img, collect_content)
		sleep(1000)
		
		-- 确保返回到微信消息列表
		common.backToWeChatMessageList()
	else
		local debugStartTime = os.time()
		local success = openID()

		if not success then
			return false
		end
		
		-- 识别ID定位消息
		findIDMsgBack()
		-- 滑动切回微信应用 - 滑动返回桌面再打开微信
		backHome()
		sleep(800)
		openWeChatImg()
		sleep(500)

		-- 微信查找消息输入框并粘贴
		findWxMsgInputPaste()
		local click_res = clickWxSendMsg()
		
		-- 发送定位
		if send_address == 1 and address_text and address_text ~= "" then
			print("发送定位")
			common.sendAddress(address_text)
		end

		if click_res then
			-- 发送图片
			--if send_img > 0 then
			--	print("发送图片")
			--	common.sendImages(send_img)
			--end
			
			-- 收藏转发流程
			if collect_content and collect_content ~= "" then
				print("触发收藏转发流程，关键词:", collect_content)
				common.handleCollectForward(collect_content)
			end
			
		
			-- 返回微信消息列表
			randomTap(120,250, 5, 5)
			sleep(1000)
			
			return true
		end
		print(string.format("**识别ID定位消息、并返回微信发送检测耗时：%d 秒**",(os.time() - debugStartTime)))
	end
	
	return false
end


--查找昵称中没有手机号的联系的人手机号
function findContactPhone(nickname)
	-- 判断nickname是否包含标准11位手机号
	local nicknamePhone = nil
	if nickname and type(nickname) == "string" then
		nicknamePhone = string.match(nickname, global_config.phone_pattern)
	end
	-- 提取昵称中的数字序列，检查是否为11位
	local nicknameDigits = nickname and string.gsub(nickname, "[^%d]", "") or ""
	local isNicknamePhoneValid = nicknamePhone and #nicknamePhone == 11

	local maxRetry = 3
	local retryCount = 0

	while retryCount < maxRetry do
		retryCount = retryCount + 1
		print(string.format("=== 第%d次尝试查找手机号 ===", retryCount))

		-- 步骤1: 点击右上角查找图片
		local findDotIndex, findDotX, findDotY = findImage(793,183,955,309, "wx_chat_detail_right_top.png", 0.9)
		print("findDot:", findDotIndex, findDotX, findDotY)
		if findDotIndex ~= -1 and findDotX ~= -1 and findDotY ~= -1 then
			randomTap(findDotX + 36, findDotY + 25, 5, 5, "点击右上角详情")
			sleep(1000)
		else
			print("未找到右上角按钮，重试")
			sleep(500)
			randomTap(findDotX + 36, findDotY + 25, 5, 5, "点击右上角详情")
		end

		-- 步骤1校验: 检测是否存在"聊天信息"
		sleep(500)
		local chatInfo = ocr_start(283, 204, 812, 317, "聊天信息")
		print("检测聊天信息:", chatInfo)
		if not chatInfo then
			print("未检测到聊天信息，重新点击右上角")
			sleep(500)
			randomTap(findDotX + 36, findDotY + 25, 5, 5, "点击右上角详情")
			-- 重试点击右上角
		else
			-- 步骤2: 查找"查找聊天记录"文字
			local searchChat = ocr_start(81, 391, 951, 749, "查找聊天记录")
			print("查找聊天记录:", searchChat)
			if searchChat then
				-- 点击识别位置的x-54，y-208位置，随机偏移x,y轴10像素
				local clickX = searchChat[1] - 54
				local clickY = searchChat[2] - 208
				randomTap(clickX, clickY, 10, 10, "点击查找聊天记录")
				sleep(1500)

				-- 步骤3: 确认当前是否有"发消息"或"音视频通话"（带重试）
				local hasSendMsg = false
				local hasVideoCall = false
				local step3Retry = 0
				local maxStep3Retry = 5

				while step3Retry < maxStep3Retry and not (hasSendMsg or hasVideoCall) do
					hasSendMsg = ocr_start(183,541,880,1887, "发消息")
					hasVideoCall = ocr_start(183,541,880,1887, "音视频通话")
					print("发消息:", hasSendMsg, "音视频通话:", hasVideoCall, "重试次数:", step3Retry)

					if hasSendMsg or hasVideoCall then
						break
					end

					step3Retry = step3Retry + 1
					print("未检测到发消息或音视频通话，第" .. step3Retry .. "次重试")
					sleep(1000)
				end

				if hasSendMsg or hasVideoCall then
					-- 步骤4: 识别范围内的文字，过滤出手机号（带重试）
					local contentText = nil
					local ocrRetry = 0
					local maxOcrRetry = 5

					while ocrRetry < maxOcrRetry do
						contentText = ocr_start(107,658,832,847, "")
						print("识别到的内容:", contentText)

						if contentText and contentText ~= "" then
							break
						end

						ocrRetry = ocrRetry + 1
						print("识别内容为空，第" .. ocrRetry .. "次重试")
						sleep(1000)
					end

					if not contentText or contentText == "" then
						print("OCR识别失败，已达最大重试次数")
					end

					local phoneNumber = string.match(contentText, global_config.phone_pattern)
					if phoneNumber then
						print("找到手机号:", phoneNumber)
						-- 步骤5: 点击左上角回退到微信聊天界面(需点击两次)
						common.weChatBack()
						sleep(800)
						common.weChatBack()
						sleep(1000)

						-- 校验当前页面是否属于聊天界面（模糊匹配昵称）
						local wxCheckContent = ocr_start(232,199,829,309, "")
						print("校验界面内容:", wxCheckContent)
						if wxCheckContent then
							-- 从校验内容中提取手机号
							local checkPhone = string.match(wxCheckContent, global_config.phone_pattern)
							-- 多种匹配策略：
							-- 1. 精确匹配：识别内容包含昵称或昵称包含识别内容
							-- 2. 手机号匹配：提取的手机号与phoneNumber一致
							-- 3. 前缀匹配：昵称前4个字符存在于识别内容中
							local nicknamePart = utf8.mid(nickname, 1, math.min(4, utf8.length(nickname)))
							local exactMatch = string.find(wxCheckContent, nickname) or string.find(nickname, wxCheckContent)
							local phoneMatch = checkPhone and checkPhone == phoneNumber
							local prefixMatch = string.find(wxCheckContent, nicknamePart)
							
							if exactMatch or phoneMatch or prefixMatch then
								-- 如果昵称中的手机号不是标准11位，使用朋友资料中识别到的手机号
								local finalPhone = phoneNumber
								if isNicknamePhoneValid then
									finalPhone = nicknamePhone
									print("昵称中的手机号为标准11位，使用昵称手机号:", finalPhone)
								else
									print("已返回微信聊天界面，返回朋友资料中的手机号:", finalPhone)
								end
								return finalPhone
							else
								print("昵称不匹配，期望:", nickname, "或", nicknamePart, "或手机号:", phoneNumber, "实际:", wxCheckContent)
							end
						else
							print("未识别到界面内容，继续重试")
						end
			else
					print("未识别到手机号，返回上一步重试")
						-- 返回上一步（从查找聊天记录页面返回聊天信息页面）
						common.weChatBack()
						sleep(800)
						-- 再返回一步（从聊天信息页面返回聊天界面）
						common.weChatBack()
						sleep(500)
					end
				else
					print("未检测到发消息或音视频通话，重试上一步")
					-- 返回上一步（从查找聊天记录页面返回聊天信息页面）
					common.weChatBack()
					sleep(800)
					-- 再返回一步（从聊天信息页面返回聊天界面）
					common.weChatBack()
					sleep(500)
				end
			else
				print("未找到查找聊天记录")
			end
		end
	end
	print("多次重试后仍未找到手机号")
	-- 兜底：如果昵称中有手机号（即使非标准11位），返回它
	if nicknamePhone then
		print("兜底返回昵称中的手机号:", nicknamePhone)
		return nicknamePhone
	end
	return ""
end

-- 切换查找ID应用
function openID()
	print("定位ID位置")	
	local success = openIdApp()
	--sleep(1500)
	 sleep(1000)
	toast(string.format("指定用户[%s]识别中...", global_config.id_ai_project_config.name))

	-- 打开ID 获取指定用户
	local res = ocr_start(86, 406, 925, 1833, global_config.id_ai_project_config.name)
	print("匹配指定对话框位置：", res)

	if res ~= -1 and res then
		local x, y = res[1], res[2]
		randomTap(x, y, 500, 80)
	end
	
	--sleep(1500)
	sleep(1000)
	-- 点击对话框
	
	return true
end

function handleNoRedMsgStep()
	print("检测wx列表是否有静默消息流程开始")
	uploadLog("检测wx列表是否有静默消息流程开始")
	
	-- 辅助函数：验证返回值是否为有效坐标数组
	local function isValidCoord(res)
		return type(res) == "table" and res[1] and res[2]
	end
	
	local patterns = {
		global_config.wx_nored_check.msg_pattern_1,
		global_config.wx_nored_check.msg_pattern_2,
		global_config.wx_nored_check.msg_pattern_3
	}
	
	for i, pattern in ipairs(patterns) do
		if pattern then
			local res = ocr_start(234, 374, 917, 1764, pattern)
			print("pattern_"..i.."["..pattern.."]: ", res)
			if isValidCoord(res) then
				randomTap(res[1], res[2] - 20, 30, 5, "点击静默消息")
				processMessage()
				break
			end
		end
	end
	
	print("检测wx列表是否有静默消息流程结束")
	uploadLog("检测wx列表是否有静默消息流程结束")
end

-- 微信消息识别前流程开始前的前置操作 功能不在wx聊天列表则回退
-- 1.检测wx是否在添加朋友页面 若是则回退到列表
-- 2.检查当前是否在聊天页面 若是回退列表
function beforeWxRedCheck()
	local isAddFriendPage = ocr_start(391,208,674,287,"添加朋友")
	print("验证当前是否在添加好友界面,res:",isAddFriendPage)
	--local isChatPage = ocr_start(824,1100,947,1930,)
	
	local index1 = -1
	local x1 = -1
	local y1 = -1
	index1,x1,y1 = findImage(824,1100,947,1930,"wx_plus.png",0.9)
	
	print("验证当前是否在聊天详情界面,res:",index1,x1,y1)
	uploadLog("验证当前是否在聊天详情界面,res:",index1,x1,y1)
	
	if isAddFriendPage ~= false or index1 ~= -1 then
		local index = -1
		local x = -1
		local y = -1
		index,x,y=findPicEx(99,211,187,292,"wx_back.png",0.9)
		if index ~= -1 then
			randomTap(x+12,y+20,3,5,"识别到返回图片位置，点击返回")
		else
			randomTap(125,252, 3, 5, "返回")
		end
	end
end

function startFindMsg()
	-- 重置状态，确保每次执行都是全新的
	state = {
		processedCount = 0,
		swipeCount = 0,
		processedPoints = {},
		currentTop = 0,
		lastFoundY = 0
	}
	t = 0

	print("=== startFindMsg 开始执行 ===")
	uploadLog("=== startFindMsg 开始执行 ===")

	-- 主逻辑 - 执行完一次加好友流程后切换下一任务

	while state.processedCount < config.maxUnreadCount and state.swipeCount <= config.maxSwipeTimes do
		t = t + 1
		print(state.processedCount, config.maxUnreadCount, state.swipeCount, config.maxSwipeTimes, config.maxSwipes)
		monitor.start()

		if processCurrentSegment() then
			-- 成功处理：重置扫描区域
			state.currentTop = config.baseTop
			state.swipeCount = 0
			-- 生成报告
			monitor.report()
		else
			-- 未找到：滑动屏幕
			if not config.maxSwipes then
				state.swipeCount = state.swipeCount + 1
			end

			if state.lastFoundY > 0 then
				-- 智能滑动：基于最后找到的位置
				local swipeStartY = math.min(state.lastFoundY + 300, config.maxTotalHeight - 200)
				-- swipe(500, swipeStartY, 500, swipeStartY - config.segmentHeight, 800)
			else
				-- 常规滑动
				-- swipe(500, 1500, 500, 1500 - config.segmentHeight, 800)
			end

			print(string.format("滑动屏幕 (#%d)，新位置: %d", state.swipeCount, state.currentTop))
			uploadLog(string.format("滑动屏幕 (#%d)，新位置: %d", state.swipeCount, state.currentTop))
			-- state.currentTop = state.currentTop + config.segmentHeight
			print("10秒后滑动")
			uploadLog("10秒后滑动")
			-- sleep(1000)
			sleep(100)

			-- 执行加好友流程，执行完后切换下一任务
			if t >= 5 then
				print("加好友流程启动")
				uploadLog("加好友流程启动")
				toast("没有消息，去处理加好友流程")
				local success, hasProcessed = common.addWXFriendOptimize()
				print("加好友流程结束，切换下一任务")
				uploadLog("加好友流程结束，切换下一任务")

				-- 如果存在加好友数据且走完加好友流程，再走静默消息流程
				if hasProcessed then
					handleNoRedMsgStep()
				end

				-- 生成报告
				monitor.report()

				-- 执行完一次加好友流程后切换下一任务
				break
			end

			sleep(800)
		end

		-- 边界检查
		if state.currentTop >= config.maxTotalHeight then
			state.currentTop = config.baseTop
		end
	end

	print(string.format("完成！处理 %d 条未读消息", state.processedCount))
	uploadLog(string.format("完成！处理 %d 条未读消息", state.processedCount))
end

-- 重置状态函数，供外部调用时重置模块状态
function resetState()
	state = {
		processedCount = 0,
		swipeCount = 0,
		currentTop = 0,
		lastFoundY = 0
	}
	t = 0
	print("状态已重置")
end

-- 导出模块
local M = {
	startFindMsg = startFindMsg,
	resetState = resetState
}

return M
