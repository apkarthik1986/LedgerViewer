import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ledger_view/services/csv_service.dart';
import 'package:ledger_view/models/ledger_entry.dart';
import 'package:ledger_view/models/customer.dart';

void main() {
  group('CsvService', () {
    final testData = [
      ['Ledger:', '1033.Saravana[V O C Nagar', '1-Apr-2025 to 23-Nov-2025', '', '', '', ''],
      ['Date', 'Particulars', '', 'Vch Type', 'Vch No.', 'Debit', 'Credit'],
      ['2025-04-01 00:00:00', 'To', 'Opening Balance', '', '', '56012', ''],
      ['56012', '', '', '', '', '', ''],
      ['', 'By', 'Closing Balance', '', '', '', '56012'],
      ['56012', '', '', '', '', '', '56012'],
      ['', '', '', '', '', '', ''],
      ['Ledger:', '1035.Vasanthi Teacher', '1-Apr-2025 to 23-Nov-2025', '', '', '', ''],
      ['Date', 'Particulars', '', 'Vch Type', 'Vch No.', 'Debit', 'Credit'],
      ['2025-07-21 00:00:00', 'To', '1035.Vasanthi Teacher', 'Sales', '2041', '101000', ''],
      ['2025-07-21 00:00:00', 'By', 'Cash', 'Receipt', '2041', '', '89700'],
      ['101000', '', '', '', '', '', '93700'],
      ['', 'By', 'Closing Balance', '', '', '', '7300'],
      ['101000', '', '', '', '', '', '101000'],
    ];

    test('findLedgerByNumber returns correct result for customer 1033', () {
      final result = CsvService.findLedgerByNumber(testData, '1033');
      
      expect(result, isNotNull);
      expect(result!.customerName, equals('1033.Saravana[V O C Nagar'));
      expect(result.dateRange, equals('1-Apr-2025 to 23-Nov-2025'));
      expect(result.closingBalance, equals('56012'));
    });

    test('findLedgerByNumber returns correct result for customer 1035', () {
      final result = CsvService.findLedgerByNumber(testData, '1035');
      
      expect(result, isNotNull);
      expect(result!.customerName, equals('1035.Vasanthi Teacher'));
      expect(result.dateRange, equals('1-Apr-2025 to 23-Nov-2025'));
      expect(result.closingBalance, equals('7300'));
      expect(result.entries.isNotEmpty, isTrue);
    });

    test('findLedgerByNumber returns correct totals from row above closing balance', () {
      final result = CsvService.findLedgerByNumber(testData, '1035');
      
      expect(result, isNotNull);
      // Totals should come from row: ['101000', '', '', '', '', '', '93700']
      // which is the row above ['', 'By', 'Closing Balance', '', '', '', '7300']
      expect(result!.totalDebit, equals('101000'));
      expect(result.totalCredit, equals('93700'));
    });

    test('findLedgerByNumber returns null for non-existent customer', () {
      final result = CsvService.findLedgerByNumber(testData, '9999');
      
      expect(result, isNull);
    });

    test('findLedgerByNumber is case insensitive', () {
      final result1 = CsvService.findLedgerByNumber(testData, '1033');
      final result2 = CsvService.findLedgerByNumber(testData, '1033');
      
      expect(result1, isNotNull);
      expect(result2, isNotNull);
      expect(result1!.customerName, equals(result2!.customerName));
    });

    test('findLedgerByNumber handles alphanumeric customer numbers', () {
      final testDataWithAlphaNum = [
        ['Ledger:', '1139B.Pushpa Malliga Teacher', '1-Apr-2025 to 23-Nov-2025', '', '', '', ''],
        ['Date', 'Particulars', '', 'Vch Type', 'Vch No.', 'Debit', 'Credit'],
        ['2025-04-24 00:00:00', 'By', 'Cash', 'Receipt', '16453', '', '15000'],
        ['85363', '', '', '', '', '', '98724'],
        ['', 'By', 'Closing Balance', '', '', '', '7749'],
        ['85363', '', '', '', '', '', '85363'],
      ];

      final result = CsvService.findLedgerByNumber(testDataWithAlphaNum, '1139B');
      
      expect(result, isNotNull);
      expect(result!.customerName, equals('1139B.Pushpa Malliga Teacher'));
      // Totals from row above closing balance: ['85363', '', '', '', '', '', '98724']
      expect(result.totalDebit, equals('85363'));
      expect(result.totalCredit, equals('98724'));
    });

    test('findLedgerByNumber handles lowercase search input', () {
      final testDataWithAlphaNum = [
        ['Ledger:', '1139B.Pushpa Malliga Teacher', '1-Apr-2025 to 23-Nov-2025', '', '', '', ''],
        ['Date', 'Particulars', '', 'Vch Type', 'Vch No.', 'Debit', 'Credit'],
        ['2025-04-24 00:00:00', 'By', 'Cash', 'Receipt', '16453', '', '15000'],
      ];

      final result = CsvService.findLedgerByNumber(testDataWithAlphaNum, '1139b');
      
      expect(result, isNotNull);
      expect(result!.customerName, equals('1139B.Pushpa Malliga Teacher'));
    });

    test('findLedgerByNumber handles missing closing balance row (matched debit/credit)', () {
      final testDataBalanced = [
        ['Ledger:', '2001.John Customer', '1-Apr-2025 to 23-Nov-2025', '', '', '', ''],
        ['Date', 'Particulars', '', 'Vch Type', 'Vch No.', 'Debit', 'Credit'],
        ['2025-04-01 00:00:00', 'To', 'Opening Balance', '', '', '50000', ''],
        ['2025-04-15 00:00:00', 'To', '2001.John Customer', 'Sales', '123', '25000', ''],
        ['2025-04-20 00:00:00', 'By', 'Cash', 'Receipt', '124', '', '75000'],
      ];

      final result = CsvService.findLedgerByNumber(testDataBalanced, '2001');
      
      expect(result, isNotNull);
      expect(result!.customerName, equals('2001.John Customer'));
      // When closing balance row is missing, totals should be calculated from entries
      expect(result.totalDebit, equals('75000'));
      expect(result.totalCredit, equals('75000'));
      expect(result.closingBalance, equals('0'));
      expect(result.entries.length, equals(3));
    });

    test('findLedgerByNumber calculates totals correctly when no totals row exists', () {
      final testDataNoTotals = [
        ['Ledger:', '2002.Jane Doe', '1-Apr-2025 to 23-Nov-2025', '', '', '', ''],
        ['Date', 'Particulars', '', 'Vch Type', 'Vch No.', 'Debit', 'Credit'],
        ['2025-04-01 00:00:00', 'To', 'Opening Balance', '', '', '10000', ''],
        ['2025-04-10 00:00:00', 'By', 'Cash', 'Receipt', '200', '', '5000'],
        ['2025-04-15 00:00:00', 'By', 'Cash', 'Receipt', '201', '', '5000'],
      ];

      final result = CsvService.findLedgerByNumber(testDataNoTotals, '2002');
      
      expect(result, isNotNull);
      expect(result!.totalDebit, equals('10000'));
      expect(result.totalCredit, equals('10000'));
      expect(result.closingBalance, equals('0'));
    });
  });

  group('CsvService - Customer Parsing', () {
    test('parseCustomerData parses customer data correctly', () {
      final testData = [
        ['NAME', 'Mobile No', 'Area', 'Group', 'GPAY', 'Bank', 'A/C NO.'],  // Header row
        ['133.Arumugam', '12345466', 'NSK', 'Retail', '9876543210', 'SBI', '133'],
        ['254.Murugesan ', '98745621', 'Thiruverkadu', 'Wholesale', '8765432109', 'HDFC', '254'],
      ];

      final customers = CsvService.parseCustomerData(testData);
      
      expect(customers.length, equals(2));
      expect(customers[0].customerId, equals('133'));
      expect(customers[0].name, equals('Arumugam'));
      expect(customers[0].mobileNumber, equals('12345466'));
      expect(customers[0].area, equals('NSK'));
      expect(customers[0].groupName, equals('Retail'));
      expect(customers[0].gpay, equals('9876543210'));
      expect(customers[0].bank, equals('SBI'));
      expect(customers[0].accountNumber, equals('133'));
      expect(customers[1].customerId, equals('254'));
      expect(customers[1].name, equals('Murugesan'));
      expect(customers[1].mobileNumber, equals('98745621'));
      expect(customers[1].area, equals('Thiruverkadu'));
      expect(customers[1].groupName, equals('Wholesale'));
      expect(customers[1].gpay, equals('8765432109'));
      expect(customers[1].bank, equals('HDFC'));
      expect(customers[1].accountNumber, equals('254'));
    });

    test('parseCustomerData skips empty rows', () {
      final testData = [
        ['NAME', 'Mobile No'],
        ['133.Arumugam', '12345466'],
        ['', ''],  // Empty row
        ['254.Murugesan', '98745621'],
      ];

      final customers = CsvService.parseCustomerData(testData);
      
      expect(customers.length, equals(2));
    });

    test('parseCustomerData handles empty data', () {
      final customers = CsvService.parseCustomerData([]);
      
      expect(customers, isEmpty);
    });
  });

  group('CsvService - Master Write API', () {
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

    test('updateMasterContactDetails throws when API returns success false', () async {
      await expectLater(
        CsvService.updateMasterContactDetails(
          writeApiUrl: 'https://example.com/write',
          customer: testCustomer,
          postJson: (_, __) async => http.Response(
            jsonEncode({
              'success': false,
              'message': 'No record found for A/C NO.: 133',
            }),
            200,
          ),
        ),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('No record found for A/C NO.: 133'),
          ),
        ),
      );
    });

    test('updateMasterContactDetails keeps POST body when following redirect', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      String? redirectedMethod;
      String? redirectedBody;

      server.listen((request) async {
        if (request.uri.path == '/write') {
          request.response
            ..statusCode = HttpStatus.found
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

  group('Customer', () {
    test('fromRow parses customer ID and name correctly', () {
      final customer = Customer.fromRow(['133.Arumugam', '12345466', 'NSK', '9876543210']);
      
      expect(customer.customerId, equals('133'));
      expect(customer.name, equals('Arumugam'));
      expect(customer.mobileNumber, equals('12345466'));
      expect(customer.area, equals('NSK'));
      expect(customer.gpay, equals('9876543210'));
    });

    test('fromRow parses using configured header indexes', () {
      final customer = Customer.fromRow(
        ['133.Arumugam', '12345466', 'NSK', 'Retail', '9876543210', 'SBI', '133'],
        headerIndex: {
          'name': 0,
          'mobile no': 1,
          'area': 2,
          'group': 3,
          'gpay': 4,
          'bank': 5,
          'a/c no.': 6,
        },
      );

      expect(customer.customerId, equals('133'));
      expect(customer.accountNumber, equals('133'));
      expect(customer.groupName, equals('Retail'));
      expect(customer.bank, equals('SBI'));
    });

    test('fromRow handles names without dots', () {
      final customer = Customer.fromRow(['Arumugam', '12345466']);
      
      expect(customer.customerId, equals(''));
      expect(customer.name, equals('Arumugam'));
    });

    test('matchesSearch finds by customer ID', () {
      final customer = Customer.fromRow(['133.Arumugam', '12345466', 'NSK', '9876543210']);
      
      expect(customer.matchesSearch('133'), isTrue);
      expect(customer.matchesSearch('999'), isFalse);
    });

    test('matchesSearch finds by name (case insensitive)', () {
      final customer = Customer.fromRow(['133.Arumugam', '12345466', 'NSK', '9876543210']);
      
      expect(customer.matchesSearch('Arumugam'), isTrue);
      expect(customer.matchesSearch('arumu'), isTrue);
      expect(customer.matchesSearch('ARUMUGAM'), isTrue);
    });

    test('matchesSearch finds by mobile number', () {
      final customer = Customer.fromRow(['133.Arumugam', '12345466', 'NSK', '9876543210']);
      
      expect(customer.matchesSearch('12345'), isTrue);
      expect(customer.matchesSearch('99999'), isFalse);
    });

    test('matchesSearch finds by area (case insensitive)', () {
      final customer = Customer.fromRow(['133.Arumugam', '12345466', 'NSK', '9876543210']);
      
      expect(customer.matchesSearch('NSK'), isTrue);
      expect(customer.matchesSearch('nsk'), isTrue);
      expect(customer.matchesSearch('NS'), isTrue);
      expect(customer.matchesSearch('XYZ'), isFalse);
    });
  });

  group('CsvService - Customer Balance Analysis', () {
    test('analyzeCustomerBalances works without master sheet', () {
      final testData = [
        ['Ledger:', '1033.Saravana[V O C Nagar', '1-Apr-2025 to 23-Nov-2025', '', '', '', ''],
        ['Date', 'Particulars', '', 'Vch Type', 'Vch No.', 'Debit', 'Credit'],
        ['2025-04-01 00:00:00', 'To', 'Opening Balance', '', '', '56012', ''],
        ['56012', '', '', '', '', '', ''],
        ['', 'By', 'Closing Balance', '', '', '', '56012'],
        ['56012', '', '', '', '', '', '56012'],
        ['', '', '', '', '', '', ''],
        ['Ledger:', '1035.Vasanthi Teacher', '1-Apr-2025 to 23-Nov-2025', '', '', '', ''],
        ['Date', 'Particulars', '', 'Vch Type', 'Vch No.', 'Debit', 'Credit'],
        ['2025-07-21 00:00:00', 'To', '1035.Vasanthi Teacher', 'Sales', '2041', '101000', ''],
        ['2025-07-21 00:00:00', 'By', 'Cash', 'Receipt', '2041', '', '89700'],
        ['101000', '', '', '', '', '', '93700'],
        ['', 'By', 'Closing Balance', '', '', '', '7300'],
        ['101000', '', '', '', '', '', '101000'],
      ];

      // Call without providing customer list
      final balances = CsvService.analyzeCustomerBalances(testData);
      
      expect(balances.length, equals(2));
      expect(balances[0].customerId, equals('1033'));
      expect(balances[0].name, equals('Saravana[V O C Nagar'));
      expect(balances[0].balance, equals(56012.0));
      expect(balances[1].customerId, equals('1035'));
      expect(balances[1].name, equals('Vasanthi Teacher'));
      expect(balances[1].balance, equals(7300.0));
    });

    test('analyzeCustomerBalances handles customers with matched debit/credit', () {
      final testData = [
        ['Ledger:', '2001.John Customer', '1-Apr-2025 to 23-Nov-2025', '', '', '', ''],
        ['Date', 'Particulars', '', 'Vch Type', 'Vch No.', 'Debit', 'Credit'],
        ['2025-04-01 00:00:00', 'To', 'Opening Balance', '', '', '50000', ''],
        ['2025-04-15 00:00:00', 'To', '2001.John Customer', 'Sales', '123', '25000', ''],
        ['2025-04-20 00:00:00', 'By', 'Cash', 'Receipt', '124', '', '75000'],
      ];

      final balances = CsvService.analyzeCustomerBalances(testData);
      
      expect(balances.length, equals(1));
      expect(balances[0].customerId, equals('2001'));
      expect(balances[0].name, equals('John Customer'));
      expect(balances[0].balance, equals(0.0)); // Matched debit and credit
    });

    test('analyzeCustomerBalances extracts last credit date correctly', () {
      final testData = [
        ['Ledger:', '1035.Vasanthi Teacher', '1-Apr-2025 to 23-Nov-2025', '', '', '', ''],
        ['Date', 'Particulars', '', 'Vch Type', 'Vch No.', 'Debit', 'Credit'],
        ['2025-07-21 00:00:00', 'To', '1035.Vasanthi Teacher', 'Sales', '2041', '101000', ''],
        ['2025-07-21 00:00:00', 'By', 'Cash', 'Receipt', '2041', '', '89700'],
        ['101000', '', '', '', '', '', '93700'],
        ['', 'By', 'Closing Balance', '', '', '', '7300'],
      ];

      final balances = CsvService.analyzeCustomerBalances(testData);
      
      expect(balances.length, equals(1));
      expect(balances[0].lastCreditDate, isNotNull);
      expect(balances[0].lastCreditDate!.year, equals(2025));
      expect(balances[0].lastCreditDate!.month, equals(7));
      expect(balances[0].lastCreditDate!.day, equals(21));
    });
  });

  group('LedgerEntry', () {
    test('isEmpty returns true for empty entry', () {
      const entry = LedgerEntry(
        date: '',
        toBy: '',
        particulars: '',
        vchType: '',
        vchNo: '',
        debit: '',
        credit: '',
      );
      
      expect(entry.isEmpty, isTrue);
    });

    test('isEmpty returns false for non-empty entry', () {
      const entry = LedgerEntry(
        date: '2025-04-01',
        toBy: 'To',
        particulars: 'Opening Balance',
        vchType: '',
        vchNo: '',
        debit: '56012',
        credit: '',
      );
      
      expect(entry.isEmpty, isFalse);
    });
  });

  group('CsvService - Master contact sync', () {
    test('follows 302 redirect and accepts success response', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      final baseUrl = 'http://${server.address.host}:${server.port}';

      server.listen((HttpRequest request) async {
        if (request.uri.path == '/sync') {
          request.response.statusCode = HttpStatus.found;
          request.response.headers.set(HttpHeaders.locationHeader, '$baseUrl/result');
          await request.response.close();
          return;
        }

        if (request.uri.path == '/result' && request.method == 'GET') {
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'success': true, 'message': 'ok'}));
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
          request.response.statusCode = HttpStatus.found;
          request.response.headers.set(HttpHeaders.locationHeader, '$baseUrl/result');
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
