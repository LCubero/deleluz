"""Serve the development webapp and its lab imports without browser caching."""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class NoCacheHandler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('port', type=int, nargs='?', default=8000)
    handler = partial(NoCacheHandler, directory=Path(__file__).resolve().parents[1])
    with ThreadingHTTPServer(('127.0.0.1', parser.parse_args().port), handler) as server:
        server.serve_forever()
