//
//  LocalProxyServer.swift
//  XYZW Game Manager - iOS 本地代理服务器
//

import Foundation
import GCDWebServer

final class LocalProxyServer {
    static let shared = LocalProxyServer()
    
    private let server = GCDWebServer()
    private let port: UInt = 8080
    
    // MARK: - 启动服务器
    
    func start() {
        setupStaticFiles()
        setupProxies()
        
        server.start(withPort: port, bonjourName: nil)
        print("[XYZW] 本地服务器已启动: http://localhost:\(port)")
    }
    
    func stop() {
        server.stop()
    }
    
    // MARK: - 静态文件服务（托管 dist 目录）
    
    private func setupStaticFiles() {
        guard let distPath = Bundle.main.path(forResource: "dist", ofType: nil) else {
            print("[XYZW] ⚠️ 未找到 dist 目录，请将 dist 文件夹拖入 Xcode (Create folder references)")
            return
        }
        
        server.addGETHandler(forBasePath: "/", 
                             directoryPath: distPath, 
                             indexFilename: "index.html", 
                             cacheAge: 0, 
                             allowRangeRequests: true)
        
        print("[XYZW] 静态文件目录: \(distPath)")
    }
    
    // MARK: - 代理配置
    
    private struct ProxyConfig {
        let prefix: String
        let target: String
        let headers: [String: String]
    }
    
    private let proxies: [ProxyConfig] = [
        ProxyConfig(
            prefix: "/api/weixin-long",
            target: "https://long.open.weixin.qq.com",
            headers: [
                "User-Agent": "Mozilla/5.0 (Linux; Android 7.0; Mi-4c Build/NRD90M; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/53.0.2785.49 Mobile MQQBrowser/6.2 TBS/043632 Safari/537.36 MicroMessenger/6.6.1.1220(0x26060135) NetType/WIFI Language/zh_CN",
                "Accept": "*/*",
                "Referer": "https://open.weixin.qq.com/"
            ]
        ),
        ProxyConfig(
            prefix: "/api/weixin",
            target: "https://open.weixin.qq.com",
            headers: [
                "User-Agent": "Mozilla/5.0 (Linux; Android 7.0; Mi-4c Build/NRD90M; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/53.0.2785.49 Mobile MQQBrowser/6.2 TBS/043632 Safari/537.36 MicroMessenger/6.6.1.1220(0x26060135) NetType/WIFI Language/zh_CN",
                "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
                "Referer": "https://open.weixin.qq.com/"
            ]
        ),
        ProxyConfig(
            prefix: "/api/hortor",
            target: "https://comb-platform.hortorgames.com",
            headers: [
                "User-Agent": "Mozilla/5.0 (Linux; Android 12; 23117RK66C Build/V417IR; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/95.0.4638.74 Mobile Safari/537.36",
                "Accept": "*/*",
                "Host": "comb-platform.hortorgames.com",
                "Connection": "keep-alive",
                "Content-Type": "text/plain; charset=utf-8",
                "Origin": "https://open.weixin.qq.com",
                "Referer": "https://open.weixin.qq.com/"
            ]
        )
    ]
    
    // MARK: - 注册所有代理路由
    
    private func setupProxies() {
        for proxy in proxies {
            // GET 请求
            server.addHandler(
                match: { (method, url, headers, path, query) -> GCDWebServerRequest? in
                    guard method == "GET" else { return nil }
                    guard path.hasPrefix(proxy.prefix) else { return nil }
                    return GCDWebServerDataRequest(method: method, url: url, headers: headers, path: path, query: query)
                },
                asyncProcessBlock: { [weak self] request, completion in
                    self?.handleProxy(request: request, proxy: proxy, completion: completion)
                }
            )
            
            // POST 请求
            server.addHandler(
                match: { (method, url, headers, path, query) -> GCDWebServerRequest? in
                    guard method == "POST" else { return nil }
                    guard path.hasPrefix(proxy.prefix) else { return nil }
                    return GCDWebServerDataRequest(method: method, url: url, headers: headers, path: path, query: query)
                },
                asyncProcessBlock: { [weak self] request, completion in
                    self?.handleProxy(request: request, proxy: proxy, completion: completion)
                }
            )
            
            print("[XYZW] 代理已注册: \(proxy.prefix) → \(proxy.target)")
        }
        
        // OPTIONS 预检请求
        server.addHandler(
            match: { (method, _, _, path, _) -> GCDWebServerRequest? in
                guard method == "OPTIONS" else { return nil }
                guard self.proxies.contains(where: { path.hasPrefix($0.prefix) }) else { return nil }
                return GCDWebServerRequest(method: method, url: URL(string: "http://localhost")!, headers: [:], path: path, query: nil)
            },
            processBlock: { _ in
                let response = GCDWebServerResponse()
                response.setValue("*", forAdditionalHeader: "Access-Control-Allow-Origin")
                response.setValue("GET, POST, OPTIONS", forAdditionalHeader: "Access-Control-Allow-Methods")
                response.setValue("Content-Type, Authorization, X-Requested-With", forAdditionalHeader: "Access-Control-Allow-Headers")
                response.statusCode = 204
                return response
            }
        )
    }
    
    // MARK: - 代理请求处理
    
    private func handleProxy(
        request: GCDWebServerRequest,
        proxy: ProxyConfig,
        completion: @escaping (GCDWebServerResponse?) -> Void
    ) {
        let targetPath = request.path.replacingOccurrences(of: proxy.prefix, with: "")
        var targetURLString = proxy.target + (targetPath.isEmpty ? "/" : targetPath)
        if let query = request.query, !query.isEmpty {
            targetURLString += "?\(query)"
        }
        
        guard let targetURL = URL(string: targetURLString) else {
            print("[XYZW] ❌ 无效的目标 URL: \(targetURLString)")
            completion(self.errorResponse("Invalid target URL"))
            return
        }
        
        var urlRequest = URLRequest(url: targetURL)
        urlRequest.httpMethod = request.method
        
        for (key, value) in proxy.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        
        if let dataRequest = request as? GCDWebServerDataRequest {
            urlRequest.httpBody = dataRequest.data
        }
        
        print("[XYZW] → \(request.method) \(targetURLString)")
        
        let task = URLSession.shared.dataTask(with: urlRequest) { data, response, error in
            if let error = error {
                print("[XYZW] ❌ 代理请求失败: \(error.localizedDescription)")
                completion(self.errorResponse(error.localizedDescription))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(self.errorResponse("No response"))
                return
            }
            
            print("[XYZW] ← \(httpResponse.statusCode) (\(data?.count ?? 0) bytes)")
            
            let contentType = httpResponse.allHeaderFields["Content-Type"] as? String ?? "application/octet-stream"
            let serverResponse = GCDWebServerDataResponse(data: data ?? Data(), contentType: contentType)
            
            serverResponse.statusCode = httpResponse.statusCode
            
            // 添加 CORS 头
            serverResponse.setValue("*", forAdditionalHeader: "Access-Control-Allow-Origin")
            serverResponse.setValue("GET, POST, OPTIONS", forAdditionalHeader: "Access-Control-Allow-Methods")
            serverResponse.setValue("Content-Type, Authorization, X-Requested-With", forAdditionalHeader: "Access-Control-Allow-Headers")
            
            completion(serverResponse)
        }
        task.resume()
    }
    
    private func errorResponse(_ message: String) -> GCDWebServerResponse {
        if let response = GCDWebServerDataResponse(jsonObject: ["error": message]) {
            response.statusCode = 500
            response.setValue("*", forAdditionalHeader: "Access-Control-Allow-Origin")
            return response
        }
        let fallback = GCDWebServerDataResponse(text: "{\"error\":\"\(message)\"}")
        fallback?.statusCode = 500
        fallback?.setValue("*", forAdditionalHeader: "Access-Control-Allow-Origin")
        return fallback ?? GCDWebServerResponse(statusCode: 500)
    }
}
