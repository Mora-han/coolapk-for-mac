# Coolapk for Mac

原生 macOS 酷安第三方客户端，SwiftUI + Liquid Glass 编写，采用官方 App 的接口与数据结构。

## 运行

```bash
# 生成 Xcode 工程（修改 project.yml 或增删源码后执行）
xcodegen generate

# 构建
xcodebuild -project CoolapkForMac.xcodeproj -scheme CoolapkForMac -configuration Debug -destination 'platform=macOS' build

# 或者直接打开
open CoolapkForMac.xcodeproj
```

要求 macOS 26.0 以上（Liquid Glass API）。

## 目录结构

```
CoolapkForMac/
  App/           应用入口、三栏主界面（NavigationSplitView）
  Core/          网络与鉴权：CoolapkClient、CoolapkToken、Bcrypt、JSON、API、AppStore
  Models/        接口数据模型
  RichText/      HTML 转 NSAttributedString、NSTextView 富文本视图
  UI/            设计系统：配色、玻璃面板、远程图片、图片查看器
  Features/      按功能划分的页面
    Home/          首页信息流与各类卡片
    Detail/        动态详情与评论
    Profile/       用户主页
    Discover/      应用、话题、商品
    Search/        搜索
    Notifications/ 通知、私信、历史、收藏
    Social/        收藏夹、看看号、问答、投票、点赞的人
    Compose/       发布动态
    Login/         登录
    Settings/      设置
  Resources/Emoji/  官方表情包
```

## 登录

未登录即可浏览首页、详情、话题、应用与搜索。关注、收藏、评论等功能需要登录：
工具栏头像 → 登录，弹出酷安网页登录，登录成功后自动抓取 Cookie 与 token。

## 调试

设置环境变量可直接打开指定页面，便于截图和自动化：

```bash
COOLAPK_OPEN="dyh:1480"                     # 看看号
COOLAPK_OPEN="page:V9_HOME_TAB_RANKING"     # 指定 Tab
COOLAPK_OPEN_FEED=73714177                  # 直接打开一条动态详情
```

支持的前缀：feed、user、topic、product、app、collection、dyh、question、vote、page、path。

## 版本

见 [CHANGELOG.md](CHANGELOG.md)。每个功能一个 0.x.x 版本，对应一个 git tag，可随时回退。
