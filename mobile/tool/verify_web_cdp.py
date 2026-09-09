"""Installed headless Chrome verification over CDP; uses backend websockets."""
import argparse
import base64
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import time

from websockets.sync.client import connect


class Handler(SimpleHTTPRequestHandler):
    isolation_headers = True

    def end_headers(self):
        if self.isolation_headers:
            self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
            self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')
        super().end_headers()

    def log_message(self, *_):
        pass


class Browser:
    def __init__(self, chrome, profile):
        self.process = subprocess.Popen([
            chrome, '--headless=new', '--remote-debugging-port=0',
            f'--user-data-dir={profile}', '--no-first-run',
            '--no-default-browser-check', '--window-size=412,915', 'about:blank',
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
        port_file = Path(profile)/'DevToolsActivePort'
        for _ in range(150):
            if port_file.exists():
                break
            time.sleep(.1)
        port, path = port_file.read_text().splitlines()[:2]
        self.socket = connect(f'ws://127.0.0.1:{port}{path}', open_timeout=15)
        self.counter = 0
        self.session = None
        self.errors = []
        target = self.call('Target.createTarget', {'url': 'about:blank'})['targetId']
        self.session = self.call('Target.attachToTarget', {'targetId': target, 'flatten': True})['sessionId']
        for domain in ['Page', 'Runtime', 'Network']:
            self.call(domain+'.enable')
        self.call('Emulation.setDeviceMetricsOverride', {'width': 412, 'height': 915, 'deviceScaleFactor': 1, 'mobile': True})

    def call(self, method, params=None):
        self.counter += 1
        message = {'id': self.counter, 'method': method, 'params': params or {}}
        if self.session:
            message['sessionId'] = self.session
        self.socket.send(json.dumps(message))
        while True:
            result = json.loads(self.socket.recv(timeout=45))
            if result.get('method') == 'Runtime.exceptionThrown':
                self.errors.append(result['params'])
            if result.get('id') == self.counter:
                if 'error' in result:
                    raise RuntimeError(result['error'])
                return result.get('result', {})

    def evaluate(self, expression):
        result = self.call('Runtime.evaluate', {'expression': expression, 'awaitPromise': True, 'returnByValue': True})
        if 'exceptionDetails' in result:
            raise RuntimeError(result['exceptionDetails'])
        return result['result'].get('value')

    def wait(self, expression):
        end = time.monotonic()+35
        while time.monotonic() < end:
            if self.evaluate(expression):
                return
            time.sleep(.2)
        raise AssertionError(f'Timed out: {expression}; body={self.evaluate("document.body.textContent")}; errors={self.errors}')

    def navigate(self, url):
        result = self.call('Page.navigate', {'url': url})
        if result.get('errorText'):
            raise AssertionError(result)
        expected = url if '/' in url.split('://', 1)[1] else url+'/'
        self.wait(f'location.href === {json.dumps(expected)} && document.readyState === "complete"')

    def screenshot(self, path):
        image = self.call('Page.captureScreenshot', {'format': 'png'})
        path.write_bytes(base64.b64decode(image['data']))

    def close(self):
        try:
            self.call('Browser.close')
        except Exception:
            pass
        self.socket.close()
        try:
            self.process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.process.terminate()
            self.process.wait(timeout=10)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--web-dir', type=Path, required=True)
    parser.add_argument('--chrome', required=True)
    parser.add_argument('--output-directory', type=Path, required=True)
    parser.add_argument('--no-isolation-headers', action='store_true')
    args = parser.parse_args()
    Handler.isolation_headers = not args.no_isolation_headers
    server = ThreadingHTTPServer(('127.0.0.1', 0), partial(Handler, directory=str(args.web_dir.resolve())))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    base = f'http://127.0.0.1:{server.server_port}'
    browser = None
    try:
        with tempfile.TemporaryDirectory(prefix='zedbiz-chrome-verification-') as profile:
            try:
                browser = Browser(args.chrome, profile)
                browser.navigate(base)
                browser.wait('navigator.serviceWorker.controller !== null && document.querySelector("flutter-view") !== null')
                time.sleep(2)
                browser.screenshot(args.output_directory/'m8-web-startup.png')
                browser.navigate(base+'/storage-check.html')
                browser.wait('document.body.textContent.startsWith("Passed:")')
                print(browser.evaluate('document.body.textContent'), flush=True)
                browser.navigate(base+'/storage-check.html?phase=read')
                browser.wait('document.body.textContent.startsWith("Passed:")')
                assert not browser.errors, browser.errors
                browser.close()
                browser = None
                (Path(profile)/'DevToolsActivePort').unlink(missing_ok=True)
                browser = Browser(args.chrome, profile)
                browser.call('Network.emulateNetworkConditions', {'offline': True, 'latency': 0, 'downloadThroughput': 0, 'uploadThroughput': 0})
                browser.navigate(base+'/storage-check.html?phase=read')
                browser.wait('document.body.textContent.startsWith("Passed:")')
                print('Passed: browser process restart and offline SQLite/queue recovery.', flush=True)
                browser.navigate(base)
                browser.wait('document.querySelector("flutter-view") !== null')
                time.sleep(2)
                browser.screenshot(args.output_directory/'m8-web-offline-startup.png')
                assert not browser.errors, browser.errors
                print('Passed: offline application shell restart; no browser page errors.', flush=True)
            finally:
                if browser:
                    browser.close()
    finally:
        server.shutdown()


if __name__ == '__main__':
    main()
