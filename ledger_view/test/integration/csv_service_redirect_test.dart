// Integration tests for CsvService HTTP redirect behaviour.
//
// These tests start a real local HttpServer and therefore MUST NOT run under
// TestWidgetsFlutterBinding (which intercepts dart:io HttpClient and returns
// HTTP 400 for every request).  The flutter_test_config.dart sibling to this
// file ensures the binding is not initialised for this directory.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_view/models/customer.dart';
import 'package:ledger_view/services/csv_service.dart';

void main() {
  group('CsvService - Master Write API redirect behaviour', () {
    const testCustomer = Customer(
      customerId: '133',
      name: 'Arumugam',
      mobileNumber: '12345466',
      area: 'NSK',
      groupName: 'Retail',
      gpay: '9876543210',
      bank: 'SBI',
      accountNumber: '133',
    );

    // 307 Temporary Redirect MUST preserve the request method and body.
    test('keeps POST body when following 307 redirect', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      String? redirectedMethod;
      String? redirectedBody;

      server.listen((request) async {
        if (request.uri.path == '/write') {
          request.response
            ..statusCode = HttpStatus.temporaryRedirect // 307
            ..headers.set(
              HttpHeaders.locationHeader,
              'http://${server.address.host}:${server.port}/final',
            );
          await request.response.close();
          return;
        }

        if (request.uri.path == '/final') {
          redirectedMethod = request.method;
          redirectedBody = await utf8.decoder.bind(request).join();
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'success': true}));
          await request.response.close();
          return;
        }

        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      await CsvService.updateMasterContactDetails(
        writeApiUrl: 'http://${server.address.host}:${server.port}/write',
        customer: testCustomer,
      );

      expect(redirectedMethod, equals('POST'));
      expect(redirectedBody, isNotEmpty);
      expect(redirectedBody, contains('"accountNumber":"133"'));
      expect(redirectedBody, contains('"mobileNo":"12345466"'));
    });
  });

  group('CsvService - Master contact sync', () {
    // Google Apps Script responds with a 302 redirect.  The implementation
    // must follow it as a GET (standard browser behaviour for 302).
    test('follows 302 redirect and accepts success response', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      final baseUrl = 'http://${server.address.host}:${server.port}';

      server.listen((HttpRequest request) async {
        if (request.uri.path == '/sync') {
          request.response.statusCode = HttpStatus.found; // 302
          request.response.headers.set(
            HttpHeaders.locationHeader,
            '$baseUrl/result',
          );
          await request.response.close();
          return;
        }

        if (request.uri.path == '/result' && request.method == 'GET') {
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType.json;
          request.response
              .write(jsonEncode({'success': true, 'message': 'ok'}));
          await request.response.close();
          return;
        }

        request.response.statusCode = HttpStatus.methodNotAllowed;
        await request.response.close();
      });

      await CsvService.updateMasterContactDetails(
        writeApiUrl: '$baseUrl/sync',
        customer: const Customer(
          customerId: '133',
          name: 'Arumugam',
          mobileNumber: '12345466',
          accountNumber: '133',
        ),
      );
    });

    test('throws when redirected response returns API failure', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      final baseUrl = 'http://${server.address.host}:${server.port}';

      server.listen((HttpRequest request) async {
        if (request.uri.path == '/sync') {
          request.response.statusCode = HttpStatus.found; // 302
          request.response.headers.set(
            HttpHeaders.locationHeader,
            '$baseUrl/result',
          );
          await request.response.close();
          return;
        }

        if (request.uri.path == '/result' && request.method == 'GET') {
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({'success': false, 'message': 'No record found'}),
          );
          await request.response.close();
          return;
        }

        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      await expectLater(
        () => CsvService.updateMasterContactDetails(
          writeApiUrl: '$baseUrl/sync',
          customer: const Customer(
            customerId: '133',
            name: 'Arumugam',
            mobileNumber: '12345466',
            accountNumber: '133',
          ),
        ),
        throwsA(
          predicate(
            (e) => e.toString().contains('No record found'),
          ),
        ),
      );
    });
  });
}
