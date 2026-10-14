import 'dart:convert';
import 'layout_template.dart';

class TemplateRenderer {
  /// 生成注入到 WebView 中的完整 JavaScript 脚本，根据所选模板重构楼层 DOM 与 CSS
  static String generateInjectionJs({
    required LayoutTemplate template,
    required int width,
    required int fontSize,
    required int usernameSize,
    required int metaSize,
    required int floorSize,
    required String pageTitle,
    bool isPreview = false,
  }) {
    final String jsTitle = jsonEncode(pageTitle);

    // 解析用户信息三类配置
    final bool showAvatar = template.showAvatar;
    final int avatarSize = template.avatarSize;
    final bool avatarRound = template.avatarRound;
    final String avatarBorder = template.avatarBorderColor;

    final bool showUsername = template.showUsername;
    final int uSize = template.usernameFontSize > 0 ? template.usernameFontSize : usernameSize;
    final String uColor = template.usernameColor;
    final bool uBold = template.usernameBold;

    final bool showOtherInfo = template.showOtherInfo;
    final int otherSize = template.otherInfoFontSize > 0 ? template.otherInfoFontSize : metaSize;
    final String otherColor = template.otherInfoColor;

    final bool showFloorBadge = template.showFloorBadge;
    final String floorColor = template.floorColor;
    final bool showPostTime = template.showPostTime;
    final String postTimeColor = template.postTimeColor;

    final String postTextColor = template.postTextColor;
    final double postLineHeight = template.postLineHeight;
    final bool showSignature = template.showSignature;

    final String layoutMode = template.layoutMode; // 'card', 'split', 'minimal'
    final String cardBorderColor = template.cardBorderColor;
    final bool showFloorDivider = template.showFloorDivider;
    final String cardBgColor = template.cardBackgroundColor;
    final String customCss = template.customCss;

    return """
      (function() {
        // 1. 触发懒加载图片
        document.querySelectorAll('img[file]').forEach(function(img) {
          if (img.getAttribute('file')) {
            img.src = img.getAttribute('file');
          }
        });

        // 2. 隐藏无关论坛装饰与交互元素
        var hideSelectors = [
          '#header', '#umenu', '#menu', '#footer',
          '.postactions', '.modact', '#quickpost',
          '#postlist_act', '.postbtn', '#newspecial', '#post_reply',
          '.threadactions', '#visitedforums', '.forumcontrol', '#f_post',
          'form[action*="post.php"]'
        ];
        hideSelectors.forEach(function(sel) {
          document.querySelectorAll(sel).forEach(function(el) {
            el.style.display = 'none';
          });
        });

        // 隐藏 #postlist 之后的所有同级干扰元素
        var postlist = document.getElementById('postlist');
        if (postlist) {
          var sib = postlist.nextElementSibling;
          while (sib) {
            var next = sib.nextElementSibling;
            sib.remove();
            sib = next;
          }
        }

        // 移除回复按钮与“返回列表”
        document.querySelectorAll('a, button, span, div, p').forEach(function(el) {
          var t = el.innerText ? el.innerText.trim() : '';
          if (t === '发表回复' || t === '发表新帖' || t === '发新帖' || t === '发帖' || t === '回复' ||
              t === '返回列表' || t.indexOf('返回列表') !== -1) {
            var container = el.closest('.pages_btns') || el.closest('.postbtn') || el.closest('.forumcontrol') || el.closest('#postlist_act') || el;
            container.style.display = 'none';
          }
        });

        document.querySelectorAll('a').forEach(function(a) {
          if (a.innerText && a.innerText.indexOf('只看该作者') !== -1) {
            a.style.display = 'none';
          }
        });

        // 控制签名档显示与隐藏
        document.querySelectorAll('.signatures').forEach(function(sig) {
          sig.style.display = ${showSignature ? "'block'" : "'none'"};
        });

        // 3. 楼层 DOM 提取与应用
        var tables = document.querySelectorAll('#postlist table[id^="pid"], table[id^="pid"]');
        if (tables.length === 0) {
          tables = document.querySelectorAll('table.viewthread, #postlist > table');
        }

        tables.forEach(function(table) {
          var authorTd = table.querySelector('.postauthor');
          var contentTd = table.querySelector('.postcontent');
          if (!contentTd) return;

          // 提取头像
          var avatarSrc = '';
          if (authorTd) {
            var avImg = authorTd.querySelector('.avatar img') || authorTd.querySelector('img[src*="avatar"]') || authorTd.querySelector('img');
            if (avImg) {
              avatarSrc = avImg.getAttribute('file') || avImg.src;
            }
          }

          // 提取用户名
          var username = '';
          if (authorTd) {
            var userLink = authorTd.querySelector('.postinfo a') || authorTd.querySelector('cite a') || authorTd.querySelector('a[href*="space.php"]');
            if (userLink) {
              username = userLink.innerText.trim();
            }
          }
          if (!username && contentTd) {
            var cl = contentTd.querySelector('a[href*="space.php"]');
            if (cl) username = cl.innerText.trim();
          }

          // 提取剩余其他信息（等级、星级、UID、帖子、积分、注册日期）
          var otherInfoHtml = '';
          if (authorTd) {
            var authorClone = authorTd.cloneNode(true);
            // 移除已有头像与名字避免重复
            var av = authorClone.querySelector('.avatar');
            if (av) av.remove();
            var cite = authorClone.querySelector('cite');
            if (cite) cite.remove();
            var pi = authorClone.querySelector('.postinfo');
            if (pi) pi.remove();
            otherInfoHtml = authorClone.innerHTML.trim();
          }

          // 提取发帖时间与楼层序号
          var postInfo = contentTd.querySelector('.postinfo');
          var postTime = '';
          var floorText = '';
          if (postInfo) {
            var strongEl = postInfo.querySelector('strong');
            if (strongEl) {
              floorText = strongEl.innerText.replace(/\\s+/g, ' ').trim();
            }

            var emList = postInfo.querySelectorAll('em');
            emList.forEach(function(em) {
              var t = em.innerText.trim();
              if (t.indexOf('发表于') !== -1 || /\\d{4}-\\d{1,2}-\\d{1,2}/.test(t)) {
                postTime = t;
              }
            });
            if (!postTime) {
              var m = postInfo.innerText.match(/发表于\\s*[\\d\\-:\\s]+/);
              if (m) postTime = m[0].trim();
            }
            postInfo.style.display = 'none';
          }

          var mode = '$layoutMode';
          if (mode === 'card' || mode === 'minimal') {
            // 隐藏原有侧边栏
            if (authorTd) authorTd.style.display = 'none';

            table.style.width = '100%';
            table.style.display = 'block';
            table.style.margin = '0 0 10px 0';
            table.style.border = 'none';
            table.style.background = '$cardBgColor';

            contentTd.style.display = 'block';
            contentTd.style.width = '100%';
            contentTd.style.padding = '0';
            contentTd.style.boxSizing = 'border-box';

            var oldHeader = contentTd.querySelector('.d2pdf-custom-header');
            if (oldHeader) oldHeader.remove();

            var header = document.createElement('div');
            header.className = 'd2pdf-custom-header';
            header.style.cssText = 'display: flex !important; align-items: center !important; justify-content: space-between !important; ' +
              'padding: 12px 14px 6px 14px !important; width: 100% !important; box-sizing: border-box !important; ' +
              'border-top: ${showFloorDivider ? "1px solid $cardBorderColor" : "none"} !important; ' +
              'background: $cardBgColor !important;';

            // 左侧：头像 + 用户名 + 剩余其他信息
            var left = document.createElement('div');
            left.className = 'd2pdf-header-left';
            left.style.cssText = 'display: flex !important; align-items: center !important; flex: 1 !important; min-width: 0 !important; gap: 8px !important;';

            if (${showAvatar}) {
              if (avatarSrc) {
                var img = document.createElement('img');
                img.src = avatarSrc;
                img.className = 'd2pdf-avatar-img';
                img.style.cssText = 'width: ${avatarSize}px !important; height: ${avatarSize}px !important; min-width: ${avatarSize}px !important; ' +
                  'border-radius: ${avatarRound ? "50%" : "6px"} !important; object-fit: cover !important; display: block !important; ' +
                  'border: 1px solid $avatarBorder !important;';
                left.appendChild(img);
              } else {
                var placeholder = document.createElement('div');
                placeholder.className = 'd2pdf-avatar-placeholder';
                placeholder.style.cssText = 'width: ${avatarSize}px !important; height: ${avatarSize}px !important; min-width: ${avatarSize}px !important; ' +
                  'border-radius: ${avatarRound ? "50%" : "6px"} !important; background: #e0e7ff !important; color: #3730a3 !important; ' +
                  'display: flex !important; align-items: center !important; justify-content: center !important; font-weight: bold !important; font-size: ${uSize}px !important;';
                placeholder.innerText = username ? username.substring(0, 1).toUpperCase() : '?';
                left.appendChild(placeholder);
              }
            }

            var userContainer = document.createElement('div');
            userContainer.style.cssText = 'display: flex !important; flex-direction: column !important; min-width: 0 !important;';

            if (${showUsername}) {
              var name = document.createElement('span');
              name.className = 'd2pdf-username-span';
              name.style.cssText = 'font-size: ${uSize}px !important; color: $uColor !important; font-weight: ${uBold ? "bold" : "normal"} !important; ' +
                'overflow: hidden !important; text-overflow: ellipsis !important; white-space: nowrap !important;';
              name.innerText = username || '用户';
              userContainer.appendChild(name);
            }

            if (${showOtherInfo} && otherInfoHtml) {
              var otherDiv = document.createElement('div');
              otherDiv.className = 'd2pdf-other-info';
              otherDiv.style.cssText = 'font-size: ${otherSize}px !important; color: $otherColor !important; line-height: 1.3 !important;';
              otherDiv.innerHTML = otherInfoHtml;
              userContainer.appendChild(otherDiv);
            }

            left.appendChild(userContainer);
            header.appendChild(left);

            // 右侧：时间 + 楼层
            var right = document.createElement('div');
            right.className = 'd2pdf-header-right';
            right.style.cssText = 'display: flex !important; align-items: center !important; gap: 8px !important; flex-shrink: 0 !important;';

            if (${showPostTime} && postTime) {
              var timeSpan = document.createElement('span');
              timeSpan.className = 'd2pdf-time-span';
              timeSpan.style.cssText = 'color: $postTimeColor !important; font-size: ${metaSize}px !important; white-space: nowrap !important;';
              timeSpan.innerText = postTime;
              right.appendChild(timeSpan);
            }

            if (${showFloorBadge} && floorText) {
              var floorSpan = document.createElement('span');
              floorSpan.className = 'd2pdf-floor-span';
              floorSpan.style.cssText = 'font-weight: bold !important; color: $floorColor !important; font-size: ${floorSize}px !important; white-space: nowrap !important;';
              floorSpan.innerText = floorText;
              right.appendChild(floorSpan);
            }

            header.appendChild(right);
            contentTd.insertBefore(header, contentTd.firstChild);

          } else if (mode === 'split') {
            // 经典论坛分栏模式
            if (authorTd) {
              authorTd.style.display = 'table-cell';
              authorTd.style.width = '180px';
              authorTd.style.maxWidth = '200px';
              authorTd.style.background = '#f8fafc';
              authorTd.style.padding = '12px';
              authorTd.style.borderRight = '1px solid $cardBorderColor';

              // 样式定制
              var avImg = authorTd.querySelector('.avatar img');
              if (avImg) {
                avImg.style.display = ${showAvatar ? "'block'" : "'none'"};
                avImg.style.borderRadius = '${avatarRound ? "50%" : "6px"}';
                avImg.style.width = '${avatarSize}px';
                avImg.style.height = '${avatarSize}px';
              }
              var cite = authorTd.querySelector('cite');
              if (cite) {
                cite.style.display = ${showUsername ? "'block'" : "'none'"};
                cite.style.color = '$uColor';
                cite.style.fontSize = '${uSize}px';
                cite.style.fontWeight = '${uBold ? "bold" : "normal"}';
              }
              authorTd.querySelectorAll('p, div, dl').forEach(function(el) {
                if (!el.classList.contains('avatar') && !el.closest('cite')) {
                  el.style.display = ${showOtherInfo ? "''" : "'none'"};
                  el.style.fontSize = '${otherSize}px';
                  el.style.color = '$otherColor';
                }
              });
            }

            if (contentTd) {
              contentTd.style.display = 'table-cell';
              contentTd.style.width = 'auto';
            }

            var oldHeader = contentTd.querySelector('.d2pdf-custom-header');
            if (oldHeader) oldHeader.remove();

            if (postInfo) {
              postInfo.style.display = 'flex';
              postInfo.style.justifyContent = 'space-between';
              postInfo.style.alignItems = 'center';
              postInfo.style.padding = '8px 12px';
              postInfo.style.borderBottom = '1px solid $cardBorderColor';
            }
          }
        });

        // 4. 处理顶部导航栏标题
        var navEl = document.getElementById('nav') || document.querySelector('.nav');
        var passedTitle = $jsTitle;
        var finalTitle = passedTitle || '';
        if (!finalTitle) {
          var h1El = document.querySelector('#threadtitle h1, #threadtitle, h1, .threadtitle, #postlist h2');
          if (h1El && h1El.innerText && h1El.innerText.trim()) {
            finalTitle = h1El.innerText.trim();
          } else if (document.title) {
            finalTitle = document.title.split(' - ')[0].split(' _ ')[0].trim();
          }
        }

        if (navEl) {
          navEl.innerHTML = '';
          var topTitleDiv = document.createElement('div');
          topTitleDiv.className = 'd2pdf-top-title';
          topTitleDiv.innerText = finalTitle;
          navEl.appendChild(topTitleDiv);
        } else if (finalTitle) {
          var newNav = document.createElement('div');
          newNav.id = 'nav';
          newNav.className = 'nav';
          var topTitleDiv = document.createElement('div');
          topTitleDiv.className = 'd2pdf-top-title';
          topTitleDiv.innerText = finalTitle;
          newNav.appendChild(topTitleDiv);
          var wrapEl = document.getElementById('wrap') || document.querySelector('.wrap') || document.body;
          wrapEl.insertBefore(newNav, wrapEl.firstChild);
        }

        // 5. 注入专属与通用样式
        var styleId = 'd2pdf-dynamic-template-style';
        var styleEl = document.getElementById(styleId);
        if (!styleEl) {
          styleEl = document.createElement('style');
          styleEl.id = styleId;
          document.head.appendChild(styleEl);
        }

        styleEl.innerHTML = `
          html, body {
            background: #ffffff !important;
            background-color: #ffffff !important;
            background-image: none !important;
            margin: 0 !important;
            padding: 0 !important;
            text-align: left !important;
            width: ${isPreview ? "100%" : "${width}px"} !important;
            overflow-x: hidden !important;
          }
          #wrap, #postlist, .viewthread, .mainbox, table.viewthread, table[id^="pid"], #postlist > table {
            text-align: left !important;
            width: ${isPreview ? "100%" : "${width}px"} !important;
            max-width: ${isPreview ? "100%" : "${width}px"} !important;
            margin: 0 !important;
            padding: 0 !important;
            border: none !important;
            box-sizing: border-box !important;
            background: #ffffff !important;
            background-color: #ffffff !important;
          }
          table, tbody, tr, td, .postcontent, .postmessage, .t_msgfont, .t_msgfontfix, p, div, span, h1, h2, h3, h4 {
            text-align: left !important;
          }
          #nav, .nav {
            display: block !important;
            height: auto !important;
            min-height: unset !important;
            line-height: 1.4 !important;
            padding: 10px 14px 12px 14px !important;
            margin: 0 !important;
            background: transparent !important;
            border: none !important;
            text-align: left !important;
          }
          .d2pdf-top-title, #nav .d2pdf-top-title, .nav .d2pdf-top-title {
            font-size: 200% !important;
            line-height: 1.4 !important;
            font-weight: bold !important;
            color: #111827 !important;
            text-align: left !important;
            display: block !important;
            margin: 0 !important;
            padding: 0 !important;
            word-break: break-word !important;
          }
          .postmessage, .t_msgfont, .t_msgfontfix {
            padding: 10px 14px 14px 14px !important;
            box-sizing: border-box !important;
            font-size: ${fontSize}px !important;
            line-height: $postLineHeight !important;
            color: $postTextColor !important;
          }
          img {
            max-width: 100% !important;
            height: auto !important;
          }
          $customCss
        `;
      })();
    """;
  }
}
