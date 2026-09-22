# MoonTouchstone

评审/首次使用请先看[实际任务、替代方案与可运行证据](REVIEW.md)：导入Touchstone，按适用条件进行阻抗变换、级联或去嵌入，再对指定频段的采样点计算插损、回损等指标，输出超限位置或无法判定的原因。

MoonBit 原生 Touchstone 文件库与小规模 RF 网络数据工具。格式解析、SI 归一化、复数矩阵、参数转换和 RF 分析全部由 MoonBit 实现；Node 仅承担 CLI 文件读写和参数传递。MIT 许可，AI 辅助开发，保留真实 Git 作者与开发过程。

`localreview/touchstone` 是**本地开发命名空间，尚未发布**。本地完成不等于远程 CI 或正式比赛验收通过。固定开发范围见 [SCOPE](docs/SCOPE.md)，验证记录见 [TESTING](docs/TESTING.md)。

## 已有能力

- Touchstone 1.0/1.1/2.0/2.1：RI/MA/DB，Hz/kHz/MHz/GHz，逐端口正实参考阻抗，二端口两种顺序，多行数据，全矩阵/上下三角。
- 旧版 Y/Z/H/G 归一化转为物理 SI；2.x 非 S 参数本来就是物理量，不能再乘参考电阻。
- 噪声参数、独立噪声参考电阻、混合模端口描述和信息段保存。规范化写出 2.1；普通网络可写 1.0/1.1。
- S/Y/Z/H/G 转换（H/G 限二端口），重归一化，端口选择，复平面线性插值，二端口级联和双夹具去嵌入。
- 互易误差、完整矩阵无源性诊断、群时延、回波损耗、插入损耗和 VSWR。
- 多频段采样点限值检查：逐规则判定、原始频点定位、极值、全量计数、限额明细和 CSV；没有采样或覆盖不足不会假通过。
- 输入严格检查；不隐式丢弃噪声/混合模元数据；现有输出文件不会被 CLI 覆盖。

## 本地运行

需要 MoonBit 工具链和 Node.js 24。已实跑 Windows、moon 0.1.20260920 / moonc 0.10.14，JS 与 Wasm-GC；其余系统的 CI 仅配置，尚未远程执行。库本身不依赖 Python 或 scikit-rf。

```sh
moon check --target all
moon test --target js
moon test --target wasm-gc
moon build --target js --release
node tools/touchstone.mjs inspect examples/attenuator.s2p
node tools/touchstone.mjs metrics examples/attenuator.s2p '{"input":0,"output":1}'
node tools/touchstone.mjs delay examples/attenuator.s2p '{"input":0,"output":1}'
node tools/touchstone.mjs band-check examples/attenuator.s2p @examples/band-limits.json
moon run examples/band_check --target js
node tools/touchstone.mjs normalize examples/attenuator.s2p '{}' normalized.ts
node tools/touchstone.mjs convert examples/attenuator.s2p '{"parameter":"Z"}' impedance.ts
node tools/touchstone.mjs renormalize examples/attenuator.s2p '{"reference_ohms":[75,75]}' at75.ts
node tools/touchstone.mjs cascade examples/attenuator.s2p '{"right_file":"examples/attenuator.s2p"}' cascaded.ts
node tools/touchstone.mjs deembed cascaded.ts '{"left_file":"examples/attenuator.s2p","right_file":"examples/attenuator.s2p"}' recovered.ts
```

以上 JSON 单引号适用 PowerShell 7 / POSIX shell，Windows cmd 需要按该 shell 的规则转义引号。示例是匹配 6.0206 dB 衰减器及 1 ns 延迟，不依赖下载文件。两只级联再去掉两只夹具得到理想直通，不能要求其有限 Z 表示。

CLI 形式为 `COMMAND INPUT [OPTIONS-JSON] [OUTPUT]`，选项也可用 `@path/to/options.json`（ASCII、≤1 MB）。不指定输出则打印结果；报告为 JSON，转换为 Touchstone 文本。输入/IO 错误退出 2；`band-check` / `band-csv` 返回 0（采样点通过）、3（超限）、4（无法判定），会先写出报告再返回状态码。旧文件 `.sNp` 可推断端口数，其余旧格式文件需 `{"ports":N}`；2.x 若同时给出端口数必须与头一致。端口、选择下标、预算必须是精确整数，小数不会自动截断。全部命令见 `--help`。

| 命令 | 选项/行为 |
|---|---|
| inspect / validate / dump | 头、元数据 / 完整校验 / 原始逐点矩阵 |
| normalize / legacy | 保留元数据写 2.1 / 普通网络写旧格式，可选 `format`、`unit` |
| convert / renormalize | `parameter` / `reference_ohms` |
| select / interpolate | `selection` 零起点端口数组 / `frequency_hz` 递增目标频率 |
| cascade / deembed | `right_file` / `left_file` 和 `right_file` |
| diagnostics | 可选 `tolerance`，默认 1e-9 |
| metrics / delay | `input`、`output` 零起点端口 |
| band-check / band-csv | `limits` 规则数组；`max_details` 全局明细额度；[完整指南](docs/BANDS.md) |

`examples/band_check` 是不依赖 Node 文件宿主的纯 MoonBit 示例，可用 JS / Wasm-GC 运行。示例故意设置一条不通过的回波损耗要求，展示 JSON 与原始超限点 CSV；它正常执行并输出 `fail` 不代表测试失败。

## 公共 API 与数值约定

完整签名在 [pkg.generated.mbti](pkg.generated.mbti)。根包为纯 MoonBit，导入模块后可调用：

```moonbit
let doc = @touchstone.parse(text, ports=2)
let net = doc.network_only()
let s75 = net.renormalize([75.0, 75.0])
let output = @touchstone.document(s75).write()
```

这些函数可抛错，调用代码需处理错误。`network(ports, frequency_hz, values, reference_ohms, parameter="S")` 也可直接构造网络。每个矩阵按行存放，`row * ports + column`；`S[out,in]` 指定传输方向。频率 Hz，参考电阻 ohm，Z 为 ohm，Y 为 siemens；H/G 各分量单位不同。构造与查询都复制数组，不暴露内部可变别名。

转换通过 `A V = B I` 直接求解，避免把理想直通强行转成不存在的有限 Z。逆矩阵使用行尺度选主元；相对主元阈值 1e-12，奇异/不可靠或溢出时拒绝，不加任意扰动。端口选择将被删除端口接其匹配负载，不是开路删除。插值是当前表示的实虚部分段线性，禁止外推。级联必须频率网格与连接参考阻抗一致；传输链要求非零 S21，去嵌入还要求夹具可逆。

`diagnostics` 检查 `I-SᴴS`，返回 passive/active/boundary 容差带，不能只看各列功率或单个 S 元素。群时延采用相位展开和中心割线/端点单边差分，单位秒；两个相邻采样间真实相位变化超过 π 时无法唯一恢复。零传输的相位没有定义，会报错。

损耗的精确零幅度对应正无穷 dB，不伪造有限数值；JSON 省略该数值并设置 `*_infinite`。VSWR 对单位反射为 infinite，对幅度大于 1 为 active/未定义。普通缺失字段不能解释为 0。

## 明确边界

- 1–32 端口，最多 100000 频点、2000000 复数；输入/输出文本最大 64 MB，最多 1000000 行，单行 262144 字符，引用/模态头 4096 字符，信息段 1000000 字符。超限明确拒绝；这是数据限额，不是恒定进程内存承诺。
- 正实且随频率不变的参考阻抗；不支持复杂/频变参考阻抗、稀疏/二进制扩展。仅有限 double 数字；DB 不编码精确零，需 RI/MA。
- 保存混合模的**文件原始矩阵与单端参考电阻**，不假装完成单端/混合模变换。`network_only()` 对噪声或混合模拒绝，`raw_network()` 是有文档警示的显式低层访问。CLI 没有隐藏的“忽略元数据”开关。
- 信息段可保存，注释及原始排版不会保存；legacy 写出拒绝信息段以免静默丢弃。噪声仅二端口。分析不宣称全频因果性、完整 RF 仿真或实测设备认证。

## 验证与来源

```sh
moon fmt --check
moon info
node tools/check-cli.mjs
python -m pip install -r tools/requirements.txt
python tools/verify-reference.py
python tools/verify-bands.py
```

独立开发参考为 [IBIS Touchstone 2.1 规范](https://www.ibis.org/touchstone_ver2.1/touchstone_ver2_1.pdf) 和 [scikit-rf](https://scikit-rf.readthedocs.io/)。没有复制规范全文或把 Python 库包装成实现。详细独立检查、容差、工作量测量及源码散列见 [TESTING](docs/TESTING.md) 和 [reference.json](evidence/reference.json)。

验证工具许可证、参考范围和合成样例来源见 [SOURCES](docs/SOURCES.md)。

新频段功能的当前源码绑定记录见 [bands-20260922.json](evidence/bands-20260922.json)；原 `reference.json` 保留为增强前的历史证据，不能用其旧散列证明新源码。

查重刷新于 2026-09-22：Mooncakes `kw=touchstone` 与 GitHub `touchstone language:MoonBit` 均未命中，并检查公开网页索引；此结论限检索范围，不宣称全球不存在。
