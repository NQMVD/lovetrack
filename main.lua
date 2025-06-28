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

local trackpad_lib = ffi.load("trackpad")

-- Max fingers the trackpad can detect (usually 11 for modern Mac trackpads)
local MAX_FINGERS = 5
-- Create a C array to hold the finger data when polling
local c_fingers_array = ffi.new("TrackpadFinger[?]", MAX_FINGERS)

function love.load()
  if trackpad_lib.trackpad_start() ~= 0 then
    error("Failed to start trackpad service!")
  end
  print("Trackpad service started.")
end

function love.update(dt)
  local nFingers = trackpad_lib.trackpad_poll(c_fingers_array, MAX_FINGERS)

  if nFingers > 0 then
    for i = 0, nFingers - 1 do
      local finger = c_fingers_array[i]
      print(string.format(
        "Finger %2d: pos=(%.2f, %.2f), vel=(%.2f, %.2f), state=%d",
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
  print("Trackpad service stopped.")
  return false
end
