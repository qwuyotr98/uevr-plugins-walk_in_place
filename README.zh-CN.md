# UEVR 原地踏步走路插件

[English](README.md) | **简体中文**

一个给 **UEVR** 用的 Lua 小插件：**只读头显姿态**，识别你是不是在"原地踏步"，然后推左摇杆让角色前进。

适合 **空间小、又想用踏步来移动（减少晕动）** 的玩家。

- 不用动捕、不用手柄、不用装任何额外软件；
- 单文件，复制进 UEVR 脚本目录就能用，删掉即卸载。

---

## 它怎么工作

```
头显姿态（高度 + 俯仰）
   → 去掉缓慢起伏（起身/下蹲/原点漂移）
   → 带通滤波去抖
   → 找"起伏的波峰"，一个波峰 = 一步
   → 步频 → 摇杆力度（踏得越快走得越快）
   → 写入左摇杆
```

点头不算：俯仰角速度超过阈值时，那一下不计步。
静止不算：起伏必须超过"最小抬升"并形成波峰才算一步。

---

## 安装

**方式 A（推荐）**：双击 `install.cmd`
自动装进 `%APPDATA%\UnrealVRMod\*\scripts\`。

**方式 B（手动）**：
把 `walkinplace.lua` 复制到

```
%APPDATA%\UnrealVRMod\<游戏名>\scripts\
```

`<游戏名>` 是 UEVR 里显示的配置名，比如 `HTGame`。

然后启动游戏，UEVR 菜单里点 **Reload Script**。

> 如果提示找不到 `%APPDATA%\UnrealVRMod`，说明这台机器还没用 UEVR 注入过游戏，
> 先注入一次、退出，再装。

---

## 使用

1. 游戏里 UEVR 菜单 → 找到 **Walk in Place** 节点；
2. 点 **Calibrate**：
   - 先**静止 4 秒**（面板显示 `stand still 4s...`）；
   - 变成 `NOW STEP for 8s...` 后**踏步 8 秒**；
   - 结束显示 `done (noise X mm, step Y mm)`；
3. 之后踏步就会走。

面板实时显示：

```
signal +12.4 mm  (recent amp 38.0 mm)
cadence 1.15/s   steps 27   stick 0.78   WALK
nod 6 deg/s   prom 15.2 mm
```

- `cadence` 步频、`steps` 已统计步数、`stick` 当前摇杆力度；
- `signal` 当前起伏、`prom` 当前判定阈值。

---

## 参数

| 滑块 | 默认 | 含义 |
|---|---|---|
| **Min rise (mm)** | 5 | 一次起伏至少几毫米才算一步。**越小越灵敏** |
| **Sensitivity x** | 0.30 | 自适应阈值比例。**越小越灵敏** |
| **Min cadence (/s)** | 0.30 | 低于这个步频不前进 |
| **Stop delay (s)** | 0.55 | 最后一步后多久松摇杆 |
| **Stick max** | 0.90 | 最大移动速度 |
| **Full speed at (/s)** | 2.20 | 步频到多少时用满摇杆 |
| **Nod reject (deg/s)** | 60 | 点头抑制阈值 |
| **Log to file** | 关 | 写日志，排查用 |

### 常见问题怎么调

| 现象 | 调整 |
|---|---|
| 踏步不触发 | `Min rise` 降到 3，或 `Sensitivity x` 降到 0.20 |
| 静止时自己走 | `Min rise` 提到 8~10，`Sensitivity x` 提到 0.45 |
| 一走一停 | `Stop delay` 提到 0.9 |
| 点头也在走 | `Nod reject` 降到 30 |
| 走得太慢 | `Stick max` 提到 1.0 |

---

## 已知限制

**这个插件靠 UEVR 的 `on_xinput_get_state` 回调改摇杆。**

如果游戏启动时没有加载 `xinput1_3.dll`，这个回调不会触发，
插件就"面板正常、`WALK` 亮、但角色不动"。

判断方法——看 UEVR 日志（`%APPDATA%\UnrealVRMod\<游戏名>\log.txt`）：

```
[XInputHook] Failed to find xinput1_3.dll after 10 seconds
```

有这一行 = 该游戏不走 XInput，本插件对它无效。
没有这一行 = 正常可用。

---

## 排查

```powershell
Select-String -Path "$env:APPDATA\UnrealVRMod\<游戏名>\log.txt" -Pattern 'walkinplace' | Select-Object -Last 10
```

正常应看到：

```
[walkinplace] loading v4, state file = ...
[walkinplace] registered on_pre_engine_tick
[walkinplace] registered on_xinput_get_state
[walkinplace] registered on_draw_ui
[walkinplace] loaded v4 (hmd=0)
```

- 有 `Exception in on_draw_ui` → 面板代码报错，看日志那一行的具体内容；
- 什么都没有 → 文件没放进 `scripts` 目录，或没有 Reload。

---

## 卸载

删掉 `scripts\uevr_walkinplace.lua` 即可，不留任何残留。

---

## 说明

个人自用工具，不含任何厂商代码或资源。按 MIT 协议开源，随意修改使用。
VR 软件版本更新可能影响兼容性，届时按脚本内注释调整即可。
