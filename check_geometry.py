import asyncio
import json
import websockets
import subprocess
import time
import urllib.request

async def test():
    edge = r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
    proc = subprocess.Popen([edge, '--headless', '--remote-debugging-port=9922', 'about:blank'])
    await asyncio.sleep(1.5)
    try:
        tabs = json.loads(urllib.request.urlopen('http://127.0.0.1:9922/json').read())
        ws_url = [t for t in tabs if t.get('type') == 'page'][0]['webSocketDebuggerUrl']
        async with websockets.connect(ws_url) as ws:
            await ws.send(json.dumps({'id': 1, 'method': 'Page.navigate', 'params': {'url': 'file:///D:/project/D2PDF/temp_p_1.html'}}))
            await ws.recv()
            await asyncio.sleep(1)
            expr = """
            (function() {
                var pid = document.querySelector('table[id^="pid"]');
                var msg = document.querySelector('.t_msgfont');
                var postauthor = document.querySelector('.postauthor');
                var postcontent = document.querySelector('td.postcontent');
                return JSON.stringify({
                    windowWidth: window.innerWidth,
                    bodyWidth: document.body.getBoundingClientRect().width,
                    tableLeft: pid ? pid.getBoundingClientRect().left : null,
                    tableWidth: pid ? pid.getBoundingClientRect().width : null,
                    authorWidth: postauthor ? postauthor.getBoundingClientRect().width : null,
                    contentLeft: postcontent ? postcontent.getBoundingClientRect().left : null,
                    contentWidth: postcontent ? postcontent.getBoundingClientRect().width : null,
                    msgLeft: msg ? msg.getBoundingClientRect().left : null,
                    msgWidth: msg ? msg.getBoundingClientRect().width : null
                });
            })()
            """
            await ws.send(json.dumps({'id': 2, 'method': 'Runtime.evaluate', 'params': {'expression': expr}}))
            res = json.loads(await ws.recv())
            print('Layout geometry:', res['result']['result']['value'])
    finally:
        proc.terminate()

if __name__ == '__main__':
    asyncio.run(test())
