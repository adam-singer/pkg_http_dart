// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library client;

import 'dart:io';

import 'base_client.dart';
import 'base_request.dart';
import 'streamed_response.dart';
import 'utils.dart';

/// An HTTP client which takes care of maintaining persistent connections across
/// multiple requests to the same server. If you only need to send a single
/// request, it's usually easier to use [head], [get], [post],
/// [put], or [delete] instead.
///
/// When creating an HTTP client class with additional functionality, it's
/// recommended that you subclass [BaseClient] and wrap another instance of
/// [BaseClient] rather than subclassing [Client] directly. This allows all
/// subclasses of [BaseClient] to be mutually composable.
class Client extends BaseClient {
  /// The underlying `dart:io` HTTP client.
  HttpClient _inner;

  /// Creates a new HTTP client.
  Client() : _inner = new HttpClient();

  /// Sends an HTTP request and asynchronously returns the response.
  Future<StreamedResponse> send(BaseRequest request) {
    var stream = request.finalize();

    var completer = new Completer<StreamedResponse>();
    var connection = _inner.openUrl(request.method, request.url);
    connection.onError = (e) {
      async.then((_) {
        // TODO(nweiz): remove this when issue 4974 is fixed
        if (completer.future.isComplete) throw e;

        completer.completeException(e);
      });
    };

    connection.onRequest = (underlyingRequest) {
      underlyingRequest.contentLength = request.contentLength;
      underlyingRequest.persistentConnection = request.persistentConnection;
      request.headers.forEach((name, value) {
        underlyingRequest.headers.set(name, value);
      });

      if (stream.closed) {
        underlyingRequest.outputStream.close();
      } else {
        stream.pipe(underlyingRequest.outputStream);
      }
    };

    connection.onResponse = (response) {
      var headers = <String>{};
      response.headers.forEach((key, value) => headers[key] = value);

      completer.complete(new StreamedResponse(
          response.inputStream,
          response.statusCode,
          response.contentLength,
          headers: headers,
          isRedirect: response.isRedirect,
          persistentConnection: response.persistentConnection,
          reasonPhrase: response.reasonPhrase));
    };

    return completer.future;
  }

  /// Closes the client. This terminates all active connections. If a client
  /// remains unclosed, the Dart process may not terminate.
  void close() {
    if (_inner != null) _inner.shutdown();
    _inner = null;
  }
}
