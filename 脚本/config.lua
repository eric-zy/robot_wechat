-- 根据debug控制接口地址前缀
-- debug=true 使用本地地址，debug=false 使用线上地址
local is_debug = false  -- 修改此处切换环境
local api_base_url = is_debug and "http://192.168.1.26:5001" or "http://81.71.47.123:5000"
local ws_base_url = is_debug and "ws://192.168.1.26:8765" or "ws://81.71.47.123:8765"
local wx_platform_url = is_debug and "http://192.168.1.39:9527" or "http://81.71.47.123:5000"
local robot_code = "HF-AT-1-029"  -- 机器人编码（需与 ws_init_msg 一致）

return {
	-- 全局基础URL配置
	api_base_url = api_base_url,
	ws_base_url = ws_base_url,

	-- WebSocket连接后发送的身份验证消息
	ws_init_msg = {
		type = "auth",
		robot_id = robot_code
	},

	wechat_swip = {
			x1 = 498,
			y1 = 333,
			x2 = 498,
			y2 = 733
		},
	server = {
		debug = is_debug,
		timeout = 60,
		require_control = false
	},

	-- 接口地址
	chat_url = api_base_url .. "/api/chat",
	robot_conf_url = api_base_url .. "/api/robot/read",

	-- 加好友流程获取待处理手机号接口
	fetch_pending_phone_url = api_base_url .. "/api/fetch_pending_phone",

	-- 主动发消息接口
	reminder_next_url = api_base_url .. "/api/reminder/next",
	reminder_send_url = api_base_url .. "/api/reminder/send",

	-- 加票接口
	ticket_add_url = api_base_url .. "/api/ticket/add",

	-- 主动发送消息接口-获取全部待主动联系人员列表
	--/api/reminder/next?robot_code=HF-AT-1-004&channel_num=1&reminder_step=0
	get_sender_list_url = api_base_url .. "/api/reminder/next",
	
	-- 主动发送消息后更新状态接口
	-- 传参  {"uid": "1234,1235,1236"}
	update_reminder_url = api_base_url .. "/api/reminder/update",

	-- 按步骤发送消息到ID接口
	send_by_step_url = api_base_url .. "/api/reminder/send-by-step",

	-- 发送消息给对应ID接口
 	send_msg_to_id_url = api_base_url .. "/api/send_msg_to_id",

	-- 获取活动配置接口
	sku_config_get_url = api_base_url .. "/api/sku-config/get",

	-- 判断用户是否使用新版聊天接口
	-- GET /device/user/read?robot_code=xxx&channel_num=n&phone=xxx
	device_user_read_url = api_base_url .. "/device/user/read",

	-- 新版聊天接口（AI对话）
	-- GET /device/chat?robot_code=xxx&channel_num=n&phone=xxx&ask=xxx
	device_chat_url = api_base_url .. "/device/chat",



	------群发助手群发接口-------
	-- 获取通道下单个任务
	-- robotCode: 机器人编码
	-- channelNum: 通道编号
	-- sendStatus: 发送状态，默认0(待发送)
	-- 返回：tables数组(phone列表) 或 nil
	mass_hlper_send_record_url = api_base_url .. "/api/mass_send/records/by_channel",

	-- 获取群发任务
	-- 参数: robotCode, channelNum (GET)
	mass_helper_send_send_url = api_base_url .. "/api/mass_send/send",

	-- 发送消息到ID (群发助手流程)
	-- 参数: robotCode, channelNum (GET)
	mass_send_send_to_id_url = api_base_url .. "/api/mass_send/send_to_id",

	-- 获取群发任务 (通用)
	-- 参数: robotCode, channelNum (GET)
	mass_send_task_url = api_base_url .. "/api/mass_send/task",

	-- 更新群发状态（POST JSON: {"batch_no": "...", "state": 1}）
	mass_helper_updateStatus_url = api_base_url .. "/api/mass_send/update_send_status",

	-- 群发全部好友-逐屏上报记录接口
	-- POST JSON: {"task_id":"...", "sub_task_id":"...", "robot_channel_id":111, "records":[{"msg":"...", "send_status":1}]}
	mass_send_device_records_url = api_base_url .. "/api/mass_send/device/records",

	------标签任务接口-------
	-- 读取单条标签任务 GET
	tag_task_read_url = api_base_url .. "/api/tag_task/read",
	-- 更新标签任务完成状态 POST
	tag_task_update_status_url = api_base_url .. "/api/tag_task/update_status",
	-- 标签任务下发到设备 POST
	tag_channel_send_to_device_url = api_base_url .. "/api/tag_channel/send_to_device",

	------设备资源收藏同步接口-------
	-- 获取待同步到微信收藏的资源文件 GET
	-- 参数: robot_code(string) / channel_num(int 1~5)
	pending_sync_url = api_base_url .. "/device/resource/pending_sync",
	-- 更新通道资源收藏状态 POST
	-- 参数: robot_code(string) / channel_num(int 1~5) / resource_ids(int[])
	update_sync_status_url = api_base_url .. "/device/resource/update_sync_status",
	-- 发送待处理收藏信息到ID GET
	-- 参数: resource_channel_id(int) 通道资源ID
	resource_send_url = api_base_url .. "/device/resource/send",

	------朋友圈任务接口-------
	-- 获取朋友圈任务 GET
	-- 参数: robot_channel_id(int)
	moments_task_read_url = api_base_url .. "/device/moments/tasks/read",
	-- 发送朋友圈内容 POST
	-- 参数: {task_id: int}  每次发送2条，循环调用直到remaining_count=0
	moments_send_url = api_base_url .. "/device/moments/send",
	-- 标记朋友圈任务完成 POST
	-- 参数: {task_id: int, task_status: 2}
	moments_task_status_url = api_base_url .. "/device/moments/task/status",

	------任务中心统一任务轮询接口------
	-- GET 参数: robot_code, robot_channel_num
	-- 返回: 任务队列 [{batch_no, task_type, task_id, payload, ...}]
	task_poll_url = wx_platform_url .. "/api/taskcenter/task-queue/poll",

	-- 更新通道微信ID POST
	-- 参数: robot_code, channel_num, channel_wechat_id
	update_wechat_id_url = api_base_url .. "/device/channel/update_wechat_id",

	------主动干预话术接口------
	-- 获取待干预消息 GET
	-- 参数: robot_code(string), channelNum(int)
	-- 返回: {success, data: {messages: [{msg_id, phone, msg, uid, ...}], total, sent_count, ...}}
	manual_intervention_url = api_base_url .. "/device/manual/intervention",

	-- 更新干预消息状态 POST
	-- 传参: {msg_id: "5863,5864"(string,逗号分隔), state: 1(int)}
	manual_update_msg_state_url = api_base_url .. "/device/manual/update_msg_state",

	------朋友圈发布-相册选图坐标------
	-- 3列网格，从上到下、从左到右排列
	moments_album_config = {
		images = {
			{x = 261, y = 350},   -- 第1张  第一行1
			--476,353
			{x = 476, y = 353},   -- 第2张  第一行2
			-- 695,352
			{x = 695, y = 352},   -- 第3张  第一行3
			--906,352
			{x = 906, y = 352},   -- 第4张  第一行4
			--259,575
			{x = 259, y = 575},   -- 第5张  第二行1
			-- 476,572
			{x = 476, y = 572},   -- 第6张  第二行2
			-- 695,573
			{x = 695, y = 573},  -- 第7张  第二行3
			-- 906,572
			{x = 906, y = 572},  -- 第8张  第二行4
			-- 261,789
			{x = 261, y = 789},  -- 第9张  第三行1
		},
		--261,354
		video = {x = 261, y = 354},  -- 视频默认位置（第二行中间）
	},

	is_send_api = True,    

	-- OCR优化识别参数
	recognition = {
		similarity = 0.75,    -- 降低相似度要求
		ocr_confidence = 0.3, -- OCR置信度阈值
		fast_mode = true      -- 启用快速模式
	},

	-- 时间优化参数 sleep 时间统一 暂时还未做相应修改
	timing = {
		short_wait = 300,       -- 短等待
		medium_wait = 800,      -- 中等待
		long_wait = 1500,       -- 长等待
		swipe_delay = 600       -- 滑动延迟
	},
	
	tomato_ocr = {
		key = "20P52FKTVHB1TSZEHKOU3DU6XHBG16FY|eBKkzCyf5JhZz5XzhCmWpEem", -- 授权码
		img_path="/mnt/shared/Pictures/",
	},

	-- 微信误识别点击的列表 腾讯新间ocr误识别情况处理
	wx_ignore_list = {"公众号", "服务号", "腾讯新闻", "微信团队", "微信运动","腾讯新间","服务通知","微信支付"},

	-- ******************************** 修改配置 ********************************
	--[[
		备注页：
			机器编号：城市-公司-项目- 机器编号
			例如：HF-AT-1-001
			机械臂对应ID号（一控三）：
			机械臂编号：HF-AT-1-001
			安团大脑测试1：100129658
			安团大脑测试2：100124991
			安团大脑测试3：100130440
	]]
	-- 打包数据
	
	current_machine_code = "TEST-AT-1-002",
	current_id_number = "100129658",

	-- 更新好友状态接口
	id_wx_ai_api_url = api_base_url .. "/api/upstates",
	-- 小区更新好友信息备注（保留）
	community_upuser_url = api_base_url .. "/api/community/upUserState",
	project = 1,
	
	-- 加好友操作频繁提示词
	add_friend_frequent_operation = "操作过于频繁",
	-- 风险验证提示词
	add_friend_check_operation = "当前账号存在安全风险",
	-- ID 聊天中转消息
	id_customer = {
		customer_1 = "发消息",
		customer_2 = "发消息",
		customer_3 = "发消息",
		customer_4 = "发消息",
		customer_5 = "发消息",
	},

	id_customer_add = {
		customer_1 = "加好友",
		customer_2 = "加好友",
		customer_3 = "加好友",
		customer_4 = "发消息",
		customer_5 = "发消息"
	},
	id_client_id = {
		client_id_1 = 100124991,
		clinet_id_2 = 100130440,
		client_id_3 = 100130440,
		client_id_4 = 100130440,
		client_id_5 = 100130440,
	},

	-- 智能AI客服发送消息配置
	id_ai_project_config = {
		name = "发消息",
		logo = "id_yifang_logo1.png",
		mark = "企业公告",
		mark1 = "通讯录好友",
		receive_name = "加好友",
		--receive_name = "张瑜",
	},
	-- ******************************** 修改配置 ********************************
	-- 不同手机 按键位置 配置
	meta30_config = {
		-- ID下列表查找name范围
		id_list_pos = {--249,415,408,1768
			x1 = 249,
			y1= 415,
			x2 = 408,
			y2 = 1768,
		},
		--微信/ID 详情返回列表按钮位置
		ret_list_bt_pos ={
			x = 119,
			y = 256,
			offSetX = 10,
			offsetY = 10,
			
		},
	},
	-- 无红点·通知时默认检测wx列表的消息类型
	wx_nored_check = {
		--msg_pattern_1 ="我是安团客服",
		msg_pattern_2 = "我通过了你的朋友验证请求，现在",
		msg_pattern_3 = "你已添加了",
		msg_pattern_4 = "我是滁州安团家博会客服"
	},
	--手机号格式
	phone_pattern = "1[3456789]%d%d%d%d%d%d%d%d%d",
	phone_remark_default = "添加备注",
	robot_code = robot_code,
	-- 日志配置
	log_config = {
		debug = false,
		switch = true,
		write_log_api_url = "http://192.168.1.201:8095/api/log/upload" --上传日志接口 post
		
	},
	--主控配置
	main_control_config = {
		cycle_state = true,
		multi_control_switch = 0,--多控开关
		tapPoints = {
			{x = 90, y = 2075, name = "主控1"},
			{x = 190, y = 2075, name = "主控2"},
			{x = 290, y = 2075, name = "主控3"},
			{x = 390, y = 2075, name = "主控4"},
			{x = 490, y = 2075, name = "主控5"}
		},
		loopInterval = 1000,  -- 循环间隔时间(ms)
		countdownTime = 10,     -- 倒计时结束时间(秒)
	},
	not_allow_add_friend_config = {
		msg_pattern_1 = "当前账号存在安全风险",
		msg_pattern_2 = "该用户不存在",
		msg_pattern_3 = "被搜账号状态异常"
	}
	
	
}
