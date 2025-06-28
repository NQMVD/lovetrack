local ffi = require("ffi")

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

local trackpad_lib = ffi.load("lovetrack")

-- Max fingers the trackpad can detect (usually 11 for modern Mac trackpads)
local MAX_FINGERS = 5
-- Create a C array to hold the finger data when polling
local c_fingers_array = ffi.new("TrackpadFinger[?]", MAX_FINGERS)

local lua_fingers = {}

function love.conf(t)
  t.window.title = "Trackpad Example"
  t.highdpi = true
  t.window.msaa = 8
  t.window.resizable = true
  t.window.width = 800
  t.window.height = 600
end

function love.load()
  if trackpad_lib.trackpad_start() ~= 0 then
    error("Failed to start trackpad service!")
  end
  print("Trackpad service started.")
end

function love.update(dt)
  lua_fingers = {}
  local nFingers = trackpad_lib.trackpad_poll(c_fingers_array, MAX_FINGERS)

  if nFingers > 0 then
    for i = 0, nFingers - 1 do
      local finger = c_fingers_array[i]
      lua_fingers[finger.id] = {
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
      -- print(string.format(
      --   "Finger %2d: pos=(%.2f, %.2f), vel=(%.2f, %.2f), state=%d",
      --   finger.id, finger.x, finger.y, finger.vx, finger.vy, finger.state
      -- ))
    end
  end
end

function love.draw()
  love.graphics.clear(0.2, 0.2, 0.2)
  love.graphics.setColor(1, 1, 1)

  for id, finger in pairs(lua_fingers) do
    local color = finger.state == 1 and { 0, 1, 0 } or { 1, 0, 0 } -- Green for down, red for up
    love.graphics.setColor(color)
    love.graphics.circle(
      "fill",
      finger.x * love.graphics.getWidth(),
      finger.y * love.graphics.getHeight(),
      finger.size * 10
    )
    -- also draw the volocity
    love.graphics.setColor(1, 1, 1)
    love.graphics.setLineWidth(2)
    love.graphics.line(
      finger.x * love.graphics.getWidth(),
      finger.y * love.graphics.getHeight(),
      (finger.x + finger.vx * 0.05) * love.graphics.getWidth(),
      (finger.y + (finger.vy) * 0.05) * love.graphics.getHeight()
    )

    love.graphics.setColor(1, 1, 1)
    love.graphics.print(string.format("Finger %d: (%.2f, %.2f)", id, finger.x, finger.y),
      finger.x * love.graphics.getWidth(), finger.y * love.graphics.getHeight())
  end
end

function love.quit()
  trackpad_lib.trackpad_stop()
  print("Trackpad service stopped.")
end
