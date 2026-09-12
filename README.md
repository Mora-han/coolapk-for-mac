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

代码按职责拆成两个可独立复用的本地 Swift 包 + 一个 App 层：

```
Packages/
  CoolapkKit/          酷安接口工具包（不依赖任何 UI，可直接给别的项目用）
    CoolapkClient      签名请求、token 缓存、失败重试、multipart 上传
    CoolapkToken       X-App-Token v2 生成（Android UA 要求）
    Bcrypt / BlowfishTables   纯 Swift bcrypt 实现，无第三方依赖
    JSON               容错 JSON 包装
    API                全部接口封装
    Models             数据模型
    FeedHTML           酷安 HTML 转 NSAttributedString（表情、话题、链接）
    RichTextView       NSTextView 富文本视图
    EmojiStore         本地表情资源

  LiquidGlassUI/       Liquid Glass 设计系统（与业务无关，可复用）
    Theme              配色、尺寸、格式化工具
    Glass              玻璃面板、胶囊 Tab、玻璃按钮等组件
    RemoteImage        远程图片（内存 + 磁盘缓存、降采样）、自适应比例单图
    ImageViewer        图片查看器（缩放、拖拽、缩略图、存储、复制）
    ImageLoader        图片缓存实现
    CommonViews        计数、标签、空状态、加载、错误条

CoolapkForMac/         应用层
  App/           应用入口、三栏主界面（NavigationSplitView）、AppStore
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

两个包可以单独使用：

```swift
import CoolapkKit      // 只要接口能力
import LiquidGlassUI   // 只要界面组件
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
