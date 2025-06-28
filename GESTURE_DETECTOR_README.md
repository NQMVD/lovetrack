# Gesture Detector Library

A Lua library built on top of the TrackpadOSC C library that provides high-level gesture detection for macOS trackpads. Detects scrolling, panning, and zoom/pinch gestures.

## Features

- **Scroll Detection**: Detects 2-finger scrolling in X and Y axes
- **Pan Detection**: Detects 1-finger panning with start/update/end events
- **Zoom Detection**: Detects 2-finger pinch/expand gestures with scale factor
- **Real-time Processing**: Low-latency gesture recognition
- **Callback System**: Event-driven architecture for easy integration

## Installation

1. Ensure you have the TrackpadOSC C library (`trackpad.dylib` or `liblovetrack.dylib`)
2. Place `gesture_detector.lua` in your project directory
3. Require the library in your Lua code

## Quick Start

```lua
local GestureDetector = require("gesture_detector")

-- Initialize
local gesture_detector = GestureDetector.new("trackpad") -- or "liblovetrack"
gesture_detector:start()

-- Set up callbacks
gesture_detector:onScroll(function(vx, vy, accumulated_x, accumulated_y)
    print("Scrolling:", vx, vy)
end)

gesture_detector:onPanUpdate(function(x, y, dx, dy, total_dx, total_dy)
    print("Panning:", dx, dy)
end)

gesture_detector:onZoomUpdate(function(center_x, center_y, scale, distance_change)
    print("Zooming:", scale)
end)

-- In your update loop
function love.update(dt)
    gesture_detector:update(dt)
end

-- Clean up
function love.quit()
    gesture_detector:stop()
end
```

## API Reference

### Constructor

#### `GestureDetector.new(library_name)`
Creates a new gesture detector instance.
- `library_name` (optional): Name of the trackpad library to load (default: "trackpad")

### Core Methods

#### `gesture_detector:start()`
Starts the trackpad service. Returns `true` on success, throws error on failure.

#### `gesture_detector:stop()`
Stops the trackpad service and cleans up resources.

#### `gesture_detector:update(dt)`
Updates gesture detection. Call this every frame.
- `dt`: Delta time since last update

### Callback Registration

#### Scroll Callbacks
```lua
gesture_detector:onScroll(function(vx, vy, accumulated_x, accumulated_y)
    -- vx, vy: Current scroll velocity
    -- accumulated_x, accumulated_y: Total scroll since gesture started
end)
```

#### Pan Callbacks
```lua
gesture_detector:onPanStart(function(x, y)
    -- x, y: Starting position (normalized 0-1)
end)

gesture_detector:onPanUpdate(function(x, y, dx, dy, total_dx, total_dy)
    -- x, y: Current position
    -- dx, dy: Delta movement since last frame
    -- total_dx, total_dy: Total movement since pan started
end)

gesture_detector:onPanEnd(function(x, y, total_dx, total_dy)
    -- x, y: Final position
    -- total_dx, total_dy: Total movement during pan
end)
```

#### Zoom Callbacks
```lua
gesture_detector:onZoomStart(function(center_x, center_y, scale)
    -- center_x, center_y: Center point of zoom gesture
    -- scale: Initial scale (1.0)
end)

gesture_detector:onZoomUpdate(function(center_x, center_y, scale, distance_change)
    -- center_x, center_y: Current center point
    -- scale: Current scale factor relative to start
    -- distance_change: Change in finger distance since last frame
end)

gesture_detector:onZoomEnd(function(center_x, center_y, final_scale)
    -- center_x, center_y: Final center point
    -- final_scale: Final scale factor
end)
```

### State Query Methods

#### `gesture_detector:isScrolling()`
Returns `true` if currently scrolling.

#### `gesture_detector:isPanning()`
Returns `true` if currently panning.

#### `gesture_detector:isZooming()`
Returns `true` if currently zooming.

#### `gesture_detector:getScrollVelocity()`
Returns current scroll velocity: `vx, vy`

#### `gesture_detector:getPanState()`
Returns current pan state: `x, y, delta_x, delta_y`

#### `gesture_detector:getZoomState()`
Returns current zoom state: `center_x, center_y, scale`

#### `gesture_detector:getFingerCount()`
Returns number of fingers currently on trackpad.

#### `gesture_detector:getFingers()`
Returns table of current finger data (same format as C library).

## Gesture Detection Logic

### Scroll Detection
- Requires exactly 2 fingers
- Detects when both fingers move in similar direction
- Velocity threshold: 0.01 (configurable)
- Supports both horizontal and vertical scrolling
- Accumulates scroll distance during gesture

### Pan Detection
- Requires exactly 1 finger
- Detects sustained movement above velocity threshold
- Velocity threshold: 0.005 (configurable)
- Tracks total movement from start to end
- Provides delta movement between frames

### Zoom Detection
- Requires exactly 2 fingers
- Measures distance between fingers
- Calculates scale factor relative to initial distance
- Tracks center point of gesture
- Distance change threshold: 0.05 (configurable)

## Configuration

You can modify these constants in the library for different sensitivity:

```lua
local SCROLL_VELOCITY_THRESHOLD = 0.01  -- Minimum velocity for scroll
local PAN_VELOCITY_THRESHOLD = 0.005    -- Minimum velocity for pan
local ZOOM_DISTANCE_THRESHOLD = 0.05    -- Minimum distance change for zoom
```

## Examples

See the included example files:
- `gesture_example.lua` - Basic usage example
- `demos/love2d/gesture_demo.lua` - Full-featured demo with visual feedback

## Coordinate System

- All positions are normalized to 0-1 range
- (0,0) is bottom-left corner of trackpad
- (1,1) is top-right corner of trackpad
- Velocities are in normalized units per second

## Requirements

- macOS with multitouch trackpad
- LuaJIT with FFI support
- TrackpadOSC C library
- LÖVE 2D (for demo examples)

## License

Same as TrackpadOSC project this is based on.