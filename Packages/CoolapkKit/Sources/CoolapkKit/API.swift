import Foundation

/// Typed wrappers around the Coolapk web API.
public enum API {
    private static var client: CoolapkClient { CoolapkClient.shared }

    // MARK: - Home

    /// Tab configuration (`/v6/main/init`).
    public static func tabConfiguration() async throws -> [SidebarSection] {
        let json = try await client.get("/v6/main/init", ["t": String(Int(Date().timeIntervalSince1970))])
        var sections: [SidebarSection] = []
        for card in json.data.array {
            let title = card.title.string
            var tabs: [HomeTab] = []
            for entity in card.entities.array {
                let pageName = entity.page_name.string
                guard !pageName.isEmpty else { continue }
                tabs.append(HomeTab(id: pageName, title: entity.title.string, pageName: pageName, logo: entity.logo.string))
            }
            guard !tabs.isEmpty else { continue }
            sections.append(SidebarSection(id: title, title: title, tabs: tabs))
        }
        return sections
    }

    public static func hotSearchWords() async throws -> [String] {
        let json = try await client.get("/v6/main/init", ["t": String(Int(Date().timeIntervalSince1970))])
        return json.data.array.first?.entities.array.map(\.title.string) ?? []
    }

    /// Home timeline (`/v6/main/indexV8`).
    public static func homeFeed(page: Int) async throws -> [HomeFeedRow] {
        let json = try await client.get("/v6/main/indexV8", ["page": String(page), "t": String(Int(Date().timeIntervalSince1970))])
        return try rows(from: json.data.array)
    }

    /// 头条信息流（`/v6/main/headline`），与首页推荐流是两套内容。
    public static func headlineFeed(page: Int) async throws -> [HomeFeedRow] {
        let json = try await client.get("/v6/main/headline", ["page": String(page), "t": String(Int(Date().timeIntervalSince1970))])
        return try rows(from: json.data.array)
    }

    /// Generic page timeline, used by "关注", "热榜", "话题" and friends.
    public static func pageFeed(pageName: String, page: Int, type: String? = nil) async throws -> [HomeFeedRow] {
        var extra: [String: String] = [:]
        if let type { extra["type"] = type }
        let items = try await client.dataList(url: pageName, page: page, extra: extra)
        return try rows(from: items)
    }

    /// 需要忽略的卡片模板：页面元数据、广告与埋点卡片。
    private static let ignoredCardTemplates: Set<String> = [
        "configCard", "sponsorCard", "sponsorArticleNews", "fabCard",
        "ratingNodeUserEnv", "adCard", "staticsCard",
    ]

    /// 图标网格族的模板名，统一渲染成九宫格 / 横滑图标。
    private static let iconCardTemplates: Set<String> = [
        "iconLinkGridCard", "iconMiniScrollCard", "iconListCard", "iconGridCard",
        "iconMiniGridCard", "iconMiniLinkGridCard", "iconLongTitleGridCard",
        "iconButtonGridCard", "iconLargeScrollCard", "imageSquareScrollCard",
    ]

    /// 胶囊链接条族的模板名。
    private static let linkBarTemplates: Set<String> = [
        "selectorLinkCard", "sortSelectCard", "capsuleListCard", "colorfulScrollCard",
    ]

    /// 把一个原始条目数组转换成可以直接渲染的行。
    /// 按页面地址拉取列表，地址可能形如 `/page?url=V11_XXX` 或 `#/topic/tagList?…`。
    public static func linkFeed(link: String, page: Int) async throws -> [HomeFeedRow] {
        var target = link
        if let range = target.range(of: "url=") {
            target = String(target[range.upperBound...])
            if let amp = target.firstIndex(of: "&") { target = String(target[..<amp]) }
        }
        target = target.replacingOccurrences(of: "#", with: "")
        if target.hasPrefix("/page?") {
            let items = try await client.get(target, ["page": String(page)]).data.array
            return try rows(from: items)
        }
        let items = try await client.dataList(url: target, page: page)
        return try rows(from: items)
    }

    public static func rows(from items: [JSON]) throws -> [HomeFeedRow] {
        var rows: [HomeFeedRow] = []
        // 连续的同类商品 / 直播合并成一条横滑，避免每张卡片各占一行。
        var pendingGoods: [PearGoods] = []
        var pendingLives: [LiveTopic] = []

        func flushGoods() {
            guard !pendingGoods.isEmpty else { return }
            rows.append(.goods("goods-\(rows.count)", pendingGoods))
            pendingGoods = []
        }

        func flushLives() {
            guard !pendingLives.isEmpty else { return }
            rows.append(.lives("lives-\(rows.count)", pendingLives))
            pendingLives = []
        }

        func flushAll() {
            flushGoods()
            flushLives()
        }

        for (index, item) in items.enumerated() {
            let template = item.entityTemplate.string
            switch item.entityType.string {
            case "pear_goods":
                flushLives()
                pendingGoods.append(PearGoods(json: item))
                continue
            case "liveTopic":
                flushGoods()
                pendingLives.append(LiveTopic(json: item))
                continue
            default:
                break
            }

            flushAll()
            switch item.entityType.string {
            case "feed", "feed_reply", "reply":
                rows.append(.feed(FeedItem(json: item)))
            case "product":
                rows.append(.product(ProductItem(json: item)))
            case "topic":
                rows.append(.topic(TopicItem(json: item)))
            case "user":
                rows.append(.user(UserBrief(json: item)))
            case "apk":
                rows.append(.app(AppItem(json: item)))
            case "card":
                rows.append(contentsOf: cardRows(item, template: template, index: index))
            default:
                continue
            }
        }
        flushAll()
        return rows
    }

    /// 单张卡片的解析；空数组表示这张卡片不产生可见内容。
    private static func cardRows(_ item: JSON, template: String, index: Int) -> [HomeFeedRow] {
        if ignoredCardTemplates.contains(template) { return [] }

        let entities = item.entities.array
        let title = item.title.string
        let moreURL = item.url.string

        /// 在内容前插入一个分节标题。
        func titled(_ rows: [HomeFeedRow]) -> [HomeFeedRow] {
            guard !title.isEmpty else { return rows }
            return [.sectionTitle(key: "\(index)", title: title, url: moreURL, subtitle: "")] + rows
        }

        // 商品类卡片：内部直接放商品时优先按商品渲染。
        if !entities.isEmpty, entities.allSatisfy({ $0.entityType.string == "pear_goods" }) {
            return titled([.goods("goods-\(index)", entities.map { PearGoods(json: $0) })])
        }

        // 含 logo 与价格字段的榜单实体（listCard / productTimelineListCard）。
        if template == "listCard" || template == "productTimelineListCard" {
            let products = entities
                .filter { !$0.logo.string.isEmpty || $0.price_min.exists }
                .map { ProductItem(json: $0) }
            if let only = products.first, products.count == 1 { return titled([.product(only)]) }
            if !products.isEmpty { return titled(products.prefix(8).map { HomeFeedRow.product($0) }) }
        }

        // 纯图片按钮卡（京东等广告位）按横幅渲染。
        if template == "iconButtonGridCard" {
            let banners = entities.compactMap { entity -> HomeBanner? in
                let image = entity.pic.string
                guard !image.isEmpty else { return nil }
                return HomeBanner(id: "\(entity.entityId.identifier)-\(index)",
                                  title: entity.title.string,
                                  subtitle: "",
                                  image: image,
                                  url: entity.url.string)
            }
            if !banners.isEmpty { return [.banners("banner-\(index)", banners)] }
        }

        if iconCardTemplates.contains(template) {
            let links = entities.map(iconLink(from:)).filter { !$0.image.isEmpty || !$0.title.isEmpty }
            if links.isEmpty { return [] }
            // 全部没有配图时改成纵向链接列表，避免出现一排空占位图。
            if links.allSatisfy({ $0.image.isEmpty }) {
                let sections = links.map { HomeSection(id: $0.id, title: $0.title, subtitle: $0.subtitle, url: $0.url, style: "") }
                return titled([.linkList("linklist-\(index)", sections)])
            }
            return titled([.icons("icons-\(index)", links)])
        }

        if linkBarTemplates.contains(template) {
            let links = entities
                .map { entity in
                    HomeSection(id: "\(entity.entityId.identifier)-\(entity.title.string)",
                                title: entity.title.string,
                                subtitle: entity.sub_title.string.isEmpty ? entity.description.string : entity.sub_title.string,
                                url: entity.url.string,
                                style: entity.pic.string)
                }
                .filter { !$0.title.isEmpty }
            return links.isEmpty ? [] : titled([.linkBar("linkbar-\(index)", links)])
        }

        switch template {
        case "imageCarouselCard_1", "imageCarouselCard_2", "imageCarouselCard":
            let banners = entities.compactMap { entity -> HomeBanner? in
                let image = entity.pic.string
                guard !image.isEmpty else { return nil }
                return HomeBanner(id: "\(entity.entityId.identifier)-\(entity.title.string)",
                                  title: entity.title.string.isEmpty ? entity.description.string : entity.title.string,
                                  subtitle: entity.sub_title.string,
                                  image: image,
                                  url: entity.url.string)
            }
            return banners.isEmpty ? [] : [.banners("banner-\(index)", banners)]

        case "imageTextScrollCard":
            let sections = entities.map { entity in
                HomeSection(id: "\(entity.entityId.identifier)-\(entity.title.string)",
                            title: entity.title.string,
                            subtitle: entity.sub_title.string.isEmpty ? entity.description.string : entity.sub_title.string,
                            url: entity.url.string,
                            style: entity.pic.string)
            }
            return sections.isEmpty ? [] : [.sections("sections-\(index)", sections)]

        case "verticalColumnsFullPageCard":
            let columns = entities
                .map { entity in
                    HomeSection(id: "\(entity.entityId.identifier)-\(entity.title.string)",
                                title: entity.title.string,
                                subtitle: entity.sub_title.string,
                                url: entity.url.string,
                                style: entity.pic.string)
                }
                .filter { !$0.title.isEmpty }
            return columns.isEmpty ? [] : [.columnTabs("columns-\(index)", columns)]

        case "titleCard":
            return title.isEmpty ? [] : [.sectionTitle(key: "\(index)", title: title, url: moreURL, subtitle: "")]

        case "unLoginCard":
            return [.loginPrompt("\(index)", title.isEmpty ? "更多精彩内容请登录" : title)]

        case "messageCard":
            let text = item.description.string
            return text.isEmpty ? [] : [.notice("\(index)", text)]

        case "feedListCard":
            // 卡片内部直接内嵌单条动态时整条渲染，其余交给「更多」入口。
            if entities.count == 1, let entity = entities.first {
                return [.feed(FeedItem(json: entity))]
            }
            return title.isEmpty ? [] : [.sectionTitle(key: "\(index)", title: title, url: moreURL, subtitle: "")]

        default:
            // 兜底：带图实体当成图标网格，纯标题当成文字卡。
            let links = entities.map(iconLink(from:)).filter { !$0.image.isEmpty }
            if !links.isEmpty { return titled([.icons("icons-\(index)", links)]) }
            if !title.isEmpty, entities.isEmpty { return [.text("text-\(index)", title)] }
        }
        return []
    }

    private static func iconLink(from entity: JSON) -> HomeIconLink {
        HomeIconLink(id: "\(entity.entityId.identifier)-\(entity.title.string)",
                     title: entity.title.string,
                     image: entity.logo.string.isEmpty ? entity.pic.string : entity.logo.string,
                     url: entity.url.string,
                     subtitle: entity.sub_title.string.isEmpty ? entity.description.string : entity.sub_title.string)
    }

    // MARK: - Feed detail

    public static func feedDetail(id: String) async throws -> FeedItem {
        let json = try await client.get("/v6/feed/detail", ["id": id])
        return FeedItem(json: json.data)
    }

    /// 排序取值必须为 `lastupdate_desc` / `dateline_desc` / `popular`，
    /// 传 `lastupdate` 时服务端会直接返回空数组。
    public static func replies(feedID: String, page: Int, listType: String = "lastupdate_desc", authorOnly: Bool = false) async throws -> [ReplyItem] {
        let json = try await client.get("/v6/feed/replyList", [
            "id": feedID,
            "listType": listType,
            "page": String(page),
            "discussMode": "1",
            "feedType": "feed",
            "blockStatus": "0",
            "fromFeedAuthor": authorOnly ? "1" : "0",
        ])
        return json.data.array.map { ReplyItem(json: $0) }
    }

    /// 热门评论走 `replyList` 的 `popular` 排序；`/v6/feed/hotReplyList` 服务端已失效。
    public static func hotReplies(feedID: String, page: Int) async throws -> [ReplyItem] {
        try await replies(feedID: feedID, page: page, listType: "popular")
    }

    public static func subReplies(replyID: String, page: Int) async throws -> [ReplyItem] {
        let json = try await client.get("/v6/feed/replyList", [
            "id": replyID,
            "page": String(page),
            "discussMode": "0",
            "feedType": "feed_reply",
            "blockStatus": "0",
            "fromFeedAuthor": "0",
        ])
        return json.data.array.map { ReplyItem(json: $0) }
    }

    // MARK: - Interactions

    public static func likeFeed(id: String, liked: Bool, feedType: String = "feed") async throws {
        let suffix = feedType == "product" ? "#3" : (feedType == "feed" ? "" : "")
        let path = (liked ? "/v6/feed/like" : "/v6/feed/unlike") + suffix
        _ = try await client.post(path, ["id": id])
    }

    public static func likeReply(id: String, liked: Bool) async throws {
        let path = liked ? "/v6/feed/like#3" : "/v6/feed/unlike#3"
        _ = try await client.post(path, ["id": id])
    }

    public static func collectFeed(id: String, collected: Bool) async throws {
        let path = collected ? "/v6/feed/collect" : "/v6/feed/unCollect"
        _ = try await client.post(path, ["id": id])
    }

    /// Posts a comment. `targetID` is the dynamic id, or the reply id when answering a comment.
    public static func postReply(targetID: String, message: String, isReply: Bool = false) async throws -> String {
        let allowed = CharacterSet.alphanumerics
        let encoded = message.addingPercentEncoding(withAllowedCharacters: allowed) ?? message
        let path = "/v6/feed/reply?id=\(targetID)&type=\(isReply ? "reply" : "feed")"
        let json = try await client.post(path, ["message": encoded])
        return json.data.string.isEmpty ? json.message.string : json.data.string
    }

    public static func deleteReply(id: String) async throws {
        _ = try await client.post("/v6/feed/deleteReply", ["id": id])
    }

    public static func followUser(uid: String, follow: Bool) async throws {
        _ = try await client.post(follow ? "/v6/user/follow" : "/v6/user/unfollow", ["uid": uid])
    }

    public static func followTopic(tag: String, follow: Bool) async throws {
        _ = try await client.post(follow ? "/v6/feed/followTag" : "/v6/feed/unFollowTag", ["tag": tag])
    }

    public static func followProduct(id: String, follow: Bool) async throws {
        _ = try await client.post("/v6/product/changeFollowStatus", ["id": id, "status": follow ? "1" : "0"])
    }

    // MARK: - Publishing

    public static func uploadImage(data: Data, filename: String) async throws -> String {
        let json = try await client.upload(
            path: "/v6/feed/uploadImage?fieldName=picFile&uploadDir=feed",
            fieldName: "picFile",
            filename: filename,
            data: data
        )
        let link = json.data.string
        guard !link.isEmpty else { throw APIError.message(json.message.string.isEmpty ? "图片上传失败" : json.message.string) }
        return link
    }

    public static func createFeed(message: String, pictures: [String]) async throws {
        var form: [String: String] = [
            "message": message,
            "type": "feed",
            "is_html_article": "0",
        ]
        if !pictures.isEmpty {
            form["pics"] = pictures.joined(separator: ",")
            form["picArr"] = pictures.joined(separator: ",")
        }
        _ = try await client.post("/v6/feed/createFeed", form)
    }

    // MARK: - Users

    public static func userProfile(uid: String) async throws -> UserProfile {
        let json = try await client.get("/v6/user/profile", ["uid": uid])
        return UserProfile(json: json.data)
    }

    public static func userSpace(uid: String) async throws -> UserProfile {
        let json = try await client.get("/v6/user/space", ["uid": uid])
        return UserProfile(json: json.data)
    }

    public static func userFeeds(uid: String, page: Int) async throws -> [HomeFeedRow] {
        let json = try await client.get("/v6/user/feedList", ["uid": uid, "page": String(page), "isIncludeTop": "1"])
        return try rows(from: json.data.array)
    }

    public static func userList(uid: String, followers: Bool, page: Int) async throws -> [UserBrief] {
        let path = followers ? "/v6/user/fansList" : "/v6/user/followList"
        let json = try await client.get(path, ["uid": uid, "page": String(page)])
        return json.data.array.map { item in
            let user = item.userInfo.exists ? item.userInfo : item.fUserInfo
            return UserBrief(json: user)
        }
    }

    public static func myProfile() async throws -> UserProfile {
        let session = await client.sessionSnapshot()
        guard !session.uid.isEmpty else { throw APIError.unauthorized }
        return try await userProfile(uid: session.uid)
    }

    public static func checkLogin() async throws -> Bool {
        let json = try await client.get("/v6/account/checkLoginInfo")
        return json.data.string == "1" || json.data.int == 1
    }

    // MARK: - Search

    public static func search(keyword: String, type: String, page: Int) async throws -> [JSON] {
        let json = try await client.get("/v6/search", [
            "type": type,
            "searchValue": keyword,
            "page": String(page),
            "showAnonymous": "-1",
        ])
        return json.data.array
    }

    public static func suggestWords(keyword: String) async throws -> [String] {
        let json = try await client.get("/v6/search/suggestSearchWordsNew", ["searchValue": keyword, "type": "app"])
        return json.data.array.map(\.title.string)
    }

    // MARK: - Topics / products / apps

    public static func topicFeeds(tag: String, page: Int, listType: String = "lastupdate_desc") async throws -> [HomeFeedRow] {
        let json = try await client.get("/v6/topic/tagFeedList", [
            "tag": tag,
            "page": String(page),
            "listType": listType,
            "blockStatus": "0",
        ])
        return try rows(from: json.data.array)
    }

    public static func topicDetail(tag: String) async throws -> TopicItem {
        do {
            let json = try await client.get("/v6/topic/newTagDetail", ["tag": tag])
            return TopicItem(json: json.data)
        } catch {
            let json = try await client.get("/v6/topic/tagDetail", ["tag": tag])
            return TopicItem(json: json.data)
        }
    }

    public static func productDetail(id: String) async throws -> ProductItem {
        let json = try await client.get("/v6/product/detail", ["id": id])
        return ProductItem(json: json.data)
    }

    /// 应用 / 游戏. `type` is 1 for apps and 2 for games.
    public static func appIndex(type: Int, page: Int) async throws -> [HomeFeedRow] {
        let json = try await client.get("/v6/apk/index", ["apkType": String(type), "page": String(page)])
        return try rows(from: json.data.array)
    }

    public static func appDetail(id: String) async throws -> JSON {
        let json = try await client.get("/v6/apk/detail", ["id": id, "installed": "0"])
        return json.data
    }

    public static func appComments(id: String, page: Int) async throws -> [HomeFeedRow] {
        let items = try await client.dataList(url: "#/feed/apkCommentList?isIncludeTop=1&id=\(id)&subTitle=", page: page)
        return try rows(from: items)
    }

    public static func collectionList(uid: String?, page: Int) async throws -> [JSON] {
        let uid = uid ?? ""
        let json = try await client.get("/v6/collection/list", ["uid": uid, "page": String(page)])
        return json.data.array
    }

    // MARK: - Notifications

    public static func badge() async throws -> NotificationBadge {
        let json = try await client.get("/v6/notification/checkCount")
        return NotificationBadge(json: json.data)
    }

    public static func notifications(type: String, page: Int) async throws -> [JSON] {
        let json = try await client.get("/v6/notification/\(type)", ["page": String(page)])
        return json.data.array
    }

    public static func messages(page: Int) async throws -> [MessageItem] {
        let json = try await client.get("/v6/message/list", ["page": String(page)])
        return json.data.array.map { MessageItem(json: $0) }
    }

    // MARK: - History / collections

    public static func recentHistory(page: Int) async throws -> [HomeFeedRow] {
        let json = try await client.get("/v6/user/recentHistoryList", ["page": String(page)])
        return try rows(from: json.data.array)
    }

    public static func hitHistory(page: Int) async throws -> [HomeFeedRow] {
        let json = try await client.get("/v6/user/hitHistoryList", ["page": String(page)])
        return try rows(from: json.data.array)
    }

    public static func myCollections(page: Int) async throws -> [JSON] {
        let session = await client.sessionSnapshot()
        let json = try await client.get("/v6/collection/list", ["uid": session.uid, "page": String(page)])
        return json.data.array
    }

    // MARK: - Home "me" card

    public static func myPageCard() async throws -> JSON {
        let json = try await client.get("/v6/account/loadConfig", ["key": "my_page_card_config"])
        return json.data
    }

    // MARK: - Engagement lists

    /// Users who liked a dynamic (`/v6/feed/likeList`).
    public static func likeList(feedID: String, page: Int) async throws -> [UserBrief] {
        let json = try await client.get("/v6/feed/likeList", [
            "id": feedID,
            "listType": "lastupdate_desc",
            "page": String(page),
        ])
        return json.data.array.map { item in
            item.userInfo.exists ? UserBrief(json: item.userInfo) : UserBrief(json: item)
        }
    }

    /// Dynamics that reposted this one (`/v6/feed/forwardList`).
    public static func forwardList(feedID: String, page: Int, type: String = "feed") async throws -> [HomeFeedRow] {
        let json = try await client.get("/v6/feed/forwardList", [
            "id": feedID,
            "type": type,
            "page": String(page),
        ])
        return try rows(from: json.data.array)
    }

    /// Revision history of a dynamic (`/v6/feed/changeHistoryList`).
    public static func changeHistory(feedID: String) async throws -> [HomeFeedRow] {
        let json = try await client.get("/v6/feed/changeHistoryList", ["id": feedID])
        return try rows(from: json.data.array)
    }

    // MARK: - Collections (收藏夹)

    public static func collectionDetail(id: String) async throws -> CollectionItem {
        let json = try await client.get("/v6/collection/detail", ["id": id])
        return CollectionItem(json: json.data)
    }

    public static func collectionItems(id: String, page: Int) async throws -> [HomeFeedRow] {
        let json = try await client.get("/v6/collection/itemList", ["id": id, "page": String(page)])
        return try rows(from: json.data.array)
    }

    public static func followCollection(id: String, follow: Bool) async throws {
        _ = try await client.post(follow ? "/v6/collection/follow" : "/v6/collection/unFollow", ["id": id])
    }

    // MARK: - 看看号 (publisher accounts)

    public static func dyhDetail(id: String) async throws -> DyhItem {
        let json = try await client.get("/v6/dyh/detail", ["dyhId": id])
        return DyhItem(json: json.data)
    }

    public static func dyhArticles(id: String, page: Int, type: String = "all") async throws -> [HomeFeedRow] {
        let json = try await client.get("/v6/dyhArticle/list", [
            "dyhId": id,
            "type": type,
            "page": String(page),
        ])
        return try rows(from: json.data.array)
    }

    public static func followDyh(id: String, follow: Bool) async throws {
        _ = try await client.post(follow ? "/v6/dyh/follow" : "/v6/dyh/unFollow", ["dyhId": id])
    }

    // MARK: - 问答 / 投票

    public static func questionAnswers(id: String, page: Int, sort: String = "default") async throws -> [HomeFeedRow] {
        let json = try await client.get("/v6/question/answerList", [
            "id": id,
            "sort": sort,
            "page": String(page),
        ])
        return try rows(from: json.data.array)
    }

    public static func voteComments(fid: String, page: Int) async throws -> [HomeFeedRow] {
        let json = try await client.get("/v6/vote/commentList", ["fid": fid, "page": String(page)])
        return try rows(from: json.data.array)
    }

    // MARK: - Device timelines

    public static func deviceFeeds(tag: String, page: Int, listType: String = "lastupdate_desc") async throws -> [HomeFeedRow] {
        let json = try await client.get("/v6/topic/deviceFeedList", [
            "tag": tag,
            "page": String(page),
            "listType": listType,
            "blockStatus": "0",
        ])
        return try rows(from: json.data.array)
    }

    // MARK: - Write operations

    /// Reposts an existing dynamic. Coolapk expects `forwardid` plus the optional comment.
    public static func forwardFeed(id: String, message: String) async throws {
        var form: [String: String] = [
            "message": message,
            "type": "feed",
            "forwardid": id,
            "is_html_article": "0",
        ]
        if message.isEmpty { form["message"] = "转发动态" }
        _ = try await client.post("/v6/feed/createFeed", form)
    }

    public static func deleteFeed(id: String) async throws {
        _ = try await client.post("/v6/feed/delete", ["id": id])
    }

    public static func deleteFeedReply(id: String) async throws {
        _ = try await client.post("/v6/feed/deleteReply", ["id": id])
    }

    // MARK: - Mention helpers used by the composer

    public static func searchTags(keyword: String, page: Int = 1) async throws -> [TopicItem] {
        let json = try await client.get("/v6/feed/searchTag", ["q": keyword, "page": String(page)])
        return json.data.array.map { TopicItem(json: $0) }
    }

    public static func searchUsers(keyword: String, page: Int = 1) async throws -> [UserBrief] {
        let json = try await client.get("/v6/user/search", ["q": keyword, "page": String(page)])
        return json.data.array.map { UserBrief(json: $0) }
    }

    /// Dynamics a user liked; the endpoint requires a signed in session.
    public static func userLikeFeeds(uid: String, page: Int) async throws -> [HomeFeedRow] {
        let json = try await client.get("/v6/user/likeList", ["uid": uid, "page": String(page)])
        return try rows(from: json.data.array)
    }
}
