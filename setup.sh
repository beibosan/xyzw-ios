#!/bin/bash
# XYZW iOS 项目构建脚本
# 使用方法: chmod +x setup.sh && ./setup.sh

set -e

echo "╔══════════════════════════════════════╗"
echo "║   XYZW 游戏管理系统 iOS 构建脚本      ║"
echo "╚══════════════════════════════════════╝"
echo ""

# 1. 检查 Xcode
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ 未找到 Xcode，请先安装 Xcode"
    exit 1
fi
echo "✅ Xcode: $(xcodebuild -version | head -1)"

# 2. 安装/检查 XcodeGen
if ! command -v xcodegen &> /dev/null; then
    echo "📦 安装 XcodeGen..."
    brew install xcodegen
fi
echo "✅ XcodeGen: $(xcodegen --version)"

# 3. 生成 Xcode 项目
echo ""
echo "🔨 生成 Xcode 项目..."
cd "$(dirname "$0")"
xcodegen generate

echo ""
echo "╔══════════════════════════════════════╗"
echo "║  ✅ 项目生成完成！                    ║"
echo "║                                      ║"
echo "║  打开方式:                            ║"
echo "║  open XYZW.xcodeproj                 ║"
echo "║                                      ║"
echo "║  然后 ⌘R 运行即可                    ║"
echo "╚══════════════════════════════════════╝"

# 4. 自动打开项目
if [ -f "XYZW.xcodeproj" ]; then
    echo ""
    read -p "是否现在打开 Xcode? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        open XYZW.xcodeproj
    fi
fi
