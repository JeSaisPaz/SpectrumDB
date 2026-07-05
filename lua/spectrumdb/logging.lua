local Logger = {}
Logger.__index = Logger

local LEVELS = {
    TRACE = 1,
    DEBUG = 2,
    INFO = 3,
    WARN = 4,
    ERROR = 5
}

function Logger.new(config)
    local instance = setmetatable({}, Logger)
    config = config or {}
    instance.level = config.logLevel and LEVELS[string.upper(config.logLevel)] or LEVELS.INFO
    instance.customLogger = config.logger
    return instance
end

function Logger:log(level, levelName, message, traceback)
    if self.level > level then return end
    
    if self.customLogger and type(self.customLogger[string.lower(levelName)]) == "function" then
        self.customLogger[string.lower(levelName)](message, traceback)
    else
        local prefix = "[SpectrumDB] [" .. levelName .. "] "
        if traceback then
            print(prefix .. tostring(message) .. "\n" .. tostring(traceback))
        else
            print(prefix .. tostring(message))
        end
    end
end

function Logger:trace(message) self:log(LEVELS.TRACE, "TRACE", message) end
function Logger:debug(message) self:log(LEVELS.DEBUG, "DEBUG", message) end
function Logger:info(message) self:log(LEVELS.INFO, "INFO", message) end
function Logger:warn(message) self:log(LEVELS.WARN, "WARN", message) end
function Logger:error(message, traceback) self:log(LEVELS.ERROR, "ERROR", message, traceback) end

return Logger
