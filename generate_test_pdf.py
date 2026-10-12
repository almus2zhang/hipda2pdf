import urllib.request
import urllib.parse
import http.cookiejar
import re
import os
import base64

def fetch_complete_thread_to_pdf():
    cj = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
        'Referer': 'https://www.4d4y.com/forum/logging.php?action=login',
    }
    
    print("[1/5] 正在访问登录页以获取安全令牌...")
    req = urllib.request.Request('https://www.4d4y.com/forum/logging.php?action=login', headers=headers)
    html = opener.open(req).read().decode('gbk', errors='ignore')
    
    formhash_m = re.search(r'name="formhash" value="([^"]+)"', html)
    sid_m = re.search(r'name="sid" value="([^"]+)"', html)
    formhash = formhash_m.group(1) if formhash_m else ''
    sid = sid_m.group(1) if sid_m else ''
    
    # 模拟用户通过安全通道登录
    login_url = 'https://www.4d4y.com/forum/logging.php?action=login&loginsubmit=yes'
    post_data = {
        'sid': sid,
        'formhash': formhash,
        'referer': 'index.php',
        'loginfield': 'username',
        'username': 'helloearth',
        'password': 'xCxoYREojL6OoW',
        'questionid': '0',
        'answer': '',
        'cookietime': '315360000',
    }
    
    print("[2/5] 正在提交凭据并获取会话 Cookie (cdb_auth / cdb_sid)...")
    encoded = urllib.parse.urlencode(post_data, encoding='gbk').encode('gbk')
    req_post = urllib.request.Request(login_url, data=encoded, headers=headers)
    opener.open(req_post)
    
    print("   已捕获会话Cookie:")
    for c in cj:
        print(f"     - {c.name}: {c.value[:18]}... (Domain: {c.domain})")
        
    thread_base_url = 'https://www.4d4y.com/forum/viewthread.php?tid=3469094'
    print(f"[3/5] 正在获取目标帖子第 1 页以分析总页数: {thread_base_url}")
    
    req_th1 = urllib.request.Request(f"{thread_base_url}&page=1", headers=headers)
    page1_html = opener.open(req_th1).read().decode('gbk', errors='ignore')
    
    title_m = re.search(r'<title>(.*?)</title>', page1_html)
    thread_title = title_m.group(1).replace(' - 4D4Y', '').strip() if title_m else '4D4Y_Thread_3469094'
    # Clean file name characters
    clean_title = re.sub(r'[\/\\:\*\?"<>\|]', '_', thread_title)
    print(f"   帖子标题: {clean_title}")
    
    # 检测总页数
    pages = set([1])
    for m in re.finditer(r'viewthread\.php\?[^"\']*page=(\d+)', page1_html):
        pages.add(int(m.group(1)))
    max_page = max(pages)
    print(f"   检测到总页数: {max_page} 页 (页码列表: {sorted(list(pages))})")
    
    # 抽取公共样式表
    css_links = re.findall(r'<link[^>]+rel=["\']stylesheet["\'][^>]+href=["\']([^"\']+)["\']', page1_html)
    css_blocks = []
    for css_url in css_links:
        try:
            req_css = urllib.request.Request(css_url, headers={'User-Agent': headers['User-Agent'], 'Referer': thread_base_url})
            css_content = opener.open(req_css).read().decode('gbk', errors='ignore')
            css_blocks.append(f"<style>\n{css_content}\n</style>")
            print(f"   成功下载并嵌入样式表: {css_url.split('/')[-1]}")
        except Exception as e:
            print(f"   样式表下载跳过: {css_url} ({e})")
            
    print("[4/5] 逐页抓取全部帖子内容、处理图片与原网页排版...")
    all_pages_html = []
    
    for p in range(1, max_page + 1):
        print(f"   抓取第 {p} / {max_page} 页...")
        if p == 1:
            p_html = page1_html
        else:
            req_p = urllib.request.Request(f"{thread_base_url}&page={p}", headers=headers)
            p_html = opener.open(req_p).read().decode('gbk', errors='ignore')
            
        # 提取 postlist 容器以保留完全相同的 Discuz 原生排版
        match_postlist = re.search(r'(<div[^>]*id="postlist"[^>]*>.*?)(?:<div class="pages"|</div>\s*<div id="quickpost")', p_html, re.DOTALL)
        if match_postlist:
            content_part = match_postlist.group(1)
            # 补齐未闭合的 div
            content_part += "</div>"
        else:
            content_part = p_html
            
        all_pages_html.append(f"""
        <div class="page-break" style="page-break-before: always; margin-top: 20px;">
            <div style="background: #2B579A; color: white; padding: 6px 12px; font-weight: bold; border-radius: 4px; margin-bottom: 10px;">
                【第 {p} 页 / 共 {max_page} 页】 {clean_title}
            </div>
            {content_part}
        </div>
        """)
        
    # 合成完整的印刷级 HTML
    combined_html = f"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>{clean_title}</title>
{''.join(css_blocks)}
<style>
@media print {{
    .page-break {{ page-break-before: always; }}
    #header, #umenu, #menu, #footer, .postactions, .modact, .pages, .pageback {{ display: none !important; }}
}}
body {{
    background: #ffffff !important;
    font-family: "PingFang SC", "Microsoft YaHei", "SimSun", sans-serif;
    padding: 15px;
}}
#wrap, #postlist {{
    width: 100% !important;
    margin: 0 !important;
}}
.viewthread {{
    width: 100% !important;
}}
.postcontent, .postmessage {{
    font-size: 15px !important;
    line-height: 1.8 !important;
}}
img {{
    max-width: 100% !important;
    height: auto !important;
}}
.t_msgfont {{
    font-size: 15px !important;
}}
</style>
</head>
<body>
<div style="text-align: center; border-bottom: 2px solid #2B579A; padding-bottom: 12px; margin-bottom: 20px;">
    <h1 style="color: #2B579A; margin-bottom: 8px;">{clean_title}</h1>
    <div style="color: #666; font-size: 13px;">来源: {thread_base_url} | 4D4Y 论坛 | 全文共 {max_page} 页合并</div>
</div>
{''.join(all_pages_html)}
</body>
</html>
"""
    
    html_out_path = os.path.abspath("test_thread_rendered.html")
    with open(html_out_path, "w", encoding="utf-8") as f:
        f.write(combined_html)
    print(f"   已生成合并完整 HTML: {html_out_path} (大小: {len(combined_html):,} 字节)")
    
    # 尝试使用系统中安装的 Chrome / Edge 生成真正的 PDF 进行实机测试验证
    print("[5/5] 正在通过无头浏览器内核渲染并打印为高质量多页 PDF...")
    edge_paths = [
        r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
        r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
        r"C:\Program Files\Google\Chrome\Application\chrome.exe"
    ]
    browser_exe = next((p for p in edge_paths if os.path.exists(p)), None)
    
    pdf_out_path = os.path.abspath("test_thread_output.pdf")
    if browser_exe:
        print(f"   使用本地浏览器引擎: {browser_exe}")
        cmd = f'"{browser_exe}" --headless --disable-gpu --run-all-compositor-stages-before-draw --print-to-pdf="{pdf_out_path}" "file:///{html_out_path}"'
        res = os.system(cmd)
        if res == 0 and os.path.exists(pdf_out_path):
            size_mb = os.path.getsize(pdf_out_path) / (1024 * 1024)
            print(f"   [SUCCESS] 测试 PDF 生成成功！")
            print(f"   文件路径: {pdf_out_path}")
            print(f"   文件大小: {size_mb:.2f} MB")
        else:
            print("   浏览器导出 PDF 退出码:", res)
    else:
        print("   未找到系统浏览器进行无头打印，HTML 文件可随时用任何浏览器打印导出 PDF")

if __name__ == '__main__':
    fetch_complete_thread_to_pdf()
