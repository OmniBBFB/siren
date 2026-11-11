```
flowchart TD
    A["打开 Markdown 文件"] --> B["检测 Mermaid 代码块"]
    B --> C{"是否需要渲染？"}
    C -->|是| D["解析 Mermaid 源码"]
    D --> E["生成图表"]
    E --> F["在 Neovim 中显示"]
    C -->|否| G["保持源码显示"]
    F --> H["监听文本变化"]
    H -->|内容更新| D
    H -->|关闭预览| G
```
