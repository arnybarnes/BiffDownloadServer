import json
import os
import socket
import threading
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from uuid import uuid4


ROOT = Path(__file__).parent
WEB_DIR = ROOT / "web"
CONFIG_PATH = ROOT / "config.local.json"
SEARCH_RESULT_CACHE: dict[str, str] = {}


@dataclass
class ProviderConfig:
    provider: str
    base_url: str | None
    api_key: str | None
    username: str | None = None
    password: str | None = None


@dataclass
class DownloaderConfig:
    downloader: str
    rpc_url: str | None
    secret: str | None
    download_dir: str | None = None


def load_local_config() -> dict[str, Any]:
    if not CONFIG_PATH.exists():
        return {}
    return json.loads(CONFIG_PATH.read_text(encoding="utf-8"))


def get_service_config(service_name: str) -> tuple[str, int]:
    local_config = load_local_config()
    services = local_config.get("services", {})
    service_config = services.get(service_name, {})
    env_prefix = service_name.upper()
    host = os.getenv(f"{env_prefix}_HOST") or service_config.get("host") or "127.0.0.1"
    port_value = os.getenv(f"{env_prefix}_PORT") or service_config.get("port")
    default_port = 8789 if service_name == "web" else 8790
    return host, int(port_value or default_port)


def get_provider_config() -> ProviderConfig:
    local_config = load_local_config()
    provider_settings = local_config.get("providers", {})
    provider = (os.getenv("TORRENT_PROVIDER") or local_config.get("provider") or "mock").strip().lower() or "mock"

    if provider == "prowlarr":
        prowlarr_config = provider_settings.get("prowlarr", {})
        return ProviderConfig(
            provider=provider,
            base_url=os.getenv("PROWLARR_URL") or prowlarr_config.get("base_url"),
            api_key=os.getenv("PROWLARR_API_KEY") or prowlarr_config.get("api_key"),
            username=os.getenv("PROWLARR_USERNAME") or prowlarr_config.get("username"),
            password=os.getenv("PROWLARR_PASSWORD") or prowlarr_config.get("password"),
        )

    if provider == "jackett":
        jackett_config = provider_settings.get("jackett", {})
        return ProviderConfig(
            provider=provider,
            base_url=os.getenv("JACKETT_URL") or jackett_config.get("base_url"),
            api_key=os.getenv("JACKETT_API_KEY") or jackett_config.get("api_key"),
            username=os.getenv("JACKETT_USERNAME") or jackett_config.get("username"),
            password=os.getenv("JACKETT_PASSWORD") or jackett_config.get("password"),
        )

    return ProviderConfig(provider="mock", base_url=None, api_key=None)


def get_downloader_config() -> DownloaderConfig:
    local_config = load_local_config()
    downloader_settings = local_config.get("downloaders", {})
    downloader = (os.getenv("TORRENT_DOWNLOADER") or local_config.get("downloader") or "none").strip().lower() or "none"

    if downloader == "aria2":
        aria2_config = downloader_settings.get("aria2", {})
        return DownloaderConfig(
            downloader=downloader,
            rpc_url=os.getenv("ARIA2_RPC_URL") or aria2_config.get("rpc_url"),
            secret=os.getenv("ARIA2_RPC_SECRET") or aria2_config.get("secret"),
            download_dir=os.getenv("ARIA2_DOWNLOAD_DIR") or aria2_config.get("download_dir"),
        )

    return DownloaderConfig(downloader="none", rpc_url=None, secret=None)


def json_response(handler: BaseHTTPRequestHandler, status: int, payload: dict[str, Any]) -> None:
    body = json.dumps(payload, indent=2).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Access-Control-Allow-Origin", "*")
    handler.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
    handler.send_header("Access-Control-Allow-Headers", "Content-Type")
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(body)))
    handler.send_header("Cache-Control", "no-store")
    handler.end_headers()
    handler.wfile.write(body)


def normalize_result(item: dict[str, Any]) -> dict[str, Any]:
    indexer = item.get("indexer") or item.get("indexerName") or "Unknown"
    title = item.get("title") or item.get("sortTitle") or "Untitled"
    link = item.get("downloadUrl") or item.get("guid") or item.get("infoUrl") or item.get("magnetUrl")
    return {
        "title": title,
        "indexer": indexer,
        "size": item.get("size"),
        "seeders": item.get("seeders"),
        "leechers": item.get("leechers"),
        "publishDate": item.get("publishDate"),
        "link": link,
        "magnetUrl": item.get("magnetUrl"),
        "protocol": item.get("protocol"),
    }


def resolve_download_source(item: dict[str, Any]) -> str | None:
    link = item.get("link")
    magnet_url = item.get("magnetUrl")

    if isinstance(link, str) and link.startswith("magnet:?"):
        return link
    if isinstance(magnet_url, str) and magnet_url:
        return magnet_url
    if isinstance(link, str) and link:
        return link
    return None


def fetch_json(url: str, headers: dict[str, str]) -> Any:
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=15) as response:
        charset = response.headers.get_content_charset() or "utf-8"
        return json.loads(response.read().decode(charset))


def post_json(url: str, payload: dict[str, Any]) -> Any:
    body = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=body,
        headers={"Content-Type": "application/json", "Accept": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=15) as response:
        charset = response.headers.get_content_charset() or "utf-8"
        return json.loads(response.read().decode(charset))


def search_prowlarr(query: str, config: ProviderConfig) -> dict[str, Any]:
    if not config.base_url or not config.api_key:
        return {
            "provider": "prowlarr",
            "configured": False,
            "results": [],
            "message": "Set PROWLARR_URL and PROWLARR_API_KEY to enable live search.",
        }

    base_url = config.base_url.rstrip("/")
    params = urllib.parse.urlencode({"query": query, "type": "search", "limit": "25"})
    url = f"{base_url}/api/v1/search?{params}"
    headers = {"X-Api-Key": config.api_key, "Accept": "application/json"}

    try:
        payload = fetch_json(url, headers)
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        return {
            "provider": "prowlarr",
            "configured": True,
            "results": [],
            "message": f"Prowlarr returned HTTP {exc.code}.",
            "detail": detail[:500],
        }
    except urllib.error.URLError as exc:
        return {
            "provider": "prowlarr",
            "configured": True,
            "results": [],
            "message": f"Could not reach Prowlarr: {exc.reason}",
        }

    items = payload if isinstance(payload, list) else payload.get("records", [])
    return {
        "provider": "prowlarr",
        "configured": True,
        "results": [normalize_result(item) for item in items],
        "message": f"Found {len(items)} result(s) from Prowlarr.",
    }


def search_jackett(query: str, config: ProviderConfig) -> dict[str, Any]:
    if not config.base_url or not config.api_key:
        return {
            "provider": "jackett",
            "configured": False,
            "results": [],
            "message": "Set JACKETT_URL and JACKETT_API_KEY to enable Jackett support.",
        }

    return {
        "provider": "jackett",
        "configured": True,
        "results": [],
        "message": "Jackett wiring is not implemented yet. The API shape is ready for it.",
    }


def search_mock(query: str) -> dict[str, Any]:
    return {
        "provider": "mock",
        "configured": False,
        "results": [
            {
                "title": f"{query} Example Release 1080p",
                "indexer": "MockIndexer",
                "size": 1610612736,
                "seeders": 84,
                "leechers": 4,
                "publishDate": "2026-03-28T12:00:00Z",
                "link": "magnet:?xt=urn:btih:EXAMPLE1",
                "magnetUrl": "magnet:?xt=urn:btih:EXAMPLE1",
                "protocol": "torrent",
            },
            {
                "title": f"{query} Example Release 4K",
                "indexer": "MockIndexer",
                "size": 12884901888,
                "seeders": 25,
                "leechers": 1,
                "publishDate": "2026-03-27T19:30:00Z",
                "link": "magnet:?xt=urn:btih:EXAMPLE2",
                "magnetUrl": "magnet:?xt=urn:btih:EXAMPLE2",
                "protocol": "torrent",
            },
        ],
        "message": "Mock mode is active. Configure Prowlarr when you're ready for live results.",
    }


def perform_search(query: str) -> dict[str, Any]:
    config = get_provider_config()
    if config.provider == "prowlarr":
        return search_prowlarr(query, config)
    if config.provider == "jackett":
        return search_jackett(query, config)
    return search_mock(query)


def aria2_rpc_call(method: str, params: list[Any]) -> Any:
    config = get_downloader_config()
    if config.downloader != "aria2" or not config.rpc_url:
        raise RuntimeError("aria2 is not configured")

    rpc_params = list(params)
    if config.secret:
        rpc_params.insert(0, f"token:{config.secret}")

    payload = {
        "jsonrpc": "2.0",
        "id": "torrentsearch",
        "method": method,
        "params": rpc_params,
    }
    return post_json(config.rpc_url, payload)


def queue_download(uri: str) -> dict[str, Any]:
    config = get_downloader_config()
    if config.downloader != "aria2":
        return {
            "status": "error",
            "message": "No supported downloader is configured.",
        }

    options: dict[str, Any] = {}
    if config.download_dir:
        options["dir"] = config.download_dir

    try:
        payload = aria2_rpc_call("aria2.addUri", [[uri], options])
    except urllib.error.URLError as exc:
        return {
            "status": "error",
            "message": f"Could not reach aria2 RPC: {exc.reason}",
        }
    except RuntimeError as exc:
        return {
            "status": "error",
            "message": str(exc),
        }

    if "error" in payload:
        return {
            "status": "error",
            "message": payload["error"].get("message", "aria2 RPC error"),
            "detail": payload["error"],
        }

    gid = payload.get("result")
    return {
        "status": "ok",
        "message": "Download queued.",
        "downloader": "aria2",
        "gid": gid,
    }


def get_download_status(gid: str) -> dict[str, Any]:
    config = get_downloader_config()
    if config.downloader != "aria2":
        return {
            "status": "error",
            "message": "No supported downloader is configured.",
        }

    keys = [
        "gid",
        "status",
        "totalLength",
        "completedLength",
        "downloadSpeed",
        "dir",
        "files",
        "infoHash",
        "followedBy",
        "following",
        "bittorrent",
    ]
    try:
        payload = aria2_rpc_call("aria2.tellStatus", [gid, keys])
    except urllib.error.URLError as exc:
        return {
            "status": "error",
            "message": f"Could not reach aria2 RPC: {exc.reason}",
        }
    except RuntimeError as exc:
        return {
            "status": "error",
            "message": str(exc),
        }

    if "error" in payload:
        return {
            "status": "error",
            "message": payload["error"].get("message", "aria2 RPC error"),
            "detail": payload["error"],
        }

    root_result = payload.get("result", {})
    effective_result = root_result
    followed_by = root_result.get("followedBy") or []
    if followed_by:
        try:
            follow_payload = aria2_rpc_call("aria2.tellStatus", [followed_by[0], keys])
            if "result" in follow_payload:
                effective_result = follow_payload["result"]
        except (urllib.error.URLError, RuntimeError):
            pass

    files = effective_result.get("files", [])
    primary_path = files[0].get("path") if files else None
    torrent_info = effective_result.get("bittorrent", {}).get("info", {})
    return {
        "status": "ok",
        "downloader": "aria2",
        "download": {
            "requestedGid": root_result.get("gid"),
            "gid": effective_result.get("gid"),
            "state": effective_result.get("status"),
            "infoHash": effective_result.get("infoHash"),
            "totalBytes": int(effective_result.get("totalLength", "0")),
            "completedBytes": int(effective_result.get("completedLength", "0")),
            "downloadSpeedBytesPerSecond": int(effective_result.get("downloadSpeed", "0")),
            "directory": effective_result.get("dir"),
            "primaryPath": primary_path,
            "name": torrent_info.get("name"),
            "metadataGid": root_result.get("gid") if root_result.get("gid") != effective_result.get("gid") else None,
            "followedBy": followed_by,
        },
    }


def build_api_health_payload() -> dict[str, Any]:
    config = get_provider_config()
    return {
        "status": "ok",
        "provider": config.provider,
        "configured": bool(config.base_url and config.api_key) if config.provider != "mock" else False,
    }


def build_api_v1_health_payload() -> dict[str, Any]:
    config = get_provider_config()
    downloader = get_downloader_config()
    return {
        "status": "ok",
        "service": "torrentsearch-api",
        "version": "v1",
        "provider": {
            "name": config.provider,
            "configured": bool(config.base_url and config.api_key) if config.provider != "mock" else False,
        },
        "downloader": {
            "name": downloader.downloader,
            "configured": bool(downloader.rpc_url) if downloader.downloader != "none" else False,
        },
    }


def get_local_ipv4_addresses() -> list[str]:
    addresses: set[str] = set()
    hostname = socket.gethostname()

    try:
        for info in socket.getaddrinfo(hostname, None, socket.AF_INET, socket.SOCK_STREAM):
            address = info[4][0]
            if not address.startswith("127.") and not address.startswith("169.254."):
                addresses.add(address)
    except socket.gaierror:
        pass

    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
            probe.connect(("8.8.8.8", 80))
            address = probe.getsockname()[0]
            if not address.startswith("127."):
                addresses.add(address)
    except OSError:
        pass

    return sorted(addresses)


def ip_priority(address: str) -> tuple[int, str]:
    if address.startswith("192.168."):
        return (0, address)
    if address.startswith("172."):
        try:
            second_octet = int(address.split(".")[1])
            if 16 <= second_octet <= 31:
                return (1, address)
        except (IndexError, ValueError):
            pass
    if address.startswith("10."):
        return (2, address)
    return (3, address)


def build_api_v1_system_payload() -> dict[str, Any]:
    web_host, web_port = get_service_config("web")
    api_host, api_port = get_service_config("api")
    addresses = get_local_ipv4_addresses()
    preferred_ip = sorted(addresses, key=ip_priority)[0] if addresses else None
    return {
        "status": "ok",
        "system": {
            "hostname": socket.gethostname(),
            "lanIPv4": addresses,
            "preferredLanIp": preferred_ip,
            "web": {
                "host": web_host,
                "port": web_port,
                "localUrl": f"http://127.0.0.1:{web_port}/",
            },
            "api": {
                "host": api_host,
                "port": api_port,
                "localUrl": f"http://127.0.0.1:{api_port}",
                "lanUrl": f"http://{preferred_ip}:{api_port}" if preferred_ip else None,
            },
        },
    }


def build_api_v1_search_payload(query: str) -> dict[str, Any]:
    raw = perform_search(query)
    items = raw.get("results", [])
    response_items = []
    for item in items:
        source_uri = resolve_download_source(item)
        result_id = uuid4().hex
        if source_uri:
            SEARCH_RESULT_CACHE[result_id] = source_uri

        response_items.append(
            {
                "resultId": result_id,
                "title": item.get("title"),
                "indexer": item.get("indexer"),
                "sizeBytes": item.get("size"),
                "seeders": item.get("seeders"),
                "leechers": item.get("leechers"),
                "publishedAt": item.get("publishDate"),
                "protocol": item.get("protocol"),
                "hasSource": bool(source_uri),
            }
        )

    return {
        "status": "ok",
        "query": query,
        "message": raw.get("message"),
        "provider": raw.get("provider"),
        "count": len(response_items),
        "items": response_items,
    }


class ApiHandler(BaseHTTPRequestHandler):
    def do_OPTIONS(self) -> None:
        self.send_response(HTTPStatus.NO_CONTENT)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def read_json_body(self) -> dict[str, Any]:
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0:
            return {}
        body = self.rfile.read(length).decode("utf-8")
        return json.loads(body) if body else {}

    def do_GET(self) -> None:
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/api/health":
            json_response(self, HTTPStatus.OK, build_api_health_payload())
            return

        if parsed.path == "/api/v1/health":
            json_response(self, HTTPStatus.OK, build_api_v1_health_payload())
            return

        if parsed.path == "/api/v1/system":
            json_response(self, HTTPStatus.OK, build_api_v1_system_payload())
            return

        if parsed.path in {"/api/search", "/api/v1/search"}:
            params = urllib.parse.parse_qs(parsed.query)
            query = (params.get("q") or [""])[0].strip()
            if not query:
                json_response(self, HTTPStatus.BAD_REQUEST, {"error": "Missing query parameter: q"})
                return

            if parsed.path == "/api/v1/search":
                json_response(self, HTTPStatus.OK, build_api_v1_search_payload(query))
            else:
                json_response(self, HTTPStatus.OK, perform_search(query))
            return

        if parsed.path.startswith("/api/v1/downloads/"):
            gid = parsed.path.rsplit("/", 1)[-1].strip()
            if not gid:
                json_response(self, HTTPStatus.BAD_REQUEST, {"error": "Missing download id"})
                return

            payload = get_download_status(gid)
            status_code = HTTPStatus.OK if payload.get("status") == "ok" else HTTPStatus.BAD_GATEWAY
            json_response(self, status_code, payload)
            return

        json_response(self, HTTPStatus.NOT_FOUND, {"error": "Not found"})

    def do_POST(self) -> None:
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path != "/api/v1/downloads":
            json_response(self, HTTPStatus.NOT_FOUND, {"error": "Not found"})
            return

        try:
            payload = self.read_json_body()
        except json.JSONDecodeError:
            json_response(self, HTTPStatus.BAD_REQUEST, {"error": "Invalid JSON body"})
            return

        result_id = (payload.get("resultId") or "").strip()
        uri = SEARCH_RESULT_CACHE.get(result_id, "").strip() if result_id else ""
        if not uri:
            uri = (payload.get("sourceUrl") or payload.get("downloadUrl") or payload.get("magnetUri") or "").strip()
        if not uri:
            json_response(
                self,
                HTTPStatus.BAD_REQUEST,
                {"error": "Provide one of: resultId, sourceUrl, downloadUrl, magnetUri"},
            )
            return

        result = queue_download(uri)
        status_code = HTTPStatus.ACCEPTED if result.get("status") == "ok" else HTTPStatus.BAD_GATEWAY
        json_response(self, status_code, result)

    def log_message(self, format: str, *args: Any) -> None:
        print(f"api {self.address_string()} - {format % args}")


class WebHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args: Any, **kwargs: Any) -> None:
        super().__init__(*args, directory=str(WEB_DIR), **kwargs)

    def log_message(self, format: str, *args: Any) -> None:
        print(f"web {self.address_string()} - {format % args}")


def serve(server: ThreadingHTTPServer, label: str) -> None:
    host, port = server.server_address
    print(f"{label} server listening on http://{host}:{port}")
    server.serve_forever()


def main() -> None:
    web_host, web_port = get_service_config("web")
    api_host, api_port = get_service_config("api")

    web_server = ThreadingHTTPServer((web_host, web_port), WebHandler)
    api_server = ThreadingHTTPServer((api_host, api_port), ApiHandler)

    web_thread = threading.Thread(target=serve, args=(web_server, "Web"), daemon=True)
    api_thread = threading.Thread(target=serve, args=(api_server, "API"), daemon=True)

    web_thread.start()
    api_thread.start()

    try:
        web_thread.join()
        api_thread.join()
    except KeyboardInterrupt:
        web_server.shutdown()
        api_server.shutdown()


if __name__ == "__main__":
    main()
