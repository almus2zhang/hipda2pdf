import 'dart:io';

class MarkdownImageToken {
  final String token;
  final String url;
  final String alt;

  MarkdownImageToken({
    required this.token,
    required this.url,
    this.alt = '',
  });

  Map<String, dynamic> toJson() => {
    'token': token,
    'url': url,
    'alt': alt,
  };

  factory MarkdownImageToken.fromJson(Map<String, dynamic> json) {
    return MarkdownImageToken(
      token: json['token']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      alt: json['alt']?.toString() ?? '图片',
    );
  }
}

class MarkdownAttachment {
  final String filename;
  final String url;
  final String size;

  MarkdownAttachment({
    required this.filename,
    required this.url,
    this.size = '',
  });

  factory MarkdownAttachment.fromJson(Map<String, dynamic> json) {
    return MarkdownAttachment(
      filename: json['filename']?.toString() ?? '附件',
      url: json['url']?.toString() ?? '',
      size: json['size']?.toString() ?? '',
    );
  }
}

class MarkdownFloorPost {
  final String floor;
  final int floorNum;
  final String author;
  final String uid;
  final String userGroup;
  final String avatarUrl;
  final String postTime;
  final String contentMarkdown;
  final List<MarkdownImageToken> images;
  final List<MarkdownAttachment> attachments;
  final String signature;

  MarkdownFloorPost({
    required this.floor,
    required this.floorNum,
    required this.author,
    this.uid = '',
    this.userGroup = '',
    this.avatarUrl = '',
    this.postTime = '',
    required this.contentMarkdown,
    this.images = const [],
    this.attachments = const [],
    this.signature = '',
  });

  factory MarkdownFloorPost.fromJson(Map<String, dynamic> json) {
    final imgsList = (json['images'] as List?)
            ?.map((e) => MarkdownImageToken.fromJson(Map<String, dynamic>.from(e)))
            .toList() ??
        [];
    final attList = (json['attachments'] as List?)
            ?.map((e) => MarkdownAttachment.fromJson(Map<String, dynamic>.from(e)))
            .toList() ??
        [];

    return MarkdownFloorPost(
      floor: json['floor']?.toString() ?? '',
      floorNum: json['floorNum'] is int ? json['floorNum'] : int.tryParse(json['floorNum']?.toString() ?? '0') ?? 0,
      author: json['author']?.toString() ?? '匿名用户',
      uid: json['uid']?.toString() ?? '',
      userGroup: json['userGroup']?.toString() ?? '',
      avatarUrl: json['avatarUrl']?.toString() ?? '',
      postTime: json['postTime']?.toString() ?? '',
      contentMarkdown: json['markdown']?.toString() ?? '',
      images: imgsList,
      attachments: attList,
      signature: json['signature']?.toString() ?? '',
    );
  }
}

class MarkdownPageData {
  final String title;
  final String forum;
  final List<MarkdownFloorPost> posts;

  MarkdownPageData({
    required this.title,
    required this.forum,
    required this.posts,
  });

  factory MarkdownPageData.fromJson(Map<String, dynamic> json) {
    final postsList = (json['posts'] as List?)
            ?.map((e) => MarkdownFloorPost.fromJson(Map<String, dynamic>.from(e)))
            .toList() ??
        [];
    return MarkdownPageData(
      title: json['title']?.toString() ?? '',
      forum: json['forum']?.toString() ?? '',
      posts: postsList,
    );
  }
}

class MarkdownExportResult {
  final File mdFile;
  final Directory imageDir;
  final int totalImagesDownloaded;
  final int totalFloors;

  MarkdownExportResult({
    required this.mdFile,
    required this.imageDir,
    required this.totalImagesDownloaded,
    required this.totalFloors,
  });
}

class MarkdownExporter {
  /// 生成注入到 WebView 中提取楼层正文与图片链接的 JavaScript 脚本
  static String getExtractScript(int pageIndex) {
    return """
      (function() {
        var result = {
          title: '',
          forum: '',
          posts: []
        };

        var h1 = document.querySelector('h1#thread_subject') || document.querySelector('h1');
        if (h1) {
          result.title = h1.innerText.replace(/ - 4D4Y.*/, '').replace(/ - Discovery.*/, '').trim();
        }
        if (!result.title) {
          var titleTag = document.querySelector('title');
          if (titleTag) {
            result.title = titleTag.innerText.replace(/ - 4D4Y.*/, '').replace(/ - Discovery.*/, '').trim();
          }
        }

        var navLinks = document.querySelectorAll('#nav a, .nav a');
        if (navLinks.length >= 2) {
          result.forum = navLinks[navLinks.length - 1].innerText.trim();
        }

        var postTables = document.querySelectorAll('#postlist table[id^="pid"], table[id^="pid"]');
        if (postTables.length === 0) {
          postTables = document.querySelectorAll('table.viewthread, #postlist > table');
        }

        var imageCounter = 0;

        function toAbsoluteUrl(url) {
          if (!url) return '';
          if (url.startsWith('http://') || url.startsWith('https://')) return url;
          if (url.startsWith('//')) return window.location.protocol + url;
          if (url.startsWith('/')) return window.location.origin + url;
          var base = window.location.href.substring(0, window.location.href.lastIndexOf('/') + 1);
          return base + url;
        }

        postTables.forEach(function(table, pIdx) {
          var authorTd = table.querySelector('.postauthor');
          var contentTd = table.querySelector('.postcontent');
          if (!contentTd) return;

          var floorText = '';
          var postInfo = contentTd.querySelector('.postinfo');
          if (postInfo) {
            var strong = postInfo.querySelector('strong');
            if (strong) {
              var postnumA = strong.querySelector('a[id^="postnum"]') || strong.querySelector('a');
              if (postnumA) {
                floorText = postnumA.innerText.trim();
              } else {
                var sc = strong.cloneNode(true);
                sc.querySelectorAll('.rpostno, a, input, span').forEach(function(e) { e.remove(); });
                floorText = sc.innerText.trim();
              }
            }
          }
          if (!floorText) {
            floorText = ((pIdx + 1) + ((($pageIndex - 1) * 10))) + '#';
          }

          var author = '';
          if (authorTd) {
            var uLink = authorTd.querySelector('.postinfo a') || authorTd.querySelector('cite a') || authorTd.querySelector('a[href*="space.php"]');
            if (uLink) author = uLink.innerText.trim();
          }
          if (!author && contentTd) {
            var cl = contentTd.querySelector('a[href*="space.php"]');
            if (cl) author = cl.innerText.trim();
          }
          if (!author) author = '匿名用户';

          var uid = '';
          var userGroup = '';
          if (authorTd) {
            var tdText = authorTd.innerText || '';
            var uidM = tdText.match(/UID\\s*:?\\s*(\\d+)/i);
            if (uidM) uid = uidM[1];
            var gEl = authorTd.querySelector('p em') || authorTd.querySelector('.star em');
            if (gEl) {
              userGroup = gEl.innerText.trim();
            } else {
              var gM = tdText.match(/(探索者|元老|资深会员|高级会员|中级会员|初级会员|新手上路|版主|超级版主|管理员)/);
              if (gM) userGroup = gM[1];
            }
          }

          var avatarUrl = '';
          if (authorTd) {
            var avImg = authorTd.querySelector('.avatar img') || authorTd.querySelector('img[src*="avatar"]');
            if (avImg) {
              var aSrc = avImg.getAttribute('file') || avImg.src || '';
              if (aSrc && aSrc.indexOf('noavatar') === -1 && aSrc.indexOf('none.gif') === -1) {
                avatarUrl = toAbsoluteUrl(aSrc);
              }
            }
          }

          var postTime = '';
          if (postInfo) {
            var emList = postInfo.querySelectorAll('em');
            emList.forEach(function(em) {
              var t = em.innerText.trim();
              if (t.indexOf('发表于') !== -1 || /\\d{4}-\\d{1,2}-\\d{1,2}/.test(t)) postTime = t;
            });
            if (!postTime) {
              var m = postInfo.innerText.match(/发表于\\s*[\\d\\-:\\s]+/);
              if (m) postTime = m[0].trim();
            }
          }

          var signature = '';
          var sigEl = table.querySelector('.signatures, .sign, .postsignature, div[id^="signature_"]');
          if (sigEl) {
            signature = sigEl.innerText.trim();
          }

          var msgEl = contentTd.querySelector('.postmessage') || contentTd.querySelector('.t_msgfont') || contentTd.querySelector('div[id^="postmessage_"]');
          var postImages = [];
          var postAttachments = [];
          var postMd = '';

          if (msgEl) {
            var clone = msgEl.cloneNode(true);

            var attachBoxes = clone.querySelectorAll('.box.attachinfo, .attachinfo');
            attachBoxes.forEach(function(ab) {
              var aTags = ab.querySelectorAll('a[href*="attachment.php"]');
              aTags.forEach(function(at) {
                var aUrl = toAbsoluteUrl(at.getAttribute('href') || '');
                var aName = at.innerText.trim();
                var pText = ab.innerText || '';
                var sM = pText.match(/\\([\\d\\.]+\\s*(?:KB|MB|GB|Bytes)\\)/i);
                var aSize = sM ? sM[0] : '';
                if (aName && aUrl) {
                  postAttachments.push({
                    filename: aName,
                    url: aUrl,
                    size: aSize
                  });
                }
              });
              ab.remove();
            });

            clone.querySelectorAll('.postactions, .modact, .pagecontrol, .rpostno, a.print, span.attach_nopermission, script, style').forEach(function(e) {
              e.remove();
            });

            function nodeToMd(node) {
              if (!node) return '';
              if (node.nodeType === 3) {
                return (node.nodeValue || '').replace(/[ \\t]+/g, ' ');
              }
              if (node.nodeType !== 1) return '';

              var tag = node.tagName.toLowerCase();

              if (tag === 'blockquote' || node.classList.contains('quote')) {
                var authorLine = '';
                var fontHeader = node.querySelector('font[size="2"], font[color="#999999"]');
                if (fontHeader) {
                  authorLine = fontHeader.innerText.trim();
                  fontHeader.remove();
                }
                node.querySelectorAll('a[href*="goto="], img[src*="back.gif"]').forEach(function(e) { e.remove(); });
                var innerMd = '';
                for (var i = 0; i < node.childNodes.length; i++) {
                  innerMd += nodeToMd(node.childNodes[i]);
                }
                innerMd = innerMd.trim();
                var out = '\\n\\n';
                if (authorLine) {
                  out += '> **' + authorLine + '**\\n';
                }
                var lines = innerMd.split('\\n');
                for (var j = 0; j < lines.length; j++) {
                  var l = lines[j].trim();
                  if (l.length > 0) {
                    out += '> ' + l + '\\n';
                  }
                }
                out += '\\n';
                return out;
              }

              if (tag === 'div' && node.classList.contains('blockcode')) {
                return '\\n\\n```\\n' + node.innerText.trim() + '\\n```\\n\\n';
              }

              if (tag === 'br') return '\\n';
              if (tag === 'p' || tag === 'div') {
                var pMd = '';
                for (var k = 0; k < node.childNodes.length; k++) {
                  pMd += nodeToMd(node.childNodes[k]);
                }
                return '\\n' + pMd + '\\n';
              }

              if (/^h[1-6]\$/.test(tag)) {
                var level = parseInt(tag[1]);
                var hPrefix = '#'.repeat(level);
                return '\\n\\n' + hPrefix + ' ' + node.innerText.trim() + '\\n\\n';
              }

              if (tag === 'strong' || tag === 'b') {
                var bText = '';
                for (var bi = 0; bi < node.childNodes.length; bi++) bText += nodeToMd(node.childNodes[bi]);
                if (!bText.trim()) return '';
                return '**' + bText.trim() + '**';
              }
              if (tag === 'em' || tag === 'i') {
                var iText = '';
                for (var ii = 0; ii < node.childNodes.length; ii++) iText += nodeToMd(node.childNodes[ii]);
                if (!iText.trim()) return '';
                return '*' + iText.trim() + '*';
              }
              if (tag === 's' || tag === 'strike' || tag === 'del') {
                return '~~' + node.innerText.trim() + '~~';
              }
              if (tag === 'u') {
                return '<u>' + node.innerText.trim() + '</u>';
              }

              if (tag === 'a') {
                var href = node.getAttribute('href') || '';
                var text = node.innerText.trim();
                if (!href || href === '#' || href.startsWith('javascript:')) return text;
                if (node.querySelector('img[src*="back.gif"]')) return '';
                href = toAbsoluteUrl(href);
                if (!text) {
                  var aInner = '';
                  for (var ai = 0; ai < node.childNodes.length; ai++) aInner += nodeToMd(node.childNodes[ai]);
                  return aInner;
                }
                return '[' + text + '](' + href + ')';
              }

              if (tag === 'img') {
                var src = node.getAttribute('file') || node.getAttribute('zoomfile') || node.src || '';
                src = toAbsoluteUrl(src);
                if (!src || src.indexOf('images/common/') !== -1 || src.indexOf('images/default/') !== -1 ||
                    src.indexOf('back.gif') !== -1 || src.indexOf('space.gif') !== -1 || src.indexOf('none.gif') !== -1) {
                  return '';
                }
                var alt = node.getAttribute('alt') || '图片';
                var token = '%%MD_IMG_TOKEN_P' + $pageIndex + '_' + (imageCounter++) + '%%';
                postImages.push({
                  token: token,
                  url: src,
                  alt: alt
                });
                return '\\n\\n![' + alt + '](' + token + ')\\n\\n';
              }

              if (tag === 'ul') {
                var ulText = '\\n';
                node.querySelectorAll(':scope > li').forEach(function(li) {
                  ulText += '- ' + li.innerText.trim() + '\\n';
                });
                return ulText + '\\n';
              }
              if (tag === 'ol') {
                var olText = '\\n';
                var olIdx = 1;
                node.querySelectorAll(':scope > li').forEach(function(li) {
                  olText += (olIdx++) + '. ' + li.innerText.trim() + '\\n';
                });
                return olText + '\\n';
              }

              var res = '';
              for (var n = 0; n < node.childNodes.length; n++) {
                res += nodeToMd(node.childNodes[n]);
              }
              return res;
            }

            postMd = nodeToMd(clone).trim();
            postMd = postMd.replace(/\\n{3,}/g, '\\n\\n');
          }

          result.posts.push({
            floor: floorText,
            floorNum: (pIdx + 1) + (($pageIndex - 1) * 10),
            author: author,
            uid: uid,
            userGroup: userGroup,
            avatarUrl: avatarUrl,
            postTime: postTime,
            markdown: postMd,
            images: postImages,
            attachments: postAttachments,
            signature: signature
          });
        });

        return JSON.stringify(result);
      })();
    """;
  }

  /// 二进制魔数检测图片真实格式
  static String detectExtensionFromBytes(List<int> bytes, String fallbackExt) {
    if (bytes.length >= 4) {
      if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return '.jpg';
      if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) return '.png';
      if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) return '.gif';
      if (bytes.length >= 12 &&
          bytes[0] == 0x52 &&
          bytes[1] == 0x49 &&
          bytes[2] == 0x46 &&
          bytes[3] == 0x46 &&
          bytes[8] == 0x57 &&
          bytes[9] == 0x45 &&
          bytes[10] == 0x42 &&
          bytes[11] == 0x50) {
        return '.webp';
      }
    }
    return fallbackExt;
  }

  /// 根据 URL 推导备用文件扩展名
  static String inferExtension(String url) {
    try {
      final cleanUrl = url.split('?').first.toLowerCase();
      if (cleanUrl.endsWith('.png')) return '.png';
      if (cleanUrl.endsWith('.gif')) return '.gif';
      if (cleanUrl.endsWith('.webp')) return '.webp';
      if (cleanUrl.endsWith('.jpeg')) return '.jpeg';
      if (cleanUrl.endsWith('.bmp')) return '.bmp';
      if (cleanUrl.endsWith('.jpg')) return '.jpg';
    } catch (_) {}
    return '.jpg';
  }

  /// 下载图片并根据实际二进制魔数重命名与保存，返回保存后的完整文件名 (含扩展名)
  static Future<String?> downloadAndSaveImage({
    required String url,
    required String baseFileNameWithoutExt,
    required Directory targetDir,
    required List<String> sessionCookies,
  }) async {
    try {
      final uri = Uri.tryParse(url);
      if (uri == null) return null;

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);

      final request = await client.getUrl(uri);
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      );
      request.headers.set(HttpHeaders.refererHeader, 'https://www.4d4y.com/forum/');
      request.headers.set(
        HttpHeaders.acceptHeader,
        'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
      );

      if (sessionCookies.isNotEmpty && uri.host.contains('4d4y.com')) {
        request.headers.set(HttpHeaders.cookieHeader, sessionCookies.join('; '));
      }

      final response = await request.close();
      if (response.statusCode == 200) {
        final List<int> bytes = await response.fold<List<int>>([], (prev, element) => prev..addAll(element));
        client.close();

        if (bytes.isEmpty) return null;

        final fallbackExt = inferExtension(url);
        final realExt = detectExtensionFromBytes(bytes, fallbackExt);
        final finalFileName = '$baseFileNameWithoutExt$realExt';
        final file = File('${targetDir.path}/$finalFileName');

        if (!targetDir.existsSync()) {
          targetDir.createSync(recursive: true);
        }

        await file.writeAsBytes(bytes, flush: true);
        return finalFileName;
      }
      client.close();
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 构建楼层图标前缀
  static String getFloorBadge(String floorText, int floorNum) {
    if (floorText.contains('楼主') || floorNum == 1) return '🏆 $floorText';
    if (floorText.contains('沙发') || floorNum == 2) return '🛋️ $floorText';
    if (floorText.contains('板凳') || floorNum == 3) return '🪑 $floorText';
    if (floorText.contains('地板') || floorNum == 4) return '🪵 $floorText';
    return '💬 $floorText';
  }

  /// 将抓取的所有页面数据导出为 Markdown 文件与同名图片目录
  static Future<MarkdownExportResult> exportMarkdownDocument({
    required List<MarkdownPageData> pages,
    required String baseName,
    required Directory destDir,
    required String threadUrl,
    required String originalAuthor,
    required int totalPages,
    required List<String> sessionCookies,
    void Function(String status, double progress)? onProgress,
  }) async {
    final mdFile = File('${destDir.path}/$baseName.md');
    final imageDir = Directory('${destDir.path}/$baseName');
    if (!imageDir.existsSync()) {
      imageDir.createSync(recursive: true);
    }

    final String folderName = baseName;
    final Map<String, String> tokenToLocalPath = {};
    int downloadedCount = 0;
    int totalFloors = 0;

    final List<Map<String, dynamic>> allImageTasks = [];
    final Set<String> downloadedAvatars = {};

    for (int pIdx = 0; pIdx < pages.length; pIdx++) {
      final page = pages[pIdx];
      final pageNum = pIdx + 1;
      for (final post in page.posts) {
        totalFloors++;
        for (int i = 0; i < post.images.length; i++) {
          final img = post.images[i];
          allImageTasks.add({
            'token': img.token,
            'url': img.url,
            'alt': img.alt,
            'pageNum': pageNum,
            'floorNum': post.floorNum,
            'imgIndex': i + 1,
            'isAvatar': false,
          });
        }

        // 头像任务
        if (post.avatarUrl.isNotEmpty && !downloadedAvatars.contains(post.author)) {
          downloadedAvatars.add(post.author);
          allImageTasks.add({
            'author': post.author,
            'url': post.avatarUrl,
            'isAvatar': true,
          });
        }
      }
    }

    final totalImages = allImageTasks.length;
    final Map<String, String> authorAvatarPaths = {};

    // 并发下载图片 (并发数 4)
    if (totalImages > 0) {
      const concurrency = 4;
      for (int i = 0; i < allImageTasks.length; i += concurrency) {
        final chunk = allImageTasks.skip(i).take(concurrency).toList();
        await Future.wait(chunk.map((task) async {
          final bool isAvatar = task['isAvatar'] == true;
          final String url = task['url'] as String;

          if (isAvatar) {
            final String author = task['author'] as String;
            final safeAuthor = author.replaceAll(RegExp(r'[\/\\:\*\?"<>\|\s]'), '_');
            final baseNameNoExt = 'avatar_$safeAuthor';

            final savedFileName = await downloadAndSaveImage(
              url: url,
              baseFileNameWithoutExt: baseNameNoExt,
              targetDir: imageDir,
              sessionCookies: sessionCookies,
            );
            if (savedFileName != null) {
              authorAvatarPaths[author] = './$folderName/$savedFileName';
            }
          } else {
            final String token = task['token'] as String;
            final int pageNum = task['pageNum'] as int;
            final int floorNum = task['floorNum'] as int;
            final int imgIndex = task['imgIndex'] as int;
            final baseNameNoExt = 'p${pageNum}_f${floorNum}_$imgIndex';

            final savedFileName = await downloadAndSaveImage(
              url: url,
              baseFileNameWithoutExt: baseNameNoExt,
              targetDir: imageDir,
              sessionCookies: sessionCookies,
            );

            if (savedFileName != null) {
              tokenToLocalPath[token] = './$folderName/$savedFileName';
              downloadedCount++;
            } else {
              tokenToLocalPath[token] = url;
            }
          }
        }));

        final progress = (i + chunk.length) / totalImages;
        onProgress?.call(
          '正在下载并归档高清图片 (${i + chunk.length}/$totalImages)...',
          progress,
        );
      }
    }

    // 组织并拼接 Markdown 文本
    final buffer = StringBuffer();
    final firstPage = pages.isNotEmpty ? pages.first : null;
    final threadTitle = firstPage?.title.isNotEmpty == true ? firstPage!.title : baseName;
    final forumName = firstPage?.forum.isNotEmpty == true ? firstPage!.forum : 'HiPDA';

    // 顶部标题与元数据横幅 (排版与 PDF 封面/顶栏高度呼应)
    buffer.writeln('# $threadTitle\n');
    buffer.writeln('> 🌐 **论坛来源**: [$forumName · HiPDA 4D4Y]($threadUrl)');
    buffer.writeln('> 👤 **原帖作者**: $originalAuthor');
    buffer.writeln('> 📄 **帖子总页数**: $totalPages 页 (共 $totalFloors 楼)');
    buffer.writeln('> ⏰ **导出时间**: ${DateTime.now().toString().substring(0, 19)}');
    buffer.writeln('> 🏷️ **归档引擎**: HiPDA D2PDF 核心排版引擎 (Markdown 增强版)\n');
    buffer.writeln('---\n');

    // 楼层依次排版
    for (int pIdx = 0; pIdx < pages.length; pIdx++) {
      final page = pages[pIdx];
      for (final post in page.posts) {
        final floorBadge = getFloorBadge(post.floor, post.floorNum);
        final avatarLocal = authorAvatarPaths[post.author];

        buffer.writeln('### $floorBadge · ${avatarLocal != null ? '<img src="$avatarLocal" width="28" height="28" style="border-radius:50%; vertical-align:middle; display:inline-block; margin-right:4px;" /> ' : ''}**${post.author}**');

        final List<String> metaParts = [];
        if (post.postTime.isNotEmpty) metaParts.add('📅 **时间**: ${post.postTime}');
        if (post.userGroup.isNotEmpty) metaParts.add('🎖️ **组别**: ${post.userGroup}');
        if (post.uid.isNotEmpty) metaParts.add('🆔 **UID**: ${post.uid}');

        if (metaParts.isNotEmpty) {
          buffer.writeln('> ${metaParts.join(' | ')}\n');
        } else {
          buffer.writeln();
        }

        // 替换正文中的图片占位符为本地相对路径
        String content = post.contentMarkdown;
        for (final img in post.images) {
          final localPath = tokenToLocalPath[img.token] ?? img.url;
          content = content.replaceAll(img.token, localPath);
        }

        if (content.isNotEmpty) {
          buffer.writeln(content);
          buffer.writeln();
        }

        // 附件下载区
        if (post.attachments.isNotEmpty) {
          buffer.writeln('📎 **附件资源**:');
          for (final att in post.attachments) {
            final sizeStr = att.size.isNotEmpty ? ' *${att.size}*' : '';
            buffer.writeln('- [${att.filename}](${att.url})$sizeStr');
          }
          buffer.writeln();
        }

        // 签名档 (与 PDF 保持一致，以微小分隔线区分)
        if (post.signature.isNotEmpty) {
          buffer.writeln('---');
          buffer.writeln('*💬 签名档: ${post.signature}*\n');
        }

        // 楼层间分隔线
        buffer.writeln('---\n');
      }
    }

    // 保存为 .md 文件
    await mdFile.writeAsString(buffer.toString(), flush: true);

    return MarkdownExportResult(
      mdFile: mdFile,
      imageDir: imageDir,
      totalImagesDownloaded: downloadedCount,
      totalFloors: totalFloors,
    );
  }
}
