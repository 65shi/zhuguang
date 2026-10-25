# 参与逐光

欢迎提交复现清楚的兼容性反馈和范围明确的改进。请先阅读 [README](README.md)、[安全说明](SECURITY.md) 与 [免责声明](DISCLAIMER.md)。

## 本地开发

需要 macOS、Swift 5.9 或更新版本和 Apple Xcode Command Line Tools：

```bash
bash scripts/test.sh
bash scripts/build-app.sh --dmg
```

测试脚本验证生产代码中的增益限值和暂停策略，并编译应用。实机自检需在兼容内置显示屏上手动运行，先退出其他逐光实例和增亮工具：

```bash
dist/逐光.app/Contents/MacOS/Zhuguang --diagnose
dist/逐光.app/Contents/MacOS/Zhuguang --self-test
```

`--self-test` 会短时开启 1.10× 增强，再自动关闭；它不是无副作用的编译检查。CI 不执行此命令。

## 提交改动

1. 说明具体问题、触发条件和改动后的行为。
2. 保持修改范围集中，运行 `scripts/test.sh` 和必要的构建验证。
3. 涉及显示、窗口或退出机制时，记录实际测试机型、系统、结果和未验证范围。截图不能证明物理亮度增益。
4. 保留默认关闭、实时增益限制、温度/休眠暂停、鼠标穿透和退出清理等保护行为。
5. 不要提交密码、令牌、个人路径、序列号、硬件 UUID、私有截图、`.build/` 或 `dist/`。安装包应作为 Release 附件分发。

若引入第三方代码，请先确认许可兼容并补齐归属和许可文本。现有 MaxNits MIT 归属必须保留；不要直接复制不兼容许可的代码。

## 问题反馈

请使用 Bug Report 模板，附逐光版本、机型、系统版本、复现步骤和脱敏后的诊断输出。安全漏洞请按 [SECURITY.md](SECURITY.md) 处理，不公开敏感数据或利用细节。
