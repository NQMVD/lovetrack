local ffi = require("ffi")

-- Load the C library
local lib = ffi.load("lovetrack")

-- Define C structures and functions
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

local Gesture = {}
Gesture.__index = Gesture

function Gesture.new(config)
  local self = setmetatable({}, Gesture)

  -- Configuration with defaults
  self.config = {
    -- Activation deadzones (higher - harder to start gesture)
    deadzone_movement_activate = config and config.deadzone_movement_activate or 0.002,
    deadzone_zoom_activate = config and config.deadzone_zoom_activate or 0.003,     -- Lowered significantly

    -- Continuation deadzones (lower - easier to continue gesture)
    deadzone_movement_continue = config and config.deadzone_movement_continue or 0.0005,
    deadzone_zoom_continue = config and config.deadzone_zoom_continue or 0.0008,

    scroll_angle_max = config and config.scroll_angle_max or math.rad(25),
    smoothing_factor = config and config.smoothing_factor or 0.2,
    min_zoom_distance = config and config.min_zoom_distance or 0.015,     -- Lowered
    zoom_sensitivity = config and config.zoom_sensitivity or 1.8,
  }

  -- State tracking
  self.state = "idle"           -- idle, scrolling, panning, zooming
  self.gesture_locked = false   -- Once locked, stays locked until fingers lift
  self.fingers = ffi.new("TrackpadFinger[20]")
  self.prev_fingers = {}
  self.has_prev_fingers = false

  -- Delta tracking
  self.deltas = {
    scroll_x = 0,
    scroll_y = 0,
    pan_x = 0,
    pan_y = 0,
    zoom_factor = 1.0,
    center_x = 0,
    center_y = 0,
  }

  -- Smoothed values
  self.smoothed = {
    scroll_x = 0,
    scroll_y = 0,
    pan_x = 0,
    pan_y = 0,
    zoom_factor = 1.0,
  }

  self.scroll_locked = false
  self.zoom_center = { x = 0, y = 0 }

  -- Start trackpad
  if lib.trackpad_start() ~= 0 then
    error("Failed to initialize trackpad")
  end

  return self
end

function Gesture:setScrollLock(locked)
  self.scroll_locked = locked
end

function Gesture:update(dt)
  local finger_count = lib.trackpad_poll(self.fingers, 20)

  -- Reset deltas
  self.deltas.scroll_x = 0
  self.deltas.scroll_y = 0
  self.deltas.pan_x = 0
  self.deltas.pan_y = 0
  self.deltas.zoom_factor = 1.0

  if finger_count == 0 then
    self:_resetState()
  elseif finger_count == 2 and self.has_prev_fingers then
    self:_processTwoFingerGesture()
  elseif finger_count == 2 then
    -- First frame with two fingers, just store them
    self:_storePreviousFingers(finger_count)
  else
    self:_resetState()
  end

  self:_applySmoothing(dt)

  if finger_count > 0 then
    self:_storePreviousFingers(finger_count)
  end
end

function Gesture:_processTwoFingerGesture()
  local f1, f2 = self.fingers[0], self.fingers[1]
  local pf1, pf2 = self.prev_fingers[1], self.prev_fingers[2]

  if not pf1 or not pf2 then return end

  -- Calculate current metrics
  local curr_center_x = (f1.x + f2.x) * 0.5
  local curr_center_y = (f1.y + f2.y) * 0.5
  local curr_distance = math.sqrt((f1.x - f2.x) ^ 2 + (f1.y - f2.y) ^ 2)

  -- Calculate previous metrics
  local prev_center_x = (pf1.x + pf2.x) * 0.5
  local prev_center_y = (pf1.y + pf2.y) * 0.5
  local prev_distance = math.sqrt((pf1.x - pf2.x) ^ 2 + (pf1.y - pf2.y) ^ 2)

  -- Calculate deltas
  local dx = curr_center_x - prev_center_x
  local dy = curr_center_y - prev_center_y
  local distance_delta = curr_distance - prev_distance

  -- Convert to screen coordinates
  local screen_w, screen_h = love.graphics.getDimensions()
  dx = dx * screen_w
  dy = dy * screen_h

  -- Store center for zoom operations
  self.deltas.center_x = curr_center_x * screen_w
  self.deltas.center_y = curr_center_y * screen_h

  -- ONLY detect gesture if we're in idle state (not locked)
  if not self.gesture_locked then
    -- Choose deadzone based on current state
    local movement_deadzone = self.config.deadzone_movement_activate
    local zoom_deadzone = self.config.deadzone_zoom_activate

    -- Check what's happening (without applying deadzones for detection)
    local has_movement = (math.abs(dx) > movement_deadzone or math.abs(dy) > movement_deadzone)
    local has_zoom = (math.abs(distance_delta) > zoom_deadzone and curr_distance > self.config.min_zoom_distance)

    -- ZOOM DETECTION FIRST (highest priority)
    if has_zoom then
      print("Activating ZOOM")
      self.state = "zooming"
      self.gesture_locked = true
      self.zoom_center = { x = self.deltas.center_x, y = self.deltas.center_y }
      -- MOVEMENT DETECTION (lower priority)
    elseif has_movement then
      -- Determine scroll vs pan based on movement angle
      local angle = math.atan2(math.abs(dy), math.abs(dx))

      if not self.scroll_locked and (angle < self.config.scroll_angle_max or angle > (math.pi / 2 - self.config.scroll_angle_max)) then
        print("Activating SCROLL")
        self.state = "scrolling"
        self.gesture_locked = true
      else
        print("Activating PAN")
        self.state = "panning"
        self.gesture_locked = true
      end
    end
  end

  -- Apply appropriate deadzones for continuation
  local movement_deadzone = self.config.deadzone_movement_continue
  local zoom_deadzone = self.config.deadzone_zoom_continue

  if math.abs(dx) < movement_deadzone then dx = 0 end
  if math.abs(dy) < movement_deadzone then dy = 0 end
  if math.abs(distance_delta) < zoom_deadzone then distance_delta = 0 end

  -- Apply deltas based on current state
  if self.state == "scrolling" then
    self.deltas.scroll_x = dx
    self.deltas.scroll_y = dy
  elseif self.state == "panning" then
    self.deltas.pan_x = dx
    self.deltas.pan_y = dy
  elseif self.state == "zooming" and distance_delta ~= 0 then
    if prev_distance > 0 then
      local zoom_change = distance_delta / prev_distance
      self.deltas.zoom_factor = 1.0 + (zoom_change * self.config.zoom_sensitivity)
    end
  end
end

function Gesture:_applySmoothing(dt)
  local factor = self.config.smoothing_factor

  -- For deltas, we want responsive movement, so less smoothing
  local movement_factor = factor * 0.5

  self.smoothed.scroll_x = self:_lerp(self.smoothed.scroll_x, self.deltas.scroll_x, movement_factor)
  self.smoothed.scroll_y = self:_lerp(self.smoothed.scroll_y, self.deltas.scroll_y, movement_factor)
  self.smoothed.pan_x = self:_lerp(self.smoothed.pan_x, self.deltas.pan_x, movement_factor)
  self.smoothed.pan_y = self:_lerp(self.smoothed.pan_y, self.deltas.pan_y, movement_factor)
  self.smoothed.zoom_factor = self:_lerp(self.smoothed.zoom_factor, self.deltas.zoom_factor, factor)

  -- Decay smoothed values when no input
  if self.state == "idle" then
    self.smoothed.scroll_x = self.smoothed.scroll_x * 0.9
    self.smoothed.scroll_y = self.smoothed.scroll_y * 0.9
    self.smoothed.pan_x = self.smoothed.pan_x * 0.9
    self.smoothed.pan_y = self.smoothed.pan_y * 0.9
    self.smoothed.zoom_factor = self:_lerp(self.smoothed.zoom_factor, 1.0, 0.1)
  end
end

function Gesture:_lerp(a, b, t)
  return a + (b - a) * t
end

function Gesture:_resetState()
  if self.state ~= "idle" then
    print("Resetting to IDLE")
  end
  self.state = "idle"
  self.gesture_locked = false   -- Unlock when fingers lift
  self.has_prev_fingers = false
end

function Gesture:_storePreviousFingers(count)
  self.prev_fingers = {}
  for i = 0, count - 1 do
    table.insert(self.prev_fingers, {
      x = self.fingers[i].x,
      y = self.fingers[i].y,
      id = self.fingers[i].id
    })
  end
  self.has_prev_fingers = (count > 0)
end

-- Public API
function Gesture:getState()
  return self.state
end

function Gesture:getScrollDelta()
  if self.state == "scrolling" then
    return self.smoothed.scroll_x, self.smoothed.scroll_y
  end
  return 0, 0
end

function Gesture:getPanDelta()
  if self.state == "panning" then
    return self.smoothed.pan_x, self.smoothed.pan_y
  end
  return 0, 0
end

function Gesture:getZoomFactor()
  if self.state == "zooming" then
    return self.smoothed.zoom_factor
  end
  return 1.0
end

function Gesture:getCenter()
  if self.state == "zooming" then
    return self.zoom_center.x, self.zoom_center.y
  end
  return self.deltas.center_x, self.deltas.center_y
end

function Gesture:destroy()
  lib.trackpad_stop()
end

return Gesture
