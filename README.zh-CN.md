# eye-break

[English](README.md) · **中文**

macOS 上的 20-20-20 护眼提醒，按**实际用眼时间**计时，而不是墙上时钟。

> 20-20-20 法则：每用眼 20 分钟，看 20 英尺（约 6 米）外的东西 20 秒。
> 目的是放松睫状肌 —— 长时间近距离对焦累的就是它。

不需要 Homebrew，不是 Electron，也不占菜单栏。两个 shell 脚本 + 一个 40 KB 的
AppleScript 通知器 + 一个 launchd 任务，所有东西都在 `~/.eye-break` 里。

## 为什么不直接设个 20 分钟定时器

因为固定定时器不知道你有没有真的在看屏幕。第 5 分钟你锁屏走了，第 19 分钟回来，
定时器会在你看了 1 分钟屏幕之后就来烦你 —— 而且之后一整天的节奏都是错位的。

`eye-break` 每分钟 tick 一次，只累加你真的在电脑前的时间：

| 情况 | 行为 |
|---|---|
| 正常使用（空闲 < 90 秒） | 正常累加 |
| 短暂发呆（90 秒 ~ 5 分钟） | **暂停累加** —— 你可能只是在读屏幕 |
| 锁屏超过 20 秒 | **清零** —— 这本身就已经是那 20 秒远眺 |
| 锁屏不到 20 秒 | **暂停累加**，进度保留 |
| 没锁屏但 2 分钟没碰键鼠 | **清零** |
| 合盖睡眠后唤醒 | **清零** —— 不会一坐下就被提醒 |
| 攒够了但不在活跃时段 | 跳过并记日志，下一轮从头开始 |

锁屏状态直接读 IORegistry 里的 `IOConsoleLocked`，**不是**用空闲时间推断的。
这一点很关键：锁屏期间 `HIDIdleTime` 会被锁屏界面自己不断重置，你人不在的整段
时间里它都贴着 0，所以任何基于空闲时间的判断都会以为你从没离开过。

## 安装

```sh
git clone https://github.com/chenyuqin98/eye-break.git
cd eye-break
./install.sh --lang zh        # 不加 --lang 则跟随系统语言
```

第一次通知可能需要授权。通知器是一个有独立身份的真 App，所以会作为「护眼提醒」
出现在**系统设置 → 通知**里。建议把样式从「横幅」改成「提醒」—— 提醒不会自动消失，
要手动点掉，对这种「必须真的离开屏幕」的场景更管用。

## 用法

```sh
~/.eye-break/eye-break.sh --status   # 已累计用眼 7 分 1 秒 / 20 分，还差 12 分 59 秒
~/.eye-break/eye-break.sh --now      # 立刻发一轮提醒
~/.eye-break/eye-break.sh --help
```

## 配置

编辑 `~/.eye-break/config`，下一次 tick 就生效，不用重载。

| 配置项 | 默认值 | 含义 |
|---|---|---|
| `LANG_PREF` | `auto` | `auto` / `zh` / `en`，`auto` 跟随系统语言 |
| `ACTIVE_START` / `ACTIVE_END` | `9` / `23` | 只在这个时段提醒 |
| `INTERVAL` | `1200` | 攒够多少秒用眼时间提醒一次 |
| `BREAK_RESET` | `120` | 没锁屏但这么久没碰键鼠就清零 |
| `SLEEP_GAP` | `300` | tick 间隔这么大就判定机器睡过（下限 180） |
| `LOCK_RESET` | `20` | 锁屏超过这么久就清零 |
| `IDLE_PAUSE` | `90` | 空闲超过这么久就暂停累加 |
| `BREAK_SECONDS` | `20` | 远眺时长 |
| `START_SOUND` / `END_SOUND` | `Glass` / `Ping` | `/System/Library/Sounds` 里的任意名字 |

每次提醒从文案池里随机抽，中英各有 14 条开场 + 8 条收尾。想加自己的词，直接往
`eye-break.sh` 顶部的数组里塞，格式是 `"标题|正文"`。

## 工作原理

```
launchd（每 60 秒） -> eye-break.sh -> 从 ioreg 读 HIDIdleTime
                            |
                            +   以及 ioreg 的 IOConsoleLocked
                            |
                            +-- tick间隔>=SLEEP_GAP .. 睡过了：清零，退出
                            +-- 锁屏中 .............. 累加锁屏时长；
                            |                         >= 20 秒 -> 清零，退出
                            +-- 空闲 >= 120 秒 ...... 清零，退出
                            +-- 空闲 >= 90 秒 ....... 暂停，退出
                            +-- 否则 ................ 累加这段间隔
                            |
                            +-- 累计 >= 1200 秒 ----> 提醒，等 20 秒，
                                                      再提醒，然后清零
```

状态就是 `~/.eye-break/state` 里的三个整数：累计用眼秒数、上次 tick 的时间戳、
已锁屏秒数。
判断机器睡没睡过，靠的是 tick 间隔是否超过 `BREAK_RESET`，不需要额外机制。

通知由 `EyeBreak.app` 投递，安装时用 `osacompile` 现编。shell 把
`标题|正文|音效` 写进 `~/.eye-break/msg.txt`，再 `open -n` 拉起 App 读文件并投递。

## 几个坑

- **macOS 自带的 bash 是 3.2.57**（2007 年的版本，GPLv3 的历史遗留）。没有 nameref，
  没有关联数组。`local -n` 能通过 `bash -n` 语法检查但运行时才炸，所以要用
  `/bin/bash` 而不是 Homebrew 的 bash 来测。
- 改 applet 的 `Info.plist` 会让代码签名失效，App 会静默拒绝启动。`install.sh`
  改完会重新 ad-hoc 签名。
- 专注模式 / 勿扰会拦掉通知。这通常正是你想要的 —— 开会时它会自动闭嘴。
- 测试钩子：`EYE_BREAK_FAKE_LOCKED`、`EYE_BREAK_FAKE_IDLE`、`EYE_BREAK_LOG`、
  `EYE_BREAK_STATE`，可以在不碰
  真实数据、不等 20 分钟的前提下把状态机跑一遍。

## 卸载

```sh
./uninstall.sh            # 删掉后台任务和通知器 App
./uninstall.sh --purge    # 连 ~/.eye-break 一起删
```

## 许可

MIT
