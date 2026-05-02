# Sparkle 发布流程

PCL.Mac 已接入 Sparkle，客户端会优先走 Sparkle 更新；仅当 `SUFeedURL` 或 `SUPublicEDKey` 未配置时，才回退到旧的 `update.json` 全量更新链路。

## 当前客户端配置

- Appcast 地址：`https://update.gzitvs.cn/meta/PCL.Mac/appcast.xml`
- Sparkle 公钥：已写入 `Configs/Base.xcconfig`
- 默认更新通道：`stable`（`SPARKLE_CHANNEL` 留空即默认通道）

## 一次性准备

先确保跑过一次 Xcode 构建，让 Sparkle 的工具落到本机缓存目录里。

然后可以查看当前 Sparkle 公钥：

```bash
"$HOME/Library/Developer/Xcode/DerivedData/PCL.Mac-dlhwgbjhdpbbyxefezmtvujyakce/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys" --account "org.ceciliastudio.pclmac" -p
```

私钥会保存在当前用户钥匙串中，后续 `generate_appcast` / `sign_update` 会直接复用。

## 产出发布包

先准备签名后的更新归档（zip 或 dmg）。

推荐目录结构：

```text
dist/sparkle/
  PCL.Mac 1.0.2.zip
  PCL.Mac 1.0.2.html
  PCL.Mac 1.0.3.zip
  PCL.Mac 1.0.3.html
```

- `zip` / `dmg`：更新包
- 同名 `.html` / `.md` / `.txt`：发布说明

## 生成 appcast

最简单的生成方式：

```bash
DOWNLOAD_URL_PREFIX=https://update.gzitvs.cn/meta/PCL.Mac/updates/ zsh "scripts/publish-sparkle-feed.sh" "dist/sparkle"
```

生成后会得到：

- `dist/sparkle/appcast.xml`
- 可能生成的 `*.delta` 增量包
- `old_updates/`（旧版本归档）

## 灰度发布

Sparkle 用 `phased rollout` 做灰度。

例如按天放量：

```bash
DOWNLOAD_URL_PREFIX=https://update.gzitvs.cn/meta/PCL.Mac/updates/ PHASED_ROLLOUT_INTERVAL=86400 zsh "scripts/publish-sparkle-feed.sh" "dist/sparkle"
```

这会在新生成的条目里写入 `sparkle:phasedRolloutInterval`。

## Beta / 灰度通道

如果要给 Beta 用户单独推送：

```bash
DOWNLOAD_URL_PREFIX=https://update.gzitvs.cn/meta/PCL.Mac/beta/ CHANNEL=beta zsh "scripts/publish-sparkle-feed.sh" "dist/sparkle-beta"
```

客户端如果要接 Beta 通道，把 `Configs/Base.xcconfig` 里的：

```text
SPARKLE_CHANNEL = beta
```

留空则使用默认稳定通道。

## 增量更新

Sparkle 的 `generate_appcast` 会根据归档自动尝试生成 delta 包。

前提是：

- 旧版本和新版本都是 Sparkle 支持的归档格式
- 归档中 App Bundle 结构可被正常解析

如果 delta 生成成功，客户端会优先使用增量更新；失败时会自动回退到全量更新。

## 发布到线上

把以下文件上传到 `https://update.gzitvs.cn/meta/PCL.Mac/` 对应目录：

- `appcast.xml`
- 所有新归档
- 所有新生成的 `*.delta`
- 发布说明文件（如果 release notes URL 指向这些文件）

## 当前限制

- Sparkle 只负责应用更新，不替代 Apple 的 Developer ID 签名 / 公证流程
- 如果线上 `appcast.xml` 尚未部署，客户端仍会回退到旧更新链路
