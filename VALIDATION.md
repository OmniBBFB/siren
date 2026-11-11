# 本机验收

2026-11-10：Neovim 0.11.0，Node 22.22.1，Kitty 0.50.0；Pele 1.13.0，resvg 2.6.2。

- npm test：2项通过，覆盖实际中文流程图/时序图PNG、CSS变量作用域、缓存复用、多来源及并发合并、配色失效、错误输入。
- nvim --headless -u NONE -i NONE -l tests/headless.lua：8项通过，覆盖围栏、Tree-sitter、托管链接、原生完整管线、异步改图/停止、范围、重命名/错误清理、浮窗缩放与释放。
- tests/desktop.py：真实Kitty原生/图链Snacks行内与浮窗、编辑刷新、清理通过；原生分屏缩放与滚动检查通过。已检查截图，源码与实际图片可见。
- tests/local-config.lua：使用本机完整配置检查lazy.nvim加载、命令/快捷键、Snacks关闭Mermaid捕获并保留普通图片通过。

详细结果和截图位于忽略Git跟踪的.test-output/：validation.json、local-config.json、native-inline.png、native-float.png、snacks-inline.png、snacks-float.png。

修复过真实截图发现的空白浮窗，以及Snacks未扣除行号栏导致的右侧裁切。浮窗现用实际空白行承载placeholder；生成的Snacks placement按文本区宽度缩放。

范围限制：仅本机Kitty；外部单独移动Markdown后通过重新渲染修复链接，项目旁资产不自动删除；无远程、tmux或自动打包验收。

更名验收：项目名 siren.md、Lua 模块 siren、命令 :Siren/:SirenPrune；保留旧版托管标记兼容。更名后重新验证渲染测试、headless 集成及本机 lazy.nvim 加载。

## 2026-11-11：触发、标签与围栏隐藏回归

根因：
- 无语言围栏不匹配 Mermaid；手动执行全文渲染时此前零匹配静默。
- 语言标签此前区分大小写，Mermaid/MERMAID 没有被识别。
- 快捷键此前只在 lazy 示例中定义，插件 setup 本身没有注册。
- render-markdown 的 conceal_lines 隐藏结束围栏时，挂在该行的图片虚拟行一并隐藏；只检查图片对象/渲染结果会漏掉此问题。

修复：
- 围栏语言标签大小写不敏感；Mermaid 源码仍仅由 Pele 解析。
- 明确手动请求的零匹配通知；自动扫描保持安静。
- 通过 setup({ keymaps = ... }) 统一管理 Markdown buffer 映射，支持覆盖、禁用和重新配置，Visual 映射读取当前选区。
- Kitty 保留逻辑围栏锚点，遇到隐藏行改用可见显示锚点，随模式/光标变化重新检查。

验证：
- tests/trigger.lua：8/8，通过手动/Tree-sitter大小写、零匹配通知、插件独立映射、重配置、实际渲染、Visual选区、隐藏围栏实际布局检查。
- tests/headless.lua：8/8，原有功能回归通过。
- tests/local-config.lua：本机 lazy 加载和 Snacks 普通图片共存通过。
- tests/trigger-desktop.py：本机完整配置，使用 ~/outputs/xxx.md 的独立副本，标签固定为 Mermaid。实际发送 <Space>ma 和 :Siren all 均成功。
- 图片虚拟行从修复前 fill=0 变为 fill=24；已查看 .test-output/xxx-mermaid-trigger.png 确认真实像素图可见。
- 不修改用户正在编辑的 ~/outputs/xxx.md；副本和验收 JSON 在 .test-output/。

## Git 安装验收

默认仓库为 OmniBBFB/siren。本机执行 `:Lazy install siren`，成功克隆至 ~/.local/share/nvim/lazy/siren 并自动运行 npm ci --ignore-scripts。安装提交为 b4c68d58f999a9a14e8d2579c5961042fd6a9c76。

`tests/local-config.lua` 已检查 Git spec、lazy 托管路径、实际加载的 runtime root、Pele 依赖、命令和快捷键、Snacks 普通图片共存，以及从安装目录实际生成两张 Mermaid 图片，全部通过。结果在 .test-output/local-config.json。开发目录 ~/app/siren 不再是默认运行依赖。
