
# TrackpadOSC Lua Library

This document provides an overview of the C library for accessing multitouch trackpad data within a Lua environment using FFI.

## Loading the Library

To use the library, you must first load it using LuaJIT's FFI extension. The library is loaded from the `trackpad.dylib` file.

```lua
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

    int trackpad_start();
    int trackpad_poll(TrackpadFinger* fingers, int max_fingers);
    void trackpad_stop();
]]

local trackpad_lib = ffi.load("trackpad")
```

## The `TrackpadFinger` Struct

The `TrackpadFinger` struct holds all the information for a single touch point on the trackpad.

### Fields

*   `id` (int): A unique identifier for the touch. This ID will remain the same as long as the finger is on the trackpad.
*   `x`, `y` (float): The normalized position of the touch. The values range from `0.0` to `1.0`, where `(0, 0)` is the bottom-left corner of the trackpad and `(1, 1)` is the top-right.
*   `vx`, `vy` (float): The normalized velocity of the touch.
*   `angle` (float): The angle of the touch ellipse in degrees.
*   `major_axis`, `minor_axis` (float): The lengths of the major and minor axes of the touch ellipse.
*   `size` (float): A measure of the touch area.
*   `state` (int): The state of the touch, based on Apple's private MultitouchSupport framework. The possible values are:
    *   `0`: Not tracking.
    *   `1`: Finger has entered the range of the trackpad and is about to touch down.
    *   `2`: Finger is hovering within the range of the trackpad.
    *   `3`: Finger has made contact with the trackpad surface.
    *   `4`: Finger is currently touching the trackpad surface.
    *   `5`: Finger is lifting off the trackpad surface.
    *   `6`: Finger is lingering in range after a touch.
    *   `7`: The finger has moved out of the trackpad's range.


## Functions

### `trackpad_start()`

Starts the trackpad listening service.

*   **Returns**: `0` on success, `-1` on failure.

### `trackpad_poll(fingers, max_fingers)`

Polls the trackpad for the latest touch data.

*   `fingers` (TrackpadFinger*): A pointer to an array of `TrackpadFinger` structs to be filled with the touch data.
*   `max_fingers` (int): The maximum number of fingers the `fingers` array can hold.
*   **Returns**: The number of fingers currently on the trackpad.

### `trackpad_stop()`

Stops the trackpad listening service.

## Example Usage

Here is a complete example of how to use the library in LÖVE 2D:

```lua
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

    int trackpad_start();
    int trackpad_poll(TrackpadFinger* fingers, int max_fingers);
    void trackpad_stop();
]]

local trackpad_lib = ffi.load("trackpad")

-- Max fingers the trackpad can detect
local MAX_FINGERS = 10
-- Create a C array to hold the finger data
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
  -- Your drawing code here
end

function love.quit()
  trackpad_lib.trackpad_stop()
  print("Trackpad service stopped.")
  return false
end
```
