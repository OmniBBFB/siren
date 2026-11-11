# siren.md

在 Neovim Markdown 中保留 Mermaid 源码，使用 Pele → SVG → PNG 预览。
支持原生 Kitty 行内/浮窗，以及可选 Snacks 图片链接后端。

## 本机安装（lazy.nvim）

依赖：Neovim 0.11+、Node 20+、本机 Kitty、可用中文字体。
Markdown Tree-sitter parser 可选；缺少时自动扫描围栏。无需 Mermaid parser、Chromium、mmdc 或 ImageMagick。

将 examples/lazy.lua 的内容放入 Neovim 的 lua/plugins/siren.lua。
插件目录执行：

```sh
npm ci --ignore-scripts
```

```lua
{
  dir = vim.fn.expand("~/app/siren"),
  name = "siren.md",
  main = "siren",
  ft = "markdown",
  build = "npm ci --ignore-scripts",
  opts = {
    snacks_preview = false,
    auto_start = false,
    parser = "auto", -- auto | treesitter | manual
    font = "Noto Sans CJK SC",
    font_size = 16,
    scale = 2,
    debounce_ms = 300,
    max_width = 100,
    max_height = 24,
    colors = {
      ["--pele-bg"] = "#1e2326",
      ["--pele-fg"] = "#d3c6aa",
    },
  },
}
```

快捷键由 Siren 插件统一注册，默认只在 Markdown buffer 生效；固定配色不跟随 colorscheme。
Markdown 内代码块须以 ` ```mermaid ` 开始并闭合；语言标签大小写不敏感，`Mermaid`、`MERMAID` 也可。普通的无语言 ` ``` ` 代码块不会自动按 Mermaid 解析。手动执行渲染但没有找到 Mermaid 块时会通知原因；复杂列表/引用嵌套建议安装 Markdown parser。

## 快捷键配置

默认：`<leader>mc` 当前块，`<leader>ma` 全文，`<leader>mv` 选区（Visual 模式），`<leader>mf` 浮窗，`<leader>mx` 清理。
在 lazy.nvim 的 `opts` 或 `require("siren").setup()` 中统一覆盖：

```lua
keymaps = {
  current = "<leader>mc",
  all = "<leader>ma",
  selection = "<leader>mv",
  float = "<leader>mf",
  clear = "<leader>mx",
}
```

`keymaps = false` 关闭全部映射，单项设置为 `false` 关闭对应映射。重新 setup 会清理旧的插件映射；不再使用 lazy 的 `keys` 表维护第二份配置。

## 操作

| 命令 | 行为 |
|---|---|
| :Siren | 开启光标所在块的行内预览 |
| :Siren all | 开启全文行内预览 |
| :'<,'>Siren | 开启选区相交的完整块 |
| :Siren float | 当前块浮窗；原生浮窗 q/Esc 关闭 |
| :Siren clear | 停止会话，清理预览及范围内的托管链接 |
| :Siren disable | 停止会话，保留已生成的 Markdown 链接 |
| :Siren status | 查看当前会话 |
| :SirenPrune 30 | 预览超过30天未使用的全局缓存清理数量 |
| :SirenPrune! 30 | 执行清理 |
| :checkhealth siren | 检查环境 |

开启后，源码改动会自动刷新；错误通知后不显示该块旧图。
全局缓存位于 stdpath("cache")/siren。PNG、SVG、JSON 同名，JSON 记录多个来源路径。
原生模式只创建 extmark 虚拟行和 Kitty virtual placement，不修改 buffer。其他插件隐藏结束围栏时，会保留逻辑位置并改用可见行放置图片。多窗口共享 buffer 时按最窄窗口适配。

## Snacks 后端

设置 snacks_preview=true，启用 Snacks.image.doc.inline。
切回原生模式前先执行 :Siren clear 清理托管链接，避免 Snacks 与原生模式重复显示。
插件在 Markdown 旁创建 .siren/<内容哈希>.png，并在围栏后维护：

```markdown
<!-- siren:begin -->
![Mermaid preview](<.siren/内容哈希.png>)
<!-- siren:end -->
```

这是实际 buffer 内容，会产生 modified 状态，由用户正常 :write 保存。插件不会自动保存。
只更新完整托管标记内的链接；不要在这些标记中手工添加内容。
普通手写图片不改动。该模式不创建本插件的 Kitty placement；Snacks 负责行内图和浮窗。
浮窗命令会将光标移至生成的图片链接，使用 Snacks 自身的 hover 生命周期。

移动整个目录时，相对链接和 .siren 一起迁移。只移动 .md 时，打开并重新渲染即可在新位置生成图片和修复链接。
旧来源保留在 metadata；无法无歧义识别外部 mv 和复制。项目图片不参与全局缓存清理，避免误删已链接的资产。

Snacks 自带 Mermaid 捕获需要关闭，普通图片捕获保留。本插件不修改全局 Tree-sitter 查询。
本机配置提供了仅移除 Mermaid 捕获的显式集成，示例在 examples/snacks-query.lua；保留普通图片与公式查询。生成图片的显示宽度会扣除行号/符号栏，按最窄窗口缩放。

## 测试

```sh
npm test
nvim --headless -u NONE -i NONE -l tests/headless.lua
nvim --headless -u NONE -i NONE -l tests/trigger.lua
```

第二项使用本机已安装的 Markdown parser；源码与 PNG 测试不依赖 Snacks。
真实 Kitty 验收见 tests/gui.lua 与 .test-output/validation.json（验收后生成）。

## 当前范围

本机 Kitty；Linux 的单元格尺寸检测。SSH/tmux 不启用原生显示。
内置围栏扫描支持最多3格缩进、反引号/波浪线，深层列表与引用使用 Tree-sitter。
Pele 语法和布局以当前锁定版本为准；公式、外部图片、自动资产打包与跨机器文档 UUID 不在初版范围。

## 名称迁移

项目目录为 ~/app/siren，Lua 模块为 siren，命令为 :Siren 和 :SirenPrune。
旧版托管链接标记仍可识别；重新渲染会写入新标记与 .siren/ 路径。已有项目旁的旧图片保留，不自动删除。
本机原全局缓存已在新缓存目录不存在时迁移至 stdpath("cache")/siren。运行中的旧 Neovim 会话需要重启。
