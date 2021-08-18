require('await')

-- 范例中虽为同步回调（因为lua本身没有异步回调的方法），但实际运用时应换成第三方提供的异步回调的方法
function asyncCall(data, callback)
    callback(data)
end

-- 将回调形式的异步方法转成返回Promise的异步方法
function asyncPromise(data)
    return Promise(function(resolve)
        asyncCall(data, resolve)
    end)
end

subProcess = async(
    function(a)
        print('Sub-process', a)
        -- assert(a < 3, '用于测试出现异常时的情况')
        print('wait for some asynchronous process to finish')
        local result = await(asyncPromise(a))
        print('asynchronous process done')
        return '[' .. result .. ']'
    end
)

mainProcess = async(
    function(n)
        local subs = {}
        for i = 1, n do
            table.insert(subs, subProcess(i))
        end
        local results = await(Promise.all(subs))
        local str = ''
        for _, v in ipairs(results) do
            str = str .. v[1]
        end
        return n, str
    end
)

mainProcess(5):next(
    function(...)
        print('Result is', ...)
        return ...
    end
):catch(
    function(error)
        print('Error occured:', error)
        return error
    end
):finally(
    function(...)
        print('finally:', ...)
    end
)
