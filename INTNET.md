# Siren：项目意图

插件名：siren.md，Lua 模块：siren。
用户目标：在本机 Neovim 编辑 Markdown 时，保留 Mermaid 源码并查看真实图片。采用 Pele 自身的 Mermaid 解析器，生成 SVG，再转 PNG，使用 Kitty 显示；可选借助 Snacks 通过 Markdown 图片链接显示。
本文件按用户指定命名为 INTNET.md。

## 已收敛的需求

- 默认通过 lazy.nvim 从 OmniBBFB/siren Git 仓库安装，build 自动安装锁定依赖；本地 dir 模式仅用于开发。Neovim 0.11+，本机 Kitty，Node 20+。
- 同时提供行内与浮窗；保留源码，默认手动启用，启用后自动刷新。
- 范围为当前代码块、全文、与选区相交的完整代码块。
- 快捷键由插件 setup({ keymaps = ... }) 统一配置并注册，仅作用于 Markdown；手动请求零匹配需提示。
- 先定位 Markdown Mermaid 围栏，再将内容交给 Pele；无需 Mermaid Tree-sitter parser。
- 优先 Markdown Tree-sitter；缺失时手工解析围栏。
- 定位或渲染失败通知错误，暂不显示；不保留该块旧图。
- 异步结果显示前检查源码，内容变化后自动调度新版本，旧结果不显示。
- 固定可配置字体；固定 CSS；窗口变窄按比例缩小、不改变布局方向。
- snacks_preview=false：自己的 extmark 和 Kitty 图片，绝不插入预览链接。
- snacks_preview=true：维护生成的图片链接，交给 Snacks 显示，不创建自己的图片。
- 记录 PNG 到 Markdown 的多来源 metadata；考虑移动与旧缓存回收。

## 实现取舍

预览缓存默认放 stdpath("cache")/siren。Snacks 模式生成图放 Markdown 旁 .siren/，写入相对链接，随文档目录迁移；独立模式不改 Markdown。
Snacks 链接使用所有权标记，仅更新/删除本插件标记的链接。用户手写图片完全不触碰。
固定 CSS 是对上一轮“固定 rss”的暂定解释；初版实现固定 CSS 配色。
导出、自动追踪外部 mv、跨机器稳定文档 UUID、远程/tmux 支持不属于首版本机目标。
