//
//  AppleReviewComments.swift
//  AppleReviewComments
//
//  Created by Praveen Prabhakar on 20/08/20.
//  Copyright © 2020 Praveen Prabhakar. All rights reserved.
//

import Foundation

enum NetworkError: Error {
    case badURL, invalidData, decoderData, noNextPage
}

struct AttributesModel: Decodable {
    static let invalidPage = UInt(0)
    enum LinkRel: String, Codable {
        case current = "self", alternate, first, last, previous, next
    }
    var type: String?
    var rel: LinkRel?
    var href: String?
    var term: String?
    var label: String?

    func pageNo() -> UInt {
        guard let urlString = href, let pageNo = URL(string: urlString)?.pathComponents
            .filter ({ $0.hasPrefix("page=") }).first?
            .split(separator: "=").last?.description else {
                return Self.invalidPage
        }
        return UInt(pageNo) ?? Self.invalidPage
    }
}

struct ReviewEntryModel: Decodable {
    var author: AuthorModel?

    var identifer: String?
    var version: String?
    var rating: String?
    var title: String?
    var voteSum: String?
    var voteCount: String?
    var content: ContentModel?
    var contentType: ContentModel?
    var link: ContentModel?

    private enum CodingKeys: String, CodingKey {
        case author, content, link, label, title
        case identifer = "id"
        case version = "im:version"
        case rating = "im:rating"
        case voteSum = "im:voteSum"
        case voteCount = "im:voteCount"
        case contentType = "im:contentType"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        author = try? container.decode(AuthorModel.self, forKey: .author)
        identifer = try? container.decode(CodingKeys.self, forKey: .identifer, subKey: .label)
        version = try? container.decode(CodingKeys.self, forKey: .version, subKey: .label)
        rating = try? container.decode(CodingKeys.self, forKey: .rating, subKey: .label)
        title = try? container.decode(CodingKeys.self, forKey: .title, subKey: .label)
        voteSum = try? container.decode(CodingKeys.self, forKey: .voteSum, subKey: .label)
        voteCount = try? container.decode(CodingKeys.self, forKey: .voteCount, subKey: .label)
        contentType = try? container.decode(ContentModel.self, forKey: .contentType)
        content = try? container.decode(ContentModel.self, forKey: .content)
        link = try? container.decode(ContentModel.self, forKey: .link)
    }

    struct ContentModel: Decodable {
        var label: String?
        var attributes: AttributesModel?
    }

    struct AuthorModel: Decodable {
        var name: String?
        var uri: String?
        var label: String?

        private enum CodingKeys: String, CodingKey {
            case name, uri, label
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(CodingKeys.self, forKey: .name, subKey: .label)
            uri = try container.decode(CodingKeys.self, forKey: .uri, subKey: .label)
            label = try container.decode(String.self, forKey: .label)
        }
    }
}

struct AppReviewsModel: Decodable {

    struct LinkAttribute: Decodable {
        var attributes: AttributesModel?
    }
    var entry: [ReviewEntryModel]?
    var link = [AttributesModel]()
    var updated: Date?
    var rights: String?

    private enum CodingKeys: String, CodingKey {
        case updated, rights, entry, link, attributes,label
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entry = try? container.decode([ReviewEntryModel].self, forKey: .entry)
        updated = try? container.decode(CodingKeys.self, forKey: .updated, subKey: .label)
        rights = try? container.decode(CodingKeys.self, forKey: .rights, subKey: .label)

        let links = try? container.decode([LinkAttribute].self, forKey: .link)
        links?.forEach { obj in
            if let attributes = obj.attributes {
                link.append(attributes)
            }
        }
    }

    func nextPageURL() -> URL? {
        guard
            let currentLink = link.filter({ $0.rel == .current }).first,
            let nextLink = link.filter({ $0.rel == .next }).first else {
                return nil
        }
        // Check if it has next page
        guard nextLink.pageNo() > currentLink.pageNo(), let urlString = nextLink.href else {
                return nil
        }
        return URL(string: urlString)
    }
}

struct ReviewResponseModel: Decodable {
    var feed: AppReviewsModel?

    private enum CodingKeys: String, CodingKey {
        case feed
    }

    static func decode(_ data: Data) throws -> AppReviewsModel? {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let comments = try decoder.decode(ReviewResponseModel.self, from: data)
            return comments.feed
        } catch {
            print("Unable to parse resposne as JSON data", error)
            if let reviewsModel = try? xmlDecode(data) {
                return reviewsModel
            }
            throw NetworkError.decoderData
        }
    }

    static func xmlDecode(_ data: Data) throws -> AppReviewsModel? {
       print("In Progress")
        return nil
    }
}

extension KeyedDecodingContainer {
    func decode<T: Decodable, NestedKey: CodingKey>(_ keyType: NestedKey.Type, forKey key: Self.Key, subKey: NestedKey) throws -> T? {
        let object = try nestedContainer(keyedBy: keyType.self, forKey: key)
        return try object.decode(T.self, forKey: subKey)
    }
}

enum ReviewComments {
    typealias ReviewCompletionBlock = (Result<AppReviewsModel, NetworkError>?) -> Void

    static func loadReviewComments(fileName: String, type: String = "json", bundle: Bundle = Bundle.main) throws -> AppReviewsModel? {
        let data = Data.dataFromFile(fileName: fileName, ofType: type, bundle: bundle)
        let reviewComments: AppReviewsModel? = try ReviewResponseModel.decode(data)
        return reviewComments
    }

    static func fetchReviews(app: String, country: String, pageNo: String, format: String = "json", completionBlock: ReviewCompletionBlock?) {
        guard let url = URL(string: "https://itunes.apple.com/rss/customerreviews/page=\(pageNo)/id=\(app)/\(format)?l=en&cc=\(country)") else {
            print("Invalid Review URL Generation")
            completionBlock?(.failure(.badURL))
            return
        }
        fetchReview(url: url, completionBlock: completionBlock)
    }

    static func fetchNextReviewPage(app: AppReviewsModel, completionBlock: ReviewCompletionBlock?) {
        guard let url = app.nextPageURL() else {
            print("No page to update")
            completionBlock?(.failure(.noNextPage))
            return
        }
        fetchReview(url: url, completionBlock: completionBlock)
    }

    private static func fetchReview(url: URL, completionBlock: ReviewCompletionBlock?) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        NetworkManager.fetchData(with: request) { data, response, error in
            // Check for error
            let parsingError = error
            guard let data = data, error == nil else {
                print("error=\(String(describing: parsingError))")
                completionBlock?(.failure(.invalidData))
                return
            }
            // Parse Data to ReviewModel
            guard let comments = try? ReviewResponseModel.decode(data) else {
                print("Data: ", String(data: data, encoding: .utf8) ?? "")
                completionBlock?(.failure(.decoderData))
                return
            }
            completionBlock?(.success(comments))
        }
    }
}

class NetworkManager {
    static let session = URLSession(configuration: .default)
    typealias NetworkCompletionBlock = (Result<Data, NetworkError>?) -> Void

    class func fetchData(with request: URLRequest, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) {
        session.dataTask(with: request, completionHandler: completionHandler).resume()
    }
}

extension Data {
    static func dataFromFile(fileName: String, ofType: String, bundle: Bundle) -> Data {
        if let path = bundle.path(forResource: fileName, ofType: ofType) {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
                return data
            } catch {
                print("dataFromFile \(fileName) not found")
                return Data()
            }
        }
        print("dataFromFile \(fileName) not found")
        return Data()
    }
}
