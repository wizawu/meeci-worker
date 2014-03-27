#!/usr/bin/lua

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
        os.write(task.url .. '\n')
    else
        os.write(task.container .. '\n')
    end
end

-- download files in /meeci/container
function wget(file)
   local cmd = "wget " .. meeci_ftp .. "/containers/" .. file
   return os.execute(cmd)
end

-- extract a container into 'container' directory
-- [args] container: container name with suffix .bz2
function tarx(container)
    os.execute("rm -rf container && mkdir container")
    return os.execute("tar xf " .. container .. " -C container") 
end

-- download a shallow repository and its build script 
function gitclone(task)
    local dir = "container/opt/" .. task.repository
    if not os.execute("mkdir -p " .. dir) then
        return false
    end
    local cmd = "git clone --depth 30 -b %s %s %s"
    cmd = string.format(cmd, task.branch, task.url, dir)
    if not os.execute(cmd) then
        return false
    end
    cmd = "cd " .. dir .. "; git checkout " .. task.commit
    if not os.execute(cmd) then
        return false
    end
    local url = meeci_http .. "/scripts/" .. task.script
    cmd = "wget -O " .. dir .. "/meeci_build.sh " .. url
    return os.execute(cmd)
end

-- inform meeci-web the result
function report(task, start, stop, code)
    local str = json.encode({
        type   = task.type,
        id     = task.id,
        start  = start,
        stop   = stop,
        exit   = code
    })
    mc:set(string.sub(task.type, 1, 1) .. ":" .. task.id, str)
    http.request(meeci_http .. "/finish", tostring(code))
end

-- compress and upload a new container
-- [args] container: container name with suffix .bz2
function upload(container)
    os.execute("rm -f container/meeci_exit_status")
    if os.execute("tar jcf container.bz2 -C container .") then
        local url = meeci_ftp .. "/containers/" .. container
        if os.execute("wput container.bz2 " .. url) then
            os.remove("container.bz2")
            return true
        end
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
    log = io:open(log, 'a')
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
    end

    log:close()
    nonblock:pclose(stream)
    local stop = os.time()
    local code = tonumber(cat("container/meeci_exit_status"))

    report(task, start, stop, code)
    if task.type == "build" then
        return true
    else
        return upload(task.container .. ".bz2")
    end
end
-->

if not wget("meeci-minbase.bz2") then
    print("Cannot wget meeci-minbase.bz2")
    os.exit(3)
end

-- main loop --
local failure = 0
while true do
    local done = false
    local task = receive()
    if task then
        log(task)
        if task.type == "build" then
            if not wget(task.container .. ".bz2") then
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
            if not wget(script) then
                goto END_TASK
            end
            os.rename(script, "container/root/" .. script)
        end
        done = build(task)
    end

    ::END_TASK::
    os.execute("rm -rf container")
    if done then
        fwrite("[%s] succeed\n", os.date())
        if failure > 0 then
            failure = failure - 1
        end
    else
        fwrite("[%s] fail\n", os.date())
        failure = failure + 1
        if failure == 10 then
            fwrite("Worker stopped because of too many failures.\n")
            os.exit(10)
        end
    end
    sleep(1)
end
