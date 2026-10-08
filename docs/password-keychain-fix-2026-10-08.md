# 密码存储与解锁修复（2026-10-08）

## 行为变化

- 密码哈希和盐以一个带版本字节的 Keychain 条目存储：`app.password.credential.v1`。
- 更新已有条目使用 `SecItemUpdate`，只有不存在时才添加；不再先删除旧凭据。
- 旧的 `app.password.hash` / `app.password.salt` 在正确密码验证成功后迁移。迁移失败时仍可用旧密码登录，下次再试；新条目存在时不再接受过期的旧副本。
- 密码存储读取只把 `errSecItemNotFound` 视为缺失；权限、暂不可用和损坏错误向认证界面传播，不消耗错误密码次数。
- 已启用密码保护时，启动始终保持锁定；凭据缺失或暂不可读不能自动关闭密码保护。
- 十种语言的既有密码存储错误提示同时覆盖读取与写入失败。

未修改媒体主密钥、文件加密格式、Bundle ID、签名权限和应用版本号。不会通过重新生成媒体密钥或清空数据处理认证故障。

## 变更文件

- `zeroNetRedact/zeroNetRedact/BusinessLogic/Security/PasswordManager.swift`
- `zeroNetRedact/zeroNetRedact/Models/AppState.swift`
- `zeroNetRedact/zeroNetRedact/ViewModels/AuthenticationViewModel.swift`
- `zeroNetRedact/zeroNetRedactTests/PasswordManagerTests.swift`
- `zeroNetRedact/zeroNetRedact/{en,zh-Hans,zh-Hant,ja,de,fr,es,pt-BR,pl,id}.lproj/Localizable.strings`
- `.omc/state/tdd-workflow-state.json`：TDD 执行状态。

## 验证

修复前的密码回归测试执行了 12 项，有 19 个失败断言（含 2 项意外抛错），覆盖写入失败破坏旧密码、旧数据迁移缺失、读取错误被隐藏、存储故障消耗登录次数等问题。

修复后在独立 iPhone 17 / iOS 26.5 模拟器执行最终 Release 测试：32 项通过，0 失败。其中 14 项密码测试、15 项 CryptoEngine 测试、3 项本地化覆盖测试。

密码测试包括正常密码验证与修改、更新失败保留旧密码、首次写入失败无部分凭据、旧密码兼容迁移与失败重试、损坏凭据拒绝回退、旧副本清理失败不影响新密码、读取失败不增加次数、启动保持锁定，以及真实模拟器 Keychain 上的保存/重新创建管理器/修改密码验证。模拟故障使用独立内存存储；真实 Keychain 集成测试使用 UUID service，均不操作正常应用的密码条目。

```sh
xcodebuild test -project zeroNetRedact/zeroNetRedact.xcodeproj -scheme zeroNetRedact -configuration Release -destination 'platform=iOS Simulator,id=D17DB1A8-42CF-46FF-B27B-5E81C657644C' -derivedDataPath /tmp/redact-password-fix -only-testing:zeroNetRedactTests/PasswordManagerTests -only-testing:zeroNetRedactTests/CryptoEngineTests -only-testing:zeroNetRedactTests/LocalizationCoverageTests ENABLE_TESTABILITY=YES -parallel-testing-enabled NO
plutil -lint zeroNetRedact/zeroNetRedact/*.lproj/Localizable.strings
git diff --check
```

日志：`/tmp/redact-password-before.log`、`/tmp/redact-password-release.log`、`/tmp/redact-password-final.log`。最终日志和 xcresult 保留于 `/tmp/redact-password-fix`。独立测试模拟器在完成后清理，重跑时需使用新的可用模拟器 ID。

第一次修复后测试因原模拟器启动 Busy/preflight 错误未执行用例，记录于 `/tmp/redact-password-after.log`；不计作功能测试结果。换独立模拟器后 Release 测试通过。Release 构建脚本产生的构建号递增已恢复，未改动用户原有 Xcode 界面状态。

## 真机验收范围

尚未安装至真实设备，未完成 App Store/TestFlight 升级验收，也未上传或发布。发行包应从旧版本升级，使用原密码解锁、查看已有内容，再修改密码并重启验证。已被旧版本写入故障破坏或丢失的凭据无法凭空重建；本次防止新的损坏并保持锁定，不承诺恢复已经损坏的密码记录。
