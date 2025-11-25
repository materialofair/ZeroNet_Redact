#!/bin/bash

# TesseractOCR 自动安装脚本

set -e  # 遇到错误立即退出

echo "🚀 开始安装TesseractOCR..."

# 切换到项目目录
cd "/Users/WangQiao/Desktop/github/ios-dev/ZeroNet-Space/openSource/ZeroNet Redact/zeroNetRedact"

echo ""
echo "📦 第1步: 检查CocoaPods..."

if ! command -v pod &> /dev/null; then
    echo "⚠️  CocoaPods未安装，正在安装..."
    echo "   如果需要密码，请输入您的Mac密码"
    sudo gem install cocoapods
    echo "✅ CocoaPods安装完成"
else
    echo "✅ CocoaPods已安装: $(pod --version)"
fi

echo ""
echo "📦 第2步: 安装TesseractOCRiOS依赖..."

pod install --repo-update

echo "✅ Pod依赖安装完成"

echo ""
echo "📦 第3步: 创建语言包目录..."

mkdir -p zeroNetRedact/Resources/tessdata

echo "✅ 目录创建完成"

echo ""
echo "📦 第4步: 下载中文简体语言包 (约25MB)..."

curl -L --progress-bar \
     https://github.com/tesseract-ocr/tessdata/raw/main/chi_sim.traineddata \
     -o zeroNetRedact/Resources/tessdata/chi_sim.traineddata

echo "✅ 中文语言包下载完成"

echo ""
echo "📦 第5步: 下载英文语言包 (约5MB)..."

curl -L --progress-bar \
     https://github.com/tesseract-ocr/tessdata/raw/main/eng.traineddata \
     -o zeroNetRedact/Resources/tessdata/eng.traineddata

echo "✅ 英文语言包下载完成"

echo ""
echo "✅ 所有安装步骤完成！"
echo ""
echo "📋 接下来请手动完成："
echo "   1. 用 zeroNetRedact.xcworkspace 打开项目 (不是.xcodeproj!)"
echo "   2. 在Xcode中右键项目 → Add Files to \"zeroNetRedact\"..."
echo "   3. 选择 zeroNetRedact/Resources/tessdata/ 文件夹"
echo "   4. 勾选: ✅ Copy items ✅ Create folder references (蓝色图标)"
echo "   5. 点击 Add"
echo ""
echo "🎉 完成后即可编译运行！"
