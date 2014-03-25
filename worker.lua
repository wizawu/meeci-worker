#!/usr/bin/lua

require("dkjson")
require("memcached")

local http = require("socket.http")
local os = require("os")

local meeci_web = os.getenv("MEECI_WEB")

if not meeci_web then
    print("MEECI_WEB is not defined")
    os.exit(1)
end

function sleep(n)
    os.execute("sleep " .. tonumber(n)) 
end

function accept_task()
    body, code = http.request(meeci_web + "/task") 
    if code == 200 then
        return json.decode(body)
    else
        return nil
end

while true do
    task = accept_task()
    if task then

    end
    sleep(1)
end
