# UI 审计 · 2026-09-22

范围：橙色极简版本的源码审计、定点修正、静态格式检查。未编译、未运行、未截图。下列“已修正”只表示代码已改；不代表实机视觉与交互验收通过。

## 结论与证据边界

源码结构符合原生应用方向：系统 TabView、NavigationStack、Form、sheet、SF Symbols；没有自绘全局导航和返回手势。品牌暖橙、暖白／暖黑 Token 与系统字体持续保留。当前最需要完善的是内容状态与自适应排版，而非增添装饰。

| 审计维度 | 源码发现及处理 | 仍需运行验证 |
| --- | --- | --- |
| 可访问性 | 关键横排新增辅助字体纵排；补记直接可见；图表读数标签；完整地图名称可读屏 | VoiceOver 顺序、焦点、最大字体实际折行 |
| 性能 | 保留局部动画、LazyVStack 记录列表；未引入动画依赖 | 大量历史记录的趋势聚合、60/120Hz 帧率；不能从源码打性能分 |
| 外观与主题 | 延续现有 Token；移动条移除低透明度；趋势使用完整主色 | 系统材料、增强对比度、地图底图在深浅色下的实际渲染 |
| 平台一致性 | 保留系统导航、安全区与抽屉；分享按钮放入 safeAreaInset | 抽屉拖动、系统分享、键盘与返回手势 |
| 自适应 | 共用 AdaptiveRow；大字体范围菜单、地图 large 抽屉、长名两行 | 375pt、小屏横屏、iPad 分屏 |

不提供 /20 总分：当前缺少运行证据，给“优秀”或“已完全达标”评分会产生误导。

## 确认问题与修改

| 等级 | 位置 | 源码证据与影响 | 处理 |
| --- | --- | --- | --- |
| P2 | SharePosterView | 图片为 nil 时无条件显示 ProgressView，渲染失败仍像正在加载 | 将加载、成功、失败分开；失败提供重试及文字分享 |
| P2 | TodayView / DayJournalView | 补记只在更多菜单；完整时间线没有空状态 | 记录区直接补记，完整页增加空状态与工具栏入口 |
| P2 | DaySummary / ReviewView | chartXSelection 存在但没有选择线，趋势缺少单位 | 选择线、读数、小时单位、标记读屏值；切换日期清空选择 |
| P2 | ReviewView | 趋势置于非空停留 totals 分支，移动记录无法展示 | 按全部记录时长判断趋势；桶时长裁剪到当前统计范围 |
| P2 | Theme / TodayView / ReviewView / RecordReviewView | 多组横排未针对辅助字体切换布局 | AdaptiveRow 基于字体大小切换 AnyLayout；撤销、明细、核对操作均接入 |
| P2 | PlacesView | 横向标签没有长文本边界；详情固定可用 medium | 标签两行、完整可访问性名称、选中语义；辅助字体只提供 large |
| P3 | SharePosterView | 主分享操作位于整张海报下方 | 固定底部主操作；隐私说明渐进展示，名称状态保留可见 |

没有从源码确认 P0 阻断。大字体的实际溢出程度尚未运行测量，相关修改属于预防性适配，不宣称已观察到设备截图错误。

## 保留的设计约束

- 橙色只强调操作和当前状态；分类色辅助数据识别。
- 开放式分区与轻分隔，保留首页单一主状态卡。
- 短促按压反馈与局部状态动画；Reduce Motion 取消缩放和位移。
- 海报为固定导出画布，字号不随辅助字体变化；界面本身继续支持 Dynamic Type。

## 下一次运行验收

1. 今日／回顾：375pt、横屏、最大辅助字体；长名称和超长时长不能遮挡操作。
2. 时间轴／趋势：拖动、抬手、滚动、切换日期后选择行为；辅助技术可以用列表完成修正与补记。
3. 地图：长名称、large 抽屉、系统权限被拒绝；定位失败提示仍值得后续完整验收。
4. 分享：真实海报渲染、重试、系统分享、最大字体底部操作；关闭名称后图片内容同步。
5. 深浅色、增强对比度、减少动态效果、VoiceOver 顺序和撤销提示可达性。

采用的技能工作流：Impeccable native audit → harden / adapt 原则 → polish；延续 Emil 与 SwiftUI UI patterns。依据用户既有自主修改授权，审计后直接完成已确认问题的修正，不额外停下来请求逐项批准。

参考：
- https://github.com/pbakaus/impeccable/blob/main/.agents/skills/impeccable/reference/audit.native.md
- https://github.com/pbakaus/impeccable/blob/main/.agents/skills/impeccable/reference/ios.md
- https://github.com/pbakaus/impeccable/blob/main/.agents/skills/impeccable/reference/harden.md
- https://github.com/emilkowalski/skills
- https://github.com/Dimillian/Skills
