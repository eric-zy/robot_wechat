local R = {_VERSION=0.1}
local config = require("config")

-- 转换函数：将表转为 key=value&key=value 格式
function tableToQueryString(t)
    local parts = {}  -- 用于存储每个 key=value 部分
    for k, v in pairs(t) do
        -- 将键和值拼接为 "key=value" 格式，添加到数组中
        table.insert(parts, tostring(k) .. "=" .. tostring(v))
    end
    -- 用 & 符号连接所有部分
    return table.concat(parts, "&")
end

-- 网络请求Post（使用JSON格式，带Content-Type头）
local function postHttp(url, params)
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    local json_str = jsonLib.encode(params)
    local response_body = {}
    local res, code = http.request{
        url = url,
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Content-Length"] = #json_str
        },
        source = ltn12.source.string(json_str),
        sink = ltn12.sink.table(response_body),
    }
    if res and code == 200 then
        return table.concat(response_body)
    end
    print("请求失败, HTTP状态码: " .. tostring(code))
    return false
end

-- 返回状态
function R.upstate(url, data)
	if data == "" then
	    -- 测试内容
		data = {
			name = "yufei",
			ask = "消息测试内容",
			project = 1
		}
	end

	-- 增加机器编号
	data.machine_code = config.current_machine_code
	-- 增加robotCode和channelNum
	data.robotCode = config.robot_code
	data.channelNum = _G.wechat_task_options and _G.wechat_task_options.channelNum or 1

	print("请求url:", url)
		print("请求data:", data)
	print("等待请求结果：")
	toast("已发送请求，等待结果中...")
	
	local res = postHttp(url, data)
	if res ~= false then
		local res_json = jsonLib.decode(res)
		print(res_json)
		return res_json
	else
	print("--接口返回数据异常，稍后再试--")
		sleep(800)
		return false
	end
end

-- 加票接口
-- @param phone 手机号
-- @param robot_code 机器人编号
-- @param channel_num 渠道编号
-- @param pay_state 支付状态，默认1
function R.ticketAdd(phone, robot_code, channel_num, pay_state,is_vip)
    pay_state = pay_state or 1
    is_vip = is_vip or 1
    local data = {
        pay_state = pay_state,
        phone = phone,
        robot_code = robot_code,
        channel_num = channel_num,
        is_vip = is_vip
    }
    
    print("调用加票接口:", config.ticket_add_url, data)
    
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    local post_data = jsonLib.encode(data)
    
    local response_body = {}
    local res, code = http.request{
        url = config.ticket_add_url,
        sink = ltn12.sink.table(response_body),
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Content-Length"] = #post_data
        },
        source = ltn12.source.string(post_data),
    }
    
    if res and code == 200 then
        local response_text = table.concat(response_body)
        print("加票接口返回:", response_text)
        local result = jsonLib.decode(response_text)
        return result
    else
        print("加票接口请求失败，错误码:", code)
        return false
    end
end

-- 获取待同步到微信收藏的资源文件数据
-- @param robot_code 机器人编号
-- @param channel_num 通道号
-- @return table {success, data: {resources: [{id, file_name, file_url, ...}]}} 或 false
function R.getPendingSync(robot_code, channel_num)
    local url = config.pending_sync_url .. "?robot_code=" .. tostring(robot_code) .. "&channel_num=" .. tostring(channel_num)
    print("获取待同步资源, url:", url)
    
    local res, code = httpGet(url)
    if code ~= 200 or not res then
        print("获取待同步资源失败, code:", code)
        return false
    end
    
    local ok, decoded = pcall(jsonLib.decode, res)
    if not ok or not decoded then
        print("获取待同步资源解析失败")
        return false
    end
    
    return decoded
end

-- 发送待处理收藏信息到ID
-- @param resource_channel_id 通道资源ID
-- @return table {success, data: {im_id, resource_channel_id, resource_id, resource_name, resource_type, resource_type_text, results: [{content, result, seq, type}], ...}} 或 false
function R.sendResource(resource_channel_id)
    local url = config.resource_send_url .. "?resource_channel_id=" .. tostring(resource_channel_id)
    print("发送待处理收藏信息到ID, url:", url)
    
    local res, code = httpGet(url)
    if code ~= 200 or not res then
        print("发送待处理收藏信息失败, code:", code)
        return false
    end
    
    local ok, decoded = pcall(jsonLib.decode, res)
    if not ok or not decoded then
        print("发送待处理收藏信息解析失败")
        return false
    end
    
    print("发送待处理收藏信息返回:", jsonLib.encode(decoded))
    return decoded
end

-- 更新通道资源收藏状态
-- @param robot_code 机器人编号
-- @param channel_num 通道号
-- @param resource_ids 已同步的资源ID列表 (table)
-- @return table {success} 或 false
function R.updateSyncStatus(robot_code, channel_num, resource_ids)
    local data = {
        robot_code = robot_code,
        channel_num = channel_num,
        resource_ids = resource_ids
    }
    
    local json_str = jsonLib.encode(data)
    print("更新资源同步状态, url:", config.update_sync_status_url, "data:", json_str)
    
    local ret, code = httpPost(config.update_sync_status_url, json_str)
    if code ~= 200 then
        print("更新资源同步状态失败, code:", code)
        return false
    end
    
    local ok, decoded = pcall(jsonLib.decode, ret)
    if not ok or not decoded then
        print("更新资源同步状态解析失败")
        return false
    end
    
    return decoded
end

return R