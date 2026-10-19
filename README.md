# 房源管家（iOS）

房产中介专用房源管理 App，SwiftUI + SwiftData，iOS 17+。

## 功能

- **登记房源**：房号、座号、房东、户型、价格、密码、备注；房号输入「2-」前缀自动识别为 2 座
- **照片 / 视频**：每套房源可存多张实拍照片和视频，列表卡片直接预览首图，详情页照片可点开大图、视频直接播放
- **分享到微信**：详情页一键分享，把「完整房源信息 + 实拍照片 + 视频」一起发到微信
- **搜索**：按房号 / 房东 / 户型 / 备注关键词搜索
- **分类检索**：按座号（1座 / 2座）、状态（待租 / 已租）、户型筛选
- **状态管理**：纯房源管理，状态只有「待租 / 已租」两档，手动切换；待租 = 可带看
- **统计**：首页顶部显示「目前已收录房源总计：1座 X 套 / 2座 Y 套」
- 数据存在本机（SwiftData + Documents 媒体目录），首次启动带 4 条示例房源，可随意删除

## 工程结构

```
房源管家-ipa/
├── HouseKeeper.xcodeproj/          # Xcode 工程
├── HouseKeeper/
│   ├── App.swift                   # 入口 + 数据存储初始化
│   ├── Models/House.swift          # 房源 / 媒体模型 + 分享文案
│   ├── Views/
│   │   ├── HouseListView.swift     # 首页列表 + 搜索 + 筛选 + 统计
│   │   ├── HouseDetailView.swift   # 详情 + 媒体画廊 + 分享 + 状态切换
│   │   ├── HouseEditView.swift     # 登记 / 编辑表单 + 照片视频上传
│   │   └── HouseComponents.swift   # 卡片 / 徽章 / 分享面板等组件
│   ├── Services/MediaStore.swift   # 照片视频文件存储
│   └── Assets.xcassets/            # 应用图标
└── .github/workflows/build.yml     # GitHub Actions 免签名构建 IPA
```

## 构建 IPA（GitHub Actions，免开发者账号）

Windows 电脑无法直接编译 iOS 应用，本工程配好了云端构建工作流：

1. 把整个 `房源管家-ipa` 文件夹推到本仓库 `main` 分支（推送含 `HouseKeeper/**` 的提交会自动触发构建）
2. 也可在仓库 Actions 页找到 **Build Unsigned IPA**，点 **Run workflow** 手动触发
3. 等几分钟，构建完成后在本次运行记录的 Artifacts 里下载 `unsigned-ipa-v1.0-b1`，解压得到 `房源管家1.0.ipa`
4. 在 iPhone 上安装免签名 IPA：可用爱思助手、AltStore 等侧载工具

改版本号：修改工程里 `MARKETING_VERSION`（当前 1.0），产出的 IPA 名会自动变成「房源管家1.x.ipa」。

## 说明

- 照片和视频保存在 App 沙盒内，删除房源会同时删除对应媒体文件
- 分享走 iOS 系统分享面板，微信在分享列表中即可选中；个别场景（如分享视频给微信）需微信支持对应文件类型
