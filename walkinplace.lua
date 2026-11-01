--[[
  uevr_walkinplace.lua —— UEVR 原地踏步插件（纯头显版 v4）

  只读头显姿态，不依赖动捕、不读 tracker。

  信号处理（每一帧）：
    1) 基线：y 的低通（τ=3s），用来去掉缓慢的起身/下蹲/漂移；
    2) 带通：d = y - 基线，再做 τ=0.09s 的低通去抖；
    3) 峰检测：d 的局部极大值，prominence 自适应（近期幅度的 40%），
       两步最小间隔 0.25s；每检出一个峰 = 一步；
    4) 点头抑制：俯仰角速度超过 Nod reject 时的峰不计。

  速度：步频越高走越快（cadence → stick 线性映射）。

  标定：面板点 Calibrate → 静止 4 秒 → 踏步 8 秒，
        自动测出噪声底与踏步幅度，并设好阈值。

  面板：UEVR 菜单 → "Walk in Place"
  日志：%APPDATA%\UnrealVRMod\<game>\log.txt，搜 [walkinplace]
]]

local CFG = {
    enabled    = true,
    stick      = 0.90,   -- 最大摇杆量
    min_prom   = 0.005,  -- 峰的最小起伏(米)：一步至少抬头 8mm
    prom_frac  = 0.30,   -- 自适应：近期幅度的 40%
    min_gap    = 0.22,   -- 两步最小间隔(秒)
    min_hz     = 0.30,   -- 低于这个步频不走
    stop_delay = 0.55,   -- 最后一步后多久松摇杆(秒)
    nod        = 60.0,   -- 点头抑制(度/秒)
    speed_min  = 0.45,   -- 慢速踏步时的摇杆下限
    speed_full = 2.20,   -- 达到这个步频时用满 stick
    base_tau   = 3.0,    -- 基线低通时间常数(秒)
    smooth_tau = 0.09,   -- 信号低通时间常数(秒)
    debug      = false,
}

local CAL = { phase = 0, t0 = 0.0, idle_rms = 0.0, idle_n = 0,
              step_amp = 0.0, step_n = 0, msg = "idle" }

local TAG = "[walkinplace] "

local function log(msg)
    local ok = pcall(function() uevr.params.functions.log_info(TAG .. msg) end)
    if not ok then print(TAG .. msg) end
end

log("loading v4 (HMD only)")

local cbs = nil
pcall(function() cbs = uevr.sdk.callbacks end)
if cbs == nil then pcall(function() cbs = uevr.params.callbacks end) end
if cbs == nil then log("no callbacks table, abort"); return end

local function reg(name, fn)
    if cbs[name] == nil then log("callback missing: " .. tostring(name)); return false end
    local ok, err = pcall(function() cbs[name](fn) end)
    if ok then log("registered " .. tostring(name))
    else log("register " .. tostring(name) .. " failed: " .. tostring(err)) end
    return ok
end

local vr = nil
pcall(function() vr = uevr.params.vr end)
if vr == nil then log("no uevr.params.vr, abort"); return end

local hmd = -1
pcall(function() hmd = vr.get_hmd_index() end)

local pos, rot = nil, nil
pcall(function() pos = UEVR_Vector3f.new() end)
pcall(function() rot = UEVR_Quaternionf.new() end)

-- ---------------- 状态 ----------------
local t = 0.0
local last_y, last_pitch = nil, nil
local base = nil          -- 基线（低通 y）
local d_raw = 0.0         -- y - 基线
local d_sm = 0.0          -- 带通后的信号
local pitch_rate = 0.0

local amp_hi, amp_lo = 0.0, 0.0   -- 近期幅度（用于自适应 prominence）
local peak_v, peak_t, trough_v = nil, nil, nil
local last_peak_t = -100.0
local last_step_t = -100.0
local cadence = 0.0
local steps = 0
local walking = false
local stick_now = 0.0
local blocking = false     -- 当前是否有峰正在进行

local t_dbg = 0.0
local ui_calls = 0

local function pitch_of(q)
    local v = 2.0 * (q.w * q.y - q.z * q.x)
    if v > 1.0 then v = 1.0 end
    if v < -1.0 then v = -1.0 end
    return math.asin(v) * 57.29578
end

local function start_calibration()
    CAL.phase = 1; CAL.t0 = t
    CAL.idle_rms = 0.0; CAL.idle_n = 0
    CAL.step_amp = 0.0; CAL.step_n = 0
    CAL.msg = "stand still 4s..."
    last_step_t = -100.0
    walking = false
    log("calibration: stand still for 4s, then step 8s")
end

local function finish_calibration()
    local noise = math.max(0.002, CAL.idle_rms)
    -- 峰的最小起伏：取噪声的 2.5 倍，但不超过实测踏步幅度的 45%
    local prom = noise * 2.5
    if CAL.step_amp > 0 then prom = math.min(prom, CAL.step_amp * 0.45) end
    prom = math.max(0.004, math.min(0.05, prom))
    CFG.min_prom = prom
    CAL.phase = 0
    CAL.msg = string.format("done (noise %.1fmm, step %.0fmm)", noise * 1000.0, CAL.step_amp * 1000.0)
    log(string.format("calibration done: idle_rms=%.4f step_amp=%.4f -> min_prom=%.4f", noise, CAL.step_amp, prom))
end

reg("on_pre_engine_tick", function(engine, delta)
    if delta == nil or delta <= 0 then return end
    t = t + delta
    if pos == nil or rot == nil then return end
    if not pcall(function() vr.get_pose(hmd, pos, rot) end) then return end

    local y = pos.y
    local pitch = pitch_of(rot)

    -- 俯仰角速度（点头检测）
    if last_pitch ~= nil and delta > 0 then
        local pr = math.abs(pitch - last_pitch) / delta
        pitch_rate = pitch_rate + (pr - pitch_rate) * math.min(1.0, delta / 0.10)
    end
    last_pitch = pitch

    -- 基线 + 带通 + 低通
    if base == nil then base = y end
    local kb = math.min(1.0, delta / CFG.base_tau)
    base = base + (y - base) * kb
    d_raw = y - base
    local ks = math.min(1.0, delta / CFG.smooth_tau)
    d_sm = d_sm + (d_raw - d_sm) * ks
    last_y = y

    -- 近期幅度（2 秒衰减的记忆）
    local decay = math.exp(-delta / 2.0)
    amp_hi = amp_hi * decay
    amp_lo = amp_lo * decay
    if d_sm > amp_hi then amp_hi = d_sm end
    if d_sm < amp_lo then amp_lo = d_sm end
    local recent_amp = amp_hi - amp_lo

    -- ---------- 标定 ----------
    if CAL.phase == 1 then
        CAL.idle_rms = CAL.idle_rms + (d_sm * d_sm - CAL.idle_rms) * math.min(1.0, delta / 1.0)
        CAL.idle_n = CAL.idle_n + 1
        if t - CAL.t0 >= 4.0 then
            CAL.phase = 2; CAL.t0 = t
            CAL.msg = "NOW STEP for 8s..."
            log(string.format("calibration: idle done, rms=%.4f", math.sqrt(math.max(0, CAL.idle_rms))))
        end
        walking = false
        return
    elseif CAL.phase == 2 then
        if recent_amp > CAL.step_amp then CAL.step_amp = recent_amp end
        if t - CAL.t0 >= 8.0 then
            CAL.idle_rms = math.sqrt(math.max(0, CAL.idle_rms))
            finish_calibration()
        end
        walking = false
        return
    end

    -- ---------- 峰检测 ----------
    local prom = math.max(CFG.min_prom, CFG.prom_frac * recent_amp)

    if peak_v == nil then
        peak_v, trough_v, peak_t = d_sm, d_sm, t
    else
        if d_sm > peak_v then
            peak_v, peak_t = d_sm, t
        end
        if d_sm < trough_v then trough_v = d_sm end

        if (peak_v - d_sm) > prom and (peak_t - last_step_t) >= CFG.min_gap then
            -- 峰成立 = 一步
            local ok_nod = (pitch_rate <= CFG.nod)
            if ok_nod then
                local gap = peak_t - last_step_t
                if gap > 0 and gap < 2.0 then
                    cadence = cadence + ((1.0 / gap) - cadence) * 0.4
                end
                last_step_t = peak_t
                steps = steps + 1
            end
            last_peak_t = peak_t
            peak_v, trough_v = d_sm, d_sm
            peak_t = t
        end
    end

    -- ---------- 走路状态 ----------
    local fresh = (t - last_step_t) <= CFG.stop_delay
    local rate_ok = cadence >= CFG.min_hz
    walking = CFG.enabled and fresh and rate_ok

    if walking then
        local span = math.max(0.1, CFG.speed_full - CFG.min_hz)
        local f = (cadence - CFG.min_hz) / span
        if f < 0 then f = 0 end
        if f > 1 then f = 1 end
        local target = CFG.speed_min + (1.0 - CFG.speed_min) * f
        stick_now = stick_now + (target * CFG.stick - stick_now) * math.min(1.0, delta / 0.12)
    else
        stick_now = 0.0
    end

    if CFG.debug and t - t_dbg >= 1.0 then
        t_dbg = t
        log(string.format("y=%.3f d=%+.4f prom=%.4f amp=%.3f cad=%.2f/s steps=%d stick=%.2f walk=%s",
            y, d_sm, prom, recent_amp, cadence, steps, stick_now, tostring(walking)))
    end
end)

reg("on_xinput_get_state", function(retval, user_index, state)
    if state == nil or not walking then return end
    local gp = state.Gamepad
    if gp == nil then return end
    local want = math.floor(stick_now * 32767)
    if gp.sThumbLY < want then gp.sThumbLY = want end
end)

reg("on_draw_ui", function()
    ui_calls = ui_calls + 1
    if ui_calls == 1 then log("on_draw_ui first call") end
    if imgui == nil then
        if ui_calls == 1 then log("imgui not available") end
        return
    end
    if not imgui.tree_node("Walk in Place") then return end

    local c
    c, CFG.enabled = imgui.checkbox("Enable", CFG.enabled)

    if imgui.button("Calibrate (still 4s + step 8s)") then
        start_calibration()
    end
    imgui.text("  " .. CAL.msg)

    -- 注意：imgui.slider_float 返回 (changed, value)。
    -- 不能写 "c, x = f() / 1000"，那样会对布尔值做算术运算而报错。
    local ch, v
    ch, v = imgui.slider_float("Min rise (mm)", CFG.min_prom * 1000.0, 1.0, 40.0)
    if v ~= nil then c = ch; CFG.min_prom = v / 1000.0 end

    ch, v = imgui.slider_float("Sensitivity x (lower=easier)", CFG.prom_frac, 0.10, 0.90)
    if v ~= nil then c = ch; CFG.prom_frac = v end

    ch, v = imgui.slider_float("Min cadence (/s)", CFG.min_hz, 0.15, 1.50)
    if v ~= nil then c = ch; CFG.min_hz = v end

    ch, v = imgui.slider_float("Stop delay (s)", CFG.stop_delay, 0.15, 1.50)
    if v ~= nil then c = ch; CFG.stop_delay = v end

    ch, v = imgui.slider_float("Stick max", CFG.stick, 0.10, 1.00)
    if v ~= nil then c = ch; CFG.stick = v end

    ch, v = imgui.slider_float("Full speed at (/s)", CFG.speed_full, 1.00, 3.50)
    if v ~= nil then c = ch; CFG.speed_full = v end

    ch, v = imgui.slider_float("Nod reject (deg/s)", CFG.nod, 10.0, 300.0)
    if v ~= nil then c = ch; CFG.nod = v end

    c, CFG.debug = imgui.checkbox("Log to file", CFG.debug)

    imgui.spacing()
    imgui.text(string.format("signal %+.1f mm  (recent amp %.1f mm)", d_sm * 1000.0, (amp_hi - amp_lo) * 1000.0))
    imgui.text(string.format("cadence %.2f/s   steps %d   stick %.2f   %s",
        cadence, steps, stick_now, walking and "WALK" or "idle"))
    imgui.text(string.format("nod %.0f deg/s   prom %.1f mm",
        pitch_rate, math.max(CFG.min_prom, CFG.prom_frac * (amp_hi - amp_lo)) * 1000.0))

    imgui.tree_pop()
end)

log(string.format("loaded v4 (hmd=%d)", hmd))
