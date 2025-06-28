--[[
    two_finger_gestures.lua
    A Lua library for detecting two-finger gestures (scroll, pan, zoom) from a trackpad.
    This library uses the `lovetrack` C library via LuaJIT FFI.

    Features:
    - Differentiates between scrolling, panning, and zooming with two fingers.
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

local TwoFingerGestureDetector = {}
TwoFingerGestureDetector.__index = TwoFingerGestureDetector

-- =============================================================================
-- Configuration
-- =============================================================================
local MAX_FINGERS = 11 -- Max fingers supported by the C library

-- Deadzones
local START_MOVE_DEADZONE_SQ = 0.0001 -- Squared distance midpoint must move to start a gesture
local ZOOM_START_DISTANCE_DEADZONE = 0.01 -- How much finger distance must change to start zoom

-- Velocity Thresholds
local GESTURE_START_VELOCITY_SQ = 0.00001 -- Squared velocity to start a gesture

-- Gesture Differentiation
local PAN_VS_SCROLL_ANGLE = 35 -- Angle in degrees to differentiate pan vs scroll.
                               -- < threshold: pan, > threshold: scroll

-- =============================================================================
-- Public Methods
-- =============================================================================

function TwoFingerGestureDetector.new(library_path)
    local self = setmetatable({}, TwoFingerGestureDetector)

    -- Load the trackpad library
    self.trackpad_lib = ffi.load(library_path or "liblovetrack.dylib")
    self.c_fingers_array = ffi.new("TrackpadFinger[?]", MAX_FINGERS)

    -- Callbacks
    self.callbacks = {
        on_scroll = nil,
        on_pan = nil,
        on_zoom = nil,
        on_gesture_end = nil
    }

    self:_reset_state()
    return self
end

function TwoFingerGestureDetector:start()
    if self.trackpad_lib.trackpad_start() ~= 0 then
        error("Failed to start trackpad service!")
    end
    self.is_running = true
    return true
end

function TwoFingerGestureDetector:stop()
    if self.is_running then
        self.trackpad_lib.trackpad_stop()
        self.is_running = false
    end
end

function TwoFingerGestureDetector:update(dt)
    if not self.is_running then return end

    -- Poll for new finger data
    local n_fingers = self.trackpad_lib.trackpad_poll(self.c_fingers_array, MAX_FINGERS)
    local current_fingers = {}
    for i = 0, n_fingers - 1 do
        table.insert(current_fingers, self.c_fingers_array[i])
    end

    local finger_count = #current_fingers

    if finger_count ~= 2 then
        -- If gesture was active, end it
        if self.current_gesture ~= "none" then
            if self.callbacks.on_gesture_end then
                self.callbacks.on_gesture_end(self.current_gesture)
            end
        end
        self:_reset_state()
        return
    end

    -- We have two fingers, process gestures
    self:_process_two_finger_gestures(current_fingers, dt)
end

-- Callback setters
function TwoFingerGestureDetector:on_scroll(callback) self.callbacks.on_scroll = callback end
function TwoFingerGestureDetector:on_pan(callback) self.callbacks.on_pan = callback end
function TwoFingerGestureDetector:on_zoom(callback) self.callbacks.on_zoom = callback end
function TwoFingerGestureDetector:on_gesture_end(callback) self.callbacks.on_gesture_end = callback end


-- =============================================================================
-- Internal Methods
-- =============================================================================

function TwoFingerGestureDetector:_reset_state()
    self.current_gesture = "none" -- "none", "starting", "scroll", "pan", "zoom"
    self.start_fingers = {}
    self.start_midpoint = { x = 0, y = 0 }
    self.start_distance = 0
    self.last_midpoint = { x = 0, y = 0 }
    self.last_distance = 0
end

function TwoFingerGestureDetector:_process_two_finger_gestures(fingers, dt)
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
        else
            -- Differentiate between pan and scroll based on angle
            local move_vec = { x = midpoint.x - self.start_midpoint.x, y = midpoint.y - self.start_midpoint.y }
            local finger_vec = { x = self.start_fingers[2].x - self.start_fingers[1].x, y = self.start_fingers[2].y - self.start_fingers[1].y }

            local angle = self:_angle_between_vectors(move_vec, finger_vec)

            if angle > 90 - PAN_VS_SCROLL_ANGLE and angle < 90 + PAN_VS_SCROLL_ANGLE then
                self.current_gesture = "scroll"
            else
                self.current_gesture = "pan"
            end
        end
    end

    -- State: gesture is active, execute and send callbacks
    local delta_midpoint = { x = midpoint.x - self.last_midpoint.x, y = midpoint.y - self.last_midpoint.y }

    if self.current_gesture == "zoom" then
        local scale = distance / self.start_distance
        if self.callbacks.on_zoom then
            self.callbacks.on_zoom(midpoint.x, midpoint.y, scale, distance - self.last_distance)
        end

    elseif self.current_gesture == "scroll" then
        if self.callbacks.on_scroll then
            self.callbacks.on_scroll(delta_midpoint.x, delta_midpoint.y)
        end

    elseif self.current_gesture == "pan" then
        if self.callbacks.on_pan then
            self.callbacks.on_pan(delta_midpoint.x, delta_midpoint.y)
        end
    end

    -- Update state for next frame
    self.last_midpoint = midpoint
    self.last_distance = distance
end

function TwoFingerGestureDetector:_angle_between_vectors(v1, v2)
    local dot = v1.x * v2.x + v1.y * v2.y
    local mag1 = math.sqrt(v1.x^2 + v1.y^2)
    local mag2 = math.sqrt(v2.x^2 + v2.y^2)
    if mag1 == 0 or mag2 == 0 then return 0 end
    local cos_angle = dot / (mag1 * mag2)
    return math.deg(math.acos(math.max(-1, math.min(1, cos_angle))))
end

return TwoFingerGestureDetector
