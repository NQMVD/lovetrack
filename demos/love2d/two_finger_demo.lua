--[[
    two_finger_demo.lua
    A Love2D demo for the TwoFingerGestureDetector library.

    Instructions:
    - This demo requires the `two_finger_gestures.lua` library to be in the parent directory.
    - Place two fingers on the trackpad to begin.
    - Move fingers parallel to each other to pan.
    - Move fingers up/down in relation to each other to scroll.
    - Pinch or expand fingers to zoom.
--]]

-- Adjust the path if your file structure is different
local TwoFingerGestureDetector = require("../../two_finger_gestures")

-- Global variables
local detector
local gesture_info = {
    type = "None",
    scroll_dx = 0,
    scroll_dy = 0,
    pan_dx = 0,
    pan_dy = 0,
    zoom_scale = 1.0,
    zoom_delta = 0
}

local total_pan = { x = 0, y = 0 }
local total_scroll = { x = 0, y = 0 }

function love.load()
    love.window.setTitle("Two-Finger Gesture Demo")
    love.window.setMode(800, 600)
    love.graphics.setBackgroundColor(0.1, 0.15, 0.2)

    -- Initialize the gesture detector
    -- The path to the C library is relative to the executable
    detector = TwoFingerGestureDetector.new("liblovetrack.dylib")

    if not detector:start() then
        love.event.quit("Failed to start trackpad service. See console for details.")
        return
    end

    -- =========================================================================
    -- Set up callbacks for gestures
    -- =========================================================================

    detector:on_scroll(function(dx, dy)
        gesture_info.type = "Scroll"
        gesture_info.scroll_dx = dx
        gesture_info.scroll_dy = dy
        total_scroll.x = total_scroll.x + dx
        total_scroll.y = total_scroll.y + dy
        print(string.format("Scroll: dx=%.3f, dy=%.3f", dx, dy))
    end)

    detector:on_pan(function(dx, dy)
        gesture_info.type = "Pan"
        gesture_info.pan_dx = dx
        gesture_info.pan_dy = dy
        total_pan.x = total_pan.x + dx
        total_pan.y = total_pan.y + dy
        -- print(string.format("Pan: dx=%.3f, dy=%.3f", dx, dy))
    end)

    detector:on_zoom(function(cx, cy, scale, delta)
        gesture_info.type = "Zoom"
        gesture_info.zoom_scale = scale
        gesture_info.zoom_delta = delta
        -- print(string.format("Zoom: scale=%.3f, delta=%.3f", scale, delta))
    end)

    detector:on_gesture_end(function(last_gesture)
        gesture_info.type = "None"
        -- Reset values on gesture end for a cleaner display
        gesture_info.scroll_dx = 0
        gesture_info.scroll_dy = 0
        gesture_info.pan_dx = 0
        gesture_info.pan_dy = 0
        gesture_info.zoom_delta = 0
        print(string.format("Gesture Ended: %s", last_gesture))
    end)
end

function love.update(dt)
    -- This is the only thing needed in your update loop!
    detector:update(dt)
end

function love.draw()
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf("Place two fingers on the trackpad and move them.", 0, 20, love.graphics.getWidth(), "center")
    love.graphics.printf("Scroll (fingers move opposite), Pan (fingers move together), or Zoom (pinch/expand).", 0, 40, love.graphics.getWidth(), "center")

    -- Display current gesture info
    love.graphics.setFont(love.graphics.newFont(18))
    love.graphics.print("Current Gesture: ", 50, 100)
    love.graphics.setColor(0, 1, 0.5)
    love.graphics.print(gesture_info.type, 250, 100)
    love.graphics.setColor(1, 1, 1)

    -- Draw a dividing line
    love.graphics.line(50, 130, love.graphics.getWidth() - 50, 130)

    -- Display gesture data
    love.graphics.print(string.format("Scroll Delta: (%.3f, %.3f)", gesture_info.scroll_dx, gesture_info.scroll_dy), 50, 150)
    love.graphics.print(string.format("Pan Delta:    (%.3f, %.3f)", gesture_info.pan_dx, gesture_info.pan_dy), 50, 180)
    love.graphics.print(string.format("Zoom Scale:   %.3f", gesture_info.zoom_scale), 50, 210)
    love.graphics.print(string.format("Zoom Delta:   %.3f", gesture_info.zoom_delta), 50, 240)

    -- Display total accumulated values
    love.graphics.line(50, 280, love.graphics.getWidth() - 50, 280)
    love.graphics.print(string.format("Total Scroll: (%.2f, %.2f)", total_scroll.x, total_scroll.y), 50, 300)
    love.graphics.print(string.format("Total Pan:    (%.2f, %.2f)", total_pan.x, total_pan.y), 50, 330)

end

function love.quit()
    if detector then
        detector:stop()
    end
    print("Trackpad service stopped.")
end
