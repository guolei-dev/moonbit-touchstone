# 公开 RF 文件：可复现的频段检查

对象是 Johanson Technology 的 [5500BP41A0665001E 产品](https://www.johansontechnology.com/products/integrated-passives/band-pass-filters/5500bp41a0665001e/)，旧料号 5500BP41A0665。这个任务展示从厂商测量数据取出频段、端口和极值，保存原始频点定位，以便 MoonBit 工具逐点复查。它不是客户案例，也不声称替代 scikit-rf 的完整 RF 工作流。

## 输入与参考

- [厂家 S2P](https://www.johansontechnology.com/docs/1886/5500BP41A0665_sT2aflU.s2p)，201833 字节；SHA-256 `404804182b54e3c37d4438b9b685ddb16d264768c8f1368ddd14f494d55310e6`。
- 头标注 2020-02-12、Agilent E5071C，Hz / S / dB / 50 ohm；文件中的逻辑端口 0、1 对应仪器物理端口 1、4，不能误认为仪器端口 1、2。
- [数据表 Rev 2.0](https://www.johansontechnology.com/docs/4622/BandPassFilter-5500BP41A0665001E.pdf)，copyright 2025。采用通带 5170–5835 MHz、插损上限 2.5 dB、回损下限 9.5 dB、波动上限 2.0 dB及三个阻带下限作演示；不把典型值用作保证值。
- 数据表与样本日期不同。数据表区分典型温度和跨温度界限，并采用指定评估板。单个文件不能证明量产、温度或完整评估条件符合。

原始厂家文件和 PDF 没有附入本项目，也没有被重新许可为 MIT。公开链接的可读取性不等于再分发许可。

## 重现

```sh
moon build --target js --release
python -m pip install -r tools/requirements.txt
python tools/fetch-johanson.py sample.s2p
python tools/verify-johanson.py sample.s2p --evidence johanson-result.json
node tools/touchstone.mjs ripple-check sample.s2p '{"start_hz":5170000000,"end_hz":5835000000,"input":0,"output":1,"maximum_ripple_db":2.0}'
```

下载器拒绝覆盖和哈希改变；上游换文件后应复核来源，不能静默改 golden。验证器先由 scikit-rf 独立读取所有频率、阻抗及复数值，再由 NumPy 计算选择掩码、指标极值和违规计数。它调用实际编译的 MoonBit 文件桥接；Python 不参与库运行。

## 已观察结果（2026-09-27 本地）

1,551 频点、6,204 复数值；对 scikit-rf 2.1.0 的最大复数绝对差约 8.89e-16。六组频段采样点检查均通过，通带采样的峰峰插损差为 0.8444743 dB。完整事实回执见 [johanson.json](../evidence/reassessment-20260927/johanson.json)。

5835 MHz 没有原始采样，报告 `end_sampled=false`。本工具只检查离散样本，不插值边界，不将范围包围误写为每个频率都测过。通过是文件中已采样点对该规则的结果，不是器件认证。

## 核心增量

`Network::check_ripple` 在 MoonBit 中计算峰峰插损，返回原始极值点和三态结论。绝对插损逐点合格并不保证波动合格；不能将两者替换。至少需要两个样本；覆盖不足不会通过；观察到违规仍失败。有限传输与精确零混合得到无限波动并失败，全零传输的无穷减无穷未定义，不能报告“0 dB、完美平坦”。

这些语义不绑定 Johanson 型号。CLI `ripple-check` 对未知参数、错误类型和非整数端口拒绝，退出 0/3/4 分别为通过/失败/无法判定，输入错误为 2。独立合成对照及坏输入用例见 `tools/verify-ripple.py`。
