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

local meeci_http = "http://" .. meeci_host .. ":80"
local meeci_ftp = "ftp://" .. meeci_host .. "/meeci"
local mc = memcache.connect(meeci_host, 11211)

--<< function definitions

local strformat = string.format

function fwrite(fmt, ...)
    return io.write(strformat(fmt, ...))
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
    fwrite("[%s] %s %s: ", os.date(), task.type, task.strid)
    if task.type == "build" then
        io.write(task.url .. '\n')
    else
        fwrite("%s@%s\n", task.container, task.user)
    end
end

-- download files in /meeci/container
function wget(file)
   local cmd = "wget -N " .. meeci_ftp .. "/containers/" .. file
   return execute(cmd)
end

-- extract a container into 'container' directory
-- [args] container: container name with suffix .tgz
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
    local https_url = "https://github.com/" .. task.owner ..
                      "/" .. task.repository .. ".git"
    cmd = strformat(cmd, task.branch, https_url, dir)
    if not execute(cmd) then
        return false
    end
    cmd = "cd " .. dir .. "; git checkout " .. task.commit
    if not execute(cmd) then
        return false
    end
    local url = meeci_http .. strformat(
        "/scripts/%s/%s/%s/%d",
        task.user, task.repository, task.owner, task.host
    )
    cmd = "wget -O " .. dir .. "/meeci_build.sh " .. url
    return execute(cmd)
end

-- inform meeci-web the result
function report(task, start, stop, code)
    local cmd = strformat(
        "wput /var/lib/meeci/worker/logs/%s/%s.log " ..
        meeci_ftp .. "/logs/%s/%s.log",
        task.type, task.strid, task.type, task.strid
    )
    execute(cmd);
    local str = json.encode({
        user   = task.user,
        start  = start,
        stop   = stop,
        exit   = code,
        container = task.container
    })
    mc:set(task.type:sub(1, 1) .. ":" .. task.strid, str)
    local url = meeci_http .. strformat(
        "/finish/%s/%s", task.type, task.strid
    )
    print("Exit status " .. code)
    http.request(url, tostring(code))
    print("POST " .. url)
end

-- compress and upload a new container
-- [args] container: container name with suffix .tgz
function upload(container)
    execute("rm -f container/meeci_exit_status")
    -- TODO: file changed as we read it
    execute("tar zcf container.tgz container")
    local url = meeci_ftp .. "/containers/" .. container
    if execute("wput container.tgz " .. url) then
        os.remove("container.tgz")
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
    cmd = strformat(cmd, dir, script)
    cmd = strformat("systemd-nspawn -D ./container bash -c '%s'", cmd)

    -- file log
    local logdir = "/var/lib/meeci/worker/logs"
    local log = strformat("%s/%s/%s.log", logdir, task.type, task.strid)
    log = io.open(log, 'a')
    -- memcache log
    local key = task.type:sub(1, 1) .. "#" .. tostring(task.strid)
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

    if task.type == "container" then
        if not upload(task.user .. "/" .. task.container .. ".tgz") then
            code = 21
        end
    end
    report(task, start, stop, code)
    return code == 0
end

-->>

if not wget("meeci-minbase.tgz") then
    print("Cannot wget meeci-minbase.tgz")
    os.exit(3)
end

-- main loop --
local failure = 0
local sleep_intv = 10
local idle = os.time()

while not test do
    local done = false
    local task = receive()

    if task then
        log(task)
        if task.type == "build" then
            if not wget(task.user .. "/" .. task.container .. ".tgz") then
                goto END_TASK
            end
            if not tarx(task.container .. ".tgz") then
                goto END_TASK
            end
            os.remove(task.container .. ".tgz")
            if not gitclone(task) then
                goto END_TASK
            end
        else
            if not tarx("meeci-minbase.tgz") then
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
    else
        -- while there is no task
        sleep(sleep_intv)
    end

    if (os.time() - idle) % 600 < sleep_intv then
        local m = math.floor((os.time() - idle) / 60)
        fwrite("[%s] idle for %d min\n", os.date(), m)
    end
end
