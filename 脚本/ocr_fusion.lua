import('java.io.File')
import('java.lang.*')
import('java.util.Arrays')
import('android.content.Context')
import('android.hardware.Sensor')
import('android.hardware.SensorEvent')
import('android.hardware.SensorEventListener')
import('android.hardware.SensorManager')
import('com.nx.assist.lua.LuaEngine')

local config = require("config")
-------------------------引入方式-------------------------
local loader = LuaEngine.loadApk("TomatoOCR.apk")
-------------------------引入方式-------------------------
local OCR = loader.loadClass("com.tomato.ocr.lr.OCRApi")
local tmo_ocr = OCR.init(LuaEngine.getContext())

-- ******************************* OCR 打包问题改变加载方式 start *****************************

--[[
local projectDir = projectPath()
local apkPath = projectDir .. "/TomatoOCR.apk"
log("APK完整路径: " .. apkPath)

if not fileExists(apkPath) then
    toast("TomatoOCR.apk 文件不存在！")
    return
end

local loader = LuaEngine.loadApk(apkPath)
local OCR = loader.loadClass("com.tomato.ocr.lr.OCRApi")
local tmo_ocr = OCR.init(LuaEngine.getContext())

if tmo_ocr then
    toast("TomatoOCR初始化成功")
else
    toast("TomatoOCR初始化失败")
end
--]]

-- ******************************* OCR 打包问题改变加载方式 end *****************************

local license = config.tomato_ocr.key
local remark = "test"    -- 备注
local flag = tmo_ocr.setLicense(license, remark) -- 设置license，见授权码获取
print("OCR授权设置返回(原始):", flag)
local flag_json = jsonLib.decode(flag)
print("OCR授权状态:", flag_json)
-- printEx(flag_json)
----------------------注：以上代码全局只需写一次-------------------------------a

-- 暴露给其他模块做诊断/直接调用
_G.tmo_ocr = tmo_ocr

function ocr_static_file()
	tmo_ocr.setRecType("ch-3.0")
    
    tmo_ocr.setDetBoxType("rect")           -- 调整检测模型检测文本参数- 默认"rect": 由于手机上截图文本均为矩形文本，从该版本之后均改为rect，"quad"：可准确检测倾斜文本
    tmo_ocr.setDetUnclipRatio(1.9)          -- 调整检测模型检测文本参数 - 默认1.9: 值范围1.6-2.5之间
    tmo_ocr.setRecScoreThreshold(0.3)       -- 识别得分过滤 - 默认0.1，值范围0.1-0.9之间
    tmo_ocr.setReturnType("json")
	tmo_ocr.setBinaryThresh(0)              -- 二值化设定，非必须
    tmo_ocr.setRunMode("slow")              -- 默认"slow"；"fast"：小图识别上会加速，但准确率会降低，推荐用默认值"slow"
    tmo_ocr.setFilterColor("", "black");    -- 设置滤色值和背景色(black\white)，滤色值默认是空的，详细使用见方法说明
	
	local type = 3;
	
	local result = tmo_ocr.ocrFile(config.tomato_ocr.img_path.."test.png", type)
	
	if result ~="" then
        -- 自行解析
        local json_results = jsonLib.decode(result) -- setReturnType为"json"时，返回的是json字符串，用jsonLib.decode解析
        for i, json_result in ipairs(json_results) do
		    message = message..json_result.words
		end
    end
	return message
end

function ocr_start(x1, y1, x2, y2, zi)
    -- 以下方法详细介绍，见文档：方法介绍
    -- 注：ch、ch-2.0、ch-3.0版可切换使用，对部分场景可适当调整
    -- "ch"：普通中英文识别，1.0版模型
    -- "ch-2.0"：普通中英文识别，2.0版模型
    -- "ch-3.0"：普通中英文识别，3.0版模型
    -- "number"：数字识别
    -- "cht"：繁体，"japan"：日语，"korean"：韩语
    tmo_ocr.setRecType("ch-3.0")
    tmo_ocr.setDetBoxType("rect")           -- 调整检测模型检测文本参数- 默认"rect": 由于手机上截图文本均为矩形文本，从该版本之后均改为rect，"quad"：可准确检测倾斜文本
    tmo_ocr.setDetUnclipRatio(1.9)          -- 调整检测模型检测文本参数 - 默认1.9: 值范围1.6-2.5之间
    -- tmo_ocr.setRecScoreThreshold(0.3)    -- 识别得分过滤 - 默认0.1，值范围0.1-0.9之间
    tmo_ocr.setRecScoreThreshold(config.recognition.ocr_confidence)
    tmo_ocr.setReturnType("json")
    -- 返回类型 - 默认"json": 包含得分、坐标和文字；
    -- "text"：纯文字；
    -- "num"：纯数字；
    -- 自定义输入想要返回的文本：".￥1234567890"，仅只返回这些内容
    
    tmo_ocr.setBinaryThresh(0)              -- 二值化设定，非必须
    -- tmo_ocr.setRunMode("slow")           -- 默认"slow"；"fast"：小图识别上会加速，但准确率会降低，推荐用默认值"slow"
    if config.recognition.fast_mode then
        tmo_ocr.setRunMode("fast")          -- 快速模式 是否能压缩时间，并且在满足业务需求的情况下
    else
        tmo_ocr.setRunMode("slow")
    end
    tmo_ocr.setFilterColor("", "black");    -- 设置滤色值和背景色(black\white)，滤色值默认是空的，详细使用见方法说明

    local ocrType = 3;
    -- ocrType=0 : 只检测
    -- ocrType=1 : 方向分类 + 识别
    -- ocrType=2 : 只识别
    -- ocrType=3 : 检测 + 识别
    
    -- 只检测文字位置：ocrType=0
    -- 全屏识别: ocrType=3或者不传ocrType
    -- 截取单行文字识别：ocrType=1或者ocrType=2
    
    -- 例子一
    --[[
	    snapShot("/mnt/shared/Pictures/test.png",x1, y1, x2, y2)
        local result = tmo_ocr.ocrFile("/mnt/shared/Pictures/test.png", ocrType)
        printEx(result);
	]]

    -- 例子二
    local bitmap = LuaEngine.snapShot(x1, y1, x2, y2)
    local result = tmo_ocr.ocrBitmap(bitmap, ocrType)
    bitmap.recycle()
    
	
    local message = ""
    if result ~="" then
        -- 自行解析
        local json_results = jsonLib.decode(result)     -- setReturnType为"json"时，返回的是json字符串，用jsonLib.decode解析
        for i, json_result in ipairs(json_results) do
		    message = message..json_result.words
		end
    end

	if zi == "" then
		return message
	end

    -- 找字返回坐标，返回的是"百度"的中心点坐标，没有找到字返回""空字符串
    -- 参数验证：确保 zi 是有效的非空字符串
    if not zi or type(zi) ~= "string" or zi == "" then
        return message
    end
    
    local point = tmo_ocr.findTapPoint(zi)
    if point ~="" then
		local json_point = jsonLib.decode(point)
		local center_x = json_point[1] + x1
		local center_y = json_point[2] + y1
		return {center_x, center_y}                     -- 需要点击，就放开这行，找字并返回中心点坐标
	end

    return false
end

-- OCR识别并返回带坐标的结果列表（用于模糊匹配）
-- 返回值: { {words="文字", x=中心x, y=中心y}, ... }
function ocr_start_with_boxes(x1, y1, x2, y2)
	tmo_ocr.setRecType("ch-3.0")
	tmo_ocr.setDetBoxType("rect")
	tmo_ocr.setDetUnclipRatio(1.9)
	tmo_ocr.setRecScoreThreshold(config.recognition.ocr_confidence)
	tmo_ocr.setReturnType("json")
	tmo_ocr.setBinaryThresh(0)
	if config.recognition.fast_mode then
		tmo_ocr.setRunMode("fast")
	else
		tmo_ocr.setRunMode("slow")
	end
	tmo_ocr.setFilterColor("", "black")

	local ocrType = 3
	local bitmap = LuaEngine.snapShot(x1, y1, x2, y2)
	local result = tmo_ocr.ocrBitmap(bitmap, ocrType)
	bitmap.recycle()

	local results = {}
	if result ~= "" then
		local json_results = jsonLib.decode(result)
		for i, json_result in ipairs(json_results) do
			local words = json_result.words or ""
			-- 计算中心点坐标（OCR返回的是相对坐标，需要加上区域偏移）
			local cx, cy
			
			-- 尝试多种可能的坐标字段
			local function tryGetCoords()
				-- 方法1: 直接使用 cx, cy 字段
				if json_result.cx and json_result.cy then
					return json_result.cx + x1, json_result.cy + y1
				end
				
				-- 方法2: 使用 location 字段 (常见格式)
				local loc = json_result.location
				if loc and type(loc) == "table" then
					-- 检查是否是顶点数组格式: [[x1,y1],[x2,y2],[x3,y3],[x4,y4]]
					if #loc >= 4 and type(loc[1]) == "table" and #loc[1] >= 2 then
						-- 计算对角点中心 [[x1,y1],[x2,y2],[x3,y3],[x4,y4]]
						local cx_local = (loc[1][1] + loc[3][1]) / 2
						local cy_local = (loc[1][2] + loc[3][2]) / 2
						return cx_local + x1, cy_local + y1
					end
					-- location = {left, top, width, height}
					if loc.left and loc.top then
						local w = loc.width or 0
						local h = loc.height or 0
						return loc.left + w/2 + x1, loc.top + h/2 + y1
					end
					-- location = {x, y, w, h}
					if loc.x and loc.y then
						local w = loc.w or loc.width or 0
						local h = loc.h or loc.height or 0
						return loc.x + w/2 + x1, loc.y + h/2 + y1
					end
				end
				
				-- 方法3: 使用 left, top, right, bottom
				if json_result.left and json_result.top then
					local w = (json_result.right or json_result.left)
					local h = (json_result.bottom or json_result.top)
					return (json_result.left + w) / 2 + x1, (json_result.top + h) / 2 + y1
				end
				
				-- 方法4: 使用 box 数组格式 {x1, y1, x2, y2, x3, y3, x4, y4}
				local box = json_result.box
				if box and type(box) == "table" then
					if #box >= 4 and type(box[1]) == "number" then
						return (box[1] + box[5]) / 2 + x1, (box[2] + box[6]) / 2 + y1
					end
					-- 格式: {{x1,y1}, {x2,y2}, {x3,y3}, {x4,y4}}
					if #box >= 3 and type(box[1]) == "table" then
						return (box[1][1] + box[3][1]) / 2 + x1, (box[1][2] + box[3][2]) / 2 + y1
					end
				end
				
				-- 方法5: 使用 points 或 polygon 顶点数组
				local points = json_result.points or json_result.polygon
				if points and type(points) == "table" and #points >= 2 then
					local xmin, xmax = points[1][1] or 0, points[1][1] or 0
					local ymin, ymax = points[1][2] or 0, points[1][2] or 0
					for _, p in ipairs(points) do
						if p[1] then
							xmin = math.min(xmin, p[1])
							xmax = math.max(xmax, p[1])
						end
						if p[2] then
							ymin = math.min(ymin, p[2])
							ymax = math.max(ymax, p[2])
						end
					end
					return (xmin + xmax) / 2 + x1, (ymin + ymax) / 2 + y1
				end
				
				return nil
			end
			
			local ok, rx, ry = pcall(tryGetCoords)
			if ok and rx and ry then
				cx, cy = rx, ry
			else
				cx, cy = 0, 0
				-- 调试打印：显示可用的字段
				local available = {}
				for k, v in pairs(json_result) do
					if k ~= "words" then
						table.insert(available, k)
					end
				end
				print("OCR坐标解析失败，可用字段:", table.concat(available, ","))
			end
			
			table.insert(results, {words = words, x = cx, y = cy})
		end
	end
	return results
end

-- OCR识别并返回每个文字块的最右侧X坐标和中心Y坐标
-- 用于需要从文字右侧精确偏移点击的场景（如长按消息唤醒收藏菜单）
-- 返回值: { {words="文字", x_right=文字块最右端X, y=中心Y}, ... }
function ocr_start_with_box_rightmost(x1, y1, x2, y2)
	tmo_ocr.setRecType("ch-3.0")
	tmo_ocr.setDetBoxType("rect")
	tmo_ocr.setDetUnclipRatio(1.9)
	tmo_ocr.setRecScoreThreshold(config.recognition.ocr_confidence)
	tmo_ocr.setReturnType("json")
	tmo_ocr.setBinaryThresh(0)
	if config.recognition.fast_mode then
		tmo_ocr.setRunMode("fast")
	else
		tmo_ocr.setRunMode("slow")
	end
	tmo_ocr.setFilterColor("", "black")

	local ocrType = 3
	local bitmap = LuaEngine.snapShot(x1, y1, x2, y2)
	local result = tmo_ocr.ocrBitmap(bitmap, ocrType)
	bitmap.recycle()

	local results = {}
	if result ~= "" then
		local json_results = jsonLib.decode(result)
		for i, json_result in ipairs(json_results) do
			local words = json_result.words or ""
			local x_right, cy

			-- 解析最右侧X坐标和中心Y坐标
			local function tryGetRightmostAndCenter()
				-- 方法1: 使用 location 顶点数组 [[x1,y1],[x2,y2],[x3,y3],[x4,y4]]
				local loc = json_result.location
				if loc and type(loc) == "table" then
					if #loc >= 4 and type(loc[1]) == "table" and #loc[1] >= 2 then
						local xmax = loc[1][1]
						for j = 2, #loc do
							if loc[j][1] > xmax then xmax = loc[j][1] end
						end
						local cy_local = (loc[1][2] + loc[3][2]) / 2
						return xmax + x1, cy_local + y1
					end
					-- location = {left, top, width, height}
					if loc.left and loc.top then
						return (loc.left + (loc.width or 0)) + x1,
							   (loc.top + (loc.height or 0) / 2) + y1
					end
					-- location = {x, y, w, h}
					if loc.x and loc.y then
						local w = loc.w or loc.width or 0
						local h = loc.h or loc.height or 0
						return (loc.x + w) + x1, (loc.y + h / 2) + y1
					end
				end

				-- 方法2: 使用 left, top, right, bottom
				if json_result.left and json_result.top then
					local r = json_result.right or json_result.left
					local b = json_result.bottom or json_result.top
					return r + x1, (json_result.top + b) / 2 + y1
				end

				-- 方法3: 使用 box 数组 {x1,y1,x2,y2,x3,y3,x4,y4}
				local box = json_result.box
				if box and type(box) == "table" then
					if #box >= 4 and type(box[1]) == "number" then
						-- 奇数索引是X值: box[1], box[3], box[5], box[7]
						local xmax = box[1]
						for j = 3, #box, 2 do
							if box[j] > xmax then xmax = box[j] end
						end
						return xmax + x1, (box[2] + box[6]) / 2 + y1
					end
					-- 格式: {{x1,y1}, {x2,y2}, {x3,y3}, {x4,y4}}
					if #box >= 3 and type(box[1]) == "table" then
						local xmax = box[1][1]
						local ymin = box[1][2]
						local ymax = box[1][2]
						for j = 2, #box do
							if box[j][1] > xmax then xmax = box[j][1] end
							if box[j][2] < ymin then ymin = box[j][2] end
							if box[j][2] > ymax then ymax = box[j][2] end
						end
						return xmax + x1, (ymin + ymax) / 2 + y1
					end
				end

				-- 方法4: 使用 points 或 polygon 顶点数组
				local points = json_result.points or json_result.polygon
				if points and type(points) == "table" and #points >= 2 then
					local xmax = points[1][1] or 0
					local ymin = points[1][2] or 0
					local ymax = points[1][2] or 0
					for _, p in ipairs(points) do
						if p[1] then
							if p[1] > xmax then xmax = p[1] end
						end
						if p[2] then
							if p[2] < ymin then ymin = p[2] end
							if p[2] > ymax then ymax = p[2] end
						end
					end
					return xmax + x1, (ymin + ymax) / 2 + y1
				end

				return nil
			end

			local ok, rx, ry = pcall(tryGetRightmostAndCenter)
			if ok and rx and ry then
				x_right, cy = rx, ry
			else
				x_right, cy = 0, 0
				local available = {}
				for k, v in pairs(json_result) do
					if k ~= "words" then
						table.insert(available, k)
					end
				end
				print("OCR最右坐标解析失败，可用字段:", table.concat(available, ","))
			end

			table.insert(results, {words = words, x_right = x_right, y = cy})
		end
	end
	return results
end

-- 转义字符串中的特殊字符，用于 string.find
local function escapePattern(str)
	if type(str) ~= "string" then return "" end
	return str:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
end

-- 计算两个字符串的最大连续重叠字符数
local function calcOverlap(str1, str2)
	local len1 = utf8.length(str1)
	local len2 = utf8.length(str2)
	local maxOverlap = 0

	-- 检查 str1 的所有子串是否在 str2 中
	for i = 1, len1 do
		for j = i, len1 do
			local sub = utf8.mid(str1, i, j - i + 1)
			if utf8.length(sub) >= 2 then
				local escapedSub = escapePattern(sub)
				if string.find(str2, escapedSub) then
					local subLen = utf8.length(sub)
					if subLen > maxOverlap then
						maxOverlap = subLen
					end
				end
			end
		end
	end
	return maxOverlap
end

-- 模糊查找包含指定子串的文字块坐标
-- 返回值: {x, y} 或 nil
function ocr_fuzzy_find(x1, y1, x2, y2, substr)
	local results = ocr_start_with_boxes(x1, y1, x2, y2)
	print("ocr_fuzzy_find 识别到", #results, "个文字块, 查找子串:", substr)
	local bestMatch = nil
	local bestScore = 0
	local bestMatchWords = nil
	local substrLen = utf8.length(substr)
	
	for i, item in ipairs(results) do
		print("文字块["..i.."]:", item.words, "坐标:", item.x, item.y)
		local score = 0
		local wordsLen = utf8.length(item.words)

		-- 双向匹配：识别内容包含搜索词，或搜索词包含识别内容
		local escapedWords = escapePattern(item.words)
		local escapedSubstr = escapePattern(substr)
		if string.find(item.words, escapedSubstr) then
			score = substrLen
		elseif string.find(substr, escapedWords) then
			score = wordsLen
		else
			-- 检查字符重叠（至少2个连续字符重叠，且重叠比例超过50%）
			local overlap = calcOverlap(item.words, substr)
			if overlap >= 2 then
				local overlapRatio = overlap / math.max(wordsLen, substrLen)
				if overlapRatio > 0.5 then
					score = overlap
				end
			end
		end
		
		-- 记录最高分数的匹配
		if score > bestScore then
			bestScore = score
			bestMatch = item
			bestMatchWords = item.words
		end
	end
	
	if bestMatch then
		-- 如果坐标有效，直接返回
		if bestMatch.x > 0 and bestMatch.y > 0 then
			print("模糊匹配成功(有效坐标):", substr, "在", bestMatchWords, "坐标:", bestMatch.x, bestMatch.y, "分数:", bestScore)
			return {bestMatch.x, bestMatch.y}
		else
			-- 坐标无效，尝试用 findTapPoint 获取坐标
			print("模糊匹配成功但坐标无效，尝试 findTapPoint:", bestMatchWords)
			local point = tmo_ocr.findTapPoint(bestMatchWords)
			if point ~= "" then
				local json_point = jsonLib.decode(point)
				local center_x = json_point[1] + x1
				local center_y = json_point[2] + y1
				print("findTapPoint 获取坐标成功:", bestMatchWords, "坐标:", center_x, center_y)
				return {center_x, center_y}
			else
				print("findTapPoint 也失败，返回 nil")
			end
		end
	end
	return nil
end