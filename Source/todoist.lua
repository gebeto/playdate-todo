-- Todoist REST API v1 client for Playdate.
--
-- All networking is asynchronous. Because playdate.network.https.new() and
-- requestAccess() yield a coroutine to show the permission dialog, they must NOT
-- be called from input handlers or system-menu callbacks -- only from startup or
-- the playdate.update() context. So this module queues jobs and drains them from
-- todoist.update(), which main.lua calls every frame.
--
-- Reads the global TODOIST_TOKEN (set in config.lua).

todoist = todoist or {}

local HOST <const> = "api.todoist.com"
local BASE <const> = "/api/v1"
local ACCESS_REASON <const> = "Sync your todos with Todoist"

-- Internal state
local jobQueue = {}         -- FIFO of pending jobs
local inFlight = false      -- true while a request is open
local accessRequested = false
local lastError = nil

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function networkingAvailable()
    return playdate.network ~= nil and playdate.network.https ~= nil
end

local function enqueue(method, path, body, cb)
    jobQueue[#jobQueue + 1] = { method = method, path = path, body = body, cb = cb }
end

-- Opens a connection for `job` and wires up callbacks. Called only from update().
local function startJob(job)
    if not networkingAvailable() then
        lastError = "networking unavailable (needs Playdate OS 2.7+)"
        if job.cb then job.cb(false, nil, nil) end
        return
    end

    inFlight = true

    local conn = playdate.network.https.new(HOST, nil, ACCESS_REASON)
    if not conn then
        inFlight = false
        lastError = "could not open connection"
        if job.cb then job.cb(false, nil, nil) end
        return
    end

    local buf = {}
    local finished = false

    local function drain()
        while conn:getBytesAvailable() > 0 do
            local chunk = conn:read()
            if not chunk or #chunk == 0 then break end
            buf[#buf + 1] = chunk
        end
    end

    local function finalize()
        if finished then return end
        finished = true
        drain()

        local status = conn:getResponseStatus()
        local body = table.concat(buf)

        local data = nil
        if #body > 0 then
            local ok, decoded = pcall(json.decode, body)
            if ok then data = decoded end
        end

        local success = status ~= nil and status >= 200 and status < 300
        if success then
            lastError = nil
        else
            lastError = "HTTP " .. tostring(status) .. " (" .. tostring(conn:getError()) .. ")"
        end

        conn:close()
        inFlight = false
        if job.cb then job.cb(success, data, status) end
    end

    -- Read data as it arrives so large responses don't stall the read buffer.
    conn:setRequestCallback(drain)
    conn:setRequestCompleteCallback(finalize)
    conn:setConnectionClosedCallback(finalize)

    local headers = {
        ["Authorization"] = "Bearer " .. (TODOIST_TOKEN or ""),
        ["Content-Type"] = "application/json",
        ["Accept"] = "application/json",
    }

    local ok, err
    if job.method == "GET" then
        ok, err = conn:get(job.path, headers)
    else
        ok, err = conn:post(job.path, headers, job.body or "")
    end

    if not ok then
        finished = true
        lastError = err or "request failed to start"
        conn:close()
        inFlight = false
        if job.cb then job.cb(false, nil, nil) end
    end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

-- Trigger the network-permission dialog once, ahead of any request. Safe to call
-- every frame; only acts the first time. Must run from update() context.
function todoist.requestAccessOnce()
    if accessRequested then return end
    accessRequested = true
    if networkingAvailable() and playdate.network.http and playdate.network.http.requestAccess then
        playdate.network.http.requestAccess(HOST, 443, true, ACCESS_REASON)
    end
end

-- Drain the job queue. Call once per frame from playdate.update().
function todoist.update()
    if inFlight then return end
    if not accessRequested then return end
    local job = table.remove(jobQueue, 1)
    if job then startJob(job) end
end

-- Last error string (or nil). Useful for a UI indicator.
function todoist.getError()
    return lastError
end

-- GET /tasks -> cb(ok, data, status); data.results is the array of active tasks.
function todoist.fetchTasks(cb)
    enqueue("GET", BASE .. "/tasks", nil, cb)
end

-- POST /tasks -> cb(ok, data, status); data is the created task object (data.id).
function todoist.createTask(title, cb)
    local body = json.encode({ content = title })
    enqueue("POST", BASE .. "/tasks", body, cb)
end

-- POST /tasks/{id}/close
function todoist.closeTask(id, cb)
    enqueue("POST", BASE .. "/tasks/" .. tostring(id) .. "/close", "", cb)
end

-- POST /tasks/{id}/reopen
function todoist.reopenTask(id, cb)
    enqueue("POST", BASE .. "/tasks/" .. tostring(id) .. "/reopen", "", cb)
end
