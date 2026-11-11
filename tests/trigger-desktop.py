"""Verify the actual Markdown file through the user's installed lazy config."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / ".test-output"
OUT.mkdir(exist_ok=True)
test_file = OUT / "xxx-Mermaid-trigger.md"
source_lines = Path("/home/csc/outputs/xxx.md").read_text().splitlines()
source_lines[0] = chr(96) * 3 + "Mermaid"
test_file.write_text("\n".join(source_lines) + "\n")
directory = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(tempfile.mkdtemp(prefix="siren-trigger-"))
server = str(directory / "nvim.sock")
kitty = str(directory / "kitty.sock")
env = dict(os.environ, XDG_RUNTIME_DIR="/run/user/1000", WAYLAND_DISPLAY="wayland-1")

def remote(body):
    expr = "luaeval(" + json.dumps("(function() " + body + " end)()") + ")"
    return subprocess.check_output(
        ["nvim", "--server", server, "--remote-expr", expr], text=True, stderr=subprocess.PIPE, timeout=5
    ).strip()

def until(fn, message):
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        try:
            if fn(): return
        except (subprocess.SubprocessError, FileNotFoundError):
            pass
        time.sleep(.15)
    raise AssertionError(message)

def send(keys):
    subprocess.run(["nvim", "--server", server, "--remote-send", keys], check=True, timeout=10)

def ready():
    return remote("local m=package.loaded.siren; if not m then return false end; local s=m.status(); return not s.busy and s.results and #s.results==1") == "true"

if len(sys.argv) == 1:
    subprocess.run([
        "kitty", "--detach", "--title", "Siren automated verification",
        "--listen-on", "unix:" + kitty, "--override", "allow_remote_control=yes",
        "nvim", "-i", "NONE", "--listen", server, str(test_file)
    ], env=env, check=True)
until(lambda: remote("return vim.fn.exists(':Siren')") == "2", "Siren command did not load")
mapping = json.loads(remote("local m=vim.fn.maparg('<Space>ma','n',false,true); return vim.json.encode({buffer=m.buffer,desc=m.desc,lhs=m.lhs,has_callback=type(m.callback)=='function'})"))
assert mapping.get("buffer") == 1 and mapping.get("desc", "").startswith("Siren:"), mapping
send("<Space>ma")
until(ready, "Physical <Space>ma did not render xxx.md")
send("<Cmd>Siren clear<CR>")
until(lambda: remote("return require('siren').status().enabled==false") == "true", "Clear failed")
send("<Cmd>Siren all<CR>")
until(ready, ":Siren all did not render xxx.md")
assert remote("return #vim.api.nvim_buf_get_extmarks(0,require('siren.kitty').ns,0,-1,{})>0") == "true"
time.sleep(.8)
remote("if Snacks and Snacks.notifier then Snacks.notifier.hide() end; vim.cmd.redraw(); return true")
assert int(remote("return vim.api.nvim_win_text_height(0,{}).fill")) > 0, "Image virtual rows are concealed"
screenshot = OUT / "xxx-mermaid-trigger.png"
subprocess.run(["kitty", "@", "--to", "unix:" + kitty, "screenshot", str(screenshot)], check=True)
result = {
    "passed": True, "source": "/home/csc/outputs/xxx.md", "file": str(test_file),
    "first_line": remote("return vim.api.nvim_buf_get_lines(0,0,1,false)[1]"),
    "buffer_keymap": mapping["desc"], "key_trigger": True, "command_trigger": True,
    "screenshot": str(screenshot), "server": server, "kitty": kitty,
    "placements": json.loads(remote("local p={}; for _,v in pairs(require('siren.kitty').placements) do local m=vim.api.nvim_buf_get_extmark_by_id(v.buf,require('siren.kitty').ns,v.mark,{details=true}); p[#p+1]={buf=v.buf,row=v.row,cols=v.cols,rows=v.rows,markrow=m[1],lines=m[3] and #(m[3].virt_lines or {})} end; return vim.json.encode(p)")),
    "text_height": json.loads(remote("return vim.json.encode(vim.api.nvim_win_text_height(0,{}))")),
}
(OUT / "trigger-desktop.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
print(json.dumps(result, ensure_ascii=False, indent=2))
