# 工具链与独立参照验证

## 工具链固定版本更新（2026-09-28）

已将 .moonbit-version 更新为 0.10.14+7d59c7ec9。格式检查、全目标 check、JS/Wasm-GC 测试（各25项）、release JS 构建、moon info、生成接口差异检查、Node CLI检查（14项）及 band-check 示例均通过，示例在 JS 和 Wasm-GC 上各运行一次。此次仅复核工具链固定版本，未重跑 NumPy/SciPy/scikit-rf 独立参照测试；相关外部结果仍由下方 2026-09-27 回执单独证明。

## Prior verification details

### 先前 0.2.0 本地验证（2026-09-27）

Windows、moon 0.1.20260904 / moonc 0.10.12+1634b282e、Node 24.11.0。格式、接口、全部后端 check、release JS 构建通过；JS/Wasm-GC 各25块核心测试通过。新聚合逻辑复用频段选择和极值，故重跑受影响的 `verify-bands.py`：104场景、128检查、17 CLI检查通过；未无理由重跑原538场景矩阵对照。

`verify-ripple.py`：173个独立 NumPy/scikit-rf 合成场景、8种非法选项、4种 CLI 退出码通过。验证全零/混合零、反向端口、单点、无采样、越界范围、无限/未定义值；不是只比较自身往返。

`verify-johanson.py`：实际厂家公开 201833 字节 S2P 的1551频点、6204复数值及6组频段规则、通带波动与独立库比较通过。最大复数绝对差约8.89e-16；通带波动0.8444743 dB。来源日期不同、缺少5835MHz边界样本等限制保存在回执；不作产品合格认证。

回执位于 `evidence/reassessment-20260927/`。首次开发验证器运行因未给 scikit-rf 合成 Network 指定 name 而失败，修正验证器后上述173场景通过；没有掩盖该开发错误，也不是产品数值错误。新CI只固定Ubuntu配置，无远程通过声明；厂家下载不作为CI必需网络依赖。

## 频段增强后的当前验证（2026-09-22）

- 格式检查、接口生成、`moon check --target all --deny-warn`、release JS 构建通过。
- JS / Wasm-GC 各22个测试块：原16块加6块频段契约测试。覆盖闭区间、并列极值、原始编号、范围不足、无采样、正无穷、有源反射、共享预算、非S转换和工作量拒绝。
- `tools/verify-bands.py`：104组独立组合场景、128项检查、17项真实文件CLI检查。scikit-rf生成/重读和数值属性，NumPy独立选点/极值/违规集合；JSON递归类型检查防止省略null或Option数组混淆。
- 原 `tools/verify-reference.py` 在当前源码重新通过538组/1398项；原CLI14项通过，没有把历史结果冒充此次执行。
- 纯MoonBit组合示例在JS/Wasm-GC实际运行；其故意不通过的规则得到原始点1、2，对应两个CSV问题行。
- 新增基准为1000/10000点、5条规则、8个保留明细的解析+检查+JSON IPC，实测值见 `evidence/band-reference.json`；不含Python期望结果计算，不是纯算法或跨库速度排名。

当前总证据 `evidence/bands-20260922.json` 绑定全部非evidence Git源文件（文本CRLF统一为LF）及两份参考回执。
`evidence/band-baseline-reference.json` 是原验证器本次重跑的Windows原始字节散列；跨平台归档应以总证据的规范化源码散列为准。
`evidence/reference.json` 仍是增强前历史，不覆盖、不用于证明新源码。新回执普通脚本运行不覆盖，需显式 `--evidence PATH`。
CI新增频段独立对照与两后端示例；仅修改配置，未宣称远程CI已执行。正式发布/申报由团队负责，不是本地技术工作的前置阻点。

## 增强前基线记录（历史）

2026-09-22，Windows 11，Node 24.11.0，moon 0.1.20260920 / moonc 0.10.14：

- `moon fmt --check`、`moon check --target all`、`moon info`（生成公共接口）、release JS 构建。
- JS 与 Wasm-GC 各 16 组核心测试。不同后端不是不同操作系统的证明。
- `node tools/check-cli.mjs`：14 项，包括文件示例、已知 1 ns 延迟、级联、JSON 参数错误、非法端口、NUL/非 ASCII、拒绝覆盖且核对原文件字节。
- Python 3.14.4 / scikit-rf 2.1.0 / NumPy 2.5.3：538 场景、1398 项比较/拒绝检查。具体记录以 `evidence/reference.json` 为准；脚本/核心/接口文件 SHA-256 绑定此次运行。

## 独立性的具体含义

scikit-rf 生成 1/2/3/4/8 端口、三种表示、三种版本的文件，由 MoonBit 读入；MoonBit 规范化/转换结果再由 scikit-rf 读入。参数矩阵、重归一化、选端口、插值、群时延、损耗、VSWR、复杂非互易级联和去嵌入与 scikit-rf 数值结果比较。无源性另用 NumPy Hermitian 特征值作为独立参照，含单位酉矩阵、放大矩阵和边界。

上下三角按规范生成后交两个解析器分别读取，检查的是转置对称，而非共轭对称。混合模只检查保存后由 scikit-rf 解释的矩阵/有效参考一致，不把它列为 MoonBit 混合模转换通过。噪声三种版本检查 Fmin、Γopt、物理 Rn 与回读。200 个固定种子的非法数字变体只作为拒绝检查，不能说是 200 个独立科学数据集。

相对容差 3e-8、通常绝对容差 3e-10；群时延绝对容差 1e-18 秒。随机值是良态小规模网络；条件很差的 RF 系统不在此数值证据的覆盖范围。最大绝对差是跨不同单位比较的汇总计数，不是通用精度保证。

## 测量与交付边界

记录一个 2000 点、二端口的“解析 + 完整无源诊断 + JSON 进程通信”墙钟测量，含宿主开销。它是本机合成负载，不是其他库速度排名或实际仪器实时性保证。CI 配置包含 Windows/Linux/macOS，但远程未创建/执行，不能声称多系统 CI 绿。

重新运行 `python tools/verify-reference.py --evidence evidence/reference.json` 会更新证据；普通运行不改动已保存记录。不要只比较自身往返而宣称独立验证，不要用延时等待替代事件或同步进程结束。所有本地验证完成后再做公开仓库、发布和正式申报，这些不属于本次自动操作。
