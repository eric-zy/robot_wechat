-- 打开多控开关
function findMoreControllerApp()
	-- 查找多控助手
	local find_app_ret = -1
	local x = -1
	local y = -1
	local maxRetry = 20  -- 最大重试次数
	local retryCount = 0

	while find_app_ret == -1 and retryCount < maxRetry do
		retryCount = retryCount + 1
		-- 尝试打开微信
		find_app_ret, x, y = findImage(0, 0, 0, 0, "多控助手app.png", 0.8)
		print("查找多控助手：", find_app_ret, x, y, "重试次数:", retryCount)

		-- 如果找到助手，跳出循环
		if find_app_ret ~= -1 then
			break
		end

		-- 返回home界面
		local contr_home_ret, home_x, home_y = findImage(0, 0, 0, 0, "contrl_home.png", 0.9)
		if contr_home_ret ~= -1 then
			randomTap(home_x, home_y, 10, 10, "主控手机-点击home")
		end
		sleep(500)
	end

	if find_app_ret == -1 then
		print("查找多控助手失败，已达最大重试次数")
		return false
	end

	-- 打开多控助手
	markPoint(x, y, { debugMode = true })
	randomTap(x, y, 80, 80, "主控手机-点击多控助手")
	sleep(1000)

	-- 检查是否连接
	local find_conn_ret, conn_x, conn_y = findImage(0, 0, 0, 0, "已连接.png", 0.9)
	local connRetry = 0
	local maxConnRetry = 10  -- 最大连接重试次数
	
	while find_conn_ret == -1 and connRetry < maxConnRetry do
		connRetry = connRetry + 1
		local find_un_conn_ret, un_conn_x, un_conn_y = findImage(0, 0, 0, 0, "连接.png", 0.9)
		if find_un_conn_ret ~= -1 then
			randomTap(un_conn_x, un_conn_y, 200, 80, "主控手机-连接")
			sleep(300)
		end
		find_conn_ret, conn_x, conn_y = findImage(0, 0, 0, 0, "已连接.png", 0.9)
		print("检查连接状态:", find_conn_ret, "重试次数:", connRetry)
	end

	if find_conn_ret == -1 then
		print("连接失败，已达最大重试次数")
		return false
	end

	-- 查找进入相机模式
	local find_camera_ret, xj_x, xj_y = findImage(0, 0, 0, 0, "进入相机模式.png", 0.9)
	if find_camera_ret ~= -1 then
		randomTap(xj_x, xj_y, 200, 80, "进入相机模式")
		sleep(100)
	end
	
	return true
end

findMoreControllerApp()
