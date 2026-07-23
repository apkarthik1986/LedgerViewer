import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/ledger_entry.dart';
import '../providers/theme_provider.dart';
import '../services/print_service.dart';
import '../services/theme_service.dart';
import '../services/storage_service.dart';
import '../utils/voucher_type_mapper.dart';

class LedgerDisplay extends StatelessWidget {
  final LedgerResult result;
  final String? customerMobileNumber;

  const LedgerDisplay({
    super.key, 
    required this.result,
    this.customerMobileNumber,
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final currentTheme = themeProvider.currentTheme;
    final headerGradient = ThemeService.getLedgerHeaderGradient(currentTheme);
    final debitColor = ThemeService.getLedgerDebitColor(currentTheme);
    final creditColor = ThemeService.getLedgerCreditColor(currentTheme);
    final tableHeaderColor = ThemeService.getLedgerTableHeaderColor(currentTheme);
    final printButtonColor = ThemeService.getLedgerPrintButtonColor(currentTheme);

    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: headerGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.customerName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        result.dateRange,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                // Print Button
                IconButton(
                  onPressed: () => _printLedger(context),
                  icon: const Icon(Icons.print, color: Colors.white),
                  tooltip: 'Print Ledger',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.2),
                  ),
                ),
                // Share Button
                PopupMenuButton<String>(
                  icon: const Icon(Icons.share, color: Colors.white),
                  tooltip: 'Share Ledger',
                  color: Colors.white,
                  onSelected: (value) {
                    if (value == 'whatsapp_pdf') {
                      _shareViaWhatsApp(context, asImage: false);
                    } else if (value == 'whatsapp_image') {
                      _shareViaWhatsApp(context, asImage: true);
                    } else if (value == 'sms') {
                      _sendLedgerSMS(context);
                    } else {
                      _shareLedger(context, value == 'image');
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'whatsapp_pdf',
                      child: Row(
                        children: [
                          Icon(Icons.message, color: Colors.green),
                          SizedBox(width: 12),
                          Text('WhatsApp (PDF)'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'whatsapp_image',
                      child: Row(
                        children: [
                          Icon(Icons.message, color: Colors.green),
                          SizedBox(width: 12),
                          Text('WhatsApp (Image)'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'pdf',
                      child: Row(
                        children: [
                          Icon(Icons.picture_as_pdf, color: Colors.red),
                          SizedBox(width: 12),
                          Text('Share as PDF'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'image',
                      child: Row(
                        children: [
                          Icon(Icons.image, color: Colors.blue),
                          SizedBox(width: 12),
                          Text('Share as Image'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'sms',
                      child: Row(
                        children: [
                          Icon(Icons.sms, color: Colors.orange),
                          SizedBox(width: 12),
                          Text('Share SMS'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Ledger entries
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  // Table Header
                  _buildTableHeader(tableHeaderColor),
                  const Divider(height: 1, thickness: 2),
                  
                  // Entries
                  ...result.entries.map((entry) => _buildEntryRow(entry, debitColor, creditColor)),
                  
                  const Divider(height: 1, thickness: 2),
                  
                  // Totals
                  _buildTotalsRow(debitColor, creditColor),
                  
                  const SizedBox(height: 8),
                  
                  // Balance
                  if (result.closingBalance.isNotEmpty)
                    _buildClosingBalance(creditColor),
                  
                  // Legend
                  if (result.closingBalance.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                      child: const Text(
                        'S - Sales, P - Purchase, C - Cash Receipt, B - Bank Receipt, J - Journal',
                        style: TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: Colors.black87,
                        ),
                        textAlign: TextAlign.left,
                      ),
                    ),
                  
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _printLedger(BuildContext context) async {
    try {
      await PrintService.printLedger(result);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error printing: ${e.toString()}'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    }
  }

  Future<void> _shareLedger(BuildContext context, bool asImage) async {
    try {
      await PrintService.shareLedger(result, asImage: asImage);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sharing: ${e.toString()}'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    }
  }

  /// Format phone number with country code prefix
  /// Returns the formatted phone number with country code prefix
  Future<String> _getFormattedPhoneNumber(String countryCodePrefix, {String? prefillNumber}) async {
    if (prefillNumber != null && prefillNumber.isNotEmpty) {
      // Use the prefilled phone number (already formatted)
      return prefillNumber;
    }
    if (customerMobileNumber != null && customerMobileNumber!.isNotEmpty) {
      // If customer has a mobile number, use it with prefix
      final cleanNumber = customerMobileNumber!.replaceAll(RegExp(r'[\s\-\(\)]'), '');
      if (cleanNumber.startsWith('+')) {
        return cleanNumber;
      } else {
        return '$countryCodePrefix$cleanNumber';
      }
    }
    // Show just the prefix so user can enter the number
    return countryCodePrefix;
  }

  /// Create a phone controller with cursor positioned correctly
  TextEditingController _createPhoneController(String initialPhoneNumber, String countryCodePrefix, {String? prefillNumber}) {
    final controller = TextEditingController(text: initialPhoneNumber);
    // Set cursor position after prefix if no customer/prefill number
    final hasExistingNumber = (prefillNumber != null && prefillNumber.isNotEmpty) ||
        (customerMobileNumber != null && customerMobileNumber!.isNotEmpty);
    if (!hasExistingNumber) {
      controller.selection = TextSelection.fromPosition(
        TextPosition(offset: initialPhoneNumber.length),
      );
    }
    return controller;
  }

  Future<void> _shareViaWhatsApp(BuildContext context, {required bool asImage}) async {
    // First check if WhatsApp is installed
    final isWhatsAppAvailable = await PrintService.isWhatsAppInstalled();
    
    if (!isWhatsAppAvailable && context.mounted) {
      // WhatsApp not available, automatically fall back to SMS
      await _sendLedgerSMS(context);
      return;
    }
    
    // Get country code prefix for pre-populating the phone field
    final countryCodePrefix = await StorageService.getCountryCodePrefix();
    final initialPhoneNumber = await _getFormattedPhoneNumber(countryCodePrefix);
    final phoneController = _createPhoneController(initialPhoneNumber, countryCodePrefix);
    String? errorText;

    final String? phoneNumber = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Share via WhatsApp'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Enter the recipient\'s WhatsApp number:'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Phone Number',
                      hintText: '${countryCodePrefix}XXXXXXXXXX',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.phone),
                      errorText: errorText,
                    ),
                    onChanged: (value) {
                      if (errorText != null) {
                        setState(() {
                          errorText = null;
                        });
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final number = phoneController.text.trim();
                    if (number.isEmpty || number == countryCodePrefix) {
                      setState(() {
                        errorText = 'Please enter a phone number';
                      });
                    } else if (!_isValidPhoneNumber(number)) {
                      setState(() {
                        errorText = 'Please enter a valid phone number';
                      });
                    } else {
                      Navigator.of(dialogContext).pop(number);
                    }
                  },
                  child: const Text('Share'),
                ),
              ],
            );
          },
        );
      },
    );

    if (phoneNumber == null || phoneNumber.isEmpty) {
      return;
    }
    
    try {
      // Show loading indicator
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                Text('Preparing ${asImage ? 'image' : 'PDF'} for WhatsApp...'),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 30),
          ),
        );
      }

      // Generate and share via WhatsApp
      final success = await PrintService.shareViaWhatsApp(result, phoneNumber: phoneNumber, asImage: asImage);
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        
        if (success) {
          // Show brief success message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Opening WhatsApp...'),
              backgroundColor: Colors.green.shade600,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        
        // On error, automatically fall back to SMS
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('WhatsApp share failed. Opening SMS...'),
            backgroundColor: Colors.orange.shade600,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
        await _sendLedgerSMS(context, prefillPhoneNumber: phoneNumber);
      }
    }
  }

  /// Send ledger summary via SMS as fallback
  Future<void> _sendLedgerSMS(BuildContext context, {String? prefillPhoneNumber}) async {
    // Get country code prefix for pre-populating the phone field
    final countryCodePrefix = await StorageService.getCountryCodePrefix();
    final initialPhoneNumber = await _getFormattedPhoneNumber(countryCodePrefix, prefillNumber: prefillPhoneNumber);
    final phoneController = _createPhoneController(initialPhoneNumber, countryCodePrefix, prefillNumber: prefillPhoneNumber);
    String? errorText;

    final String? phoneNumber = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Send SMS Summary'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Enter the recipient\'s mobile number:'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Phone Number',
                      hintText: '${countryCodePrefix}XXXXXXXXXX',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.phone),
                      errorText: errorText,
                    ),
                    onChanged: (value) {
                      if (errorText != null) {
                        setState(() {
                          errorText = null;
                        });
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final number = phoneController.text.trim();
                    if (number.isEmpty || number == countryCodePrefix) {
                      setState(() {
                        errorText = 'Please enter a phone number';
                      });
                    } else if (!_isValidPhoneNumber(number)) {
                      setState(() {
                        errorText = 'Please enter a valid phone number';
                      });
                    } else {
                      Navigator.of(dialogContext).pop(number);
                    }
                  },
                  child: const Text('Send SMS'),
                ),
              ],
            );
          },
        );
      },
    );

    if (phoneNumber != null && phoneNumber.isNotEmpty && context.mounted) {
      try {
        // Show loading indicator
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                SizedBox(width: 12),
                Text('Opening SMS app...'),
              ],
            ),
            backgroundColor: Colors.blue,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 3),
          ),
        );

        // Send SMS
        await PrintService.sendLedgerSMS(result, phoneNumber: phoneNumber);
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('SMS app opened with ledger summary'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error sending SMS: ${e.toString()}'),
              backgroundColor: Colors.red.shade600,
            ),
          );
        }
      }
    }
  }

  /// Basic phone number validation
  /// Checks for minimum length and numeric characters (allows + for country code)
  bool _isValidPhoneNumber(String number) {
    // Remove common formatting characters except +
    final cleaned = number.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    
    // Check if contains only digits (and optionally + at start)
    if (!RegExp(r'^\+?\d+$').hasMatch(cleaned)) {
      return false;
    }
    
    // Extract just digits for length check
    final digitsOnly = cleaned.replaceAll('+', '');
    
    // Minimum 10 digits for a valid phone number
    return digitsOnly.length >= 10;
  }

  Widget _buildTableHeader(Color backgroundColor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      color: backgroundColor,
      child: const Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              'Date',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Type',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'No',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Debit',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
              textAlign: TextAlign.right,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Credit',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryRow(LedgerEntry entry, Color debitColor, Color creditColor) {
    final isDebit = entry.debit.isNotEmpty;
    final isCredit = entry.credit.isNotEmpty;
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Text(
              _formatDateForDisplay(entry.date), // Format for display: 24-Apr-2025 → 24/04/25
              style: const TextStyle(fontSize: 10),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              VoucherTypeMapper.getVchTypeFirstLetter(entry.vchType, entry.particulars),
              style: const TextStyle(fontSize: 10),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              entry.vchNo,
              style: const TextStyle(fontSize: 10),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _formatAmount(entry.debit),
              style: TextStyle(
                fontSize: 10,
                fontWeight: isDebit ? FontWeight.w600 : FontWeight.normal,
                color: isDebit ? debitColor : Colors.grey,
                fontFamily: 'monospace',
              ),
              textAlign: TextAlign.right,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _formatAmount(entry.credit),
              style: TextStyle(
                fontSize: 10,
                fontWeight: isCredit ? FontWeight.w600 : FontWeight.normal,
                color: isCredit ? creditColor : Colors.grey,
                fontFamily: 'monospace',
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalsRow(Color debitColor, Color creditColor) {
    return Column(
      children: [
        // Total Debit
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                debitColor.withOpacity(0.1),
                debitColor.withOpacity(0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: debitColor.withOpacity(0.3),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total Debit',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: debitColor,
                ),
              ),
              Text(
                '₹ ${_formatAmount(result.totalDebit)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: debitColor,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Total Credit
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                creditColor.withOpacity(0.1),
                creditColor.withOpacity(0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: creditColor.withOpacity(0.3),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total Credit',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: creditColor,
                ),
              ),
              Text(
                '₹ ${_formatAmount(result.totalCredit)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: creditColor,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildClosingBalance(Color balanceColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            balanceColor.withOpacity(0.15),
            balanceColor.withOpacity(0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: balanceColor.withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Balance',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: balanceColor,
            ),
          ),
          Text(
            '₹ ${_formatAmount(result.closingBalance)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: balanceColor,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  String _formatAmount(String amount) {
    if (amount.isEmpty) return '-';
    
    // Try to parse and format the number
    try {
      final numValue = double.tryParse(amount.replaceAll(',', ''));
      if (numValue != null) {
        final formatter = NumberFormat('#,##,###.##', 'en_IN');
        return formatter.format(numValue);
      }
    } catch (e) {
      // Return original if parsing fails
    }
    
    return amount;
  }

  String _formatDateForDisplay(String dateStr) {
    if (dateStr.isEmpty) return '';
    
    try {
      // Date comes from CsvService._formatDate() in format "24-Apr-25"
      // Convert to dd/mm/yy format for display
      if (dateStr.contains('-')) {
        final parts = dateStr.split('-');
        if (parts.length == 3) {
          final day = parts[0].padLeft(2, '0');
          final month = _getMonthNumber(parts[1]); // Already zero-padded
          final year = parts[2].length == 4 ? parts[2].substring(2) : parts[2];
          return '$day/$month/$year';
        }
      }
      
      return dateStr;
    } catch (e) {
      return dateStr;
    }
  }

  String _getMonthNumber(String monthName) {
    const months = {
      'Jan': '01', 'Feb': '02', 'Mar': '03', 'Apr': '04',
      'May': '05', 'Jun': '06', 'Jul': '07', 'Aug': '08',
      'Sep': '09', 'Oct': '10', 'Nov': '11', 'Dec': '12'
    };
    return months[monthName] ?? monthName;
  }
}
