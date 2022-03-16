-- earthbound
--
-- bounds and earthsea
-- together
--

engine.name = 'PolySub'

local sc = include("lib/tlps_earthbound")
sc.file_path = "/home/we/dust/audio/tape/earthbound."

local lfo = include("otis/lib/hnds")

-- for lib hnds
local lfo_targets ={
  "none",
  "1vol",
  "2vol",
  "1pan",
  "2pan",
  "1feedback",
  "2feedback",
  "shape",
  "timbre",
  "sub",
  "noise",
  "detune",
  "cut",
  "ampatk",
  "ampdec",
  "ampsus",
  "amprel"
}

local tab = require 'tabutil'
local pattern_time = require 'pattern_time'

local polysub = require 'polysub'

local g = grid.connect()

local mode = 1
local balls = {}
local cur_ball = 0
local current_spd = {1, 1}
local spds = {.5, 1}
local shift = false
local buffer_hold = false
--local start_time = 0

local mode_transpose = 0
local root = { x=5, y=5 }
local trans = { x=5, y=5 }
local lit = {}

local screen_framerate = 15
local screen_refresh_metro

local ripple_repeat_rate = 1 / 0.3 / screen_framerate
local ripple_decay_rate = 1 / 0.5 / screen_framerate
local ripple_growth_rate = 1 / 0.02 / screen_framerate
local screen_notes = {}

local MAX_NUM_VOICES = 16


local function set_hold()
  -- softcut rec on/off based on buffer_hold
  for i = 1, 2 do
    softcut.rec(i, buffer_hold and 0 or 1)
  end
end


local function skip(n)
  if math.random() <= .25 then
    softcut.position(n, 0)
  end
end


local function flip(n)
  -- flip tape direction
  local spd = current_spd[n]
  spd = -spd
  softcut.rate(n, spd)
  current_spd[n] = spd
end
  

local function set_spd(n)
  local rand = math.random(2)
  local speed = params:get(n .. "speed") * spds[rand]
  if params:get(n .. "speed") < 0 then
    speed = -speed
  end
  softcut.rate(n, speed)
  current_spd[n] = speed
end


function lfo.process()
  -- for lib hnds
  for i = 1, 4 do
    local target = params:get(i .. "lfo_target")

    if params:get(i .. "lfo") == 2 then
      -- left/right volume and feedback.
      params:set(lfo_targets[target], lfo[i].slope)
    end
  end
end

-- pythagorean minor/major, kinda
local ratios = { 1, 9/8, 6/5, 5/4, 4/3, 3/2, 27/16, 16/9 }
local base = 27.5 -- low A


local function getHz(deg,oct)
  return base * ratios[deg] * (2^oct)
end


local function getHzET(note)
  return 55*2^(note/12)
end
-- current count of active voices
local nvoices = 0


function init()
  start_time = util.time()

  m = midi.connect()
  m.event = midi_event

  pat = pattern_time.new()
  pat.process = grid_note_trans

  params:add_option("output", "output", {"audio", "ii JF"}, 1)
  params:set_action("output", function(x) 
    if x == 2 then
      crow.ii.pullup(true)
      crow.ii.jf.mode(1)
    end
  end
  )

  params:add_option("enc2","enc2", {"shape","timbre","noise","cut"})
  params:add_option("enc3","enc3", {"shape","timbre","noise","cut"}, 2)

  params:add_separator()

  polysub:params()
  params:add_separator()
  -- set up tlps/softcut
  sc.init()
  -- set hnds/lfos
  for i = 1, 4 do
    lfo[i].lfo_targets = lfo_targets
  end
  lfo.init()

  -- ball control
  local u = metro.init()
  u.time = 1/60
  u.count = -1
  u.event = update_ball
  u:start()

  engine.stopAll()
  stop_all_screen_notes()

  softcut.buffer_clear()
  params:bang()

  if g then gridredraw() end

  screen_refresh_metro = metro.init()
  screen_refresh_metro.event = function(stage)
    update()
    redraw()
  end
  screen_refresh_metro:start(1 / screen_framerate)
end


function update_ball()
  for i=1,#balls do
    updateball(balls[i])
  end
  redraw()
end


function enc(n, d)
  if n == 1 and not shift then
    mode = util.clamp(mode + d, 1, 2)
  end
  if mode == 1 then
    enc_bounds(n, d)
  elseif mode == 2 then
    enc_earthsea(n, d)
  end
end


function enc_bounds(n, d)
  if n == 1 and shift and cur_ball > 0 then
    -- probability
    balls[cur_ball].prob = util.clamp(balls[cur_ball].prob + d, 0, 100)
  elseif n == 2 then
    -- feedback left
    if shift then
      params:delta("1feedback", d)
    else
      -- rotate
      for i=1,#balls do
        if i == cur_ball then
          balls[i].a = balls[i].a - d / 10
        end
      end
    end
  elseif n == 3 then
    -- feedback right
    if shift then
      params:delta("2feedback", d)
    else
      -- accelerate
      for i=1,#balls do
        if i == cur_ball then
          balls[i].v = balls[i].v + d / 10
        end
      end
    end
  end
end


function enc_earthsea(n,delta)
  if n == 1 then
    --nav
  elseif n == 2 then
    params:delta(params:string("enc2"),delta*4)
  elseif n == 3 then
    params:delta(params:string("enc3"),delta*4)
  end
end


function key(n, z)
  -- shift
  if n == 1 then shift = z == 1 end

  if shift then
    if n == 2 and z == 1 then
      table.remove(balls, cur_ball)
      if cur_ball > #balls then
        cur_ball = #balls
      end
    elseif n == 3 and z == 1 then
      buffer_hold = not buffer_hold
      set_hold()
    end
  else
    if n == 2 and z == 1 then
      -- add ball
      table.insert(balls, newball())
      cur_ball = #balls
    elseif n == 3 and z == 1 and #balls > 0 then
      -- select next ball
      cur_ball = cur_ball % #balls + 1
    end
  end
end


function newball()
  return {
    x = 64,
    y = 32,
    v = 0.5*math.random()+0.2,
    a =  math.random()*2*math.pi,
    prob = 100
  }
end


function drawball(b, hilite)
  screen.level(hilite and 15 or 5)
  screen.circle(b.x, b.y, hilite and 2 or 1.5)
  screen.fill()
end


function updateball(b)
  b.x = b.x + math.sin(b.a)*b.v
  b.y = b.y + math.cos(b.a)*b.v

  local minx = 2
  local miny = 2
  local maxx = 126
  local maxy = 62
  if b.x >= maxx then
    b.x = maxx
    b.a = 2*math.pi - b.a
    if b.y >= maxy / 2 then
      if math.random(100) <= b.prob then
        flip(2)
      end
    else
      if math.random(100) <= b.prob then
        set_spd(2)
      end
    end
  elseif b.x <= minx then
    b.x = minx
    b.a = 2*math.pi - b.a
    if b.y >= maxy / 2 then
      if math.random(100) <= b.prob then
        flip(1)
      end
    else
      if math.random(100) <= b.prob then
        set_spd(1)
      end
    end
  elseif b.y >= maxy then
    b.y = maxy
    b.a = math.pi - b.a

  elseif b.y <= miny then
    b.y = miny
    b.a = math.pi - b.a
    if b.x <= maxx / 2 and math.random(100) <= b.prob then
      skip(1)
    else
      skip(2)
    end
  end
end


function g.key(x, y, z)
  if x == 1 then
    if z == 1 then
      if y == 1 and pat.rec == 0 then
        mode_transpose = 0
        trans.x = 5
        trans.y = 5
        pat:stop()
        engine.stopAll()
        stop_all_screen_notes()
        pat:clear()
        pat:rec_start()
      elseif y == 1 and pat.rec == 1 then
        pat:rec_stop()
        if pat.count > 0 then
          root.x = pat.event[1].x
          root.y = pat.event[1].y
          trans.x = root.x
          trans.y = root.y
          pat:start()
        end
      elseif y == 2 and pat.play == 0 and pat.count > 0 then
        if pat.rec == 1 then
          pat:rec_stop()
        end
        pat:start()
      elseif y == 2 and pat.play == 1 then
        pat:stop()
        engine.stopAll()
        stop_all_screen_notes()
        nvoices = 0
        lit = {}
      elseif y == 8 then
        mode_transpose = 1 - mode_transpose
      end
    end
  else
    if mode_transpose == 0 then
      local e = {}
      e.id = x*8 + y
      e.x = x
      e.y = y
      e.state = z
      pat:watch(e)
      grid_note(e)
    else
      trans.x = x
      trans.y = y
    end
  end
  gridredraw()
end


function grid_note(e)
  local note = ((7-e.y)*5) + e.x
  if e.state > 0 then
    if nvoices < MAX_NUM_VOICES then
      --engine.start(id, getHz(x, y-1))
      --print("grid > "..id.." "..note)
      if params:get("output") == 1 then
        engine.start(e.id, getHzET(note))
      end
      if params:get("output") == 2 then
        crow.ii.jf.play_note((note) / 12, 5)
      end
      start_screen_note(note)
      lit[e.id] = {}
      lit[e.id].x = e.x
      lit[e.id].y = e.y
      nvoices = nvoices + 1
    end
  else
    if lit[e.id] ~= nil then
      engine.stop(e.id)
      stop_screen_note(note)
      lit[e.id] = nil
      nvoices = nvoices - 1
    end
  end
  gridredraw()
end

function grid_note_trans(e)
  local note = ((7-e.y+(root.y-trans.y))*5) + e.x + (trans.x-root.x)
  if e.state > 0 then
    if nvoices < MAX_NUM_VOICES then
      --engine.start(id, getHz(x, y-1))
      --print("grid > "..id.." "..note)
      if params:get("output") == 1 then
        engine.start(e.id, getHzET(note))
      end
      if params:get("output") == 2 then
        crow.ii.jf.play_note((note) / 12, 5)
        --print("crowed")
      end
      start_screen_note(note)
      lit[e.id] = {}
      lit[e.id].x = e.x + trans.x - root.x
      lit[e.id].y = e.y + trans.y - root.y
      nvoices = nvoices + 1
    end
  else
    engine.stop(e.id)
    stop_screen_note(note)
    lit[e.id] = nil
    nvoices = nvoices - 1
  end
  gridredraw()
end

function gridredraw()
  g:all(0)
  g:led(1,1,2 + pat.rec * 10)
  g:led(1,2,2 + pat.play * 10)
  g:led(1,8,2 + mode_transpose * 10)

  if mode_transpose == 1 then g:led(trans.x, trans.y, 4) end
  for i,e in pairs(lit) do
    g:led(e.x, e.y,15)
  end

  g:refresh()
end

function start_screen_note(note)
  local screen_note = nil

  -- Get an existing screen_note if it exists
  local count = 0
  for key, val in pairs(screen_notes) do
    if val.note == note then
      screen_note = val
      break
    end
    count = count + 1
    if count > 8 then return end
  end

  if screen_note then
    screen_note.active = true
  else
    screen_note = {note = note, active = true, repeat_timer = 0, x = math.random(128), y = math.random(64), init_radius = math.random(6,18), ripples = {} }
    table.insert(screen_notes, screen_note)
  end

  add_ripple(screen_note)
end


function stop_screen_note(note)
  for key, val in pairs(screen_notes) do
    if val.note == note then
      val.active = false
      break
    end
  end
end

function stop_all_screen_notes()
  for key, val in pairs(screen_notes) do
    val.active = false
  end
end

function add_ripple(screen_note)
  if tab.count(screen_note.ripples) < 6 then
    local ripple = {radius = screen_note.init_radius, life = 1}
    table.insert(screen_note.ripples, ripple)
  end
end

function update()
  for n_key, n_val in pairs(screen_notes) do

    if n_val.active then
      n_val.repeat_timer = n_val.repeat_timer + ripple_repeat_rate
      if n_val.repeat_timer >= 1 then
        add_ripple(n_val)
        n_val.repeat_timer = 0
      end
    end

    local r_count = 0
    for r_key, r_val in pairs(n_val.ripples) do
      r_val.radius = r_val.radius + ripple_growth_rate
      r_val.life = r_val.life - ripple_decay_rate

      if r_val.life <= 0 then
        n_val.ripples[r_key] = nil
      else
        r_count = r_count + 1
      end
    end

    if r_count == 0 and not n_val.active then
      screen_notes[n_key] = nil
    end
  end
end


function redraw_earthsea()
  screen.clear()
  screen.aa(0)
  screen.line_width(1)
  screen.font_size(24)
  screen.level(1)
  screen.move(64, 36)
  screen.text_center("earthsea")
  local first_ripple = true
  for n_key, n_val in pairs(screen_notes) do
    for r_key, r_val in pairs(n_val.ripples) do
      if first_ripple then -- Avoid extra line when returning from menu
        screen.move(n_val.x + r_val.radius, n_val.y)
        first_ripple = false
      end
      screen.level(math.max(1,math.floor(r_val.life * 15 + 0.5)))
      screen.circle(n_val.x, n_val.y, r_val.radius)
      screen.stroke()
    end
  end

  screen.update()
end


function redraw_bounds()
  screen.clear()
  screen.aa(1)
  screen.font_size(24)
  screen.level(1)
  screen.move(64, 36)
  screen.text_center("bounds")
  if shift then
    -- draw bounds
    screen.clear()
    screen.level(4)
    screen.line_width(1)
    screen.rect(1, 1, 126, 62)
    screen.stroke()
    -- draw loop info
    screen.level(1)
    screen.move(8, 30)
    screen.font_size(8)
    screen.text("spd: ")
    screen.move(40, 30)
    screen.text( "L : ".. current_spd[1])
    screen.move(8, 40)
    screen.text("fbk: ")
    screen.move(40, 40)
    screen.text("L : " .. params:get("1feedback"))
    screen.move(88, 30)
    screen.text("R : " .. current_spd[2])
    screen.move(88, 40)
    screen.text("R : " .. params:get("2feedback"))
    screen.move(64, 16)
    if #balls > 0 then
      screen.text_center("ball ".. cur_ball .. " prob : " .. balls[cur_ball].prob .. "%")
    else
      screen.text_center("ball - prob :  -")
    end
    screen.move(64, 52)
    screen.text_center(buffer_hold and "held" or "recording...")
  end
  for i=1,#balls do
    drawball(balls[i], i == cur_ball)
  end
  screen.update()
end


function redraw()
  if mode == 1 then
    redraw_bounds()
  elseif mode == 2 then
    redraw_earthsea()
  end
end


function note_on(note, vel)
  if nvoices < MAX_NUM_VOICES then
    --engine.start(id, getHz(x, y-1))
    engine.start(note, getHzET(note))
    start_screen_note(note)
    nvoices = nvoices + 1
  end
end

function note_off(note, vel)
  engine.stop(note)
  stop_screen_note(note)
  nvoices = nvoices - 1
end


function midi_event(data)
  if #data == 0 then return end
  local msg = midi.to_msg(data)

  -- Note off
  if msg.type == "note_off" then
    note_off(msg.note)

    -- Note on
  elseif msg.type == "note_on" then
    note_on(msg.note, msg.vel / 127)

--[[
    -- Key pressure
  elseif msg.type == "key_pressure" then
    set_key_pressure(msg.note, msg.val / 127)

    -- Channel pressure
  elseif msg.type == "channel_pressure" then
    set_channel_pressure(msg.val / 127)

    -- Pitch bend
  elseif msg.type == "pitchbend" then
    local bend_st = (util.round(msg.val / 2)) / 8192 * 2 -1 -- Convert to -1 to 1
    local bend_range = params:get("bend_range")
    set_pitch_bend(bend_st * bend_range)

  ]]--
  end

end


function cleanup()
  stop_all_screen_notes()
  pat:stop()
  pat = nil
end
