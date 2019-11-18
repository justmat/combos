--
-- oats
--
-- otis and boingg
-- together
--
-- requires otis
--

engine.name = "Decimator"

local sc = include("otis/lib/tlps")
sc.file_path = "/home/we/dust/audio/tape/otis."

local lfo = include("otis/lib/hnds")

local alt = 0
local page = 2
local page_time = 1
local skip_time_L = 1
local skip_time_R = 1
local muted_L = false
local pre_mute_vol_L = 0
local muted_R = false
local pre_mute_vol_R = 0
local rec1 = true
local rec2 = true
local flipped_L = false
local flipped_R = false
local skipped_L = false
local skipped_R = false

local pages = {"mix", "play", "edit", "boingg"}
local skip_options = {"start", "???"}
local speed_options = {"free", "octaves"}

-- for lib/hnds
local lfo_targets = {
  "none",
  "1pan",
  "2pan",
  "1vol",
  "2vol",
  "1feedback",
  "2feedback",
  "1speed",
  "2speed",
  "rec L",
  "rec R",
  "flip L",
  "flip R",
  "skip L",
  "skip R"
}


local g = grid.connect(1)
function g.event(x,y,z) gridkey(x,y,z) end

local GRID_HEIGHT = 8
local DURATION_1 = 1 / 20
local GRID_FRAMERATE = 1 / 60
local SCREEN_FRAMERATE = 1 / 30

local output_options = {"crow cv", "ii jf"}
local notes = { 2, 4, 5, 7, 9, 11, 12, 14, 16, 17, 19, 21, 23, 24, 26, 28 }

local cycles = {}
local cycle_metros = {}
local current_cycle = 1
local transpose = 48

local grid_refresh_metro
local screen_refresh_metro

local function set_output()
  if params:get("output") == 2 then
    crow.ii.pullup(true)
    crow.ii.jf.mode(1)
  else
    crow.ii.pullup(false)
    crow.ii.jf.mode(0)
  end
end


local function midicps(m)
  return (440 / 32) * math.pow(2, (m - 9) / 12)
end


local function draw_cycle(x, stage)
  if g then
    for y = 1 , GRID_HEIGHT do
      g:led(x, y, (y == cycles[x].led_pos) and 15 or 0)
    end
  end
end


local function update_cycle(x, stage)
  ---set led.po
  local h = cycles[x].height
  local a = (stage-1) % (16-2*h) + 1
  cycles[x].led_pos = (a <= (9-h) and 1 or 0) * (a + h - 1) + (a > (9-h) and 1 or 0) * (17 - a - h)
  local on = cycles[x].led_pos == 8
  if on and math.random(100) <= params:get("probability") then
    if params:get("output") == 1 then
      crow.output[1].volts = (notes[x] + params:get("transpose")-60)/12
      crow.output[2].execute()
    elseif params:get("output") == 2 then
      crow.ii.jf.play_note(((notes[x] + params:get("transpose")) - 60) / 12, 5)
    end
  else
    
  end
end


local function start_cycle(x, speed)
  local timer = cycle_metros[x]
  timer.time = 8 / params:get("tempo") * cycles[x].speed
  timer.stage = cycles[x].height
  timer:start()
  timer.event = function(stage)
    update_cycle(x, stage)
    draw_cycle(x, stage)
  end
  cycles[x].running = true
end


local function stop_cycle(x)
  cycle_metros[x]:stop()
  cycle_metros[x].callback = nil
  cycles[x].running = false
  if g then
    for y = 1 , GRID_HEIGHT do
      g:led(x, y, 0)
    end
  end
end


local function skip(n)
  -- reset loop to start, or jump to a random position
  if params:get("skip_controls") == 1 then
    softcut.position(n, params:get(n .. "loop_start"))
  else
    local length = params:get(n .. "tape_len")
    softcut.position(n, lfo.scale(math.random(), params:get(n .. "loop_start"), 1.0, 0.25, length))
  end
end


local function flip(n)
  -- flip tape direction
  local spd = params:get(n .. "speed")
  spd = -spd
  params:set(n .. "speed", spd)
end


local function speed_control(n, d)
  -- free controls
  if params:get("speed_controls") == 1 then
    params:delta(n - 1 .. "speed", d / 7.5)
  else
    -- quantized to octaves
    if params:get(n - 1 .. "speed") == 0 then
      params:set(n - 1 .. "speed", d < 0 and -0.01 or 0.01)
    else
      if d < 0 then
        params:set(n - 1 .. "speed", params:get(n - 1 .. "speed") / 2)
      else
        params:set(n - 1 .. "speed", params:get(n - 1 .."speed") * 2)
      end
    end
  end
end


-- for lib/hnds
function lfo.process()

  for i = 1, 4 do

    local offset = params:get(i .. "offset")
    local target = params:get(i .. "lfo_target")

    if params:get(i .. "lfo") == 2 then
      -- left/right panning, volume, feedback, speed
      if target > 1 and target <= 9 then
        params:set(lfo_targets[target], lfo[i].slope)
      -- record L on/off
      elseif target == 10 then
        if lfo[i].slope > 0 then
          if not rec1 then
            rec1 = true
            softcut.rec(1, 1)
          end
        else
          rec1 = false
          softcut.rec(1, 0)
        end
      -- record R on/off
      elseif target == 11 then
        if lfo[i].slope > 0 then
          if not rec2 then
            rec2 = true
            softcut.rec(2, 1)
          end
        else
          rec2 = false
          softcut.rec(2, 0)
        end
      -- flip L
      elseif target == 12 then
        if lfo[i].slope > 0 then
          if not flipped_L then
            flip(1)
            flipped_L = true
          end
        else flipped_L = false end
      -- flip R
      elseif target == 13 then
        if lfo[i].slope > 0 then
          if not flipped_R then
            flip(2)
            flipped_R = true
          end
        else flipped_R = false end
      -- skip L
      elseif target == 14 then
        if lfo[i].slope > 0 then
          if not skipped_L then
            skip(1)
            skipped_L = true
          end
        else skipped_L = false end
      -- skip R
      elseif target == 15 then
        if lfo[i].slope > 0 then
          if not skipped_R then
            skip(2)
            skipped_R = true
          end
        else skipped_R = false end
      end
    end
  end
end


function init()
  -- sample rate
  params:add_control("sample_rate", "sample rate", controlspec.new(0, 48000, "lin", 10, 48000, ''))
  params:set_action("sample_rate", function(x) engine.srate(x) end)
  -- bit depth
  params:add_control("bit_depth", "bit depth", controlspec.new(4, 31, "lin", 0, 31, ''))
  params:set_action("bit_depth", function(x) engine.sdepth(x) end)
  params:add_separator()

  for i=1, 16 do
    cycle_metros[i] = metro.init()
    cycles[i] = { running = false, keys_pressed = 0, speed = 1, led_pos = 0, height = 0}
  end

  params:add_option("output", "output", output_options, 1)
  params:set_action("output", function() set_output() end)

  params:add_number("tempo", "tempo", 10, 240, 40)
  params:set_action("tempo", function(t)
    for i=1,16 do
      cycle_metros[i].time = 8 / t * cycles[i].speed
    end
  end)

  params:add_number("probability", "probability", 0, 100, 100)

  params:add_number("transpose", "transpose", 0, 127, 48)
  -- for crow
  crow.output[2].action = "{to(5,0),to(0,0.25)}"
  sc.init()
  
  params:add_option("skip_controls", "skip controls", skip_options, 1)
  params:add_option("speed_controls", "speed controls", speed_options, 1)
  
  -- for lib/hnds
  for i = 1, 4 do
    lfo[i].lfo_targets = lfo_targets
  end
  lfo.init()

  params:bang()
  softcut.buffer_clear()

  local screen_metro = metro.init()
  screen_metro.time = 1/30
  screen_metro.event = function() redraw() end
  screen_metro:start()

  if g then g:all(0) end

  grid_refresh_metro = metro.init()
  grid_refresh_metro.time = GRID_FRAMERATE
  grid_refresh_metro.event = function(stage)
    if g then g:refresh() end
  end
  grid_refresh_metro:start()

end


-- norns controls --

local function mix_enc(n, d)
  if alt == 1 then
      if n == 2 then
        params:delta("1pan", d)
      elseif n == 3 then
        params:delta("2pan", d)
      end
  else
    if n == 2 then
      if not muted_L then
        params:delta("1vol", d)
      end
    elseif n == 3 then
      if not muted_R then
        params:delta("2vol", d)
      end
    end
  end
end


local function play_enc(n, d)
  if alt == 1 then
    if n == 2 then
      params:delta("1feedback", d)
    elseif n == 3 then
      params:delta("2feedback", d)
    end
  else
    if n == 2 or n == 3 then
      speed_control(n, d)
    end
  end
end


local function edit_enc(n, d)
  if alt == 1 then
    if n == 2 then
      params:delta("1loop_end", d)
    elseif n == 3 then
      params:delta("2loop_end", d)
    end
  else
    if n == 2 then
      params:delta("1loop_start", d)
    elseif n == 3 then
      params:delta("2loop_start", d)
    end
  end
end


local function boingg_enc(n, d)
  if n == 1 then
    -- nav
  elseif n == 2 then
    if alt == 1 then
      params:delta("tempo", d)
    else
      current_cycle = util.clamp(current_cycle + d, 1, 16)
      redraw()
    end
  elseif n == 3 then
    notes[current_cycle] = util.clamp(notes[current_cycle] + d, -32, 32)
    redraw()
  end
end


function enc(n, d)
  -- navigation
  if n == 1 then
    page = util.clamp(page + d, 1, 4)
    page_time = util.time()
  end
  -- interface pages
  if page == 1 then
    mix_enc(n,d)
  elseif page == 2 then
    play_enc(n, d)
  elseif page == 3 then
    edit_enc(n, d)
  elseif page == 4 then
    boingg_enc(n, d)
  end
end


local function mix_key(n, z)
  if n == 2 and z == 1 then
    if not muted_L then
      pre_mute_vol_L = params:get("1vol")
      softcut.level(1, 0)
      muted_L = true
    else
      softcut.level(1, pre_mute_vol_L)
      muted_L = false
    end
  elseif n == 3 and z == 1 then
    if not muted_R then
      pre_mute_vol_R = params:get("2vol")
      softcut.level(2, 0)
      muted_R = true
    else
      softcut.level(2, pre_mute_vol_R)
      muted_R = false
    end
  end
end


local function play_key(n, z)
  if alt == 1 then
    if n == 2 and z == 1 then
      skip(1)
      skip_time_L = util.time()
    elseif n == 3 and z ==1 then
      skip(2)
      skip_time_R = util.time()
    end
  else
    if n == 2 and z == 1 then
      flip(1)
    elseif n == 3 and z == 1 then
      flip(2)
    end
  end
end


local function edit_key(n, z)
  if alt == 1 then
    if n == 2 and z == 1 then
      softcut.buffer_clear_channel(1)
    elseif n == 3 and z == 1 then
      softcut.buffer_clear_channel(2)
    end
  else
    if n == 2 and z == 1 then
      softcut.rec(1, rec1 == true and 0 or 1)
      rec1 = not rec1
    elseif n == 3 and z == 1 then
      softcut.rec(2, rec2 == true and 0 or 1)
      rec2 = not rec2
    end
  end
end


local function boingg_key(n, z)
  if z == 1 then
    if n == 2 then
      start_cycle(current_cycle,1)
    elseif n == 3 then
      stop_cycle(current_cycle)
    end
  end
end


function key(n, z)
  if n == 1 then alt = z end
  if page == 1 then
    mix_key(n, z)
  elseif page == 2 then
    play_key(n, z)
  elseif page == 3 then
    edit_key(n, z)
  elseif page == 4 then
    boingg_key(n, z)
  end
end

-- screen drawing

local function draw_left()
  -- tape direction indicator
  screen.line_rel(0, -7)
  screen.line_rel(-3, 3)
  screen.line_rel(3, 3)
  screen.fill()
end


local function draw_right()
  -- tape direction indicator
  screen.line_rel(0, -7)
  screen.line_rel(3, 3)
  screen.line_rel(-3, 3)
  screen.fill()
end


local function draw_skip()
  -- skip indicator
  screen.line_rel(0, -5)
  screen.line_rel(-11, 0)
  screen.line_rel(0, 5)
  screen.line_rel(5, 0)
  screen.line_rel(-2, -2)
  screen.line_rel(0, 4)
  screen.line_rel(2, -2)
  screen.stroke()
end


local function draw_skip_rand()
  screen.text("???")
end


local function draw_page_mix()
  -- screen drawing for the mix page
  screen.level(alt == 1 and 3 or 15)
  screen.move(64, 15)
  screen.text_center("volume L : " .. string.format("%.2f", params:get("1vol")))
  screen.move(64, 23)
  screen.text_center("volume R : " .. string.format("%.2f", params:get("2vol")))
  screen.level(alt == 1 and 15 or 3)
  screen.move(64, 31)
  screen.text_center("pan L : " .. string.format("%.2f", params:get("1pan")))
  screen.move(64, 39)
  screen.text_center("pan R : " .. string.format("%.2f", params:get("2pan")))

  screen.level(muted_L == false and 3 or 15)
  screen.move(5, 52)
  screen.text("mute L")
  screen.level(muted_R == false and 3 or 15)
  screen.move(122, 52)
  screen.text_right("mute R")
end


local function draw_page_play()
  -- screen drawing for the play page
  screen.level(alt == 1 and 3 or 15)
  screen.move(64, 15)
  screen.text_center("speed L : " .. string.format("%.2f", math.abs(params:get("1speed"))))
  screen.move(64, 23)
  screen.text_center("speed R : " .. string.format("%.2f", math.abs(params:get("2speed"))))
  screen.level(alt == 1 and 15 or 3)
  screen.move(64, 31)
  screen.text_center("feedback L : " .. string.format("%.2f", params:get("1feedback")))
  screen.move(64, 39)
  screen.text_center("feedback R : " .. string.format("%.2f", params:get("2feedback")))

  screen.move(34, 16)
  screen.level(params:get("1speed") < 0 and 15 or 0)
  draw_left()
  screen.move(34, 24)
  screen.level(params:get("2speed") < 0 and 15 or 0)
  draw_left()
  screen.move(96, 16)
  screen.level(params:get("1speed") > 0 and 15 or 0)
  draw_right()
  screen.move(96, 24)
  screen.level(params:get("2speed") > 0 and 15 or 0)
  draw_right()

  screen.level(alt == 1 and 3 or 15)
  screen.move(5, 52)
  screen.text("flip")
  screen.move(122, 52)
  screen.text_right("flip")
  screen.level(alt == 1 and 15 or 3)
  screen.move(5, 60)
  screen.text("skip")
  screen.move(122, 60)
  screen.text_right("skip")

  if util.time() - skip_time_L < .15 then
    if params:get("skip_controls") == 1 then
      screen.move(18, 40)
      draw_skip()
    else
      screen.move(7, 40)
      draw_skip_rand()
    end
  end

  if util.time() - skip_time_R < .15 then
    if params:get("skip_controls") == 1 then
      screen.move(120, 40)
      draw_skip()
    else
      screen.move(109, 40)
      draw_skip_rand()
    end
  end
end


local function draw_page_edit()
  -- screen drawing for edit page
  screen.level(alt == 1 and 3 or 15)
  screen.move(64, 15)
  screen.text_center("loop start L : " .. string.format("%.2f", params:get("1loop_start")))
  screen.move(64, 23)
  screen.text_center("loop start R : " .. string.format("%.2f", params:get("2loop_start")))
  screen.level(alt == 1 and 15 or 3)
  screen.move(64, 31)
  screen.text_center("loop end L : " .. string.format("%.2f", params:get("1loop_end")))
  screen.move(64, 39)
  screen.text_center("loop end R : " .. string.format("%.2f", params:get("2loop_end")))

  screen.level(alt == 1 and 3 or 15)
  screen.move(5, 52)
  screen.text(rec1 == true and "rec : on" or "rec : off")
  screen.move(122, 52)
  screen.text_right(rec2 == true and "rec : on" or "rec : off")
  screen.level(alt == 1 and 15 or 3)
  screen.move(5, 60)
  screen.text("clear")
  screen.move(122, 60)
  screen.text_right("clear")
end


local function draw_page_boingg()
  screen.line_width(1)

  screen.level(1)
  screen.move(0, 48)
  screen.line(128,48)
  screen.stroke()

  for i=1,16 do
    local x = (i-1) * 8
    local y = 48 - notes[i] - 2

    if i == current_cycle then
      screen.level(1)
      screen.move(x+2, 0)
      screen.line(x+2, 64)
      screen.stroke()
    end

    if cycles[i].running then
      screen.level(15)
    else
      screen.level(i == current_cycle and 7 or 2)
    end
    screen.rect (x, y, 5, 4)
    screen.fill()
    if cycles[i].running then
      screen.circle(x+2,y+(cycles[i].led_pos) * 4 - 32,2)
      screen.fill()
    end
  end

  screen.update()
end


function redraw()
  screen.clear()
  screen.aa(0)
  screen.font_face(25)
  screen.font_size(6)
  screen.move(20 * page, 5)
  -- current page indication
  if util.time() - page_time < .6 then
    screen.level(15)
    screen.text(pages[page])
  else
    screen.level(1)
    screen.text(pages[page])
  end

  if page == 1 then
    draw_page_mix()
  elseif page == 2 then
    draw_page_play()
  elseif page == 3 then
    draw_page_edit()
  elseif page == 4 then
    draw_page_boingg()
  end
  screen.update()
end


function g.key(x, y, s)
  if y == GRID_HEIGHT then
    if s == 1 then stop_cycle(x)
     end
    return
  else
    if s == 1 then
      cycles[x].height = y
      cycles[x].led_pos = 8-y
      start_cycle(x,1)
     --- print("Starting col " .. x .. "height" .. y)
    end
  end
end
