import 'dart:convert';
import 'dart:html';
import 'dart:js';
import 'package:collection/collection.dart';
import 'package:intl/intl.dart';
import 'package:markdown/markdown.dart' as md;

import 'package:skychat/js.dart';
import 'package:skychat/model/server.dart';
import 'package:skychat/mysky.dart';
import 'package:skynet/skynet.dart';
import 'package:skynet/dacs.dart';
import 'package:string_validator/string_validator.dart';

final joinedServerIds = [
  'a8e04ee82f2120b90cb234df62bd3181517a201ef4944b03277b162cc16b3ce9'
];

final servers = <String, Server>{};

Server currentServerData;
String currentChannelId;

final mySky = MySkyService();

// TODO Check all TrustedNodeValidator's for security flaws

void skychatClick(String type, [String id]) {
  print('skychatClick $type $id');
  if (type == 'server') {
    print('select server $id');
    RenderChannels(id);
  } else if (type == 'channel') {
    print('select channel $id');
    RenderMessages(id);
  } else if (type == 'login') {
    mySky.requestLoginAccess();
  }
}

Map<String, dynamic> UI;

Future<void> sendMessage(String message) async {
  if ((querySelector('#msgField') as InputElement).disabled) return;

  print('sendMessage');
  (querySelector('#msgField') as InputElement).disabled = true;
  final path = '${mySky.dataDomain}/${currentServerData?.id}/messages.json';

  final res = await mySky.skynetClient.file.getJSONWithRevision(
    mySky.userId,
    path,
  );
  print('existing ${res.revision} ${res.data}');

  Map data;

  if (res.data == null) {
    data = {'messages': []};
  } else {
    data = res.data;
  }

  final int lastIndex =
      ((data['messages'] as List).lastOrNull ?? {})['index'] ?? 0;

  print('lastIndex ${lastIndex}');

  final scrollElem = UI['content']['chatWindow']['scrollElem'];
  final autoScroll = scrollElem.scrollHeight - 5 <=
      scrollElem.clientHeight + scrollElem.scrollTop;

  insertMessage(
    Post(
      content: PostContent(
        ext: {
          "chatbubble.hns": {
            "userId": mySky.userId,
            "serverId": currentServerData.id,
            "channelName": currentChannelId,
            "i": lastIndex + 1,
          }
        },
        text: message,
        textContentType: 'text/plain',
      ),
    ),
    true,
  );

  if (autoScroll) {
    scrollElem.scrollTop = scrollElem.scrollHeight - scrollElem.clientHeight;
  }

  data['messages'].add({
    'content': {
      'text': message,
    },
    'channelName': currentChannelId,
    'index': lastIndex + 1,
  });

  while (data['messages'].length > 8) {
    (data['messages'] as List).removeAt(0);
  }

  print('[send] setJSON');

  await mySky.mySky.setJSON(path, data); // TODO Set revision here

  print('[send] notify');

  ws.notify(SkynetUser.fromId(mySky.userId), path);

  (querySelector('#msgField') as InputElement).value = '';

  (querySelector('#msgField') as InputElement).disabled = false;
}

SkynetUser publicUser;

SkyDBoverWS ws;

bool isRunningInIframe = false;
void main() async {
  isRunningInIframe = window.self != window.top;

  var host = window.location.hostname.split('.hns.').last;

  if (host == 'localhost' || host == '127.0.0.1') {
    host = 'siasky.net';
  }

  ws = SkyDBoverWS(mySky.skynetClient);

  ws.onConnectionStateChange = () {
    final cs = ws.connectionState;

    String statusHtml;

    // TODO Show status somewhere

    if (cs.type == ConnectionStateType.connected) {
      statusHtml = 'Connected with ${ws.endpoint}';
    } else if (cs.type == ConnectionStateType.disconnected) {
      statusHtml = 'Disconnected! Retrying...';
    } else {
      statusHtml = 'None';
    }

    print('[status] $statusHtml');
    // querySelector('#status').innerHtml = statusHtml;
  };
  ws.connect();

  mySky.isLoggedIn.values.listen((event) {
    print('isLoggedIn $event');

    if (event == null) {
      return;
    }

    if (event) {
      document.getElementById('loginModal').style.display = 'none';
      startSkyChat();
    } else {
      document
          .getElementById('loginModal')
          .querySelector('.modal-content')
          .setInnerHtml(
            "<h2>Welcome to SkyChat</h2><p>You need to login with your MySky account to continue</p><button onclick=\"skychatClick('login');\">Login with MySky</button>",
            validator: TrustedNodeValidator(),
          );
    }
  });

  await mySky.init();

  publicUser =
      await SkynetUser.createFromSeedAsync(List.generate(32, (index) => 0));

  UI = {
    'nav': document.getElementsByTagName("nav")[0],
    'header': {
      'serverNameElem': document.getElementById("headerServerName"),
      'serverCatergories': document.getElementById("headerBrowseServer"),
      'serverCatergoryTemplate':
          "<div class=\"catergory\" id=\"catergory_{id}\"><span class=\"title\" onClick=\"this.parentNode.classList.toggle('hide');\">{name}<span class=\"channelUnreadCount\">{count}</span></span>{channels}</div>",
      'serverChannelTemplate':
          "<div id=\"channel_{id}\" class=\"channel {active}\" onClick=\"skychatClick('channel','{id}');\">{name}</div>"
    },
    'content': {
      'chatHeader': document.querySelector(".channelName"),
      'memberCount': document.querySelector(".memberCount"),
      'chatWindow': {
        'scrollElem': document.querySelector(".channelContent"),
        'elem': document.querySelector(".channelChats")
      },
      'inputForm': document.querySelector(".channelInput")
    },
    'aside': {'membersList': document.getElementById("membersList")}
  };

  final FormElement form = querySelector('#channelInput');

  form.onSubmit.listen((event) {
    // TODO Make the message sending process better (UI)

    event.preventDefault();

    // if (lockMsgSend) return false;

    final String msg = (querySelector('#msgField') as InputElement).value;
    //  print(msg);
/*     if (ownMessages.isEmpty) {
      setStatus(
          'Sending message... (The first message with your account can take up to 1 min)');
    } else { */
    // setStatus('Sending message...');
    /* } */
    sendMessage(msg);

    return false;
  });

  skychatClickJS = allowInterop(skychatClick);
}

void startSkyChat() async {
  // TODO Load joined server list from MySky
  await Future.wait(<Future>[
    for (final serverId in joinedServerIds)
      () async {
        servers[serverId] = Server.fromJson(
            await mySky.skynetClient.file.getJSON(serverId, 'index.json'))
          ..id = serverId;
      }(),
  ]);

  for (final server in servers.values) {
    print(server.memberList);
    subscribeToMemberList(server.id, server.memberList);

    for (final channelName in server.channels.keys) {
      subscribeToChannel(server.id, channelName, server.channels[channelName]);
    }
  }

  RenderServers();
}

final messagesDB = <String, List<Post>>{};

final memberListDB = <String, Map<String, dynamic>>{};

final processedMessageIds = <String>{};

void subscribeToMemberList(String serverId, String ref) {
  final uri = Uri.tryParse(ref);

  if (uri == null) {
    print('Could not subscribe to channel $serverId/memberList');
    return;
  }
  final userId = uri.host;
  final path = uri.path.substring(1);

  if (!ws.isSubscribed(SkynetUser.fromId(userId), path)) {
    ws.subscribe(SkynetUser.fromId(userId), '', path: path).listen((srv) async {
      try {
        print('[new] memberList');

        final res = await ws.downloadFileFromRegistryEntry(srv);

        final data = json.decode(res.asString)['_data'];

        memberListDB[serverId] = data['relations'];

        if (serverId == currentServerData?.id) {
          RenderMemberList();
          RenderInputField();
        }

        if (mySky.isLoggedIn.value == true) {
          final isMember = memberListDB[serverId].containsKey(mySky.userId);
          if (!isMember) {
            sendJoinRequest(serverId);
          }
        }
      } catch (e, st) {
        print(e);
        print(st);
      }
      // print(srv);
    });
  }
}

void sendJoinRequest(String serverId) async {
  print('sendJoinRequest');

  final path = 'chatbubble.hns/$serverId/join.request.json';
  final res = await mySky.skynetClient.file.getJSONWithRevision(
    publicUser.id,
    path,
  );

  var data = res.data;

  // data = [];

  if (data == null) {
    data = [];
  }
  if (data.contains(mySky.userId)) {
    return;
  }
  data.add(mySky.userId);

  await ws.setJSON(
    publicUser,
    path,
    data,
    res.revision + 1,
  );
}

void subscribeToChannel(String serverId, String channelName, String ref) {
  print('ref $ref');
  final uri = Uri.tryParse(ref);
  final key = '$serverId#$channelName';

  if (uri == null) {
    print('Could not subscribe to channel $key');
    return;
  }
  final userId = uri.host;
  final path = uri.path.substring(1);

  print(userId);
  print(path);

  if (!ws.isSubscribed(SkynetUser.fromId(userId), path)) {
    ws.subscribe(SkynetUser.fromId(userId), '', path: path).listen((srv) async {
      try {
        print('[new] channel');

        final res = await ws.downloadFileFromRegistryEntry(srv);

        final data = json.decode(res.asString)['_data'];

        final int currPage = data['currPageNumber'];

        final pagePath =
            path.replaceFirst('/index.json', '/page_$currPage.json');

        final page = await mySky.skynetClient.file.getJSON(userId, pagePath);

        final self = page['_self'];

        print(self);

        if (!messagesDB.containsKey(key)) {
          messagesDB[key] = [];
        }

        List<Post> newMessages = [];

        for (final item in page['items']) {
          final fullId = '$self#${item['id']}';

          if (!processedMessageIds.contains(fullId)) {
            final post = Post.fromJson(item);
            post.fullId = fullId;
            messagesDB[key].add(post);

            processedMessageIds.add(fullId);
            newMessages.add(post);
          }
        }
        if (currentServerData?.id == serverId &&
            currentChannelId == channelName &&
            newMessages.isNotEmpty) {
          print('UPDATE MESSAGES UI');

          final scrollElem = UI['content']['chatWindow']['scrollElem'];

          final autoScroll = scrollElem.scrollHeight - 5 <=
              scrollElem.clientHeight + scrollElem.scrollTop;

          for (final msg in newMessages) {
            insertMessage(msg);
          }

          if (autoScroll) {
            scrollElem.scrollTop =
                scrollElem.scrollHeight - scrollElem.clientHeight;
          }
        }
      } catch (e, st) {
        print(e);
        print(st);
      }
    });
  }
}

void RenderServers() {
  var finalHtml = '';

  servers.forEach((serverId, server) {
    final serverIcon = mySky.skynetClient.resolveSkylink(server.icon);
    var serverInitials = "";

    if (serverIcon == null) {
      server.name.split(' ').forEach((e) => serverInitials += e[0]);
    }

    /* if (id == 0)
        setActiveServerId = server.Id; */

    finalHtml += ServerIconTemplate.replaceAll(
            "{initials}", escape(serverInitials.toUpperCase()))
        .replaceAll("{icon}", escape(serverIcon))
        .replaceAll("{id}", escape(serverId));
  });
  document
      .getElementById("serverElemList")
      .setInnerHtml(finalHtml, validator: TrustedNodeValidator());

  /* TODO if (setActiveServerId)
      App.RenderChannels(setActiveServerId); */
}

const ServerIconTemplate =
    "<a href=\"javascript:skychatClick('server','{id}');\" id=\"server_{id}\">" +
        "{initials}" +
        "<div style=\"background-image: url('{icon}');\"></div>" +
        "</a>";

/// A [NodeValidator] which allows everything.
class TrustedNodeValidator implements NodeValidator {
  bool allowsElement(Element element) => true;
  bool allowsAttribute(element, attributeName, value) => true;
}

void RenderChannels(String serverId) {
  var serverElement = document.getElementById("server_" + serverId);
  if (serverElement.classes.contains('active')) {
    return;
  }
  final Element otherServer =
      (UI['nav'] as Element).getElementsByClassName("active").firstOrNull;
  if (otherServer != null && serverElement.id != otherServer.id) {
    otherServer.classes.remove("active");
  }

  serverElement.classes.add("active");

  try {
    final serverData =
        servers[serverId]; // await App.FindServerWithId(serverId);

    UI['header']['serverNameElem'].innerText = serverData.name;
    currentServerData = serverData;
    currentChannelId = null;

    var channelsHtml = "";
    for (final channelName in serverData.channels.keys) {
      channelsHtml += UI['header']['serverChannelTemplate']
          .replaceAll("{id}", escape(channelName))
          .replaceFirst(
              "{active}",
              escape(channelName == serverData.channels.keys.firstOrNull
                  ? "active"
                  : ""))
          .replaceFirst("{name}", escape(channelName));
    }
    final browseHtml = UI['header']['serverCatergoryTemplate']
        .replaceAll("{id}", "1")
        .replaceFirst("{name}", "Text Channels")
        .replaceFirst("{count}", serverData.channels.length.toString())
        .replaceFirst("{channels}", channelsHtml);

    /*  serverData.Catergories.forEach((catergory, catergoryIndex) => {
        var channelsHtml = "";
        catergory.Channels.forEach((channel, channelIndex) => {
          channelsHtml += App.UI.header.serverChannelTemplate
            .replaceAll("{id}", channel.Id)
            .replace("{active}", catergoryIndex == 0 && channelIndex == 0 ? "active" : "")
            .replace("{name}", channel.Name);
        });
        browseHtml += App.UI.header.serverCatergoryTemplate
          .replaceAll("{id}", catergory.Id)
          .replace("{name}", catergory.Name)
          .replace("{count}", catergory.Channels.length)
          .replace("{channels}", channelsHtml);
      }); */
    UI['header']['serverCatergories']
        .setInnerHtml(browseHtml, validator: TrustedNodeValidator());

    (UI['header']['serverCatergories'].querySelector(".channel") as Element)
        .click();

    RenderMemberList();

    // validator: TrustedNodeValidator()
  } catch (e, st) {
    print(e);
    print(st);
    window.alert("Runtime Error: Server not found!");
  }
}

void RenderMemberList() {
  var membersHtml = "";

  final members = memberListDB[currentServerData?.id];
  if (members == null) {
    UI['content']['memberCount'].innerText = 'Loading...';

    UI['aside']['membersList'].setInnerHtml('');
    return;
  }

  members.keys.forEach((userId) {
    membersHtml += "<div class=\"entry user-${userId}\">{user}</div>"
        .replaceAll("{user}", userId);
  });
  UI['content']['memberCount'].innerText = members.length.toString();

  UI['aside']['membersList'].setInnerHtml(membersHtml);

/*   for (final userId in members.keys) {
    loadUserProfileAsync(userId);
  } */
}

void loadUserProfileAsync(String userId) async {
  final profile = await mySky.profileDAC.getProfile(userId);

  document.querySelectorAll('.user-$userId').forEach((element) {
    if (profile == null) {
      element.innerText = 'No profile set';
    } else {
      element.innerText = profile.username;
      element.style.fontStyle = 'normal';
    }
  });
}

void RenderInputField() {
  final InputElement inputForm = document.querySelector("#msgField");

  final isMember =
      (memberListDB[currentServerData?.id] ?? {}).containsKey(mySky.userId);

  if (isMember) {
    inputForm.disabled = false;
    inputForm.placeholder = "Say something...";
  } else {
    inputForm.value = '';
    inputForm.disabled = true;
    inputForm.placeholder =
        "You can't send messages until an Admin of this server verified you";
    // inputForm.placeholder = "You do not have permission to send messages here";
  }
}

void RenderMessages(String channelId) async {
  // Get currently active channel
  var currentChannelElem =
      UI['header']['serverCatergories'].querySelector(".channel.active");
  if (currentChannelId == channelId) return;

  UI['content']['chatWindow']['elem'].setInnerHtml('');
  var newChannelElem =
      UI['header']['serverCatergories'].querySelector("#channel_" + channelId);

  currentChannelElem.classes.remove("active");
  newChannelElem.classes.add("active");

/*   if (App.currentSet.channelData.Muted) {
    App.UI.content.inputForm.msg.disabled = true;
    App.UI.content.inputForm.msg.placeholder =
        "You do not have permission to send messages here";
    App.UI.content.inputForm.msg.value = string.Empty;
  } else { */

  RenderInputField();

/*   } */
  currentChannelId = channelId;

  UI['content']['chatHeader'].innerText = channelId;

  // final Set<String> userIdsToLoad = {};

  for (final post
      in (messagesDB['${currentServerData?.id}#$channelId'] ?? [])) {
    insertMessage(post);
  }

  final scrollElem = UI['content']['chatWindow']['scrollElem'];

  scrollElem.scrollTop = scrollElem.scrollHeight - scrollElem.clientHeight;

  if (isRunningInIframe) {
    final title = '#$channelId - ${currentServerData?.name ?? ''}';
    // print('isRunningInIframe -> set window title: ${title}');
    window.parent.postMessage(
      {
        'skappy': true,
        'action': 'setTitle',
        'name': window.name,
        'data': '${base64Url.encode(utf8.encode(title))}'
      },
      '*',
    );
  }
}

void insertMessage(Post post, [bool isDraft = false]) {
  try {
    print('insertMessage');
    final userId = post.content.ext['chatbubble.hns']['userId'];
    final index = post.content.ext['chatbubble.hns']['i'];
    final id = 'msg_${userId}_$index';

    final existingElement = document.getElementById(id);

    if (existingElement != null) {
      existingElement.remove();
    }

    final Element chatWindowElement = UI['content']['chatWindow']['elem'];
    // TODO Show loading indicator if null

    final baseElem = document.createElement("div");
    if (isDraft) {
      baseElem.style.opacity = '40%';
    }
    baseElem.setAttribute("id", id);
    baseElem.classes.add("chatEntry");

    final usernameField = document.createElement("span");
    if (userId == null) {
      usernameField.innerText = currentServerData?.name;

      usernameField.style.color = '#00C65E';
    } else {
      usernameField.style.fontStyle = 'italic';
      usernameField.innerText = 'Loading username...';
      usernameField.classes.add('user-${userId}');
      // userIdsToLoad.add(userId);

    }

    baseElem.append(usernameField);

    if (post.ts != null) {
      final dateTimeField = document.createElement('span');

      dateTimeField.innerText =
          ' ${DateFormat.Hm().format(DateTime.fromMillisecondsSinceEpoch(post.ts))}';

      baseElem.append(dateTimeField);
    }

    String msgText = escape(post?.content?.text ?? '');

    if (msgText.length > 3000) {
      msgText = msgText.substring(0, 3000) +
          '... [cut down from ${msgText.length} to 3000 characters by your client]';
    }

    msgText = msgText.replaceAllMapped(RegExp(r'(^| )[#@][^ ]+'), (match) {
      final str = msgText.substring(match.start, match.end);

      if (str.trimLeft().startsWith('@')) {
        return '<a>$str</a>';
      } else {
        return '<a href="${str.trim()}">$str</a>';
      }
    });

    /*   if (true) {
      msgText = msgText.replaceAllMapped(RegExp(r' href="([^"]+)"'), (match) {
        final str = match.group(1);
    
        return ' href="javascript:alert(\'${str}\')"';
      });
    } */

    msgText = msgText.replaceAllMapped('sia://', (match) {
      final str =
          msgText.substring(match.end).split(' ').first.split('/').first;

      if (str.length < 46) {
        return 'https://${mySky.skynetClient.portalHost}/hns/';
      } else {
        return 'https://${mySky.skynetClient.portalHost}/';
      }
    });

    msgText = md.markdownToHtml(
      msgText,
      extensionSet: md.ExtensionSet.gitHubWeb,
    );

    msgText = msgText
        .replaceAll('>https://${mySky.skynetClient.portalHost}/', '>sia://')
        .trim();

    try {
      if (msgText.startsWith('<p>') && msgText.endsWith('</p>')) {
        msgText = msgText.substring(3, msgText.length - 4);
      }
    } catch (e) {}

    final messageField = document.createElement("div");

    messageField.setInnerHtml(
      msgText,
      validator: MessageContentNodeValidator(),
    );

    messageField.querySelectorAll('a').forEach((element) {
      if (isRunningInIframe) {
        final href = element.getAttribute('href');

        element.setAttribute('onclick',
            "window.parent.postMessage({'skappy':true,'action':'launch','name':'${window.name}','data':'${base64Url.encode(utf8.encode(href))}'},'*')");
        element.setAttribute('href', 'javascript:void(0)');
        element.title = href;
      } else {
        element.setAttribute('target', '_blank');
      }
    });

    //innerText = post.content.text;
    baseElem.append(messageField);

    chatWindowElement.append(baseElem);
    if (userId != null) loadUserProfileAsync(userId);
  } catch (e, st) {
    print(
        'Exception $e while inserting message in DOM. Post: ${json.encode(post)} stack trace: $st');
  }
}

class MessageContentNodeValidator implements NodeValidator {
  final defaultValidator = NodeValidatorBuilder.common();

  @override
  bool allowsElement(Element element) {
    return defaultValidator.allowsElement(element);
  }

  @override
  bool allowsAttribute(element, attributeName, value) {
/*     print(element.tagName);
    print(element.className);
    print(element.nodeName); */
    if (element.tagName == 'A') {
      if (attributeName == 'href') {
        return true;
      }
    }
    /* else if (element.tagName == 'IMG') {
      if (attributeName == 'src') {
        if (value.startsWith('https://${mySky.skynetClient.portalHost}/')) {
          return true;
        }
      }
    } */

    return defaultValidator.allowsAttribute(element, attributeName, value);
  }
}

class AllowSkylinksUrlPolicy implements UriPolicy {
  final AnchorElement _hiddenAnchor = AnchorElement();
  final Location _loc = window.location;

  @override
  bool allowsUri(String uri) {
    _hiddenAnchor.href = uri;

    if (_hiddenAnchor.hostname == _loc.hostname) return true;
    // IE leaves an empty hostname for same-origin URIs.
    return (_hiddenAnchor.hostname == mySky.skynetClient.portalHost) ||
        (_hiddenAnchor.hostname == '' &&
            _hiddenAnchor.port == '' &&
            (_hiddenAnchor.protocol == ':' || _hiddenAnchor.protocol == ''));
  }
}

// TODO Attachments
/*      if (msg.Attachment) {
        if (msg.Attachment.Type == "img") {
          let imgPreview = document.createElement("img");
          imgPreview.setAttribute("src", msg.Attachment.Source);
          imgPreview.classList.add("fileAttachment");
          baseElem.appendChild(imgPreview);
        }
        else if (msg.Attachment.Type == "vid") {
          let vidPreview = document.createElement("video");
          vidPreview.classList.add("fileAttachment");
          vidPreview.setAttribute("controls", string.Empty);

          let vidSource = document.createElement("source");
          vidSource.setAttribute("src", msg.Attachment.Source);
          vidPreview.appendChild(vidSource);

          baseElem.appendChild(vidPreview);
        }
        else {
          let fileAttachment = document.createElement("div");
          fileAttachment.classList.add("fileAttachment");
          {
            let fileDetails = document.createElement("div");
            fileDetails.classList.add("fileDetails");
            {
              let fileName = document.createElement("a");
              fileName.setAttribute("href", "/attachment/" + msg.Attachment.Id + "/" + msg.Attachment.Name);
              fileName.setAttribute("target", "_blank");
              fileName.appendChild(document.createTextNode(msg.Attachment.Name));
              fileDetails.appendChild(fileName);

              let fileSize = document.createElement("span");
              fileSize.classList.add("fileSize");
              fileSize.appendChild(document.createTextNode(msg.Attachment.Size + " bytes"));
              fileDetails.appendChild(fileSize);
            }
            fileAttachment.appendChild(fileDetails);

            let downloadBtn = document.createElement("a");
            downloadBtn.classList.add("downloadBtn");
            downloadBtn.setAttribute("href", "/attachment/" + msg.Attachment.Id + "/" + msg.Attachment.Name);
            downloadBtn.setAttribute("download", string.Empty);
            fileAttachment.appendChild(downloadBtn);
          }
          baseElem.appendChild(fileAttachment);
        }
      } */
