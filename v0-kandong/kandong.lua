-- 看懂 (kàndǒng) · v0
-- 鼠标 Agent 的最小切口:在终端里划选任何看不懂的东西,按快捷键,当场用大白话解释。
--   ⌥?    = 解释/看屏(quick / 没选中则读屏)
--   ⌘⌥?   = 详细解释(deep / 没选中则详细解释整屏)
--   ⌘?    = 本周卡点小结(summary;用 eventtap 拦截以绕过 macOS 帮助;⌘/ 兜底)
-- 复用本机已装好的 Claude Code(claude -p),不需要 API key。

local home       = os.getenv("HOME")
-- 找 claude 可执行文件:先问 PATH(覆盖 npm / homebrew / 原生安装等各种位置),
-- 再退回常见安装路径,最后退回 "claude"(靠下面 pathFix 兜底)。装到哪台机器都能找到——
-- 不再写死 ~/.local/bin/claude(否则 npm 装的人路径不对,所有解释会静默失败)。
local function detectClaude()
  local pathPre = "export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH:" .. home .. "/.local/bin; "
  local f = io.popen(pathPre .. "command -v claude 2>/dev/null")
  if f then
    local p = (f:read("*l") or ""):gsub("%s+$", ""); f:close()
    if p ~= "" then return p end
  end
  for _, p in ipairs({ home .. "/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude" }) do
    local t = io.open(p, "r"); if t then t:close(); return p end
  end
  return "claude"
end
local claudePath = detectClaude()
local selFile    = "/tmp/kandong_sel.txt"
-- 卡点日志放通用位置(跟 key 同目录),不依赖项目路径——装到哪台机器都能记。
local logDir     = home .. "/.config/kandong/logs"
local logFile    = logDir .. "/confusions.jsonl"
os.execute('mkdir -p "' .. logDir .. '"')
local MAX_CHARS  = 6000

-- ===== 匿名使用心跳 + 效果信号(算"留存"和"解释好不好用")=====
-- 发出去的只有:随机匿名码 + 事件名 + 日期/版本/系统,外加几个结果信号和粗粒度元数据:
--   installed/used  —— 留存。
--   explained       —— 每次解释:mode、source(本地词典/个人词典/中转/claude)、ok、sel_len/ans_len(分桶长度,不是原文)。
--   feedback        —— 用户点右下角"没懂?"时:helpful(恒为 false)、mode。(懂了=直接关掉,不发)
-- 绝不发任何选中内容、屏幕文字、答案正文、文件名、路径。长度只发分桶(如 "21-80"),不发原文。
-- 默认开;想关 = 建个空文件即可,即时生效、不用重载(一关全关):
--     touch ~/.config/kandong/telemetry.off
-- 安全兜底:POSTHOG_KEY 为空时整段是 no-op(什么都不发),所以提交进仓库也安全。
local POSTHOG_KEY  = "phc_BSyxvEdp6arPfeKC73gKzqajb7D79LqUmSWVJVPoQZ5F"  -- 公开写入 key,可提交
local POSTHOG_HOST = "https://us.i.posthog.com"  -- 项目在 EU 区就改 https://eu.i.posthog.com
local cfgDir       = home .. "/.config/kandong"
local anonIdFile   = cfgDir .. "/anon_id"
local teleStateF   = cfgDir .. "/telemetry_state"   -- 记最近一次发 used 的日期(每天最多发一次)
local teleOffFile  = cfgDir .. "/telemetry.off"

local function teleEnabled()
  if POSTHOG_KEY == "" then return false end
  local f = io.open(teleOffFile, "r"); if f then f:close(); return false end
  return true
end

-- 取/生成匿名码。返回 (id, 是不是刚新建)。刚新建 = 这台机器第一次跑(用来发 installed)。
local function anonId()
  local f = io.open(anonIdFile, "r")
  if f then local id = (f:read("*a") or ""):gsub("%s", ""); f:close(); if #id > 0 then return id, false end end
  local id = (hs.host and hs.host.uuid and hs.host.uuid()) or nil
  if not id then
    local t = {}; for i = 1, 32 do t[i] = string.format("%x", math.random(0, 15)) end; id = table.concat(t)
  end
  local w = io.open(anonIdFile, "w"); if w then w:write(id); w:close() end
  return id, true
end

-- 长度分桶:埋点里只发"大概多长"这种粗粒度,绝不发原文。长度是元数据、不是内容。
local function lenBucket(n)
  n = n or 0
  if n <= 20 then return "0-20"
  elseif n <= 80 then return "21-80"
  elseif n <= 400 then return "81-400"
  else return "400+" end
end

-- extraProps:可带不含内容的结构化属性(mode/source/ok/分桶长度/👍👎),绝不放选中内容/屏幕文字/路径。
-- 开关守卫集中在这里:telemetry 关了 / 没填 key,任何事件都不发(installed/used/explained/feedback 一视同仁)。
local function teleSend(event, extraProps)
  if not teleEnabled() then return end
  local id = anonId()
  local props = { ["$lib"] = "kandong", version = "v0", os = "macos" }
  if type(extraProps) == "table" then
    for k, v in pairs(extraProps) do props[k] = v end
  end
  local body = hs.json.encode({
    api_key = POSTHOG_KEY, event = event, distinct_id = id,
    properties = props,
    timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
  })
  hs.http.asyncPost(POSTHOG_HOST .. "/capture/", body,
    { ["Content-Type"] = "application/json" }, function() end)  -- 成败都不管,绝不卡界面
end

-- 每次按快捷键调一下:首次安装发 installed;之后每天首次使用发一次 used(够算留存)。
local function heartbeat()
  pcall(function()
    if not teleEnabled() then return end
    local _, isNew = anonId()
    if isNew then teleSend("installed") end
    local today = os.date("!%Y-%m-%d")
    local last = ""
    local f = io.open(teleStateF, "r"); if f then last = (f:read("*a") or ""):gsub("%s", ""); f:close() end
    if last ~= today then
      local w = io.open(teleStateF, "w"); if w then w:write(today); w:close() end
      teleSend("used")
    end
  end)
end

-- ===== 自动更新(下载+提醒,手动 Reload)=====
-- 每天首次启动后台拉一下 GitHub 最新版;有新版→校验→备份旧版→替换→弹提示让用户 Reload。
-- 两个安全点:
--   1) 只更新"标准安装路径"的副本(~/.hammerspoon/mouse-ai/kandong.lua)。从别处加载(如开发机
--      直接 dofile 仓库文件)时整段 no-op,绝不覆盖开发副本。
--   2) 替换前校验(非空、够长、含已知标志),坏下载绝不顶上去;旧版先备份成 .bak。
local KANDONG_BUILD  = 4   -- 每次发版 +1;远端 build 比这个大才更新
local UPDATE_RAW_URL = "https://raw.githubusercontent.com/luanrj-ai/mouse-ai/main/v0-kandong/kandong.lua"
local installPath    = home .. "/.hammerspoon/mouse-ai/kandong.lua"
local updateStateF   = cfgDir .. "/update_check"   -- 记最近一次检查日期(每天最多查一次)

local function loadedFromInstallPath()
  -- 当前文件实际路径(@/path/...);只有 == 标准安装路径才允许自更新
  local src = (debug.getinfo(1, "S").source or ""):gsub("^@", "")
  return src == installPath
end

local function autoUpdate()
  pcall(function()
    if not loadedFromInstallPath() then return end   -- 开发副本/非标准路径:整段 no-op
    -- 每天最多查一次
    local today = os.date("!%Y-%m-%d")
    local last = ""
    local f = io.open(updateStateF, "r"); if f then last = (f:read("*a") or ""):gsub("%s", ""); f:close() end
    if last == today then return end
    local w = io.open(updateStateF, "w"); if w then w:write(today); w:close() end

    hs.http.asyncGet(UPDATE_RAW_URL, nil, function(status, body)
      if status ~= 200 or type(body) ~= "string" then return end
      -- 校验:够长 + 含已知标志(防半截下载/错误页/被劫持的内容顶上去)
      if #body < 5000 then return end
      if not (body:find("看懂已就绪", 1, true) and body:find("hs.hotkey.bind", 1, true)
              and body:find("KANDONG_BUILD", 1, true)) then return end
      -- 远端 build 比本地大才更新
      local rb = tonumber(body:match("KANDONG_BUILD%s*=%s*(%d+)") or "")
      if not rb or rb <= KANDONG_BUILD then return end
      -- 先备份旧版,再写新版
      pcall(function()
        local cur = io.open(installPath, "r")
        if cur then
          local data = cur:read("*a"); cur:close()
          local bk = io.open(installPath .. ".bak", "w"); if bk then bk:write(data or ""); bk:close() end
        end
      end)
      local nf = io.open(installPath, "w"); if not nf then return end
      nf:write(body); nf:close()
      pcall(function()
        hs.notify.new({ title = "看懂已更新到 build " .. rb,
          informativeText = "点菜单栏锤子图标 → Reload Config 生效" }):send()
      end)
      hs.alert.show("看懂有新版(build " .. rb .. "),点锤子图标 → Reload Config 生效")
    end)
  end)
end

-- 云端中转(OpenAI 兼容)配置:key/base 放仓库外、仅本人可读(chmod 600),代码不硬编码。
-- 词典未命中的 quick 走中转 gpt-5-low(实测 ~2-3s,远快于 claude -p 的 9-25s);
-- 中转失败自动兜底回本机 claude -p(免费登录),保证总有答案。有 key 才启用。
local relayBase, relayConf, relayKeyOk
local relayModelQuick = "gpt-5-low"
do
  relayConf = home .. "/.config/kandong/curl.conf"
  local kf = io.open(home .. "/.config/kandong/llm.key", "r")
  if kf then local k = (kf:read("*a") or ""):gsub("%s", ""); kf:close(); relayKeyOk = (#k > 0) end
  local bf = io.open(home .. "/.config/kandong/llm.base", "r")
  if bf then relayBase = ((bf:read("*a") or ""):gsub("%s", "")); bf:close() end
end
local function relayModelFor(mode)
  if not (relayKeyOk and relayBase and #relayBase > 0) then return nil end
  -- 全切中转:quick/watch/recent(短)+ deep/screen(已改强约束短 prompt,~4-7s)。
  -- 关键前提:deep/screen 的 prompt 必须限定字数/要点,否则模型写长文会慢到 25s+。
  if mode == "quick" or mode == "watch" or mode == "recent"
    or mode == "deep" or mode == "screen" then return relayModelQuick end
  return nil
end

-- 解释指令(我能控制、不含单引号,拼进 shell 命令时可安全单引号包裹)
-- 通用指令:不靠猜格式,让 AI 自己分辨选中的是术语/代码/报错,还是 cc 要执行的操作。
local QUICK_INSTR = "下面是用户在终端(Claude Code)里选中的看不懂的内容(术语/命令/代码/报错/操作)。用中文一行说清意思,越短越好,尽量 20 字以内,只给核心、别加括号注释、别完整句子。若是要执行的操作,另起一行只写『安全』或『⚠️+三五字风险』。禁止任何寒暄铺垫和英文复述。"
local DEEP_INSTR  = "下面是用户在终端(Claude Code)里选中、看不懂的内容(术语/命令/代码/报错/操作)。用中文大白话讲清,最多 4 个要点,每点一句话、单独一行,全部加起来不超过 120 字。讲:是什么、对用户什么影响、要不要紧;若是要执行的操作,补一句会做什么、有没有风险、该不该放行。禁止长段、禁止多级标题、禁止寒暄、禁止复述英文。"
local SUMMARY_INSTR = "下面是用户最近用 Claude Code 时,一条条'看不懂、需要解释'的东西。请用中文大白话帮他归纳:他最近主要卡在哪几类(比如某类术语、某类命令、报错、配置等),每类一句话点出来,最后给一句鼓励或学习小建议。要归类总结,不要逐条复述。用 markdown 分点:"
-- 没选中文字时:读最近屏幕内容用的两条指令
local WATCH_INSTR  = "下面是终端画面,末尾有一个 Claude Code 待批准的操作。用户不懂技术。聚焦末尾那个操作,用中文极简三行,每行一个短语别写整句:『做什么:…』『风险:…(无则写「无」)』『建议:可放行/先别』。禁止寒暄、铺垫、复述英文。"
local RECENT_INSTR = "下面是终端最近画面(Claude Code 与用户的对话)。用户不懂技术。用中文极简总结,2-4 个短句要点,每点一行短语别写长句:cc 在做什么、到哪步、有没有要你决定的。禁止寒暄、复述英文。markdown 分点。"
-- ⌘⌥? 没选中时:对整屏做"稍详细"解释(比 RECENT 多一点)
local SCREEN_INSTR = "下面是终端最近画面(Claude Code 与用户的对话/输出)。用户不懂技术、想看懂这一屏。分 3 小块、每块 1-2 句短话,全部不超过 130 字:1)cc 最近在干嘛、到哪步;2)屏幕上关键词/命令/报错啥意思;3)有没有要你做的决定或风险。禁止逐行复述、禁止复述英文、禁止寒暄、禁止长篇。"

-- ===== 状态 =====
local popup, escKey, hideTimer

-- ===== 反馈桥:浮窗右下角"没懂?"通过它回传给 Lua =====
-- 设计:只有"没懂"才需要按钮。看懂了直接 Esc 关掉=默认的"懂了",不必点、也不发信号。
-- 对外:只发一个"没懂"结果信号 + 模式给作者(匿名,绝不含选中内容/答案)。
-- 对内(本地闭环,越用越懂你):删掉烂答案 + 记住"这类要讲细" + 立刻换聪明模型重讲。
-- fbSel 是当前卡片对应的选中内容,只在本机内存里用,绝不外发。
local fbMode, fbSel = nil, nil
local handleFeedback   -- 前向声明:真正实现放在 runClaude / 个人词典函数之后(见下方),这样能调用它们
local fbController = hs.webview.usercontent.new("kandong")
fbController:setCallback(function(msg)
  if (msg and msg.body == "down") and handleFeedback then handleFeedback() end
end)

-- ===== 工具 =====
local function jsonStr(s)
  s = tostring(s or "")
  s = s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", " "):gsub("\r", " "):gsub("\t", " ")
  return '"' .. s .. '"'
end

local function htmlEsc(s)
  s = tostring(s or "")
  return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

-- 清洗中转返回:有的模型(gpt-5.x)会把推理过程当成 <think>…</think> 塞进正文。
-- 去掉完整推理块、未闭合(被截断)的推理、残留标签,再去首尾空白。
-- 若清完为空(整段都是推理),上层会当作"没正文"自动兜底回 claude。
local function cleanRelay(s)
  s = tostring(s or "")
  s = s:gsub("<think>.-</think>", ""):gsub("<thinking>.-</thinking>", "")
  s = s:gsub("<think>.*$", ""):gsub("<thinking>.*$", "")
  s = s:gsub("</?think>", ""):gsub("</?thinking>", "")
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  return s
end

-- 轻量 markdown → HTML:处理 **加粗**、`代码`、# 标题、- 分点、空行。
-- 先转义 &<>(防 HTML 注入),再套标记(* ` # - 本身不是 HTML 特殊字符)。
local function mdToHtml(s)
  s = htmlEsc(s)
  s = s:gsub("`([^`]+)`", "<code>%1</code>")
  s = s:gsub("%*%*([^*]+)%*%*", "<b>%1</b>")
  local out = {}
  for line in (s .. "\n"):gmatch("(.-)\n") do
    local h = line:match("^%s*#+%s+(.*)")
    local b = line:match("^%s*[%-%*•]%s+(.*)")
    local n = line:match("^%s*%d+%.%s+.*")
    if h then
      out[#out + 1] = '<div class="h">' .. h .. '</div>'
    elseif b then
      out[#out + 1] = '<div class="li">• ' .. b .. '</div>'
    elseif n then
      out[#out + 1] = '<div class="li">' .. line:gsub("^%s+", "") .. '</div>'
    elseif #line:gsub("%s", "") == 0 then
      out[#out + 1] = '<div class="sp"></div>'
    else
      out[#out + 1] = '<div>' .. line .. '</div>'
    end
  end
  return table.concat(out, "")
end

local function cardHTML(title, body, footer, loading, feedback)
  local inner
  if loading then
    inner = '<div class="loading"><span class="dot"></span>' .. htmlEsc(body) .. '</div>'
  else
    inner = mdToHtml(body)
  end
  -- body 容器固定 id="out",标题/脚注也带 id,方便流式时用 JS 原地更新(不重建浮窗)
  local bodyHtml = '<div class="body" id="out">' .. inner .. '</div>'
  -- 反馈:只放一个右下角的"没懂?"。看懂了直接 Esc 关掉就是默认的"懂了",不必点。
  -- 点"没懂?"→ 删烂答案 + 记这类要讲细 + 立刻换聪明模型重讲(并匿名告诉作者,不含内容)。
  local footerInner = htmlEsc(footer)
  if feedback then
    footerInner = '<span>' .. footerInner .. '</span>'
      .. '<a class="fblink" id="fbwrap" onclick="fb()">没懂?</a>'
  end
  return [[<!doctype html><html><head><meta charset="utf-8"><style>
    * { margin:0; padding:0; box-sizing:border-box; }
    html,body { background:transparent; }
    .card {
      font-family:-apple-system,"PingFang SC","Helvetica Neue",sans-serif;
      background:#1c1c1eF2; color:#f2f2f7; border-radius:16px;
      padding:18px 20px; height:100vh; display:flex; flex-direction:column;
      border:0.5px solid #ffffff22; -webkit-backdrop-filter:blur(20px);
    }
    .title { font-size:11px; letter-spacing:2px; text-transform:uppercase;
      color:#0a84ff; font-weight:700; margin-bottom:10px; }
    .body { font-size:15px; line-height:1.6; color:#f2f2f7; overflow-y:auto;
      flex:1; word-break:break-word; }
    .body .h { font-weight:700; margin:6px 0 2px; color:#fff; }
    .body .li { padding-left:4px; margin:2px 0; }
    .body .sp { height:8px; }
    .body code { background:#ffffff1a; padding:1px 5px; border-radius:4px;
      font-family:"SF Mono",Menlo,monospace; font-size:13px; }
    .body b { color:#fff; }
    .loading { font-size:14px; color:#aeaeb2; display:flex; align-items:center; flex:1; }
    .dot { width:8px; height:8px; border-radius:50%; background:#0a84ff;
      margin-right:10px; animation:pulse 1s infinite; }
    @keyframes pulse { 0%,100%{opacity:.3} 50%{opacity:1} }
    .footer { font-size:11px; color:#8e8e93; margin-top:12px;
      padding-top:10px; border-top:0.5px solid #ffffff1a;
      display:flex; justify-content:space-between; align-items:center; gap:10px; }
    .fblink { color:#8e8e93; cursor:pointer; text-decoration:none; white-space:nowrap; }
    .fblink:hover { color:#0a84ff; }
    .fbdone { color:#8e8e93; white-space:nowrap; }
  </style></head><body><div class="card">
    <div class="title" id="ttl">]] .. htmlEsc(title) .. [[</div>
    ]] .. bodyHtml .. [[
    <div class="footer" id="ftr">]] .. footerInner .. [[</div>
  </div>
  <script>
    function fb(){
      try{ window.webkit.messageHandlers.kandong.postMessage('down'); }catch(e){}
      var w=document.getElementById('fbwrap');
      if(w){ w.outerHTML='<span class="fbdone">重讲中…</span>'; }
    }
  </script>
  </body></html>]]
end

local function closePopup()
  if popup then popup:delete(); popup = nil end
  if escKey then escKey:delete(); escKey = nil end
  if hideTimer then hideTimer:stop(); hideTimer = nil end
end

local function showCard(title, body, footer, loading, feedback)
  local pos = hs.mouse.absolutePosition()
  local scr = hs.mouse.getCurrentScreen():fullFrame()
  local w, h = 480, 280
  local x = pos.x + 14
  local y = pos.y + 14
  if x + w > scr.x + scr.w then x = scr.x + scr.w - w - 14 end
  if y + h > scr.y + scr.h then y = scr.y + scr.h - h - 14 end
  if x < scr.x then x = scr.x + 14 end
  if y < scr.y then y = scr.y + 14 end

  if popup then popup:delete() end
  -- 带上 fbController:浮窗里的 👍/👎 才能 postMessage 回 Lua
  popup = hs.webview.new({ x = x, y = y, w = w, h = h }, {}, fbController)
  popup:windowStyle({ "borderless", "nonactivating" })  -- 不抢焦点,终端仍能按 1/2/3
  popup:level(hs.drawing.windowLevels.floating)
  popup:shadow(true)
  popup:transparent(true)
  popup:html(cardHTML(title, body, footer, loading, feedback))
  popup:bringToFront(true)
  popup:show()

  if escKey then escKey:delete() end
  escKey = hs.hotkey.bind({}, "escape", closePopup)
  -- 不再自动消失:留到你按 Esc(或发起下一次解释时自动替换),你可以慢慢读
  if hideTimer then hideTimer:stop(); hideTimer = nil end
end

local function logQuery(mode, sel, ok)
  -- 只记录选中解释(quick/deep)这种干净的"卡点"信号;读屏类不污染飞轮数据
  if mode == "summary" or mode == "watch" or mode == "recent" or mode == "screen" then return end
  -- UTF-8 安全截断:截到约 100 个字符,绝不切在多字节(中文)字中间——
  -- 否则写出的 JSON 会含半个字的乱码,小结解析时这条还会被跳过(丢卡点)。
  local preview = sel:gsub("[\r\n]", " ")
  local oku, cut = pcall(utf8.offset, preview, 101)
  if oku then
    if cut then preview = preview:sub(1, cut - 1) end
  else
    preview = preview:sub(1, 100):gsub("[\194-\244][\128-\191]*$", "")
  end
  local line = "{" ..
    '"ts":' .. jsonStr(os.date("!%Y-%m-%dT%H:%M:%SZ")) .. "," ..
    '"mode":' .. jsonStr(mode) .. "," ..
    '"ok":' .. (ok and "true" or "false") .. "," ..
    '"chars":' .. tostring(#sel) .. "," ..
    '"preview":' .. jsonStr(preview) ..
    "}\n"
  local f = io.open(logFile, "a")
  if f then f:write(line); f:close() end
end

-- ===== 本地秒答词典 =====
-- 联网那段(每次 5~25s)砍不掉,但高频、可预测的危险操作/报错/术语可以离线 0ms 答。
-- 命中即返回、不打网络、答案每次一致。只用于 quick(⌥? 选中那段);deep/读屏仍走 AI。
-- confusions.jsonl 飞轮记录的高频卡点 → 往这里补,这是"数据飞轮"真正落地的地方。
-- 顺序=优先级:更具体的放前面(force push 在 push 前、rm -rf 在前)。
local function norm(s)
  return " " .. (s:lower():gsub("%s+", " ")) .. " "
end
local function has(s, sub) return s:find(sub, 1, true) ~= nil end

local LOCAL_ANSWERS = {
  -- ---- 危险操作 ----
  { m = function(s) return has(s, "push") and (has(s, "force") or has(s, " -f")) end,
    a = "强制推送,用本地覆盖远程历史\n⚠️ 会抹掉别人的提交,共享分支别用" },
  { m = function(s) return has(s, "rm ") and (has(s, "-rf") or has(s, "-fr") or (has(s, "-r") and has(s, "-f"))) end,
    a = "强制删掉文件夹和里面所有东西\n⚠️ 不进废纸篓,删了找不回,先看清路径" },
  { m = function(s) return has(s, " sudo ") end,
    a = "用管理员权限执行,能改动系统\n⚠️ 权力很大,看清后面那条命令再放行" },
  { m = function(s) return has(s, "reset") and (has(s, "--hard") or has(s, " -hard")) end,
    a = "把代码强行退回某个版本,丢弃改动\n⚠️ 没提交的改动会全部消失" },
  { m = function(s) return has(s, "git clean") and has(s, "-f") end,
    a = "删掉所有还没跟踪的新文件\n⚠️ 新建、没提交的文件会被清掉" },
  { m = function(s) return has(s, "checkout -- ") or has(s, "git restore") end,
    a = "丢弃文件的本地改动,回到上次提交\n⚠️ 没保存的改动会丢" },
  { m = function(s) return has(s, "chmod") and has(s, "777") end,
    a = "把权限开到所有人可读、可写、可执行\n⚠️ 太宽,任何人都能改这个文件" },
  { m = function(s) return has(s, "drop table") or has(s, "drop database") or has(s, "truncate table") end,
    a = "删除整张数据表 / 整个数据库\n⚠️ 数据全没,不可逆" },
  { m = function(s) return (has(s, "curl") or has(s, "wget")) and (has(s, "| sh") or has(s, "|sh") or has(s, "| bash") or has(s, "|bash")) end,
    a = "下载网上的脚本,直接在你电脑运行\n⚠️ 等于让陌生代码随便跑,先看清来源" },
  { m = function(s) return has(s, "mkfs") or has(s, "dd if=") end,
    a = "直接读写 / 格式化磁盘\n⚠️ 极危险,可能清空整块磁盘" },
  { m = function(s) return has(s, "kill -9") or has(s, "killall") end,
    a = "强制结束进程\n安全,但程序没存的数据会丢" },
  -- ---- 常见、且安全的 git/包操作(给"放行"信心)----
  { m = function(s) return has(s, "git push") end,
    a = "把本地提交上传到远程\n安全" },
  { m = function(s) return has(s, "git pull") end,
    a = "拉远程最新代码合并到本地\n安全(偶尔有冲突要解决)" },
  { m = function(s) return has(s, "git commit") end,
    a = "把改动存成一条提交记录\n安全" },
  { m = function(s) return has(s, "npm i") or has(s, "pnpm i") or has(s, "yarn add") or has(s, "yarn install") end,
    a = "下载安装项目依赖包\n安全,只是联网下载" },
  -- ---- 常见报错 ----
  { m = function(s) return has(s, "module_not_found") or has(s, "cannot find module") or has(s, "module not found") or has(s, "modulenotfound") end,
    a = "找不到要用的模块\n多半没装依赖,或导入路径写错了" },
  { m = function(s) return has(s, "eresolve") end,
    a = "依赖之间版本打架,装不上\n常用 --legacy-peer-deps 绕过" },
  { m = function(s) return has(s, "enoent") end,
    a = "找不到这个文件或目录\n多半路径写错,或文件不存在" },
  { m = function(s) return has(s, "eaddrinuse") or has(s, "address already in use") end,
    a = "端口被占用,已经有程序在用\n换个端口,或关掉占用它的程序" },
  { m = function(s) return has(s, "permission denied") or has(s, "eacces") end,
    a = "没权限读 / 写 / 执行\n多半要改权限,或命令前加 sudo" },
  { m = function(s) return has(s, "command not found") end,
    a = "系统找不到这个命令\n多半没装,或不在 PATH 里" },
  { m = function(s) return has(s, "not a git repository") end,
    a = "当前文件夹不是 git 仓库\n先进到项目目录,或先 git init" },
  { m = function(s) return has(s, "detached head") end,
    a = "你没在任何分支上,改动容易丢\n先切回分支,或新建一个分支" },
  { m = function(s) return has(s, "segmentation fault") or has(s, "segfault") end,
    a = "程序乱访问内存崩溃了\n通常是程序本身的 bug" },
  -- ---- 高频术语 ----
  { m = function(s) return has(s, "node_modules") end,
    a = "放项目所有依赖包的文件夹\n安全,删了重装就能恢复" },
  { m = function(s) return has(s, "localhost") or has(s, "127.0.0.1") end,
    a = "指你自己这台电脑(本地)\n安全" },
  { m = function(s) return has(s, ".env") end,
    a = ".env:存密钥和配置的文件\n⚠️ 含敏感信息,别提交到 git" },
  { m = function(s) return has(s, "package.json") end,
    a = "项目说明书:依赖和脚本都记在这里\n安全" },
}

-- 选中内容查本地词典;命中返回答案字符串,否则 nil。太长(多半不是单个词/命令)直接跳过。
local function lookupLocal(sel)
  if not sel or #sel == 0 or #sel > 400 then return nil end
  local s = norm(sel)
  for _, e in ipairs(LOCAL_ANSWERS) do
    local ok, hit = pcall(e.m, s)
    if ok and hit then return e.a end
  end
  return nil
end

-- ===== 越用越懂你:个人画像 + 个人词典(全本地、不上传)=====
-- 思路:看懂记住"你这个人"反复卡在哪、什么程度,讲解越来越贴你。云厂商做不到(要上传、千人一面),
-- 这正是看懂的护城河。两块都纯本地、几乎零延迟,不破坏"内容不出本机"的承诺。
local personalDictFile = cfgDir .. "/personal_dict.json"

-- 个人词典:你卡过的"词/命令" → 你上次听懂的那条解释。下次同一个 0ms 秒出、还用你听懂的说法。
local function loadPersonalDict()
  local f = io.open(personalDictFile, "r"); if not f then return {} end
  local raw = f:read("*a") or ""; f:close()
  local ok, t = pcall(hs.json.decode, raw)
  if ok and type(t) == "table" then return t end
  return {}
end
local function dictKey(sel) return (sel:lower():gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")) end
local function lookupPersonal(sel)
  if not sel or #sel == 0 or #sel > 80 then return nil end       -- 只认"词/命令"这种短的
  local e = loadPersonalDict()[dictKey(sel)]
  if type(e) == "table" and type(e.a) == "string" and #e.a > 0 then return e.a end
  return nil
end
local function savePersonal(sel, answer)
  if not sel or #sel == 0 or #sel > 80 then return end
  if not answer or #answer == 0 or #answer > 400 then return end
  if answer:find("出错") or answer:find("没拿到") or answer:find("没找到 Claude") then return end
  pcall(function()
    local d = loadPersonalDict()
    d[dictKey(sel)] = { a = answer, ts = os.date("!%Y-%m-%dT%H:%M:%SZ") }
    local f = io.open(personalDictFile, "w"); if f then f:write(hs.json.encode(d)); f:close() end
  end)
end
-- "没懂":把这条听不懂的解释从个人词典删掉,下次别再把烂答案 0ms 秒出
local function removePersonal(sel)
  if not sel or #sel == 0 or #sel > 80 then return end
  pcall(function()
    local d = loadPersonalDict()
    if d[dictKey(sel)] == nil then return end
    d[dictKey(sel)] = nil
    local f = io.open(personalDictFile, "w"); if f then f:write(hs.json.encode(d)); f:close() end
  end)
end

-- 个人画像:纯本地、纯计算(不调 AI、不加延迟)。数最近卡点的「类别」+「技术栈」,
-- 拼一句塞进解释指令,让 cc 按你的程度讲、用你熟的栈打比方。数据越多越准;<5 条返回空。
local PROFILE_CATS = {
  { name = "依赖安装",   kw = { "npm", "pnpm", "yarn", "pip", "install", "module", "node_modules", "依赖", "eresolve" } },
  { name = "报错",       kw = { "error", "exception", "traceback", "failed", "fault", "报错", "enoent", "denied" } },
  { name = "git",        kw = { "git", "commit", "push", "pull", "branch", "merge", "rebase", "分支", "仓库" } },
  { name = "命令与权限", kw = { "sudo", "chmod", "rm ", "permission", "kill", "bash", "shell", "权限" } },
  { name = "配置",       kw = { ".env", "config", "json", "yaml", "port", "端口", "环境变量", "配置" } },
}
-- 技术栈:认出你平时写什么,解释时用你熟的语言/框架打比方。
local STACK_CATS = {
  { name = "React",            kw = { "react", "usestate", "useeffect", ".jsx", ".tsx", "next.js", "nextjs", "vite" } },
  { name = "TypeScript",       kw = { "typescript", "tsc", ".ts", "tsconfig", "interface " } },
  { name = "JavaScript/Node",  kw = { "npm", "node", "package.json", "npx", "yarn", "pnpm", ".js", "express" } },
  { name = "Python",           kw = { "python", "pip", ".py", "traceback", "pytest", "venv", "conda", "django", "flask", "numpy", "pandas" } },
  { name = "Rust",             kw = { "cargo", "rustc", ".rs", "rustup" } },
  { name = "Go",               kw = { "go test", "go build", "go.mod", "golang", "go run" } },
  { name = "Java/Kotlin",      kw = { "gradle", "maven", ".java", ".kt", "spring" } },
  { name = "Ruby/Rails",       kw = { "gem ", "bundle", "rails", ".rb" } },
  { name = "容器/运维",        kw = { "docker", "kubectl", "kubernetes", "terraform", "helm", "nginx" } },
}
-- 取出现次数最多的前 n 类(需 >= minN 次才算数,避免一两次的噪声)
local function topNames(counts, n, minN)
  local arr = {}
  for name, c in pairs(counts) do if c >= (minN or 1) then arr[#arr + 1] = { name = name, n = c } end end
  table.sort(arr, function(a, b) return a.n > b.n end)
  local out = {}
  for i = 1, math.min(n, #arr) do out[#out + 1] = arr[i].name end
  return out
end
local function countHits(p, cats, counts)
  for _, c in ipairs(cats) do
    for _, k in ipairs(c.kw) do
      if p:find(k, 1, true) then counts[c.name] = (counts[c.name] or 0) + 1; break end
    end
  end
end

-- 👎 反馈飞轮:记住"哪类解释你常说没懂",以后同类自动讲更细。纯本地、不上传。
local needsDeeperFile = cfgDir .. "/needs_deeper.json"
local function categoryOf(sel)
  local p = (sel or ""):lower()
  for _, c in ipairs(PROFILE_CATS) do
    for _, k in ipairs(c.kw) do
      if p:find(k, 1, true) then return c.name end
    end
  end
  return nil
end
local function loadNeedsDeeper()
  local f = io.open(needsDeeperFile, "r"); if not f then return {} end
  local raw = f:read("*a") or ""; f:close()
  local ok, t = pcall(hs.json.decode, raw)
  if ok and type(t) == "table" then return t end
  return {}
end
local function bumpNeedsDeeper(sel)
  local cat = categoryOf(sel); if not cat then return end
  pcall(function()
    local d = loadNeedsDeeper()
    d[cat] = (tonumber(d[cat]) or 0) + 1
    local f = io.open(needsDeeperFile, "w"); if f then f:write(hs.json.encode(d)); f:close() end
  end)
end
-- ===== 自进化:让"卡点主题"自己长 =====
-- 写死的 5 类(PROFILE_CATS)发现不了新主题。这里后台让 cc 把你真实的卡点日志聚类成你自己的
-- 具体主题(如"异步/Promise""TypeScript 类型"),存盘;personalProfile 优先用它。攒够新条目才重聚,
-- 纯后台不卡界面;没聚过/失败则回退写死分类。全本地、不上传。
local discoveredFile = cfgDir .. "/discovered_topics.json"
local DISCOVER_INSTR = "下面是用户用 Claude Code 时,一条条看不懂、需要解释的内容(每行一条)。提炼出他最近反复卡的 3-5 个【具体】主题——用具体的词(如「异步/Promise」「TypeScript 类型」「git rebase」「Docker 网络」),不要泛泛的大类(别用「报错」「命令」这种)。只输出一个 JSON 字符串数组,例如 [\"异步/Promise\",\"环境变量\"],别的什么都别输出。"

local function loadDiscovered()
  local f = io.open(discoveredFile, "r"); if not f then return nil end
  local raw = f:read("*a") or ""; f:close()
  local ok, t = pcall(hs.json.decode, raw)
  if ok and type(t) == "table" and type(t.topics) == "table" then return t end
  return nil
end

-- 读卡点日志的 preview(排除 summary 自己),返回 {previews, 总行数}
local function readConfusions(maxN)
  local f = io.open(logFile, "r"); if not f then return {}, 0 end
  local lines = {}
  for ln in f:lines() do lines[#lines + 1] = ln end
  f:close()
  local total, out = #lines, {}
  for i = math.max(1, total - (maxN or 100) + 1), total do
    local ok, o = pcall(hs.json.decode, lines[i])
    if ok and type(o) == "table" and o.preview and o.mode ~= "summary" then out[#out + 1] = o.preview end
  end
  return out, total
end

local discovering = false
local function discoverTopics()
  if discovering then return end
  local previews, total = readConfusions(100)
  if #previews < 8 then return end                       -- 信号太少不聚类
  discovering = true
  local tmp = selFile .. ".discover." .. tostring(hs.timer.absoluteTime())
  local wf = io.open(tmp, "w"); if not wf then discovering = false; return end
  wf:write(table.concat(previews, "\n")); wf:close()
  local pathFix = "export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH:" .. home .. "/.local/bin; "
  local cmd = pathFix .. "cat " .. tmp .. " | '" .. claudePath
    .. "' -p --model haiku --effort low --no-session-persistence --disable-slash-commands --tools '' --no-chrome '"
    .. DISCOVER_INSTR .. "'"
  hs.task.new("/bin/sh", function(code, out, err)
    discovering = false
    pcall(function() os.remove(tmp) end)
    pcall(function()
      local jsonPart = (out or ""):match("%[.-%]")       -- 抠出第一个 [...]
      if not jsonPart then return end
      local ok, arr = pcall(hs.json.decode, jsonPart)
      if not ok or type(arr) ~= "table" then return end
      local topics = {}
      for _, v in ipairs(arr) do
        if type(v) == "string" and #v > 0 and #v < 30 then topics[#topics + 1] = v end
      end
      if #topics == 0 then return end
      local rec = { topics = topics, n = total, ts = os.date("!%Y-%m-%dT%H:%M:%SZ") }
      local f = io.open(discoveredFile, "w"); if f then f:write(hs.json.encode(rec)); f:close() end
    end)
  end, { "-c", cmd }):start()
end

-- 攒够 15 条新卡点(或从没聚过且已有 >=8 条)就后台重聚一次
local function maybeDiscoverTopics()
  pcall(function()
    local _, total = readConfusions(1)
    local d = loadDiscovered()
    local last = d and tonumber(d.n) or 0
    if total >= 8 and (total - last) >= 15 then discoverTopics() end
  end)
end

local function personalProfile()
  local prof = ""
  pcall(function()
    local f = io.open(logFile, "r"); if not f then return end
    local lines = {}
    for ln in f:lines() do lines[#lines + 1] = ln end
    f:close()
    local cat, stack, total = {}, {}, 0
    for i = math.max(1, #lines - 119), #lines do
      local ok, o = pcall(hs.json.decode, lines[i])
      if ok and type(o) == "table" and o.preview then
        total = total + 1
        local p = o.preview:lower()
        countHits(p, PROFILE_CATS, cat)
        countHits(p, STACK_CATS, stack)
      end
    end
    if total < 5 then return end
    local topics = topNames(cat, 3, 1)
    -- 自进化:有 cc 聚类出的真实主题就优先用它(比写死的 5 类具体得多),否则回退写死分类
    local disc = loadDiscovered()
    if disc and disc.topics and #disc.topics > 0 then
      topics = {}
      for i = 1, math.min(4, #disc.topics) do topics[#topics + 1] = disc.topics[i] end
    end
    local stacks = topNames(stack, 2, 3)        -- 技术栈需 >=3 次才算,更稳
    if #topics == 0 and #stacks == 0 then return end
    prof = "(读者是非技术用户"
    if #topics > 0 then prof = prof .. ",最近常卡在:" .. table.concat(topics, "、") end
    if #stacks > 0 then prof = prof .. ";平时主要写:" .. table.concat(stacks, "、") end
    prof = prof .. "。请按这个熟悉度调整深浅、别重复他已熟的基础;打比方时尽量用他熟的语言/框架。)"
  end)
  -- 叠加 👎 飞轮:对常说"没懂"的类别要求讲更细(独立生效,即便上面画像为空)
  pcall(function()
    local nd, deep = loadNeedsDeeper(), {}
    for cat, c in pairs(nd) do if (tonumber(c) or 0) >= 2 then deep[#deep + 1] = cat end end
    if #deep > 0 then
      prof = prof .. "(他对【" .. table.concat(deep, "、") .. "】类常反馈没懂,这类请讲得更细、更基础、多打比方。)"
    end
  end)
  return prof
end

-- ===== 热进程:常驻一个 claude(stream-json 输入/输出),免每次 ~4.5s 冷启动 =====
-- 只服务 haiku 那几种快查;详细版/中转不走。任何异常/超时都回退一次性路径,保证不比现在差。
-- 只缓冲+解析、不做浮窗实时渲染(避开流式渲染卡死),收到 result 再一次性出卡。
local WARM_FLAGS = "-p --input-format stream-json --output-format stream-json --verbose "
  .. "--model haiku --effort low --no-session-persistence --tools '' --no-chrome --disable-slash-commands"
local warmTask, warmBuf, warmBusy, warmCb = nil, "", false, nil

local function warmAlive() return warmTask ~= nil and warmTask:isRunning() end

local function warmHandleLine(line)
  if #line == 0 then return end
  local ok, obj = pcall(hs.json.decode, line)
  if not ok or type(obj) ~= "table" then return end
  if obj.type == "result" then          -- 一个 turn 收尾
    local cb = warmCb
    warmCb = nil; warmBusy = false
    if cb then pcall(cb, obj.result, obj.subtype) end
  end
end

local function warmStart()
  if warmAlive() then return end
  warmTask, warmBuf, warmBusy, warmCb = nil, "", false, nil
  local launch = "export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH:" .. home
    .. "/.local/bin; exec '" .. claudePath .. "' " .. WARM_FLAGS
  warmTask = hs.task.new("/bin/sh", function(c, o, e)
    warmTask = nil
    local cb = warmCb; warmCb = nil; warmBusy = false
    if cb then pcall(cb, nil, "exited") end           -- 进程死了→在途请求失败→回退
  end, function(t, so, se)
    pcall(function()
      if so and #so > 0 then
        warmBuf = warmBuf .. so
        while true do
          local nl = warmBuf:find("\n", 1, true)
          if not nl then break end
          warmHandleLine(warmBuf:sub(1, nl - 1)); warmBuf = warmBuf:sub(nl + 1)
        end
      end
    end)
    return true
  end, { "-c", launch })
  pcall(function() warmTask:start() end)
end

-- 给热进程发一条请求。受理→true(稍后回调 onDone(result, subtype));忙/没活着→false(调用方回退)。
local function warmAsk(prompt, onDone)
  if not warmAlive() or warmBusy then return false end
  warmBusy = true; warmCb = onDone
  local msg = hs.json.encode({ type = "user", message = { role = "user", content = prompt } }) .. "\n"
  if not pcall(function() warmTask:setInput(msg) end) then
    warmBusy = false; warmCb = nil; return false
  end
  return true
end

local function runClaude(sel, mode)
  -- 本地秒答:quick 先查词典,命中就 0ms 显示、不打网络(仍记飞轮)
  if mode == "quick" then
    local hit = lookupLocal(sel)
    if hit then
      fbMode, fbSel = "quick", sel
      showCard("大白话", hit, "本地秒答 · ⌘⌥? 看详细 · Esc 关闭", false, true)
      logQuery("quick", sel, true)
      teleSend("explained", { mode = "quick", source = "local_dict", ok = true,
        sel_len = lenBucket(#sel), ans_len = lenBucket(#hit) })
      return
    end
    -- 个人词典:这个词你之前问过 → 用你上次听懂的说法,0ms 秒出
    local phit = lookupPersonal(sel)
    if phit then
      fbMode, fbSel = "quick", sel
      showCard("大白话", phit, "你之前问过 · ⌘⌥? 看详细 · Esc 关闭", false, true)
      logQuery("quick", sel, true)
      teleSend("explained", { mode = "quick", source = "personal_dict", ok = true,
        sel_len = lenBucket(#sel), ans_len = lenBucket(#phit) })
      return
    end
  end
  if #sel > MAX_CHARS then sel = sel:sub(1, MAX_CHARS) end
  -- 每次用独立临时文件,避免快速连按时两次输入互相覆盖
  local myFile = selFile .. "." .. tostring(hs.timer.absoluteTime())
  local f = io.open(myFile, "w")
  if not f then showCard("出错了", "写不了临时文件,检查权限。", "Esc 关闭", false); return end
  f:write(sel); f:close()

  local instr, loadTitle, doneTitle, doneFooter, modelFlag
  if mode == "deep" then
    instr, loadTitle, doneTitle, doneFooter = DEEP_INSTR, "详细解释中…", "详细解释", "Esc 关闭"
    modelFlag = "--no-session-persistence "          -- 详细版用默认聪明模型
  elseif mode == "summary" then
    instr, loadTitle, doneTitle, doneFooter = SUMMARY_INSTR, "汇总中…", "本周卡点小结", "Esc 关闭"
    modelFlag = "--model haiku --no-session-persistence "
  elseif mode == "watch" then
    instr, loadTitle, doneTitle, doneFooter = WATCH_INSTR, "看 cc 要做啥…", "cc 要做这个", "看懂了自己在终端按 1/2/3   ·   Esc 关"
    modelFlag = "--model haiku --no-session-persistence "
  elseif mode == "recent" then
    instr, loadTitle, doneTitle, doneFooter = RECENT_INSTR, "看最近发生了啥…", "最近发生了什么", "Esc 关闭"
    modelFlag = "--model haiku --no-session-persistence "
  elseif mode == "screen" then
    instr, loadTitle, doneTitle, doneFooter = SCREEN_INSTR, "看这一屏…", "这屏在干嘛", "Esc 关闭"
    modelFlag = "--model haiku --no-session-persistence "
  else
    instr, loadTitle, doneTitle, doneFooter = QUICK_INSTR, "解释中…", "大白话", "⌘⌥? 看详细   ·   Esc 关闭"
    modelFlag = "--model haiku --no-session-persistence "  -- 快查用 haiku,更快更省
  end
  -- 越用越懂你:给选中解释(quick/deep)拼一句"个人画像",让 cc 按你的程度讲。
  -- 纯本地计算、不加延迟;画像不含单引号,拼进单引号包裹的 shell 命令里安全。
  if mode == "quick" or mode == "deep" then
    local prof = personalProfile()
    if #prof > 0 then instr = instr .. prof end
  end
  -- 提速:纯解释不需要技能/工具/chrome,关掉它们能少 ~2 秒、且避免偶尔加载 70+ 技能卡顿到 20s+
  -- haiku 那几种再加 --effort low(一句话解释不需要高强度思考,省思考时间和 token)
  if mode ~= "deep" then modelFlag = modelFlag .. "--effort low " end
  modelFlag = modelFlag .. "--disable-slash-commands --tools '' --no-chrome "
  showCard(loadTitle, "正在问 cc,稍等…", "Esc 关闭", true)

  -- 关键:不要用 task:setEnvironment 替换环境,否则会丢掉 claude 读钥匙串凭证
  -- 所需的 USER / XPC_* 等变量,导致 "Not logged in"。改为继承 Hammerspoon
  -- 的完整环境,只在命令里临时补 PATH(让 claude 及其子进程能被找到)。
  local pathFix = "export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH:" .. home .. "/.local/bin; "
  -- 流式暂时关闭:Hammerspoon 的 hs.task 流式回调在 macOS 上会偶发
  -- "Resource temporarily unavailable" 异常,导致收尾回调抛错、浮窗卡死。
  -- 可靠优先,退回非流式(等完整结果再一次性显示)。prompt 已改短,等待本就少。
  local streaming = false

  local function errMark(s)
    return s:match("Not logged in") or s:match("Please run /login")
      or s:match("Invalid API key") or s:match("Credit balance")
  end

  local task, killer, done = nil, nil, false
  local usedSource = "claude"   -- 实际出答案的后端:claude / relay(中转);埋点用,不含内容

  -- 收尾:出错显示提示,成功则定稿(流式时同一浮窗 JS 更新,不重建)
  local function finish(text, errtext, streamedAlready)
    if done then return end
    done = true
    if killer then killer:stop(); killer = nil end
    os.remove(myFile)
    local trimmed = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local em = errMark(trimmed) or (errtext and errMark(errtext))
    if #trimmed == 0 or em then
      local hint
      local notFound = errtext and (errtext:match("command not found") or errtext:match("No such file")
        or errtext:match("not found"))
      if em then hint = "cc 说没登录。请在终端运行 claude /login 重新登录后再试。"
      elseif notFound then hint = "没找到 Claude Code。看懂要复用它才能解释。\n请先安装并登录:claude.com/claude-code\n(装好后重启终端,再点菜单栏锤子图标 Reload Config)"
      elseif errtext and #errtext > 0 then hint = "出错了:\n" .. errtext:sub(1, 300)
      else hint = "没拿到解释(可能超时)。再按一次试试。" end
      showCard("出错了", hint, "Esc 关闭", false)
      logQuery(mode, sel, false)
      teleSend("explained", { mode = mode, source = usedSource, ok = false,
        sel_len = lenBucket(#sel), ans_len = "0-20" })
      return
    end
    if streamedAlready and popup then
      -- 已在浮窗里逐段显示完,只更新标题/脚注/最终排版,不重建浮窗(不闪)
      local js = "var o=document.getElementById('out'); if(o){o.innerHTML=" .. jsonStr(mdToHtml(trimmed)) .. ";}"
        .. "var t=document.getElementById('ttl'); if(t)t.innerHTML=" .. jsonStr(htmlEsc(doneTitle)) .. ";"
        .. "var fr=document.getElementById('ftr'); if(fr)fr.innerHTML=" .. jsonStr(htmlEsc(doneFooter)) .. ";"
      pcall(function() popup:evaluateJavaScript(js) end)
    else
      fbMode, fbSel = mode, sel
      showCard(doneTitle, trimmed, doneFooter, false, true)
    end
    logQuery(mode, sel, true)
    teleSend("explained", { mode = mode, source = usedSource, ok = true,
      sel_len = lenBucket(#sel), ans_len = lenBucket(#trimmed) })
    if mode == "quick" then savePersonal(sel, trimmed) end   -- 存进个人词典,下次秒出
    pcall(maybeDiscoverTopics)   -- 自进化:攒够新卡点就后台重聚一次「你的卡点主题」
  end

  -- 热进程优先:haiku 那几种 + 没走中转 + 常驻进程活着时,复用它省冷启动;失败/超时自动回退一次性。
  if mode ~= "deep" and not relayModelFor(mode) and warmAlive() then
    local function warmFallback()
      if done then return end
      local cmd = pathFix .. "cat " .. myFile .. " | '" .. claudePath .. "' -p " .. modelFlag .. "'" .. instr .. "'"
      task = hs.task.new("/bin/sh", function(code, out, err) finish(out, err, false) end, { "-c", cmd })
      task:start()
    end
    killer = hs.timer.doAfter(12, warmFallback)        -- 12s 没回 → 回退
    local accepted = warmAsk(instr .. "\n\n" .. sel, function(result, subtype)
      if done then return end
      if killer then killer:stop(); killer = nil end
      local r = result and tostring(result) or ""
      if subtype == "success" and #(r:gsub("%s", "")) > 0 then
        usedSource = "claude_warm"; finish(r, nil, false)
      else
        warmFallback()
      end
    end)
    if accepted then return end
    if killer then killer:stop(); killer = nil end
  end

  if streaming then
    local cmd = pathFix .. "cat " .. myFile .. " | '" .. claudePath .. "' -p " .. modelFlag
      .. "--output-format stream-json --include-partial-messages --verbose '" .. instr .. "'"
    local acc, buf, errbuf = "", "", ""
    local function renderBody(h)
      if not popup then return end
      pcall(function()
        popup:evaluateJavaScript("var o=document.getElementById('out'); if(o){o.innerHTML="
          .. jsonStr(h) .. ";o.scrollTop=o.scrollHeight;}")
      end)
    end
    local function handleLine(line)
      if done or #line == 0 then return end
      local ok, obj = pcall(hs.json.decode, line)
      if not ok or type(obj) ~= "table" then return end
      local ev = obj.event
      if obj.type == "stream_event" and ev and ev.type == "content_block_delta"
        and ev.delta and ev.delta.type == "text_delta" and ev.delta.text then
        acc = acc .. ev.delta.text         -- 只收正文(跳过 thinking_delta)
        renderBody(mdToHtml(acc))
      elseif obj.type == "result" and obj.result and #acc == 0 then
        acc = obj.result                   -- 没收到增量时的兜底
      end
    end
    task = hs.task.new("/bin/sh", function(code, out, err)
      if #buf > 0 then handleLine(buf); buf = "" end
      finish(acc, (errbuf ~= "" and errbuf) or err, #acc > 0)
    end, function(t, sout, serr)
      if done then return false end
      if serr and #serr > 0 then errbuf = errbuf .. serr end
      if sout and #sout > 0 then
        buf = buf .. sout
        while true do
          local nl = buf:find("\n", 1, true)
          if not nl then break end
          handleLine(buf:sub(1, nl - 1)); buf = buf:sub(nl + 1)
        end
      end
      return true
    end, { "-c", cmd })
  else
    local relayModel = relayModelFor(mode)
    if relayModel then
      -- 请求写成 OpenAI 格式 JSON 落临时文件(避免命令行转义/泄漏 key),curl 直连中转
      local detailed = (mode == "deep" or mode == "screen")  -- 详细类输出多些
      local body = hs.json.encode({
        model = relayModel,
        reasoning_effort = "low",
        max_completion_tokens = detailed and 480 or 320,
        messages = {
          { role = "system", content = instr },
          { role = "user",   content = sel },
        },
      })
      local jf = io.open(myFile, "w"); if jf then jf:write(body or ""); jf:close() end
      -- 超时:快速一瞥 12s;详细类(deep/screen,字多些)18s。卡住即快速失败、兜底回 claude,不傻等 40s
      local relayMaxtime = detailed and 18 or 12
      local relayCmd = pathFix .. "curl -s --max-time " .. relayMaxtime .. " -K '" .. relayConf
        .. "' --data-binary @" .. myFile .. " '" .. relayBase .. "/chat/completions'"
      local claudeCmd = pathFix .. "cat " .. myFile .. " | '" .. claudePath
        .. "' -p " .. modelFlag .. "'" .. instr .. "'"
      task = hs.task.new("/bin/sh", function(code, out, err)
        if done then return end
        local content
        local ok, o = pcall(hs.json.decode, out or "")
        if ok and type(o) == "table" and o.choices and o.choices[1]
          and o.choices[1].message then content = o.choices[1].message.content end
        content = cleanRelay(content)   -- 去掉 <think> 推理块再判断/显示
        if content and #(content:gsub("%s", "")) > 0 then
          usedSource = "relay"
          finish(content, nil, false)
        else
          -- 中转没给正文(key/网络/参数问题)→ 兜底回本机 claude,先把原文写回 myFile
          local cf = io.open(myFile, "w"); if cf then cf:write(sel); cf:close() end
          local ct = hs.task.new("/bin/sh", function(c2, out2, err2)
            finish(out2, err2, false)
          end, { "-c", claudeCmd })
          task = ct; ct:start()
        end
      end, { "-c", relayCmd })
    else
      local cmd = pathFix .. "cat " .. myFile .. " | '" .. claudePath .. "' -p " .. modelFlag .. "'" .. instr .. "'"
      task = hs.task.new("/bin/sh", function(code, out, err)
        finish(out, err, false)
      end, { "-c", cmd })
    end
  end
  task:start()

  -- 超时保护:45 秒没回就终止任务并提示,避免浮窗一直转
  killer = hs.timer.doAfter(45, function()
    if done then return end
    done = true
    if task then pcall(function() task:terminate() end) end
    os.remove(myFile)
    showCard("太久没回", "cc 这次太久没响应(可能卡住或网络慢)。按 Esc 关掉,再按一次试试。", "Esc 关闭", false)
    logQuery(mode, sel, false)
    teleSend("explained", { mode = mode, source = usedSource, ok = false,
      sel_len = lenBucket(#sel), ans_len = "0-20", timeout = true })
  end)
end

-- ===== "没懂"本地闭环实现(前向声明在文件上方;放这里才能调到 runClaude / 个人词典)=====
-- 只有用户点右下角"没懂?"才触发(懂了=直接关掉=默认,不点也不发信号)。三件事一起做:
--   ① 删掉这条烂答案(下次别再 0ms 秒出) ② 记住"这类要讲更细" ③ 立刻换聪明模型(deep)重讲。
-- 全程纯本地:删词典、记类别都只写本机文件;只有"没懂"这一个结果信号匿名发给作者(不含内容)。
function handleFeedback()
  local sel, mode = fbSel, fbMode
  teleSend("feedback", { helpful = false, mode = mode or "" })   -- 对外:匿名,一关全关同 telemetry.off
  if not (sel and #sel > 0) then return end
  removePersonal(sel)      -- ① 别再把这条烂答案 0ms 秒出
  bumpNeedsDeeper(sel)     -- ② 记住这类要讲更细(下次同类 personalProfile 会要求讲深点)
  runClaude(sel, "deep")   -- ③ 立刻换更聪明的模型重讲一遍
end

-- 终端开了「安全键盘输入」(Secure Keyboard Entry)时,系统会拦掉一切模拟按键,
-- 包括我们模拟的 ⌘C → 复制不到选区。AX 读屏不受影响,所以现象是「全屏能用、划选失效」。
local function secureInputOn()
  local f = hs.eventtap.isSecureInputEnabled
  return type(f) == "function" and f() or false
end

-- 划选抓不到、且安全键盘输入开着时的提示卡:告诉用户去关掉它,而不是默默退化成读整屏。
local function secureInputCard()
  showCard("划选用不了 · 终端开了「安全键盘输入」",
    "这个开关会拦掉划选复制(整屏解释不受影响)。到菜单栏关掉它再划选:iTerm2 → 取消勾选 Secure Keyboard Entry;系统「终端」→ 取消勾选 安全键盘输入。",
    "Esc 关闭", false)
end

-- 用辅助功能直接读前台聚焦元素的选中文字(不发按键、不碰剪贴板 → 不触发"没东西可复制"的 beep,也更快)。
-- 返回:选中的字符串 / "" (终端暴露选区但当前没选) / nil (终端不暴露选区,需退回 ⌘C 方式)。
local function axSelectedText()
  local app = hs.application.frontmostApplication()
  if not app then return nil end
  local ax = hs.axuielement.applicationElement(app)
  if not ax then return nil end
  local ok, focused = pcall(function() return ax:attributeValue("AXFocusedUIElement") end)
  if not ok or not focused then return nil end
  local ok2, sel = pcall(function() return focused:attributeValue("AXSelectedText") end)
  if ok2 and type(sel) == "string" then return sel end
  return nil
end

-- 抓当前选中文字。优先 AX 直读(暴露选区的终端走这条,永不发 ⌘C → 没 beep、更快);
-- 不暴露选区的终端(如 Ghostty)才退回:先存剪贴板 → 模拟 ⌘C → 读 → 还原(全异步,不卡界面)。
-- 抓不到时把 secure(是否开了安全键盘输入)回传给上层,据此提示而非默默读整屏。
local function withSelection(fn)
  local axSel = axSelectedText()
  if axSel ~= nil then
    if axSel ~= "" then fn(axSel) else fn(nil, secureInputOn()) end
    return
  end
  local saved = hs.pasteboard.getContents()
  hs.pasteboard.clearContents()
  hs.eventtap.keyStroke({ "cmd" }, "c", 0)
  hs.timer.doAfter(0.18, function()
    local sel = hs.pasteboard.getContents()
    hs.timer.doAfter(0.1, function()
      if saved ~= nil then hs.pasteboard.setContents(saved) end
    end)
    if sel == nil or sel == "" then fn(nil, secureInputOn()) else fn(sel) end
  end)
end

local function explain(mode)
  withSelection(function(sel, secure)
    if not sel then
      if secure then secureInputCard()
      else showCard("没选中文字", "先用鼠标在终端里划选一段看不懂的内容,再按快捷键。", "Esc 关闭", false) end
      return
    end
    runClaude(sel, mode)
  end)
end

-- 读最前面窗口的可见文字(走辅助功能,不截图)。没选中文字时用。
local function readScreenText()
  local app = hs.application.frontmostApplication()
  if not app then return nil end
  local ax = hs.axuielement.applicationElement(app)
  if not ax then return nil end
  local best
  local function walk(el, d)
    if d > 14 or best then return end
    local okr, role = pcall(function() return el:attributeValue("AXRole") end)
    if okr and role == "AXTextArea" then
      local okv, v = pcall(function() return el:attributeValue("AXValue") end)
      if okv and type(v) == "string" and #v > 100 then best = v; return end
    end
    local okc, kids = pcall(function() return el:attributeValue("AXChildren") end)
    if okc and kids then for _, k in ipairs(kids) do walk(k, d + 1) end end
  end
  walk(ax, 0)
  return best
end

-- 屏幕末尾像不像 cc 正在请求批准一个操作
local function looksPending(tail)
  return tail:find("Waiting", 1, true)
    or tail:find("Do you want", 1, true)
    or tail:find("❯%s*%d")
    or (tail:find("Bash command", 1, true) and tail:find("esc", 1, true))
end

-- ⌘?:智能键。选中了 → 解释那段;没选中 → 读最近屏幕,有权限请求就解释+风险,否则总结。
local function smart()
  heartbeat()
  withSelection(function(sel, secure)
    if sel and #sel > 0 then
      runClaude(sel, "quick")
      return
    end
    if secure then secureInputCard(); return end
    local text = readScreenText()
    if not text or #text < 20 then
      showCard("没读到内容", "选一段文字按 ⌘? 我来解释;或在终端里按,我读最近的内容帮你看。", "Esc 关闭", false)
      return
    end
    local tail = text:sub(-2800)
    if looksPending(tail:sub(-1000)) then
      runClaude(tail, "watch")
    else
      runClaude(tail, "recent")
    end
  end)
end

-- ⌘⌥?:详细版智能键。选中了→详细解释那段;没选中→读屏,稍详细解释整屏在干嘛。
local function smartDeep()
  heartbeat()
  withSelection(function(sel, secure)
    if sel and #sel > 0 then
      runClaude(sel, "deep")
      return
    end
    if secure then secureInputCard(); return end
    local text = readScreenText()
    if not text or #text < 20 then
      showCard("没读到内容", "在终端里按 ⌘⌥? 我会读最近这一屏帮你详细讲;选中一段则详细解释那段。", "Esc 关闭", false)
      return
    end
    runClaude(text:sub(-2800), "screen")
  end)
end

-- ⌘?:读卡点日志,归纳"你最近主要卡在哪几类"
local function summarize()
  heartbeat()
  local items = {}
  local f = io.open(logFile, "r")
  if f then
    for line in f:lines() do
      local ok, obj = pcall(hs.json.decode, line)
      if ok and obj and obj.preview and obj.mode ~= "summary" then
        items[#items + 1] = obj.preview
      end
    end
    f:close()
  end
  if #items == 0 then
    showCard("还没有记录", "你还没用 ⌥? 解释过东西。多用几次,这里就能告诉你最近主要卡在哪几类。", "Esc 关闭", false)
    return
  end
  -- 只取最近 60 条
  local start = math.max(1, #items - 59)
  local recent = {}
  for i = start, #items do recent[#recent + 1] = "- " .. items[i] end
  runClaude(table.concat(recent, "\n"), "summary")
end

-- ===== 快捷键(都在 /? 键上,不同修饰键)=====
-- ⌥?  全局智能键:选中了→解释那段;没选中→读最近屏幕(有权限请求评估风险,否则总结)
-- ⌘⌥? 详细解释选中
-- ⌘?  本周卡点小结
-- 关键:同时绑"带 shift / 不带 shift"两种,这样你按 ⌥? (= ⌥⇧/) 或 ⌥/ 都能触发,不用纠结。
hs.hotkey.bind({ "alt" }, "/", smart)                                  -- ⌥/
hs.hotkey.bind({ "alt", "shift" }, "/", smart)                         -- ⌥?
hs.hotkey.bind({ "cmd", "alt" }, "/", smartDeep)                       -- ⌘⌥/
hs.hotkey.bind({ "cmd", "alt", "shift" }, "/", smartDeep)              -- ⌘⌥?
-- 小结:⌘?(=⌘⇧/)会被 macOS"帮助"抢走。普通 hotkey 抢不过,改用 eventtap 在系统之前
-- 拦下 ⌘⇧/ 并吞掉事件(这样"帮助"不弹、小结触发)。⌘/ 留作兜底。
-- "/" 键的 keycode = 44。
SummaryTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(e)
  local f = e:getFlags()
  if e:getKeyCode() == 44 and f.cmd and f.shift and not f.alt and not f.ctrl then
    summarize()
    return true   -- 吞掉事件,阻止"帮助"
  end
  return false
end)
SummaryTap:start()
hs.hotkey.bind({ "cmd" }, "/", summarize)                              -- ⌘/  (兜底,稳)

hs.alert.show("看懂已就绪  ·  ⌥? 解释/看屏  ·  ⌘⌥? 详细  ·  ⌘? 卡点小结")

-- 启动后台查一次更新(每天最多一次;非标准安装路径自动跳过,不影响开发副本)
autoUpdate()

-- 预热:加载时就起一个常驻 claude,连第一次 ⌥? 都免冷启动(失败也无妨,会自动回退一次性)
warmStart()

-- 自进化:加载后台聚类一次「你的卡点主题」(攒够新条目才真跑,纯后台)
hs.timer.doAfter(8, function() pcall(maybeDiscoverTopics) end)

-- 测试钩子:可用 hs CLI 触发,验证"浮窗+调 cc"链路,无需辅助功能/无需选中
function kandongExplainText(txt, mode) runClaude(txt, mode or "quick") end
function kandongSummarize() summarize() end
function kandongMd(s) return mdToHtml(s) end
function kandongSmart() smart() end
function kandongPending(t) return looksPending(t) and true or false end
function kandongLocal(s) return lookupLocal(s) end
function kandongDiscover() discoverTopics() end
function kandongDiscovered() return hs.json.encode(loadDiscovered() or {}) end
function kandongProfile() return personalProfile() end
function kandongProfile() return personalProfile() end
function kandongPersonalGet(s) return lookupPersonal(s) end
function kandongPersonalSave(s, a) savePersonal(s, a) end
