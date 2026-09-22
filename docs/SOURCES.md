# 来源、验证工具与样例

本库自身采用根目录MIT LICENSE，格式和RF运算独立实现于MoonBit。
不是scikit-rf绑定，不包含其Python算法源码或上游示例数据集。

| 外部来源 | 角色 | 许可证或使用边界 |
|---|---|---|
| [IBIS Touchstone 2.1](https://www.ibis.org/touchstone_ver2.1/touchstone_ver2_1.pdf) | 文件布局、参数和元数据语义 | 链接规范，不重新分发规范全文 |
| [scikit-rf](https://github.com/scikit-rf/scikit-rf/blob/master/LICENSE.txt) | 2.1.0 独立网络与格式对照 | BSD-3-Clause |
| [NumPy](https://github.com/numpy/numpy/blob/main/LICENSE.txt) | 2.5.3 数组/复数矩阵参考 | BSD-3-Clause |
| [SciPy](https://github.com/scipy/scipy/blob/main/LICENSE.txt) | 1.18.1 参考验证环境 | BSD-3-Clause |

2026-09-22核对上游许可证文本；版本由tools/requirements.txt锁定。
这些Python库仅开发验证依赖，不进入MoonBit库/Node CLI运行路径，源码ZIP不包含其发行包。
表内是项目主许可证，不代表依赖二进制轮子的全部第三方组件许可；
若将来一并分发参考环境，应保留各发行包原有的完整许可与版权文件。

examples/attenuator.s2p及测试矩阵、噪声和频率数据由本项目合成；
验证脚本调用参考库产生/读取临时文件，无实测设备数据、私有设计或第三方下载样本。
evidence记录参考结果和源码散列，不表示上游或设备厂商认证。AI辅助事实保留。

频段示例及 band-limits.json 也是本项目合成数据/要求，不是实际产品的合格指标。
`tools/verify-bands.py` 复用独立 scikit-rf 数值属性与 NumPy 掩码，不导入本库计算结果作为真值；
VSWR 有源反射、采样不充分、明细截断和判定优先级为本项目明确制定的接口契约，见 docs/BANDS.md。
