import urllib.request
import urllib.parse
import http.cookiejar
import re
import os
import subprocess
import time
import json
import asyncio
import base64
import websockets
from pypdf import PdfReader, PdfWriter

async def send_cdp(ws, method, params=None):
    call_id = int(time.time() * 1000) % 10000000
    msg = {"id": call_id, "method": method, "params": params or {}}
    await ws.send(json.dumps(msg))
    while True:
        resp = await ws.recv()
        data = json.loads(resp)
        if data.get("id") == call_id:
            if "error" in data:
                raise Exception(f"CDP error {method}: {data['error']}")
            return data.get("result", {})

async def convert_thread_to_1920_pdf():
    cj = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
        'Referer': 'https://www.4d4y.com/forum/logging.php?action=login',
    }
    
    print("[1/5] 登录论坛...")
    req = urllib.request.Request('https://www.4d4y.com/forum/logging.php?action=login', headers=headers)
    html = opener.open(req).read().decode('gbk', errors='ignore')
    formhash = re.search(r'name="formhash" value="([^"]+)"', html).group(1)
    sid = re.search(r'name="sid" value="([^"]+)"', html).group(1)
    
    login_url = 'https://www.4d4y.com/forum/logging.php?action=login&loginsubmit=yes'
    post_data = urllib.parse.urlencode({
        'sid': sid,
        'formhash': formhash,
        'referer': 'index.php',
        'loginfield': 'username',
        'username': 'helloearth',
        'password': 'xCxoYREojL6OoW',
        'questionid': '0',
        'answer': '',
        'cookietime': '315360000',
    }, encoding='gbk').encode('gbk')
    opener.open(urllib.request.Request(login_url, data=post_data, headers=headers))
    
    thread_base_url = 'https://www.4d4y.com/forum/viewthread.php?tid=3469094'
    req_th1 = urllib.request.Request(f"{thread_base_url}&page=1", headers=headers)
    page1_html = opener.open(req_th1).read().decode('gbk', errors='ignore')
    
    title_m = re.search(r'<title>(.*?)</title>', page1_html)
    clean_title = re.sub(r'[\/\\:\*\?"<>\|]', '_', title_m.group(1).replace(' - 4D4Y', '').strip() if title_m else '4D4Y_Thread')
    
    pages = set([1])
    for m in re.finditer(r'viewthread\.php\?[^"\']*page=(\d+)', page1_html):
        pages.add(int(m.group(1)))
    max_page = max(pages)
    print(f"   帖子: {clean_title}, 共 {max_page} 页")
    
    css_links = re.findall(r'<link[^>]+rel=["\']stylesheet["\'][^>]+href=["\']([^"\']+)["\']', page1_html)
    css_blocks = []
    for css_url in css_links:
        try:
            req_css = urllib.request.Request(css_url, headers={'User-Agent': headers['User-Agent'], 'Referer': thread_base_url})
            css_content = opener.open(req_css).read().decode('gbk', errors='ignore')
            css_blocks.append(f"<style>\n{css_content}\n</style>")
        except Exception:
            pass
            
    edge = r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
    port = 9444
    proc = subprocess.Popen([
        edge,
        '--headless',
        f'--remote-debugging-port={port}',
        '--disable-gpu',
        '--window-size=1920,1080',
        'about:blank'
    ])
    await asyncio.sleep(2)
    
    try:
        tabs = json.loads(urllib.request.urlopen(f'http://127.0.0.1:{port}/json').read())
        page_tabs = [t for t in tabs if t.get('type') == 'page']
        ws_url = page_tabs[0]['webSocketDebuggerUrl']
        
        async with websockets.connect(ws_url, max_size=100 * 1024 * 1024) as ws:
            await send_cdp(ws, "Page.enable")
            
            # 设置视口固定宽度 1920px
            await send_cdp(ws, "Emulation.setDeviceMetricsOverride", {
                "width": 1920,
                "height": 1080,
                "deviceScaleFactor": 1,
                "mobile": False
            })
            
            writer = PdfWriter()
            temp_pdf_files = []
            
            for p in range(1, max_page + 1):
                if p == 1:
                    p_html = page1_html
                else:
                    req_p = urllib.request.Request(f"{thread_base_url}&page={p}", headers=headers)
                    p_html = opener.open(req_p).read().decode('gbk', errors='ignore')
                    
                match_postlist = re.search(r'(<div[^>]*id="postlist"[^>]*>.*?)(?:<div class="pages"|</div>\s*<div id="quickpost")', p_html, re.DOTALL)
                if match_postlist:
                    content_part = match_postlist.group(1) + "</div>"
                else:
                    content_part = p_html
                    
                page_full_html = f"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>{clean_title} - 第{p}页</title>
{''.join(css_blocks)}
<style>
@page {{
    size: 20in auto;
    margin: 0 !important;
}}
html, body {{
    margin: 0 !important;
    padding: 0 !important;
    width: 1920px !important;
    background: #ffffff !important;
    text-align: left !important;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
}}
* {{
    text-align: left !important;
}}
.postauthor, .postauthor * {{
    text-align: left !important;
}}
#wrap, #postlist, .viewthread, .mainbox {{
    width: 1920px !important;
    box-sizing: border-box !important;
    margin: 0 !important;
    padding: 10px 30px !important;
    text-align: left !important;
}}
table, tbody, tr, td {{
    text-align: left !important;
}}
.postcontent, .postmessage, .t_msgfont, .t_msgfontfix, p, div, span, h1, h2, h3, h4 {{
    text-align: left !important;
    font-size: 16px !important;
    line-height: 1.8 !important;
}}
img {{
    max-width: 1800px !important;
    height: auto !important;
}}
.postactions, .modact, .pages, .pageback, #quickpost {{
    display: none !important;
}}
</style>
</head>
<body>
<div style="width: 1920px; box-sizing: border-box; background: #2B579A; color: #ffffff; padding: 14px 30px; font-size: 20px; font-weight: bold; text-align: left !important;">
    【第 {p} 页 / 共 {max_page} 页】 {clean_title}
</div>
{content_part}
</body>
</html>
"""
                temp_html_path = os.path.abspath(f"temp_p_{p}.html")
                with open(temp_html_path, "w", encoding="utf-8") as f:
                    f.write(page_full_html)
                    
                file_url = f"file:///{temp_html_path.replace(os.sep, '/')}"
                await send_cdp(ws, "Page.navigate", {"url": file_url})
                await asyncio.sleep(2)
                
                # 正确获取 document.documentElement.scrollHeight
                eval_res = await send_cdp(ws, "Runtime.evaluate", {
                    "expression": "Math.max(document.body.scrollHeight, document.documentElement.scrollHeight, 1080)"
                })
                total_height_px = eval_res.get("result", {}).get("value", 2000)
                
                # 宽度 1920px (20.0 英寸), 高度按帖子这一页全部内容完全展开的高度
                width_in = 20.0
                height_in = max(1.0, float(total_height_px) / 96.0)
                print(f"[2/5] 第 {p} / {max_page} 页: 测得内容高度 {total_height_px}px ({height_in:.2f}英寸)，生成单页完整PDF (0页眉页脚)...")
                
                print_res = await send_cdp(ws, "Page.printToPDF", {
                    "landscape": False,
                    "displayHeaderFooter": False,
                    "printBackground": True,
                    "paperWidth": width_in,
                    "paperHeight": height_in,
                    "marginTop": 0,
                    "marginBottom": 0,
                    "marginLeft": 0,
                    "marginRight": 0,
                    "preferCSSPageSize": False
                })
                
                pdf_bytes = base64.b64decode(print_res["data"])
                temp_pdf = f"temp_p_{p}.pdf"
                with open(temp_pdf, "wb") as pf:
                    pf.write(pdf_bytes)
                temp_pdf_files.append(temp_pdf)
                
                reader = PdfReader(temp_pdf)
                print(f"   第 {p} 页生成的 PDF 包含 {len(reader.pages)} 个物理页 (应为1页无断裂)")
                for page_obj in reader.pages:
                    writer.add_page(page_obj)
                    
            final_output_pdf = os.path.abspath("4D4Y_1920_Per_Thread_Page.pdf")
            with open(final_output_pdf, "wb") as out_f:
                writer.write(out_f)
                
            print(f"\n[3/5] 全部完成！最终 PDF 包含帖子对应的 {len(writer.pages)} 个完整分页：")
            final_reader = PdfReader(final_output_pdf)
            for idx, pg in enumerate(final_reader.pages):
                w_pt = float(pg.mediabox.width)
                h_pt = float(pg.mediabox.height)
                print(f"   页面 {idx+1}: 宽 {w_pt/72*96:.0f}px (1920px 电脑宽度), 高 {h_pt/72*96:.0f}px (贴合本页内容高度), 页眉页脚边距为 0")
                
            for tp in temp_pdf_files:
                if os.path.exists(tp):
                    os.remove(tp)
            for p in range(1, max_page + 1):
                th = f"temp_p_{p}.html"
                if os.path.exists(th):
                    os.remove(th)
                    
    finally:
        proc.terminate()

if __name__ == '__main__':
    asyncio.run(convert_thread_to_1920_pdf())
