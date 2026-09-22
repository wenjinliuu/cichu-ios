# 此处 · Here

**看见时间，留在哪里。**

一款以地点与时间为核心的 iOS 生活日志。SwiftUI + MapKit + Core Location + SwiftData，本地优先，无需账号。

- 今日停留、移动和时间轴
- 常用地点地图、自动识别与手动补记
- 周／月／年回顾、地点记忆与地图回看
- 深浅色主题、JSON 备份和独立示例体验

## 源码状态

已提供首版应用源码与 `Cichu.xcodeproj`。**尚未编译、签名或经过真机验证。** 当前不含自动构建工作流。

直接打开 `Cichu.xcodeproj`，选择 `Cichu` scheme。后续编译、权限与签名注意事项见 [实现与交接说明](docs/IMPLEMENTATION.md)。

```text
Cichu/App        应用入口与导航
Cichu/Models     地点、时间记录与时间计算
Cichu/Services   持久化、定位、备份、示例数据
Cichu/Features   今日、地点、回顾、设置与编辑页面
Cichu/Design     视觉组件与主题
CichuTests      数据与时间边界测试（未运行）
```



## 源码许可

© 2026 Wenjin Liu. All rights reserved.

本项目采用 **PolyForm Noncommercial License 1.0.0**。源码可用于个人学习、研究、实验和其他非商业用途；商业使用不在该许可授权范围内。官方商业发行权由版权所有者保留。

项目名称、App 名称、Logo、图标及品牌资产不因源码许可而获得复用授权。完整许可条款见 [LICENSE](LICENSE)，版权与品牌声明见 [NOTICE](NOTICE)。
