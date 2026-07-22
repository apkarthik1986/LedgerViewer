/// Represents a customer with their details
class Customer {
  final String customerId;
  final String name;
  final String mobileNumber;
  final String area;
  final String groupName;
  final String gpay;
  final String bank;
  final String accountNumber;

  const Customer({
    required this.customerId,
    required this.name,
    required this.mobileNumber,
    this.area = '',
    this.groupName = '',
    this.gpay = '',
    this.bank = '',
    this.accountNumber = '',
  });

  /// Parse customer data from a row where column A contains "CustomerID.Name" format,
  /// and supports header-based parsing for:
  /// NAME, Mobile No, Area, Group, GPAY, Bank, A/C NO.
  factory Customer.fromRow(
    List<dynamic> row, {
    Map<String, int>? headerIndex,
  }) {
    String getCell(int index) =>
        index >= 0 && index < row.length ? row[index].toString().trim() : '';

    int findHeaderIndex(List<String> aliases) {
      if (headerIndex == null) return -1;
      for (final alias in aliases) {
        final match = headerIndex[alias.toLowerCase()];
        if (match != null) return match;
      }
      return -1;
    }

    final nameIndex = findHeaderIndex(['name']);
    final mobileIndex = findHeaderIndex([
      'mobile no',
      'mobile no.',
      'mobile number',
      'mobile',
      'phone',
    ]);
    final areaIndex = findHeaderIndex(['area']);
    final groupIndex = findHeaderIndex(['group']);
    final gpayIndex = findHeaderIndex(['gpay', 'g pay']);
    final bankIndex = findHeaderIndex(['bank']);
    final accountNumberIndex = findHeaderIndex([
      'a/c no.',
      'a/c no',
      'ac no.',
      'ac no',
      'account no',
      'account number',
    ]);

    final fullName = getCell(nameIndex >= 0 ? nameIndex : 0);
    final mobile = getCell(mobileIndex >= 0 ? mobileIndex : 1);
    final area = getCell(areaIndex >= 0 ? areaIndex : 2);
    final groupName = getCell(groupIndex >= 0 ? groupIndex : 3);
    final gpay = getCell(gpayIndex >= 0 ? gpayIndex : 3);
    final bank = getCell(bankIndex >= 0 ? bankIndex : 5);
    final accountNumber = getCell(accountNumberIndex >= 0 ? accountNumberIndex : 6);

    final parsed = _parseCustomerName(fullName);
    final derivedCustomerId = parsed.$1.isNotEmpty ? parsed.$1 : accountNumber;
    final derivedAccountNumber = accountNumber.isNotEmpty ? accountNumber : parsed.$1;

    return Customer(
      customerId: derivedCustomerId,
      name: parsed.$2,
      mobileNumber: mobile,
      area: area,
      groupName: groupName,
      gpay: gpay,
      bank: bank,
      accountNumber: derivedAccountNumber,
    );
  }

  static (String, String) _parseCustomerName(String fullName) {
    if (fullName.contains('.')) {
      final dotIndex = fullName.indexOf('.');
      return (
        fullName.substring(0, dotIndex).trim(),
        fullName.substring(dotIndex + 1).trim(),
      );
    }

    if (fullName.contains('_')) {
      final parts = fullName
          .split('_')
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .toList();
      if (parts.length >= 2) {
        return (parts.first, parts.last);
      }
    }

    return ('', fullName);
  }

  /// Check if customer matches search query (case-insensitive)
  bool matchesSearch(String query) {
    final lowerQuery = query.toLowerCase();
    return customerId.toLowerCase().contains(lowerQuery) ||
        name.toLowerCase().contains(lowerQuery) ||
        mobileNumber.toLowerCase().contains(lowerQuery) ||
        area.toLowerCase().contains(lowerQuery) ||
        groupName.toLowerCase().contains(lowerQuery) ||
        bank.toLowerCase().contains(lowerQuery) ||
        accountNumber.toLowerCase().contains(lowerQuery);
  }

  @override
  String toString() {
    return 'Customer(id: $customerId, account: $accountNumber, name: $name, mobile: $mobileNumber, area: $area, group: $groupName, gpay: $gpay, bank: $bank)';
  }
}
