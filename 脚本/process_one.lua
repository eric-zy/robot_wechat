local M = {}

-- 单个被控执行入口
function M.run(params)
    local options = {
        taskId = params.taskId or 0,
        taskName = params.taskName or "未知任务",
        tapPoint = params.tapPoint or {x = 0, y = 0, name = "未知位置"},
        timeout = params.timeout or 1000,
        enableLog = params.enableLog or false,
        payState = params.payState,
        addressState = params.addressState,
        enabledFunctions = params.enabledFunctions
    }

    -- 设置全局配置（优先使用传入参数，否则从现有全局配置获取）
    _G.wechat_task_options = _G.wechat_task_options or {}
    _G.wechat_task_options.taskId = options.taskId
    _G.wechat_task_options.channelNum = options.taskId
    if options.payState then
        _G.wechat_task_options.payState = options.payState
    end
    if options.addressState ~= nil then
        _G.wechat_task_options.addressState = options.addressState
    end
    if options.enabledFunctions then
        _G.wechat_task_options.enabledFunctions = options.enabledFunctions
    end

    -- 从全局配置获取启用的功能
    local enabledFunctions = _G.wechat_task_options and _G.wechat_task_options.enabledFunctions
        or {ADD_FRIEND = true, CHAT = true, MASS_SEND = true}

    -- 日志输出函数
    local function writelog(message)
        if options.enableLog then
            local logContent = string.format("[ProcessOne-%d] %s", options.taskId, message)
            print(logContent)
            uploadLog(logContent)
        end
    end

    -- 获取当前脚本所在目录
    local function getScriptDir()
        local info = debug.getinfo(1, "S")
        local scriptPath = info.source:sub(2)  -- 去掉开头的@符号
        return scriptPath:match("(.*/)") or "./"
    end

    local scriptDir = getScriptDir()

    writelog(string.format("开始执行任务：%s，点击位置：%s", options.taskName, options.tapPoint.name))

    -- 打印启用的功能
    writelog("启用的功能:")
    for funcCode, enabled in pairs(enabledFunctions) do
        writelog(string.format("  %s: %s", funcCode, tostring(enabled)))
    end

    -- 使用绝对路径加载同一目录下的文件
    local mainPath = scriptDir .. "main.lua"

    -- 1. 查找微信并打开（带异常捕获与重试）
    local maxMainRetry = 3
    local mainOk = false
    for i = 1, maxMainRetry do
        local success, err = pcall(dofile, mainPath)
        if success then
            mainOk = true
            break
        else
            writelog(string.format("第%d次执行 main.lua 失败: %s", i, tostring(err)))
            sleep(1000)
        end
    end

    if not mainOk then
        writelog("多次执行 main.lua 仍然失败，放弃本次任务")
        return {
            success = false,
            taskId = options.taskId,
            message = "main.lua 执行失败"
        }
    end

    writelog("main.lua 执行完成")

    -- 2. 根据启用的功能执行对应模块
    local common = require("common")
    local config = require("config")
    local mass = require("mass_send")
    local initFavor = require("init_favor")

    -- ADD_FRIEND 加好友流程
    if enabledFunctions.ADD_FRIEND then
        writelog("执行加好友流程(ADD_FRIEND)")
        local ok, result = pcall(common.addWXFriendOptimize)
        if not ok then
            writelog("加好友流程执行异常: " .. tostring(result))
        else
            writelog("加好友流程执行完成")
        end
    else
        writelog("加好友流程(ADD_FRIEND)未启用，跳过")
    end

    -- 初始化微信收藏同步（聊天开始前执行，不判断功能开关）
    writelog("执行初始化微信收藏同步(initFavor)")
    local okFavor, favorErr = pcall(initFavor.initFavor, config.robot_code, options.taskId)
    if not okFavor then
        writelog("initFavor 执行异常: " .. tostring(favorErr))
    else
        writelog("initFavor 执行完成")
    end

    -- CHAT 聊天流程
	if enabledFunctions.CHAT then
        writelog("执行聊天流程(CHAT)")
        local wechat_msg_ok, wechat_msg = pcall(require, "get_wechat_msg_v2")
        if not wechat_msg_ok or not wechat_msg or type(wechat_msg.startFindMsg) ~= "function" then
            writelog("加载 get_wechat_msg_v2 失败或接口不存在")
        else
            writelog("开始调用 startFindMsg 处理消息")

            local ok, result = pcall(wechat_msg.startFindMsg, {
                taskId = options.taskId,
                taskName = options.taskName,
                tapPoint = options.tapPoint,
                timeout = options.timeout,
                enableLog = options.enableLog,
                callback = function(res)
                    writelog(string.format("startFindMsg 回调：处理了 %d 条消息", res.processedCount or 0))
                end
            })

            if not ok then
                writelog("startFindMsg 执行异常: " .. tostring(result))
            else
                writelog("聊天流程执行完成")
            end
        end
    else
        writelog("聊天流程(CHAT)未启用，跳过")
    end

    -- MASS_SEND 群发流程
    if enabledFunctions.MASS_SEND then
        writelog("执行主动唤醒群发流程(MASS_SEND)")
        local ok, result = pcall(mass.runMassSendTask, {
            robot_code = config.robot_code,
            channel_num = options.taskId,
            msg_type = 2
        })
        if not ok then
            writelog("群发流程执行异常: " .. tostring(result))
        else
            writelog("群发流程执行完成")
        end

        -- 回访流程：仅当 pay_state=2(未支付) 且 address_state=0(未留地址) 时触发
        local payState = options.payState or _G.wechat_task_options.payState or 1
        local addressState = options.addressState
        if addressState == nil then
            addressState = _G.wechat_task_options.addressState
        end
        if payState == 2 and addressState == 0 then
            writelog(string.format("通道 %d 满足回访条件 (pay_state=%d, address_state=%d)，执回访流程(MASS_SEND)", options.taskId, payState, addressState))
            local ok2, result2 = pcall(mass.runMassSendTask, {
                robot_code = config.robot_code,
                channel_num = options.taskId,
                msg_type = 1
            })
            if not ok2 then
                writelog("回访流程执行异常: " .. tostring(result2))
            else
                writelog("回访流程执行完成")
            end
        else
            writelog(string.format("通道 %d 不满足回访条件 (pay_state=%d, address_state=%d)，跳过回访流程", options.taskId, payState, addressState or "nil"))
        end
    else
        writelog("群发流程(MASS_SEND)未启用，跳过")
    end

    -- TAG_TASK 标签任务流程
   -- if enabledFunctions.TAG_TASK then
        writelog("执行标签任务流程(TAG_TASK)")
        local robot_code = config.robot_code
        local channel_num = options.taskId

        -- 读取标签任务
        writelog("读取标签任务: robot_code=" .. robot_code .. ", channel_num=" .. tostring(channel_num))
        local tagTask = common.readTagTask(robot_code, channel_num)
        if tagTask then
            writelog(string.format("获取到标签任务: task_id=%s, tag_name=%s, 用户数量=%s",
                tostring(tagTask.task_id), tostring(tagTask.target_tag_name), tostring(tagTask.total_count)))

            -- 执行标签任务流程（后续实现具体逻辑）
            local tag_ok, tag_result = pcall(common.executeTagTask, tagTask)
            if not tag_ok then
                writelog("标签任务流程执行异常: " .. tostring(tag_result))
            else
                writelog("标签任务流程执行完成: " .. tostring(tag_result))
            end
        else
            writelog("无待执行标签任务")
        end
    --else
      --  writelog("标签任务流程(TAG_TASK)未启用，跳过")
    --end

    -- MOMENTS_TASK 朋友圈任务流程
   -- if enabledFunctions.MOMENTS_TASK then
        writelog("执行朋友圈任务流程(MOMENTS_TASK)")

        writelog("朋友圈任务: robot_code=" .. robot_code .. ", channel_num=" .. tostring(channel_num))
        local moments_ok, moments_result = pcall(common.runMomentsTask, robot_code, channel_num)
        if not moments_ok then
            writelog("朋友圈任务流程执行异常: " .. tostring(moments_result))
        else
            writelog("朋友圈任务流程执行完成: " .. tostring(moments_result))
        end
    --else
    --    writelog("朋友圈任务流程(MOMENTS_TASK)未启用，跳过")
    --end

    return {
        success = true,
        taskId = options.taskId,
        message = "任务执行成功"
    }
end

return M