import Foundation

// MARK: - Feed

/// One dynamic (动态) row. Coolapk returns loosely typed JSON, so every field is coerced.
struct FeedItem: Identifiable, Hashable {
    enum Kind: String {
        case feed
        case product
        case topic
        case question
        case dyh
        case unknown
    }

    let id: String
    var kind: Kind = .feed
    var uid: String = ""
    var username: String = ""
    var avatar: String = ""
    var message: String = ""
    var messageTitle: String = ""
    var deviceTitle: String = ""
    var ipLocation: String = ""
    var dateline: Date?
    var datelineText: String = ""
    var likeNum: Int = 0
    var commentNum: Int = 0
    var replyNum: Int = 0
    var forwardNum: Int = 0
    var favNum: Int = 0
    var shareNum: Int = 0
    var pics: [String] = []
    var cover: String = ""
    var isLiked = false
    var isFavorited = false
    var isHeadline = false
    var infoText: String = ""
    var feedTypeName: String = "动态"
    var targetTitle: String = ""
    var targetURL: String = ""
    var targetPic: String = ""
    var targetInfo: String = ""
    var forwardSourceName: String = ""
    var replyRows: [ReplyItem] = []
    var topReplyRows: [ReplyItem] = []
    var sourceFeed: ForwardedContent?
    var rankScore: Int = 0
    var raw: JSON = .null

    static func == (lhs: FeedItem, rhs: FeedItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    init(json: JSON) {
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
    var forwardLabel: String {
        if sourceFeed != nil { return "转发动态" }
        return ""
    }
}

// MARK: - Reply

/// Content of a reposted dynamic. Kept flat so `FeedItem` stays a value type.
struct ForwardedContent: Hashable {
    var id: String = ""
    var username: String = ""
    var avatar: String = ""
    var message: String = ""
    var pics: [String] = []
    var datelineText: String = ""
    var feedType: String = "feed"

    init(json: JSON) {
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

struct ReplyItem: Identifiable, Hashable {
    let id: String
    var uid: String = ""
    var username: String = ""
    var avatar: String = ""
    var message: String = ""
    var replyToName: String = ""
    var replyToID: String = ""
    var rootID: String = ""
    var dateline: Date?
    var datelineText: String = ""
    var likeNum: Int = 0
    var replyNum: Int = 0
    var isLiked = false
    var isAuthor = false
    var pics: [String] = []
    var nested: [ReplyItem] = []
    var raw: JSON = .null

    static func == (lhs: ReplyItem, rhs: ReplyItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    init(json: JSON) {
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

struct UserProfile: Identifiable, Hashable {
    let id: String
    var username: String = ""
    var avatar: String = ""
    var cover: String = ""
    var bio: String = ""
    var level: Int = 0
    var experience: Int = 0
    var nextLevelExperience: Int = 0
    var followNum: Int = 0
    var fansNum: Int = 0
    var feedNum: Int = 0
    var verifyLabel: String = ""
    var verifyTitle: String = ""
    var location: String = ""
    var isFollowed = false
    var gender: Int = 0
    var registerDate: Date?
    var raw: JSON = .null

    static func == (lhs: UserProfile, rhs: UserProfile) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    init(json: JSON) {
        raw = json
        id = json.uid.exists ? json.uid.identifier : json.entityId.identifier
        username = json.username.string
        avatar = json.userAvatar.string.isEmpty ? json.userBigAvatar.string : json.userAvatar.string
        cover = json.cover.string
        bio = json.bio.string.isEmpty ? json.signature.string : json.bio.string
        level = json.level.int
        experience = json.experience.int
        nextLevelExperience = json.next_level_experience.int
        followNum = json.follow_num.int
        fansNum = json.fans_num.int
        feedNum = json.feed_num.int
        verifyLabel = json.verify_label.string
        verifyTitle = json.verify_title.string
        location = json.location.string
        isFollowed = json.isFollowed.int > 0 || json.follow.int > 0
        gender = json.gender.int
        registerDate = json.regdate.date
    }
}

struct UserBrief: Identifiable, Hashable {
    let id: String
    var username: String
    var avatar: String
    var level: Int
    var isFollowed: Bool
    var bio: String
    var verifyLabel: String
    var fansNum: Int
    var feedNum: Int

    init(json: JSON) {
        id = json.uid.exists ? json.uid.identifier : json.entityId.identifier
        username = json.username.string
        avatar = json.userAvatar.string.isEmpty ? json.avatar.string : json.userAvatar.string
        level = json.level.int
        isFollowed = json.isFollowed.int > 0
        bio = json.bio.string
        verifyLabel = json.verify_label.string
        fansNum = json.fans_num.int
        feedNum = json.feed_num.int
    }
}

// MARK: - Home cards

struct HomeBanner: Identifiable, Hashable {
    let id: String
    var title: String
    var subtitle: String
    var image: String
    var url: String
}

struct HomeIconLink: Identifiable, Hashable {
    let id: String
    var title: String
    var image: String
    var url: String
    var subtitle: String = ""
}

struct HomeSection: Identifiable, Hashable {
    let id: String
    var title: String
    var subtitle: String
    var url: String
    var style: String
}

struct AppItem: Identifiable, Hashable {
    let id: String
    var title: String = ""
    var subtitle: String = ""
    var logo: String = ""
    var score: String = ""
    var size: String = ""
    var version: String = ""
    var developer: String = ""
    var category: String = ""
    var downloadCount: String = ""
    var description: String = ""
    var commentCount: Int = 0
    var followCount: String = ""
    var packageName: String = ""
    var url: String = ""
    var updateFlag: String = ""
    var screenshots: [String] = []
    var changelog: String = ""
    var raw: JSON = .null

    init(json: JSON) {
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
            .map { ImageStore.normalize(String($0)) }
            .filter { !$0.isEmpty }
    }
}

/// A single row of a home feed: either rich header content or a dynamic.
enum HomeFeedRow: Identifiable, Hashable {
    case feed(FeedItem)
    case product(ProductItem)
    case topic(TopicItem)
    case user(UserBrief)
    case app(AppItem)
    case banners(String, [HomeBanner])
    case icons(String, [HomeIconLink])
    case sections(String, [HomeSection])
    case text(String, String)

    var id: String {
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
        }
    }
}

// MARK: - Product / topic

struct ProductItem: Identifiable, Hashable {
    let id: String
    var title: String = ""
    var subtitle: String = ""
    var logo: String = ""
    var description: String = ""
    var score: String = ""
    var followNum: Int = 0
    var isFollowed = false
    var url: String = ""
    var raw: JSON = .null

    init(json: JSON) {
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

struct TopicItem: Identifiable, Hashable {
    let id: String
    var title: String = ""
    var description: String = ""
    var logo: String = ""
    var feedNum: Int = 0
    var followNum: Int = 0
    var isFollowed = false
    var raw: JSON = .null

    init(json: JSON) {
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
struct CollectionItem: Identifiable, Hashable {
    let id: String
    var title: String = ""
    var subtitle: String = ""
    var description: String = ""
    var logo: String = ""
    var username: String = ""
    var avatar: String = ""
    var uid: String = ""
    var itemNum: Int = 0
    var followNum: Int = 0
    var likeNum: Int = 0
    var isFollowed = false
    var raw: JSON = .null

    init(json: JSON) {
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
struct DyhItem: Identifiable, Hashable {
    let id: String
    var title: String = ""
    var description: String = ""
    var logo: String = ""
    var username: String = ""
    var avatar: String = ""
    var uid: String = ""
    var followNum: Int = 0
    var likeNum: Int = 0
    var isFollowed = false
    var raw: JSON = .null

    init(json: JSON) {
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
struct RankEntry: Identifiable, Hashable {
    let id: String
    var title: String = ""
    var subtitle: String = ""
    var score: Int = 0
    var url: String = ""

    init(json: JSON) {
        id = json.id.exists ? json.id.identifier : json.entityId.identifier
        title = json.title.string
        subtitle = json.sub_title.string.isEmpty ? json.description.string : json.sub_title.string
        score = json.rank_score.int
        url = json.url.string
    }
}

struct NotificationItem: Identifiable, Hashable {
    let id: String
    var type: String = ""
    var title: String = ""
    var message: String = ""
    var avatar: String = ""
    var username: String = ""
    var url: String = ""
    var dateline: Date?
    var datelineText: String = ""
    var isRead = false
    var extraTitle: String = ""
    var extraPic: String = ""
    var raw: JSON = .null

    init(json: JSON) {
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

struct MessageItem: Identifiable, Hashable {
    let id: String
    var username: String = ""
    var avatar: String = ""
    var message: String = ""
    var dateline: Date?
    var unreadNum: Int = 0
    var uid: String = ""

    init(json: JSON) {
        id = json.id.exists ? json.id.identifier : json.uid.identifier
        username = json.username.string
        avatar = json.userAvatar.string
        message = json.message.string
        dateline = json.dateline.date
        unreadNum = json.unread_num.int
        uid = json.uid.identifier
    }
}

struct NotificationBadge: Equatable {
    var notification = 0
    var message = 0
    var atMe = 0
    var atCommentMe = 0
    var commentMe = 0
    var feedLike = 0
    var contactsFollow = 0

    var total: Int { notification + message }

    init(json: JSON = .null) {
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

struct HomeTab: Identifiable, Hashable {
    let id: String
    var title: String
    var pageName: String
    var logo: String = ""
}

struct SidebarSection: Identifiable, Hashable {
    let id: String
    var title: String
    var tabs: [HomeTab]
}
