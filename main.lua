local ffi = require("ffi")

ffi.cdef[[
    typedef struct {
        int id;
        float x, y;
        float vx, vy;
        float angle;
        float major_axis, minor_axis;
        float size;
        int state;
    } TrackpadFinger;

    typedef void (*TrackpadCallback)(int nFingers, const TrackpadFinger* fingers);

    void trackpad_start(TrackpadCallback callback);
    void trackpad_stop();
]]

local trackpad_lib = ffi.load("trackpad")

-- A thread-safe queue to hold the trackpad data.
local touch_queue = {}

local function on_trackpad_data(nFingers, fingers)
    -- This callback runs on a separate thread. It MUST copy the data from the
    -- C-owned pointer into Lua-owned memory before the function returns.
    local frame_data = {}
    for i = 0, nFingers - 1 do
        local c_finger = fingers[i]
        -- Perform a deep copy from the C struct to a new Lua table.
        local lua_finger = {
            id = c_finger.id,
            x = c_finger.x,
            y = c_finger.y,
            vx = c_finger.vx,
            vy = c_finger.vy,
            angle = c_finger.angle,
            major_axis = c_finger.major_axis,
            minor_axis = c_finger.minor_axis,
            size = c_finger.size,
            state = c_finger.state
        }
        table.insert(frame_data, lua_finger)
    end
    -- This is now a table of pure Lua tables, not cdata pointers.
    table.insert(touch_queue, frame_data)
end

-- Keep a reference to the callback to prevent it from being garbage collected
local c_callback = ffi.cast("TrackpadCallback", on_trackpad_data)

function love.load()
    trackpad_lib.trackpad_start(c_callback)
end

function love.update(dt)
    -- Process the queued trackpad data on the main thread.
    while #touch_queue > 0 do
        local frame_data = table.remove(touch_queue, 1)
        for _, finger in ipairs(frame_data) do
            print(string.format(
                "Finger %d: pos=(%.2f, %.2f), vel=(%.2f, %.2f), state=%d",
                finger.id, finger.x, finger.y, finger.vx, finger.vy, finger.state
            ))
        end
    end
end

function love.draw()
    -- Required love callback
end

function love.quit()
    trackpad_lib.trackpad_stop()
    return false
end
