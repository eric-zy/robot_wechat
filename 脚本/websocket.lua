-- websocket.lua
local config = require("config")

local wsHandle = nil
local WS_URL = nil
local reConnectTimer = nil
local messageQueue = {}  -- 服务器主动发送的任务队列
local replyCache = {}    -- 存储带ID消息的回复（key:消息ID, value:回复内容）
local queueLock = false
local replyLock = false
local nextMsgId = 1      -- 消息ID生成器（自增）
local reconnectCount = 0          -- 当前重连次数
local MAX_RECONNECT_MS = 60000    -- 最大重连间隔 60秒
local BASE_RECONNECT_MS = 3000    -- 基础重连间隔 3秒

-- 日志打印（toast 缩小放最下方，避免遮挡屏幕干扰图像识别）
local function wLog(text)
    local logStr = "[" .. os.date("%H:%M:%S") .. "] [WebSocket] " .. text
    print(logStr)
    toast(logStr, 5, 1880, 8)
end

-- 安全操作队列
local function pushMessageToQueue(message)
    while queueLock do sleep(10) end
    queueLock = true
    table.insert(messageQueue, message)
    queueLock = false
end

local function popMessageFromQueue()
    while queueLock do sleep(10) end
    queueLock = true
    local msg = table.remove(messageQueue, 1)
    queueLock = false
    return msg
end

-- 安全操作回复缓存
local function setReply(msgId, reply)
    while replyLock do sleep(10) end
    replyLock = true
    replyCache[msgId] = reply
    replyLock = false
end

local function getReply(msgId)
    while replyLock do sleep(10) end
    replyLock = true
    local reply = replyCache[msgId]
    replyCache[msgId] = nil  -- 取出后删除缓存
    replyLock = false
    return reply
end

-- 内部接收消息回调（区分普通任务和带ID的回复）
function internalOnRecv(handle, message)
    wLog("收到消息：" .. message)

    local ok, msgData = pcall(jsonLib.decode, message)
    if not ok or not msgData then
        wLog("JSON解析失败：" .. tostring(msgData))
        pushMessageToQueue(message)
        return
    end

    -- 只有当消息明确是 reply 类型且有 msgId 时才缓存为回复
    local msgType = msgData.type or ""
    local msgId = msgData.msgId

    if msgType == "reply" and msgId then
        setReply(tonumber(msgId), message)
        wLog("已缓存回复（ID:" .. msgId .. "）")
    else
        -- 普通消息放入任务队列
        pushMessageToQueue(message)
    end
end

-- 重连逻辑（指数退避 + 次数限制 + 连接成功回调）
local function reConnect(onSuccess)
    -- 防止重复创建重连定时器
    if reConnectTimer then
        return
    end
    if not WS_URL then
        wLog("重连失败: WS_URL 未设置")
        return
    end

    reconnectCount = reconnectCount + 1
    -- 指数退避: 3s → 6s → 12s → 24s → 48s → 60s(max)
    local delay = math.min(BASE_RECONNECT_MS * (2 ^ (reconnectCount - 1)), MAX_RECONNECT_MS)
    wLog(string.format("第%d次重连，%d秒后尝试...", reconnectCount, delay // 1000))

    reConnectTimer = setTimer(function()
        reConnectTimer = nil
        local res = startWebSocket(WS_URL, internalOnOpened, internalOnClosed, internalOnError, internalOnRecv)
        print(string.format("重连结果: %s, handle=%s", tostring(res), tostring(res)))
        if res then
            -- 连接成功立即重置计数器
            -- 注意：wsHandle 的赋值在 internalOnOpened 中完成
            wLog("重连连接请求成功，等待 onOpened 回调...")
            if onSuccess then
                onSuccess()
            end
        else
            wLog("重连连接请求失败")
        end
    end, delay)
end

-- 其他内部回调
function internalOnOpened(handle)
    wsHandle = handle
    reconnectCount = 0  -- 连接成功，重置重连计数
    wLog("连接成功（句柄：" .. handle .. "），reset重连计数")
    -- 发送初始化消息
    if config.ws_init_msg then
        local ok, initMsg = pcall(function() return jsonLib.encode(config.ws_init_msg) end)
        if not ok then
            wLog("JSON编码失败：" .. tostring(initMsg))
            return
        end
        wLog("准备发送初始化消息：" .. tostring(initMsg))
        local success = sendWebSocket(wsHandle, initMsg)
        if success then
            wLog("已发送初始化消息：" .. initMsg)
        else
            wLog("初始化消息发送失败")
        end
    else
        wLog("未配置ws_init_msg")
    end
end

function internalOnClosed(handle)
    wLog("连接已关闭")
    wsHandle = nil
    reConnect()
end

function internalOnError(handle, err)
    wLog("连接错误：" .. err)
    wsHandle = nil
    reConnect()
end

-- 模块对外接口
local WebSocket = {
    init = function(url)
        if not url then
            wLog("服务器地址不能为空")
            return false
        end
        WS_URL = url
        print("初始化websocket连接参数：", WS_URL, internalOnOpened, internalOnClosed, internalOnError, internalOnRecv)
        local handle = startWebSocket(WS_URL, internalOnOpened, internalOnClosed, internalOnError, internalOnRecv)
        if not handle then
            wLog("初始化失败，即将重试")
            reConnect()
            return false
        end
        return true
    end,

    -- 发送普通消息（用于服务器任务的响应，无需等待回复）
    send = function(text)
        print("text:", text)
        if not wsHandle then
            wLog("未连接服务器，发送失败 → 触发重连")
            reConnect()
            return false
        end
        local success = sendWebSocket(wsHandle, text)
        if success then
            wLog("发送消息：" .. text)
        else
            wLog("发送失败，可能连接已断开")
            wsHandle = nil
            reConnect()
        end
        return success
    end,

    -- 发送带ID的消息（用于常规任务，需要等待回复）
    -- 返回：消息ID（用于获取回复）
    sendWithReply = function(text)
        if not wsHandle then
            wLog("未连接服务器，发送失败 → 触发重连")
            reConnect()
            return nil
        end
        local msgId = nextMsgId
        nextMsgId = nextMsgId + 1
        text["msgId"] = msgId
        local success = sendWebSocket(wsHandle, jsonLib.encode(text))
        if success then
            wLog("发送带回复消息（ID:" .. msgId .. "）：" .. jsonLib.encode(text))
            return msgId
        else
            wLog("带回复消息发送失败，可能连接已断开")
            wsHandle = nil
            reConnect()
            return nil
        end
    end,

    -- 等待带ID消息的回复（超时返回nil）
    waitReply = function(msgId, timeout)
        timeout = timeout or 5000
        local start = os.clock() * 1000
        while true do
            local reply = getReply(msgId)
            if reply then
                return reply
            end
            if os.clock() * 1000 - start > timeout then
                wLog("等待回复超时（ID:" .. msgId .. "）")
                return nil
            end
            sleep(100)
        end
    end,

    -- 获取服务器主动发送的任务消息
    getTaskMessage = function()
        return popMessageFromQueue()
    end,

    isConnected = function()
        return wsHandle ~= nil
    end,

    close = function()
        if wsHandle then
            closeWebSocket(wsHandle)
            wsHandle = nil
            wLog("已关闭连接")
        end
    end,
    
    reConnect = function(url)
        -- 允许传入新 url 覆盖旧地址
        if url then
            WS_URL = url
        end
        reconnectCount = 0  -- 外部手动触发重连，重置计数
        reConnect()
    end
}

return WebSocket
