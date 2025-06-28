local Gestures = require("gestures")

local gesture_detector
local camera = { x = 0, y = 0, zoom = 1.0 }
local scroll_history = {}
local max_scroll_history = 50

-- Visual feedback
local pan_trail = {}
local zoom_indicator = { active = false, x = 0, y = 0, scale = 1.0, timer = 0 }
-- Removed scroll_indicator as scroll is now part of pan

function love.conf(t)
  t.window.title = "Trackpad Gesture Detection Demo"
  t.highdpi = true
  t.window.msaa = 8
  t.window.resizable = true
  t.window.width = 1200
  t.window.height = 800
end

function love.load()
  -- Initialize gesture detector
  gesture_detector = Gestures.new("liblovetrack.dylib")
  gesture_detector:start()

  -- Set up gesture callbacks
  -- Removed on_scroll callback

  gesture_detector:on_pan_start(function(x, y)
    pan_trail = { { x = x, y = y, time = love.timer.getTime() } }
    print(string.format("Pan Start: (%.3f, %.3f)", x, y))
  end)

  gesture_detector:on_pan_update(function(x, y, dx, dy, total_dx, total_dy)
    -- Update camera position
    camera.x = camera.x - dx * 500 * camera.zoom
    camera.y = camera.y - dy * 500 * camera.zoom

    -- Add to pan trail
    table.insert(pan_trail, { x = x, y = y, time = love.timer.getTime() })
    if #pan_trail > 20 then
      table.remove(pan_trail, 1)
    end

    print(string.format("Pan Update: pos(%.3f, %.3f), delta(%.3f, %.3f), total(%.3f, %.3f)",
      x, y, dx, dy, total_dx, total_dy))
  end)

  gesture_detector:on_pan_end(function(x, y, total_dx, total_dy)
    print(string.format("Pan End: (%.3f, %.3f), total(%.3f, %.3f)", x, y, total_dx, total_dy))
  end)

  gesture_detector:on_zoom_start(function(center_x, center_y, scale)
    zoom_indicator.active = true
    zoom_indicator.x = center_x
    zoom_indicator.y = center_y
    zoom_indicator.scale = scale
    zoom_indicator.timer = 1.0
    print(string.format("Zoom Start: center(%.3f, %.3f), scale=%.3f", center_x, center_y, scale))
  end)

  gesture_detector:on_zoom_update(function(center_x, center_y, scale, distance_change)
    -- Update camera zoom
    local zoom_factor = scale / camera.zoom
    camera.zoom = scale

    -- Zoom towards the center point
    local screen_center_x = center_x * love.graphics.getWidth()
    local screen_center_y = center_y * love.graphics.getHeight()

    camera.x = camera.x + (screen_center_x - camera.x) * (1 - 1 / zoom_factor)
    camera.y = camera.y + (screen_center_y - camera.y) * (1 - 1 / zoom_factor)

    -- Update zoom indicator
    zoom_indicator.x = center_x
    zoom_indicator.y = center_y
    zoom_indicator.scale = scale
    zoom_indicator.timer = 1.0

    print(string.format("Zoom Update: center(%.3f, %.3f), scale=%.3f, change=%.3f",
      center_x, center_y, scale, distance_change))
  end)

  gesture_detector:on_zoom_end(function(center_x, center_y, final_scale)
    zoom_indicator.active = false
    print(string.format("Zoom End: center(%.3f, %.3f), final_scale=%.3f", center_x, center_y, final_scale))
  end)

  print("Gesture Detection Demo Started")
  print("- Use 2 fingers to pan or zoom (pinch/expand)")
end

function love.update(dt)
  gesture_detector:update(dt)

  -- Update visual indicators
  -- Removed scroll_indicator update

  if zoom_indicator.timer > 0 then
    zoom_indicator.timer = zoom_indicator.timer - dt
  end

  -- Clean up old scroll history (no longer needed)
  scroll_history = {}

  -- Clean up old pan trail
  local current_time = love.timer.getTime()
  for i = #pan_trail, 1, -1 do
    if current_time - pan_trail[i].time > 1.0 then
      table.remove(pan_trail, i)
    end
  end
end

function love.draw()
  love.graphics.clear(0.1, 0.1, 0.15)

  -- Apply camera transform
  love.graphics.push()
  love.graphics.translate(-camera.x, -camera.y)
  love.graphics.scale(camera.zoom)

  -- Draw a grid to show pan/zoom effects
  love.graphics.setColor(0.3, 0.3, 0.4, 0.5)
  love.graphics.setLineWidth(1)

  local grid_size = 100
  local start_x = math.floor(camera.x / camera.zoom / grid_size) * grid_size
  local start_y = math.floor(camera.y / camera.zoom / grid_size) * grid_size
  local end_x = start_x + love.graphics.getWidth() / camera.zoom + grid_size
  local end_y = start_y + love.graphics.getHeight() / camera.zoom + grid_size

  for x = start_x, end_x, grid_size do
    love.graphics.line(x, start_y, x, end_y)
  end
  for y = start_y, end_y, grid_size do
    love.graphics.line(start_x, y, end_x, y)
  end

  -- Draw some objects to interact with
  love.graphics.setColor(0.8, 0.4, 0.2)
  love.graphics.rectangle("fill", 200, 200, 100, 100)
  love.graphics.setColor(0.2, 0.8, 0.4)
  love.graphics.circle("fill", 500, 300, 50)
  love.graphics.setColor(0.4, 0.2, 0.8)
  love.graphics.rectangle("fill", 300, 500, 150, 75)

  love.graphics.pop()

  -- Draw current finger positions
  love.graphics.setColor(1, 1, 1, 0.8)
  for id, finger in pairs(gesture_detector:getFingers()) do
    local x = finger.x * love.graphics.getWidth()
    local y = finger.y * love.graphics.getHeight()

    -- Draw finger circle
    local color = finger.state == 4 and { 0, 1, 0 } or { 1, 1, 0 }
    love.graphics.setColor(color[1], color[2], color[3], 0.7)
    love.graphics.circle("fill", x, y, finger.size * 20 + 10)

    -- Draw velocity vector
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.setLineWidth(2)
    love.graphics.line(x, y, x + finger.vx * 100, y + finger.vy * 100)

    -- Draw finger ID
    love.graphics.setColor(1, 1, 1)
    love.graphics.print(tostring(finger.id), x - 5, y - 5)
  end

  -- Draw pan trail
  if #pan_trail > 1 then
    love.graphics.setColor(1, 0.5, 0, 0.6)
    love.graphics.setLineWidth(3)
    for i = 2, #pan_trail do
      local p1 = pan_trail[i - 1]
      local p2 = pan_trail[i]
      love.graphics.line(
        p1.x * love.graphics.getWidth(), p1.y * love.graphics.getHeight(),
        p2.x * love.graphics.getWidth(), p2.y * love.graphics.getHeight()
      )
    end
  end

  -- Removed scroll indicator drawing

  -- Draw zoom indicator
  if zoom_indicator.active and zoom_indicator.timer > 0 then
    local alpha = zoom_indicator.timer
    love.graphics.setColor(1, 0, 1, alpha)
    local x = zoom_indicator.x * love.graphics.getWidth()
    local y = zoom_indicator.y * love.graphics.getHeight()
    local radius = 30 * zoom_indicator.scale
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", x, y, radius)
    love.graphics.print(string.format("ZOOM %.2fx", zoom_indicator.scale), x + radius + 10, y)
  end

  -- Draw UI
  love.graphics.setColor(1, 1, 1, 0.9)
  love.graphics.print("Gesture Detection Demo", 10, 10)
  love.graphics.print(string.format("Camera: x=%.1f, y=%.1f, zoom=%.2fx", camera.x, camera.y, camera.zoom), 10, 30)
  love.graphics.print(string.format("Fingers: %d", gesture_detector:getFingerCount()), 10, 50)

  -- Instructions
  love.graphics.setColor(1, 1, 1, 0.7)
  love.graphics.print("Instructions:", 10, love.graphics.getHeight() - 80)
  love.graphics.print("• 2 fingers: Pan or Zoom (pinch/expand)", 10, love.graphics.getHeight() - 60)
  love.graphics.print("• ESC: Quit", 10, love.graphics.getHeight() - 40)
end

function love.keypressed(key)
  if key == "escape" then
    love.event.quit()
  elseif key == "r" then
    -- Reset camera
    camera.x = 0
    camera.y = 0
    camera.zoom = 1.0
  end
end

function love.quit()
  gesture_detector:stop()
  print("Gesture Detection Demo Stopped")
end
