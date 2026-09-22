# 频段采样点分析与限值检查

用途：对 Touchstone 文件配置多条频段要求，输出可以定位回原始频率矩阵的超限点、极值和计数。实现、规则解析、数值计算和 CSV 格式化均在 MoonBit；Node 仅负责文件、参数和退出码映射。无需 Python/scikit-rf 运行库。

## 可直接运行

```sh
moon build --target js --release
node tools/touchstone.mjs band-check examples/attenuator.s2p @examples/band-limits.json
node tools/touchstone.mjs band-csv examples/attenuator.s2p @examples/band-limits.json
moon run examples/band_check --target js
moon run examples/band_check --target wasm-gc
```

文件示例三条规则均通过。纯 MoonBit 示例故意让回波损耗规则超限，显示原始频点 1、2 的失败明细。文件命令可加第四个参数保存结果；已存在文件拒绝覆盖。带空格的参数文件路径可写为 `'@path with spaces/options.json'`。

## 公共接口

```moonbit
let rule = @touchstone.band_limit(
  InsertionLossDb, 100.0e6, 300.0e6,
  input=0, output=1, minimum=6.0, maximum=6.1,
)
let report = net.check_bands([rule], max_details=256)
let json = report.to_json().stringify()
let csv = report.issues_csv()
```

构造规则和检查可抛错；完整可执行调用见 `examples/band_check/main.mbt`。`BandLimit` 构造后只读，外部无法绕过构造器写入非法边界。`Network::check_bands` 不修改网络、频率或参考阻抗。

| 枚举 / JSON metric | 量与方向 | 单位 |
|---|---|---|
| ReflectionMagnitude / reflection_magnitude | `abs(S[input,input])` | 无量纲 |
| TransmissionMagnitude / transmission_magnitude | `abs(S[output,input])` | 无量纲 |
| ReturnLossDb / return_loss_db | `-20 log10(abs(S[input,input]))` | dB |
| InsertionLossDb / insertion_loss_db | `-20 log10(abs(S[output,input]))` | dB |
| Vswr / vswr | `(1+r)/(1-r)`，r 为输入反射幅度 | 无量纲 |

端口均为零起点，`input`/`output` 必填；反射类指标不使用 output 的矩阵行，但仍校验该端口存在。其他端口按其正实参考阻抗匹配。非 S 数据整体转换为 S 一次，沿用原参考，不自动重归一化；任何频点奇异转换使整个操作报错。

损耗符号是 S 参数幅度 dB 的负数，与 [scikit-rf 的幅度 dB 定义](https://scikit-rf.readthedocs.io/en/latest/_modules/skrf/mathFunctions.html#magnitude_2_db) 对应。它不是任意失配系统的换能功率增益或设备认证。VSWR 使用 [scikit-rf S 矩阵 VSWR](https://scikit-rf.readthedocs.io/en/latest/api/generated/skrf.network.Network.s_vswr.html) 作数值参考，但 r>1 时本库显式标为未定义，不把代数负值当作物理驻波比。

## 必须理解的采样语义

- 频段为闭区间 `[start_hz,end_hz]`；上下限也包含等号。频率边界有限、非负且有序。单点区间允许。
- 至少一条有限 minimum/maximum；两个都有则 minimum≤maximum。没有隐藏容差，调用方应把允许误差计入限值。
- 只选原始采样点。没有插值、外推、重采样或连续频带保证。即使最左/右边界都有采样，也不证明两点之间满足要求。
- `range_covered` 表示数据集的首尾频率包住整个请求区间，不等于连续覆盖；`start_sampled` / `end_sampled` 仅说明边界是否恰好采到。
- `pass`：至少一个点，首尾范围覆盖请求区间，所有选中值有定义且都满足限值。
- `fail`：至少一个有定义的值超限，优先于其他问题。仍需查看 undefined_count 和 range_covered。
- `inconclusive`：未发现超限，但没有采样、范围覆盖不足或存在未定义值。
- 总判定先看是否任意规则 fail，再看是否任意规则 inconclusive，否则 pass。任何结果都带 `scope: sampled_points_only`。

## 无穷、未定义及定位

精确零幅度对应正无穷损耗；VSWR 在 r=1 时为正无穷，在 r>1 时未定义。正无穷满足任何有限下限，但违反任何有限上限；未定义不算通过，也不算已证实数值超限。

`BandObservation` 始终包含 `point`（原始零起点索引）、`frequency_hz`、`state`、`value`。finite 对应 JSON 数字；infinite/undefined 对应显式 null。不要把 null 当作零，也不要根据 CSV 空值推断状态。

`lowest`/`highest` 包含正无穷，不包含未定义值；没有有定义值时显式为 null。并列极值取最早原始频点。每条规则的 sample_count、failed_count、undefined_count 是完整计数，极值也遍历全部选中点。

`max_details` 是所有规则共享的预算（默认256，0..100000）；按规则顺序、频率顺序保留最早的问题点。达到预算后仍继续计算完整计数和极值，设置相应 `issues_truncated`。因此尾部更严重的失败可能不在 issues，但仍在最高/最低值中体现。不是“最严重 N 个”排序。

CSV 仅导出保留的问题点，不包含通过点和规则汇总；空 CSV 可能源自空频段、零预算或数据缺口，不能独立证明通过。正式脚本应以 JSON 的判定和截断字段为准。相邻问题行不能解释成连续违规区间。

## 输入及工作量边界

1..256 条规则；最多 2000000 次选中点/规则评估；同一频点被两条规则检查计两次。明细上限不限制计数。额度预检在 S 转换前进行。维持现有网络 1..32 端口、100000 频点、2000000 复数限制。数值溢出、非有限限值、非法方向、空规则数组、未知指标/规则字段和整数小数均报错。JSON 中无下限/上限时应省略输入字段，显式 null 不是数值限值。

群时延和完整矩阵无源性保留现有独立 API；本次不把相位展开/采样混叠问题藏在标量限值规则里。噪声/混合模文档沿用 `network_only()` 的拒绝策略，不自动忽略元数据。

## CLI 状态码

| 状态码 | 意义 |
|---|---|
| 0 | 正常采样点通过（或其他旧命令正常完成） |
| 3 | band-check / band-csv 有超限，报告已正常输出 |
| 4 | band-check / band-csv 无法判定，报告已正常输出 |
| 2 | 参数、数据、数值、文件 IO 或拒绝覆盖错误 |

输入端口、选择数组、预算为严格 Int32 整数，不能用 0.5 代替0。band 命令拒绝未知顶层参数，避免拼错后静默应用默认预算。

## 验证边界

`tools/verify-bands.py` 用 scikit-rf 写入/重读多端口 RI/MA/DB、1.0/2.1、S/Y/Z/H/G 数据，以 scikit-rf 数值属性和 NumPy 掩码/极值独立计算期望；逐层检查 JSON 类型及显式 null，不能让 `[number]` 广播伪装成 number。另测真实文件、退出码、CSV、配置文件、覆盖保护和错误参数。

固定种子合成数据不是实测 RF 数据集；本地性能测量包含解析和进程通信开销，不是算法纯耗时或跨库排名。两后端验证不是三操作系统远程 CI；发布和申报仍由团队完成。
