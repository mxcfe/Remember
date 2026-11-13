# 记得

Android 离线生活管理应用。支持待办、本地提醒、每日/每周/每月重复、物品数量和低库存、物品到期提醒，以及 JSON 备份和恢复。

数据保存在设备本地。请在更换设备或卸载前通过右上角菜单导出备份；恢复会替换本机数据。提醒需要允许通知，Android 省电策略可能使通知延迟。物品到期提醒默认在指定提前天数的上午 9 点触发。重复待办完成后自动生成下一次；每月重复以系统日历规则为准。

## 开发和构建

需要 Flutter 3.50、JDK 21、Android SDK 36 和 NDK 28.2。运行 `flutter pub get`、`flutter test`、`flutter analyze`。为发布包提供签名环境变量 `REMEMBER_KEYSTORE`（密钥库路径）和 `REMEMBER_KEY_PASSWORD`（密钥库及密钥密码，别名为 `remember`），然后运行 `flutter build apk --release`。签名密钥与密码不应提交到仓库；请妥善备份密钥，以便后续版本能覆盖安装。

本项目不需要服务器或账号。首次创建提醒时会请求通知权限；重启设备后由 Android 接收器恢复计划中的通知。
