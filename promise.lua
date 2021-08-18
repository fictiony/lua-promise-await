local M = {
    PENDING = 'pending',
    FULFILLED = 'fulfilled',
    REJECTED = 'rejected'
}
M.__index = M

local function safeCall(func, resolve, reject, ...)
    local result = {pcall(func, ...)}
    if result[1] then
        if resolve then
            resolve(unpack(result, 2))
        end
    else
        if reject then
            reject(result[2])
        end
    end
end

local function resolveNext(promise, ...)
    if promise.state == M.PENDING then
        promise.state = M.FULFILLED
        promise.result = {...}
        for _, v in ipairs(promise.nexts) do
            v.resolve(...)
        end
    end
end

local function rejectNext(promise, error)
    if promise.state == M.PENDING then
        promise.state = M.REJECTED
        promise.result = error
        if promise.throwUncaught and #promise.nexts == 0 then
            assert(nil, 'Uncaught exception in promise process:\n' .. tostring(error))
        end
        for _, v in ipairs(promise.nexts) do
            v.reject(error)
        end
    end
end

-- resolve a Promise means resolve/reject the result of the promise
local function deferResolve(resolve, reject)
    return function(...)
        local result = {...}
        local promise = result[1]
        if #result == 1 and getmetatable(promise) == M then
            promise:next(resolve, reject)
        else
            resolve(...)
        end
    end
end

-- excutor = function(resolve, reject) ... end | nil
function M.new(excutor)
    local self = setmetatable({}, M)

    self.state = M.PENDING
    self.result = nil
    self.nexts = {}
    self.reject = function(error)
        rejectNext(self, error)
    end
    self.resolve = deferResolve(function(...)
        resolveNext(self, ...)
    end, self.reject)

    if excutor then
        safeCall(excutor, nil, self.reject, self.resolve, self.reject)
    end
    self.throwUncaught = true

    if self.state == M.REJECTED and #self.nexts == 0 then
        assert(nil, 'Uncaught exception in promise init:\n' .. tostring(self.result))
    end

    return self
end

-- allow using Promise() instead of Promise.new()
setmetatable(M, {
    __call = function(t, ...)
        return M.new(...)
    end
})

-- onResolve = function(...) ... return <Promise>|... end | nil
-- onReject = function(error) ... return <Promise>|... end | nil
function M:next(onResolve, onReject)
    local promise = M()
    local resolve = promise.resolve
    local reject = promise.reject
    table.insert(self.nexts, promise)

    if onResolve then
        promise.resolve = function(...)
            safeCall(onResolve, resolve, reject, ...)
        end
        promise.resolve = deferResolve(promise.resolve, reject)
    end
    if onReject then
        promise.reject = function(error)
            safeCall(onReject, resolve, reject, error)
        end
    end

    if self.state == M.FULFILLED then
        promise.resolve(unpack(self.result))
    elseif self.state == M.REJECTED then
        promise.reject(self.result)
    end

    return promise
end

function M:catch(onReject)
    return self:next(nil, onReject)
end

-- onFinally = function(success, ...) ... return <Promise>|... end
function M:finally(onFinally)
    return self:next(
        function(...)
            return onFinally(true, ...)
        end,
        function(error)
            return onFinally(false, error)
        end
    )
end

function M:toString()
    return string.format('Promise {<%s> = %s}', self.state, tostring(self.result))
end

-- onTry = function() ... return <Promise>|... end
function M.try(onTry)
    return M(
        function(resolve, reject)
            safeCall(onTry, resolve, reject)
        end
    )
end

function M.resolve(...)
    local result = {...}
    return M(
        function(resolve, reject)
            resolve(unpack(result))
        end
    )
end

function M.reject(error)
    return M(
        function(resolve, reject)
            reject(error)
        end
    )
end

-- resolve = { {...}, {...}, ... }
-- reject = error
function M.all(promises)
    return M(
        function(resolve, reject)
            local count = #promises
            local results = {}
            for i = 1, count do
                promises[i]:next(
                    function(...)
                        count = count - 1
                        results[i] = {...}
                        if count == 0 then
                            resolve(results)
                        end
                    end,
                    reject
                )
            end
        end
    )
end

-- resolve = ...
-- reject = error
function M.race(promises)
    return M(
        function(resolve, reject)
            for i = 1, #promises do
                promises[i]:next(resolve, reject)
            end
        end
    )
end

-- resolve = { {success, .../error}, {success, .../error}, ... }
-- no reject
function M.allSettled(promises)
    return M(
        function(resolve, reject)
            local count = #promises
            local results = {}
            for i = 1, count do
                promises[i]:finally(
                    function(...)
                        count = count - 1
                        results[i] = {...}
                        if count == 0 then
                            resolve(results)
                        end
                    end
                )
            end
        end
    )
end

-- resolve = ...
-- reject = { error, error, ... }
function M.any(promises)
    return M(
        function(resolve, reject)
            local count = #promises
            local errors = {}
            for i = 1, count do
                promises[i]:next(
                    resolve,
                    function(error)
                        count = count - 1
                        errors[i] = error
                        if count == 0 then
                            reject(errors)
                        end
                    end
                )
            end
        end
    )
end

Promise = M
return M
