-- 标签任务模块
-- 从 common.lua 中迁移出来的标签相关功能

local M = { _VERSION = 0.1 }

-- 引用由 init() 注入
local C
local config

-- ==================== URL编码函数 ====================
local function urlEncode(s)
    if not s then return "" end
    s = tostring(s)
    s = string.gsub(s, "([^\r])\n", "%1\r\n")
    s = string.gsub(s, "([^%w%-%_%.%~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    return s
end

-- 初始化依赖（由 common.lua 在加载后调用）
function M.init(_C, _config)
	C = _C
	config = _config
end

-- ==================== newFriendTag流程：标签处理 ====================
function M.handleNewFriendTag(tagName)
	print("步骤：处理新好友标签, tagName=" .. tostring(tagName))
    local addTag = ocr_start(159,602,856,1552,"添加标签")
	print("查找添加标签文字位置",addTag)
	if addTag then
		randomTap(addTag[1],addTag[2],3,20,"点击添加标签")
		sleep(2000)
		
		local rawTags = ocr_start_with_boxes(131,665,940,1912)
		print(rawTags)
		
		-- 1. 坐标转换为整型
		for _, item in ipairs(rawTags or {}) do
			item.x = math.floor(item.x or 0)
			item.y = math.floor(item.y or 0)
		end
		
		-- 2. 查找tagName是否在标签列表中
		local matchedTag = nil
		local newTagPos = nil
		for _, item in ipairs(rawTags or {}) do
			if item.words and type(item.words) == "string" then
				local cleanWords = string.gsub(item.words, "[%s%p]", "")
				local cleanTagName = string.gsub(tagName, "[%s%p]", "")
				if string.find(item.words, tagName) or string.find(tagName, item.words)
				   or string.find(cleanWords, cleanTagName) or string.find(cleanTagName, cleanWords) then
					matchedTag = item
					print("找到匹配标签: " .. item.words .. " (x:" .. item.x .. ", y:" .. item.y .. ")")
					break
				end
				-- 记录"新建标签"位置
				if string.find(item.words, "新建标签") then
					newTagPos = {x = item.x, y = item.y}
				end
			end
		end
		
		if matchedTag then
			-- 标签已存在，直接点击选中
			print("标签已存在，直接选中")
			randomTap(matchedTag.x, matchedTag.y, 10, 10, "选中标签: " .. tagName)
			sleep(1000)
			print("点击完成")
			completeRes = ocr_start(642,597,960,758,"完成")
			print("查找完成坐标",completeRes)
			if completeRes then
				randomTap(completeRes[1],completeRes[2],4,2,"点击完成")
			end

		elseif newTagPos then
			-- 标签不存在，点击"新建标签"
			print("标签不存在，点击新建标签: (" .. newTagPos.x .. ", " .. newTagPos.y .. ")")
			randomTap(newTagPos.x, newTagPos.y, 10, 10, "点击新建标签")
			sleep(2000)
			
			-- 3. 调用接口发送标签信息给设备
			-- POST /api/tag_channel/send_to_device
			-- 参数: robot_code, channel_num, tag_name
		local robot_code = config.robot_code or ""
		local channel_num = (_G.wechat_task_options and (_G.wechat_task_options.taskId or _G.wechat_task_options.channelNum)) or 1
			
			local http = require("socket.http")
			local ltn12 = require("ltn12")
			
			local send_device_url = config.tag_channel_send_to_device_url or "http://127.0.0.1:8095/api/tag_channel/send_to_device"
			local post_data = string.format('{"robot_code":"%s","channel_num":%s,"tag_name":"%s"}',
				tostring(robot_code), tostring(channel_num), tostring(tagName))
			
			print("调用发送标签接口: " .. send_device_url)
			print("参数: " .. post_data)
			
			local response_body = {}
			local res, code = http.request{
				url = send_device_url,
				method = "POST",
				sink = ltn12.sink.table(response_body),
				headers = {
					["Content-Type"] = "application/json",
					["Content-Length"] = tostring(#post_data),
				},
				source = ltn12.source.string(post_data),
			}
			
			if res and code == 200 then
				print("发送标签接口返回: " .. table.concat(response_body))
			else
				print("发送标签接口失败, HTTP状态码: " .. tostring(code))
			end
			
			-- 4. 回到桌面 -> 打开ID -> 复制最新一条记录 -> 回退到ID列表 -> 切回微信
			print("回到桌面...")
			C.backToHomeWithCheck(3)
			sleep(1000)
			
			print("打开ID获取消息...")
			local idOpened = false
			for idRetry = 1, 2 do
				C.openIDOptimize()
				sleep(1000)
				if C.searchIDOptimize(config.id_ai_project_config and config.id_ai_project_config.name or "", false) then
					sleep(1500)
					idOpened = true
					break
				end
				print("打开ID失败，重试第" .. idRetry .. "次...")
				sleep(1000)
			end
			
			if not idOpened then
				print("打开ID失败，跳过复制消息")
			end
			
			-- 获取ID消息列表并复制最新一条消息（带重试）
			if idOpened then
				local msgs = nil
				for msgRetry = 1, 3 do
					msgs = C.getIDMessages()
					if msgs and #msgs > 0 then
						break
					end
					print("未获取到ID消息，重试第" .. msgRetry .. "次")
					if msgRetry < 3 then
						if C.searchIDOptimize(config.id_ai_project_config and config.id_ai_project_config.name or "", false) then
							sleep(1000)
						else
							print("重新进入对话失败，停止重试")
							break
						end
					end
				end

				if msgs and #msgs > 0 then
					print("获取到" .. #msgs .. "条ID消息")
					local lastMsg = msgs[#msgs]
					local msg_x = lastMsg.x + 200
					local msg_y = lastMsg.y + 60
					
					print("长按复制最新一条消息")
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
						print("最新消息复制成功")
					else
						print("复制消息失败")
					end
				else
					print("未获取到ID消息")
				end
				
				-- 返回ID消息列表
				C.backToIDMessageList()
				sleep(500)
				
				-- 切回微信
				print("切回微信...")
				C.backToHomeWithCheck()
				sleep(500)
				randomTap(422, 1791, 10, 10, "打开微信")
				sleep(1500)
				
				-- 1. 查找"标签名称"位置
				local tagNameLabelPos = ocr_start(93, 681, 823, 969, "标签名称")
				if tagNameLabelPos then
					print("找到标签名称位置: (" .. tagNameLabelPos[1] .. ", " .. tagNameLabelPos[2] .. ")")
					
					-- 2. 点击对应坐标（y偏移3，x偏移60）
					local tapX = tagNameLabelPos[1] + 60
					local tapY = tagNameLabelPos[2] + 3
					randomTap(tapX, tapY, 10, 10, "点击标签名称区域")
					sleep(1500)
					
					-- 3. 检测是否有"高情商回复"（剪切板已有内容）
					print("检测高情商回复...")
					local smartReply = ocr_start(496, 1187, 925, 1354, "高情商回复")
					if smartReply then
						print("找到高情商回复: (" .. smartReply[1] .. ", " .. smartReply[2] .. ")")
						randomTap(smartReply[1] - 500, smartReply[2], 150, 5, "点击剪切板内容")
						sleep(1000)
						
						-- 关闭输入法
						C.closeInputMethodIfNeeded()
						sleep(500)
					else
						-- 没有高情商回复，长按唤醒粘贴框
						print("未找到高情商回复，长按唤醒粘贴框...")
						longTap(tapX, tapY)
						sleep(1500)
						
						-- 4. 查找粘贴位置并点击（带重试）
						local pasteClicked = false
						for pasteRetry = 1, 3 do
							local pastePos = ocr_start(96, 630, 840, 921, "粘贴")
							if pastePos then
								print("找到粘贴按钮: (" .. pastePos[1] .. ", " .. pastePos[2] .. ")")
								randomTap(pastePos[1], pastePos[2], 5, 5, "点击粘贴")
								sleep(1000)
								pasteClicked = true
								break
							end
							print("未找到粘贴按钮，重试第" .. pasteRetry .. "次...")
							sleep(500)
						end
						
						if not pasteClicked then
							print("粘贴失败，未找到粘贴按钮")
						end
						
						-- 关闭输入法
						C.closeInputMethodIfNeeded()
						sleep(500)
					end
					
					-- 5. 查找"确定"位置并点击
					sleep(1000)
					local confirmPos = ocr_start(339,1089,719,1301, "确定")
					if confirmPos then
						print("找到确定按钮: (" .. confirmPos[1] .. ", " .. confirmPos[2] .. ")")
						randomTap(confirmPos[1], confirmPos[2], 5, 5, "点击确定")
						sleep(1000)
						print("标签创建确认完成")
						completeRes = ocr_start(642,597,960,758,"完成")
						print("查找完成坐标",completeRes)
						if completeRes then
							randomTap(completeRes[1],completeRes[2],4,2,"点击完成")
						end
					else
						print("未找到确定按钮")
					end
				else
					print("未找到标签名称位置")
				end
			end
		else
			print("未找到新建标签按钮")
		end
	else
		print("已有标签,跳过加标签流程")
	end
end


-- ==================== 标签任务接口 ====================
-- 读取单条标签任务 GET /api/tag_task/read?robot_code=xxx&channel_num=1
-- @param robot_code 机器人编号
-- @param channel_num 通道编号
-- @return task_data 任务数据(包含task_list, target_tag_name等) 或 nil
function M.readTagTask(robot_code, channel_num)
	if not robot_code or not channel_num then
		print("readTagTask: robot_code或channel_num为空")
		return nil
	end
	
	local url = config.tag_task_read_url .. "?robot_code=" .. tostring(robot_code) .. "&channel_num=" .. tostring(channel_num)
	print("调用读取标签任务接口: " .. url)
	
	local http = require("socket.http")
	local ltn12 = require("ltn12")
	
	local response_body = {}
	local res, code = http.request{
		url = url,
		method = "GET",
		sink = ltn12.sink.table(response_body),
	}
	
	if not res or code ~= 200 then
		print("读取标签任务失败, HTTP状态码: " .. tostring(code))
		return nil
	end
	
	local body = table.concat(response_body)
	print("读取标签任务接口返回: " .. body)
	
	local ok, decoded = pcall(jsonLib.decode, body)
	if not ok then
		print("解析标签任务响应失败")
		return nil
	end
	
	if decoded and decoded.success and decoded.data then
		local task_list = decoded.data.task_list
		if task_list and #task_list > 0 then
			local task = task_list[1]
			-- 兼容新旧两种字段格式:
			-- 新格式: { tag_id, tag_name, lk_id, old_tag_name, channel_id, status, create_time, update_time }
			-- 旧格式: { id, task_name, target_tag_name, target_tag_id, user_list, total_count, ... }
			local task_id = task.tag_id or task.id
			local task_name = task.tag_name or task.task_name
			local target_tag_name = task.target_tag_name or task.tag_name
			local target_tag_id = task.target_tag_id or task.tag_id
			print("获取到标签任务: task_id=" .. tostring(task_id) .. ", tag_name=" .. tostring(task_name)
				.. ", target_tag_name=" .. tostring(target_tag_name)
				.. ", lk_id=" .. tostring(task.lk_id)
				.. ", old_tag_name=" .. tostring(task.old_tag_name))
			return {
				task_id = task_id,
				task_name = task_name,
				target_tag_id = target_tag_id,
				target_tag_name = target_tag_name,
				lk_id = task.lk_id,
				old_tag_name = task.old_tag_name,
				total_count = task.total_count,
				status = task.status,
				success_count = task.success_count,
				fail_count = task.fail_count,
				user_list = task.user_list or {},
				channel = decoded.data.channel,
			}
		else
			print("无待执行标签任务")
		end
	else
		print("读取标签任务返回失败: " .. tostring(decoded and decoded.message))
	end
	
	return nil
end

-- 更新标签任务完成状态 POST /api/tag_task/update_status
-- @param task_id 任务ID
-- @param user_ids 用户ID列表(table) 或 逗号分隔的字符串
-- @return success 是否成功, response 服务器响应
function M.updateTagTaskStatus(task_id, user_ids)
	if not task_id then
		print("updateTagTaskStatus: task_id为空")
		return false, nil
	end
	
	local user_ids_str
	if type(user_ids) == "table" then
		user_ids_str = table.concat(user_ids, ",")
	elseif type(user_ids) == "string" then
		user_ids_str = user_ids
	else
		user_ids_str = ""
	end
	
	local url = config.tag_task_update_status_url
	print("调用更新标签任务状态接口: " .. url)
	print("参数: task_id=" .. tostring(task_id) .. ", user_ids=" .. user_ids_str)
	
	local http = require("socket.http")
	local ltn12 = require("ltn12")
	
	local post_data = string.format('{"task_id":%s,"user_ids":"%s"}', tostring(task_id), user_ids_str)
	
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
		print("更新标签任务状态失败, HTTP状态码: " .. tostring(code))
		return false, nil
	end
	
	local body = table.concat(response_body)
	print("更新标签任务状态接口返回: " .. body)
	
	local ok, decoded = pcall(jsonLib.decode, body)
	if not ok then
		print("解析更新标签任务响应失败")
		return false, body
	end
	
	return decoded and decoded.success or false, body
end

-- 执行标签任务流程
-- @param task_data 标签任务数据(由readTagTask返回)
-- @return string 执行结果描述
function M.executeTagTask(task_data)
	if not task_data or not task_data.target_tag_name or not task_data.user_list then
		print("executeTagTask: 任务数据不完整")
		return "任务数据不完整"
	end

	local tagName = task_data.target_tag_name
	local userList = task_data.user_list
	local taskId = task_data.task_id

	print(string.format("开始执行标签任务: task_id=%s, tag_name=%s, 用户数量=%s",
		tostring(taskId), tagName, #userList))

	-- 用户数为0时直接更新状态并跳过任务
	if not userList or #userList == 0 then
		print("任务用户数为0，直接更新状态并跳过")
		M.updateTagTaskStatus(taskId, {})
		return "用户数为0，已跳过"
	end

	-- 打开微信通讯录
	print("回到桌面")
	C.backToHomeWithCheck()
	sleep(500)
	print("打开微信")
	C.openWeChatSimple()
	sleep(2000)

	-- 点击通讯录
	local contactTab = ocr_start(188,1768,785,1932, "通讯录")
	print("查找通讯录位置",contactTab)
	if contactTab then
		randomTap(contactTab[1], contactTab[2], 10, 10, "点击通讯录")
		sleep(1500)
	else
		randomTap(416,1836, 20, 10, "点击通讯录(默认位置)")
		sleep(1500)
	end

	-- 点击标签
	local tagBtn = ocr_start(123,369,746,1018, "标签")
	print("查找标签位置",tagBtn)
	if tagBtn then
		randomTap(tagBtn[1], tagBtn[2], 5, 3, "点击标签")
		sleep(2000)
	else
		print("未找到标签入口")
		return "未找到标签入口"
	end

	-- ========== 标签任务：查找/创建目标标签 ==========
	local newTagCreated = false
	local completedIds = {}
	print("步骤1：检测标签列表中是否已有目标标签: " .. tostring(tagName))
	local tagFound = false

	-- 1. 检测98,451,928,1773范围内的文字块，查看是否有匹配的目标标签名称
	local ocrItems = ocr_start_with_boxes(98, 451, 928, 1773)
	if ocrItems then
		-- 坐标取整
		for _, item in ipairs(ocrItems) do
			item.x = math.floor(item.x or 0)
			item.y = math.floor(item.y or 0)
		end
		for _, item in ipairs(ocrItems) do
			if item.words and type(item.words) == "string" then
				local cleanWords = string.gsub(item.words, "[%s%p]", "")
				local cleanTagName = string.gsub(tagName, "[%s%p]", "")
				if string.find(item.words, tagName) or string.find(tagName, item.words)
				   or string.find(cleanWords, cleanTagName) or string.find(cleanTagName, cleanWords) then
					print("找到目标标签: " .. item.words .. " 位置: (" .. item.x .. ", " .. item.y .. ")")
					randomTap(item.x, item.y, 5, 5, "点击目标标签: " .. tagName)
					sleep(1500)
					tagFound = true

					-- 标签已存在，查找"添加"按钮 126,1748,314,1936 → 点击 → 下拉选择联系人
					print("标签已存在，查找添加按钮并选择联系人")
					local existAddPos = nil
					for retryExist = 1, 3 do
						existAddPos = ocr_start(126, 1748, 314, 1936, "添加")
						if existAddPos then break end
						print("未找到添加按钮，重试第" .. retryExist .. "次...")
						sleep(800)
					end

					if existAddPos then
						print("找到添加按钮: (" .. existAddPos[1] .. ", " .. existAddPos[2] .. ")")
						randomTap(existAddPos[1], existAddPos[2], 10, 10, "点击添加")
						sleep(1500)

						print("下滑查找并选中联系人")
						local selectedContacts = M.selectContactsByDropDown(userList)
						if selectedContacts then
							for _, contactId in ipairs(selectedContacts) do
								table.insert(completedIds, contactId)
								print("  记录选中联系人ID: " .. tostring(contactId))
							end
							print("共选中 " .. #selectedContacts .. " 个联系人加入标签")

							-- 底部添加按钮完成后
							if #selectedContacts > 0 then
								print("点击底部添加按钮完成操作")
								local bottomAddClicked = false
								for retry10 = 1, 5 do
									local bottomAddPos = ocr_start(632, 1694, 972, 1922, "添加")
									if bottomAddPos then
										print(string.format("找到底部添加: (%d, %d), 第%d次点击", bottomAddPos[1], bottomAddPos[2], retry10))
										randomTap(bottomAddPos[1], bottomAddPos[2], 10, 10, "点击底部添加")
										sleep(1500)
										local stillAdd = ocr_start(632, 1694, 972, 1922, "添加")
										if not stillAdd then
											print("底部添加按钮已消失，点击成功")
											bottomAddClicked = true
											break
										else
											print("底部添加仍存在，第" .. retry10 .. "次重试...")
										end
									else
										print("未找到底部添加按钮，重试第" .. retry10 .. "次...")
										sleep(800)
									end
								end
								if not bottomAddClicked then
									print("底部添加按钮重试耗尽，继续流程")
								end
							end
						end
					else
						print("未找到添加按钮")
					end

					-- 联系人已通过下拉方式选择完毕，跳过后续逐个处理
					newTagCreated = true
					break
				end
			end
		end
	end

	if not tagFound then
		-- 2. 目标标签不存在，尝试下滑查找，或点击"新建"
		print("步骤2：目标标签不存在，尝试下滑查找...")
		local prevOCRText = ""
		local newTagClicked = false

		for scrollAttempt = 1, 10 do
			local curOCRItems = ocr_start_with_boxes(98, 451, 928, 1773)
			-- 坐标取整
			if curOCRItems then
				for _, item in ipairs(curOCRItems) do
					item.x = math.floor(item.x or 0)
					item.y = math.floor(item.y or 0)
				end
			end
			local curOCRText = ""
			if curOCRItems then
				for _, item in ipairs(curOCRItems) do
					if item.words then
						curOCRText = curOCRText .. item.words
						-- 边滑动边搜索目标标签
						local cleanWords = string.gsub(item.words, "[%s%p]", "")
						local cleanTagName = string.gsub(tagName, "[%s%p]", "")
						if string.find(item.words, tagName) or string.find(tagName, item.words)
						   or string.find(cleanWords, cleanTagName) or string.find(cleanTagName, cleanWords) then
							print("滑动后找到目标标签: " .. item.words .. " 位置: (" .. item.x .. ", " .. item.y .. ")")
							randomTap(item.x, item.y, 5, 5, "点击目标标签: " .. tagName)
							sleep(1000)
							tagFound = true
							break
						end
					end
				end
			end

			if tagFound then break end

			-- 比较当前页面与上一页文本，90%相似说明已到底
			if prevOCRText ~= "" and curOCRText ~= "" then
				local matchCount = 0
				local minLen = math.min(#prevOCRText, #curOCRText)
				if minLen > 0 then
					for ci = 1, minLen do
						if prevOCRText:sub(ci, ci) == curOCRText:sub(ci, ci) then
							matchCount = matchCount + 1
						end
					end
					local similarity = matchCount / minLen
					print(string.format("  文本相似度: %.2f%%", similarity * 100))
					if similarity > 0.9 then
						print("  文本90%相似，已到列表底部，查找'新建'按钮...")
						local newBtn = ocr_start(108, 1794, 268, 1901, "新建")
						if newBtn then
							print("找到新建按钮: (" .. newBtn[1] .. ", " .. newBtn[2] .. ")")
							randomTap(newBtn[1], newBtn[2], 5, 5, "点击新建")
							sleep(2000)
							newTagClicked = true
						else
							print("未找到新建按钮")
						end
						break
					end
				end
			end

			prevOCRText = curOCRText

			-- 向下滑动
			print("  向下滑动...")
			swipe(500, 1400, 500, 600, 500)
			sleep(1500)
		end

		if newTagClicked then
			-- POST /api/tag_channel/send_to_device 发送标签名到设备
		local robot_code = config.robot_code or ""
		local channel_num = (_G.wechat_task_options and (_G.wechat_task_options.taskId or _G.wechat_task_options.channelNum)) or 1

			local http = require("socket.http")
			local ltn12 = require("ltn12")
			local send_device_url = config.tag_channel_send_to_device_url or "http://127.0.0.1:8095/api/tag_channel/send_to_device"
			local post_data = string.format('{"robot_code":"%s","channel_num":%s,"tag_name":"%s"}',
				tostring(robot_code), tostring(channel_num), tostring(tagName))

			print("调用发送标签接口: " .. send_device_url)
			print("参数: " .. post_data)

			local sendBody = {}
			local res, code = http.request{
				url = send_device_url,
				method = "POST",
				sink = ltn12.sink.table(sendBody),
				headers = {
					["Content-Type"] = "application/json",
					["Content-Length"] = tostring(#post_data),
				},
				source = ltn12.source.string(post_data),
			}
			if res and code == 200 then
				print("发送标签接口返回: " .. table.concat(sendBody))
			else
				print("发送标签到设备失败, HTTP: " .. tostring(code))
			end

			-- 3. 回到桌面 -> 打开ID -> 查找发消息位置 -> 复制最新一条 -> 回到ID列表
			print("步骤3：回到桌面 -> 打开ID复制消息")
			C.backToHomeWithCheck(3)
			sleep(1000)

			C.openIDOptimize()
			sleep(1500)
			if C.searchIDOptimize(config.id_ai_project_config and config.id_ai_project_config.name or "", false) then
				sleep(1500)

				-- 获取消息列表，复制最后一条（带重试）
				local msgs = nil
				for msgRetry = 1, 3 do
					msgs = C.getIDMessages()
					if msgs and #msgs > 0 then
						break
					end
					print("未获取到ID消息，重试第" .. msgRetry .. "次")
					if msgRetry < 3 then
						if C.searchIDOptimize(config.id_ai_project_config and config.id_ai_project_config.name or "", false) then
							sleep(1000)
						else
							print("重新进入对话失败，停止重试")
							break
						end
					end
				end

				if msgs and #msgs > 0 then
					print("获取到" .. #msgs .. "条ID消息")
					local lastMsg = msgs[#msgs]
					local msg_x = lastMsg.x + 200
					local msg_y = lastMsg.y + 60

					print("长按复制最新一条消息")
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

					if copySuccess then
						print("最新消息复制成功")
					else
						print("复制消息失败")
					end
				else
					print("未获取到ID消息")
				end

				-- 返回ID消息列表
				C.backToIDMessageList()
				sleep(500)
			else
				print("打开ID失败")
			end

			-- 4. 回到桌面 -> 切回微信（不检测微信状态，已在标签设置页面）
			print("步骤4：回到桌面 -> 切回微信")
			C.backToHomeWithCheck()
			sleep(500)
			randomTap(422, 1791, 10, 10, "打开微信")
			sleep(1500)

			-- 5. 先检测输入法是否打开，再查找"设置标签名称" -> 点击 -> 粘贴
			print("步骤5：查找设置标签名称位置并粘贴")
			-- 检测输入法是否打开（检测"换行"/"符号"）
			local imeOpen = false
			local imeNl = ocr_start(767, 1583, 961, 1900, "换行")
			local imeSign = ocr_start(89, 1646, 443, 1940, "符号")
			if imeNl or imeSign then
				imeOpen = true
				print("检测到输入法已打开")
			else
				print("未检测到输入法打开")
			end
			-- 用 box 识别 129,459,911,1920 范围，多个匹配时取最下方（y最大）
			local setNamePos = nil
			local setNameItems = ocr_start_with_boxes(129, 459, 911, 1920)
			if setNameItems then
				-- 坐标取整
				for _, item in ipairs(setNameItems) do
					item.x = math.floor(item.x or 0)
					item.y = math.floor(item.y or 0)
				end
				local candidates = {}
				for _, item in ipairs(setNameItems) do
					if item.words and string.find(item.words, "设置标签名称") then
						table.insert(candidates, item)
					end
				end
				if #candidates > 0 then
					-- 取最下方：y 坐标最大的
					setNamePos = candidates[1]
					for i = 2, #candidates do
						if candidates[i].y > setNamePos.y then
							setNamePos = candidates[i]
						end
					end
				end
			end
			if setNamePos then
				print("找到设置标签名称: (" .. setNamePos.x .. ", " .. setNamePos.y .. ")")
				randomTap(setNamePos.x, setNamePos.y, 10, 10, "点击设置标签名称")
				sleep(1500)

				-- 检测是否有"高情商回复"
				local smartReply = ocr_start(496, 1187, 925, 1354, "高情商回复")
				if smartReply then
					print("找到高情商回复: (" .. smartReply[1] .. ", " .. smartReply[2] .. ")")
					randomTap(smartReply[1] - 500, smartReply[2], 150, 5, "点击剪切板内容")
					sleep(1000)
				--	C.closeInputMethodIfNeeded()
					sleep(500)
				else
					-- 长按设置标签名称位置唤出粘贴
					print("未找到高情商回复，长按唤出粘贴...")
					longTap(setNamePos.x, setNamePos.y)
					sleep(1500)

					local pasteClicked = false
					for pasteRetry = 1, 3 do
						local pastePos = ocr_start(96, 630, 840, 921, "粘贴")
						if pastePos then
							print("找到粘贴按钮: (" .. pastePos[1] .. ", " .. pastePos[2] .. ")")
							randomTap(pastePos[1], pastePos[2], 5, 5, "点击粘贴")
							sleep(1000)
							pasteClicked = true
							break
						end
						print("未找到粘贴按钮，重试第" .. pasteRetry .. "次...")
						sleep(500)
					end

					if not pasteClicked then
						print("粘贴失败，未找到粘贴按钮")
					end

					--C.closeInputMethodIfNeeded()
					--sleep(500)
				end

				-- 6. 查找"确认"并点击
				print("步骤6：查找确认按钮并点击")
				sleep(2000)
				local confirmPos = ocr_start(150,836,891,1899, "确定")
				if confirmPos then
					print("找到确定按钮: (" .. confirmPos[1] .. ", " .. confirmPos[2] .. ")")
					randomTap(confirmPos[1], confirmPos[2], 5, 5, "点击确定")
					sleep(1000)
					print("标签创建确定完成")

					-- 步骤7：标签确认后，返回标签列表页，查找刚创建的标签名并点击
					print("步骤7：查找刚创建的标签名位置")
					sleep(1000)
					-- 步骤7：查找"添加"按钮 103,1754,326,1909
					print("步骤7：查找添加按钮")
					local addPos = nil
					for retry2 = 1, 3 do
						addPos = ocr_start(122,402,923,1887, "添加")
						if addPos then break end
						print("未找到添加按钮，重试第" .. retry2 .. "次...")
						sleep(800)
					end

					if addPos then
						print("找到添加按钮: (" .. addPos[1] .. ", " .. addPos[2] .. ")")
						randomTap(addPos[1], addPos[2], 10, 10, "点击添加")
						sleep(1500)
							-- 步骤9：滑动匹配user_list中的联系人，参考回访下拉选中模式
						print("步骤9：滑动匹配并选中联系人")
						local selectedContacts = M.selectContactsByDropDown(userList)
						if selectedContacts then
							for _, contactId in ipairs(selectedContacts) do
								table.insert(completedIds, contactId)
								print("  记录选中联系人ID: " .. tostring(contactId))
							end
							print("共选中 " .. #selectedContacts .. " 个联系人加入标签")

							-- 步骤10：查找底部"添加"按钮(632,1694,972,1922)并点击，带重试
							if #selectedContacts > 0 then
								print("步骤10：点击底部添加按钮完成操作")
								local bottomAddClicked = false
								for retry10 = 1, 5 do
									local bottomAddPos = ocr_start(632, 1694, 972, 1922, "添加")
									if bottomAddPos then
										print(string.format("找到底部添加: (%d, %d), 第%d次点击", bottomAddPos[1], bottomAddPos[2], retry10))
										randomTap(bottomAddPos[1], bottomAddPos[2], 10, 10, "点击底部添加")
										sleep(1500)

										-- 检测点击后是否还存在"添加"，存在则重试
										local stillAdd = ocr_start(632, 1694, 972, 1922, "添加")
										if not stillAdd then
											print("底部添加按钮已消失，点击成功")
											bottomAddClicked = true
											break
										else
											print("底部添加仍存在，第" .. retry10 .. "次重试...")
										end
									else
										print("未找到底部添加按钮，可能已完成，重试第" .. retry10 .. "次...")
										sleep(800)
									end
								end
								if not bottomAddClicked then
									print("底部添加按钮重试耗尽，继续流程")
								end
							end
						end
					else
						print("未找到添加按钮")
					end	
					-- 新标签创建流程已完成联系人选择，跳过后续的user_list逐个处理
					newTagCreated = true
				else
					print("未找到确认按钮")
				end
			else
				print("未找到设置标签名称位置")
			end
		end
	end

	-- 遍历user_list，逐个处理（新标签创建已在流程中完成用户选择则跳过）
	if not newTagCreated then
	for i, user in ipairs(userList) do
		local userName = tostring(user.msg or user.phone or user.id or "")
		local userId = user.id

		print(string.format("处理用户[%d/%d]: %s (user_id=%s)", i, #userList, userName, tostring(userId)))

		-- 在当前页面OCR查找该用户
		local found = false
		local maxScroll = math.ceil(#userList / 5) + 3  -- 估算需要滑动的次数

		for scroll = 1, maxScroll do
			print(string.format("  第%d次查找...", scroll))

			-- OCR识别当前页面
			local ocrItems = ocr_start_with_boxes(80, 300, 940, 1800)
			if ocrItems then
				-- 坐标取整
				for _, item in ipairs(ocrItems) do
					item.x = math.floor(item.x or 0)
					item.y = math.floor(item.y or 0)
				end
				for _, item in ipairs(ocrItems) do
					if item.words and type(item.words) == "string" then
						local cleanWords = string.gsub(item.words, "[%s%p]", "")
						local cleanName = string.gsub(userName, "[%s%p]", "")

						if string.find(item.words, userName) or
						   string.find(userName, item.words) or
						   string.find(cleanWords, cleanName) or
						   string.find(cleanName, cleanWords) then
							print("  找到用户: " .. item.words .. " 位置: (" .. item.x .. ", " .. item.y .. ")")
							randomTap(item.x, item.y, 10, 10, "点击进入用户详情: " .. userName)
							sleep(2000)

							-- 调用标签处理函数
							M.handleNewFriendTag(tagName)
							sleep(1000)

							table.insert(completedIds, userId)
							found = true

							-- 返回新的好友列表
							C.weChatBack()
							sleep(1000)
							break
						end
					end
				end
			end

			if found then break end

			-- 向下滑动
			swipe(500, 1500, 500, 600, 500)
			sleep(1500)
		end

		if not found then
			print(string.format("  未找到用户: %s", userName))
		end
	end
	end  -- if not newTagCreated

	-- 上报完成状态（无论是否有用户完成都调接口）
	if #completedIds > 0 then
		print(string.format("标签任务完成: 成功%d个用户, IDs=%s", #completedIds, table.concat(completedIds, ",")))
	else
		print("标签任务未完成任何用户")
	end
	M.updateTagTaskStatus(taskId, completedIds)

	-- ========== 流程完成，返回微信列表 ==========
	print("流程完成，尝试返回微信列表...")
	sleep(1000)

	-- 循环检测返回图片，存在则点击后继续检测，直到连续2次都未找到
	local backImgClicked = false
	local backGoneCount = 0
	for retryImg = 1, 10 do
		local backRet, backX, backY = findImage(106, 193, 218, 333, "wx_back_2.png|wx_detail_back.png", 0.9)
		if backRet ~= -1 then
			print(string.format("找到返回按钮图片: (%d, %d), 第%d次点击", backX, backY, retryImg))
			randomTap(backX, backY, 5, 5, "点击返回按钮")
			sleep(1500)
			backImgClicked = true
			backGoneCount = 0
			-- 不break，继续循环检测是否还存在返回图片
		else
			if backImgClicked then
				backGoneCount = backGoneCount + 1
				if backGoneCount >= 2 then
					print("返回按钮图片连续消失，返回完成")
					break
				else
					print("未找到返回图片，等待确认中(第" .. backGoneCount .. "次)...")
					sleep(800)
				end
			else
				print("未找到返回按钮图片，重试第" .. retryImg .. "次...")
				sleep(500)
			end
		end
	end
	if not backImgClicked then
		print("未找到返回按钮图片")
	end

	-- 验证是否回到微信列表：检测 300,204,797,320 区域
	print("验证是否回到微信列表...")
	local backToWxDone = false
	for retryBack = 1, 8 do
		local wxTitle = ocr_start(300, 204, 797, 320, "微信")
		if wxTitle then
			print("已回到微信列表，流程结束")
			backToWxDone = true
			break
		end

		-- 检测是否在通讯录页面
		local tongxun = ocr_start(300, 204, 797, 320, "通讯录")
		if tongxun then
			print("检测到通讯录页面，查找底部微信按钮")
			local wxPos = ocr_start(99, 1784, 387, 1939, "微信")
			if wxPos then
				print(string.format("找到微信: (%d, %d)", wxPos[1], wxPos[2]))
				randomTap(wxPos[1], wxPos[2], 5, 5, "点击微信回到列表")
				sleep(1500)

				-- 再次检测是否回到微信列表
				local wxTitle2 = ocr_start(300, 204, 797, 320, "微信")
				if wxTitle2 then
					print("已回到微信列表，流程结束")
					backToWxDone = true
					break
				else
					print("未回到微信列表，继续重试...")
				end
			else
				print("未找到微信按钮，重试第" .. retryBack .. "次...")
				sleep(800)
			end
		else
			print("未检测到微信/通讯录，重试第" .. retryBack .. "次...")
			sleep(800)
		end
	end
	if not backToWxDone then
		print("返回微信列表重试耗尽")
	end

	return string.format("成功处理%d/%d个用户", #completedIds, #userList)
end

-- 下拉滑动选中联系人（参考回访流程）
-- @param userList 用户列表，每个元素需含 msg/phone/id 字段
-- @return table 选中的用户ID列表
function M.selectContactsByDropDown(userList)
	if not userList or #userList == 0 then
		print("selectContactsByDropDown: 无联系人需要选中")
		return {}
	end

	local region = {x1 = 80, y1 = 300, x2 = 940, y2 = 1800}
	local maxSwipe = 50
	local swipeCount = 0
	local lastOcrContent = ""
	local selectedIds = {}

	-- ========== 模糊匹配相关函数（参考mass_send方案）==========
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

	-- 计算两个字符串的差异字符数（允许OCR误差）
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
	-- contact: 要匹配的联系人手机号
	-- 返回: 是否匹配, 匹配到的文本
	local function fuzzyMatchContact(ocrText, contact)
		if not ocrText or not contact then
			return false, nil
		end

		local contactLen = #contact
		local ocrLen = #ocrText

		-- 最小匹配长度
		local minMatchLen = math.max(3, math.ceil(contactLen * 0.6))

		-- 1. 精确匹配
		if string.find(ocrText, contact) then
			return true, contact
		end

		-- 2. 双向子串匹配
		local maxSubLen = math.min(contactLen, ocrLen)
		for subLen = maxSubLen, minMatchLen, -1 do
			for startIdx = 1, contactLen - subLen + 1 do
				local subContact = string.sub(contact, startIdx, startIdx + subLen - 1)
				if string.find(ocrText, subContact) then
					return true, subContact
				end
			end
		end

		for subLen = math.min(ocrLen, contactLen), minMatchLen, -1 do
			for startIdx = 1, ocrLen - subLen + 1 do
				local subOcr = string.sub(ocrText, startIdx, startIdx + subLen - 1)
				if string.find(contact, subOcr) then
					return true, subOcr
				end
			end
		end

		-- 3. 滑动窗口模糊匹配（允许25%差异）
		for i = 1, math.max(1, ocrLen - contactLen + 1) do
			local substr = string.sub(ocrText, i, i + contactLen - 1)
			local diffCount = calculateDiff(contact, substr)
			local maxDiff = math.max(1, math.floor(contactLen * 0.25))

			if diffCount <= maxDiff then
				return true, substr
			end
		end

		-- 4. 跳过中间字符匹配
		for skip = 1, 2 do
			local matched, matchText = matchWithSkip(ocrText, contact, skip)
			if matched then
				print("跳过中间" .. skip .. "个字符匹配成功")
				return true, matchText
			end
		end

		-- 5. 前缀匹配
		local prefixLen = math.min(5, contactLen)
		if prefixLen >= minMatchLen then
			local prefix = string.sub(contact, 1, prefixLen)
			if string.find(ocrText, prefix) then
				return true, prefix
			end
			for i = 1, math.max(1, ocrLen - prefixLen + 1) do
				local substr = string.sub(ocrText, i, i + prefixLen - 1)
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

	-- 从msg中提取手机号数字（仅匹配手机号）
	local function extractMatchTokens(msg)
		local t = {}
		if not msg or msg == "" then return t end
		local str = tostring(msg)
		local seen = {}
		for digits in string.gmatch(str, "%d+") do
			if #digits >= 7 and not seen[digits] then
				seen[digits] = true
				table.insert(t, digits)
			end
		end
		return t
	end

	-- 构建待匹配列表，每个用户存储多个匹配关键词
	local pendingList = {}  -- { {user, tokens}, ... }
	for _, user in ipairs(userList) do
		local msg = tostring(user.msg or user.phone or user.id or "")
		local tokens = extractMatchTokens(msg)
		table.insert(pendingList, {user = user, tokens = tokens})
	end

	print("[下拉选中] 待匹配联系人: " .. #userList .. " 个")
	for _, user in ipairs(userList) do
		print("  -> " .. tostring(user.msg or user.phone or user.id))
	end

	while swipeCount < maxSwipe do
		if swipeCount > 0 then
			sleep(1500)
		end

		local ocrResult = ocr_start_with_boxes(region.x1, region.y1, region.x2, region.y2)
		if not ocrResult then
			ocrResult = {}
		end

		-- 坐标取整
		for _, item in ipairs(ocrResult) do
			item.x = math.floor(item.x or 0)
			item.y = math.floor(item.y or 0)
		end

		local currentContent = ""
		for _, item in ipairs(ocrResult) do
			if item.words then
				currentContent = currentContent .. item.words
			end
		end

		-- 检测是否到底（连续2屏内容相似度>=95%）
		if swipeCount > 0 then
			local maxLen = math.max(#currentContent, #lastOcrContent)
			if maxLen > 0 then
				local diffCount = calculateDiff(lastOcrContent, currentContent)
				local sim = 1 - diffCount / maxLen
				if sim >= 0.95 then
					print(string.format("[下拉选中] 已滑到底部 (相似度: %.1f%%)", sim * 100))
					break
				end
			end
		end
		lastOcrContent = currentContent

		-- 打印当前屏OCR识别结果（调试用，输出前20条）
		print(string.format("[下拉选中] 第%d屏OCR内容(%d条):", swipeCount + 1, #ocrResult))
		local debugCount = 0
		for _, item in ipairs(ocrResult) do
			if item.words and debugCount < 20 then
				local digits = string.gsub(item.words, "%D", "")
				local flag = ""
				if #digits >= 7 then flag = " <--数字" end
				print(string.format("  [%d] %s | (x:%d, y:%d)%s", debugCount + 1, item.words, item.x, item.y, flag))
				debugCount = debugCount + 1
			end
		end

		-- 匹配当前屏幕中的联系人
		for _, item in ipairs(ocrResult) do
			if item.words and type(item.words) == "string" and #item.words >= 2 then
				for i = #pendingList, 1, -1 do
					local pu = pendingList[i]
					local user = pu.user
					local userName = tostring(user.msg or user.phone or user.id or "")

					for _, token in ipairs(pu.tokens) do
						local matched, matchText = fuzzyMatchContact(item.words, token)
						if matched then
							print(string.format("[下拉选中] 匹配: %s (x:%d, y:%d) phone=%s match=%s", userName, item.x, item.y, token, matchText or ""))
							randomTap(item.x, item.y, 20, 10, "选中联系人: " .. userName)
							sleep(800)
							table.insert(selectedIds, user.id)
							table.remove(pendingList, i)
							break
						end
					end
				end
			end
		end

		-- 检查是否全部完成
		local remaining = 0
		for _ in pairs(pendingList) do
			remaining = remaining + 1
		end
		if remaining == 0 then
			print("[下拉选中] 所有联系人均已选中，共: " .. #selectedIds)
			break
		end

		-- 向下滑动
		local swipeY1 = 1500 + math.random(-50, 50)
		local swipeY2 = 600 + math.random(-30, 30)
		swipe(500, swipeY1, 500, swipeY2, 500)
		swipeCount = swipeCount + 1
		print(string.format("[下拉选中] 滑动第%d次，剩余: %d 个", swipeCount, remaining))
	end

	-- 打印未匹配的联系人
	local unmatched = {}
	for _, user in pairs(pendingList) do
		table.insert(unmatched, tostring(user.msg or user.phone or user.id))
	end
	if #unmatched > 0 then
		print("[下拉选中] 未匹配的联系人(" .. #unmatched .. "个): " .. table.concat(unmatched, ", "))
	end

	return selectedIds
end

return M
