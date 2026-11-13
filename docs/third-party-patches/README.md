# 历史第三方修补

`details-secret-hover-20261106.patch` 是此前对第三方 Details 的最小修补 diff，原目标文件为 `Details/frames/window_main.lua`，解决 secret 值参与布尔/字符串控制流的问题。保留我们做过的修改，不收录完整第三方插件。

目标插件目前不在自研协作仓库中，不能将补丁直接应用到任意新版 Details。`PersonalAddons/tests/details_truncation_test.lua` 仍需匹配的原目标文件；新的自研检查入口明确排除此历史第三方测试。本次没有重新安装或验收 Details。
