part of '../main.dart';

class ConnectionManager {

  static final ConnectionManager _instance = ConnectionManager._internal();

  factory ConnectionManager() {
    return _instance;
  }

  ConnectionManager._internal();

  String _domain;
  String _port;
  String displayHostname;
  String _webSocketAPIEndpoint;
  String httpWebHost;
  String _token;
  String _tempToken;
  String oauthUrl;
  String webhookId;
  bool settingsLoaded = false;
  int appIntegrationVersion;
  bool get isAuthenticated => _token != null;
  StreamSubscription _socketSubscription;
  Duration connectTimeout = Duration(seconds: 15);

  bool isConnected = false;

  var onStateChangeCallback;
  var onLovelaceUpdatedCallback;

  IOWebSocketChannel _socket;

  int _currentMessageId = 0;
  Map<String, Completer> _messageResolver = {};

  Future init({bool loadSettings, bool forceReconnect: false}) async {
    Completer completer = Completer();
    bool stopInit = false;
    if (loadSettings) {
      Logger.d("Loading settings...");
      SharedPreferences prefs = await SharedPreferences.getInstance();
      _domain = prefs.getString('hassio-domain');
      _port = prefs.getString('hassio-port');
      webhookId = prefs.getString('app-webhook-id');
      appIntegrationVersion = prefs.getInt('app-integration-version') ?? 0;
      displayHostname = "$_domain:$_port";
      _webSocketAPIEndpoint =
      "${prefs.getString('hassio-protocol')}://$_domain:$_port/api/websocket";
      httpWebHost =
      "${prefs.getString('hassio-res-protocol')}://$_domain:$_port";
      Logger.d('$_domain$_port');
      if ((_domain == null) || (_port == null) ||
          (_domain.isEmpty) || (_port.isEmpty)) {
        completer.completeError(HACException.checkConnectionSettings());
        stopInit = true;
      } else {
        final storage = new FlutterSecureStorage();
        try {
          _token = await storage.read(key: "hacl_llt");
          Logger.d("Long-lived token read successful");
          oauthUrl = "$httpWebHost/auth/authorize?client_id=${Uri.encodeComponent(
              'https://ha-client.app')}&redirect_uri=${Uri
              .encodeComponent(
              'https://ha-client.app/service/auth_callback.html')}";
          settingsLoaded = true;
        } catch (e, stacktrace) {
          completer.completeError(HACException("Error reading login details", actions: [HAErrorAction.tryAgain(type: HAErrorActionType.FULL_RELOAD), HAErrorAction.loginAgain()]));
          Logger.e("Error reading secure storage: $e", stacktrace: stacktrace);
          stopInit = true;
        }
      }
    } else {
      if ((_domain == null) || (_port == null) ||
          (_domain.isEmpty) || (_port.isEmpty)) {
        completer.completeError(HACException.checkConnectionSettings());
        stopInit = true;
      }
    }

    if (!stopInit) {
      if (_token == null) {
        AuthManager().start(
            oauthUrl: oauthUrl
        ).then((token) {
          Logger.d("Token from AuthManager recived");
          _tempToken = token;
          _doConnect(completer: completer, forceReconnect: forceReconnect);
        }).catchError((e) {
          completer.completeError(e);
        });
      } else {
        _doConnect(completer: completer, forceReconnect: forceReconnect);
      }
    }

    return completer.future;
  }

  void _doConnect({Completer completer, bool forceReconnect}) {
    if (forceReconnect || !isConnected) {
      _disconnect().then((_){
        _connect().timeout(connectTimeout).then((_) {
          completer?.complete();
        }).catchError((e) {
          _disconnect().then((_) {
            if (e is TimeoutException) {
              if (connecting != null && !connecting.isCompleted) {
                connecting.completeError(HACException("Connection timeout"));
              }
              completer?.completeError(HACException("Connection timeout"));
            } else if (e is HACException) {
              completer?.completeError(e);
            } else {
              completer?.completeError(HACException("${e.toString()}"));
            }
          });
        });
      });
    } else {
      completer?.complete();
    }
  }

  Completer connecting;

  Future _connect() {
    if (connecting != null && !connecting.isCompleted) {
      Logger.w("Previous connection attempt pending...");
      return connecting.future;
    } else {
      connecting = Completer();
      _disconnect().then((_) {
        Logger.d("Socket connecting...");
        try {
          _socket = IOWebSocketChannel.connect(
            _webSocketAPIEndpoint, pingInterval: Duration(seconds: 15));
          _socketSubscription = _socket.stream.listen(
                  (message) {
                isConnected = true;
                var data = json.decode(message);
                if (data["type"] == "auth_required") {
                  Logger.d("[Received] <== ${data.toString()}");
                  _authenticate().then((_) {
                    Logger.d('Authentication complete');
                    connecting.complete();
                  }).catchError((e) {
                    if (!connecting.isCompleted) connecting.completeError(e);
                  });
                } else if (data["type"] == "auth_ok") {
                  Logger.d("[Received] <== ${data.toString()}");
                  Logger.d("[Connection] Subscribing to events");
                  sendSocketMessage(
                    type: "subscribe_events",
                    additionalData: {"event_type": "lovelace_updated"},
                  );
                  sendSocketMessage(
                    type: "subscribe_events",
                    additionalData: {"event_type": "state_changed"},
                  ).whenComplete((){
                    _messageResolver["auth"]?.complete();
                    _messageResolver.remove("auth");
                    if (_token != null) {
                      if (!connecting.isCompleted) connecting.complete();
                    }
                  });
                } else if (data["type"] == "auth_invalid") {
                  Logger.d("[Received] <== ${data.toString()}");
                  _messageResolver["auth"]?.completeError(HACException("${data["message"]}", actions: [HAErrorAction.loginAgain()]));
                  _messageResolver.remove("auth");
                  if (!connecting.isCompleted) connecting.completeError(HACException("${data["message"]}", actions: [HAErrorAction.tryAgain(title: "Retry"), HAErrorAction.loginAgain(title: "Relogin")]));
                } else {
                  _handleMessage(data);
                }
              },
              cancelOnError: true,
              onDone: () => _handleSocketClose(connecting),
              onError: (e) => _handleSocketError(e, connecting)
          );
        } catch(exeption) {
          connecting.completeError(HACException("${exeption.toString()}"));
        }
      });
      return connecting.future;
    }
  }

  Future _disconnect() {
    Completer completer = Completer();
    if (!isConnected) {
      completer.complete();
    } else {
      isConnected = false;
      List<Future> fl = [];
      Logger.d("Socket disconnecting...");
      if (_socketSubscription != null) {
        fl.add(_socketSubscription.cancel());
      }
      if (_socket != null && _socket.sink != null &&
          _socket.closeCode == null) {
        fl.add(_socket.sink.close().timeout(Duration(seconds: 3)));
      }
      Future.wait(fl).whenComplete(() => completer.complete());
    }
    return completer.future;
  }

  _handleMessage(data) {
    if (data["type"] == "result") {
      if (data["id"] != null && data["success"]) {
        //Logger.d("[Received] <== Request id ${data['id']} was successful");
        _messageResolver["${data["id"]}"]?.complete(data["result"]);
      } else if (data["id"] != null) {
        Logger.e("[Received] <== Error received on request id ${data['id']}: ${data['error']}", skipCrashlytics: true);
        _messageResolver["${data["id"]}"]?.completeError("${data["error"]["code"]}: ${data["error"]["message"]}");
      }
      _messageResolver.remove("${data["id"]}");
    } else if (data["type"] == "event") {
      if (data["event"] != null) {
        if (data["event"]["event_type"] == "state_changed") {
          Logger.d("[Received] <== ${data['type']}.${data["event"]["event_type"]}: ${data["event"]["data"]["entity_id"]}");
          onStateChangeCallback(data["event"]["data"]);
        } else if (data["event"]["event_type"] == "lovelace_updated") {
          Logger.d("[Received] <== ${data['type']}.${data["event"]["event_type"]}: $data");
          onLovelaceUpdatedCallback();
        }  
      }
    } else {
      Logger.d("[Received unhandled] <== ${data.toString()}");
    }
  }

  void _handleSocketClose(Completer connectionCompleter) {
    Logger.d("Socket disconnected.");
    _disconnect().then((_) {
      if (!connectionCompleter.isCompleted) {
        isConnected = false;
        connectionCompleter.completeError(HACException("Disconnected", actions: [HAErrorAction.reconnect()]));
      }
      eventBus.fire(ShowErrorEvent(HACException("Unable to connect to Home Assistant")));  
    });
  }

  void _handleSocketError(e, Completer connectionCompleter) {
    Logger.e("Socket stream Error: $e", skipCrashlytics: true);
    _disconnect().then((_) {
      if (!connectionCompleter.isCompleted) {
        isConnected = false;
        connectionCompleter.completeError(HACException("Disconnected", actions: [HAErrorAction.reconnect()]));
      }
      eventBus.fire(ShowErrorEvent(HACException("Unable to connect to Home Assistant")));  
    });
  }

  Future _authenticate() {
    Completer completer = Completer();
    if (_token != null) {
      Logger.d( "Long-lived token exist");
      Logger.d( "[Sending] ==> auth request");
      sendSocketMessage(
          type: "auth",
          additionalData: {"access_token": "$_token"},
          auth: true
      ).then((_) {
        completer.complete();
      }).catchError((e) => completer.completeError(e));
    } else if (_tempToken != null) {
      Logger.d("We have temp token. Loging in...");
      sendSocketMessage(
          type: "auth",
          additionalData: {"access_token": "$_tempToken"},
          auth: true
      ).then((_) {
        Logger.d("Requesting long-lived token...");
        _getLongLivedToken().then((_) {
          Logger.d("getLongLivedToken finished");
          completer.complete();
        }).catchError((e) {
          Logger.e("Can't get long-lived token: $e");
          throw e;
        });
      }).catchError((e) => completer.completeError(e));
    } else {
      completer.completeError(HACException("General login error"));
    }
    return completer.future;
  }

  Future logout() {
    Logger.d("Logging out");
    Completer completer = Completer();
    _disconnect().whenComplete(() {
      _token = null;
      _tempToken = null;
      final storage = new FlutterSecureStorage();
      storage.delete(key: "hacl_llt").whenComplete((){
        completer.complete();
      });
    });
    return completer.future;
  }

  Future _getLongLivedToken() {
    Completer completer = Completer();
    sendSocketMessage(type: "auth/long_lived_access_token", additionalData: {"client_name": "HA Client app ${DateTime.now().millisecondsSinceEpoch}", "lifespan": 365}).then((data) {
      Logger.d("Got long-lived token.");
      _token = data;
      _tempToken = null;
      final storage = new FlutterSecureStorage();
      storage.write(key: "hacl_llt", value: "$_token").then((_) {
        SharedPreferences.getInstance().then((prefs) {
          prefs.setBool("oauth-used", true);
          completer.complete();
        });
      }).catchError((e) {
        throw e;
      });
    }).catchError((e) {
      completer.completeError(HACException("Authentication error: $e", actions: [HAErrorAction.reload(title: "Retry"), HAErrorAction.loginAgain(title: "Relogin")]));
    });
    return completer.future;
  }

  Future sendSocketMessage({String type, Map additionalData, bool auth: false}) {
    Completer _completer = Completer();
    Map dataObject = {"type": "$type"};
    String callbackName;
    if (!auth) {
      _incrementMessageId();
      dataObject["id"] = _currentMessageId;
      callbackName = "$_currentMessageId";
    } else {
      callbackName = "auth";
    }
    if (additionalData != null) {
      dataObject.addAll(additionalData);
    }
    _messageResolver[callbackName] = _completer;
    String rawMessage = json.encode(dataObject);
    if (!isConnected) {
      _connect().timeout(connectTimeout).then((_) {
        Logger.d("[Sending] ==> ${auth ? "type="+dataObject['type'] : rawMessage}");
        _socket.sink.add(rawMessage);
      }).catchError((e) {
        if (!_completer.isCompleted) {
          _completer.completeError(HACException("No connection to Home Assistant", actions: [HAErrorAction.reconnect()]));
        }
      });
    } else {
      Logger.d("[Sending] ==> ${auth ? "type="+dataObject['type'] : rawMessage}");
      _socket.sink.add(rawMessage);
    }
    return _completer.future;
  }

  void _incrementMessageId() {
    _currentMessageId += 1;
  }

  Future callService({@required String domain, @required String service, entityId, Map data}) {
    eventBus.fire(NotifyServiceCallEvent(domain, service, entityId));
    Logger.d("Service call: $domain.$service, $entityId, $data");
    Completer completer = Completer();
    Map serviceData = {};
    if (entityId != null) {
      serviceData["entity_id"] = entityId;
    }
    if (data != null && data.isNotEmpty) {
      serviceData.addAll(data);
    }
    if (serviceData.isNotEmpty)
      sendHTTPPost(
        endPoint: "/api/services/$domain/$service",
        data: json.encode(serviceData)
      ).then((data) => completer.complete(data)).catchError((e) => completer.completeError(HACException(e.toString())));
      //return sendSocketMessage(type: "call_service", additionalData: {"domain": domain, "service": service, "service_data": serviceData});
    else
      sendHTTPPost(
          endPoint: "/api/services/$domain/$service"
      ).then((data) => completer.complete(data)).catchError((e) => completer.completeError(HACException(e.toString())));
      //return sendSocketMessage(type: "call_service", additionalData: {"domain": domain, "service": service});
    return completer.future;
  }

  Future<List> getHistory(String entityId) async {
    DateTime now = DateTime.now();
    //String endTime = formatDate(now, [yyyy, '-', mm, '-', dd, 'T', HH, ':', nn, ':', ss, z]);
    String startTime = formatDate(now.subtract(Duration(hours: 24)), [yyyy, '-', mm, '-', dd, 'T', HH, ':', nn, ':', ss, z]);
    String url = "$httpWebHost/api/history/period/$startTime?&filter_entity_id=$entityId";
    Logger.d("[Sending] ==> HTTP /api/history/period/$startTime?&filter_entity_id=$entityId");
    http.Response historyResponse;
    historyResponse = await http.get(url, headers: {
      "authorization": "Bearer $_token",
      "Content-Type": "application/json"
    });
    var history = json.decode(historyResponse.body);
    if (history is List) {
      Logger.d( "[Received] <== HTTP ${history.first.length} history recors");
      return history;
    } else {
      return [];
    }
  }

  Future sendHTTPPost({String endPoint, String data, String contentType: "application/json", bool includeAuthHeader: true}) async {
    Completer completer = Completer();
    String url = "$httpWebHost$endPoint";
    Logger.d("[Sending] ==> HTTP $endPoint");
    Map<String, String> headers = {};
    if (contentType != null) {
      headers["Content-Type"] = contentType;
    }
    if (includeAuthHeader) {
      headers["authorization"] = "Bearer $_token";
    }
    http.post(
        url,
        headers: headers,
        body: data
    ).then((response) {
      if (response.statusCode >= 200 && response.statusCode < 300 ) {
        Logger.d("[Received] <== HTTP ${response.statusCode}");
        completer.complete(response.body);
      } else {
        Logger.d("[Received] <== HTTP ${response.statusCode}: ${response.body}");
        completer.completeError(response);
      }
    }).catchError((e) {
      completer.completeError(e);
    });
    return completer.future;
  }

}