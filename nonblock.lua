local ffi = require("ffi")

local module = {}

ffi.cdef[[
    void *popen(const char *command, const char *type);
    int pclose(void *stream);
    int fileno(void *stream);
    int fcntl(int fd, int cmd, int flag);
    int read(int fd, void *buf, int count);
]]

local F_SETFL = 4
local O_NONBLOCK = 2048

module.buffer = ffi.new("uint8_t[?]", 1024)

module.popen = function(self, cmd)
    local stream = ffi.C.popen(cmd, "r")
    local fd = ffi.C.fileno(stream)
    ffi.C.fcntl(fd, F_SETFL, O_NONBLOCK)
    return stream, fd
end

module.read = function(self, fd)
    ffi.fill(self.buffer, 1024)
    local n = ffi.C.read(fd, self.buffer, 1023)
    return n, ffi.string(self.buffer)
end

module.pclose = function(self, stream)
    ffi.C.pclose(stream)
end

return module
