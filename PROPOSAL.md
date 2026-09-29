# MoonTouchstone——MoonBit RF 网络数据变换与采样频段判定

本地模块 `guolei-dev/touchstone@0.2.1`，拟替换因与 `wbgxiaosu/xiangqi` 功能冲突而停用的象棋选题。公开仓库：https://github.com/guolei-dev/moonbit-touchstone。 本地交付版 0.2.1 仅补全已存在公开仓库的包元数据地址，算法未改；尚未推送或发布，公开版仍为 0.2.0。

## RF 数据任务与 MoonBit 实现

测量文件中的参数表示、端口顺序、参考阻抗和频段覆盖会改变计算结果。项目提供纯 MoonBit 网络数据模型、复数矩阵变换、二端口级联/去嵌入及采样频段限值、峰峰插损判定，让 MoonBit 应用在不部署 Python 服务的情况下组合这些基础能力。输入歧义、奇异运算和无法覆盖的频段明确拒绝或报告无法判定。

## 与已有工具的关系

scikit-rf 和 Rust Touchstone 库已有成熟 RF 能力，本项目不主张算法原创或生态空白。MoonBit 增量是同一网络模型上的可调用变换、采样频段判定和明确拒绝语义；宿主只做文件 I/O。关键词检索未找到直接同范围 Mooncakes 包，不代表其他实现不存在；完整 RF 分析、仪器控制和测量认证应使用专业工具。

## 公开测量记录与独立核对

Johanson 5500BP41A0665 的公开输入含 1551 个频点；与 scikit-rf/NumPy 独立比较 6204 个复数值、六组限值和通带波动。原始频点定位、零幅度、无采样和覆盖边界另有针对性检查。来源、复现命令和限制见 [PUBLIC-SAMPLE](docs/PUBLIC-SAMPLE.md)。这验证实际公开数据处理任务，不代表客户采用或厂商认证。

本地支持 JS/Wasm-GC 核心，1–32 端口、正实参考阻抗和有界文件；不承诺完整连续频带、复杂参考阻抗、所有扩展或完整 RF 仿真。当前已实现版本 0.2.0，源代码、接口和本地回执可独立审阅。公开仓库、已有提交的成功 CI 与 Mooncakes 0.2.0 已核实，换题提交及赛事批准尚未核实。

**公开状态（2026-09-29 核对）**：GitHub [公开仓库](https://github.com/guolei-dev/moonbit-touchstone)、[Mooncakes 0.2.0](https://mooncakes.io/docs/guolei-dev/touchstone@0.2.0) 已可访问；[CI 成功记录](https://github.com/guolei-dev/moonbit-touchstone/actions/runs/36561975947) 对应 `3723fef1db29`。本次材料更新尚未推送；该远端 CI 对应所列公开提交。报名表一致性及赛事审核结果尚未核实。
