//
//  LaunchScreen.swift
//  zeroNetRedact
//
//  Created by WangQiao on 2025/11/24.
//

import SwiftUI

struct LaunchScreenView: View {
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // 启动页图片 - 强制宽度占满屏幕，高度自适应
                Image("LaunchScreen")
                    .resizable()
                    .scaledToFit()
                    .frame(width: geometry.size.width)

                // 底部背景色填充剩余空间
                Spacer()
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(Color(red: 208.0 / 255.0, green: 247.0 / 255.0, blue: 251.0 / 255.0))
        }
        .ignoresSafeArea()
    }
}

#Preview {
    LaunchScreenView()
}
