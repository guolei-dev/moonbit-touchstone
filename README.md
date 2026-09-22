# MoonTouchstone

正在开发的 MoonBit 原生 Touchstone 网络文件与 RF 数据操作库。当前能力与未完成项见 `docs/PROGRESS.md`，承诺范围见 `docs/SCOPE.md`。`localreview/touchstone` 仅为本地命名空间，尚未发布。

核心约定：频率统一 Hz，参考电阻为正实数 ohm；矩阵行优先、端口下标从 0 开始；复数网络值和领域算法在 MoonBit，文件 IO 由薄 Node 层承担。

## 本地检查

```sh
moon check --target all
moon test --target js
moon test --target wasm-gc
moon fmt
moon info
```

不能用本地通过声明远程 CI、注册表发布或正式赛事验收通过。

## 来源

根据 IBIS Touchstone 2.1 规范独立实现，不复制其完整文本：
https://www.ibis.org/touchstone_ver2.1/touchstone_ver2_1.pdf

计划使用 scikit-rf/NumPy 作独立开发参考，不作为库运行时依赖。搜索刷新于 2026-09-22：Mooncakes `kw=touchstone` 及 GitHub `touchstone language:MoonBit` 均未命中；另检查公开网页索引。此结论限检索范围，不宣称全球不存在。

许可证 MIT。AI 辅助开发，保留真实 Git 署名和检查记录。
