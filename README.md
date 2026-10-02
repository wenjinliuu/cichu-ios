# 此处 · Here

**看见时间，留在哪里。**

一款以地点与时间为核心的 iOS 生活日志。SwiftUI + MapKit + Core Location + SwiftData，本地优先，无需账号。

- 今日停留、移动和时间轴
- 常用地点地图、自动识别与手动补记
- 周／月／年回顾、地点记忆与地图回看
- 图标同源橙色主题、暖白／暖黑界面、克制动效
- JSON 备份和独立示例体验
- 地点识别防抖、异常记录核对、停留拆分与合并
- 分步权限向导、默认隐藏地点名称的图片分享海报

## 开发与验证

原生 SwiftUI + MapKit + Core Location + SwiftData，本地记录，无账号。1.1 完善前台即时定位、常用地点围栏与访问地点停留记录，浅色采用白底橙色主视觉。

工作流已接入 [ios-ci-workflows v1.1.0](https://github.com/wenjinliuu/ios-ci-workflows/releases/tag/v1.1.0)：Build & Test、TestFlight、App Icon Preview、Live Preview。统一配置见 `.ios-ci.yml`；测试、快照和签名均在 GitHub Actions 上执行。

最新整改与未实现路线见 [1.1 整顿报告](docs/REBUILD_20261002.md)。旧 [实现记录](docs/IMPLEMENTATION.md) 是历史交付说明，不能代替当前 CI 结果。锁屏、全天后台停留和升级数据保留，需要 TestFlight 真机验收。

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

界面设计规范、动效参数与静态检查边界见 [DESIGN.md](DESIGN.md)。

