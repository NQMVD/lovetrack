--[[
    gestures.lua
    A Lua library for detecting two-finger gestures (pan and zoom) from a trackpad.
    This library uses the `lovetrack` C library via LuaJIT FFI.

    Features:
    - Differentiates between panning and zooming with two fingers.
    - Uses deadzones to prevent accidental gestures.
    - Uses velocity to determine gesture intent.
    - Locks the current gesture until fingers are lifted.
    - Provides callbacks for gesture events.
--]]

local ffi = require("ffi")

-- Define the C interface from lovetrack_lib.h
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

    int trackpad_start();
    int trackpad_poll(TrackpadFinger* fingers, int max_fingers);
    void trackpad_stop();
]]

local Gestures = {}
Gestures.__index = Gestures

-- =============================================================================
-- Configuration
-- =============================================================================
local MAX_FINGERS = 11 -- Max fingers supported by the C library

-- Deadzones
local START_MOVE_DEADZONE_SQ = 0.0001 -- Squared distance midpoint must move to start a gesture
local ZOOM_START_DISTANCE_DEADZONE = 0.01 -- How much finger distance must change to start zoom

-- Velocity Thresholds
local GESTURE_START_VELOCITY_SQ = 0.00001 -- Squared velocity to start a gesture

-- =============================================================================
-- Public Methods
-- =============================================================================

function Gestures.new(library_path)
    local self = setmetatable({}, Gestures)

    -- Load the trackpad library
    self.trackpad_lib = ffi.load(library_path or "liblovetrack.dylib")
    self.c_fingers_array = ffi.new("TrackpadFinger[?]", MAX_FINGERS)

    -- Callbacks
    self.callbacks = {
        on_pan_start = nil,
        on_pan_update = nil,
        on_pan_end = nil,
        on_zoom_start = nil,
        on_zoom_update = nil,
        on_zoom_end = nil,
        on_gesture_end = nil
    }

    self:_reset_state()
    return self
end

function Gestures:start()
    if self.trackpad_lib.trackpad_start() ~= 0 then
        error("Failed to start trackpad service!")
    end
    self.is_running = true
    return true
end

function Gestures:stop()
    if self.is_running then
        self.trackpad_lib.trackpad_stop()
        self.is_running = false
    end
end

function Gestures:update(dt)
    if not self.is_running then return end

    -- Poll for new finger data
    local n_fingers = self.trackpad_lib.trackpad_poll(self.c_fingers_array, MAX_FINGERS)
    self.fingers = {}
    for i = 0, n_fingers - 1 do
        local finger = self.c_fingers_array[i]
        self.fingers[finger.id] = {
            id = finger.id,
            x = finger.x,
            y = finger.y,
            vx = finger.vx,
            vy = finger.vy,
            angle = finger.angle,
            major_axis = finger.major_axis,
            minor_axis = finger.minor_axis,
            size = finger.size,
            state = finger.state
        }
    end

    local finger_count = self:getFingerCount()

    if finger_count == 2 then
        self:_process_two_finger_gestures(dt)
    else
        -- If gesture was active, end it
        if self.current_gesture ~= "none" then
            if self.callbacks.on_gesture_end then
                self.callbacks.on_gesture_end(self.current_gesture)
            end
            if self.current_gesture == "pan" and self.callbacks.on_pan_end then
                self.callbacks.on_pan_end(self.last_pan_x, self.last_pan_y, self.total_pan_dx, self.total_pan_dy)
            end
            if self.current_gesture == "zoom" and self.callbacks.on_zoom_end then
                self.callbacks.on_zoom_end(self.zoom_center_x, self.zoom_center_y, self.zoom_scale)
            end
        end
        self:_reset_state()
    end
end

-- Callback setters
function Gestures:on_pan_start(callback) self.callbacks.on_pan_start = callback end
function Gestures:on_pan_update(callback) self.callbacks.on_pan_update = callback end
function Gestures:on_pan_end(callback) self.callbacks.on_pan_end = callback end
function Gestures:on_zoom_start(callback) self.callbacks.on_zoom_start = callback end
function Gestures:on_zoom_update(callback) self.callbacks.on_zoom_update = callback end
function Gestures:on_zoom_end(callback) self.callbacks.on_zoom_end = callback end
function Gestures:on_gesture_end(callback) self.callbacks.on_gesture_end = callback end


-- =============================================================================
-- Internal Methods
-- =============================================================================

function Gestures:_reset_state()
    self.current_gesture = "none" -- "none", "starting", "pan", "zoom"
    self.start_fingers = {}
    self.start_midpoint = { x = 0, y = 0 }
    self.start_distance = 0
    self.last_midpoint = { x = 0, y = 0 }
    self.last_distance = 0
    self.last_pan_x = 0
    self.last_pan_y = 0
    self.total_pan_dx = 0
    self.total_pan_dy = 0
    self.zoom_center_x = 0
    self.zoom_center_y = 0
    self.zoom_scale = 1.0
end

function Gestures:_get_fingers_array()
    local fingers = {}
    for _, finger in pairs(self.fingers) do
        table.insert(fingers, finger)
    end
    return fingers
end

function Gestures:getFingerCount()
    local count = 0
    for _ in pairs(self.fingers) do
        count = count + 1
    end
    return count
end

function Gestures:getFingers()
    return self.fingers
end

function Gestures:_process_two_finger_gestures(dt)
    local fingers = self:_get_fingers_array()
    local f1 = fingers[1]
    local f2 = fingers[2]

    -- Calculate current gesture parameters
    local midpoint = { x = (f1.x + f2.x) / 2, y = (f1.y + f2.y) / 2 }
    local dx, dy = f2.x - f1.x, f2.y - f1.y
    local distance = math.sqrt(dx*dx + dy*dy)
    local avg_velocity_sq = ((f1.vx + f2.vx)/2)^2 + ((f1.vy + f2.vy)/2)^2

    -- State: "none" -> "starting"
    -- This is the first frame with two fingers. Record initial state.
    if self.current_gesture == "none" then
        self.current_gesture = "starting"
        self.start_fingers = { f1, f2 }
        self.start_midpoint = midpoint
        self.start_distance = distance
        self.last_midpoint = midpoint
        self.last_distance = distance
        return
    end

    -- State: "starting" -> gesture detection
    -- We are waiting for movement to exceed deadzones to decide the gesture.
    if self.current_gesture == "starting" then
        local move_dist_sq = (midpoint.x - self.start_midpoint.x)^2 + (midpoint.y - self.start_midpoint.y)^2
        local zoom_dist = math.abs(distance - self.start_distance)

        -- Check for low velocity, do nothing if too slow
        if avg_velocity_sq < GESTURE_START_VELOCITY_SQ then return end

        -- Check if movement is significant enough to start a gesture
        if move_dist_sq < START_MOVE_DEADZONE_SQ and zoom_dist < ZOOM_START_DISTANCE_DEADZONE then
            return
        end

        -- Determine gesture type: zoom has priority
        if zoom_dist > ZOOM_START_DISTANCE_DEADZONE then
            self.current_gesture = "zoom"
            self.zoom_center_x = midpoint.x
            self.zoom_center_y = midpoint.y
            if self.callbacks.on_zoom_start then
                self.callbacks.on_zoom_start(self.zoom_center_x, self.zoom_center_y, self.zoom_scale)
            end
        else
            self.current_gesture = "pan"
            if self.callbacks.on_pan_start then
                self.callbacks.on_pan_start(midpoint.x, midpoint.y)
            end
        end
    end

    -- State: gesture is active, execute and send callbacks
    local delta_midpoint = { x = midpoint.x - self.last_midpoint.x, y = midpoint.y - self.last_midpoint.y }

    if self.current_gesture == "zoom" then
        self.zoom_scale = distance / self.start_distance
        if self.callbacks.on_zoom_update then
            self.callbacks.on_zoom_update(midpoint.x, midpoint.y, self.zoom_scale, distance - self.last_distance)
        end

    elseif self.current_gesture == "pan" then
        if self.callbacks.on_pan_update then
            self.callbacks.on_pan_update(midpoint.x, midpoint.y, delta_midpoint.x, delta_midpoint.y, midpoint.x - self.start_midpoint.x, midpoint.y - self.start_midpoint.y)
        end
    end

    -- Update state for next frame
    self.last_midpoint = midpoint
    self.last_distance = distance
end

return Gestures