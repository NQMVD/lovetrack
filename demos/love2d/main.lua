local Gesture = require("gesture")

local gesture
local font
local text_scroll_y = 0
local grid_offset_x = 0
local grid_offset_y = 0
local grid_zoom = 1.0
local grid_shapes = {}

-- Sample text for scrolling
local sample_text = [[
Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod
tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim
veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea
commodo consequat.

Duis aute irure dolor in reprehenderit in voluptate velit esse cillum
dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non
proident, sunt in culpa qui officia deserunt mollit anim id est laborum.

Sed ut perspiciatis unde omnis iste natus error sit voluptatem accusantium
doloremque laudantium, totam rem aperiam, eaque ipsa quae ab illo inventore
veritatis et quasi architecto beatae vitae dicta sunt explicabo.

Nemo enim ipsam voluptatem quia voluptas sit aspernatur aut odit aut fugit,
sed quia consequuntur magni dolores eos qui ratione voluptatem sequi
nesciunt. Neque porro quisquam est, qui dolorem ipsum quia dolor sit amet.

At vero eos et accusamus et iusto odio dignissimos ducimus qui blanditiis
praesentium voluptatum deleniti atque corrupti quos dolores et quas
molestias excepturi sint occaecati cupiditate non provident.

This is more text to demonstrate scrolling behavior. The scrolling should
be smooth and responsive to two-finger gestures. You should be able to
scroll up and down easily without it switching to panning mode.

More content here to make the text longer and test the scrolling
functionality properly. The gesture detection should be robust and
maintain the scrolling state throughout the gesture.

Additional paragraphs to ensure we have enough content to scroll through.
The text should scroll smoothly and naturally, just like in any other
application that supports trackpad scrolling.
]]

function love.load()
  love.window.setTitle("Multi-Touch Gesture Test - Final")
  love.window.setMode(1000, 600)

  font = love.graphics.newFont(14)
  love.graphics.setFont(font)

  gesture = Gesture.new({
    deadzone_movement_activate = 3,
    deadzone_movement_continue = 0.1,
    deadzone_zoom_activate = 0.008,
    deadzone_zoom_continue = 0.0005,
    scroll_angle_max = math.rad(30),
    smoothing_factor = 0.65,
    zoom_sensitivity = 1.0,
    min_zoom_distance = 0.01,
  })

  -- Generate grid shapes
  for i = 1, 50 do
    table.insert(grid_shapes, {
      x = (i % 10) * 80 + 40,
      y = math.floor((i - 1) / 10) * 80 + 40,
      color = {
        love.math.random(0.3, 1.0),
        love.math.random(0.3, 1.0),
        love.math.random(0.3, 1.0)
      },
      shape = love.math.random(1, 3)
    })
  end
end

function love.update(dt)
  gesture:update(dt)

  local mouse_x = love.mouse.getX()
  local screen_w = love.graphics.getWidth()

  -- Determine which view we're in
  if mouse_x < screen_w * 0.5 then
    -- Left view - text scrolling
    gesture:setScrollLock(false)
    local scroll_x, scroll_y = gesture:getScrollDelta()
    if gesture:getState() == "scrolling" then
      text_scroll_y = text_scroll_y - scroll_y * 2.0
      text_scroll_y = math.max(0, math.min(text_scroll_y, 3000))
    end
  else
    -- Right view - grid panning and zooming
    gesture:setScrollLock(true)

    local pan_x, pan_y = gesture:getPanDelta()
    local zoom_factor = gesture:getZoomFactor()

    if gesture:getState() == "panning" then
      grid_offset_x = grid_offset_x + pan_x
      grid_offset_y = grid_offset_y + pan_y
    elseif gesture:getState() == "zooming" then
      local center_x, center_y = gesture:getCenter()
      local mouse_x, mouse_y = love.mouse.getPosition()

      if mouse_x > screen_w * 0.5 then
        local local_center_x = center_x - screen_w * 0.5
        local local_center_y = center_y

        local prev_zoom = grid_zoom
        grid_zoom = grid_zoom * zoom_factor
        grid_zoom = math.max(0.2, math.min(8.0, grid_zoom))

        if zoom_factor ~= 1.0 then
          local zoom_ratio = grid_zoom / prev_zoom
          grid_offset_x = (grid_offset_x - local_center_x) * zoom_ratio + local_center_x
          grid_offset_y = (grid_offset_y - local_center_y) * zoom_ratio + local_center_y
        end
      end
    end
  end
end

function love.draw()
  local screen_w, screen_h = love.graphics.getDimensions()
  local mid_x = screen_w * 0.5

  -- Draw divider
  love.graphics.setColor(0.3, 0.3, 0.3)
  love.graphics.line(mid_x, 0, mid_x, screen_h)

  -- Status info with color coding
  local state = gesture:getState()
  local scroll_x, scroll_y = gesture:getScrollDelta()
  local pan_x, pan_y = gesture:getPanDelta()
  local zoom = gesture:getZoomFactor()

  if state == "scrolling" then
    love.graphics.setColor(0.3, 1, 0.3)
  elseif state == "panning" then
    love.graphics.setColor(0.3, 0.3, 1)
  elseif state == "zooming" then
    love.graphics.setColor(1, 0.3, 0.3)
  else
    love.graphics.setColor(0.7, 0.7, 0.7)
  end

  love.graphics.print("State: " .. state, 10, 10)
  love.graphics.setColor(1, 1, 1)
  love.graphics.print(string.format("Scroll: %.2f, %.2f", scroll_x, scroll_y), 10, 25)
  love.graphics.print(string.format("Pan: %.2f, %.2f", pan_x, pan_y), 10, 40)
  love.graphics.print(string.format("Zoom: %.3f Grid: %.3f", zoom, grid_zoom), 10, 55)

  -- Left view - scrollable text
  love.graphics.print("Text View (Scroll vertically)", 10, 80)

  love.graphics.setScissor(0, 100, mid_x, screen_h - 100)
  love.graphics.print(sample_text, 10, 100 - text_scroll_y)
  love.graphics.setScissor()

  -- Right view - pannable/zoomable grid
  love.graphics.setScissor(mid_x, 0, mid_x, screen_h)
  love.graphics.push()
  love.graphics.translate(mid_x + grid_offset_x, grid_offset_y)
  love.graphics.scale(grid_zoom, grid_zoom)

  love.graphics.setColor(1, 1, 1)
  love.graphics.print("Grid View (Pan diagonal, Zoom pinch)", 10, 10)
  love.graphics.print("Zoom: " .. string.format("%.2f", grid_zoom), 10, 30)

  -- Draw grid shapes
  for _, shape in ipairs(grid_shapes) do
    love.graphics.setColor(shape.color)
    if shape.shape == 1 then
      love.graphics.circle("fill", shape.x, shape.y, 20)
    elseif shape.shape == 2 then
      love.graphics.rectangle("fill", shape.x - 20, shape.y - 20, 40, 40)
    else
      love.graphics.polygon("fill", shape.x, shape.y - 20,
        shape.x - 20, shape.y + 15,
        shape.x + 20, shape.y + 15)
    end
  end

  love.graphics.pop()
  love.graphics.setScissor()
end

function love.quit()
  if gesture then
    gesture:destroy()
  end
end
