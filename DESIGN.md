# Stats 电源控制设计

## 功能语义

Stats 提供两个独立的电源开关：

- `Prevent sleep on lid close` 通过特权 helper 设置 `pmset disablesleep`，实现真实的合盖不睡眠。
- `Keep screen awake` 通过受支持的 `PreventUserIdleDisplaySleep` 进程级断言阻止屏幕因空闲关闭。

`PreventSystemSleep` 已被 macOS SDK 标记为不受支持，不得用于实现或验证合盖不睡眠。

## 状态所有权

- `PowerController` 是应用侧唯一入口，负责用户期望状态、屏幕断言和 UI 结果。
- `SMCHelper` 负责 helper 注册、升级和 XPC 通信，不直接解释电源业务状态。
- helper 内的 `PowerSettings` 是 `SleepDisabled` 的唯一写入者。
- 设置页、组合弹窗和电池弹窗只调用 `PowerController`，不得直接写 Store、调用 `pmset` 或创建合盖相关断言。

两个 UI 状态分别存储在 `lid_no_sleep_state` 和 `keep_screen_awake_state`。合盖状态只有在 helper 完成写入、读回验证或原值恢复后才更新；helper 返回的是操作成功与否，不把恢复后的系统原值当作开关状态。失败时 UI 恢复到先前状态。

## 合盖控制生命周期

开启合盖不睡眠时，helper 按以下顺序执行：

1. 从 `IOPMrootDomain` 读取当前 `SleepDisabled`。
2. 将原值原子写入 `/Library/Application Support/Stats/power-session.json`。
3. 通过固定路径 `/usr/bin/pmset` 写入 `disablesleep 1`。
4. 再次读取 `IOPMrootDomain`，只在实际值为 `true` 时报告成功。

关闭开关时，helper 恢复日志中的原值，验证成功后删除日志。以下路径也执行相同恢复：

- Stats 正常退出或 XPC 连接失效。
- helper 异常退出后被 launchd 再次启动。
- helper 卸载。

因此 Stats 不会把 `SleepDisabled=1` 永久遗留给系统，也不会覆盖开启功能前由其他软件设置的原值。若 helper 意外重启而用户期望状态仍为开启，应用会在系统原值恢复后重新连接并重新申请。

启用失败时，helper 立即尝试恢复原值。只有恢复值读回验证成功才删除日志；若恢复也失败，日志必须保留，供 helper 下次启动继续恢复。

## Helper 可用性

合盖功能复用 Stats 已有的 `eu.exelban.Stats.SMC.Helper`，不增加第二套守护进程或 AppleScript 回退。

helper 只接受代码签名证书与自身一致、证书链非空且签名标识为 `eu.exelban.Stats` 的 XPC 客户端。临时签名不能通过特权接口校验。

- helper 已启用：直接执行并验证。
- helper 未注册：通过 `SMAppService` 注册。
- macOS 要求批准后台项目：开关回滚，提示用户打开“登录项”设置；批准后重新开启。
- 安装、XPC 或系统写入失败：开关回滚并显示错误，不写入期望状态。

Stats 启动时先完成 helper 版本对账，再恢复电源状态，避免 helper 升级与状态恢复并发。

## 旧版本迁移

提交 `f70bdce` 之前的本地开发版本曾直接持久写入：

```bash
pmset -a disablesleep 1
pmset -a displaysleep 0
```

运行过该版本的机器需要一次性清理：

```bash
sudo pmset -a disablesleep 0 displaysleep 10
```

旧实现没有保存此前的屏幕超时时间，所以 10 分钟只是其约定回退值。该清理不放进运行时代码，避免覆盖用户之后设置的有效配置。

## 验证要求

- 单元测试覆盖屏幕断言创建和释放。
- 单元测试覆盖合盖控制的原值恢复、原值为开启、异常重启恢复、失败回滚和回滚失败时保留日志。
- 集成验证必须确认开启时 `SleepDisabled=1`、关闭或退出 Stats 后恢复原值。
- 任何“断言创建成功”都不能作为合盖不睡眠的效果证据。
