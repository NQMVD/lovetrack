-- Simple example showing how to use the GestureDetector library
local GestureDetector = require("gesture_detector")

local gesture_detector

function love.load()
    -- Initialize the gesture detector
    gesture_detector = GestureDetector.new("trackpad")
    gesture_detector:start()
    
    -- Set up gesture callbacks
    gesture_detector:onScroll(function(vx, vy, accumulated_x, accumulated_y)
        print("Scrolling:", vx, vy)
    end)
    
    gesture_detector:onPanStart(function(x, y)
        print("Pan started at:", x, y)
    end)
    
    gesture_detector:onPanUpdate(function(x, y, dx, dy, total_dx, total_dy)
        print("Panning:", dx, dy)
    end)
    
    gesture_detector:onPanEnd(function(x, y, total_dx, total_dy)
        print("Pan ended, total movement:", total_dx, total_dy)
    end)
    
    gesture_detector:onZoomStart(function(center_x, center_y, scale)
        print("Zoom started at:", center_x, center_y)
    end)
    
    gesture_detector:onZoomUpdate(function(center_x, center_y, scale, distance_change)
        print("Zooming:", scale)
    end)
    
    gesture_detector:onZoomEnd(function(center_x, center_y, final_scale)
        print("Zoom ended, final scale:", final_scale)
    end)
end

function love.update(dt)
    -- Update gesture detection
    gesture_detector:update(dt)
end

function love.draw()
    love.graphics.print("Use trackpad gestures:", 10, 10)
    love.graphics.print("1 finger = pan", 10, 30)
    love.graphics.print("2 fingers = scroll or zoom", 10, 50)
    
    -- Show current gesture states
    local y = 80
    if gesture_detector:isScrolling() then
        love.graphics.print("SCROLLING", 10, y)
        y = y + 20
    end
    if gesture_detector:isPanning() then
        love.graphics.print("PANNING", 10, y)
        y = y + 20
    end
    if gesture_detector:isZooming() then
        love.graphics.print("ZOOMING", 10, y)
        y = y + 20
    end
end

function love.quit()
    gesture_detector:stop()
end