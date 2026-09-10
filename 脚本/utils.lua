local config = require("config")
local Comm = require("common")

--[[

function getEnvironment()
    -- 方法1：检查 getAppVersion
    if type(getAppVersion) == "function" then
        local version = getAppVersion()
        if version and version ~= "" then
            return "APK"
        end
    end
    
    -- 方法2：检查 getPackageName
    if type(getPackageName) == "function" then
        local package = getPackageName()
        if package and package ~= "" then
            return "APK"
        end
    end
    
    -- 方法3：检查特定APK函数
    if type(getEngineVersion) == "function" then
        return "APK"
    end
    
    -- 方法4：检查文件系统（APK中通常受限）
    if not fileExist("/sdcard/") then
        return "APK"
    end
    
    -- 默认认为是PC环境
    return "PC"
end


-- findImage 兼容打包APK
function findImageFixed(x1, y1, x2, y2, imageList, similarity)
	local env = getEnvironment()

	if env == "APK" then
		-- APK环境：逐个尝试图片
		for imgName in string.gmatch(imageList, "([^|]+)") do
			local ret = findImage(x1 or 0, y1 or 0, x2 or 0, y2 or 0, "res://" .. imgName, similarity or 0.7)
			if ret then
				return ret, ret[1], ret[2]
			end
		end
		return -1, -1, -1
	else
		-- PC环境：使用原方式
		return findImage(x1 or 0, y1 or 0, x2 or 0, y2 or 0, imageList, similarity or 0.7)
	end
end

-- findPic 兼容打包APK
function findPicFixed(x1, y1, x2, y2, imageList, color, order, similarity)
	local env = getEnvironment()

	if env == "APK" then
		-- APK环境：逐个尝试图片
		for imgName in string.gmatch(imageList, "([^|]+)") do
			local index, x, y = findPic(x1 or 0, y1 or 0, x2 or 0, y2 or 0, "res://" .. imgName, color or "000000", order or 0, similarity or 0.8)
			if index ~= -1 then
				return index, x, y
			end
		end
		return -1, -1, -1
	else
		-- PC环境：使用原方式
		return findPic(x1 or 0, y1 or 0, x2 or 0, y2 or 0, imageList, color or "000000", order or 0, similarity or 0.8)
	end
end

]]


-- 去除两端空格的函数
function trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

-- 封装是否在函数内
function isInArray(value, array)
    for _, v in ipairs(array) do
        if value == v then
            return true
        end
    end
    return false
end

-- 带随机偏移的点击函数
function randomTap(x, y, a, b, msg)
	msg = msg or nil
    if not x or not y or x == -1 or y == -1 then
    	print("randomTap 参数无效: x="..tostring(x)..", y="..tostring(y))
    	return false
    end
    
    -- 计算随机偏移量
    local offsetX = math.random(0, a)
    local offsetY = math.random(0, b)
    
    -- 计算目标位置
    local targetX = x + offsetX
    local targetY = y + offsetY
    
    -- 执行点击操作
    tap(targetX, targetY)
    
    -- 调试信息
    print(string.format("%s-点击位置: (%d, %d) - 原始位置: (%d, %d) - 偏移: (%d, %d)", 
      msg, targetX, targetY, x, y, offsetX, offsetY))
		uploadLog(string.format("%s-点击位置: (%d, %d) - 原始位置: (%d, %d) - 偏移: (%d, %d)", 
      msg, targetX, targetY, x, y, offsetX, offsetY))
    return true
end

-- lua 字典排序 按y从小到大排序
function arrSortByY(data)
	-- 转换为数组形式，保存原始索引
	local array = {}
	for key, value in pairs(data) do
		table.insert(array, {
			id = key,
			y = value.y,
			x = value.x
		})
	end
	-- 按y值从小到大排序
	table.sort(array, function(a, b)
		return a.y < b.y
	end)
	return array
end

-- 重试sleep
function optimizedWait(conditionFunc, timeout, checkInterval)
	timeout = timeout or 3000       		-- 默认3000毫秒（缩短等待时间）
	checkInterval = checkInterval or 300  	-- 默认300毫秒

	-- 获取当前时间的毫秒数（近似）
	local function getCurrentTimeMS()
		return os.clock() * 1000
	end

	local startTime = getCurrentTimeMS()

	while getCurrentTimeMS() - startTime < timeout do
		if conditionFunc() then
			return true
		end
		sleep(checkInterval)
	end

	print(string.format("等待超时: %.0f毫秒", getCurrentTimeMS() - startTime))
	return false
end

-- 从返回手机界面
function backHome()
	local home_ret = false
	local maxRetry = 10  -- 最大重试次数
	local retryCount = 0

	while home_ret == false and retryCount < maxRetry do
		retryCount = retryCount + 1
		--local ret, x, y = findImage(0, 0, 0, 0, "home_btn.png|home_btn1.png|home_btn2.png|home_btn3.png|home_btn4.png|home_btn_vivo.png|home_btn_vivo1.png|home_btn_vivo2.png|home_btn_redmi.png", 0.7)
		local ret, x, y = findImage(0, 0, 0, 0, "mate30_home.png|mate30_home_1.png", 0.7)
		sleep(500)
		print("返回home2:", ret, x, y, "重试次数:", retryCount)
		if ret ~= -1 then
			home_ret = true
		end

		if home_ret == true then
			x = x + math.random(10, 20)
			y = y + math.random(10, 20)
			randomTap(x, y, 10, 10)
			break
		end
	end
	sleep(1000)
end

-- 返回
function goBack()
	local back_ret = false
	local maxRetry = 5  -- 最大重试次数
	local retryCount = 0

	while back_ret == false and retryCount < maxRetry do
		retryCount = retryCount + 1
		local ret, x, y = findImage(0, 0, 0, 0, "msg_back.png|msg_back1.png|msg_back2.png|msg_back3.png|msg_back4.png", 0.7)
		print("go_back返回home1:", ret, x, y, "重试次数:", retryCount)

		if ret ~= -1 then
			back_ret = true
		end

		if back_ret == true then
			x = x +20+ math.random(5, 10)
			y = y+30 + math.random(5, 10)
			randomTap(x, y, 10, 10)
			sleep(800)
			break
		else
			print("go_back返回home1固定位置点击:", ret, x, y)
			randomTap(120,257,10,5,"ID返回聊天列表固定位置点击")
			sleep(800)
			back_ret = true
		end
	end
end

-- 识别并打开微信
function openWeChatImg()
	
	-- 直接打开
	return Comm.changeToWX()
	
	--local x, y = -1, -1
	--local ret, x, y = findImage(0, 0, 0, 0, "wx_logo_1.png|wxapp_logo.png", 0.8)

	--print(ret, x, y)

	-- 检查是否找到微信图标
	--if ret == -1 then
		-- ocr识别微信
	--	sleep(500)
	--	local locationB = ocr_start(85, 415, 912, 1947, "微信")

	--	if locationB then
	--		if locationB[2] < 260 then
	--			randomTap(locationB[1] + 10, locationB[2] + 100, 10, 50)
	--		end
	--		return true
	--	else
	--		backHome()
	--		return false
	--	end
	--end

	-- 获取图标位置
	--if x ~= -1 and y ~= -1 then
		-- 在图标区域随机点击
	--	return randomTap(x, y, 20, 40)
	--end

	--return true
end

-- 微信点击发送按钮
function clickWxSendMsg()
	local clickRes = false
	local n = 0
	while clickRes == false do
		n = n + 1
		local rex, x, y = findImage(0, 0, 0, 0, "send_btn.png", 0.8)
		print(string.format("发送按钮坐标: %d, %d", x, y))

		-- 图片匹配失败时，尝试 OCR 检测"发送"按钮
		if rex == -1 then
			print("图片匹配失败，尝试OCR检测发送按钮")
			local sendBtn = ocr_start(750, 1100, 950, 1250, "发送")
			if sendBtn then
				print("OCR检测到发送按钮位置:", sendBtn[1], sendBtn[2])
				x = sendBtn[1]
				y = sendBtn[2]
				rex = 1
			end
		end

		if rex ~= -1 then
			clickRes = true
		end

		toast(string.format("发送按钮坐标: %d, %d", x, y))

		if clickRes == true then
			print("查找发送按钮坐标:", x, y)
			sleep(800)
			-- 发送按钮
			randomTap(x, y, 20, 10, "发送按钮")
			-- 检测左侧是否还有文字信息 来确保点击发送事件生效
			sleep(1000)
			local checkSendNotOk = ocr_start(212,1127,749,1211,"")
			print("确认输入框是否有文字-result",checkSendNotOk)
			if checkSendNotOk ~= "" then
				randomTap(x+50, y+20, 20, 20, "发送按钮重复点击")
			end
			
			break	
		end
		if n == 5 then
			print("需检查外部光线等原因，5次未识别改为手动固定点击发送位置")
			randomTap(872,1180,20,20,"点击固定发送位置")
			break
		end

		print("重新定位发送按钮坐标")
		sleep(1000)
	end

	return true
end

-- 识别并打开智企ID
function openIdApp()
	local find_id_logo_ret = false
	toast("定位智企坐标")
	local n = 0
	while find_id_logo_ret == false do
		local ret, x, y = findImage(0, 0, 0, 0, "ID_logo_01.png|ID_logo_02.png|ID_logo_03.png|ID_logo.png|id_logo.png|idapp.png|ld_logo9.png", 0.85)
		print("查询ID结果:", ret, x, y)

		if ret ~= -1 then
			find_id_logo_ret = true
		end

		if find_id_logo_ret == true then
			-- 获取图标位置
			-- 在图标区域随机点击
			randomTap(x, y, 100, 100)
			-- sleep(1000)
			sleep(500)
			break
		end
		if n == 3 then
			break
		end
		n = n+1
	end		
	if n == 3 then
		print("直接点击")
		randomTap(541,1909, 1, 1)
		sleep(500)
		randomTap(599,1747, 100, 100)
	end
	return true
end

-- 可视化标记点
function markPoint(x, y, config)
	if config.debugMode then
		local circle1 = imgui.createCircle(x, y, 10, 0xFFFF0000, true, 12)
		ret = imgui.show(false) -- 不阻塞
		sleep(300) -- 确保标记可见
	end
end

-- 微信发送消息
-- 微信发送消息
function findWxMsgInputPaste()
	print("微信发送消息")
	print("点击输入框")

	-- 添加重试机制
	local retryCount = 0
	local maxRetry = 3
	local pasteSuccess = false

	while retryCount < maxRetry and not pasteSuccess do
		retryCount = retryCount + 1
		print(string.format("第%d次尝试粘贴消息", retryCount))

		optimizedWait(function ()
			debugtartTime = os.clock()

			-- 点击输入框并验证输入法是否打开
			local inputBoxRetry = 0
			local inputBoxOpened = false

			-- 先OCR识别右下角是否有"换行"两个字
			local newlineRes = ocr_start(689, 1589, 951, 1914, "换行")
			print("初始检测输入法换行符号:", newlineRes)
			local rex, x, y = findImage(0, 0, 0, 0, "send_btn.png", 0.8)
			print(string.format("发送按钮识别坐标: %d, %d", x, y))
			-- 如果发送按钮已存在，说明消息已粘贴好，直接点击发送
			if rex ~= -1 then
				print("发送按钮已存在，消息已粘贴，直接点击发送")
				randomTap(x, y, 20, 10, "点击发送按钮")
				sleep(1500)
				pasteSuccess = true
				return true
			end
			if newlineRes then
				print("输入法已打开，直接执行粘贴操作")
				inputBoxOpened = true
			else
				print("输入法未打开，开始点击输入框")

				-- 图片查找输入框位置（移到循环外）
				local index = -1
				local x = -1
				local y = -1
				index, x, y = findPic(94,1702,948,1982, "chat_box_left_btn.png", "101010", 3, 0.9)
				print("图片查找输入框", index, x, y)

				while inputBoxRetry < 3 and not inputBoxOpened do
					inputBoxRetry = inputBoxRetry + 1
					print(string.format("第%d次点击输入框", inputBoxRetry))

					if index ~= -1 then
						print("图片识别点击消息输入框")
						local tapX = x + math.random(120, 400)
						local tapY = y + math.random(10, 80)
						randomTap(tapX, tapY, 20, 20, "点击消息输入框")
					else
						print("直接点击消息输入框")
						randomTap(288,1849, 20, 20, "点击消息输入框")
					end

					-- 等待1秒后检查输入法是否打开
					sleep(1500)

					-- OCR识别右下角范围是否存在"换行"
					newlineRes = ocr_start(689, 1589, 951, 1914, "换行")
					fhRes = ocr_start(86,1703,351,1931,"符号")
					print("检测输入法换行符号:", newlineRes)
					print("检测输入法符号:", fhRes)

					if newlineRes or fhRes then
						print("输入法已打开，检测到换行符号")
						inputBoxOpened = true
						break
					else
						print(string.format("未识别到换行，输入法未打开，第%d次点击失败", inputBoxRetry))
						if inputBoxRetry < 3 then
							sleep(300)
						end
					end
				end
			end

			if not inputBoxOpened then
				print("输入框展开失败，本次粘贴流程失败")
				return false
			end

			-- 执行粘贴操作
			local index = -1
			local x = -1
			local y = -1
			index, x, y = findPic(100,1162,288,1924, "chat_box_left_btn.png", "101010", 3, 0.9)
			print("查找输入框位置", index, x, y)

			if index ~= -1 then
				print("图片识别点击消息输入框")
				x = x + math.random(120, 400)
				y = y + math.random(10, 80)
				randomTap(x, y, 20, 20, "点击输入框")
			else
				print("直接点击输入框唤醒粘贴")
				randomTap(223,1160,100,20,"直接点击输入框唤醒粘贴")
			end
			sleep(1000)

			-- 扩大OCR检测范围并添加检测
			local res = ocr_start(80, 1000, 350, 1250, "粘贴")
			print("文字识别粘贴", res)

			if res then
				print("点击粘贴")
				randomTap(res[1], res[2], 3, 3, "点击粘贴")
				sleep(1500)
				-- 验证粘贴是否成功：检测右侧是否有"发送"按钮
				local verifyPaste = ocr_start(649, 990, 940, 1904, "发送")
				print("验证右侧发送按钮:", verifyPaste)
				if verifyPaste then
					print("粘贴成功，检测到发送按钮")
					pasteSuccess = true
					return true
				else
					print("粘贴可能失败，未检测到发送按钮")
				end
			else
				print("直接点击粘贴")
				randomTap(176,1080, 30, 30, "点击粘贴")
				sleep(500)
				--二次确认
				local res1 = ocr_start(80, 1000, 350, 1250, "粘贴")
				if res1 then
					randomTap(res1[1],res1[2],30,30)
					sleep(1000)
					-- 验证粘贴是否成功：检测右侧是否有"发送"按钮
					local verifyPaste = ocr_start(649, 990, 940, 1904, "发送")
					print("验证右侧发送按钮(二次确认):", verifyPaste)
					if verifyPaste then
						print("粘贴成功（二次确认），检测到发送按钮")
						pasteSuccess = true
						return true
					else
						print("粘贴可能失败（二次确认），未检测到发送按钮")
					end
				end
			end
			print("**微信发送消息-长按输入框耗时**",os.clock()-debugtartTime)
		end,8000,800)

		if not pasteSuccess and retryCount < maxRetry then
			print(string.format("第%d次粘贴失败，等待%d毫秒后重试", retryCount, 800))
			sleep(800)
		end
	end

	if pasteSuccess then
		print("粘贴消息成功")
		return true
	else
		print(string.format("粘贴消息失败，已重试%d次", maxRetry))
		return false
	end
end

-- 识别ID定位消息
function findIDMsgBack()
	-- 识别ID定位消息
	--local ret, x1, y1 = findColor(360, 835, 800, 1700, "b6b6b4|b6b7b4|b7b7b5|c7cbcb|c9cecc|ccd2d4|ccd2d5", 2, 1)
	local x1, y1 = nil, nil
	n = 0
	local maxRetry = 10  -- 最大重试次数
	while n < maxRetry do
		sleep(1500)
	    n =  n + 1
		local arr=findPicAllPoint(204,335,394,1838,"id_yifang_logo2.png",0.9)
		print("第"..n.."次识别ID回复单条消息查询的坐标信息",arr)
		if next(arr) ~= nil then
			arr = arrSortByY(arr) -- 按从上到下排序
			print("计算当前页回复消息数量",arr)
			x1 =  arr[#arr].x +math.random(150,200)
			y1 = arr[#arr].y + math.random(60,80)
			print("消息内容坐标：", x1, y1)
			break
		elseif n == 3 then
			-- 打开ID 获取指定用户
			print("重新定位ID列表发消息位置")
			local res = ocr_start(265,449,944,1751, config.id_ai_project_config.name)
			print("匹配指定对话框位置：", res)

			if res ~= -1 and res then
				local x, y = res[1], res[2]
				randomTap(x, y, 500, 80,"点击"..config.id_ai_project_config.name.."位置并等待1s")
				sleep(1000)
			else
				--检测当前是否在加好友位置
				local addFriendDetailRes = ocr_start(369,209,693,301,config.id_ai_project_config.receive_name)
				local messageRes = ocr_start(100,309,210,1744,config.id_ai_project_config.name)
				if addFriendDetailRes and messageRes then
					print("检测到当前在"..config.id_ai_project_config.receive_name.."详情页，跳转回"..config.id_ai_project_config.name)
					randomTap(messageRes[1],messageRes[2]-50,5,5,"跳转回发消息位置")
				end
			end
			n = 0  -- 重置计数器，继续查找
		end
	end

	-- 如果超过最大重试次数仍未找到，返回false
	if n >= maxRetry then
		print("识别ID消息失败，已达最大重试次数")
		return false
	end

	local circle2 = imgui.createCircle(x1, y1, 10, 0xFFFF0000, true, 12)
	ret = imgui.show(false) -- 不阻塞
	sleep(100)

	-- 长按
	longTap(x1, y1)
	sleep(1000)
	imgui.close()

	-- 查找复制按钮
	local rey, id_msg_copy_x, id_msg_copy_y = findImage(0, 0, 0, 0, "id_msg_copy2.png|id_msg_copy1.png|id_msg_copy.png|id_msg_copy3.png|id_msg_copy4.png", 0.8)
	print("id 复制按钮：", id_msg_copy_x, id_msg_copy_y)

	if rey == -1 then
		print("未识别到复制图标")
		return false
	end

	-- 点击复制按钮
	randomTap(id_msg_copy_x + 20, id_msg_copy_y, 30, 60, "点击复制按钮")
	sleep(800)

	-- 返回ID消息列表
	local bak_msg_list_ret = -1
	local x = -1
	local y = -1
	--增加返回列表保底机制
	checkBack = checkIDBackList(config.id_ai_project_config.name)
	print("检测当前是否返回ID列表结果",checkBack)

	local retryBackCount = 0
	local maxBackRetry = 5
	local retIDList = false

	while retryBackCount < maxBackRetry and not retIDList do
		retryBackCount = retryBackCount + 1
		print(string.format("返回ID列表第%d次尝试", retryBackCount))

		bak_msg_list_ret, x, y = findImage(0, 0, 200, 350, "msg_bak.png|msg_back_1.png", 0.9)
		print("id返回消息列表:", bak_msg_list_ret, x, y)
		if bak_msg_list_ret ~= -1 then
			randomTap(x+5, y+5, 5, 5, "id返回消息列表")
			sleep(1000)
			-- 验证是否真的返回了列表（检测是否还在详情页）
			local stillInDetail = ocr_start(303, 195, 771, 310, config.id_ai_project_config.name)
			if stillInDetail then
				print("仍在详情页，返回列表失败，准备重试")
			else
				print("已成功返回列表")
				retIDList = true
				break
			end
		else
			-- 没找到返回按钮，检查是否已经在列表
			checkBack = checkIDBackList(config.id_ai_project_config.name)
			if checkBack then
				print("已在列表页，无需返回")
				retIDList = true
				break
			end
		end

		if not retIDList then
			print("返回ID列表点击未生效，准备重试")
			-- 尝试使用OCR查找返回按钮
			local backPos = ocr_start(50, 180, 200, 350, "返回")
			if backPos then
				randomTap(backPos[1], backPos[2], 5, 5, "OCR点击返回")
			else
				-- 尝试点击固定位置
				randomTap(108, 241, 10, 10, "固定位置点击返回")
			end
			sleep(1000)
		end
	end

	if not retIDList then
		print("返回ID列表失败，已达最大重试次数")
		return false
	end

	--sleep(500)
	sleep(100)
end

-- 转换函数：将表转为 key=value&key=value 格式
function tableToQueryString(t)
	local parts = {} -- 用于存储每个 key=value 部分

	for k, v in pairs(t) do
		-- 将键和值拼接为 "key=value" 格式，添加到数组中
		table.insert(parts, tostring(k) .. "=" .. tostring(v))
	end

	-- 用 & 符号连接所有部分
	return table.concat(parts, "&")
end

-- 网络请求Post（超时5分钟）
function postHttp(url, params)
	local ret, code = httpPost(url, params, 300)

	if code ~= 200 then
		print("请求失败",code,ret)
		return false
	end

	return ret
end

-- 网络请求Get
function getHttp(url)
	local ret, code = httpGet(url)

	if code ~= 200 then
		print("GET请求失败", code, ret)
		return false
	end

	return ret
end

-- 发送消息（chat接口专用，超时90秒）
function sendMsg(url, data)
	-- 设置HTTP请求超时时间为90秒
	if httpSetTimeout then
		httpSetTimeout(90000)
	end

	if data == "" then
		-- 测试内容
		data = {
			name = "yufei",
			ask = "消息测试内容",
			project = 1
		}
	end

	print("请求url:", url)
	local params = tableToQueryString(data)
	print("等待请求结果：", params)
	toast("已发送请求，等待结果中...")

	local res = postHttp(url, params)
	print("服务器返回结果",res)
	if res ~= false then
		local res_json = jsonLib.decode(res)
		print(res_json)
		return res_json
	else
		print("--接口返回数据异常，请联系管理员--")
		sleep(800)
		randomTap(117,249,5,5,"返回微信列表")
		return false
	end


end

-- 微信红包检测
-- @param message 消息内容
-- @param robot_code 机器人编号
-- @param channel_num 渠道编号
-- @param phone 手机号
-- @param pay_state 支付状态
function chkWxRedBag(message, robot_code, channel_num, phone, pay_state)
	sleep(1000)
	if string.match(message, "已过期") then
		-- 红包已经过期
		return false
	end
	
	if string.match(message, "已领取微信红包") then
		print("红包已领取")
		return false
	end

	if string.match(message, "微信转账") then
		print("message"..message)
		print("文字识别有转账")
		-- 定位红包位置
		local index = -1
		local x = -1
		local y = -1
		index, x, y = findPic(0, 0, 0, 0, "redbag.png|wechat_transfer.png|transfer3.png|transfer4.png|transfer5.png|transfer6.png|transfer7.png", "000000", 0, 0.9)
		print("图片识别转账定位", index, x, y)

		-- 通过图片识别红包定位失败
		if index == -1 then
			-- 通过文字识别
			center, _ = ocr_start(0,0,0,0, "微信转账")

			if center then
				print("文字识别转账定位", center[1], center[2])
				res = tapTransfer(center[1], center[2], robot_code, channel_num, phone, pay_state)

				if res then
					return true
				end
			end
		else
		print("图片识别转账定位", index, x, y)
		res = tapTransfer(x, y, robot_code, channel_num, phone, pay_state)

		if res then
			return true
		end
	end

	if string.match(message, "请收款") then
			print("请收款")
		else
			print("可能有转账")
		end
	elseif string.match(message, "微信红包") then
		print("文字识别有红包")
		-- 定位红包位置
		local index = -1
		local x = -1
		local y = -1
		index, x, y = findPic(201, 271, 832, 1738, "readbag1.png|redBag2.png", "000000", 0, 0.9)
		print("图片识别红包定位", index, x, y)

		-- 通过图片识别红包定位失败
		if index == -1 then
			-- 通过文字识别
			center, _ = ocr_start(201, 271, 832, 1738, "微信红包")
			center1, _ = ocr_start(201, 271, 832, 1738, "恭喜发财，大吉大利")
		
			if center then
				print("文字识别红包定位", center, center[1], center[2])
				res = tapRedBag(center[1], center[2], robot_code, channel_num, phone, pay_state)

				if res then
					return true
				end
			end
			if center1 then
				print("文字识别红包定位", center1, center1[1], center1[2])
				res1 = tapRedBag(center1[1], center1[2], robot_code, channel_num, phone, pay_state)

				if res1 then
					return true
				end
			end
		else
			print("图片识别红包定位", index, x, y)
			res = tapRedBag(x, y, robot_code, channel_num, phone, pay_state)

			if res then
				return true
			end
		end
	else
		local index = -1
		local x = -1
		local y = -1
		index, x, y = findImage(201,271,832,1738,"redbag.png|wechat_transfer.png|transfer3.png|transfer4.png|transfer5.png",0.9)
		print("识别转账结果",index, x, y)

		if index ~= -1 then
			print("图片识别有转账")
			-- 定位红包位置
			local index = -1
			local x = -1
			local y = -1
			index, x, y =  findImage(201,271,832,1738,"redbag.png|wechat_transfer.png|transfer3.png|transfer4.png|transfer5.png",0.9)
			print("图片识别转账定位", index, x, y)

			-- 通过图片识别红包定位失败
			if index == -1 then
				-- 通过文字识别
				center, _ = ocr_start(201, 271, 832, 1738, "微信转账")

				if center then
					print("文字识别转账定位", center[1], center[2])
					res = tapTransfer(center[1], center[2], robot_code, channel_num, phone, pay_state)

					if res then
						return true
					end
				end
			else
				print("图片识别转账定位", index, x, y)
				res = tapTransfer(x, y, robot_code, channel_num, phone, pay_state)

				if res then
					return true
				end
			end
		else
			print("本屏没发现红包/转账")
			return false
		end
	end
end

-- 收取红包
-- 收取红包
-- @param x 点击位置x
-- @param y 点击位置y
-- @param robot_code 机器人编号
-- @param channel_num 渠道编号
-- @param phone 手机号
function tapRedBag(x, y, robot_code, channel_num, phone, pay_state)
	pay_state = pay_state or 1
	tap(x, y)
	sleep(800)

	-- 图片识别开红包
	local index = -1
	local ix = -1
	local iy = -1
	index, ix, iy = findPic(205, 570, 831, 1539, "openredbag.png", "000000", 0, 0.9)
	print("图片识别收红包定位", index, ix, iy)

	if index == -1 then
		-- 通过文字识别
		center, _ = ocr_start(205, 570, 831, 1539, "開")

		if center then
			print("文字识别收红包定位 并点击开红包", center, center[1], center[2])
			tap(center[1], center[2])
			sleep(5000)
			-- 收取红包后返回
			tap(123, 235)
			-- 收取红包后调用加票接口
			if robot_code and channel_num and phone then
				local request = require("requests")
				local result = request.ticketAdd(phone, robot_code, channel_num, pay_state)
				if result and result.success then
					print("加票成功，ticket_num:", result.ticket_num or "")
				else
					print("加票失败:", result and result.msg or "")
				end
			end
			return true
		else
			-- 通过固定位置
			print("图片和文字识别都没识别到开红包位置 点击固定位置开红包")
			tap(520, 1259)
			sleep(5000)
			-- 收取红包后返回
			tap(123, 235)
			-- 收取红包后调用加票接口
			if robot_code and channel_num and phone then
				local request = require("requests")
				local result = request.ticketAdd(phone, robot_code, channel_num, pay_state)
				if result and result.success then
					print("加票成功，ticket_num:", result.ticket_num or "")
				else
					print("加票失败:", result and result.msg or "")
				end
			end
			return true
		end
	else
		print("通过图片识别 并点击开红包")
		tap(ix, iy)
		sleep(600)
		-- 收取红包后返回
		tap(123, 235)
		-- 收取红包后调用加票接口
		if robot_code and channel_num and phone then
			local request = require("requests")
			local result = request.ticketAdd(phone, robot_code, channel_num, pay_state)
			if result and result.success then
				print("加票成功，ticket_num:", result.ticket_num or "")
			else
				print("加票失败:", result and result.msg or "")
			end
		end
		return true
	end

	return false
end

-- 收取转帐
-- @param x 点击位置x
-- @param y 点击位置y
-- @param robot_code 机器人编号
-- @param channel_num 渠道编号
-- @param phone 手机号
-- @param pay_state 支付状态
function tapTransfer(x, y, robot_code, channel_num, phone, pay_state)
	pay_state = pay_state or 1
	tap(x, y)
	sleep(2800)

	-- 图片识别开转帐
	local index = -1
	local ix = -1
	local iy = -1
	index, ix, iy = findPic(224, 1444, 800, 1667, "redbag.png|wechat_transfer.png|transfer3.png|transfer4.png|transfer5.png|transfer6.png|transfer7.png", "000000", 0, 0.9)
	print(index, ix, iy)
	print("图片识别收转帐定位", index, ix, iy)

	if index == -1 then
		-- 通过固定位置
		tap(528, 1599)
		print("图片和文字识别都没识别到开转帐位置 点击固定位置开转帐")
		sleep(5000)
		-- 收取转帐后返回
		tap(138,262)
	else
		print("通过图片识别 并点击开转帐")
		tap(ix, iy)
		sleep(6000)
		-- 收取转帐后返回
		tap(138,262)
	end

	-- 收取转账后调用加票接口
	if robot_code and channel_num and phone then
		local request = require("requests")
		local result = request.ticketAdd(phone, robot_code, channel_num, pay_state)
		if result and result.success then
			print("加票成功，ticket_num:", result.ticket_num or "")
		else
			print("加票失败:", result and result.msg or "")
		end
	end

	return true
end



-- 微信小程序点击发送按钮
function clickWxSendButton()
	local clickRes = false
	local maxRetry = 5  -- 最大重试次数
	local retryCount = 0

	while clickRes == false and retryCount < maxRetry do
		retryCount = retryCount + 1
		local ret= ocr_start(436,1567,953,1846, "发送")
		print("识别发送按钮结果",ret, "重试次数:", retryCount)

		if ret then
			clickRes = true
			print(string.format("发送按钮坐标: %d, %d", ret[1], ret[2]))
			uploadLog(string.format("发送按钮坐标: %d, %d", ret[1], ret[2]))
			toast(string.format("发送按钮坐标: %d, %d", ret[1], ret[2]))
			print("查找发送按钮坐标:", ret[1], ret[2])
			uploadLog("查找发送按钮坐标:", ret[1], ret[2])
			sleep(800)
			-- 发送按钮
			randomTap(ret[1],ret[2], 20, 20, "发送按钮")
			sleep(1000)
			break
		end

		print("重新定位发送按钮坐标")
		sleep(1000)
	end

	return clickRes
end

--检测id是否回到列表
function checkIDBackList(name)
	sleep(500)
	check = ocr_start(303,195,771,310,name)
	if check then
		return false
	else
		return true
	end
end

--校验table是否为空
function isEmpty(t)
	print(type(t),t)
	if t == false then
		return true
	end
    return next(t) == nil
end

function mergeTables(t1, t2)
    if isEmpty(t1) and isEmpty(t2) then
        return {}  -- 如果两个table都为空，返回一个空table
    elseif isEmpty(t1) then
        return t2  -- 如果t1为空，返回t2
    elseif isEmpty(t2) then
        return t1  -- 如果t2为空，返回t1
    else
        local result = {}
        for _, v in ipairs(t1) do
            table.insert(result, v)
        end
        for _, v in ipairs(t2) do
            table.insert(result, v)
        end
        return result  -- 返回合并后的table
    end
end

-- 上传日志信息
function uploadLog(msg)
	-- debug 为 false 时全局不走日志上传接口
	if not config.log_config.debug then
		return nil
	end
	local writeLogSwitch = config.log_config.switch
	local header = ""
	if config.log_config.debug then
	-- 匹配打印的文件名及行号
		local info = debug.getinfo(2, "Sl")
		header = info.source:match("[^/\\]+$")..":"..info.currentline
	end
	
	if writeLogSwitch then
		local apiUrl = config.log_config.write_log_api_url
		local params = {
			header = header,
			deviceId = config.current_machine_code,
			logData = msg
		}
	 	local res = postJsonHttp(apiUrl,params)
		--print("写入日志-服务器返回结果",res)
		if res ~= false then
			local res_json = jsonLib.decode(res)
			return res_json
		else
			print("--日志接口请求异常，请联系管理员--")
			sleep(800)
			return false
		end
	end
end

-- 网络请求Post
function postJsonHttp(url, params)
	local ret, code = httpPost(url, jsonLib.encode(params),300)

	if code ~= 200 then
		print("请求失败",code,ret)
		return false
	end

	return ret
end


-- 检测是否有语音消息
function handleVoiceMessage(msg)
	if msg and string.match(msg, "转文字") then
	
		local transferChinese = ocr_start(227,313,918,1782,"转文字")
		--检测到转文字则点击
		if transferChinese then
			print("识别到语音消息",transferChinese)
			randomTap(transferChinese[1],transferChinese[2],1,1,"点击转文字")
			sleep(2000)
			return true
		end
	end
	return false
end