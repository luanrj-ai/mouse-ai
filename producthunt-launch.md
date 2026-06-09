# Product Hunt 发布套件 · mouseAI(看懂)

> 给你的发布参考。**英文部分 = 直接抄到 Product Hunt**;中文部分 = 给你的说明。
> 核心定位:别主打"给小白",主打**"给你的 Mac 装一个全局快捷键:选中任何东西→大白话解释,
> 用你自己的 Claude Code,零成本、全本地"**,把"cc 动手前帮你拦一下"当杀手锏。

---

## 1. 名字(Name)

保持 **mouseAI**(和落地页一致)。PH 上 Name 填 `mouseAI`,后面靠 tagline 说清楚。
> "看懂 / kàndǒng" 老外读不懂,放在描述里当 origin story 用,别当主名。

---

## 2. Tagline(PH 限 60 字符,挑一个)

英文,逐条都数过字符,选你最顺眼的:

1. `Understand anything on your screen — via your Claude Code`  ← ✅ 已选(56)
2. `Select anything, get it explained. $0 extra, fully local.`  (57)
3. `A hotkey that explains anything, using your own Claude Code`  (58)
4. `Plain-English for anything on screen. Runs on your cc.`  (54)

> 推荐 1:点出"任何东西 + 用你自己的 cc",两个钩子都在。

---

## 3. Description(tagline 下方那段短描述)

```
A system-wide hotkey for your Mac: select anything you don't understand —
a term, an error, foreign text, a scary command — and get it in plain English
in seconds. It runs on the Claude Code you already have: no API key, no extra
cost, and your screen content never leaves your machine. When Claude Code wants
to run a command, it also tells you what it does, the risk, and whether to allow it.
```

---

## 4. 首条 Maker 评论(最重要 —— PH 吃故事)

```
Hi PH 👋 I built mouseAI after watching a non-technical friend use Claude Code.
She could get it to write working code — but kept freezing at a wall of red
errors, an English term, or a "Do you want to proceed?" and just clicked
continue on a hunch. The model wasn't the missing piece. A layer she could
SEE and UNDERSTAND was.

So: select anything on your screen, hit ⌥? , and get a plain-English
explanation in seconds. Browser, PDF, terminal — any window.

Three things I cared about:
• It runs on your OWN Claude Code (any plan). No API key, no new subscription,
  $0 extra. Same engine you already use.
• Fully local. Your selected text and screen content NEVER reach me. The only
  thing I get is an anonymous "someone used it today" heartbeat (one command
  turns it off).
• When cc wants to run something risky (rm -rf, sudo…), it flags the risk
  BEFORE you approve. The "AI is about to do something — should I let it?"
  moment, handled.

Heads up — honest about scope:
• macOS only for now (Linux/Windows on the way)
• Requires Claude Code already installed + logged in (it's the engine)
• Fully open source — read it before you install

Would love your brutal feedback, especially on the install flow. AMA 🙏
```

---

## 5. Gallery(图/GIF,第 1 张必须是动图)

顺序就是说服顺序:

1. **(GIF,放第一)** 在浏览器划选一个术语 → 浮窗秒出大白话。**这是 5 秒 aha。**
2. **(GIF/图)** cc 要跑 `rm -rf /var/lib/test-db/*` → 浮窗 "⚠ 不可恢复,建议先看一眼"。
   ← 最可能被转发的一张。Caption: `It warns you before you approve a risky command.`
3. 一屏红色报错 → 一句话解释。Caption: `A wall of red, in one plain sentence.`
4. 成本/隐私图:`Runs on your own Claude Code · $0 API · nothing leaves your Mac.`
5. "越用越懂你"记忆功能。Caption: `It remembers what keeps tripping you up.`

> 图上的字用英文。GIF 比静图重要 10 倍。

---

## 6. Topics / Tags(PH 分类,选 3-4 个)

`Developer Tools` · `Artificial Intelligence` · `Mac` · `Productivity`

---

## 7. 评论区常见问题 · 预备回复(直接抄)

**"Does it cost extra / need another API key?"**
```
No. It uses the Claude Code you're already logged into — your existing plan.
No API key, no server of mine, no new account.
```

**"It reads my screen? Privacy?"**
```
It reads TEXT (not screenshots), and only: (1) what you actively select,
(2) the visible text of the frontmost window when you press the key. That text
goes to your own cc to explain — it never reaches me. It's fully open source,
read it before installing.
```

**"Windows / Linux?"**
```
macOS only for v0 (it's built on Hammerspoon for the global hotkey + screen
selection). Linux/Windows are on the roadmap — would love to know which you'd want.
```

**"Why Hammerspoon / why not a standalone app?"**
```
v0 wedge — Hammerspoon gives me a system-wide hotkey + accessibility read with
zero app to maintain. A signed standalone app is the natural next step.
```

---

## 8. 发布机制清单(不懂也能照做)

- [ ] **时间**:PH 一天一榜,排名按当天票数。挑**周二/周三**,在 **太平洋时间 00:01(PT)** 发(= 北京时间下午 3:01 左右,注意夏令时)。一上线就有一整天积累。
- [ ] **Hunter**:自己发就行(self-launch 现在完全 OK),不必非找大 V hunter。找得到相关领域的人帮 hunt 更好,但别为这个拖延。
- [ ] **首条 maker 评论**:发布**那一刻立刻贴**(上面第 4 节)。这是你和访客的第一句话。
- [ ] **别求票**:PH 规则禁止"求 upvote"。对外只说 **"we just launched, would love your feedback"**,放链接。求反馈不犯规,求票会被降权。
- [ ] **首日盯评论**:每条都快速回(上面第 7 节备好了)。回复速度 = 排名信号 + 信任。
- [ ] **第一张是 GIF**:没好 GIF 就别急着发。
- [ ] **硬依赖写在最前**:Requires macOS + Claude Code。挡掉装不上来骂街的。
- [ ] **同步引流**:小红书(你已有素材)、X/Twitter、相关 Discord/微信群同时发"我们上 PH 了,来拍砖"。
- [ ] **心理预期**:你的硬依赖(必须有 cc)会筛掉大半 PH 访客。**别用绝对票数衡量成败**,看的是"装了的人里有没有人留言说真好用"。

---

## 9. 录屏脚本(你来录,15 分钟搞定)

> PH 第一张 GIF 用**真实浮窗录屏**,比任何宣传片都能打。总长 **15-20 秒**,两个镜头。
> 录之前确认看懂在跑(Hammerspoon 菜单栏锤子图标在;不确定就点 Reload Config)。

### 录之前的准备(5 分钟)
1. **关掉桌面上私密的东西**(录屏会拍到屏幕,别让聊天记录/邮件入镜)。
2. **字调大**:浏览器 ⌘ 加号放到 150%;终端字号也调大。读者在手机上看 GIF,字小=白录。
3. **桌面干净**:关掉无关窗口,壁纸别花。
4. 录屏工具:按 **⌘⇧5** → 选「录制选定部分」,框住要演示的窗口(别录整屏,聚焦)。

### 镜头 1:任何窗口划选就懂(~8 秒)
1. 打开 Chrome,随便一个有英文术语的技术页面(或维基百科搜 `idempotence`)。
2. 鼠标**慢慢划选**一个术语(如 `idempotent`)。
3. 按 **⌥?**。
4. 浮窗弹出大白话解释 → **停 2-3 秒让人读完**。
5. 按 **Esc** 关掉。

### 镜头 2:AI 动手前帮你拦(~8 秒)—— 这是爆点
1. 切到终端。屏幕上要有一条像样的危险命令(最真实:让 cc 干点会删东西的活,等它弹出
   `rm -rf …` + `Do you want to proceed?`;懒一点:终端里**敲出**(别回车)一条
   `rm -rf ~/test-data/*`)。
2. **划选**那条 `rm -rf …`。
3. 按 **⌥?**。
4. 浮窗弹出 **"⚠ 不可恢复 · 建议先看一眼 / 该不该放行"** → **停 2-3 秒**。
5. Esc。

### 录完
- 导出 mp4。**PH 主视频位直接传 mp4 就行**(会自动播)。
- 想要 gallery 里自动循环的 GIF,把 mp4 转一下(装了 ffmpeg 的话):
  ```
  ffmpeg -i demo.mp4 -vf "fps=12,scale=900:-1:flags=lanczos" -loop 0 demo.gif
  ```
- 第一张就放这个。第 2 张单独截"rm -rf 风险警告"那一帧当静图,配文
  `It warns you before you approve a risky command.`

### 录得好的几个点
- 鼠标移动**稳、慢、有目的**,别乱晃。
- 每个浮窗**停够 2-3 秒**(读者要读字)。
- 一镜到底最好;不行就两段分别录,后期拼。
- 别加花哨转场,真实感本身就是卖点。

---

## 10. 还没做的 / 可选

- pitchkit 风格化宣传片:`pitchkit` 已装,要的话跑 make-pitchkit 出一段,当落地页头图/次要素材(非 PH 第一张)。
- 文案二改:首评 / Description 你录完 demo 后想调再说。
