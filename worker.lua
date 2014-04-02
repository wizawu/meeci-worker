#!/usr/bin/luajit

local io = require("io")
local os = require("os")
local string = require("string")
local http = require("socket.http")
local json = require("dkjson")
local memcache = require("memcached")
local nonblock = require("nonblock")

-- check effective uid
if io.popen("whoami"):read("*l") ~= "root" then
    print("Need to be root.")
    os.exit(1)
end

-- retrieve url from environment
local meeci_host = os.getenv("MEECI_HOST")
if not meeci_host then
    print("MEECI_HOST is not defined.")
    os.exit(2)
end

local meeci_http = "http://" .. meeci_host
local meeci_ftp = "ftp://" .. meeci_host .. "/meeci"
local mc = memcache.connect(meeci_host, 11211)

--< function definitions
function fwrite(fmt, ...)
    return io.write(string.format(fmt, ...))
end

function sleep(n)
    os.execute("sleep " .. tonumber(n))
end

-- luajit os.execute returns only the exit status
function execute(cmd)
    print(cmd)
    if _G.jit then
        return os.execute(cmd) == 0
    else
        return os.execute(cmd)
    end
end

-- return content of a file
function cat(file)
    local stream = io.popen("cat " .. file)
    local result = stream:read("*a")
    stream:close()
    return result
end

-- receive a task from meeci-web
function receive()
    local body, code = http.request(meeci_http .. "/task")
    if code == 200 then
        return json.decode(body)
    end
end

function log(task)
    fwrite("[%s] %s %d: ", os.date(), task.type, task.id)
    if task.type == "build" then
        io.write(task.url .. '\n')
    else
        io.write(task.container .. '\n')
    end
end

-- download files in /meeci/container
function wget(file)
   local cmd = "wget -N " .. meeci_ftp .. "/containers/" .. file
   return execute(cmd)
end

-- extract a container into 'container' directory
-- [args] container: container name with suffix .bz2
function tarx(container)
    execute("rm -rf container")
    return execute("tar xf " .. container)
end

-- download a shallow repository and its build script
function gitclone(task)
    local dir = "container/opt/" .. task.repository
    if not execute("mkdir -p " .. dir) then
        return false
    end
    local cmd = "git clone --depth 30 -b %s %s %s"
    cmd = string.format(cmd, task.branch, task.url, dir)
    if not execute(cmd) then
        return false
    end
    cmd = "cd " .. dir .. "; git checkout " .. task.commit
    if not execute(cmd) then
        return false
    end
    local url = meeci_http .. "/scripts/" .. task.id
    cmd = "wget -O " .. dir .. "/meeci_build.sh " .. url
    return execute(cmd)
end

-- inform meeci-web the result
function report(task, start, stop, code)
    local cmd = string.format(
        "wput /var/lib/meeci/worker/logs/%s/%d.log " ..
        meeci_ftp .. "/logs/%s/%d.log",
        task.type, task.id, task.type, task.id
    )
    execute(cmd);
    local str = json.encode({
        user   = task.user,
        type   = task.type,
        id     = task.id,
        start  = start,
        stop   = stop,
        exit   = code,
        container = task.container
    })
    mc:set(string.sub(task.type, 1, 1) .. ":" .. task.id, str)
    local path = string.format(
        "/finish/%s/%d", task.type, task.id
    )
    http.request(meeci_http .. path, tostring(code))
    print("POST " .. meeci_http .. path) 
end

-- compress and upload a new container
-- [args] container: container name with suffix .bz2
function upload(container)
    execute("rm -f container/meeci_exit_status")
    -- TODO: file changed as we read it
    execute("tar jcf container.bz2 container")
    local url = meeci_ftp .. "/containers/" .. container
    if execute("wput container.bz2 " .. url) then
        os.remove("container.bz2")
        return true
    end
end

-- run a build task or create a container
function build(task)
    local dir, script
    if task.type == "build" then
        dir = "/opt/" .. task.repository
        script = "meeci_build.sh"
    else
        dir = "/root"
        script = task.container .. ".sh"
    end
    local cmd = "cd %s; bash %s; echo -n $? > /meeci_exit_status"
    cmd = string.format(cmd, dir, script)
    cmd = string.format("systemd-nspawn -D ./container bash -c '%s'", cmd)

    -- file log
    local logdir = "/var/lib/meeci/worker/logs"
    local log = string.format("%s/%s/%d.log", logdir, task.type, task.id)
    log = io.open(log, 'a')
    -- memcache log
    local key = string.sub(task.type, 1, 1) .. "#" .. tostring(task.id)
    mc:set(key, "")

    local start = os.time()
    local stream, fd = nonblock:popen(cmd)

    while true do
        local n, line = nonblock:read(fd)
        if n == 0 then break end
        log:write(line)
        mc:append(key, line)
        if n < 1000 then sleep(1) end
        -- TODO: 10min and 60min limit
    end

    log:close()
    nonblock:pclose(stream)
    local stop = os.time()
    local code = tonumber(cat("container/meeci_exit_status"))

    if task.type == "build" then
        report(task, start, stop, code)
        return true
    else
        if (not upload(task.user .. "/" .. task.container .. ".bz2")) then
            code = 21
        end
        report(task, start, stop, code)
        return code == 0
    end
end
-->

local test = os.getenv("TEST") and true or false

if not test and not wget("meeci-minbase.bz2") then
    print("Cannot wget meeci-minbase.bz2")
    os.exit(3)
end

-- main loop --
local failure, idle = 0, os.time()
while not test do
    local done = false
    local task = receive()
    if task then
        log(task)
        if task.type == "build" then
            if not wget(task.user .. "/" .. task.container .. ".bz2") then
                goto END_TASK
            end
            if not tarx(task.container .. ".bz2") then
                goto END_TASK
            end
            os.remove(task.container .. ".bz2")
            if not gitclone(task) then
                goto END_TASK
            end
        else
            if not tarx("meeci-minbase.bz2") then
                goto END_TASK
            end
            local script = task.container .. ".sh"
            if not wget(task.user .. "/" .. script) then
                goto END_TASK
            end
            os.rename(script, "container/root/" .. script)
        end
        done = build(task)

        ::END_TASK::
        execute("rm -rf container")
        if done then
            fwrite("[%s] SUCCESS\n", os.date())
            if failure > 0 then
                failure = failure - 1
            end
        else
            fwrite("[%s] ERROR\n", os.date())
            failure = failure + 1
            if failure == 10 then
                fwrite("Worker stopped because of too many failures.\n")
                os.exit(10)
            end
        end
        idle = os.time()
    end

    -- TODO: sleep(1)
    sleep(10)
    if (os.time() - idle) % 600 == 0 then
        local m = math.floor((os.time() - idle) / 60)
        fwrite("[%s] idle for %d min\n", os.date(), m)
    end
end
