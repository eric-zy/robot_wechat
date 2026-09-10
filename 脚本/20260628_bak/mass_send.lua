-- mass_send.lua
-- 群发助手模块

-- 引入公共函数
local common = require("common")

-- 引入配置
local global_config = require("config")

-- ========== 状态更新函数 ==========

-- 更新提醒消息状态
-- @param uid 用户UID（可以是单个uid或多个用逗号分隔的uid字符串）
-- @return success 是否成功, response 服务器响应
local function updateReminderMessageStatus(uid)
    if not uid or uid == "" then
        print("更新状态失败: uid不能为空")
        return false, nil
    end
    
    local api_base_url = global_config and global_config.api_base_url or "http://127.0.0.1:8095"
    local update_url = api_base_url .. "/api/reminder/update"
    
    print("调用更新状态接口: " .. update_url)
    print("更新uid: " .. tostring(uid))
    
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    
    -- 构建POST数据：多个uid用逗号分隔
    local uid_str = tostring(uid)
    local post_data = '{"uid": "' .. uid_str .. '"}'
    
    local response_body = {}
    local res, code, response_headers = http.request{
        url = update_url,
        method = "POST",
        sink = ltn12.sink.table(response_body),
        headers = {
            ["Content-Type"] = "application/json",
            ["Content-Length"] = tostring(#post_data),
        },
        source = ltn12.source.string(post_data),
    }
    
    if not res or code ~= 200 then
        print("更新状态失败, HTTP状态码: " .. tostring(code))
        return false, nil
    end
    
    local body = table.concat(response_body)
    print("更新状态接口返回: " .. body)
    
    local ok, decoded = pcall(jsonLib.decode, body)
    if not ok then
        print("解析更新状态响应失败")
        return false, body
    end
    
    return decoded.success or false, body
end

-- 更新群发记录状态（msg_type=2 使用）
-- @param robot_code 机器人编号
-- @param channel_num 通道编号
-- @param send_status 发送状态（默认1成功）
-- @param record_ids 选中的记录ID列表（可选）
-- @return success 是否成功, response 服务器响应
local function updateMassSendRecordStatus(robot_code, channel_num, send_status, record_ids)
    send_status = send_status or 1
    
    local api_base_url = global_config and global_config.api_base_url or "http://127.0.0.1:8095"
    local update_url = api_base_url .. "/api/mass_send/update_record_status"
    
    -- 构建查询参数
    if record_ids and #record_ids > 0 then
        local record_ids_str = table.concat(record_ids, ",")
        update_url = update_url .. "?record_ids=" .. record_ids_str
        print("更新方式: 按记录ID, IDs=" .. record_ids_str)
    else
        update_url = update_url .. string.format("?robot_code=%s&channel_num=%s&send_status=%s",
            robot_code, tostring(channel_num), tostring(send_status))
        print("更新方式: 按通道, robot_code=" .. tostring(robot_code) .. ", channel_num=" .. tostring(channel_num) .. ", send_status=" .. tostring(send_status))
    end
    
    print("调用更新群发记录状态接口: " .. update_url)
    
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    
    local response_body = {}
    local res, code = http.request{
        url = update_url,
        method = "GET",
        sink = ltn12.sink.table(response_body),
    }
    
    if not res or code ~= 200 then
        print("更新群发记录状态失败, HTTP状态码: " .. tostring(code))
        return false, nil
    end
    
    local body = table.concat(response_body)
    print("更新群发记录状态接口返回: " .. body)
    
    return true, body
end

-- ========== URL编码函数 ==========
local function urlEncode(s)
    if not s then return "" end
    s = tostring(s)
    -- 只在独立换行符\n前加\r（不在\r\n的\n前重复添加）
    s = string.gsub(s, "([^\r])\n", "%1\r\n")
    -- 编码特殊字符
    s = string.gsub(s, "([^%w%-%_%.%~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    return s
end

-- ========== 配置获取函数 ==========

-- 群发类型配置
-- type: 接口类型
-- api_path: 接口路径（相对于api_base_url）
-- response_field: 联系人列表在响应数据中的字段路径
-- field_mapping: 字段映射表（将接口返回的字段映射为标准联系人名称）
local MASS_SEND_TYPE_CONFIG = {
    [1] = {  -- 回访接口
        name = "回访",
        api_path = "/api/reminder/next",
        params = "?robot_code=%s&channel_num=%s",
        response_field = "data.contacts",  -- 支持点分隔的嵌套路径
    },
    [2] = {  -- 群发助手记录接口
        name = "群发记录",
        api_path = "/api/mass_send/records/by_channel",
        params = "?robotCode=%s&channelNum=%s",
        response_field = "data.records",
        use_msg_field = true,  -- 标记：消息内容从 records 的 msg 字段获取
    },
}

-- 获取robot_code和channel_num
local function getRobotChannelConfig()
    local robot_code = _G and _G.robot_code or ""
    local channel_num = (_G.wechat_task_options and (_G.wechat_task_options.taskId or _G.wechat_task_options.channelNum)) or 1
    return robot_code, channel_num
end

-- 获取嵌套字段值（支持点分隔的路径如 "data.contacts"）
local function getNestedValue(data, path)
    if not data or not path then return nil end
    local parts = {}
    for part in string.gmatch(path, "[^.]+") do
        table.insert(parts, part)
    end
    local result = data
    for _, part in ipairs(parts) do
        if type(result) ~= "table" then return nil end
        result = result[part]
    end
    return result
end

-- 根据robot_code和channel_num获取待群发联系人列表
-- @param robot_code 机器人编号
-- @param channel_num 通道编号
-- @param msg_type 消息类型（默认1）
-- @return contacts 联系人列表, message_content 消息内容, success 是否成功, task_type 任务类型, task_data 完整任务数据
local function getMassSendContacts(robot_code, channel_num, msg_type)
    msg_type = msg_type or 1
    
    if not robot_code or robot_code == "" then
        print("错误: robot_code不能为空")
        return {}, "", false, nil, nil
    end
    
    -- 获取类型配置
    local typeConfig = MASS_SEND_TYPE_CONFIG[msg_type]
    if not typeConfig then
        print("错误: 未知的msg_type: " .. tostring(msg_type))
        return {}, "", false, nil, nil
    end
    
    print("获取群发联系人列表, robot_code=" .. robot_code .. ", channel_num=" .. tostring(channel_num) .. ", msg_type=" .. tostring(msg_type) .. "(" .. typeConfig.name .. ")")
    
    local api_base_url = global_config and global_config.api_base_url or "http://127.0.0.1:8095"
    local url = api_base_url .. typeConfig.api_path .. string.format(typeConfig.params, robot_code, tostring(channel_num))
    
    print("请求URL: " .. url)
    
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    
    local response_body = {}
    local res, code, response_headers = http.request{
        url = url,
        method = "GET",
        sink = ltn12.sink.table(response_body),
        protocol = "http",
    }
    
    if not res or code ~= 200 then
        print("获取联系人列表失败, HTTP状态码: " .. tostring(code))
        return {}, "", false, nil, nil
    end
    
    local body = table.concat(response_body)
    print("响应内容: " .. body)
    
    local ok, decoded = pcall(jsonLib.decode, body)
    if not ok or not decoded or not decoded.success then
        print("解析响应失败或接口返回错误")
        return {}, "", false, nil, nil
    end

    -- 提取任务元数据（type、template_contents 等），用于路由判断
    local task_type = decoded.data and decoded.data.type
    local task_data = decoded.data  -- 完整任务数据
    if task_type then
        print(string.format("任务类型 type=%d (%s)", task_type, decoded.data.type_text or "未知"))
    end
    
    -- 提取联系人列表：从 steps[].users 中提取所有用户
    local contacts = {}
    local message_content = ""
    
    -- msg_type = 2 时使用 records 接口，数据结构不同
    if msg_type == 2 then
        local records = decoded.data and decoded.data.records
        if records and type(records) == "table" and #records > 0 then
            print("获取到 records 数量: " .. #records)
            for _, record in ipairs(records) do
                -- 每个 record 的 msg 字段是消息内容，取第一个有内容的
                if record.msg and record.msg ~= "" and message_content == "" then
                    message_content = tostring(record.msg)
                    print("获取到消息内容: " .. message_content)
                end
                -- 将 record 转换为联系人格式，phone 作为 uid
                if record.phone then
                    table.insert(contacts, {
                        uid = tostring(record.phone),
                        phone = tostring(record.phone),
                        msg = record.msg or "",
                        id = record.id,
                        send_status = record.send_status
                    })
                end
            end
        else
            print("警告: 未找到 records 字段或为空")
        end
    else
        -- 回访接口：steps 在根层级 decoded.steps（data 字段为空）
        local stepsData = nil
        if decoded.data and decoded.data.steps then
            stepsData = decoded.data.steps
            print("stepsData 来源: decoded.data.steps")
        elseif decoded.steps then
            stepsData = decoded.steps
            print("stepsData 来源: decoded.steps")
        else
            print("警告: 未找到 steps 字段，响应结构: " .. jsonLib.encode(decoded))
        end
        
        if stepsData and type(stepsData) == "table" then
            print("调试: stepsData 长度=" .. #stepsData .. ", type=" .. type(stepsData[1]))
            
            -- 提取消息内容：根据 steps_type 获取对应的 step 的 message
            -- steps_type="1,3" 表示消息在最后一个 step 中（如 step=3）
            -- 或者直接获取最后一个 step 的 message（群发通常是最后一步）
            if #stepsData > 0 then
                local targetStep = stepsData[#stepsData]  -- 获取最后一个 step
                if targetStep and targetStep.message then
                    message_content = targetStep.message
                    print("获取到消息内容（最后一个step）: " .. message_content)
                end
            end
            
            -- 如果最后一个 step 没有 message，尝试获取第一个 step
            if message_content == "" and stepsData[1] and stepsData[1].message then
                message_content = stepsData[1].message
                print("获取到消息内容（第一个step）: " .. message_content)
            end
            
            if message_content == "" then
                print("警告: 未能获取到消息内容，stepsData[1].message=" .. tostring(stepsData[1] and stepsData[1].message))
            end
            
            for _, step in ipairs(stepsData) do
                if step.users and type(step.users) == "table" then
                    for _, user in ipairs(step.users) do
                        table.insert(contacts, user)
                    end
                end
            end
        end
        
        -- 兼容 data.contacts 结构
        if #contacts == 0 then
            local rawContacts = getNestedValue(decoded, typeConfig.response_field)
            if rawContacts and type(rawContacts) == "table" then
                for _, contact in ipairs(rawContacts) do
                    table.insert(contacts, contact)
                end
            elseif decoded.data and type(decoded.data) == "table" and #decoded.data > 0 then
                for _, contact in ipairs(decoded.data) do
                    table.insert(contacts, contact)
                end
            end
        end
    end
    
    print("获取到联系人数量: " .. #contacts)
    return contacts, message_content, true, task_type, task_data
end

-- ========== UI操作函数 ==========

-- 点击"新建群发"
-- 完整流程: 微信列表 -> 我 -> 设置 -> 其他功能 -> 辅助功能 -> 群发助手 -> 开始群发 -> 新建群发
-- 返回: true 成功, false 失败
local function clickNewMassSend()
    -- ========== 步骤1: 确保在微信列表页 ==========
    print("步骤1: 确保在微信列表页")
    for i = 1, 3 do
        local inWxList = ocr_start(374, 224, 678, 292, "微信")
        if inWxList then
            print("已在微信列表页")
            break
        end
        local backIndex, backX, backY = findPicEx(99, 211, 187, 292, "wx_back.png", 0.9)
        if backIndex ~= -1 then
            randomTap(backX + 12, backY + 20, 3, 5, "点击返回按钮")
        else
            randomTap(125, 252, 3, 5, "点击固定位置返回")
        end
        sleep(800)
    end
    -- 若不在微信，尝试打开微信
    common.changeToWX()
    sleep(1000)

    -- ========== 步骤2: 点击"我" ==========
    print("步骤2: 点击'我'")
    local meSuccess = false
    for i = 1, 5 do
        local mePos = ocr_start(766,1835,895,1924, "我")
        if mePos then
            randomTap(mePos[1], mePos[2], 20, 5, "点击'我'(OCR)")
            sleep(1000)
        else
            print("OCR未找到'我'，使用固定位置")
            randomTap(821,1856, 10, 5, "点击'我'(固定位置)")
            sleep(1000)
        end
        local servicePos = ocr_start(119, 601, 515, 891, "服务")
        local collectPos = ocr_start(119, 601, 515, 891, "收藏")
        local momentsPos = ocr_start(119, 300, 515, 600, "朋友圈")
        if servicePos or collectPos or momentsPos then
            print("已成功进入'我'页面")
            meSuccess = true
            break
        end
        sleep(500)
    end
    if not meSuccess then
        print("点击'我'失败")
        return false
    end

    -- ========== 步骤3: 点击"设置" ==========
    print("步骤3: 点击'设置'")
    local settingsSuccess = false
    for i = 1, 3 do
        local settingPos = ocr_start(64, 1198, 580, 1552, "设置")
        if settingPos then
            randomTap(settingPos[1], settingPos[2], 20, 5, "点击'设置'")
            sleep(1500)
            local hasAccount = ocr_start(295,215,711,325, "设置")
            if hasAccount then
                print("已成功进入设置页面")
                settingsSuccess = true
                break
            end
        end
        sleep(500)
    end
    if not settingsSuccess then
        print("点击'设置'失败")
        return false
    end

    -- ========== 步骤4: 优先找"其他功能"，找不到则走"通用"路径 ==========
    print("步骤4: 查找设置入口")
    local auxSuccess = false

    -- 先尝试找"其他功能"（最多3次滑动）
    local otherFound = false
    for swipeCount = 0, 2 do
        sleep(1000)
        local otherPos = ocr_start(76, 466, 529, 1885, "其他功能")
        if otherPos then
            randomTap(otherPos[1], otherPos[2], 20, 5, "点击'其他功能'")
            sleep(2500)
            local checkPos = ocr_start(76, 466, 529, 1885, "其他功能")
            if not checkPos then
                print("已成功进入其他功能页面")
                otherFound = true
                break
            end
        else
            swipe(500, 1500, 500, 1300, 500)
            print("未找到'其他功能'，向下滑动 第" .. swipeCount .. "次")
            sleep(800)
        end
    end

    if otherFound then
        -- 找到"其他功能"，直接找"辅助功能"（无需滑动）
        print("步骤5: 点击'辅助功能'")
        for i = 1, 3 do
            local auxPos = ocr_start(68, 298, 647, 1651, "辅助功能")
            if auxPos then
                randomTap(auxPos[1], auxPos[2], 20, 5, "点击'辅助功能'")
                sleep(1500)
                local checkPos = ocr_start(248, 220, 779, 317, "辅助功能")
                print("检测是否进入辅助功能", checkPos)
                if checkPos then
                    print("已成功进入辅助功能页面")
                    auxSuccess = true
                    break
                end
            end
            sleep(500)
        end
    else
        -- 没有"其他功能"，走"通用"路径
        print("未找到'其他功能'，切换到'通用'路径")

        -- 步骤4a: 点击"通用"
        local generalSuccess = false
        for swipeCount = 0, 10 do
            sleep(1000)
            local generalPos = ocr_start(68, 298, 647, 1651, "通用")
            if generalPos then
                randomTap(generalPos[1], generalPos[2], 20, 5, "点击'通用'")
                sleep(1000)
                local checkPos = ocr_start(68, 298, 647, 1651, "通用")
                if not checkPos then
                    print("已成功进入通用页面")
                    generalSuccess = true
                    break
                end
            else
                swipe(500, 1500, 500, 1300, 500)
                print("未找到'通用'，向下滑动 第" .. swipeCount .. "次")
                sleep(800)
            end
        end
        if not generalSuccess then
            print("查找'通用'失败")
            return false
        end

        -- 步骤4b: 在通用页面找"辅助功能"（滑动查找）
        print("步骤5: 点击'辅助功能'")
        for swipeCount = 0, 10 do
            sleep(1000)
            local auxPos = ocr_start(68, 298, 647, 1651, "辅助功能")
            if auxPos then
                randomTap(auxPos[1], auxPos[2], 20, 5, "点击'辅助功能'")
                sleep(1500)
                local checkPos = ocr_start(248, 220, 779, 317, "辅助功能")
                print("检测是否进入辅助功能", checkPos)
                if checkPos then
                    print("已成功进入辅助功能页面")
                    auxSuccess = true
                    break
                end
            else
                swipe(500, 1500, 500, 1300, 500)
                print("未找到'辅助功能'，向下滑动 第" .. swipeCount .. "次")
                sleep(800)
            end
        end
    end

    if not auxSuccess then
        print("点击'辅助功能'失败")
        return false
    end

    -- ========== 步骤6: 点击"群发助手" ==========
    print("步骤6: 点击'群发助手'")
    local helperSuccess = false
    for i = 1, 3 do
        local helperPos = ocr_start(135, 421, 580, 1290, "群发助手")
        if helperPos then
            randomTap(helperPos[1], helperPos[2], 20, 5, "点击'群发助手'")
            sleep(1000)
            local checkPos = ocr_start(135, 421, 580, 1290, "群发助手")
            if not checkPos then
                print("已成功进入群发助手页面")
                helperSuccess = true
                break
            end
        end
        sleep(500)
    end
    if not helperSuccess then
        print("点击'群发助手'失败")
        return false
    end

    -- ========== 步骤7: 点击"开始群发" ==========
    print("步骤7: 点击'开始群发'")
    local startSuccess = false
    for i = 1, 3 do
        local startPos = ocr_start(68, 690, 735, 998, "开始群发")
        if startPos then
            randomTap(startPos[1], startPos[2], 20, 10, "点击'开始群发'")
            sleep(1000)
            local checkPos = ocr_start(68, 690, 735, 998, "开始群发")
            if not checkPos then
                print("已成功点击开始群发")
                startSuccess = true
                break
            end
        end
        sleep(500)
    end
    if not startSuccess then
        print("点击'开始群发'失败")
        return false
    end

    -- ========== 步骤8: 点击"新建群发" ==========
    print("步骤8: 点击'新建群发'")
    local newSuccess = false
    for i = 1, 3 do
        local newPos = ocr_start(261, 1763, 824, 1886, "新建群发")
        if newPos then
            randomTap(newPos[1], newPos[2], 20, 10, "点击'新建群发'")
            sleep(2000)
            local checkPos = ocr_start(261, 1763, 824, 1886, "新建群发")
            if not checkPos then
                print("已成功点击新建群发")
                newSuccess = true
                break
            end
        end
        sleep(500)
    end
    if not newSuccess then
        print("点击'新建群发'失败")
        return false
    end

    return true
end

-- 点击"选中"按钮
-- 返回: true 成功, false 失败
local function clickSelectButton()
    print("步骤: 点击'选中'按钮")
    local maxRetry = 3
    for i = 1, maxRetry do
        local selectPos = ocr_start(680, 1753, 960, 1879, "选中")
        if selectPos then
            randomTap(selectPos[1], selectPos[2], 20, 10, "点击'选中'")
            sleep(1500)
            -- 验证是否跳转
            local checkPos = ocr_start(680, 1753, 960, 1879, "选中")
            if not checkPos then
                print("已成功点击选中按钮（按钮已消失）")
                return true
            else
                print("'选中'仍存在，重新点击")
            end
            sleep(500)
        else
            if i > 1 then
                -- 首次点击后按钮消失，说明已成功跳转
                print("'选中'已消失，视为点击成功")
                return true
            end
            print("未找到'选中'，重试")
            sleep(500)
        end
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
-- contact: 要匹配的联系人名称
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

-- 滑动查找并选中匹配的联系人
-- userdata: 联系人列表(tables数组)
-- 返回: matchedContacts, success
local function selectContactsFromList(userdata)
    print("步骤: 滑动查找并选中联系人")
    if not userdata or #userdata == 0 then
        print("无联系人需要选中")
        return {}, false
    end
    
    local region = {x1 = 300, y1 = 405, x2 = 902, y2 = 1714}
    local maxSwipeRetry = 100
    local swipeCount = 0
    local lastOcrContent = ""
    local selectedCount = 0
    local matchedCount = 0
    
    -- 打印待匹配的联系人列表
    print("[待匹配列表] 共 " .. #userdata .. " 个联系人:")
    for i, contact in ipairs(userdata) do
        local name = contact
        if type(contact) == "table" then
            name = contact.msg or contact.name or contact.nickname or contact.nick_name or contact.title or contact.phone or contact.uid or tostring(contact)
        end
        print("  [" .. i .. "] " .. tostring(name))
    end
    
    -- 创建联系人查找集合（用名称作为key，避免表作为key的问题）
    local pendingContacts = {}
    local contactNameToOriginal = {}  -- 名称到原始contact的映射
    for i, contact in ipairs(userdata) do
        local contactName = contact
        if type(contact) == "table" then
            contactName = contact.msg or contact.name or contact.nickname or contact.nick_name or contact.title or contact.phone or contact.uid or tostring(contact)
        end
        contactName = tostring(contactName)
        -- 用清理后的名称作为key
        local cleanName = string.gsub(contactName, "[%s%p]", "")
        pendingContacts[cleanName] = contact  -- 存储原始contact对象
        contactNameToOriginal[cleanName] = contactName
    end
    
    local matchedContacts = {}
    
    while swipeCount < maxSwipeRetry do
        if swipeCount > 0 then
            sleep(2000)
        end
        
        -- 使用 ocr_start_with_boxes 返回带坐标的结果列表
        local ocrResult = ocr_start_with_boxes(region.x1, region.y1, region.x2, region.y2)
        if not ocrResult then
            ocrResult = {}
        end
        
        -- 转换坐标为整型
        for _, item in ipairs(ocrResult) do
            item.x = math.floor(item.x or 0)
            item.y = math.floor(item.y or 0)
            -- 确保 words 是字符串
            if item.words and type(item.words) ~= "string" then
                item.words = tostring(item.words)
            end
        end
        
        -- 打印每个OCR box
        local currentContent = ""
        print("OCR识别到 " .. #ocrResult .. " 个文字块:")
        for i, item in ipairs(ocrResult) do
            if item.words then
                print("  [Box#" .. i .. "] " .. item.words .. " (x:" .. item.x .. ", y:" .. item.y .. ")")
                currentContent = currentContent .. item.words
            end
        end
        
        if currentContent == lastOcrContent and swipeCount > 0 then
            print("已滑动到底部，OCR内容未变化")
            break
        end
        lastOcrContent = currentContent
        
        -- 遍历每个OCR box进行匹配
        for _, item in ipairs(ocrResult) do
            if item.words and type(item.words) == "string" then
                local boxText = item.words
                local boxMatched = false  -- 当前box是否已匹配
                
                -- 清理boxText：去除空格、换行符等
                local cleanBoxText = string.gsub(boxText, "[%s%p]", "")
                
                -- 第一步：精确匹配 - 在待匹配列表中查找包含boxText的联系人
                for cleanName, contact in pairs(pendingContacts) do
                    local contactName = contactNameToOriginal[cleanName] or tostring(contact)
                    -- 清理contactName
                    local cleanContactName = cleanName
                    
                    -- 标准精确匹配（先用清理后的文本匹配，避免特殊字符导致 pattern 报错）
                    if string.find(cleanBoxText, cleanContactName) or string.find(cleanContactName, cleanBoxText) then
                        matchedCount = matchedCount + 1
                        print("找到匹配联系人[" .. matchedCount .. "]: " .. contactName .. " (x:" .. item.x .. ", y:" .. item.y .. ")")
                        
                        sleep(500)
                        randomTap(item.x, item.y, 20, 10, "选中联系人: " .. contactName)
                        sleep(1000)
                        selectedCount = selectedCount + 1
                        -- 立即从待匹配列表中删除
                        pendingContacts[cleanName] = nil
                        contactNameToOriginal[cleanName] = nil
                        table.insert(matchedContacts, contact)
                        boxMatched = true
                        break
                    end
                    
                    -- 手机号特殊匹配：如果都是纯数字11位，直接比较
                    local boxDigits = string.gsub(boxText, "%D", "")
                    local contactDigits = string.gsub(contactName, "%D", "")
                    if #boxDigits == 11 and #contactDigits == 11 and boxDigits == contactDigits then
                        matchedCount = matchedCount + 1
                        print("找到匹配联系人[手机号][" .. matchedCount .. "]: " .. contactName .. " (x:" .. item.x .. ", y:" .. item.y .. ")")
                        
                        sleep(500)
                        randomTap(item.x, item.y, 20, 10, "选中联系人(手机号): " .. contactName)
                        sleep(1000)
                        selectedCount = selectedCount + 1
                        -- 立即从待匹配列表中删除
                        pendingContacts[cleanName] = nil
                        contactNameToOriginal[cleanName] = nil
                        table.insert(matchedContacts, contact)
                        boxMatched = true
                        break
                    end
                end
                
                -- 第二步：模糊匹配 - 只针对OCR识别错误（如两个号码合并）的情况
                if not boxMatched then
                    local boxLen = #boxText
                    -- 只对18位以上的文本进行模糊匹配（可能是合并的11位手机号）
                    if boxLen >= 18 then
                        for cleanName, contact in pairs(pendingContacts) do
                            local contactName = contactNameToOriginal[cleanName] or tostring(contact)
                            local contactLen = #contactName
                            
                            -- 只处理11位手机号
                            if contactLen == 11 then
                                local boxDigits = string.gsub(boxText, "%D", "")
                                
                                -- 检查是否包含这个11位手机号
                                if string.find(boxDigits, contactName) then
                                    matchedCount = matchedCount + 1
                                    print("找到模糊匹配联系人[" .. matchedCount .. "]: " .. contactName .. " (x:" .. item.x .. ", y:" .. item.y .. ") 来源: " .. boxText)
                                    
                                    sleep(500)
                                    randomTap(item.x, item.y, 20, 10, "选中联系人(模糊): " .. contactName)
                                    sleep(1000)
                                    selectedCount = selectedCount + 1
                                    -- 立即从待匹配列表中删除
                                    pendingContacts[cleanName] = nil
                                    contactNameToOriginal[cleanName] = nil
                                    table.insert(matchedContacts, contact)
                                    boxMatched = true
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
        
        -- 检查剩余待匹配数量
        local remaining = 0
        for _ in pairs(pendingContacts) do
            remaining = remaining + 1
        end
        
        if remaining == 0 then
            print("所有联系人均已选中，共选中: " .. selectedCount)
            return matchedContacts, true
        end
        
        -- 向下滑动（向上增加300px，避免勾选的数据被重新识别到）
        local swipeY1 = 1250 + math.random(-50, 50)
        local swipeY2 = 500 + math.random(-30, 30)
        swipe(500, swipeY1, 500, swipeY2, 700)
        swipeCount = swipeCount + 1
        print("向下滑动查找联系人 第" .. swipeCount .. "次，剩余: " .. remaining .. "个")
    end
    
    -- 打印未匹配的联系人
    local unmatchedList = {}
    for cleanName, _ in pairs(pendingContacts) do
        table.insert(unmatchedList, contactNameToOriginal[cleanName] or cleanName)
    end
    if #unmatchedList > 0 then
        print("未匹配到的联系人(" .. #unmatchedList .. "个): " .. table.concat(unmatchedList, ", "))
    end
    
    print("联系人选择完成，共选中: " .. selectedCount .. "个")
    return matchedContacts, selectedCount > 0
end

-- ========== 发送消息流程函数 ==========

-- 通过ID发送消息并通过文件传输助手转发
-- @param robot_code 机器人编号
-- @param channel_num 通道编号
-- @param msg_type 消息类型（默认1）
-- @param contacts 联系人列表
-- @param message_content 消息内容（从 getMassSendContacts 获取）
-- @return success 是否成功
local function sendViaFileHelperAndForward(robot_code, channel_num, msg_type, contacts, message_content)
    print("========== 开始发送消息流程 ==========")
    print("消息内容: " .. tostring(message_content))
    
    -- 调用 /api/send_msg_to_id 接口发送消息
    local send_url = global_config.send_msg_to_id_url .. "?robotCode=" .. robot_code .. "&channelNum=" .. tostring(channel_num) .. "&msg=" .. urlEncode(message_content or "")
    print("请求发送消息到ID: " .. send_url)
    
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    
    local response_body = {}
    local res, code = http.request{
        url = send_url,
        method = "GET",
        sink = ltn12.sink.table(response_body),
    }
    
    if not res or code ~= 200 then
        print("发送消息到ID失败, HTTP状态码: " .. tostring(code))
        return false
    end
    
    local body = table.concat(response_body)
    print("发送消息到ID接口返回: " .. body)
    
    local ok, data = pcall(jsonLib.decode, body)
    if not ok or not data or not data.success then
        print("解析发送消息响应失败")
        return false
    end
    
    -- 回到桌面打开ID
    print("切换到ID获取消息...")
    common.backToHomeWithCheck(2)
    sleep(300)
    common.openIDOptimize()
    sleep(1000)
    
    -- 搜索联系人获取消息
    common.searchIDOptimize(global_config.id_ai_project_config.name, false)
    sleep(1500)
    
    -- 获取ID消息列表
    local msgs = common.getIDMessages()
    if msgs and #msgs > 0 then
        print("获取到" .. #msgs .. "条ID消息")
        
        -- 获取最后一条消息
        local lastMsg = msgs[#msgs]
        local msg_x = lastMsg.x + 200
        local msg_y = lastMsg.y + 60
        
        -- 长按最后一条消息复制
        print("长按复制消息")
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
            print("复制成功，切回微信发送")
            
            -- 返回ID消息列表
            common.backToIDMessageList()
            sleep(500)
            
            -- 直接切换到微信打开文件传输助手
            common.backToHomeWithCheck()
            sleep(500)
            common.openWeChatSimple()
            sleep(1500)
            
       
            
            -- 粘贴消息
            common.doPaste()
            sleep(1000)
            
             -- 点击发送
            local send_pos = ocr_start(115, 216, 804, 1270, "发送")
            if send_pos then
                print("[发送步骤1", "] 点击发送按钮")
                randomTap(send_pos[1], send_pos[2], 10, 10, "点击发送按钮")
                sleep(1500)
            end
			sleep(2000)
			 local send_pos1 = ocr_start(489,1640,827,1839, "发送")
            if send_pos1 then
                print("[发送步骤2", "] 点击发送按钮")
                randomTap(send_pos1[1], send_pos1[2], 10, 10, "点击发送按钮")
                sleep(1500)
            end

            
            -- 调用转发函数，传入联系人列表进行勾选
            print("开始转发给联系人")
          --  common.forwardLastMessageFromFileHelper(contacts)
            
            print("========== 发送消息流程完成 ==========")
            
            -- 注意：状态更新应该在 massSendFlow 函数中完成，而不是在这里
            -- 因为 sendViaFileHelperAndForward 只负责发送，状态更新应该在更高层级的函数中处理
            
            common.backToWeChatMessageList()
			sleep(1000)
			wx_word = ocr_start(121,1833,244,1943,"微信")
			if wx_word then
				randomTap(wx_word[1],wx_word[2],3,3,"点击回到微信列表")
			end
            return true
        else
            print("复制消息失败")
            return false
        end
    else
        print("未获取到ID消息")
        return false
    end
end

-- ========== msg_type=2 发送流程函数 ==========

-- 通过群发助手发送消息（msg_type=2 专用）
-- 流程：调用接口发送消息到ID -> 切到ID复制消息 -> 切回微信粘贴发送
-- @param robot_code 机器人编号
-- @param channel_num 通道编号
-- @return success 是否成功
local function sendViaMassSendAssistant(robot_code, channel_num)
    print("========== 开始群发助手发送流程(msg_type=2) ==========")
    
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    local api_base_url = global_config and global_config.api_base_url or "http://127.0.0.1:8095"
    
    -- ========== 1. 调用 /api/mass_send/send_to_id 接口 ==========
    local send_url = api_base_url .. "/api/mass_send/send_to_id?robotCode=" .. robot_code .. "&channelNum=" .. tostring(channel_num)
    print("请求发送消息到ID: " .. send_url)
    
    local response_body = {}
    local res, code = http.request{
        url = send_url,
        method = "GET",
        sink = ltn12.sink.table(response_body),
    }
    
    if not res or code ~= 200 then
        print("发送消息到ID失败, HTTP状态码: " .. tostring(code))
        return false
    end
    
    local body = table.concat(response_body)
    print("mass_send/send_to_id 接口返回: " .. body)
    
    local ok, data = pcall(jsonLib.decode, body)
    if not ok or not data or not data.success then
        print("解析发送消息响应失败")
        return false
    end
    
    -- ========== 2. 切回桌面打开ID获取消息 ==========
    print("切换到ID获取消息...")
    common.backToHomeWithCheck(2)
    sleep(300)
    common.openIDOptimize()
    sleep(1000)
    
    -- 搜索联系人获取消息
    common.searchIDOptimize(global_config.id_ai_project_config.name, false)
    sleep(1500)
    
    -- ========== 3. 获取ID消息列表并复制消息 ==========
    local msgs = common.getIDMessages()
    if msgs and #msgs > 0 then
        print("获取到" .. #msgs .. "条ID消息")
        
        -- 获取最后一条消息
        local lastMsg = msgs[#msgs]
        local msg_x = lastMsg.x + 200
        local msg_y = lastMsg.y + 60
        
        -- 长按最后一条消息复制
        print("长按复制消息")
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
        
        if not copySuccess then
            print("复制消息失败")
            return false
        end
        
        -- ========== 4. 切回微信粘贴发送 ==========
        print("复制成功，切回微信发送")
        
        -- 返回ID消息列表
        common.backToIDMessageList()
        sleep(500)
        
        -- 切换到微信
        common.backToHomeWithCheck()
        sleep(500)
        common.openWeChatSimple()
        sleep(1500)
        
        -- 粘贴消息
        common.doPaste()
        sleep(1000)
        
        -- 点击发送
        local send_pos = ocr_start(115, 216, 804, 1270, "发送")
        if send_pos then
            print("[发送步骤1] 点击发送按钮")
            randomTap(send_pos[1], send_pos[2], 10, 10, "点击发送按钮")
            sleep(1500)
        end
        sleep(2000)
        local send_pos1 = ocr_start(489, 1640, 827, 1839, "发送")
        if send_pos1 then
            print("[发送步骤2] 点击发送按钮")
            randomTap(send_pos1[1], send_pos1[2], 10, 10, "点击发送按钮")
            sleep(1500)
        end
        
        print("========== 群发助手发送完成 ==========")
        
        -- 返回微信消息列表
        common.backToWeChatMessageList()
        sleep(1000)
        local wx_word = ocr_start(121, 1833, 244, 1943, "微信")
        if wx_word then
            randomTap(wx_word[1], wx_word[2], 3, 3, "点击回到微信列表")
        end
        
        return true
    else
        print("未获取到ID消息")
        return false
    end
end



-- 通过ID发送消息并通过群发助手转发
-- @param robot_code 机器人编号
-- @param channel_num 通道编号
-- @param msg_type 消息类型（默认1）
-- @param contacts 联系人列表
-- @return success 是否成功
local function reminderSendAndUp(robot_code, channel_num, msg_type, contact)
    print("========== 开始发送消息流程 ==========")
    
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    
    -- ========== 1. 先调用 /api/reminder/next 获取消息内容 ==========
    local api_base_url = global_config and global_config.api_base_url or "http://127.0.0.1:8095"
    local next_url = api_base_url .. "/api/reminder/next?robot_code=" .. robot_code .. "&channel_num=" .. tostring(channel_num)
    print("请求获取消息内容: " .. next_url)
    
    local next_response_body = {}
    local next_res, next_code = http.request{
        url = next_url,
        method = "GET",
        sink = ltn12.sink.table(next_response_body),
    }
    
    if not next_res or next_code ~= 200 then
        print("获取消息内容失败, HTTP状态码: " .. tostring(next_code))
        return false
    end
    
    local next_body = table.concat(next_response_body)
    print("next接口返回: " .. next_body)
    
    local ok, next_data = pcall(jsonLib.decode, next_body)
    if not ok or not next_data or not next_data.success then
        print("解析next接口响应失败")
        return false
    end
    
    -- 从响应中获取message内容（获取最后一个step的message，因为群发通常是最后一步）
    local message_content = ""
    if next_data.steps and #next_data.steps > 0 then
        local targetStep = next_data.steps[#next_data.steps]
        if targetStep and targetStep.message then
            message_content = targetStep.message
            print("获取到消息内容（最后一个step）: " .. message_content)
        elseif next_data.steps[1].message then
            -- 备用：获取第一个step的消息
            message_content = next_data.steps[1].message
            print("获取到消息内容（第一个step）: " .. message_content)
        end
    end
    
    if message_content == "" then
        print("警告: 未能获取到消息内容")
    end
    
    -- 从 steps[].users[] 中提取所有uid用于后续更新状态
    local all_uids = {}
    if next_data.steps then
        for _, step in ipairs(next_data.steps) do
            if step.users then
                for _, user in ipairs(step.users) do
                    if user.uid then
                        table.insert(all_uids, tostring(user.uid))
                    end
                end
            end
        end
    end
    local response_uid = #all_uids > 0 and table.concat(all_uids, ",") or ""
    print("待更新uid数量: " .. #all_uids .. ", uid列表: " .. response_uid)
    
    -- ========== 2. 调用 /api/send_msg_to_id 发送消息 ==========
    local send_url = global_config.send_msg_to_id_url .. "?robotCode=" .. robot_code .. "&channelNum=" .. tostring(channel_num) .. "&msg=" .. urlEncode(message_content)
    print("请求发送消息到ID: " .. send_url)
    
    local response_body = {}
    local res, code = http.request{
        url = send_url,
        method = "GET",
        sink = ltn12.sink.table(response_body),
    }
    
    if not res or code ~= 200 then
        print("发送消息到ID失败, HTTP状态码: " .. tostring(code))
        return false
    end
    
    local body = table.concat(response_body)
    print("发送消息到ID接口返回: " .. body)
    
    local ok2, data = pcall(jsonLib.decode, body)
    if not ok2 or not data or not data.success then
        print("解析发送消息响应失败")
        return false
    end
    
    -- 回到桌面打开ID
    print("切换到ID获取消息...")
    common.backToHomeWithCheck(2)
    sleep(300)
    common.openIDOptimize()
    sleep(1000)
    
    -- 搜索联系人获取消息
    common.searchIDOptimize(global_config.id_ai_project_config.name, false)
    sleep(1500)
    
    -- 获取ID消息列表
    local msgs = common.getIDMessages()
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
            common.backToIDMessageList()
            sleep(500)

            -- 直接切换到微信打开文件传输助手
            common.backToHomeWithCheck()
            sleep(500)
            common.openWeChatSimple()
            sleep(1500)

            -- 粘贴消息
            common.doPaste()
            sleep(1000)

            -- 点击发送
            local send_pos = ocr_start(115, 216, 804, 1270, "发送")
            if send_pos then
                print("[发送步骤1", "] 点击发送按钮")
                randomTap(send_pos[1], send_pos[2], 10, 10, "点击发送按钮")
                sleep(1500)
            end
			sleep(2000)
			 local send_pos1 = ocr_start(489,1640,827,1839, "发送")
            if send_pos1 then
                print("[发送步骤2", "] 点击发送按钮")
                randomTap(send_pos1[1], send_pos1[2], 10, 10, "点击发送按钮")
                sleep(1500)
            end

            -- 从next接口响应中获取uid并更新状态
            local uid_to_update = response_uid or ""
            if uid_to_update ~= "" then
                updateReminderMessageStatus(uid_to_update)
            else
                print("警告: 未获取到uid，无法更新状态")
            end
			
			common.backToWeChatMessageList()
			sleep(1000)
			wx_word = ocr_start(121,1833,244,1943,"微信")
			if wx_word then
				randomTap(wx_word[1],wx_word[2],3,3,"点击回到微信列表")
				return true
			end
			
            
        end
    end

end

-- ========== 主流程函数 ==========

-- 执行群发助手流程
-- @param options 配置选项
--   - robot_code: 机器人编号（可选，默认从全局配置获取）
--   - channel_num: 通道编号（可选，默认从全局配置获取）
--   - msg_type: 消息类型（可选，默认1，1=回访）
--   - contacts: 联系人列表（可选，如果为空则自动从接口获取）
-- 返回: success, contacts, robot_code, channel_num
local function massSendFlow(options)
    options = options or {}
    
    local robot_code = options.robot_code or getRobotChannelConfig()
    local channel_num = options.channel_num or select(2, getRobotChannelConfig())
    local msg_type = options.msg_type or 1
    local contacts = options.contacts
    
    print("========== 开始群发助手流程 ==========")
    print("robot_code: " .. robot_code .. ", channel_num: " .. tostring(channel_num) .. ", msg_type: " .. tostring(msg_type))
    
    -- 如果没有提供联系人列表，自动从接口获取
    local message_content = options.message_content
    if not contacts or #contacts == 0 then
        print("未提供联系人列表，自动从接口获取...")
        local task_type, task_data
        contacts, message_content, _, task_type, task_data = getMassSendContacts(robot_code, channel_num, msg_type)
        if #contacts == 0 then
            print("未能获取到联系人列表，流程中断")
            return false, {}, robot_code, channel_num, msg_type
        end

        -- 检测 type=3 走收藏群发流程
        if task_type == 3 then
            print("========== 检测到 type=3，路由到收藏群发流程 ==========")
            local favorite = require("favorite_mass_send")
            return favorite.run({
                robot_code = robot_code,
                channel_num = channel_num,
                task_data = task_data,
                records = contacts,
            })
        end
    end
    
    print("待发送联系人数量: " .. #contacts)
    
    -- 1. 点击新建群发
    if not clickNewMassSend() then
        print("流程中断: 无法点击新建群发")
        return false
    end
    
    -- 2. 选择联系人
    local matched, success = selectContactsFromList(contacts)
    if not success then
        print("流程中断: 联系人选择失败")
        return false
    end
	
    -- 3. 点击选中按钮
    if not clickSelectButton() then
        print("流程中断: 无法点击选中按钮")
        return false
    end
    
    -- 4. 根据 msg_type 选择发送方式
    if msg_type == 2 then
        -- msg_type=2: 调用 mass_send/send_to_id 接口，然后切到ID复制消息
        print("========== msg_type=2: 使用群发助手发送 ==========")
        if not sendViaMassSendAssistant(robot_code, channel_num) then
            print("流程中断: 发送消息失败")
            return false
        end
        
        -- 发送成功后更新状态
        print("发送成功，更新群发记录状态...")
        -- 从已选中的联系人中提取record_ids
        local record_ids = {}
        for _, contact in ipairs(matched) do
            if type(contact) == "table" and contact.id then
                table.insert(record_ids, tostring(contact.id))
            end
        end
        updateMassSendRecordStatus(robot_code, channel_num, 1, record_ids)
    else
        -- msg_type=1: 通过文件传输助手发送并转发消息
        print("========== msg_type=1: 通过文件传输助手发送 ==========")
        if not sendViaFileHelperAndForward(robot_code, channel_num, msg_type, contacts, message_content) then
            print("流程中断: 发送消息失败")
            return false
        end
        
        -- 发送成功后更新状态
        print("发送成功，开始更新状态...")
        local all_uids = {}
        for _, contact in ipairs(contacts) do
            if type(contact) == "table" and contact.uid then
                table.insert(all_uids, tostring(contact.uid))
            end
        end
        if #all_uids > 0 then
            local uid_str = table.concat(all_uids, ",")
            print("更新uid: " .. uid_str)
            updateReminderMessageStatus(uid_str)
        else
            print("警告: 未提取到uid，跳过状态更新")
        end
    end
    
    print("========== 群发助手流程完成 ==========")
    print("成功选中: " .. #matched .. " 个联系人")
    print("robot_code: " .. robot_code .. ", channel_num: " .. tostring(channel_num) .. ", msg_type: " .. tostring(msg_type))
    -- 检测是否存在返回图标，存在则点击返回
    print("检测是否存在返回图标，存在则点击返回")
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
	for retryBack = 1, 12 do
		-- 第1步：检测微信列表标题
		local wxTitle = ocr_start(300, 204, 797, 320, "微信")
		if wxTitle then
			print("已回到微信列表，流程结束")
			backToWxDone = true
			break
		end

		-- 第2步：检测是否在"我的"页面（有"服务"或"收藏"）
		local server_wd = ocr_start(93, 581, 936, 956, "服务")
		local favor_wd = ocr_start(93, 581, 936, 956, "收藏")
		if server_wd or favor_wd then
			print('在"我的"页面，尝试通过底部微信Tab切回聊天列表')
			local wxTabPos = ocr_start(99, 1784, 387, 1939, "微信")
			if wxTabPos then
				print(string.format("找到底部微信Tab: (%d, %d)", wxTabPos[1], wxTabPos[2]))
				randomTap(wxTabPos[1], wxTabPos[2], 5, 5, "点击微信Tab回到聊天列表")
				sleep(1200)
			else
				print("未找到底部微信Tab，尝试页内返回 (第" .. retryBack .. "次)")
				local back_pos = ocr_start(115, 216, 804, 1270, "返回")
				if back_pos then
					randomTap(back_pos[1], back_pos[2], 10, 10, "点击页面返回")
				end
				sleep(1000)
			end
		else
			-- 第3步：不在微信列表也不在"我的"页面，尝试点击返回按钮
			print(string.format("未在微信列表，尝试返回 (第%d次)", retryBack))
			local back_pos = ocr_start(115, 216, 804, 1270, "返回")
			if back_pos then
				randomTap(back_pos[1], back_pos[2], 10, 10, "点击返回按钮")
				sleep(1000)
			else
				-- OCR未找到返回文字，尝试点击左上角通用返回区域
				print("未找到返回文字，点击左上角返回区域")
				randomTap(100, 220, 30, 20, "点击左上角返回")
				sleep(1000)
			end
		end
	end
	if not backToWxDone then
		print("返回微信列表重试耗尽")
	end
    return true, matched, robot_code, channel_num, msg_type
end

-- ========== 任务获取与 type 路由 ==========

-- 获取群发任务（/api/mass_send/task）
-- @param robot_code 机器人编码
-- @param channel_num 通道编号
-- @return task_data 任务数据(含 type、records 等), nil 表示失败
local function fetchMassSendTask(robot_code, channel_num)
    local api_base_url = global_config and global_config.api_base_url or "http://127.0.0.1:8095"
    local url = api_base_url .. "/api/mass_send/task?robotCode=" .. robot_code .. "&channelNum=" .. tostring(channel_num)

    print("获取群发任务: " .. url)

    local http = require("socket.http")
    local ltn12 = require("ltn12")

    local response_body = {}
    local res, code = http.request{
        url = url,
        method = "GET",
        sink = ltn12.sink.table(response_body),
        protocol = "http",
    }

    if not res or code ~= 200 then
        print("获取群发任务失败, HTTP状态码: " .. tostring(code))
        return nil
    end

    local body = table.concat(response_body)
    print("任务接口响应: " .. body)

    local ok, decoded = pcall(jsonLib.decode, body)
    if not ok or not decoded or not decoded.success then
        print("解析任务响应失败或接口返回错误")
        return nil
    end

    return decoded.data
end

-- 群发任务入口：统一调用 massSendFlow（内部已含 type=3 路由逻辑）
-- @param options table { robot_code, channel_num, msg_type }
-- @return boolean 是否成功
local function runMassSendTask(options)
    options = options or {}

    local robot_code = options.robot_code or getRobotChannelConfig()
    local channel_num = options.channel_num or select(2, getRobotChannelConfig())
    local msg_type = options.msg_type or 2

    print("========== 群发任务路由 ==========")
    print(string.format("robot_code: %s, channel_num: %d, msg_type: %d", robot_code, channel_num, msg_type))

    -- 统一走 massSendFlow，内部会根据 by_channel 返回的 type 字段自动路由
    return massSendFlow(options)
end

-- 导出模块
local M = {
    clickNewMassSend = clickNewMassSend,

    clickSelectButton = clickSelectButton,
    fuzzyMatchContact = fuzzyMatchContact,
    selectContactsFromList = selectContactsFromList,
    sendViaFileHelperAndForward = sendViaFileHelperAndForward,
    sendViaMassSendAssistant = sendViaMassSendAssistant,
    massSendFlow = massSendFlow,
    reminderSendAndUp = reminderSendAndUp,
    getRobotChannelConfig = getRobotChannelConfig,
    getMassSendContacts = getMassSendContacts,
    updateMassSendRecordStatus = updateMassSendRecordStatus,
    fetchMassSendTask = fetchMassSendTask,
    runMassSendTask = runMassSendTask,
}

return M
