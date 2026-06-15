//
//  LocalProxyServer.swift
//  XYZW Game Manager - iOS 本地代理服务器
//
//  使用方法：
//  1. 将本文件拖入 Xcode 项目
//  2. 通过 SPM 添加 GCDWebServer: https://github.com/swisspol/GCDWebServer
//  3. 把 dist 文件夹拖入 Xcode (Create folder references, 蓝色文件夹)
//  4. 在 AppDelegate/SceneDelegate 中调用 LocalProxyServer.shared.start()
//
//  然后 WKWebView 加载 http://localhost:8080/index.html 即可

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
        // 假设 dist 文件夹以 folder reference 方式添加到 bundle
        guard let distPath = Bundle.main.path(forResource: "dist", ofType: nil) else {
            print("[XYZW] ⚠️ 未找到 dist 目录，请将 dist 文件夹拖入 Xcode (Create folder references)")
            return
        }
        
        // 添加静态文件处理器（所有非 /api/* 的请求走这里）
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
        // ⚠️ 长前缀放前面，先匹配
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
            // 匹配 /api/xxx/* 的所有请求
            let pattern = "^\(NSRegularExpression.escapedPattern(for: proxy.prefix))/.*$"
            
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
                    return GCDWebServerDataRequest(method: method, url: url, headers: path, path: path, query: query)
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
                guard proxies.contains(where: { path.hasPrefix($0.prefix) }) else { return nil }
                return GCDWebServerRequest(method: method, url: URL(string: "http://localhost")!, headers: nil, path: path, query: nil)
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
        // 构建目标 URL
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
        
        // 设置代理需要的请求头
        for (key, value) in proxy.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        
        // 传递原请求的 body
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
            
            let serverResponse: GCDWebServerDataResponse
            
            if let data = data {
                serverResponse = GCDWebServerDataResponse(data: data, contentType: "application/octet-stream")
                serverResponse.statusCode = httpResponse.statusCode
            } else {
                serverResponse = GCDWebServerDataResponse()
                serverResponse.statusCode = httpResponse.statusCode
            }
            
            // 添加 CORS 头
            serverResponse.setValue("*", forAdditionalHeader: "Access-Control-Allow-Origin")
            serverResponse.setValue("GET, POST, OPTIONS", forAdditionalHeader: "Access-Control-Allow-Methods")
            serverResponse.setValue("Content-Type, Authorization, X-Requested-With", forAdditionalHeader: "Access-Control-Allow-Headers")
            
            // 透传 Content-Type
            if let contentType = httpResponse.allHeaderFields["Content-Type"] as? String {
                serverResponse.contentType = contentType
            }
            
            completion(serverResponse)
        }
        task.resume()
    }
    
    private func errorResponse(_ message: String) -> GCDWebServerResponse {
        let json = #"{"error":"\#(message)"}"#
        let response = GCDWebServerDataResponse(
            jsonObject: ["error": message]
        ) ?? GCDWebServerDataResponse(text: json)
        response.statusCode = 500
        response.setValue("*", forAdditionalHeader: "Access-Control-Allow-Origin")
        return response
    }
}
