#!/usr/bin/env python3
# 看懂 · 低风险命令自动放行(Claude Code PreToolUse hook)
#
# cc 每次要执行 Bash 命令前,会先把命令交给这个脚本。脚本判断:
#   - 只看不改的命令、常见安全操作(测试/检查/查依赖) → allow(自动放行)
#   - 极危险的(rm -rf /、sudo、curl|sh 等)            → deny(直接拦下)
#   - 其余                                             → 不表态,交给 cc 照常问用户
#
# 关键安全设计:只要命令里有可能"夹带"副作用的 shell 拼接(; && || > < ` $( &),
# 一律不自动放行(走正常询问),哪怕开头是 ls。纯只读命令之间的管道 | 例外放行。
#
# 输出格式见 Claude Code 文档 PreToolUse hookSpecificOutput。

import sys, json, re, shlex, os, time

LOG = os.path.expanduser("~/Desktop/mouse-ai/v0-kandong/logs/auto-approve.jsonl")


def emit(decision, reason, cmd):
    # 记录(透明:你能回看它自动放行/拦下了什么)
    try:
        with open(LOG, "a") as f:
            f.write(json.dumps({
                "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "decision": decision,
                "cmd": cmd[:200],
            }, ensure_ascii=False) + "\n")
    except Exception:
        pass
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": decision,
        "permissionDecisionReason": reason,
    }}, ensure_ascii=False))
    sys.exit(0)


def defer():
    # 不输出任何决定 → cc 走正常询问流程
    sys.exit(0)


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        defer()

    if data.get("tool_name") != "Bash":
        defer()

    cmd = (data.get("tool_input") or {}).get("command", "")
    if not isinstance(cmd, str) or not cmd.strip():
        defer()
    c = cmd.strip()

    # ---- 1) 极危险:直接拦下(连问都不问) ----
    # rm 只在删"危险目标"时才拦:根 / 家目录 / 系统目录 / 通配 / --no-preserve-root。
    # 普通 rm 某个文件、/tmp/x、项目子目录 → 不拦,交给用户问(defer)。
    def danger_rm(s):
        try:
            parts = shlex.split(s)
        except Exception:
            parts = s.split()
        # 找到 rm(允许前面有 sudo)
        idx = None
        for i, p in enumerate(parts):
            if p == "rm" or p.endswith("/rm"):
                idx = i; break
        if idx is None:
            return False
        if "--no-preserve-root" in parts:
            return True
        DANGER = {"/", "~", "~/", "$HOME", "${HOME}", "*", ".", "..", "./", "../",
                  "/Users", "/System", "/Library", "/Applications", "/etc", "/bin",
                  "/sbin", "/usr", "/var", "/opt", "/private"}
        for a in parts[idx + 1:]:
            if a.startswith("-"):
                continue
            t = a.rstrip("/")
            if a in DANGER or t in DANGER:
                return True
            if a.endswith("/*"):
                return True
            if re.match(r"^/Users/[^/]+$", t):  # 删整个用户主目录
                return True
            if re.match(r"^~/?$", a):
                return True
        return False

    DENY = [
        r":\s*\(\s*\)\s*\{",                              # fork bomb :(){
        r"\bmkfs\b", r"\bdd\b[^\n]*\bof=/dev/", r">\s*/dev/sd",
        r"\bsudo\b",                                       # 非技术用户:sudo 一律拦
        r"\bchmod\s+-R\s+0*777\s+/",
        r"\b(curl|wget)\b[^\n]*\|\s*(sudo\s+)?(sh|bash|zsh|python3?)\b",  # curl|sh
        r"\bgit\s+push\b[^\n]*--force",
        r"\b(shutdown|reboot|halt|poweroff)\b",
        r">\s*/etc/",
    ]
    if danger_rm(c) or any(re.search(p, c) for p in DENY):
        emit("deny", "看懂:这条命令风险很高,已自动拦下。确实需要的话请手动处理。", c)

    # ---- 2) 判断有没有"夹带副作用"的拼接符 ----
    CHAIN = [";", "&&", "||", ">", "<", "`", "$(", "&"]
    has_chain = any(tok in c for tok in CHAIN)

    READONLY = {
        "ls", "cat", "grep", "egrep", "fgrep", "rg", "find", "head", "tail",
        "wc", "which", "pwd", "echo", "stat", "file", "du", "df", "tree",
        "whoami", "date", "env", "printenv", "type", "cut", "sort", "uniq",
        "basename", "dirname", "realpath", "readlink", "hostname", "uname",
        "ps", "top", "id", "groups", "history",
    }
    GIT_RO = {"status", "diff", "log", "show", "branch", "remote", "config",
              "blame", "describe", "tag", "stash", "ls-files", "rev-parse"}

    # 中等档:不改源码的常见安全操作(测试/检查/查依赖/构建)
    SAFE_PROJECT = [
        r"^npm\s+(test|run\s+(test|lint|build|typecheck|check|format:check|tsc)|ls|list|outdated|view|info|why|audit)\b",
        r"^npx\s+(tsc|eslint|jest|vitest|playwright\s+test|prettier\s+--check)\b",
        r"^yarn\s+(test|lint|build|why|list|outdated|info)\b",
        r"^pnpm\s+(test|lint|build|list|why|outdated)\b",
        r"^(pytest|jest|vitest|mocha|tsc|eslint|ruff|flake8|mypy)\b",
        r"^black\s+--check\b", r"^prettier\s+--check\b",
        r"^python3?\s+-m\s+(pytest|mypy|flake8|ruff|unittest|json\.tool)\b",
        r"^make\s+(test|lint|check|build)\b",
        r"^go\s+(test|vet|build)\b",
        r"^cargo\s+(test|check|build|clippy)\b",
        r"^(node|python3?)\s+--version\b", r"^\w+\s+--version\b", r"^\w+\s+--help\b",
    ]

    def first_token(s):
        try:
            parts = shlex.split(s)
        except Exception:
            parts = s.split()
        return (parts[0] if parts else ""), parts

    def is_readonly_simple(s):
        t, parts = first_token(s)
        if t in READONLY:
            return True
        if t == "git":
            i, sub = 1, None
            while i < len(parts):
                if parts[i].startswith("-"):
                    i += 2 if parts[i] in ("-C", "--git-dir", "--work-tree") else 1
                    continue
                sub = parts[i]; break
            return sub in GIT_RO
        return False

    # ---- 3) 没有夹带:只读命令 / 安全操作 → 放行 ----
    if not has_chain:
        if is_readonly_simple(c):
            emit("allow", "看懂:只读命令(只看不改),已自动放行。", c)
        for p in SAFE_PROJECT:
            if re.search(p, c):
                emit("allow", "看懂:常见安全操作(测试/检查类,不改源码),已自动放行。", c)
    else:
        # 纯管道、且每一段都是只读命令 → 放行(如 cat x | grep y | head)
        only_pipe = ("|" in c) and not any(t in c for t in [";", "&&", "||", ">", "<", "`", "$(", "&"])
        if only_pipe:
            segs = [s.strip() for s in c.split("|") if s.strip()]
            if segs and all(is_readonly_simple(s) for s in segs):
                emit("allow", "看懂:只读查看(管道里都是只看不改的命令),已自动放行。", c)

    # ---- 4) 其余:不表态,交给 cc 照常问你(你可选中按 ⌘⌥E 看懂) ----
    defer()


if __name__ == "__main__":
    main()
