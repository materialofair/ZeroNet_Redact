import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        NavigationView {
            List {
                // 存储信息
                Section {
                    HStack {
                        Text("已用存储")
                        Spacer()
                        Text(viewModel.usedStorageText)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("加密文件")
                        Spacer()
                        Text("\(viewModel.fileCount) 个")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("存储")
                }

                // 安全设置
                Section {
                    Toggle("自动锁定", isOn: $viewModel.autoLock)

                    if viewModel.autoLock {
                        Picker("锁定时间", selection: $viewModel.lockTimeout) {
                            Text("立即").tag(0)
                            Text("1分钟").tag(60)
                            Text("5分钟").tag(300)
                            Text("15分钟").tag(900)
                        }
                    }
                } header: {
                    Text("安全")
                }

                // 关于
                Section {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }

                    Link(destination: URL(string: "https://github.com/zeronet")!) {
                        HStack {
                            Text("GitHub")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("关于")
                }

                // 危险操作
                Section {
                    Button(
                        role: .destructive,
                        action: {
                            viewModel.showClearAllAlert = true
                        }
                    ) {
                        Text("清空所有文件")
                    }
                } header: {
                    Text("数据")
                }
            }
            .navigationTitle("设置")
            .alert("清空所有文件", isPresented: $viewModel.showClearAllAlert) {
                Button("取消", role: .cancel) {}
                Button("确认清空", role: .destructive) {
                    viewModel.clearAllFiles()
                }
            } message: {
                Text("此操作将永久删除所有加密文件,无法恢复")
            }
            .onAppear {
                viewModel.loadStorageInfo()
            }
        }
    }
}

#Preview {
    SettingsView()
}
