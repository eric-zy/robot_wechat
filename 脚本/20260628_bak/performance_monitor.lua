local monitor = {
    start_time = 0,
    operations = {},
    total_operations = 0
}

-- 开启计时
function monitor.start()
    monitor.start_time = os.time()
	monitor.operations = {}
	monitor.total_operations = 0
end

-- 添加流程操作
function monitor.record(operation, duration)
    monitor.operations[operation] = (monitor.operations[operation] or 0) + duration
    monitor.total_operations = monitor.total_operations + 1
end

-- 性能报告，监测每个阶段的试运行时间，方便更好的优化调整
function monitor.report()
    local total_time = os.time() - monitor.start_time
    print("=== 性能报告 ===")
    print(string.format("总运行时间: %d 秒", total_time))
    print(string.format("总操作次数: %d", monitor.total_operations))

    for op, time in pairs(monitor.operations) do
        print(string.format("%s: %d 秒", op, time))
    end
end

return monitor