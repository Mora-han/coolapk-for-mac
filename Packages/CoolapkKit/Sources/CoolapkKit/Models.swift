import Foundation

/// 把接口返回的图片地址统一成 https，并支持协议相对地址。
private func coolapkNormalizedURL(_ url: String) -> String {
    guard !url.isEmpty else { return url }
    if url.hasPrefix("http://") { return "https://" + url.dropFirst("http://".count) }
    if url.hasPrefix("//") { return "https:" + url }
    return url
}

// MARK: - Feed

/// One dynamic (动态) row. Coolapk returns loosely typed JSON, so every field is coerced.
public struct FeedItem: Identifiable, Hashable {
    public enum Kind: String {
        case feed
        case product
        case topic
        case question
        case dyh
        case unknown
    }

    public let id: String
    public var kind: Kind = .feed
    public var uid: String = ""
    public var username: String = ""
    public var avatar: String = ""
    public var message: String = ""
    public var messageTitle: String = ""
    public var deviceTitle: String = ""
    public var ipLocation: String = ""
    public var dateline: Date?
    public var datelineText: String = ""
    public var likeNum: Int = 0
    public var commentNum: Int = 0
    public var replyNum: Int = 0
    public var forwardNum: Int = 0
    public var favNum: Int = 0
    public var shareNum: Int = 0
    public var pics: [String] = []
    public var cover: String = ""
    public var isLiked = false
    public var isFavorited = false
    public var isHeadline = false
    public var infoText: String = ""
    public var feedTypeName: String = "动态"
    public var targetTitle: String = ""
    public var targetURL: String = ""
    public var targetPic: String = ""
    public var targetInfo: String = ""
    public var forwardSourceName: String = ""
    public var replyRows: [ReplyItem] = []
    public var topReplyRows: [ReplyItem] = []
    public var sourceFeed: ForwardedContent?
    public var rankScore: Int = 0
    public var raw: JSON = .null

    public static func == (lhs: FeedItem, rhs: FeedItem) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    public init(json: JSON) {
        raw = json
        id = json.id.exists ? json.id.identifier : json.entityId.identifier
        uid = json.uid.identifier
        username = json.username.string
        avatar = json.userAvatar.string.isEmpty ? json.avatar.string : json.userAvatar.string
        message = json.message.string
        messageTitle = json.message_title.string
        deviceTitle = json.device_title.string
        ipLocation = json.ip_location.string
        dateline = json.dateline.date ?? json.lastupdate.date
        datelineText = json.dateline_text.string
        likeNum = json.likenum.int
        commentNum = json.commentnum.int
        replyNum = json.replynum.int
        forwardNum = json.forwardnum.int
        favNum = json.favnum.int
        shareNum = json.share_num.int
        cover = json.message_cover.string
        isHeadline = json.is_headline.int > 0
        infoText = json.infoHtml.string.isEmpty ? json.info.string : json.infoHtml.string
        feedTypeName = json.feedTypeName.string.isEmpty ? "动态" : json.feedTypeName.string
        rankScore = json.rank_score.int

        let pictures = json.picArr.array.map(\.string).filter { !$0.isEmpty }
        if pictures.isEmpty {
            let single = json.pic.string.isEmpty ? json.media_pic.string : json.pic.string
            pics = single.isEmpty ? [] : [single]
        } else {
            pics = pictures
        }

        if json.userAction.exists {
            isLiked = json.userAction.like.int > 0
            isFavorited = json.userAction.favorite.int > 0 || json.userAction.collect.int > 0
        }

        let type = json.feedType.string
        switch type {
        case "product": kind = .product
        case "topic": kind = .topic
        case "question": kind = .question
        case "dyh", "dyhArticle": kind = .dyh
        case "feed": kind = .feed
        default: kind = type.isEmpty ? .feed : .unknown
        }

        if json.targetRow.exists, !json.targetRow.isNull {
            targetTitle = json.targetRow.title.string
            targetURL = json.targetRow.url.string
            targetPic = json.targetRow.logo.string.isEmpty ? json.targetRow.pic.string : json.targetRow.logo.string
            targetInfo = json.targetRow.description.string
        }
        if targetTitle.isEmpty, !json.ttitle.string.isEmpty {
            targetTitle = json.ttitle.string
            targetURL = json.turl.string
            targetPic = json.tpic.string
        }
        if targetTitle.isEmpty, !json.topic_title.string.isEmpty {
            targetTitle = json.topic_title.string
        }

        if json.sourceFeed.exists, !json.sourceFeed.isNull {
            forwardSourceName = json.sourceFeed.username.string
            sourceFeed = ForwardedContent(json: json.sourceFeed)
        }
        if !json.forwardSourceName.string.isEmpty { forwardSourceName = json.forwardSourceName.string }

        replyRows = json.replyRows.array.map { ReplyItem(json: $0) }
        topReplyRows = json.topReplyRows.array.map { ReplyItem(json: $0) }
    }

    /// Text shown when the dynamic is a repost of another one.
    public var forwardLabel: String {
        if sourceFeed != nil { return "转发动态" }
        return ""
    }
}

// MARK: - Reply

/// Content of a reposted dynamic. Kept flat so `FeedItem` stays a value type.
public struct ForwardedContent: Hashable {
    public var id: String = ""
    public var username: String = ""
    public var avatar: String = ""
    public var message: String = ""
    public var pics: [String] = []
    public var datelineText: String = ""
    public var feedType: String = "feed"

    public init(json: JSON) {
        id = json.id.exists ? json.id.identifier : json.entityId.identifier
        username = json.username.string
        avatar = json.userAvatar.string.isEmpty ? json.avatar.string : json.userAvatar.string
        message = json.message.string
        let pictures = json.picArr.array.map(\.string).filter { !$0.isEmpty }
        let single = json.pic.string
        pics = pictures.isEmpty ? (single.isEmpty ? [] : [single]) : pictures
        datelineText = json.dateline_text.string
        feedType = json.feedType.string
    }
}

public struct ReplyItem: Identifiable, Hashable {
    public let id: String
    public var uid: String = ""
    public var username: String = ""
    public var avatar: String = ""
    public var message: String = ""
    public var replyToName: String = ""
    public var replyToID: String = ""
    public var rootID: String = ""
    public var dateline: Date?
    public var datelineText: String = ""
    public var likeNum: Int = 0
    public var replyNum: Int = 0
    public var isLiked = false
    public var isAuthor = false
    public var pics: [String] = []
    public var nested: [ReplyItem] = []
    public var raw: JSON = .null

    public static func == (lhs: ReplyItem, rhs: ReplyItem) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    public init(json: JSON) {
        raw = json
        id = json.id.exists ? json.id.identifier : json.entityId.identifier
        uid = json.uid.identifier
        username = json.username.string
        avatar = json.userAvatar.string.isEmpty ? json.avatar.string : json.userAvatar.string
        message = json.message.string
        replyToName = json.rusername.string
        replyToID = json.rid.identifier
        rootID = json.rrid.identifier
        dateline = json.dateline.date
        datelineText = json.dateline_text.string
        likeNum = json.likenum.int
        replyNum = json.replynum.int
        isLiked = json.userAction.like.int > 0
        isAuthor = json.is_feed_author.int > 0 || json.isAuthor.int > 0
        let pictures = json.picArr.array.map(\.string).filter { !$0.isEmpty }
        let single = json.pic.string
        pics = pictures.isEmpty ? (single.isEmpty ? [] : [single]) : pictures
        nested = json.replyRows.array.map { ReplyItem(json: $0) }
    }
}

// MARK: - User

public struct UserProfile: Identifiable, Hashable {
    public let id: String
    public var username: String = ""
    public var avatar: String = ""
    public var cover: String = ""
    public var bio: String = ""
    public var level: Int = 0
    public var experience: Int = 0
    public var nextLevelExperience: Int = 0
    public var followNum: Int = 0
    public var fansNum: Int = 0
    public var feedNum: Int = 0
    public var verifyLabel: String = ""
    public var verifyTitle: String = ""
    public var location: String = ""
    public var isFollowed = false
    public var gender: Int = 0
    public var registerDate: Date?
    public var raw: JSON = .null

    public static func == (lhs: UserProfile, rhs: UserProfile) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    public init(json: JSON) {
        raw = json
        id = json.uid.exists ? json.uid.identifier : json.entityId.identifier
        username = json.username.string
        avatar = json.userAvatar.string.isEmpty ? json.userBigAvatar.string : json.userAvatar.string
        cover = json.cover.string
        bio = json.bio.string.isEmpty ? json.signature.string : json.bio.string
        level = json.level.int
        experience = json.experience.int
        nextLevelExperience = json.next_level_experience.int
        // 接口里同时存在 follow/fans/feed 与 *_num 两种写法，两个都试。
        followNum = json.follow_num.int > 0 ? json.follow_num.int : json.follow.int
        fansNum = json.fans_num.int > 0 ? json.fans_num.int : json.fans.int
        feedNum = json.feed_num.int > 0 ? json.feed_num.int : json.feed.int
        verifyLabel = json.verify_label.string
        verifyTitle = json.verify_title.string
        location = json.location.string
        isFollowed = json.isFollowed.int > 0 || json.follow.int > 0
        gender = json.gender.int
        registerDate = json.regdate.date
    }
}

public struct UserBrief: Identifiable, Hashable {
    public let id: String
    public var username: String
    public var avatar: String
    public var level: Int
    public var isFollowed: Bool
    public var bio: String
    public var verifyLabel: String
    public var fansNum: Int
    public var feedNum: Int

    public init(json: JSON) {
        id = json.uid.exists ? json.uid.identifier : json.entityId.identifier
        username = json.username.string
        avatar = json.userAvatar.string.isEmpty ? json.avatar.string : json.userAvatar.string
        level = json.level.int
        isFollowed = json.isFollowed.int > 0
        bio = json.bio.string
        verifyLabel = json.verify_label.string
        fansNum = json.fans_num.int > 0 ? json.fans_num.int : json.fans.int
        feedNum = json.feed_num.int > 0 ? json.feed_num.int : json.feed.int
    }
}

// MARK: - Home cards

public struct HomeBanner: Identifiable, Hashable {
    public init(id: String, title: String, subtitle: String, image: String, url: String) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.image = image
        self.url = url
    }

    public let id: String
    public var title: String
    public var subtitle: String
    public var image: String
    public var url: String
}

public struct HomeIconLink: Identifiable, Hashable {
    public init(id: String, title: String, image: String, url: String, subtitle: String = "") {
        self.id = id
        self.title = title
        self.image = image
        self.url = url
        self.subtitle = subtitle
    }

    public let id: String
    public var title: String
    public var image: String
    public var url: String
    public var subtitle: String = ""
}

public struct HomeSection: Identifiable, Hashable {
    public init(id: String, title: String, subtitle: String, url: String, style: String) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.url = url
        self.style = style
    }

    public let id: String
    public var title: String
    public var subtitle: String
    public var url: String
    public var style: String
}

public struct AppItem: Identifiable, Hashable {
    public let id: String
    public var title: String = ""
    public var subtitle: String = ""
    public var logo: String = ""
    public var score: String = ""
    public var size: String = ""
    public var version: String = ""
    public var developer: String = ""
    public var category: String = ""
    public var downloadCount: String = ""
    public var description: String = ""
    public var commentCount: Int = 0
    public var followCount: String = ""
    public var packageName: String = ""
    public var url: String = ""
    public var updateFlag: String = ""
    public var screenshots: [String] = []
    public var changelog: String = ""
    public var raw: JSON = .null

    public init(json: JSON) {
        raw = json
        id = json.id.exists ? json.id.identifier : json.entityId.identifier
        title = json.title.string
        subtitle = json.shorttitle.string.isEmpty ? json.subtitle.string : json.shorttitle.string
        logo = json.logo.string
        score = json.score.string
        size = json.apksize.string
        version = json.apkversionname.string.isEmpty ? json.version.string : json.apkversionname.string
        developer = json.developername.string
        category = json.catName.string
        downloadCount = json.downCount.string.isEmpty ? json.downnum.string : json.downCount.string
        description = json.description.string.isEmpty ? json.introduce.string : json.description.string
        commentCount = json.commentnum.int
        followCount = json.followCount.string
        packageName = json.packageName.string.isEmpty ? json.apkname.string : json.packageName.string
        url = json.url.string
        updateFlag = json.updateFlag.string
        changelog = json.changelog.string
        screenshots = json.screenshots.string
            .split(separator: ",")
            .map { coolapkNormalizedURL(String($0)) }
            .filter { !$0.isEmpty }
    }
}

/// A single row of a home feed: either rich header content or a dynamic.
public enum HomeFeedRow: Identifiable, Hashable {
    case feed(FeedItem)
    case product(ProductItem)
    case topic(TopicItem)
    case user(UserBrief)
    case app(AppItem)
    case banners(String, [HomeBanner])
    case icons(String, [HomeIconLink])
    case sections(String, [HomeSection])
    case text(String, String)
    /// 分节标题，可带「更多」入口。
    case sectionTitle(key: String, title: String, url: String, subtitle: String)
    /// 横向胶囊链接条（selectorLinkCard / sortSelectCard / capsuleListCard）。
    case linkBar(String, [HomeSection])
    /// 纵向链接列表（无图标的 iconListCard / goodsList）。
    case linkList(String, [HomeSection])
    /// 竖版子栏目切换（verticalColumnsFullPageCard）。
    case columnTabs(String, [HomeSection])
    /// 未登录提示卡。
    case loginPrompt(String, String)
    /// 纯说明文字卡（messageCard）。
    case notice(String, String)
    /// 横向商品（酷品 / 京东联盟商品）。
    case goods(String, [PearGoods])
    /// 横向直播。
    case lives(String, [LiveTopic])

    public var id: String {
        switch self {
        case let .feed(item): return "feed-\(item.id)"
        case let .product(item): return "product-\(item.id)"
        case let .topic(item): return "topic-\(item.id)"
        case let .user(item): return "user-\(item.id)"
        case let .app(item): return "app-\(item.id)"
        case let .banners(key, _): return "banner-\(key)"
        case let .icons(key, _): return "icons-\(key)"
        case let .sections(key, _): return "sections-\(key)"
        case let .text(key, _): return "text-\(key)"
        case let .sectionTitle(key, _, _, _): return "section-\(key)"
        case let .linkBar(key, _): return "linkbar-\(key)"
        case let .linkList(key, _): return "linklist-\(key)"
        case let .columnTabs(key, _): return "columns-\(key)"
        case let .loginPrompt(key, _): return "login-\(key)"
        case let .notice(key, _): return "notice-\(key)"
        case let .goods(key, _): return "goods-\(key)"
        case let .lives(key, _): return "lives-\(key)"
        }
    }
}

// MARK: - 电商与直播

/// 酷品 / 京东联盟商品。
public struct PearGoods: Identifiable, Hashable {
    public let id: String
    public var title = ""
    public var image = ""
    public var price = ""
    public var promoTitle = ""
    public var mall = ""
    public var category = ""
    public var buyText = ""
    public var buyURL = ""
    public var detailURL = ""
    public var raw: JSON = .null

    public init(json: JSON) {
        self.raw = json
        let union = json.union_item_id.string
        let rawID = json.id.identifier
        self.id = !union.isEmpty ? union : (rawID.isEmpty ? json.title.string : rawID)
        self.title = json.title.string.isEmpty ? json.goods_title.string : json.title.string
        self.image = json.goods_pic.string
        let priceValue = json.goods_promo_price.double
        self.price = priceValue > 0 ? String(format: "¥%.2f", priceValue) : ""
        self.promoTitle = json.goods_promo_title.string
        self.mall = json.mall_title.string
        self.category = json.category_title.string
        self.buyText = json.goods_buy_text.string
        self.buyURL = json.goods_buy_url.string.isEmpty ? json.goods_url.string : json.goods_buy_url.string
        self.detailURL = json.goods_url.string
    }
}

/// 直播条目（`liveTopic`）。
public struct LiveTopic: Identifiable, Hashable {
    public let id: String
    public var title = ""
    public var summary = ""
    public var cover = ""
    public var startAt: Date?
    public var presenterUID = ""
    public var raw: JSON = .null

    public init(json: JSON) {
        self.raw = json
        self.id = json.id.identifier
        self.title = json.title.string
        self.summary = json.description.string
        self.cover = json.pic_url.string
        let stamp = json.live_time.double
        self.startAt = stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
        self.presenterUID = json.presenter_uid.string
    }

    public var timeText: String {
        guard let startAt else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: startAt)
    }
}

// MARK: - Product / topic

public struct ProductItem: Identifiable, Hashable {
    public let id: String
    public var title: String = ""
    public var subtitle: String = ""
    public var logo: String = ""
    public var description: String = ""
    public var score: String = ""
    public var followNum: Int = 0
    public var isFollowed = false
    public var url: String = ""
    public var raw: JSON = .null

    public init(json: JSON) {
        raw = json
        id = json.id.exists ? json.id.identifier : json.entityId.identifier
        title = json.title.string
        subtitle = json.sub_title.string.isEmpty ? json.description.string : json.sub_title.string
        logo = json.logo.string.isEmpty ? json.pic.string : json.logo.string
        description = json.description.string
        score = json.score.string.isEmpty ? json.avg_score.string : json.score.string
        followNum = json.follow_num.int
        isFollowed = json.isFollowed.int > 0 || json.follow.int > 0
        url = json.url.string
    }
}

public struct TopicItem: Identifiable, Hashable {
    public let id: String
    public var title: String = ""
    public var description: String = ""
    public var logo: String = ""
    public var feedNum: Int = 0
    public var followNum: Int = 0
    public var isFollowed = false
    public var raw: JSON = .null

    public init(json: JSON) {
        raw = json
        id = json.id.exists ? json.id.identifier : json.entityId.identifier
        title = json.title.string
        description = json.description.string
        logo = json.logo.string.isEmpty ? json.pic.string : json.logo.string
        feedNum = json.feed_num.int
        followNum = json.follow_num.int
        isFollowed = json.isFollowed.int > 0 || json.follow.int > 0
    }
}

// MARK: - Notifications

/// 收藏夹 (a curated collection of feeds).
public struct CollectionItem: Identifiable, Hashable {
    public let id: String
    public var title: String = ""
    public var subtitle: String = ""
    public var description: String = ""
    public var logo: String = ""
    public var username: String = ""
    public var avatar: String = ""
    public var uid: String = ""
    public var itemNum: Int = 0
    public var followNum: Int = 0
    public var likeNum: Int = 0
    public var isFollowed = false
    public var raw: JSON = .null

    public init(json: JSON) {
        raw = json
        id = json.id.exists ? json.id.identifier : json.entityId.identifier
        title = json.title.string
        subtitle = json.sub_title.string
        description = json.description.string.isEmpty ? json.intro.string : json.description.string
        logo = json.logo.string.isEmpty ? json.pic.string : json.logo.string
        username = json.username.string.isEmpty ? json.userInfo.username.string : json.username.string
        avatar = json.userAvatar.string.isEmpty ? json.userInfo.userAvatar.string : json.userAvatar.string
        uid = json.uid.identifier.isEmpty ? json.userInfo.uid.identifier : json.uid.identifier
        itemNum = json.item_num.int
        followNum = json.follow_num.int
        likeNum = json.like_num.int
        isFollowed = json.isFollowed.int > 0 || json.follow.int > 0
    }
}

/// 看看号 (a publisher / newspaper style account).
public struct DyhItem: Identifiable, Hashable {
    public let id: String
    public var title: String = ""
    public var description: String = ""
    public var logo: String = ""
    public var username: String = ""
    public var avatar: String = ""
    public var uid: String = ""
    public var followNum: Int = 0
    public var likeNum: Int = 0
    public var isFollowed = false
    public var raw: JSON = .null

    public init(json: JSON) {
        raw = json
        id = json.id.exists ? json.id.identifier : json.dyh_id.identifier
        title = json.title.string
        description = json.description.string
        logo = json.logo.string.isEmpty ? json.pic.string : json.logo.string
        username = json.username.string
        avatar = json.userAvatar.string
        uid = json.uid.identifier
        followNum = json.follownum.int
        likeNum = json.likenum.int
        isFollowed = json.isFollowed.int > 0 || json.follow.int > 0 || json.is_follow.int > 0
    }
}

/// One entry of the 热榜 ranking, used when a list card carries a score.
public struct RankEntry: Identifiable, Hashable {
    public let id: String
    public var title: String = ""
    public var subtitle: String = ""
    public var score: Int = 0
    public var url: String = ""

    public init(json: JSON) {
        id = json.id.exists ? json.id.identifier : json.entityId.identifier
        title = json.title.string
        subtitle = json.sub_title.string.isEmpty ? json.description.string : json.sub_title.string
        score = json.rank_score.int
        url = json.url.string
    }
}

public struct NotificationItem: Identifiable, Hashable {
    public let id: String
    public var type: String = ""
    public var title: String = ""
    public var message: String = ""
    public var avatar: String = ""
    public var username: String = ""
    public var url: String = ""
    public var dateline: Date?
    public var datelineText: String = ""
    public var isRead = false
    public var extraTitle: String = ""
    public var extraPic: String = ""
    public var raw: JSON = .null

    public init(json: JSON) {
        raw = json
        id = json.id.exists ? json.id.identifier : json.entityId.identifier
        type = json.type.string
        title = json.title.string
        message = json.message.string
        avatar = json.userAvatar.string.isEmpty ? json.avatar.string : json.userAvatar.string
        username = json.username.string
        url = json.url.string
        dateline = json.dateline.date ?? json.lastupdate.date
        datelineText = json.dateline_text.string
        isRead = json.is_read.int > 0
        extraTitle = json.extra_title.string
        extraPic = json.extra_pic.string
    }
}

public struct MessageItem: Identifiable, Hashable {
    public let id: String
    public var username: String = ""
    public var avatar: String = ""
    public var message: String = ""
    public var dateline: Date?
    public var unreadNum: Int = 0
    public var uid: String = ""

    public init(json: JSON) {
        id = json.id.exists ? json.id.identifier : json.uid.identifier
        username = json.username.string
        avatar = json.userAvatar.string
        message = json.message.string
        dateline = json.dateline.date
        unreadNum = json.unread_num.int
        uid = json.uid.identifier
    }
}

public struct NotificationBadge: Equatable {
    public var notification = 0
    public var message = 0
    public var atMe = 0
    public var atCommentMe = 0
    public var commentMe = 0
    public var feedLike = 0
    public var contactsFollow = 0

    public var total: Int { notification + message }

    public init(json: JSON = .null) {
        notification = json.notification.int
        message = json.message.int
        atMe = json.atme.int
        atCommentMe = json.atcommentme.int
        commentMe = json.commentme.int
        feedLike = json.feedlike.int
        contactsFollow = json.contacts_follow.int
    }
}

// MARK: - Sidebar model

public struct HomeTab: Identifiable, Hashable {
    public init(id: String, title: String, pageName: String, logo: String = "") {
        self.id = id
        self.title = title
        self.pageName = pageName
        self.logo = logo
    }

    public let id: String
    public var title: String
    public var pageName: String
    public var logo: String = ""
}

public struct SidebarSection: Identifiable, Hashable {
    public init(id: String, title: String, tabs: [HomeTab]) {
        self.id = id
        self.title = title
        self.tabs = tabs
    }

    public let id: String
    public var title: String
    public var tabs: [HomeTab]
}
