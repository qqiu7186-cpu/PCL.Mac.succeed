# PCL.Mac 更新联调 Checklist

本文用于对齐 **PCL.Mac 当前客户端实现** 与 `https://update.gzitvs.cn` 的 **SparkleGrayAdmin 动态 Feed** 行为。

适用范围：

- 正式版 `stable`
- 测试版 `beta`
- 预灰度测试组 `beta-gray`
- 客户端 `beta` 的“双通道预评估后择优”逻辑

## 1. 联调前确认

客户端当前实现前提：

- 更新只走 Sparkle 动态 Feed，不再回退 `update.json`
- 动态 Feed 基址：`https://update.gzitvs.cn/api/v1/appcast/cn.gzitvs.PCL-Mac/`
- 请求参数包含：
  - `channel`
  - `current_build`
  - `user_id`
  - `macos_version`
- `user_id` 为安装级匿名 ID：
  - 首次生成
  - Keychain 持久化
  - 更新替换后保持不变
- `beta` 通道客户端逻辑：
  - 先分别评估 `beta-gray` 与 `beta`
  - 比较两个频道的可升级候选
  - 取版本更高的那个
  - 如果版本相同，偏向 `beta-gray`

服务端联调前建议确认：

- 已创建应用：`cn.gzitvs.PCL-Mac`
- 已存在可访问的动态 Appcast 接口
- 对 `stable` / `beta` / `beta-gray` 三个频道的版本准备明确
- 如果要测灰度规则，已准备对应白名单、百分比或系统版本规则
- 服务端可查看请求日志或更新命中日志

建议客户端准备：

- 一份当前 build 较低的测试包
- 一份当前 build 等于最新版本的测试包
- 可查看客户端日志的环境
- 可查看服务端请求日志的环境

## 2. 客户端请求观测点

每次联调都建议确认这些字段：

- 客户端最终请求的 `channel`
- `current_build` 是否等于客户端实际 `CFBundleVersion`
- `macos_version` 是否与当前系统一致
- `user_id` 是否在同一安装实例内保持稳定

建议记录：

- 客户端启动自动检查时的请求
- 手动点击“再次检查”时的请求
- 同一安装实例多次请求时的 `user_id`

## 3. 正式版 `stable`

### Case 3.1 `stable` 有可升级版本

服务端准备：

- `stable` 频道存在比客户端 `current_build` 更高的版本

客户端操作：

- 选择正式版通道
- 启动客户端或手动点击“再次检查”

期望结果：

- 客户端请求 `channel=stable`
- 能收到并展示新版本
- Sparkle 正常进入下载/安装流程

核对项：

- 服务端日志中 `channel=stable`
- `current_build` 与客户端构建号一致
- 不应访问 `beta` / `beta-gray`

### Case 3.2 `stable` 已是最新

服务端准备：

- `stable` 频道最新版本 `<= current_build`

客户端操作：

- 选择正式版通道
- 点击“再次检查”

期望结果：

- 客户端提示“当前使用的是最新版本，无需更新！”
- 不应出现下载流程

## 4. `beta-gray`

### Case 4.1 `beta-gray` 有可升级版本

服务端准备：

- `beta-gray` 存在更高版本

客户端操作：

- 选择 `beta-gray`
- 点击“再次检查”

期望结果：

- 客户端只请求 `channel=beta-gray`
- 能正确拿到 `beta-gray` 更新

### Case 4.2 `beta-gray` 已是最新

服务端准备：

- `beta-gray` 最新版本 `<= current_build`

客户端操作：

- 选择 `beta-gray`
- 点击“再次检查”

期望结果：

- 客户端提示已是最新
- 不应降级去请求 `beta`

## 5. `beta` 双通道择优

### Case 5.1 `beta-gray` 比 `beta` 旧，必须选 `beta`

服务端准备：

- `beta-gray` 最新可升级候选 = `101`
- `beta` 最新可升级候选 = `105`
- 客户端 `current_build = 100`

客户端操作：

- 选择 `beta`
- 点击“再次检查”

期望结果：

- 客户端会预评估 `beta-gray` 与 `beta`
- 最终正式 Sparkle 检查应走 `beta`
- 客户端应拿到 `105`

重点核对：

- 不能因为 `beta-gray` 也有更新就误选 `101`

### Case 5.2 `beta-gray` 比 `beta` 新，必须选 `beta-gray`

服务端准备：

- `beta-gray` 候选 = `105`
- `beta` 候选 = `101`
- 客户端 `current_build = 100`

客户端操作：

- 选择 `beta`
- 点击“再次检查”

期望结果：

- 最终正式检查走 `beta-gray`
- 客户端应拿到 `105`

### Case 5.3 `beta-gray` 与 `beta` 同版本，偏向 `beta-gray`

服务端准备：

- `beta-gray` 候选 = `105`
- `beta` 候选 = `105`
- 客户端 `current_build = 100`

客户端操作：

- 选择 `beta`
- 点击“再次检查”

期望结果：

- 最终正式检查走 `beta-gray`

### Case 5.4 `beta-gray` 请求失败，`beta` 正常

服务端准备：

- `beta-gray` 返回 5xx、超时或无效响应
- `beta` 返回正常可升级版本

客户端操作：

- 选择 `beta`
- 点击“再次检查”

期望结果：

- 客户端应降级使用 `beta`
- 不应因为 `beta-gray` 失败而整体更新失败

重点核对：

- 客户端日志应能看到 `beta-gray` 预评估失败
- 最终仍能走 `beta`

### Case 5.5 `beta` 请求失败，`beta-gray` 正常

服务端准备：

- `beta-gray` 有可升级版本
- `beta` 返回 5xx、超时或无效响应

客户端操作：

- 选择 `beta`
- 点击“再次检查”

期望结果：

- 客户端应仍可使用 `beta-gray`

### Case 5.6 两边都失败

服务端准备：

- `beta-gray` 与 `beta` 都不可用

客户端操作：

- 选择 `beta`
- 点击“再次检查”

期望结果：

- 客户端不给出错误版本更新结果
- Sparkle 正式检查应失败并提示错误

## 6. 版本门槛与系统门槛

### Case 6.1 `minimumUpdateVersion` 生效

服务端准备：

- 某候选版本设置 `minimumUpdateVersion > current_build`

客户端操作：

- 发起更新检查

期望结果：

- 客户端预评估阶段应忽略该候选
- 不应将其作为最终频道选择依据

### Case 6.2 `minimumSystemVersion` 生效

服务端准备：

- 某候选版本设置 `minimumSystemVersion` 高于当前系统

客户端操作：

- 发起更新检查

期望结果：

- 该候选不应被视为有效升级

### Case 6.3 `maximumSystemVersion` 生效

服务端准备：

- 某候选版本设置 `maximumSystemVersion` 低于当前系统

客户端操作：

- 发起更新检查

期望结果：

- 该候选不应被视为有效升级

### Case 6.4 同频道多个候选版本

服务端准备：

- 同一频道提供多个版本
- 其中一部分因系统门槛不满足被过滤

客户端操作：

- 发起更新检查

期望结果：

- 客户端应选择“最高且可升级”的那个候选

## 7. XML 变体兼容

### Case 7.1 `<sparkle:version>` 元素

服务端准备：

- 使用标准 `<sparkle:version>` 写法

期望结果：

- 客户端能正常识别候选版本

### Case 7.2 `<enclosure sparkle:version="...">` 属性写法

服务端准备：

- 用 `enclosure` 上的 `sparkle:version` 提供版本

期望结果：

- 客户端能正常识别候选版本

## 8. `user_id` 稳定性与匿名性

### Case 8.1 同一安装实例多次启动

客户端操作：

- 连续多次启动客户端并抓取更新请求

期望结果：

- `user_id` 保持不变

### Case 8.2 更新后保持不变

客户端操作：

- 记录更新前 `user_id`
- 执行一次客户端更新
- 更新后再次触发检查

期望结果：

- `user_id` 不变化

### Case 8.3 替换 app bundle 后保持不变

客户端操作：

- 记录 `user_id`
- 用新版 `.app` 替换旧版
- 再次检查更新

期望结果：

- `user_id` 不变化

### Case 8.4 卸载重装行为确认

客户端操作：

- 卸载 app
- 重装 app
- 再次触发更新检查

期望结果：

- 由于 Keychain 可能保留，`user_id` 可能保持不变

说明：

- 这不是 bug，而是当前实现的预期行为
- 请团队确认是否接受“卸载后重装仍保留同一匿名 ID”

## 9. 灰度规则联调

### Case 9.1 白名单灰度命中

服务端准备：

- 将当前 `user_id` 加入白名单

客户端操作：

- 发起更新检查

期望结果：

- 当前客户端命中新版本

### Case 9.2 白名单未命中

服务端准备：

- 将另一 `user_id` 放入白名单，当前客户端不在名单中

客户端操作：

- 发起更新检查

期望结果：

- 当前客户端不应误拿白名单版本

### Case 9.3 百分比灰度稳定性

客户端操作：

- 同一安装实例多次触发更新检查

期望结果：

- 同一 `user_id` 的命中结果应保持稳定

### Case 9.4 防降级

服务端准备：

- 让服务端目标版本 `<= current_build`

客户端操作：

- 发起更新检查

期望结果：

- 应返回无更新

## 10. 客户端与服务端结果一致性

### Case 10.1 预评估频道与正式 Sparkle 检查频道一致

客户端操作：

- 选择 `beta`
- 在 `beta-gray` 与 `beta` 都有候选的情况下发起检查

期望结果：

- 预评估选中的频道
- 与后续正式 Sparkle 请求频道一致

说明：

- 由于预评估与正式请求之间存在极小时间差，偶发不一致理论上可能存在
- 如果出现不一致，请同时记录：
  - 客户端预评估日志
  - 服务端返回
  - Sparkle 正式请求日志

## 11. 服务端可用性

由于客户端已经移除 `update.json` 回退，建议额外验证：

- Feed 服务正常时，更新全链路可用
- Feed 5xx 时，客户端报错明确
- Feed TLS/证书异常时，客户端报错明确
- 服务端监控、告警、回滚策略可用

## 12. 联调结果记录模板

建议每个 case 至少记录：

- Case 编号
- 客户端版本 / build
- 当前系统版本
- 当前频道
- 当前 `user_id`
- 服务端配置
- 实际请求 URL 参数
- 服务端返回结果
- 客户端实际行为
- 是否符合预期
- 备注 / 异常截图 / 日志位置
