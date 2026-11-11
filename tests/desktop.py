"""Run only against the dedicated siren test windows."""
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / ".test-output"
ENV = dict(os.environ, XDG_RUNTIME_DIR="/run/user/1000", WAYLAND_DISPLAY="wayland-1")
NATIVE = "/tmp/siren-nvim.sock"
SNACKS = "/tmp/siren-snacks-nvim.sock"

def remote(sock, body):
    expr = "luaeval(" + json.dumps("(function() " + body + " end)()") + ")"
    return subprocess.check_output(["nvim", "--server", sock, "--remote-expr", expr], text=True).strip()

def until(fn, message, seconds=25):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if fn():
            return
        time.sleep(.15)
    raise AssertionError(message)

def screenshot(socket, filename):
    time.sleep(.5)
    subprocess.run(["kitty", "@", "--to", "unix:" + socket, "screenshot", str(OUT / filename)], check=True)

# Recreate only the dedicated native fixture so code changes are loaded.
subprocess.run(["nvim", "--server", NATIVE, "--remote-send", "<Cmd>qa!<CR>"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(.4)
(OUT / "gui-native.json").unlink(missing_ok=True)
subprocess.run([
    "kitty", "--detach", "--title", "siren-native-test",
    "--listen-on", "unix:/tmp/siren-kitty.sock",
    "--override", "allow_remote_control=yes", "nvim",
    "-u", str(ROOT / "tests/gui.lua"), "-i", "NONE", "--listen", NATIVE,
], env=dict(ENV, SIREN_TEST_MODE="native"), check=True)
until(lambda: (OUT / "gui-native.json").exists(), "native fixture")
result = {"native": {}, "snacks": {}}
remote(NATIVE, "vim.cmd('edit! ' .. vim.fn.fnameescape('" + str(ROOT / "examples/demo.md") + "')); require('siren').render('all')")
until(lambda: remote(NATIVE, "local s=require('siren').status(); return not s.busy and #(s.results or {})==2") == "true", "native initial render")
result["native"]["initial"] = json.loads((OUT / "gui-native.json").read_text())
assert result["native"]["initial"]["passed"]
screenshot("/tmp/siren-kitty.sock", "native-inline.png")
remote(NATIVE, "vim.api.nvim_win_set_cursor(0,{17,0}); require('siren').float()")
until(lambda: remote(NATIVE, "return require('siren')._sessions[1].float_place ~= nil") == "true", "native float")
screenshot("/tmp/siren-kitty.sock", "native-float.png")
remote(NATIVE, "vim.api.nvim_win_close(vim.api.nvim_get_current_win(),true)")
remote(NATIVE, "vim.api.nvim_buf_set_lines(1,6,7,false,{'  A[最新版本] --> B{Pele 解析}'}); vim.api.nvim_exec_autocmds('TextChanged',{buffer=1})")
until(lambda: remote(NATIVE, "local s=require('siren').status(); if s.busy then return false end; for _,r in ipairs(s.results or {}) do if r.block.source:find('最新版本',1,true) then return true end end; return false") == "true", "native edit refresh")
result["native"]["float"] = True
result["native"]["latest_edit"] = True
remote(NATIVE, "require('siren').clear()")
assert remote(NATIVE, "return next(require('siren.kitty').placements)==nil") == "true"
result["native"]["clear"] = True

(OUT / "gui-snacks.json").unlink(missing_ok=True)
subprocess.run([
    "kitty", "--detach", "--title", "siren-snacks-test",
    "--listen-on", "unix:/tmp/siren-snacks-kitty.sock",
    "--override", "allow_remote_control=yes",
    "nvim", "-u", str(ROOT / "tests/gui.lua"), "-i", "NONE",
    "--listen", SNACKS
], env=dict(ENV, SIREN_TEST_MODE="snacks"), check=True)
until(lambda: (OUT / "gui-snacks.json").exists(), "Snacks test output")
result["snacks"]["initial"] = json.loads((OUT / "gui-snacks.json").read_text())
assert result["snacks"]["initial"]["passed"], result["snacks"]["initial"]
screenshot("/tmp/siren-snacks-kitty.sock", "snacks-inline.png")
remote(SNACKS, "vim.api.nvim_win_set_cursor(0,{7,0}); require('siren').float()")
until(lambda: remote(SNACKS, "return #vim.api.nvim_tabpage_list_wins(0)>1") == "true", "Snacks float")
screenshot("/tmp/siren-snacks-kitty.sock", "snacks-float.png")
result["snacks"]["float"] = True
assert remote(SNACKS, "return next(require('siren.kitty').placements)==nil") == "true"
result["snacks"]["no_duplicate_native"] = True
remote(SNACKS, "Snacks.image.doc.hover_close(); require('siren').clear()")
until(lambda: remote(SNACKS, "return #vim.api.nvim_buf_get_extmarks(1,Snacks.image.placement.ns,0,-1,{})==0") == "true", "Snacks clear")
result["snacks"]["clear"] = True
result["passed"] = True
(OUT / "validation.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
print(json.dumps(result, ensure_ascii=False, indent=2))
subprocess.run(["nvim", "--server", SNACKS, "--remote-send", "<Cmd>qa!<CR>"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
until(lambda: not Path(SNACKS).exists(), "Snacks fixture shutdown")
# Restore source in the native demonstration without saving it.
remote(NATIVE, "vim.cmd('edit! ' .. vim.fn.fnameescape('" + str(ROOT / "examples/demo.md") + "')); require('siren').render('all')")
