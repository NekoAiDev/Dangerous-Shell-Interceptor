// 危险Shell拦截 DSI - WebUI 逻辑
// 适配 KernelSU WebUI 与 Magisk MMRL WebUI 的执行桥。

const DSI = "/data/adb/dsi/bin/dsi";
const CONFIG = "/data/adb/dsi/config.conf";

const RULES = [
  ["forkbomb", "fork 炸弹"],
  ["dd", "块设备写入"],
  ["mkfs", "格式化 / 分区"],
  ["rm", "递归删除"],
  ["chmod_chown", "权限 / 属主修改"],
  ["redirect", "重定向覆盖"],
  ["mv", "移动 / 重命名"],
  ["wipe", "擦除 / 格式化"],
  ["flash", "刷写 / 擦除分区"],
  ["selinux", "SELinux 关闭"],
  ["mount_rw", "系统分区改写挂载"],
  ["pm_uninstall", "系统应用卸载"],
  ["curl_pipe", "网络脚本直执行"],
  ["kill", "关键进程终止"],
];

// 统一的命令执行桥
async function exec(cmd) {
  if (window.KSUWebUI && typeof window.KSUWebUI.exec === "function") {
    const r = await window.KSUWebUI.exec(cmd);
    return { code: r.errno || 0, out: r.stdout || "", err: r.stderr || "" };
  }
  if (window.MMRLWebUI && typeof window.MMRLWebUI.exec === "function") {
    const r = await window.MMRLWebUI.exec(cmd);
    return { code: r.code || 0, out: r.stdout || "", err: r.stderr || "" };
  }
  throw new Error("当前环境不支持 WebUI 命令执行（需 KernelSU 或 MMRL）。");
}

function setStatus(ok) {
  const dot = document.getElementById("status-dot");
  dot.className = "dot " + (ok ? "on" : "off");
}

function esc(s) {
  return (s || "").replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" }[c]));
}

function riskClass(risk) {
  switch ((risk || "").toLowerCase()) {
    case "critical":
    case "high": return "crit";
    case "medium": return "med";
    case "low": return "low";
    case "none": return "safe";
    default: return "";
  }
}

// 解析 `dsi config` 输出，得到规则状态与白名单
function parseConfig(text) {
  const rules = {};
  let inRules = false;
  let inAllow = false;
  const allow = [];
  (text || "").split("\n").forEach((line) => {
    if (line.indexOf("已启用规则") >= 0) { inRules = true; inAllow = false; return; }
    if (line.indexOf("白名单条目") >= 0) { inRules = false; inAllow = true; return; }
    if (inRules) {
      const m = line.trim().match(/^(\S+)\s+(on|off)$/);
      if (m) rules[m[1]] = m[2];
    }
    if (inAllow) {
      const m = line.trim().match(/^allow\.\*=(.*)$/);
      if (m) allow.push(m[1]);
    }
  });
  return { rules, allow };
}

async function renderRules() {
  const box = document.getElementById("rules");
  try {
    const { out } = await exec(`${DSI} config`);
    const { rules } = parseConfig(out);
    box.innerHTML = "";
    RULES.forEach(([id, desc]) => {
      const on = (rules[id] || "on") === "on";
      const el = document.createElement("div");
      el.className = "rule";
      el.innerHTML =
        `<div><div class="name">${esc(id)}</div><div class="desc">${esc(desc)}</div></div>` +
        `<label class="switch"><input type="checkbox" ${on ? "checked" : ""} data-rule="${esc(id)}">` +
        `<span class="slider"></span></label>`;
      box.appendChild(el);
    });
    box.querySelectorAll("input[data-rule]").forEach((inp) => {
      inp.addEventListener("change", async (e) => {
        const id = e.target.dataset.rule;
        const val = e.target.checked ? "on" : "off";
        e.target.disabled = true;
        try {
          await exec(`${DSI} set rule.${id} ${val}`);
          await renderRules();
        } catch (err) {
          alert("操作失败: " + err.message);
          e.target.checked = !e.target.checked;
        } finally {
          e.target.disabled = false;
        }
      });
    });
    setStatus(true);
  } catch (err) {
    box.innerHTML = `<div class="notice">无法读取规则：${esc(err.message)}</div>`;
    setStatus(false);
  }
}

async function renderAllow() {
  const box = document.getElementById("allowlist");
  try {
    const { out } = await exec(`${DSI} config`);
    const { allow } = parseConfig(out);
    box.innerHTML = "";
    if (!allow.length) {
      box.innerHTML = `<span class="hint">（空）</span>`;
      return;
    }
    allow.forEach((p) => {
      const chip = document.createElement("span");
      chip.className = "chip";
      chip.innerHTML = `${esc(p)} <span class="x" data-pat="${esc(p)}">x</span>`;
      box.appendChild(chip);
    });
    box.querySelectorAll(".x[data-pat]").forEach((x) => {
      x.addEventListener("click", async () => {
        try {
          await exec(`${DSI} unallow ${JSON.stringify(x.dataset.pat).slice(1, -1)}`);
          await renderAllow();
        } catch (err) {
          alert("删除失败: " + err.message);
        }
      });
    });
  } catch (err) {
    box.innerHTML = `<div class="notice">${esc(err.message)}</div>`;
  }
}

async function renderLog() {
  const el = document.getElementById("log");
  try {
    const { out } = await exec(`${DSI} log`);
    el.textContent = out && out.trim() ? out : "暂无拦截日志";
  } catch (err) {
    el.textContent = "无法读取日志: " + err.message;
  }
}

async function testDetect() {
  const inp = document.getElementById("test-input");
  const res = document.getElementById("test-result");
  const cmd = inp.value.trim();
  if (!cmd) { res.textContent = "请输入要检测的命令"; return; }
  res.className = "result";
  res.textContent = "检测中...";
  try {
    const { out, code } = await exec(`${DSI} check ${JSON.stringify(cmd)}`);
    const riskLine = (out.match(/风险等级\s*:\s*(\S+)/) || [])[1] || (code === 0 ? "none" : "unknown");
    const rc = riskClass(riskLine);
    res.className = "result " + rc;
    res.textContent = out && out.trim() ? out : (code === 0 ? "安全: 未检测到危险操作" : "检测到风险");
  } catch (err) {
    res.className = "result crit";
    res.textContent = "检测失败: " + err.message;
  }
}

document.getElementById("test-btn").addEventListener("click", testDetect);
document.getElementById("test-input").addEventListener("keydown", (e) => {
  if (e.key === "Enter") testDetect();
});
document.getElementById("allow-btn").addEventListener("click", async () => {
  const inp = document.getElementById("allow-input");
  const v = inp.value.trim();
  if (!v) return;
  try {
    await exec(`${DSI} allow ${JSON.stringify(v)}`);
    inp.value = "";
    await renderAllow();
  } catch (err) {
    alert("添加失败: " + err.message);
  }
});

// 终端：直接运行 dsi 子命令
async function termRun() {
  const inp = document.getElementById("term-input");
  const res = document.getElementById("term-result");
  const cmd = inp.value.trim();
  if (!cmd) { res.textContent = "请输入 dsi 子命令，例如 help"; return; }
  res.className = "result";
  res.textContent = "运行中...";
  try {
    const { out, err } = await exec(`${DSI} ${cmd}`);
    res.textContent = (out || "") + (err ? "\n" + err : "");
    if (!res.textContent) res.textContent = "(无输出)";
  } catch (err) {
    res.className = "result crit";
    res.textContent = "执行失败: " + err.message;
  }
}
document.getElementById("term-btn").addEventListener("click", termRun);
document.getElementById("term-input").addEventListener("keydown", (e) => {
  if (e.key === "Enter") termRun();
});

// 一键更新
async function doUpdate() {
  const res = document.getElementById("term-result");
  res.className = "result";
  res.textContent = "更新中...\n";
  try {
    const { out, err } = await exec(`${DSI} update`);
    res.textContent = (out || "") + (err ? "\n" + err : "");
    if (!res.textContent) res.textContent = "(无输出)";
    await renderRules(); await renderAllow(); await renderLog();
  } catch (err) {
    res.className = "result crit";
    res.textContent = "更新失败: " + err.message;
  }
}
document.getElementById("update-btn").addEventListener("click", doUpdate);

document.getElementById("refresh").addEventListener("click", () => {
  renderRules(); renderAllow(); renderLog();
});

// 初始化
renderRules();
renderAllow();
renderLog();
