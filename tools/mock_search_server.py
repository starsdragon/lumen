"""Local SearXNG-shaped mock for UI verification of source citations."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs
import json

RESULTS = [
    {
        "title": "Anthropic兼容-Messages - 阿里云百炼",
        "url": "https://help.aliyun.com/zh/model-studio/anthropic-api-messages",
        "content": "阿里云百炼为华北2（北京）地域提供 Anthropic 兼容 Messages 接口，支持通过 x-api-key 或 Authorization Bearer 传入密钥。",
        "publishedDate": "2026-09-02T00:00:00Z",
    },
    {
        "title": "更多工具 - Alibaba Cloud Model Studio",
        "url": "https://help.aliyun.com/zh/model-studio/tools",
        "content": "Model Studio 的工具调用、联网搜索和文件解析能力说明，包含工作空间专属域名迁移提示。",
        "publishedDate": "2026-09-11T00:00:00Z",
    },
    {
        "title": "GLM 与 DeepSeek 定价对比：如何选择",
        "url": "https://example.com/blog/glm-vs-deepseek-pricing",
        "content": "对比 GLM 与 DeepSeek 的输入、输出与缓存价格，并给出按调用量和上下文长度选择模型的建议。",
        "publishedDate": "2026-10-12T00:00:00Z",
    },
    {
        "title": "OpenCode Go 订阅说明",
        "url": "https://opencode.ai/docs/go",
        "content": "OpenCode Go 使用 /zen/go/v1 端点，并在请求中携带 x-opencode-session 以优化路由与缓存。",
        "publishedDate": "2026-10-01T00:00:00Z",
    },
]


class Handler(BaseHTTPRequestHandler):
    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path != "/search":
            self.send_response(404)
            self._cors()
            self.end_headers()
            return
        query = parse_qs(parsed.query).get("q", [""])[0]
        payload = {
            "query": query,
            "number_of_results": len(RESULTS),
            "results": RESULTS,
        }
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self._cors()
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    server = ThreadingHTTPServer(("127.0.0.1", 8140), Handler)
    print("mock search listening on 127.0.0.1:8140")
    server.serve_forever()
