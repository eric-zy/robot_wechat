-- 引入公共函数
require("utils")

-- OCR识别
require("ocr_fusion")

-- common
local common = require("common")

local config = require("config")

local requrest = require("requests")

local mass = require("mass_send")

local moments = require("moments_task")

-- 主动干预话术模块
local manual = require("manual")

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

-- 打开多控助手并进入相机模式
if config.server.require_control then
    require("open_controller")
    sleep(100)
end

	--local resA = ocr_start(656,930,936,1917, "发送")
	--print("发送", resA)
	--common.handleNewFriendRemark()
	--exitScript()
	

-- 群发模块 (暂时注释，mass_send.lua 不存在)
 --local mass = require("mass_send")
 --local ok, result = pcall(mass.massSendFlow, {
        --    robot_code = config.robot_code,
      --      channel_num = 1,
    --        msg_type = 2
  --      })

--print(ok,result)
--exitScript()





-- 单被控任务模块
local processOne = require("process_one")


--common.handleReminder({robot_code = 'HF-AT-1-001',channel_num = _G.wechat_task_options and _G.wechat_task_options.taskId or 1})

--local ocr_result = ocr_start_with_boxes(97,247,938,1808)
--print(ocr_result)

--common.initChat_send(config.robot_code,1)	
--common.initChat_send_by_file_helper(config.robot_code,1)  -- 已移至加好友流程之后执行


	
--common.handleCollectForward("保价协议")
--exitScript()
-- 全局任务配置（与 threads_mate_20 保持一致风格）

--common.sendAddress("蚌埠市蚌山区涂山东路淮河文化广场蚌埠会展中心")




-- 11.5 根据文字位置动态识别上一条消息的位置（排除刚发送的自身消息）
-- 11.5 用OCR文字块最右坐标查找最后一条文字消息，长按唤醒"收藏"菜单
    




 -- 查找"搜索地点"并点击(唤醒输入法)
	-- 请求发送消息到ID 接口将resource_name发送到发消息


--local initFavor = require("init_favor")
--local okFavor, favorErr = pcall(initFavor.initFavor, config.robot_code, 1)

--if not okFavor then
--   print("初始化收藏失败:", favorErr)
--end

--exitScript()


-- local moments_ok, moments_result = pcall(common.runMomentsTask, config.robot_code, 1)
-- if not moments_ok then
--         print("朋友圈任务流程执行异常: " .. tostring(moments_result))
-- else
--         print("朋友圈任务流程执行完成: " .. tostring(moments_result))
-- end




local M = {_VERSION = 0.1}

-- 引用（由外部传入或直接 require）



-- 初始化依赖

_G.wechat_task_options = {
    taskId = 1
}

local var = {
    exit = true,
    data = 0,
    lock = false  -- 线程锁（目前主循环顺序执行，这里仅保留占位，方便以后扩展）
}

-- 获取机器人通道状态
local function fetchRobotChannels()
    local robotCode = config.robot_code
    local url = config.robot_conf_url.."?robotCode=" .. robotCode

    print("获取机器人通道状态:", url)
    local res = getHttp(url)

    if res == false then
        print("获取机器人状态失败")
        return nil
    end

    local resJson = jsonLib.decode(res)
    if resJson and resJson.success and resJson.data and resJson.data.channels then
        print("获取到通道数量:", resJson.data.channels_count)
        -- 返回完整数据，包括channels和pay_state
        return {
            channels = resJson.data.channels,
            payState = resJson.data.pay_state or 1  -- 默认已支付
        }
    end

    return nil
end

-- 获取指定通道的payState
local function getChannelPayState(channelsData, channelNum)
    if not channelsData or not channelsData.channels then
        return 1  -- 默认已支付
    end

    for _, channel in ipairs(channelsData.channels) do
        local channelNumInData = tonumber(channel.channel_num)
        if channelNumInData == tonumber(channelNum) then
            -- 优先取通道级别的pay_state，没有则取全局的
            local payState = channel.pay_state or channelsData.payState or 1
            print("通道", channelNum, "payState:", payState)
            return tonumber(payState)
        end
    end

    return channelsData.payState or 1  -- 默认已支付
end

-- 获取指定通道的address_state（0=未留地址，1=已留地址，2=无需地址）
local function getChannelAddressState(channelsData, channelNum)
    if not channelsData or not channelsData.channels then
        return nil
    end

    for _, channel in ipairs(channelsData.channels) do
        local channelNumInData = tonumber(channel.channel_num)
        if channelNumInData == tonumber(channelNum) then
            local addressState = tonumber(channel.address_state)
            print("通道", channelNum, "address_state:", addressState or "nil")
            return addressState
        end
    end

    return nil
end

-- 获取指定通道启用的功能列表
-- 返回: {ADD_FRIEND=true, CHAT=true, MASS_SEND=true} 或 nil
local function getChannelFunctions(channelsData, channelNum)
    if not channelsData or not channelsData.channels then
        print("channels为空，返回默认功能")
        return {ADD_FRIEND = true, CHAT = true, MASS_SEND = true}
    end

    for _, channel in ipairs(channelsData.channels) do
        local channelNumInData = tonumber(channel.channel_num)
        if channelNumInData == tonumber(channelNum) then
            local enabledFunctions = {}
            if channel.functions and #channel.functions > 0 then
                for _, func in ipairs(channel.functions) do
                    if tonumber(func.function_status) == 1 then
                        enabledFunctions[func.function_code] = true
                        print(string.format("通道%d启用功能: %s (%s)", channelNum, func.function_code, func.function_name))
                    end
                end
            end
            return enabledFunctions
        end
    end

    return {ADD_FRIEND = true, CHAT = true, MASS_SEND = true}  -- 默认全部启用
end

-- 检查指定通道是否启用
local function isChannelEnabled(channelsData, channelNum)
    if not channelsData or not channelsData.channels then
        print("channels为空，默认启用通道", channelNum)
        return true  -- 无法获取状态时默认启用
    end

    local channels = channelsData.channels

    -- 调试：打印所有通道信息
    print("开始检查通道", channelNum, "channels长度:", #channels)
    for i, ch in ipairs(channels) do
        print(string.format("  channels[%d]: channel_num=%s (type=%s), status=%s (type=%s)",
            i, tostring(ch.channel_num), type(ch.channel_num), tostring(ch.status), type(ch.status)))
    end

    for _, channel in ipairs(channels) do
        -- 确保比较时类型一致
        local channelNumInData = tonumber(channel.channel_num)
        local targetNum = tonumber(channelNum)

        if channelNumInData == targetNum then
            -- 确保转为数字比较，兼容字符串 "0"/"1" 或整数 0/1
            local statusValue = tonumber(channel.status)
            local isEnabled = statusValue == 1
            print(string.format("匹配成功！通道 %d 状态: %s (status=%s)",
                channelNum,
                isEnabled and "启用" or "禁用",
                tostring(channel.status)))
            return isEnabled
        end
    end

    print("未找到匹配通道", channelNum, "，跳过")
    return false  -- 未找到对应通道时跳过（不再默认启用）
end

-- 获取指定通道的channel_wechat_id（从channelsData中查找）
local function getChannelWechatId(channelsData, channelNum)
    if not channelsData or not channelsData.channels then
        return nil
    end
    for _, channel in ipairs(channelsData.channels) do
        if tonumber(channel.channel_num) == tonumber(channelNum) then
            local id = channel.channel_wechat_id
            -- 去除首尾空格，后端可能返回 " " 作为空值
            if id and type(id) == "string" then
                id = string.match(id, "^%s*(.-)%s*$")
            else
                id = nil
            end
            return id
        end
    end
    return nil
end

-- 初始化时检测并更新微信号（channel_wechat_id为空时执行）
-- @param channelsData 通道数据
-- @param channelNum 通道编号
local function syncWechatIdIfNeeded(channelsData, channelNum)
    local wechatId = getChannelWechatId(channelsData, channelNum)

    -- 已有微信号则跳过
    if wechatId and wechatId ~= "" then
        print(string.format("通道%d已有微信号: %s，跳过", channelNum, wechatId))
        return
    end

    print(string.format("通道%d微信号为空，开始获取...", channelNum))

    -- 1. 打开微信并确认在列表 → 点击"我"
    common.changeToWXWithCheck()
    sleep(500)
    local meTab = nil
    for _ = 1, 3 do
        meTab = ocr_start(660, 1780, 933, 1934, "我")
        if meTab then
            randomTap(meTab[1], meTab[2] - 10, 10, 10, "点击'我'")
            break
        end
        randomTap(860, 1786, 10, 10, "点击'我'(默认位置)")
        sleep(800)
    end

    -- 2. 等待2s，box OCR识别 (293,307,901,517) 区域
    sleep(2000)
    local textBlocks = ocr_start_with_boxes(293, 307, 901, 517)
    if not textBlocks or #textBlocks == 0 then
        print("syncWechatId: OCR未识别到任何文字块")
        randomTap(150, 1870, 10, 10, "点击微信返回列表")
        sleep(500)
        return
    end

    -- 3. 查找"微信号："并截取后面的字符
    local extractedId = nil
    for _, block in ipairs(textBlocks) do
        local words = block.words or ""
        print(string.format("syncWechatId: OCR识别到: '%s'", words))
        -- 匹配"微信号："或"微信号:"后的内容
        local wxid = string.match(words, "微信号[:：]%s*(.+)")
        if wxid and wxid ~= "" then
            extractedId = wxid
            break
        end
        -- 也可以是"微信号"和微信号分别在两个block中
        if extractedId then
            break
        end
    end

    -- 如果"微信号："后没有内容，尝试取下一个block
    if not extractedId then
        for i, block in ipairs(textBlocks) do
            local words = block.words or ""
            if string.find(words, "微信号") then
                -- 下一个block可能就是微信号
                if i < #textBlocks then
                    local nextWords = textBlocks[i + 1].words or ""
                    -- 过滤掉纯数字/字母组合的微信号（不含中文）
                    if nextWords ~= "" and not string.find(nextWords, "[^\128-\191]") then
                        extractedId = nextWords
                    else
                        extractedId = nextWords
                    end
                    break
                end
            end
        end
    end

    -- 过滤特殊字符，只保留有效微信号（字母数字下划线连字符）
    if extractedId then
        extractedId = string.match(extractedId, "[a-zA-Z0-9_][a-zA-Z0-9_-]*")
    end

    -- 4. 调用更新接口
    if extractedId and extractedId ~= "" then
        print(string.format("syncWechatId: 获取到微信号=%s，更新接口", extractedId))
        local url = config.update_wechat_id_url
            .. "?robot_code=" .. urlEncode(config.robot_code)
            .. "&channel_num=" .. tostring(channelNum)
            .. "&channel_wechat_id=" .. urlEncode(extractedId)
        print("调用更新微信号接口: " .. url)
        local http = require("socket.http")
        local ltn12 = require("ltn12")
        local response_body = {}
        local res, code = http.request{
            url = url,
            method = "POST",
            sink = ltn12.sink.table(response_body),
        }
        if res and code == 200 then
            print("syncWechatId: 微信号更新成功")
        else
            print("syncWechatId: 微信号更新失败, HTTP状态码: " .. tostring(code))
        end
    else
        print("syncWechatId: 未能提取微信号")
    end

    -- 6. 点击左下方"微信"回到列表
    randomTap(150, 1870, 10, 10, "点击微信返回列表")
    sleep(500)
end

-- 单个任务执行逻辑：1 控 N 的 "被控" 执行入口
local function executeTask(taskId, payState, addressState, enabledFunctions)
    _G.wechat_task_options = {
        taskId = taskId,
        channelNum = taskId,  -- 通道编号
        payState = payState or 1,  -- 默认已支付
        addressState = addressState,  -- 地址状态
        enabledFunctions = enabledFunctions or {ADD_FRIEND = true, CHAT = true, MASS_SEND = true}
    }
    local taskName = "任务" .. taskId
    local point = config.main_control_config.tapPoints[taskId]

    uploadLog(taskName, "开始执行")

    -- 打印启用的功能
    print("通道", taskId, "启用的功能:")
    for funcCode, enabled in pairs(_G.wechat_task_options.enabledFunctions) do
        print("  " .. funcCode .. ": " .. tostring(enabled))
    end

    -- 调试输出
    local repeatStr = string.rep(tostring(taskId), 10 + taskId * 2)
    print(repeatStr)
    sleep(800)

    -- 轻点一次桌面，保证当前画面稳定
    randomTap(515, 1935, 5, 5, "点击桌面")

    -- 如果找不到对应点位，直接返回
    if not point or not point.x or not point.y then
        uploadLog(taskName, "未找到对应 tapPoint，跳过")
        return
    end

    -- 点击对应的被控入口
    randomTap(point.x, point.y, 20, 50, point.name or ("主控" .. taskId))
    sleep(800)

    -- 调用被控流程，带异常捕获
    local ok, result = pcall(processOne.run, {
        taskId = taskId,
        taskName = taskName,
        tapPoint = point,
        timeout = 100000,
        enableLog = true,
        payState = payState or 1,
        addressState = addressState
    })

    if not ok then
        uploadLog(taskName, "执行异常: " .. tostring(result))
    elseif type(result) == "table" and result.success == false then
        uploadLog(taskName, "执行结果失败: " .. tostring(result.message or "unknown"))
    else
        uploadLog(taskName, "执行完成")
    end

    -- 主动干预话术：聊天检测前拉取并执行干预任务
    uploadLog(taskName, "检查主动干预任务")
    pcall(function()
        manual.runManualIntervention(config.robot_code, taskId)
    end)
    sleep(1000)

    -- 加好友流程完成后，检查是否启用聊天功能并执行
    if enabledFunctions and enabledFunctions.CHAT then
        uploadLog(taskName, "执行聊天消息发送流程")
       -- local chatResult = common.initChat_send_by_file_helper(config.robot_code, taskId)
        --if chatResult then
          --  uploadLog(taskName, "聊天消息发送完成")
       -- else
         --   uploadLog(taskName, "聊天消息发送失败或无待发送数据")
        --end
        sleep(1000)
    end

    -- 任务执行完后返回主控界面
    uploadLog(taskName, "返回主控界面")
    randomTap(515, 1935, 5, 5, "点击桌面返回主控")
    sleep(500)
end

-- 主循环：按配置的 tapPoints 顺序轮询执行，默认 1 控 5
local function main()
    toast("Alarm 主控脚本启动", 0, 0, 12)
    print("Alarm 主控脚本启动")

    -- 脚本启动时先切回任务1
    local firstPoint = config.main_control_config.tapPoints[1]
    if firstPoint then
        randomTap(515, 1935, 5, 5, "点击桌面")
        sleep(500)
        randomTap(firstPoint.x, firstPoint.y, 20, 50, "启动时切换到主控1")
        sleep(800)
        randomTap(515, 1935, 5, 5, "返回主控界面")
        print("已切换到主控1，准备开始任务")
    end

    local countdown = config.main_control_config.countdownTime or 10
    print("初始 countdown 值:", countdown)
    print("cycle_state:", tostring(config.main_control_config.cycle_state))

    while config.main_control_config.cycle_state do
        local ok, loopErr = pcall(function()
            uploadLog("主线程", string.format("倒计时【%d】秒后结束", countdown))
            toast(string.format("倒计时【%d】秒后结束", countdown))

            -- 每次循环开始前获取机器人通道状态
            local channelsData = fetchRobotChannels()
            local channels = channelsData and channelsData.channels

            -- 从channels数组中找到第一个status=1的channel_num
            local firstEnabledTaskId = nil
        if channels and #channels > 0 then
            for _, channel in ipairs(channels) do
                local statusValue = tonumber(channel.status)
                print(string.format("通道 %s status=%s", tostring(channel.channel_num), tostring(channel.status)))
                if statusValue == 1 then
                    firstEnabledTaskId = tonumber(channel.channel_num)
                    print("从接口获取第一个可用通道 channel_num:", firstEnabledTaskId)
                    break
                end
            end
        end

        -- 如果没有可用通道，等待后继续下一轮
        if not firstEnabledTaskId then
            print("所有通道均禁用，等待后重试")
            uploadLog("主线程", "没有可用通道，等待后重试")
            sleep(2000)
        else
            -- 根据channels长度决定执行的通道数量
            local channelCount = channels and #channels or 0
            print("channels长度:", channelCount, "将从通道", firstEnabledTaskId, "开始执行")

            -- 从第一个可用通道开始执行
            for i = 0, channelCount - 1 do
                local taskId = ((firstEnabledTaskId - 1 + i) % channelCount) + 1
                -- 检查通道状态，如果 status=0 则跳过
                if not isChannelEnabled(channelsData, taskId) then
                    uploadLog("任务" .. taskId, "通道已禁用，跳过执行")
                else
                    -- 获取通道的payState和启用的功能
                    local payState = getChannelPayState(channelsData, taskId)
                    local addressState = getChannelAddressState(channelsData, taskId)
                    local enabledFunctions = getChannelFunctions(channelsData, taskId)

                    -- 切换到对应通道子控，检测并同步微信号
                    local point = config.main_control_config.tapPoints[taskId]
                    if point then
                        randomTap(point.x, point.y, 20, 50, "切换到通道" .. taskId)
                        sleep(800)
                        syncWechatIdIfNeeded(channelsData, taskId)
                        -- 返回主控界面（syncWechatIdIfNeeded 结束时在微信列表）
                        randomTap(515, 1935, 5, 5, "返回主控")
                        sleep(500)
                    end

                    -- 触发提醒流程：pay_state=2(未支付) 且 address_state=0(未留地址)
                    if payState == 2 and addressState == 0 then
                        print(string.format("通道 %d 满足提醒条件 (pay_state=%d, address_state=%d)，触发reminder流程", taskId, payState, addressState))
                        uploadLog("任务" .. taskId, "触发reminder提醒流程")
                        sleep(1000)
                        common.handleReminder({
                            robot_code = config.robot_code,
                            channel_num = taskId
                        })
                        sleep(1000)
                    end

                    sleep(1000)
                    executeTask(taskId, payState, addressState, enabledFunctions)
                end
            end
        end

            -- countdown 仅用于日志显示，不控制循环退出
            countdown = countdown - 1
            if countdown <= 0 then
                countdown = config.main_control_config.countdownTime or 10  -- 重置倒计时
            end
            print("循环结束，countdown 重置为:", countdown)
        end) -- pcall end

        if not ok then
            print("主循环异常: " .. tostring(loopErr))
            uploadLog("主线程", "主循环异常: " .. tostring(loopErr))
        end

        sleep(config.main_control_config.loopInterval or 1000)
    end

    uploadLog("主线程", "所有任务已结束")
    toast("所有任务已结束", 0, 0, 20)
end

-- 运行主函数
main()