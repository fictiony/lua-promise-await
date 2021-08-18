require('promise')

-- for coroutine exception catching
local coRejects = setmetatable({}, {__mode = 'kv'})

local function coReject(co, error)
    local reject = coRejects[co]
    if reject then
        coRejects[co] = nil
        reject(error)
    else
        assert(nil, error)
    end
end

local function arun(co, ...)
    local success, error = coroutine.resume(co, ...)
    if not success then
        -- record coroutine error stack info
        error = debug.traceback(co, error)
    end
    return success, error
end

function async(func)
    return function(...)
        local args = {...}
        return Promise(
            function(resolve, reject)
                local function proc()
                    resolve(func(unpack(args)))
                end
                local co = coroutine.create(proc)
                coRejects[co] = reject
                local success, error = arun(co)
                if not success then
                    coReject(co, error)
                end
            end
        )
    end
end

function await(promise)
    local co, result
    promise:next(
        function(...)
            if co then
                local success, error = arun(co, ...)
                if not success then
                    coReject(co, error)
                end
            else
                result = {...}
            end
        end,
        function(error)
            coReject(co, error)
        end
    )
    if result then
        return unpack(result)
    end
    co = coroutine.running()
    assert(co, 'await should be used in a coroutine')
    return coroutine.yield()
end

return {
    sync = async,
    wait = await
}
