# 给 AI 的“软件清单”提示词（可复用）

你们这个仓库的 app 数量多时，最有效的做法是：把“有哪些软件”固化成一份**可机器读取且可自动更新**的清单文件，然后每次对话只引用它（或粘贴精简版）。

本仓库已提供自动生成的清单：
- `docs/apps-catalog.min.md`：适合直接给 AI 作为上下文（短）
- `docs/apps-catalog.md`：更完整（表格）
- `docs/apps-catalog.json`：给脚本/工具用（结构化）

更新清单：
- `make apps-catalog`

## 直接可用的提示词模板

把下面这段放在每次对话的开头（按需替换“本次目标”）：

```
你在维护 iStoreOS 的 app-hub 仓库。
请先阅读并记住仓库已有软件清单：docs/apps-catalog.min.md（必要时再看 docs/apps-catalog.md）。
后续我提到软件时，会用清单里的 id（例如 airconnect、ddnsto）。

本次目标：<在这里描述你要 AI 做什么>

要求：
1) 不要发明不存在的 app id
2) 如果不确定清单是否最新，先提醒我运行：make apps-catalog
```

