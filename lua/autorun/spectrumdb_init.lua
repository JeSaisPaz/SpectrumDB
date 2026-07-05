--[[
     _______________________________________________________
    /                                                       \
   |   ___________________________________________________   |
   |  |                                                   |  |
   |  |   ___               _                             |  |
   |  |  / __|_ __  ___  __| |_ _ _ _  _ _ __             |  |
   |  |  \__ \ '_ \/ -_)/ _|  _| '_| || | '  \            |  |
   |  |  |___/ .__/\___|\__|\__|_|  \_,_|_|_|_|  ___      |  |
   |  |      |_|                                |   \     |  |
   |  |                                         | D  |    |  |
   |  |     ==========================*         | B  |    |  |
   |  |    (White Light)              | \       |___/     |  |
   |  |                               |  \___             |  |
   |  |                               |      \_______     |  |
   |  |                                \  RED        \    |  |
   |  |                                 \  ORANGE     \   |  |
   |  |                                  \  YELLOW     \  |  |
   |  |                                   \  GREEN      \ |  |
   |  |                                    \  BLUE      / |  |
   |  |                                     \ INDIGO   /  |  |
   |  |                                      \ VIOLET /   |  |
   |  |                                       '------'    |  |
   |  |                                                   |  |
   |  |___________________________________________________|  |
   \________________________________________________________/
--]]

if SERVER then
    SpectrumDB = SpectrumDB or {}

    -- Autoloader for SpectrumDB
    local files = {
        "spectrumdb/core.lua",
        "spectrumdb/driver_sqlite.lua",
        "spectrumdb/driver_mysqloo.lua",
        "spectrumdb/query_builder.lua",
        "spectrumdb/schema_migrator.lua",
        "spectrumdb/migrator.lua",
        "spectrumdb/model.lua"
    }

    for _, file in ipairs(files) do
        include(file)
    end

    if MsgC and Color then
        local c_cyan   = Color(0, 255, 255)
        local c_white  = Color(255, 255, 255)
        local c_red    = Color(255, 0, 0)
        local c_orange = Color(255, 127, 0)
        local c_yellow = Color(255, 255, 0)
        local c_green  = Color(0, 255, 0)
        local c_blue   = Color(0, 191, 255)
        local c_purple = Color(186, 85, 211)

        MsgC(c_cyan, "\n  ___               _                            \n")
        MsgC(c_cyan, "  / __|_ __  ___  __| |_ _ _ _  _ _ __            \n")
        MsgC(c_cyan, "  \\__ \\ '_ \\/ -_)/ _|  _| '_| || | '  \\  ___      \n")
        MsgC(c_cyan, "  |___/ .__/\\___|\\__|\\__|_|  \\_,_|_|_|_| |   \\     \n")
        MsgC(c_cyan, "      |_|                                | D |    \n")
        MsgC(c_white, "     ==========================*") MsgC(c_cyan, "         | B |    \n")
        MsgC(c_white, "    (White Light)              | \\") MsgC(c_cyan, "       |___/     \n")
        MsgC(c_white, "                               |  \\___            \n")
        MsgC(c_white, "                               |      \\_______    \n")
        MsgC(c_red, "                                \\  RED        \\   \n")
        MsgC(c_orange, "                                 \\  ORANGE     \\  \n")
        MsgC(c_yellow, "                                  \\  YELLOW     \\ \n")
        MsgC(c_green, "                                   \\  GREEN      \\\n")
        MsgC(c_blue, "                                    \\  BLUE      /\n")
        MsgC(c_purple, "                                     \\ VIOLET   / \n")
        MsgC(c_purple, "                                      '--------'  \n\n")
        MsgC(c_cyan, "[SpectrumDB] Loaded successfully (Database ORM initialized).\n\n")
    else
        print("[SpectrumDB] Loaded successfully (Database ORM initialized).")
    end
end
