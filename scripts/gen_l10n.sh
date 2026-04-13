#!/bin/bash
set -e

echo "==> 合并模块化 ARB..."
dart run tool/merge_l10n.dart

echo "==> 生成本地化代码..."
flutter gen-l10n

echo "==> 完成"
