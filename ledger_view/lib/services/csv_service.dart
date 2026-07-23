import 'package:http/http.dart' as http;
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'dart:convert';
import 'dart:io';
import '../models/ledger_entry.dart';
import '../models/customer.dart';
import '../models/customer_balance.dart';

class CsvService {
  /// Extract the spreadsheet ID from any Google Sheets URL.
  ///
  /// Supports share links, edit links, and CSV publish links.
  /// Returns null if the URL does not contain a recognisable spreadsheet ID.
  static String? extractSpreadsheetId(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return null;
    // Pattern: /spreadsheets/d/{ID}[/...]
    final match = RegExp(r'/spreadsheets/d/([a-zA-Z0-9_-]+)').firstMatch(uri.path);
    return match?.group(1);
  }

  /// Build a CSV export URL from a spreadsheet ID and a sheet (tab) name.
  ///
  /// Uses the gviz/tq endpoint which works for any publicly viewable sheet
  /// without requiring "Publish to web".
  static String buildCsvExportUrl(String spreadsheetId, String tabName) {
    final encoded = Uri.encodeQueryComponent(tabName);
    return 'https://docs.google.com/spreadsheets/d/$spreadsheetId/gviz/tq?tqx=out:csv&sheet=$encoded';
  }

  /// Convenience helper: given a raw Google Sheets URL and a tab name, produce
  /// the CSV export URL.  Returns null when the spreadsheet ID cannot be parsed.
  static String? buildCsvUrlFromSheetUrl(String sheetUrl, String tabName) {
    final id = extractSpreadsheetId(sheetUrl);
    if (id == null) return null;
    return buildCsvExportUrl(id, tabName);
  }

  /// Fetch and parse data from an Excel file (.xlsx) and select a sheet
  static Future<List<List<dynamic>>> fetchExcelSheetData(String filePath, String sheetName) async {
    // filePath: local path to .xlsx file
    // sheetName: name of the sheet to read (e.g., 'input' or 'output')
    final bytes = await _readFileBytes(filePath);
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.sheets[sheetName];
    if (sheet == null) {
      throw Exception('Sheet "$sheetName" not found in $filePath');
    }
    // Convert Excel rows to List<List<dynamic>>
    return sheet.rows.map((row) => row.map((cell) => cell?.value ?? '').toList()).toList();
  }

  static Future<List<int>> _readFileBytes(String filePath) async {
    // For Flutter mobile/desktop
    return await File(filePath).readAsBytes();
  }
  /// Fetch and parse customer data from the Master sheet
  /// Column A contains "CustomerID.Name" format, Column B contains Mobile Number,
  /// Column C contains Area, Column D contains GPAY
  static Future<List<Customer>> fetchCustomerData(String url) async {
    try {
      final csvData = await fetchCsvData(url);
      return parseCustomerData(csvData);
    } catch (e) {
      throw Exception('Error fetching customer data: $e');
    }
  }

  /// Update master contact details via write API endpoint
  static Future<void> updateMasterContactDetails({
    required String writeApiUrl,
    required Customer customer,
  }) async {
    try {
      final payload = jsonEncode({
        'action': 'update_master_contact',
        'accountNumber': customer.accountNumber.isNotEmpty
            ? customer.accountNumber
            : customer.customerId,
        'customerId': customer.customerId,
        'name': customer.name,
        'mobileNo': customer.mobileNumber,
        'mobileNumber': customer.mobileNumber,
        'area': customer.area,
        'group': customer.groupName,
        'gpay': customer.gpay,
        'bank': customer.bank,
      });

      final response = await _postJsonFollowingRedirects(
        Uri.parse(writeApiUrl),
        payload,
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'Failed to sync master contact details: HTTP ${response.statusCode}',
        );
      }

      final body = response.body.trim();
      if (body.isEmpty) return;

      try {
        final decoded = jsonDecode(body);
        if (decoded is Map && decoded['success'] == false) {
          final message = decoded['message']?.toString() ??
              'Unknown error from master write API';
          throw Exception(message);
        }
      } catch (_) {
        // Non-JSON responses are accepted as long as status code is successful
      }
    } catch (e) {
      throw Exception('Error updating master contact details: $e');
    }
  }

  static Future<http.Response> _postJsonFollowingRedirects(
    Uri uri,
    String body,
  ) async {
    const redirectStatusCodes = {301, 302, 303, 307, 308};
    final client = http.Client();
    try {
      Uri currentUri = uri;
      String method = 'POST';
      String? currentBody = body;
      int redirects = 0;

      while (true) {
        final request = http.Request(method, currentUri)
          ..followRedirects = false
          ..headers['Content-Type'] = 'application/json';

        if (currentBody != null) {
          request.body = currentBody;
        }

        final streamed = await client.send(request);
        final response = await http.Response.fromStream(streamed);

        if (!redirectStatusCodes.contains(response.statusCode)) {
          return response;
        }

        final location = response.headers['location'];
        if (location == null || location.trim().isEmpty) {
          return response;
        }

        redirects++;
        if (redirects > 5) {
          throw Exception('Too many redirects while syncing master contact');
        }

        currentUri = currentUri.resolve(location);
        if (response.statusCode == 303 ||
            response.statusCode == 301 ||
            response.statusCode == 302) {
          method = 'GET';
          currentBody = null;
        }
      }
    } finally {
      client.close();
    }
  }

  /// Parse customer data from CSV rows
  /// Skips the header row (first row)
  static List<Customer> parseCustomerData(List<List<dynamic>> data) {
    if (data.isEmpty) return [];

    final customers = <Customer>[];
    final headerIndex = _buildHeaderIndex(data.first);

    // Skip first row (header)
    for (int i = 1; i < data.length; i++) {
      final row = data[i];
      final isRowEmpty = row.isEmpty ||
          row.every((cell) => cell.toString().trim().isEmpty);
      if (isRowEmpty) {
        continue; // Skip empty rows
      }

      final customer = Customer.fromRow(row, headerIndex: headerIndex);
      // Only add customers with at least an ID or name
      if (customer.customerId.isNotEmpty || customer.name.isNotEmpty) {
        customers.add(customer);
      }
    }

    return customers;
  }

  /// Fetch CSV data from the given URL and parse it
  static Future<List<List<dynamic>>> fetchCsvData(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        final csvString = response.body;
        final csvConverter = const CsvToListConverter(
          eol: '\n',
          shouldParseNumbers: false,
        );
        return csvConverter.convert(csvString);
      } else {
        throw Exception('Failed to fetch data: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching CSV: $e');
    }
  }

  /// Find ledger entries for a specific customer number or name
  static LedgerResult? findLedgerByNumber(
    List<List<dynamic>> data,
    String searchQuery,
  ) {
    if (data.isEmpty) return null;

    // Normalize search query
    final normalizedSearch = searchQuery.trim().toUpperCase();
    
    int startRow = -1;
    int endRow = -1;
    String customerName = '';
    String dateRange = '';

    // Find the section that matches the search number or name
    for (int i = 0; i < data.length; i++) {
      final row = data[i];
      
      // Check if this row is a header row (contains "Ledger:")
      if (row.isNotEmpty && row[0].toString().trim().toLowerCase() == 'ledger:') {
        // Column 1 contains the customer number and name (e.g., "1139B.Pushpa Malliga Teacher")
        final customerInfo = row.length > 1 ? row[1].toString().trim() : '';
        
        // Extract the number part and name part
        String extractedNumber = '';
        String extractedName = '';
        if (customerInfo.contains('.')) {
          final parts = customerInfo.split('.');
          extractedNumber = parts[0].trim().toUpperCase();
          extractedName = parts.length > 1 ? parts[1].trim().toUpperCase() : '';
        } else {
          // Try splitting by space
          final parts = customerInfo.split(' ');
          extractedNumber = parts[0].trim().toUpperCase();
          extractedName = parts.length > 1 ? parts.sublist(1).join(' ').trim().toUpperCase() : '';
        }
        
        // Match by number or name (partial match for name)
        if (extractedNumber == normalizedSearch || 
            (extractedName.isNotEmpty && extractedName.contains(normalizedSearch))) {
          startRow = i;
          customerName = customerInfo;
          dateRange = row.length > 2 ? row[2].toString().trim() : '';
          
          // Find the end of this section (next "Ledger:" or end of data)
          for (int j = i + 1; j < data.length; j++) {
            final nextRow = data[j];
            if (nextRow.isNotEmpty && 
                nextRow[0].toString().trim().toLowerCase() == 'ledger:') {
              endRow = j - 1;
              break;
            }
          }
          
          // If we didn't find another "Ledger:", use the end of data
          if (endRow == -1) {
            endRow = data.length - 1;
          }
          
          break;
        }
      }
    }

    if (startRow == -1) return null;

    // Extract the ledger entries
    final entries = <LedgerEntry>[];
    String totalDebit = '';
    String totalCredit = '';
    String closingBalance = '';
    bool foundClosingBalance = false;
    
    // Track the previous row for Total calculation
    List<dynamic>? previousRow;

    for (int i = startRow + 2; i <= endRow; i++) {
      final row = data[i];
      if (row.isEmpty || row.every((cell) => cell.toString().trim().isEmpty)) {
        previousRow = null;
        continue; // Skip empty rows
      }

      // Parse the row
      final date = row.length > 0 ? row[0].toString().trim() : '';
      final toBy = row.length > 1 ? row[1].toString().trim() : '';
      final particulars = row.length > 2 ? row[2].toString().trim() : '';
      final vchType = row.length > 3 ? row[3].toString().trim() : '';
      final vchNo = row.length > 4 ? row[4].toString().trim() : '';
      final debit = row.length > 5 ? row[5].toString().trim() : '';
      final credit = row.length > 6 ? row[6].toString().trim() : '';

      // Check if this is a closing balance row
      if (particulars.toLowerCase().contains('closing balance')) {
        foundClosingBalance = true;
        closingBalance = credit.isNotEmpty ? credit : debit;
        // Get totals from the row above (previous row)
        // CSV structure: The totals row appears before the Closing Balance row
        // and has the total debit value in the first column (normally the date column)
        // and total credit in the credit column (index 6).
        // Example: ['101000', '', '', '', '', '', '93700'] represents totals
        if (previousRow != null) {
          final prevFirstColumn = previousRow.isNotEmpty ? previousRow[0].toString().trim() : '';
          final prevCredit = previousRow.length > 6 ? previousRow[6].toString().trim() : '';
          // Check if previous row is a totals row (has numeric value in first column, not a date)
          if (prevFirstColumn.isNotEmpty && !_isDateString(prevFirstColumn)) {
            // Validate that it's actually a numeric value
            final numValue = double.tryParse(prevFirstColumn.replaceAll(',', ''));
            if (numValue != null) {
              totalDebit = prevFirstColumn;
              totalCredit = prevCredit;
            }
          }
        }
      } else if (date.isNotEmpty || toBy.isNotEmpty || particulars.isNotEmpty) {
        // Only add as entry if it's a valid date row
        if (_isDateString(date)) {
          entries.add(LedgerEntry(
            date: _formatDate(date),
            toBy: toBy,
            particulars: particulars,
            vchType: vchType,
            vchNo: vchNo,
            debit: debit,
            credit: credit,
          ));
        }
      }
      
      previousRow = row;
    }

    // If closing balance row is not found (e.g., when debit and credit are matched),
    // calculate totals from the entries
    if (!foundClosingBalance) {
      double calculatedDebit = 0.0;
      double calculatedCredit = 0.0;
      
      for (final entry in entries) {
        if (entry.debit.isNotEmpty) {
          final debitValue = double.tryParse(entry.debit.replaceAll(',', ''));
          if (debitValue != null) {
            calculatedDebit += debitValue;
          }
        }
        if (entry.credit.isNotEmpty) {
          final creditValue = double.tryParse(entry.credit.replaceAll(',', ''));
          if (creditValue != null) {
            calculatedCredit += creditValue;
          }
        }
      }
      
      // Format the calculated totals
      totalDebit = calculatedDebit.toStringAsFixed(0);
      totalCredit = calculatedCredit.toStringAsFixed(0);
      // Closing balance is 0 when debits and credits match
      closingBalance = '0';
    }

    return LedgerResult(
      customerName: customerName,
      dateRange: dateRange,
      entries: entries,
      totalDebit: totalDebit,
      totalCredit: totalCredit,
      closingBalance: closingBalance,
    );
  }

  static bool _isDateString(String str) {
    // Check if the string looks like a date using regex pattern
    // Matches yyyy-mm-dd, dd-mm-yyyy, dd/mm/yyyy formats
    final datePattern = RegExp(r'\d{4}-\d{2}-\d{2}|\d{2}[-/]\d{2}[-/]\d{4}|\d{2}-[A-Za-z]{3}-\d{4}');
    return datePattern.hasMatch(str) || str.contains('-') && str.length > 8;
  }

  static String _formatDate(String dateStr) {
    if (dateStr.isEmpty) return '';
    
    // Try to parse and format the date
    try {
      // Handle Excel date format (e.g., "2025-04-01 00:00:00")
      if (dateStr.contains(' ')) {
        dateStr = dateStr.split(' ')[0];
      }
      
      // Parse date format
      if (dateStr.contains('-')) {
        final parts = dateStr.split('-');
        if (parts.length == 3) {
          // Determine if format is yyyy-mm-dd or dd-mm-yyyy
          // If first part is 4 digits, it's yyyy-mm-dd
          // If last part is 4 digits, it's dd-mm-yyyy
          String day, month, year;
          
          if (parts[0].length == 4) {
            // yyyy-mm-dd format
            year = parts[0].substring(2); // Get last 2 digits of year
            month = _getMonthName(int.tryParse(parts[1]) ?? 0);
            day = (int.tryParse(parts[2]) ?? parts[2]).toString();
          } else if (parts[2].length == 4) {
            // dd-mm-yyyy format
            day = (int.tryParse(parts[0]) ?? parts[0]).toString();
            month = _getMonthName(int.tryParse(parts[1]) ?? 0);
            year = parts[2].substring(2); // Get last 2 digits of year
          } else {
            // Assume it's already in a short format, just pass through
            day = parts[0];
            month = parts[1];
            year = parts[2];
          }
          
          return '$day-$month-$year';
        }
      }
      
      return dateStr;
    } catch (e) {
      return dateStr;
    }
  }

  static String _getMonthName(int month) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    if (month >= 1 && month <= 12) {
      return months[month];
    }
    return month.toString();
  }

  static Map<String, int> _buildHeaderIndex(List<dynamic> headerRow) {
    final index = <String, int>{};
    for (int i = 0; i < headerRow.length; i++) {
      final key = headerRow[i].toString().trim().toLowerCase();
      if (key.isNotEmpty && !index.containsKey(key)) {
        index[key] = i;
      }
    }
    return index;
  }

  /// Analyze customer balances from ledger data
  /// Returns a list of CustomerBalance objects with balance and last credit date
  /// Extracts customer information directly from ledger data (no master sheet required)
  static List<CustomerBalance> analyzeCustomerBalances(
    List<List<dynamic>> ledgerData,
    [List<Customer>? customers]
  ) {
    if (ledgerData.isEmpty) return [];

    final balances = <CustomerBalance>[];
    
    // If customers list is not provided, extract from ledger data
    if (customers == null || customers.isEmpty) {
      // Extract all unique customers from ledger data
      final customerMap = <String, Customer>{};
      
      for (int i = 0; i < ledgerData.length; i++) {
        final row = ledgerData[i];
        
        // Check if this row is a ledger header row (contains "Ledger:")
        if (row.isNotEmpty && row[0].toString().trim().toLowerCase() == 'ledger:') {
          // Column 1 contains the customer number and name (e.g., "1139B.Pushpa Malliga Teacher")
          final customerInfo = row.length > 1 ? row[1].toString().trim() : '';
          
          if (customerInfo.isNotEmpty) {
            // Extract the number part and name part
            String customerId = '';
            String name = '';
            if (customerInfo.contains('.')) {
              final parts = customerInfo.split('.');
              customerId = parts[0].trim();
              name = parts.length > 1 ? parts[1].trim() : '';
            } else {
              // If no dot, use the whole thing as ID
              customerId = customerInfo;
            }
            
            if (customerId.isNotEmpty && !customerMap.containsKey(customerId)) {
              customerMap[customerId] = Customer(
                customerId: customerId,
                name: name,
                mobileNumber: '', // Mobile number not available in ledger data
              );
            }
          }
        }
      }
      
      customers = customerMap.values.toList();
    }

    for (final customer in customers) {
      // Find the ledger for this customer
      final ledgerResult = findLedgerByNumber(ledgerData, customer.customerId);
      
      if (ledgerResult != null) {
        // Parse closing balance
        double balance = 0.0;
        try {
          final balanceStr = ledgerResult.closingBalance.replaceAll(',', '');
          balance = double.tryParse(balanceStr) ?? 0.0;
        } catch (e) {
          // If parsing fails, balance remains 0
        }

        // Find the last credit entry date
        DateTime? lastCreditDate;
        for (final entry in ledgerResult.entries.reversed) {
          if (_isValidCreditAmount(entry.credit)) {
            try {
              // Try to parse the date
              lastCreditDate = _parseEntryDate(entry.date);
              if (lastCreditDate != null) break;
            } catch (e) {
              // Continue to next entry if parsing fails
            }
          }
        }

        balances.add(CustomerBalance(
          customerId: customer.customerId,
          name: customer.name,
          mobileNumber: customer.mobileNumber,
          balance: balance,
          lastCreditDate: lastCreditDate,
        ));
      }
    }

    return balances;
  }

  /// Parse a date string from ledger entry
  /// Supports various formats: "24-Apr-25", "2025-04-24", "24/04/2025"
  static DateTime? _parseEntryDate(String dateStr) {
    if (dateStr.isEmpty) return null;

    try {
      // Handle format "24-Apr-25" or similar
      if (dateStr.contains('-')) {
        final parts = dateStr.split('-');
        if (parts.length == 3) {
          int? day, year;
          int? month;

          // Check if it's in format "24-Apr-25" (day-month-year)
          if (parts[1].length == 3 && !RegExp(r'^\d+$').hasMatch(parts[1])) {
            // Month name format
            day = int.tryParse(parts[0]);
            month = _parseMonthName(parts[1]);
            year = int.tryParse(parts[2]);
            
            if (year != null) {
              year = _convertTwoDigitYear(year);
            }
          } else if (parts[0].length == 4) {
            // Format: yyyy-mm-dd
            year = int.tryParse(parts[0]);
            month = int.tryParse(parts[1]);
            day = int.tryParse(parts[2]);
          } else {
            // Format: dd-mm-yyyy
            day = int.tryParse(parts[0]);
            month = int.tryParse(parts[1]);
            year = int.tryParse(parts[2]);
            
            if (year != null) {
              year = _convertTwoDigitYear(year);
            }
          }

          if (day != null && month != null && year != null) {
            return DateTime(year, month, day);
          }
        }
      }
      
      // Handle format "24/04/2025" or "24/04/25"
      if (dateStr.contains('/')) {
        final parts = dateStr.split('/');
        if (parts.length == 3) {
          final day = int.tryParse(parts[0]);
          final month = int.tryParse(parts[1]);
          int? year = int.tryParse(parts[2]);
          
          if (year != null) {
            year = _convertTwoDigitYear(year);
          }

          if (day != null && month != null && year != null) {
            return DateTime(year, month, day);
          }
        }
      }
    } catch (e) {
      // Return null if parsing fails
    }

    return null;
  }

  /// Parse month name to month number
  static int? _parseMonthName(String monthName) {
    const months = {
      'jan': 1, 'january': 1,
      'feb': 2, 'february': 2,
      'mar': 3, 'march': 3,
      'apr': 4, 'april': 4,
      'may': 5,
      'jun': 6, 'june': 6,
      'jul': 7, 'july': 7,
      'aug': 8, 'august': 8,
      'sep': 9, 'september': 9,
      'oct': 10, 'october': 10,
      'nov': 11, 'november': 11,
      'dec': 12, 'december': 12,
    };
    
    return months[monthName.toLowerCase()];
  }

  /// Check if a credit amount string is valid (non-empty and non-zero)
  static bool _isValidCreditAmount(String credit) {
    return credit.isNotEmpty && credit != '0' && credit != '0.00';
  }

  /// Convert 2-digit year to 4-digit year
  /// Uses pivot year approach: 0-30 = 2000s, 31-99 = 1900s
  static int _convertTwoDigitYear(int year) {
    if (year >= 100) return year; // Already 4-digit
    if (year <= 30) return 2000 + year;
    return 1900 + year;
  }
}
