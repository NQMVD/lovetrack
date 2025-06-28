local ffi = require("ffi")

-- Define the C interface
ffi.cdef [[
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

local GestureDetector = {}
GestureDetector.__index = GestureDetector

-- Configuration constants
local MAX_FINGERS = 11
local SCROLL_VELOCITY_THRESHOLD = 0.01
local PAN_VELOCITY_THRESHOLD = 0.005
local ZOOM_DISTANCE_THRESHOLD = 0.05
local GESTURE_TIMEOUT = 0.5

function GestureDetector.new(library_name)
    local self = setmetatable({}, GestureDetector)
    
    -- Load the trackpad library
    self.trackpad_lib = ffi.load(library_name or "trackpad")
    self.c_fingers_array = ffi.new("TrackpadFinger[?]", MAX_FINGERS)
    
    -- Gesture state tracking
    self.fingers = {}
    self.previous_fingers = {}
    self.gesture_state = {
        scroll = { active = false, x = 0, y = 0, accumulated_x = 0, accumulated_y = 0 },
        pan = { active = false, x = 0, y = 0, start_x = 0, start_y = 0, delta_x = 0, delta_y = 0 },
        zoom = { active = false, scale = 1.0, initial_distance = 0, current_distance = 0, center_x = 0, center_y = 0 }
    }
    
    -- Timing for gesture detection
    self.last_update_time = 0
    self.gesture_start_time = {}
    
    -- Callbacks
    self.callbacks = {
        scroll = nil,
        pan_start = nil,
        pan_update = nil,
        pan_end = nil,
        zoom_start = nil,
        zoom_update = nil,
        zoom_end = nil
    }
    
    return self
end

function GestureDetector:start()
    if self.trackpad_lib.trackpad_start() ~= 0 then
        error("Failed to start trackpad service!")
    end
    return true
end

function GestureDetector:stop()
    self.trackpad_lib.trackpad_stop()
end

function GestureDetector:update(dt)
    self.last_update_time = self.last_update_time + dt
    
    -- Store previous finger state
    self.previous_fingers = {}
    for id, finger in pairs(self.fingers) do
        self.previous_fingers[id] = {
            x = finger.x, y = finger.y,
            vx = finger.vx, vy = finger.vy,
            state = finger.state
        }
    end
    
    -- Poll new finger data
    self.fingers = {}
    local nFingers = self.trackpad_lib.trackpad_poll(self.c_fingers_array, MAX_FINGERS)
    
    if nFingers > 0 then
        for i = 0, nFingers - 1 do
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
    end
    
    -- Detect gestures
    self:detectScroll(dt)
    self:detectPan(dt)
    self:detectZoom(dt)
end

function GestureDetector:detectScroll(dt)
    local finger_count = self:getFingerCount()
    
    if finger_count == 2 then
        local fingers = self:getFingersArray()
        local avg_vx = (fingers[1].vx + fingers[2].vx) / 2
        local avg_vy = (fingers[1].vy + fingers[2].vy) / 2
        
        -- Check if both fingers are moving in similar direction (scroll)
        local velocity_magnitude = math.sqrt(avg_vx * avg_vx + avg_vy * avg_vy)
        
        if velocity_magnitude > SCROLL_VELOCITY_THRESHOLD then
            -- Determine if it's primarily horizontal or vertical scroll
            local abs_vx = math.abs(avg_vx)
            local abs_vy = math.abs(avg_vy)
            
            local scroll_x = 0
            local scroll_y = 0
            
            if abs_vx > abs_vy * 0.5 then -- Horizontal component significant
                scroll_x = avg_vx
            end
            
            if abs_vy > abs_vx * 0.5 then -- Vertical component significant
                scroll_y = avg_vy
            end
            
            self.gesture_state.scroll.active = true
            self.gesture_state.scroll.x = scroll_x
            self.gesture_state.scroll.y = scroll_y
            self.gesture_state.scroll.accumulated_x = self.gesture_state.scroll.accumulated_x + scroll_x * dt
            self.gesture_state.scroll.accumulated_y = self.gesture_state.scroll.accumulated_y + scroll_y * dt
            
            if self.callbacks.scroll then
                self.callbacks.scroll(scroll_x, scroll_y, self.gesture_state.scroll.accumulated_x, self.gesture_state.scroll.accumulated_y)
            end
        else
            if self.gesture_state.scroll.active then
                -- Reset accumulated scroll when gesture ends
                self.gesture_state.scroll.accumulated_x = 0
                self.gesture_state.scroll.accumulated_y = 0
            end
            self.gesture_state.scroll.active = false
        end
    else
        if self.gesture_state.scroll.active then
            self.gesture_state.scroll.accumulated_x = 0
            self.gesture_state.scroll.accumulated_y = 0
        end
        self.gesture_state.scroll.active = false
    end
end

function GestureDetector:detectPan(dt)
    local finger_count = self:getFingerCount()
    
    if finger_count == 1 then
        local finger = self:getFingersArray()[1]
        local velocity_magnitude = math.sqrt(finger.vx * finger.vx + finger.vy * finger.vy)
        
        if velocity_magnitude > PAN_VELOCITY_THRESHOLD then
            if not self.gesture_state.pan.active then
                -- Start pan gesture
                self.gesture_state.pan.active = true
                self.gesture_state.pan.start_x = finger.x
                self.gesture_state.pan.start_y = finger.y
                self.gesture_state.pan.x = finger.x
                self.gesture_state.pan.y = finger.y
                self.gesture_state.pan.delta_x = 0
                self.gesture_state.pan.delta_y = 0
                
                if self.callbacks.pan_start then
                    self.callbacks.pan_start(finger.x, finger.y)
                end
            else
                -- Update pan gesture
                local prev_x = self.gesture_state.pan.x
                local prev_y = self.gesture_state.pan.y
                
                self.gesture_state.pan.x = finger.x
                self.gesture_state.pan.y = finger.y
                self.gesture_state.pan.delta_x = finger.x - prev_x
                self.gesture_state.pan.delta_y = finger.y - prev_y
                
                if self.callbacks.pan_update then
                    self.callbacks.pan_update(
                        finger.x, finger.y,
                        self.gesture_state.pan.delta_x, self.gesture_state.pan.delta_y,
                        finger.x - self.gesture_state.pan.start_x, finger.y - self.gesture_state.pan.start_y
                    )
                end
            end
        else
            if self.gesture_state.pan.active then
                -- End pan gesture
                self.gesture_state.pan.active = false
                
                if self.callbacks.pan_end then
                    self.callbacks.pan_end(
                        finger.x, finger.y,
                        finger.x - self.gesture_state.pan.start_x, finger.y - self.gesture_state.pan.start_y
                    )
                end
            end
        end
    else
        if self.gesture_state.pan.active then
            -- End pan gesture when finger count changes
            self.gesture_state.pan.active = false
            
            if self.callbacks.pan_end then
                self.callbacks.pan_end(
                    self.gesture_state.pan.x, self.gesture_state.pan.y,
                    self.gesture_state.pan.x - self.gesture_state.pan.start_x, 
                    self.gesture_state.pan.y - self.gesture_state.pan.start_y
                )
            end
        end
    end
end

function GestureDetector:detectZoom(dt)
    local finger_count = self:getFingerCount()
    
    if finger_count == 2 then
        local fingers = self:getFingersArray()
        local finger1, finger2 = fingers[1], fingers[2]
        
        -- Calculate distance between fingers
        local dx = finger2.x - finger1.x
        local dy = finger2.y - finger1.y
        local current_distance = math.sqrt(dx * dx + dy * dy)
        
        -- Calculate center point
        local center_x = (finger1.x + finger2.x) / 2
        local center_y = (finger1.y + finger2.y) / 2
        
        if not self.gesture_state.zoom.active then
            -- Start zoom gesture
            self.gesture_state.zoom.active = true
            self.gesture_state.zoom.initial_distance = current_distance
            self.gesture_state.zoom.current_distance = current_distance
            self.gesture_state.zoom.scale = 1.0
            self.gesture_state.zoom.center_x = center_x
            self.gesture_state.zoom.center_y = center_y
            
            if self.callbacks.zoom_start then
                self.callbacks.zoom_start(center_x, center_y, 1.0)
            end
        else
            -- Update zoom gesture
            local distance_change = current_distance - self.gesture_state.zoom.current_distance
            
            if math.abs(distance_change) > ZOOM_DISTANCE_THRESHOLD * dt then
                self.gesture_state.zoom.current_distance = current_distance
                self.gesture_state.zoom.scale = current_distance / self.gesture_state.zoom.initial_distance
                self.gesture_state.zoom.center_x = center_x
                self.gesture_state.zoom.center_y = center_y
                
                if self.callbacks.zoom_update then
                    self.callbacks.zoom_update(
                        center_x, center_y, 
                        self.gesture_state.zoom.scale,
                        distance_change
                    )
                end
            end
        end
    else
        if self.gesture_state.zoom.active then
            -- End zoom gesture
            self.gesture_state.zoom.active = false
            
            if self.callbacks.zoom_end then
                self.callbacks.zoom_end(
                    self.gesture_state.zoom.center_x, 
                    self.gesture_state.zoom.center_y, 
                    self.gesture_state.zoom.scale
                )
            end
        end
    end
end

-- Helper functions
function GestureDetector:getFingerCount()
    local count = 0
    for _ in pairs(self.fingers) do
        count = count + 1
    end
    return count
end

function GestureDetector:getFingersArray()
    local fingers = {}
    for _, finger in pairs(self.fingers) do
        table.insert(fingers, finger)
    end
    return fingers
end

function GestureDetector:getFingers()
    return self.fingers
end

-- Callback setters
function GestureDetector:onScroll(callback)
    self.callbacks.scroll = callback
end

function GestureDetector:onPanStart(callback)
    self.callbacks.pan_start = callback
end

function GestureDetector:onPanUpdate(callback)
    self.callbacks.pan_update = callback
end

function GestureDetector:onPanEnd(callback)
    self.callbacks.pan_end = callback
end

function GestureDetector:onZoomStart(callback)
    self.callbacks.zoom_start = callback
end

function GestureDetector:onZoomUpdate(callback)
    self.callbacks.zoom_update = callback
end

function GestureDetector:onZoomEnd(callback)
    self.callbacks.zoom_end = callback
end

-- Gesture state getters
function GestureDetector:isScrolling()
    return self.gesture_state.scroll.active
end

function GestureDetector:isPanning()
    return self.gesture_state.pan.active
end

function GestureDetector:isZooming()
    return self.gesture_state.zoom.active
end

function GestureDetector:getScrollVelocity()
    return self.gesture_state.scroll.x, self.gesture_state.scroll.y
end

function GestureDetector:getPanState()
    return self.gesture_state.pan.x, self.gesture_state.pan.y, 
           self.gesture_state.pan.delta_x, self.gesture_state.pan.delta_y
end

function GestureDetector:getZoomState()
    return self.gesture_state.zoom.center_x, self.gesture_state.zoom.center_y, 
           self.gesture_state.zoom.scale
end

return GestureDetector