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

    // 解析用户信息三类配置 (优先读取当前宽度独立定制，若未定制则遵循模板基准配置)
    final bool showAvatar = template.getShowAvatarForWidth(width);
    final bool avatarRound = template.avatarRound;
    final String avatarBorder = template.avatarBorderColor;

    final bool showUsername = template.getShowUsernameForWidth(width);
    final int uSize = template.usernameFontSize > 0 ? template.usernameFontSize : usernameSize;
    final String uColor = template.usernameColor;
    final bool uBold = template.usernameBold;

    final bool showOtherInfo = template.getShowOtherInfoForWidth(width);
    final int otherSize = template.otherInfoFontSize > 0 ? template.otherInfoFontSize : metaSize;
    final String otherColor = template.otherInfoColor;

    final bool showFloorBadge = template.getShowFloorBadgeForWidth(width);
    final String floorColor = template.floorColor;
    final bool showPostTime = template.getShowPostTimeForWidth(width);
    final String postTimeColor = template.postTimeColor;

    final String postTextColor = template.postTextColor;
    final double postLineHeight = template.postLineHeight;
    final bool showSignature = template.getShowSignatureForWidth(width);

    final String layoutMode = template.layoutMode; // 'card', 'split', 'minimal'
    final String cardBorderColor = template.cardBorderColor;
    final int cardBorderWidth = template.cardBorderWidth;
    final int cardBorderRadius = template.getBorderRadiusForWidth(width);
    final bool showFloorDivider = template.getShowFloorDividerForWidth(width);
    final String cardBgColor = template.cardBackgroundColor;
    final bool enableAlternateBubbleColor = template.enableAlternateBubbleColor;
    final String alternateBubbleColor = template.alternateBubbleColor;
    final String pageBgColor = (layoutMode == 'card') ? template.pageBackgroundColor : '#ffffff';
    final int cardSpacing = template.getCardSpacingForWidth(width);
    final int effectiveAvatarSize = template.getAvatarSizeForWidth(width);
    final int authorWidth = template.getAuthorWidthForWidth(width);
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
          'form[action*="post.php"]',
          // 彻底去除主贴顶部的打印、字体大小、跳转到、倒序看帖
          '.pagecontrol', '.print', 'a.print', 'a[href*="action=printable"]',
          '.msgfsize', '.msgfontsize', '#msgfontsize',
          'em.rpostno', '#rpostnobtn', '#rpostnovalue', 'input[name="rpostno"]',
          'a[href*="ordertype="]'
        ];
        hideSelectors.forEach(function(sel) {
          document.querySelectorAll(sel).forEach(function(el) {
            el.style.display = 'none';
          });
        });

        // 确保 #postlist 容器绝对可见，绝不可隐匿
        var postlist = document.getElementById('postlist');
        if (postlist) {
          postlist.style.display = 'block';
          postlist.style.visibility = 'visible';
          postlist.style.opacity = '1';
          // 仅隐藏 #postlist 之后且非帖子内容的同级干扰元素
          var sib = postlist.nextElementSibling;
          while (sib) {
            var next = sib.nextElementSibling;
            if (!sib.id || (!sib.id.startsWith('post') && !sib.className.includes('viewthread'))) {
              sib.remove();
            }
            sib = next;
          }
        }

        // 仅对 a 与 button 标签精确比对交互文字，绝不查询 div/span/p，彻底避免误伤正文与 postlist 容器
        document.querySelectorAll('a, button').forEach(function(el) {
          var t = el.innerText ? el.innerText.trim() : '';
          if (t === '发表回复' || t === '发表新帖' || t === '发新帖' || t === '发帖' || t === '回复' ||
              t === '返回列表' || t.indexOf('返回列表') !== -1 ||
              t === '倒序看帖' || t === '倒序看贴' || t.indexOf('倒序看') !== -1 ||
              t === '正序看帖' || t === '正序看贴' || t.indexOf('正序看') !== -1 ||
              t === '只看该作者' || t.indexOf('只看该作者') !== -1 ||
              t === '打印' || t.indexOf('打印') !== -1) {
            el.style.display = 'none';
          }
        });

        // 隐藏顶部跳转与字体控制等叶子元素（严格限定只隐藏具体微小控件，绝不向上隐藏容器）
        document.querySelectorAll('.rpostno, em.rpostno, #rpostnobtn, #rpostnovalue, .msgfsize, .pagecontrol, a.print').forEach(function(el) {
          el.style.display = 'none';
        });

        // 控制签名档显示与隐藏
        document.querySelectorAll('.signatures, .sign, .postsignature, div[id^="signature"]').forEach(function(sig) {
          sig.style.display = ${showSignature ? "'block'" : "'none'"};
        });

        // 彻底移除底部悬浮与多余空白干扰元素
        document.querySelectorAll('#footer, #scrolltop, #append_parent, #ajaxwaitid, .pages_btns, .pages, .popupmenu_popup').forEach(function(el) {
          el.remove();
        });

        // 3. 楼层 DOM 提取与应用
        var mode = '$layoutMode';
        var tables = document.querySelectorAll('#postlist table[id^="pid"], table[id^="pid"]');
        if (tables.length === 0) {
          tables = document.querySelectorAll('table.viewthread, #postlist > table');
        }

        if (mode === 'card') {
          // ====== 现代气泡卡片模式：每楼独立气泡卡片，全宽填满，支持双色交替与边框底色 ======
          tables.forEach(function(table, idx) {
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
                var postnumA = strongEl.querySelector('a[id^="postnum"]') || strongEl.querySelector('a');
                if (postnumA) {
                  floorText = postnumA.innerText.replace(/\\s+/g, ' ').trim();
                } else {
                  var strongClone = strongEl.cloneNode(true);
                  strongClone.querySelectorAll('.rpostno, a, input, span').forEach(function(r) { r.remove(); });
                  floorText = strongClone.innerText.replace(/\\s+/g, ' ').trim();
                }
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

            // 安全隐藏无关附属元素与底边条，绝不误伤正文内部嵌套表格
            table.querySelectorAll('.postauthor').forEach(function(el) {
              el.style.display = 'none';
              el.style.background = 'transparent';
            });
            table.querySelectorAll('.postbottom, .postactions, tr.threadad, tr.threadsep, tr.line, td.line, .adcontent').forEach(function(el) {
              el.style.display = 'none';
              var r = el.closest('tr');
              if (r && (r.parentNode === table || (table.tBodies && Array.from(table.tBodies).includes(r.parentNode)))) {
                r.style.display = 'none';
              }
            });

            // 气泡交替双色判断
            var isOddFloor = (idx % 2 === 1);
            var thisBubbleColor = ($enableAlternateBubbleColor && isOddFloor) ? '$alternateBubbleColor' : '$cardBgColor';

            table.style.width = '100%';
            table.style.maxWidth = '100%';
            table.style.display = 'block';
            table.style.margin = '0 0 ${cardSpacing}px 0';
            table.style.border = '${cardBorderWidth}px solid $cardBorderColor';
            table.style.borderRadius = '${cardBorderRadius}px';
            table.style.background = thisBubbleColor;
            table.style.backgroundColor = thisBubbleColor;
            table.style.boxShadow = '0 1px 3px rgba(0, 0, 0, 0.05)';
            table.style.boxSizing = 'border-box';
            table.style.overflow = 'hidden';

            contentTd.style.display = 'block';
            contentTd.style.width = '100%';
            contentTd.style.maxWidth = '100%';
            contentTd.style.padding = '0';
            contentTd.style.boxSizing = 'border-box';
            contentTd.style.background = 'transparent';

            var oldHeader = contentTd.querySelector('.d2pdf-custom-header');
            if (oldHeader) oldHeader.remove();

            var header = document.createElement('div');
            header.className = 'd2pdf-custom-header';
            header.style.cssText = 'display: flex !important; align-items: center !important; justify-content: space-between !important; ' +
              'padding: 6px 12px 4px 12px !important; width: 100% !important; box-sizing: border-box !important; ' +
              'background: transparent !important; ' +
              'border-bottom: ${showFloorDivider ? "1px solid rgba(0,0,0,0.06)" : "none"} !important;';

            // 左侧：头像 + 用户名 + 剩余其他信息（紧凑缩窄）
            var left = document.createElement('div');
            left.className = 'd2pdf-header-left';
            left.style.cssText = 'display: flex !important; align-items: center !important; flex: 1 !important; min-width: 0 !important; gap: 6px !important;';

            var effectiveAvatarSize = $effectiveAvatarSize;

            if ($showAvatar) {
              if (avatarSrc) {
                var img = document.createElement('img');
                img.src = avatarSrc;
                img.className = 'd2pdf-avatar-img';
                img.style.cssText = 'width: ' + effectiveAvatarSize + 'px !important; height: ' + effectiveAvatarSize + 'px !important; min-width: ' + effectiveAvatarSize + 'px !important; ' +
                  'border-radius: ${avatarRound ? "50%" : "4px"} !important; object-fit: cover !important; display: block !important; ' +
                  'border: 1px solid $avatarBorder !important;';
                left.appendChild(img);
              } else {
                var placeholder = document.createElement('div');
                placeholder.className = 'd2pdf-avatar-placeholder';
                placeholder.style.cssText = 'width: ' + effectiveAvatarSize + 'px !important; height: ' + effectiveAvatarSize + 'px !important; min-width: ' + effectiveAvatarSize + 'px !important; ' +
                  'border-radius: ${avatarRound ? "50%" : "4px"} !important; background: #e0e7ff !important; color: #3730a3 !important; ' +
                  'display: flex !important; align-items: center !important; justify-content: center !important; font-weight: bold !important; font-size: ${uSize}px !important;';
                placeholder.innerText = username ? username.substring(0, 1).toUpperCase() : '?';
                left.appendChild(placeholder);
              }
            }

            var userContainer = document.createElement('div');
            userContainer.style.cssText = 'display: flex !important; flex-direction: column !important; min-width: 0 !important; line-height: 1.2 !important;';

            if ($showUsername) {
              var name = document.createElement('span');
              name.className = 'd2pdf-username-span';
              name.style.cssText = 'font-size: ${uSize}px !important; color: $uColor !important; font-weight: ${uBold ? "bold" : "normal"} !important; ' +
                'overflow: hidden !important; text-overflow: ellipsis !important; white-space: nowrap !important; line-height: 1.2 !important;';
              name.innerText = username || '用户';
              userContainer.appendChild(name);
            }

            if ($showOtherInfo && otherInfoHtml) {
              var otherDiv = document.createElement('div');
              otherDiv.className = 'd2pdf-other-info';
              otherDiv.style.cssText = 'font-size: ${otherSize}px !important; color: $otherColor !important; line-height: 1.2 !important;';
              otherDiv.innerHTML = otherInfoHtml;
              userContainer.appendChild(otherDiv);
            }

            left.appendChild(userContainer);
            header.appendChild(left);

            // 右侧：时间 + 楼层
            var right = document.createElement('div');
            right.className = 'd2pdf-header-right';
            right.style.cssText = 'display: flex !important; align-items: center !important; gap: 6px !important; flex-shrink: 0 !important;';

            if ($showPostTime && postTime) {
              var timeSpan = document.createElement('span');
              timeSpan.className = 'd2pdf-time-span';
              timeSpan.style.cssText = 'color: $postTimeColor !important; font-size: ${metaSize}px !important; white-space: nowrap !important;';
              timeSpan.innerText = postTime;
              right.appendChild(timeSpan);
            }

            if ($showFloorBadge && floorText) {
              var floorSpan = document.createElement('span');
              floorSpan.className = 'd2pdf-floor-span';
              floorSpan.style.cssText = 'font-weight: bold !important; color: $floorColor !important; font-size: ${floorSize}px !important; white-space: nowrap !important;';
              floorSpan.innerText = floorText;
              right.appendChild(floorSpan);
            }

            header.appendChild(right);
            contentTd.insertBefore(header, contentTd.firstChild);

            // 确保帖子内部的表格和消息容器 100% 撑满，不挤在左侧
            contentTd.querySelectorAll('table, .postmessage, .t_msgfont, .t_msgfontfix, .defaultpost').forEach(function(el) {
              el.style.width = '100%';
              el.style.maxWidth = '100%';
              el.style.boxSizing = 'border-box';
            });
          });

        } else if (mode === 'minimal') {
          // ====== 极简纯享模式：保持扁平阅读风貌，支持头像显隐与全宽填满 ======
          tables.forEach(function(table) {
            var authorTd = table.querySelector('.postauthor');
            var contentTd = table.querySelector('.postcontent');
            if (!contentTd) return;

            var username = '';
            var avatarSrc = '';
            if (authorTd) {
              var userLink = authorTd.querySelector('.postinfo a') || authorTd.querySelector('cite a') || authorTd.querySelector('a[href*="space.php"]');
              if (userLink) username = userLink.innerText.trim();
              var imgEl = authorTd.querySelector('.avatar img');
              if (imgEl) avatarSrc = imgEl.getAttribute('file') || imgEl.src;
            }
            if (!username && contentTd) {
              var cl = contentTd.querySelector('a[href*="space.php"]');
              if (cl) username = cl.innerText.trim();
            }

            var postInfo = contentTd.querySelector('.postinfo');
            var postTime = '';
            var floorText = '';
            if (postInfo) {
              var strongEl = postInfo.querySelector('strong');
              if (strongEl) {
                var postnumA = strongEl.querySelector('a[id^="postnum"]') || strongEl.querySelector('a');
                if (postnumA) {
                  floorText = postnumA.innerText.replace(/\\s+/g, ' ').trim();
                } else {
                  var strongClone = strongEl.cloneNode(true);
                  strongClone.querySelectorAll('.rpostno, a, input, span').forEach(function(r) { r.remove(); });
                  floorText = strongClone.innerText.replace(/\\s+/g, ' ').trim();
                }
              }
              var emList = postInfo.querySelectorAll('em');
              emList.forEach(function(em) {
                var t = em.innerText.trim();
                if (t.indexOf('发表于') !== -1 || /\\d{4}-\\d{1,2}-\\d{1,2}/.test(t)) postTime = t;
              });
              if (!postTime) {
                var m = postInfo.innerText.match(/发表于\\s*[\\d\\-:\\s]+/);
                if (m) postTime = m[0].trim();
              }
              postInfo.style.display = 'none';
            }

            // 安全隐藏无关附属行与底边条，绝不误伤正文内部嵌套表格
            table.querySelectorAll('.postauthor').forEach(function(el) {
              el.style.display = 'none';
              el.style.background = 'transparent';
            });
            table.querySelectorAll('.postbottom, .postactions, tr.threadad, tr.threadsep, tr.line, td.line, .adcontent').forEach(function(el) {
              el.style.display = 'none';
              var r = el.closest('tr');
              if (r && (r.parentNode === table || (table.tBodies && Array.from(table.tBodies).includes(r.parentNode)))) {
                r.style.display = 'none';
              }
            });

            table.style.width = '100%';
            table.style.maxWidth = '100%';
            table.style.minWidth = '100%';
            table.style.display = 'block';
            table.style.margin = '0';
            table.style.border = 'none';
            // 延长到全屏的楼层底部分隔宽条 (8px 全宽纯净底部分隔)
            table.style.borderBottom = '8px solid #f1f5f9';
            table.style.background = '#ffffff';
            table.style.boxSizing = 'border-box';

            contentTd.style.display = 'block';
            contentTd.style.width = '100%';
            contentTd.style.maxWidth = '100%';
            contentTd.style.minWidth = '100%';
            contentTd.style.padding = '0';
            contentTd.style.boxSizing = 'border-box';

            var oldHeader = contentTd.querySelector('.d2pdf-custom-header');
            if (oldHeader) oldHeader.remove();

            var header = document.createElement('div');
            header.className = 'd2pdf-custom-header';
            header.style.cssText = 'display: flex !important; align-items: center !important; justify-content: space-between !important; ' +
              'padding: 8px 12px 4px 12px !important; width: 100% !important; box-sizing: border-box !important; background: #ffffff !important; ' +
              'border-bottom: ${showFloorDivider ? "1px solid #e5e7eb" : "none"} !important;';

            var left = document.createElement('div');
            left.style.cssText = 'display: flex !important; align-items: center !important; gap: 8px !important; flex: 1 !important; min-width: 0 !important;';

            var effectiveAvatarSize = $effectiveAvatarSize;

            if ($showAvatar) {
              if (avatarSrc) {
                var img = document.createElement('img');
                img.src = avatarSrc;
                img.className = 'd2pdf-avatar-img';
                img.style.cssText = 'width: ' + effectiveAvatarSize + 'px !important; height: ' + effectiveAvatarSize + 'px !important; min-width: ' + effectiveAvatarSize + 'px !important; ' +
                  'border-radius: ${avatarRound ? "50%" : "4px"} !important; object-fit: cover !important; display: block !important; ' +
                  'border: 1px solid $avatarBorder !important; flex-shrink: 0 !important;';
                left.appendChild(img);
              } else {
                var placeholder = document.createElement('div');
                placeholder.className = 'd2pdf-avatar-placeholder';
                placeholder.style.cssText = 'width: ' + effectiveAvatarSize + 'px !important; height: ' + effectiveAvatarSize + 'px !important; min-width: ' + effectiveAvatarSize + 'px !important; ' +
                  'border-radius: ${avatarRound ? "50%" : "4px"} !important; background: #e0e7ff !important; color: #3730a3 !important; ' +
                  'display: flex !important; align-items: center !important; justify-content: center !important; font-weight: bold !important; font-size: ${uSize}px !important; flex-shrink: 0 !important;';
                placeholder.innerText = username ? username.substring(0, 1).toUpperCase() : '?';
                left.appendChild(placeholder);
              }
            }

            if ($showUsername && username) {
              var name = document.createElement('span');
              name.style.cssText = 'font-weight: bold !important; font-size: ${uSize}px !important; color: $uColor !important;';
              name.innerText = username;
              left.appendChild(name);
            }
            header.appendChild(left);

            var right = document.createElement('div');
            right.style.cssText = 'display: flex !important; align-items: center !important; gap: 8px !important; flex-shrink: 0 !important;';
            if ($showPostTime && postTime) {
              var timeSpan = document.createElement('span');
              timeSpan.style.cssText = 'color: $postTimeColor !important; font-size: ${metaSize}px !important;';
              timeSpan.innerText = postTime;
              right.appendChild(timeSpan);
            }
            if ($showFloorBadge && floorText) {
              var floorSpan = document.createElement('span');
              floorSpan.style.cssText = 'color: $floorColor !important; font-size: ${floorSize}px !important; font-weight: bold !important;';
              floorSpan.innerText = floorText;
              right.appendChild(floorSpan);
            }
            header.appendChild(right);
            contentTd.insertBefore(header, contentTd.firstChild);

            // 确保帖子内部的表格和消息容器 100% 撑满，不挤在左侧
            contentTd.querySelectorAll('table, .postmessage, .t_msgfont, .t_msgfontfix, .defaultpost').forEach(function(el) {
              el.style.width = '100%';
              el.style.maxWidth = '100%';
              el.style.boxSizing = 'border-box';
            });
          });

        } else if (mode === 'split') {
          // ====== 经典论坛左右分栏模式：完全与没加模板功能之前的原版维持一致 ======
          tables.forEach(function(table) {
            table.style.width = '';
            table.style.display = '';
            table.style.margin = '';
            table.style.border = '';
            table.style.background = '';

            // 隐藏多余空白操作栏 tr，避免楼层之间出现冗余空隙
            table.querySelectorAll('.postactions').forEach(function(el) {
              var r = el.closest('tr');
              if (r) r.style.display = 'none';
            });

            var authorTd = table.querySelector('.postauthor');
            if (authorTd) {
              authorTd.style.display = '';
              authorTd.style.width = '${authorWidth}px';
              authorTd.style.minWidth = '${authorWidth}px';
              authorTd.style.maxWidth = '${authorWidth}px';
              authorTd.style.verticalAlign = '';
            }

            var contentTd = table.querySelector('.postcontent');
            if (contentTd) {
              contentTd.style.display = '';
              contentTd.style.width = '';
              contentTd.style.padding = '';
              contentTd.style.boxSizing = '';

              var oldHeader = contentTd.querySelector('.d2pdf-custom-header');
              if (oldHeader) oldHeader.remove();

              var postInfo = contentTd.querySelector('.postinfo');
              if (postInfo) {
                postInfo.style.display = '';
              }
            }
          });

          // 用户在编辑器中选择关闭某些项时才执行隐藏，默认完整展现原版风貌
          if (!$showAvatar) {
            document.querySelectorAll('.postauthor .avatar').forEach(function(el) { el.style.display = 'none'; });
          }
          if (!$showUsername) {
            document.querySelectorAll('.postauthor cite').forEach(function(el) { el.style.display = 'none'; });
          }
          if (!$showOtherInfo) {
            document.querySelectorAll('.postauthor dl.profile, .postauthor ul.profile, .postauthor p, .postauthor dl').forEach(function(el) {
              if (!el.closest('cite') && !el.closest('.avatar')) {
                el.style.display = 'none';
              }
            });
          }
          if (!$showFloorBadge) {
            document.querySelectorAll('.postinfo strong').forEach(function(el) { el.style.display = 'none'; });
          }
          if (!$showPostTime) {
            document.querySelectorAll('.postinfo em').forEach(function(el) { el.style.display = 'none'; });
          }

        } else if (mode === 'raw') {
          // ====== 原汁原味模式：原汁原味保留论坛经典排版，仅调整宽度与文字大小 ======
          tables.forEach(function(table) {
            table.style.width = '100%';
            table.style.display = '';
            table.style.margin = '';
            table.style.border = '';
            table.style.background = '';

            table.querySelectorAll('.postactions').forEach(function(el) {
              var r = el.closest('tr');
              if (r) r.style.display = 'none';
            });

            var authorTd = table.querySelector('.postauthor');
            if (authorTd) {
              authorTd.style.display = '';
              authorTd.style.width = '';
              authorTd.style.minWidth = '';
              authorTd.style.maxWidth = '';
              authorTd.style.verticalAlign = '';
            }

            var contentTd = table.querySelector('.postcontent');
            if (contentTd) {
              contentTd.style.display = '';
              contentTd.style.width = '';
              contentTd.style.padding = '';
              contentTd.style.boxSizing = '';

              var oldHeader = contentTd.querySelector('.d2pdf-custom-header');
              if (oldHeader) oldHeader.remove();

              var postInfo = contentTd.querySelector('.postinfo');
              if (postInfo) {
                postInfo.style.display = '';
              }
            }
          });
        }

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

        // 彻底隐藏主楼内部重复显示的标题，直接展现正文内容
        document.querySelectorAll('#threadtitle, .threadtitle, #postlist h2, #postlist > h2, .firstpost #threadtitle, .defaultpost #threadtitle').forEach(function(el) {
          el.style.display = 'none';
        });

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
            background: $pageBgColor !important;
            background-color: $pageBgColor !important;
            background-image: none !important;
            margin: 0 !important;
            padding: 0 !important;
            text-align: left !important;
            width: ${isPreview ? "100%" : "${width}px"} !important;
            max-width: ${isPreview ? "100%" : "${width}px"} !important;
            overflow-x: hidden !important;
            height: auto !important;
            min-height: 0 !important;
          }
          #wrap, .wrap, .main, .content, #postlist, div[id^="post_"] {
            text-align: left !important;
            width: 100% !important;
            max-width: 100% !important;
            min-width: 100% !important;
            margin: 0 !important;
            padding: ${layoutMode == 'card' ? "8px 10px 14px 10px" : "0"} !important;
            box-sizing: border-box !important;
            background: transparent !important;
            height: auto !important;
            min-height: 0 !important;
            margin-bottom: 0 !important;
            padding-bottom: 0 !important;
            display: block !important;
            visibility: visible !important;
            opacity: 1 !important;
          }

          ${layoutMode == 'card' ? '''
          .viewthread, .mainbox, table.viewthread, table[id^="pid"], #postlist > table {
            text-align: left !important;
            width: 100% !important;
            max-width: 100% !important;
            min-width: 100% !important;
            display: block !important;
            margin: 0 0 ${cardSpacing}px 0 !important;
            padding: 0 !important;
            box-sizing: border-box !important;
          }
          .postauthor, td.postauthor {
            display: none !important;
          }
          .postactions, .modact, tr.threadad, tr.threadsep, td.line, tr.line, .postbottom {
            display: none !important;
          }
          table.viewthread > tbody, table[id^="pid"] > tbody,
          table.viewthread > tbody > tr, table[id^="pid"] > tbody > tr,
          table.viewthread td.postcontent, table[id^="pid"] td.postcontent,
          .postcontent, td.postcontent {
            display: block !important;
            width: 100% !important;
            max-width: 100% !important;
            min-width: 100% !important;
            box-sizing: border-box !important;
            padding: 0 !important;
            margin: 0 !important;
            background: transparent !important;
            visibility: visible !important;
            opacity: 1 !important;
          }
          .defaultpost, .postmessage, .t_msgfontfix {
            display: block !important;
            width: 100% !important;
            max-width: 100% !important;
            min-width: 100% !important;
            box-sizing: border-box !important;
            visibility: visible !important;
            opacity: 1 !important;
          }
          .postmessage table, .t_msgfontfix table {
            width: 100% !important;
            max-width: 100% !important;
            min-width: 100% !important;
            box-sizing: border-box !important;
            table-layout: auto !important;
          }
          .postmessage {
            padding: 8px 12px 12px 12px !important;
          }
          .postmessage, .t_msgfont, .t_msgfontfix, .t_msgfont td {
            font-size: ${fontSize}px !important;
            line-height: $postLineHeight !important;
            color: $postTextColor !important;
            word-break: break-word !important;
            word-wrap: break-word !important;
            visibility: visible !important;
            opacity: 1 !important;
          }
          ''' : (layoutMode == 'minimal' ? '''
          .viewthread, .mainbox, table.viewthread, table[id^="pid"], #postlist > table {
            text-align: left !important;
            width: 100% !important;
            max-width: 100% !important;
            min-width: 100% !important;
            display: block !important;
            margin: 0 !important;
            padding: 0 !important;
            border: none !important;
            border-bottom: 8px solid #f1f5f9 !important; /* 延长到全屏的楼层底部分隔宽条 */
            box-sizing: border-box !important;
            background: #ffffff !important;
          }
          .postauthor, td.postauthor {
            display: none !important;
          }
          .postactions, .modact, tr.threadad, tr.threadsep, td.line, tr.line, .postbottom {
            display: none !important;
          }
          table.viewthread > tbody, table[id^="pid"] > tbody,
          table.viewthread > tbody > tr, table[id^="pid"] > tbody > tr,
          table.viewthread td.postcontent, table[id^="pid"] td.postcontent,
          .postcontent, td.postcontent {
            display: block !important;
            width: 100% !important;
            max-width: 100% !important;
            min-width: 100% !important;
            box-sizing: border-box !important;
            padding: 0 !important;
            margin: 0 !important;
            background: transparent !important;
            visibility: visible !important;
            opacity: 1 !important;
          }
          .defaultpost, .postmessage, .t_msgfontfix {
            display: block !important;
            width: 100% !important;
            max-width: 100% !important;
            min-width: 100% !important;
            box-sizing: border-box !important;
            visibility: visible !important;
            opacity: 1 !important;
          }
          .postmessage table, .t_msgfontfix table {
            width: 100% !important;
            max-width: 100% !important;
            min-width: 100% !important;
            box-sizing: border-box !important;
            table-layout: auto !important;
          }
          .postmessage {
            padding: 8px 12px 12px 12px !important;
          }
          .postmessage, .t_msgfont, .t_msgfontfix, .t_msgfont td {
            font-size: ${fontSize}px !important;
            line-height: $postLineHeight !important;
            color: $postTextColor !important;
            word-break: break-word !important;
            word-wrap: break-word !important;
            visibility: visible !important;
            opacity: 1 !important;
          }
          ''' : (layoutMode == 'raw' ? '''
          .viewthread, .mainbox, table.viewthread, table[id^="pid"], #postlist > table {
            text-align: left !important;
            width: ${isPreview ? "100%" : "${width}px"} !important;
            max-width: ${isPreview ? "100%" : "${width}px"} !important;
            margin: 0 !important;
            background: #ffffff !important;
            background-color: #ffffff !important;
          }
          .postmessage, .t_msgfont, .t_msgfontfix, .t_msgfont td {
            font-size: ${fontSize}px !important;
            line-height: $postLineHeight !important;
            color: $postTextColor !important;
          }
          ''' : '''
          .viewthread, .mainbox, table.viewthread, table[id^="pid"], #postlist > table {
            text-align: left !important;
            width: ${isPreview ? "100%" : "${width}px"} !important;
            max-width: ${isPreview ? "100%" : "${width}px"} !important;
            margin: 0 !important;
            padding: 0 !important;
            border: none !important;
            border-bottom: 2px solid #e2e8f0 !important; /* 经典左右分割线减为一半 */
            background: #ffffff !important;
            background-color: #ffffff !important;
          }
          /* 经典左右模式：楼层间分割线减为现在的一半 */
          tr.threadad, tr.threadad td, tr.threadad td.postauthor, tr.threadad td.adcontent {
            height: 3px !important;
            max-height: 3px !important;
            min-height: 3px !important;
            line-height: 3px !important;
            font-size: 0 !important;
            padding: 0 !important;
            margin: 0 !important;
          }
          tr.threadsep, tr.threadsep td, tr.line, tr.line td {
            height: 2px !important;
            max-height: 2px !important;
            min-height: 2px !important;
            line-height: 2px !important;
            font-size: 0 !important;
            padding: 0 !important;
            margin: 0 !important;
          }
          .postauthor, .postauthor * {
            text-align: left !important;
          }
          .postauthor, td.postauthor {
            width: ${authorWidth}px !important;
            min-width: ${authorWidth}px !important;
            max-width: ${authorWidth}px !important;
            padding: ${authorWidth <= 120 ? "4px" : "8px"} !important;
          }
          .postauthor .avatar img {
            width: ${effectiveAvatarSize > 0 ? effectiveAvatarSize : (authorWidth <= 120 ? 48 : 64)}px !important;
            height: ${effectiveAvatarSize > 0 ? effectiveAvatarSize : (authorWidth <= 120 ? 48 : 64)}px !important;
          }
          .postmessage, .t_msgfont, .t_msgfontfix {
            padding: 10px 14px 14px 14px !important;
            box-sizing: border-box !important;
            font-size: ${fontSize}px !important;
            line-height: $postLineHeight !important;
            color: $postTextColor !important;
          }
          .postinfo strong, .postinfo strong a {
            font-size: ${floorSize}px !important;
          }
          .postinfo em, .postinfo em span {
            font-size: ${metaSize}px !important;
          }
          .postauthor cite, .postauthor cite a {
            font-size: ${uSize}px !important;
          }
          '''))}

          /* 彻底隐藏主贴顶部多余文字与按钮：打印、字体大小、倒序看贴、跳转到，以及主楼内部重复显示的标题 */
          .pagecontrol, .print, a.print, a[href*="action=printable"],
          .msgfsize, .msgfontsize, #msgfontsize,
          em.rpostno, #rpostnobtn, #rpostnovalue, input[name="rpostno"],
          a[href*="ordertype="],
          #threadtitle, .threadtitle, #postlist h2, #postlist > h2,
          .firstpost #threadtitle, .defaultpost #threadtitle {
            display: none !important;
          }

          table, tbody, tr, td, .postcontent, p, div, span, h1, h2, h3, h4 {
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
          img {
            max-width: 100% !important;
            height: auto !important;
          }
          .signatures, .sign, .postsignature, div[id^="signature"] {
            display: ${showSignature ? "block !important" : "none !important"};
          }
          #footer, #scrolltop, #append_parent, #ajaxwaitid {
            display: none !important;
          }
          $customCss
        `;
      })();
    """;
  }
}
