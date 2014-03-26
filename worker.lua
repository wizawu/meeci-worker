#!/usr/bin/lua

require("dkjson")
require("memcached")

local io = require("io")
local os = require("os")
local string = require("string")
local http = require("socket.http")

-- check effective uid
if io.popen("whoami"):read("*l") ~= "root" then
    print("Start the worker as root")
    os.exit(1)
end

-- retrieve url from environment
local meeci_host = os.getenv("MEECI_HOST")
if not meeci_host then
    print("MEECI_HOST is not defined")
    os.exit(2)
end
local meeci_http = "http://" .. meeci_host
local meeci_ftp = "ftp://" .. meeci_host

--< function definitions
function sleep(n)
    os.execute("sleep " .. tonumber(n)) 
end

function fwrite(fmt, ...)
    return io.write(string.format(fmt, ...))
end

function accept()
    local body, code = http.request("http://" .. meeci_host .. "/task")
    if code == 200 then
        return json.decode(body)
    else
        return nil
    end
end

function log(task)
    fwrite("[%s] %s %d: ", os.date(), task.type, task.id)
    if task.type == "build" then
        os.write(task.url .. '\n')
    else
        os.write(task.target .. '\n')
    end
end

-- download container and 
function download(container)
    local dir = "ftp://" .. meeci_host .. "/meeci/container/"
    local url = dir .. container .. ".bz2"
    if os.execute("wget -O container.bz2 " .. url) then
        url = dir .. container .. ".sh"
        if os.execute("wget -O script.sh " .. url) then
            return true
        end
    end
    return false
end

-- compress and upload a new container
-- [args] container: container name with suffix .bz2
function upload(container)
    if os.execute("tar jcf container.bz2 -C container .") then
        local url = meeci_ftp .. "/meeci/containers/" .. container
        if os.execute("wput container.bz2 " .. url) then
            return true
        end
    end
end

-- download a shallow repository and its build script 
function gitclone(task)
    local dir = "container/opt/" .. task.repository
    if not os.execute("mkdir -p " .. dir) then
        return false
    end
    if os.execute("git clone --depth 1 " .. task.url .. " " .. dir) then
        local url = meeci_http .. "/scripts/" .. task.id 
        return os.execute("wget -O " .. dir .. "/meeci_build.sh " .. url)
    end
end
-->

-- main loop of worker
local failure = 0
while true do
    local done = false
    local task = accept()
    if task then
        log(task)
        if task.type == "build" then
            if not wget(task.container .. ".bz2") then
                goto NETX_TASK
            end
        else
            if not wget("meeci-minbase.bz2") then
                goto NETX_TASK
            end
            if not wget(task.container .. ".sh") then
                goto NETX_TASK
            end
            if not create(task.container) then
                goto NETX_TASK
            end
        end
    end
    done = true

    ::NETX_TASK::
    if done then
        fwrite("[%s] succeed\n", os.date())
        if failure > 0 then
            failure = failure - 1
        end
    else
        fwrite("[%s] fail\n", os.date())
        failure = failure + 1
        if failure == 10 then
            os.exit(10)
        end
    end
    sleep(1)
end
