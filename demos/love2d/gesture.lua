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
    -- Activation deadzones (distance from initial position)
    deadzone_movement_activate = config and config.deadzone_movement_activate or 1,
    deadzone_zoom_activate = config and config.deadzone_zoom_activate or 1,

    -- Continuation deadzones (frame-to-frame delta)
    deadzone_movement_continue = config and config.deadzone_movement_continue or 1,
    deadzone_zoom_continue = config and config.deadzone_zoom_continue or 1,

    scroll_angle_max = config and config.scroll_angle_max or math.rad(30),
    smoothing_factor = config and config.smoothing_factor or 0.9,
    zoom_sensitivity = config and config.zoom_sensitivity or 1.0,
    min_zoom_distance = config and config.min_zoom_distance or 0.01,
  }

  -- map the deadzone values
  self.config.deadzone_movement_activate =
      self.config.deadzone_movement_activate * 4

  self.config.deadzone_zoom_activate =
      self.config.deadzone_zoom_activate * 0.01

  self.config.deadzone_movement_continue =
      self.config.deadzone_movement_continue * 0.1

  self.config.deadzone_zoom_continue =
      self.config.deadzone_zoom_continue * 0.0005

  -- print("deadzone_movement_activate: " .. self.config.deadzone_movement_activate)
  -- print("deadzone_zoom_activate: " .. self.config.deadzone_zoom_activate)
  -- print("deadzone_movement_continue: " .. self.config.deadzone_movement_continue)
  -- print("deadzone_zoom_continue: " .. self.config.deadzone_zoom_continue)

  -- State tracking
  self.state = "idle"         -- idle, scrolling, panning, zooming
  self.gesture_locked = false -- Once locked, stays locked until fingers lift
  self.fingers = ffi.new("TrackpadFinger[11]")
  self.prev_fingers = {}
  self.initial_fingers = {} -- Store initial finger positions
  self.has_prev_fingers = false
  self.has_initial_fingers = false

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
  local finger_count = lib.trackpad_poll(self.fingers, 11)

  -- Reset deltas
  self.deltas.scroll_x = 0
  self.deltas.scroll_y = 0
  self.deltas.pan_x = 0
  self.deltas.pan_y = 0
  self.deltas.zoom_factor = 1.0

  if finger_count == 2 then
    local min, avg, max = self:_getFingerValues()
    if min > 2 and max < 6 then
      if not self.has_initial_fingers then
        self:_storeInitialFingers()
      elseif self.has_prev_fingers then
        self:_processTwoFingerGesture()
      end
      self:_storePreviousFingers(finger_count)
    end
  else
    self:_resetState()
  end

  self:_applySmoothing(dt)
end

function Gesture:_getFingerValues()
  local min_value = math.huge
  local max_value = -math.huge
  local total_value = 0
  local count = 0
  for i = 0, 10 do
    if self.fingers[i].id ~= 0 then
      local value = self.fingers[i].state
      min_value = math.min(min_value, value)
      max_value = math.max(max_value, value)
      total_value = total_value + value
      count = count + 1
    end
  end
  if count > 1 then
    return min_value, total_value / count, max_value, count
  else
    return 0, 0, 0, 0 -- No fingers detected
  end
end

function Gesture:_isWithinWindow(center_x, center_y)
  local screen_w, screen_h = love.graphics.getDimensions()
  return center_x >= 0 and center_x <= screen_w and center_y >= 0 and center_y <= screen_h
end

function Gesture:_processTwoFingerGesture()
  local f1, f2 = self.fingers[0], self.fingers[1]
  local pf1, pf2 = self.prev_fingers[1], self.prev_fingers[2]
  local if1, if2 = self.initial_fingers[1], self.initial_fingers[2]

  if not pf1 or not pf2 or not if1 or not if2 then return end

  -- Calculate current metrics
  local curr_center_x = (f1.x + f2.x) * 0.5
  local curr_center_y = (f1.y + f2.y) * 0.5
  local curr_distance = math.sqrt((f1.x - f2.x) ^ 2 + (f1.y - f2.y) ^ 2)

  -- Calculate previous metrics
  local prev_center_x = (pf1.x + pf2.x) * 0.5
  local prev_center_y = (pf1.y + pf2.y) * 0.5
  local prev_distance = math.sqrt((pf1.x - pf2.x) ^ 2 + (pf1.y - pf2.y) ^ 2)

  -- Calculate initial metrics
  local initial_center_x = (if1.x + if2.x) * 0.5
  local initial_center_y = (if1.y + if2.y) * 0.5
  local initial_distance = math.sqrt((if1.x - if2.x) ^ 2 + (if1.y - if2.y) ^ 2)

  -- Calculate deltas (frame-to-frame)
  local dx = curr_center_x - prev_center_x
  local dy = curr_center_y - prev_center_y
  local distance_delta = curr_distance - prev_distance

  -- Calculate distance from initial position (for activation)
  local initial_dx = curr_center_x - initial_center_x
  local initial_dy = curr_center_y - initial_center_y
  local initial_distance_change = curr_distance - initial_distance

  -- Convert to screen coordinates
  local screen_w, screen_h = love.graphics.getDimensions()
  dx = dx * screen_w
  dy = dy * screen_h
  initial_dx = initial_dx * screen_w
  initial_dy = initial_dy * screen_h

  -- Store center for zoom operations
  self.deltas.center_x = curr_center_x * screen_w
  self.deltas.center_y = curr_center_y * screen_h

  -- Check if gesture is within Love2D window
  if not self:_isWithinWindow(self.deltas.center_x, self.deltas.center_y) then
    return -- Ignore gestures outside window
  end

  -- ONLY detect gesture if we're in idle state (not locked)
  if not self.gesture_locked then
    -- Use initial position distance for activation
    local movement_distance = math.sqrt(initial_dx ^ 2 + initial_dy ^ 2)
    local has_movement = (movement_distance > self.config.deadzone_movement_activate)
    local has_zoom = (
      math.abs(initial_distance_change) > self.config.deadzone_zoom_activate
      and curr_distance > self.config.min_zoom_distance
    )

    -- ZOOM DETECTION FIRST (highest priority)
    if has_zoom then
      self.state = "zooming"
      self.gesture_locked = true
      self.zoom_center = { x = self.deltas.center_x, y = self.deltas.center_y }
      -- MOVEMENT DETECTION (lower priority)
    elseif has_movement then
      -- Determine scroll vs pan based on movement angle from initial position
      local angle = math.atan2(math.abs(initial_dy), math.abs(initial_dx))

      if not self.scroll_locked and (angle < self.config.scroll_angle_max or angle > (math.pi / 2 - self.config.scroll_angle_max)) then
        self.state = "scrolling"
        self.gesture_locked = true
      else
        self.state = "panning"
        self.gesture_locked = true
      end
    end
  end

  -- Apply continuation deadzones to frame-to-frame deltas
  if math.abs(dx) < self.config.deadzone_movement_continue then dx = 0 end
  if math.abs(dy) < self.config.deadzone_movement_continue then dy = 0 end
  if math.abs(distance_delta) < self.config.deadzone_zoom_continue then distance_delta = 0 end

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
  self.state = "idle"
  self.gesture_locked = false
  self.has_prev_fingers = false
  self.has_initial_fingers = false
  lib.trackpad_reset(self.fingers, 11)
  self.initial_fingers = {}
end

function Gesture:_storeInitialFingers()
  self.initial_fingers = {}
  for i = 0, 1 do -- Only store first two fingers
    table.insert(self.initial_fingers, {
      x = self.fingers[i].x,
      y = self.fingers[i].y,
      id = self.fingers[i].id
    })
  end
  self.has_initial_fingers = true
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
