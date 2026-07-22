/// Represents a customer with their details
class Customer {
  final String customerId;
  final String name;
  final String mobileNumber;
  final String area;
  final String gpay;

  const Customer({
    required this.customerId,
    required this.name,
    required this.mobileNumber,
    this.area = '',
    this.gpay = '',
  });

  /// Parse customer data from a row where column A contains "CustomerID.Name" format,
  /// column B contains the mobile number, column C contains Area, and column D contains GPAY
  factory Customer.fromRow(List<dynamic> row) {
    final fullName = row.isNotEmpty ? row[0].toString().trim() : '';
    final mobile = row.length > 1 ? row[1].toString().trim() : '';
    final area = row.length > 2 ? row[2].toString().trim() : '';
    final gpay = row.length > 3 ? row[3].toString().trim() : '';

    final parsed = _parseCustomerName(fullName);

    return Customer(
      customerId: parsed.$1,
      name: parsed.$2,
      mobileNumber: mobile,
      area: area,
      gpay: gpay,
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
        area.toLowerCase().contains(lowerQuery);
  }

  @override
  String toString() {
    return 'Customer(id: $customerId, name: $name, mobile: $mobileNumber, area: $area, gpay: $gpay)';
  }
}
