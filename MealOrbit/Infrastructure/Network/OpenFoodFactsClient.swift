import Foundation

/// Onion ring: Infrastructure / Network.
/// Mirrors Open Food Facts JSON. Never decoded into domain types directly.
struct SearchDocumentDTO: Decodable, Sendable {
    var products: [ProductDTO]?
}

struct ProductDocumentDTO: Decodable, Sendable {
    var status: Int?
    var product: ProductDTO?
}

struct ProductDTO: Decodable, Sendable {
    var code: FlexibleString?
    var productName: String?
    var genericName: String?
    var brands: String?
    var imageFrontSmallURL: String?
    var imageSmallURL: String?
    var nutriments: NutrimentDTO?

    enum CodingKeys: String, CodingKey {
        case code
        case productName = "product_name"
        case genericName = "generic_name"
        case brands
        case imageFrontSmallURL = "image_front_small_url"
        case imageSmallURL = "image_small_url"
        case nutriments
    }

    func mappedPayload() -> OrbitPayload? {
        let name = firstNonEmpty(productName, genericName, brands)
        guard let name else { return nil }
        let barcode = code?.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !barcode.isEmpty else { return nil }
        let kcal = TelemetryService.kcal100(
            energyKcal: nutriments?.energyKcal100g?.value,
            energyKj: nutriments?.energy100g?.value
        )
        return OrbitPayload(
            barcode: barcode,
            name: name,
            brand: brands ?? "",
            mass: PayloadMass(
                kcal100: kcal,
                protein100: nutriments?.proteins100g?.value,
                carbs100: nutriments?.carbohydrates100g?.value,
                fat100: nutriments?.fat100g?.value
            ),
            imageURL: imageFrontSmallURL ?? imageSmallURL,
            bundledAsset: nil,
            refreshedAt: Date()
        )
    }

    private func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            if let value {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }
}

struct NutrimentDTO: Decodable, Sendable {
    var energyKcal100g: FlexibleDouble?
    var energy100g: FlexibleDouble?
    var proteins100g: FlexibleDouble?
    var carbohydrates100g: FlexibleDouble?
    var fat100g: FlexibleDouble?

    enum CodingKeys: String, CodingKey {
        case energyKcal100g = "energy-kcal_100g"
        case energy100g = "energy_100g"
        case proteins100g = "proteins_100g"
        case carbohydrates100g = "carbohydrates_100g"
        case fat100g = "fat_100g"
    }
}

/// Accepts a JSON number or a numeric string without trapping.
struct FlexibleDouble: Decodable, Sendable {
    var value: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
            return
        }
        if let number = try? container.decode(Double.self) {
            value = number.isFinite ? number : nil
            return
        }
        if let number = try? container.decode(Int.self) {
            value = Double(number)
            return
        }
        if let text = try? container.decode(String.self) {
            let normalised = text.replacingOccurrences(of: ",", with: ".")
            value = Double(normalised)
            return
        }
        value = nil
    }
}

/// Accepts a JSON string or a JSON number for `code`.
struct FlexibleString: Decodable, Sendable {
    var value: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
            return
        }
        if let text = try? container.decode(String.self) {
            value = text
            return
        }
        if let number = try? container.decode(Int.self) {
            value = String(number)
            return
        }
        if let number = try? container.decode(Double.self) {
            value = String(Int(number))
            return
        }
        value = nil
    }
}

/// Onion ring: Infrastructure / Network.
/// Owns both Open Food Facts endpoints. 15 s timeout, one retry on transport.
actor TelemetryCatalogClient: CatalogGateway {
    static let searchPageSize = 24
    static let userAgent = "MealOrbit/1.0 (iOS; +https://mealorbit.pro)"

    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 15
            configuration.httpAdditionalHeaders = ["User-Agent": Self.userAgent]
            self.session = URLSession(configuration: configuration)
        }
        self.decoder = JSONDecoder()
    }

    func search(terms: String) async throws -> [OrbitPayload] {
        var components = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")
        components?.queryItems = [
            URLQueryItem(name: "search_terms", value: terms),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: String(Self.searchPageSize))
        ]
        guard let url = components?.url else { throw CatalogFault.transport }
        let data = try await data(from: url, retryOnNotFound: false)
        let document: SearchDocumentDTO
        do {
            document = try decoder.decode(SearchDocumentDTO.self, from: data)
        } catch {
            throw CatalogFault.decoding
        }
        return (document.products ?? []).compactMap { $0.mappedPayload() }
    }

    func fetch(barcode: String) async throws -> OrbitPayload {
        guard let encoded = barcode.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(encoded).json") else {
            throw CatalogFault.transport
        }
        let data = try await data(from: url, retryOnNotFound: false)
        let document: ProductDocumentDTO
        do {
            document = try decoder.decode(ProductDocumentDTO.self, from: data)
        } catch {
            throw CatalogFault.decoding
        }
        if document.status == 0 {
            throw CatalogFault.notFound
        }
        guard let payload = document.product?.mappedPayload() else {
            throw CatalogFault.notFound
        }
        return payload
    }

    private func data(from url: URL, retryOnNotFound: Bool) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        var lastFault: CatalogFault = .transport
        for attempt in 0...1 {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw CatalogFault.transport }
                if http.statusCode == 404 {
                    throw CatalogFault.notFound
                }
                if (500...599).contains(http.statusCode) || http.statusCode == 429 {
                    lastFault = .transport
                    if attempt == 0 { continue }
                    throw CatalogFault.transport
                }
                guard (200...299).contains(http.statusCode) else { throw CatalogFault.transport }
                return data
            } catch is CancellationError {
                throw CatalogFault.cancelled
            } catch let fault as CatalogFault {
                if fault == .notFound { throw fault }
                lastFault = fault
                if attempt == 0 { continue }
                throw fault
            } catch let urlError as URLError where urlError.code == .cancelled {
                throw CatalogFault.cancelled
            } catch {
                lastFault = .transport
                if attempt == 0 { continue }
                throw CatalogFault.transport
            }
        }
        throw lastFault
    }
}
