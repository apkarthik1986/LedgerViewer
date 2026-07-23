import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/ledger_entry.dart';
import '../models/customer.dart';
import '../services/csv_service.dart';
import '../services/storage_service.dart';
import '../services/print_service.dart';
import '../widgets/ledger_display.dart';

class HomeScreen extends StatefulWidget {
  final String? initialSearchQuery;
  final VoidCallback? onSettingsTap;
  final bool hideSearch;

  const HomeScreen({
    super.key, 
    this.initialSearchQuery, 
    this.onSettingsTap,
    this.hideSearch = false,
  });

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  static const int _minSearchChars = 1; // Minimum characters to trigger autocomplete
  static const Duration _refreshTimeout = Duration(seconds: 15);
  static final RegExp _phoneNormalizationRegex = RegExp(r'[\s\-\+\(\)]');
  
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  LedgerResult? _ledgerResult;
  Customer? _selectedCustomer;
  List<Customer> _allCustomers = [];
  bool _hasLoadedCustomers = false;
  bool _hasLedgerUrl = false;
  String? _masterWriteApiUrl;
  bool _autoSearchTriggered = false;

  @override
  void initState() {
    super.initState();
    _loadCustomerData();
  }

  /// Public method to reload customer data from storage
  /// Called when settings are saved to refresh the UI
  void reloadData() {
    _loadCustomerData();
  }

  Future<void> _loadCustomerData() async {
    // Try to load cached customer data
    final cachedData = await StorageService.getCachedMasterData();
    final ledgerUrl = await StorageService.getLedgerSheetUrl();
    final masterWriteApiUrl = await StorageService.getMasterWriteApiUrl();
    
    if (cachedData != null) {
      final customers = CsvService.parseCustomerData(cachedData);
      setState(() {
        _allCustomers = customers;
        _hasLoadedCustomers = customers.isNotEmpty;
        _hasLedgerUrl = ledgerUrl != null && ledgerUrl.isNotEmpty;
        _masterWriteApiUrl = masterWriteApiUrl;
      });
      
      // If initialSearchQuery is provided, use it
      if (widget.initialSearchQuery != null && widget.initialSearchQuery!.isNotEmpty) {
        _searchController.text = widget.initialSearchQuery!;
        if (!_autoSearchTriggered) {
          _autoSearchTriggered = true;
          _searchLedger();
        }
      }
    } else {
      setState(() {
        _hasLedgerUrl = ledgerUrl != null && ledgerUrl.isNotEmpty;
        _masterWriteApiUrl = masterWriteApiUrl;
      });
    }
  }

  Future<void> _searchLedger() async {
    // Dismiss the keyboard
    FocusScope.of(context).unfocus();
    
    final searchQuery = _searchController.text.trim();
    if (searchQuery.isEmpty) {
      _showError('Please enter a customer number, name, or mobile number');
      return;
    }

    // Get ledger sheet URL to fetch real-time data
    final ledgerUrl = await StorageService.getLedgerSheetUrl();
    if (ledgerUrl == null || ledgerUrl.isEmpty) {
      _showError('No data available. Please configure and save settings first.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _ledgerResult = null;
    });

    try {
      // Save the search query
      await StorageService.saveLastSearch(searchQuery);

      // Fetch fresh ledger data from Google Sheets (real-time)
      final ledgerData = await CsvService.fetchCsvData(ledgerUrl);
      
      // Update cached ledger data (for reference, but always fetch fresh on search)
      await StorageService.saveCachedLedgerData(ledgerData);

      // First, check if search query matches a mobile number in the customer list
      // Normalize phone numbers by removing common formatting characters
      final normalizedSearchQuery = searchQuery.replaceAll(_phoneNormalizationRegex, '');
      String actualSearchQuery = searchQuery;
      Customer? foundCustomer;
      
      final matchedCustomer = _allCustomers.firstWhere(
        (customer) {
          final normalizedMobile = customer.mobileNumber.replaceAll(_phoneNormalizationRegex, '');
          return normalizedMobile == normalizedSearchQuery;
        },
        orElse: () => const Customer(customerId: '', name: '', mobileNumber: ''),
      );
      
      // If we found a customer by mobile number, use their customer ID for ledger search
      if (matchedCustomer.customerId.isNotEmpty) {
        actualSearchQuery = matchedCustomer.customerId;
        foundCustomer = matchedCustomer;
      } else {
        // Try to find customer by ID or name
        final upperSearchQuery = searchQuery.toUpperCase();
        foundCustomer = _allCustomers.firstWhere(
          (customer) => 
            customer.customerId.toUpperCase() == upperSearchQuery ||
            customer.name.toUpperCase().contains(upperSearchQuery),
          orElse: () => const Customer(customerId: '', name: '', mobileNumber: ''),
        );
        if (foundCustomer.customerId.isEmpty) {
          foundCustomer = null;
        }
      }

      // Find the ledger for the searched number or name
      final result = CsvService.findLedgerByNumber(ledgerData, actualSearchQuery);

      if (result != null) {
        setState(() {
          _ledgerResult = result;
          _selectedCustomer = foundCustomer;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'No ledger found for "$searchQuery"';
          _selectedCustomer = null;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error: ${e.toString()}';
        _selectedCustomer = null;
      });
    }
  }

  Future<void> _refreshLedgerData() async {
    // Get only master sheet URL (refresh should only take master data)
    final masterUrl = await StorageService.getMasterSheetUrl();
    
    if (masterUrl == null || masterUrl.isEmpty) {
      _showError('Please configure Master Sheet URL in Settings first');
      return;
    }

    // Show loading indicator
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
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
              Text('Refreshing master data from Google Sheets...'),
            ],
          ),
          backgroundColor: Colors.blue.shade600,
          behavior: SnackBarBehavior.floating,
          duration: _refreshTimeout,
        ),
      );
    }

    try {
      // Fetch only master data
      final masterData = await CsvService.fetchCsvData(masterUrl);
      
      // Update the cached master data
      await StorageService.saveCachedMasterData(masterData);

      // Parse and update customer list
      final customers = CsvService.parseCustomerData(masterData);
      
      // Update state to reflect we have master data
      setState(() {
        _allCustomers = customers;
        _hasLoadedCustomers = customers.isNotEmpty;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('Master data refreshed successfully'),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error refreshing data: ${e.toString()}'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            ShaderMask(
              shaderCallback: (Rect bounds) {
                return const LinearGradient(
                  colors: [Colors.blue, Colors.purple, Colors.pink],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ).createShader(bounds);
              },
              child: const Icon(Icons.help_outline, color: Colors.white),
            ),
            const SizedBox(width: 8),
            const Text('How to use'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '📋 Setup',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              const Text(
                '1. Open your Google Sheet with customer and ledger data\n'
                '2. Go to File → Share → Publish to web\n'
                '3. Publish both Master and Ledger sheets as CSV\n'
                '4. Copy the CSV URLs and paste them in Settings',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              const Text(
                '🏠 Home Screen',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              const Text(
                '• Search for customers by ID, name, or phone\n'
                '• View detailed ledger statements\n'
                '• Print or share ledgers as PDF/Image\n'
                '• Filter ledger by date range',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              const Text(
                '📊 Balance Analysis',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              const Text(
                '• Filter customers by outstanding balance\n'
                '• Find customers without credits for X days\n'
                '• View total balances across all customers\n'
                '• Export analysis as PDF or Image',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              const Text(
                '🎨 Themes',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              const Text(
                '• Choose from multiple color themes\n'
                '• Customized for better readability',
                style: TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it!'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ledger Search'),
        automaticallyImplyLeading: false,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Theme.of(context).colorScheme.primary,
                Theme.of(context).colorScheme.secondary,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: ShaderMask(
              shaderCallback: (Rect bounds) {
                return const LinearGradient(
                  colors: [Colors.blue, Colors.purple, Colors.pink],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ).createShader(bounds);
              },
              child: const Icon(Icons.help_outline, color: Colors.white),
            ),
            tooltip: 'Help',
            onPressed: _showHelpDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshLedgerData,
            tooltip: 'Refresh Master Data',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: widget.onSettingsTap,
            tooltip: 'Go to Settings',
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.grey.shade50,
              Colors.white,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Search Card with Autocomplete
                if (!widget.hideSearch)
                  Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Autocomplete<Customer>(
                          optionsBuilder: (TextEditingValue textEditingValue) {
                            // Only show suggestions after typing at least minimum characters
                            if (textEditingValue.text.isEmpty || textEditingValue.text.length < _minSearchChars) {
                              return const Iterable<Customer>.empty();
                            }
                            final query = textEditingValue.text.toLowerCase();
                            return _allCustomers.where((Customer customer) {
                              return customer.customerId.toLowerCase().contains(query) ||
                                  customer.name.toLowerCase().contains(query) ||
                                  customer.mobileNumber.toLowerCase().contains(query) ||
                                  customer.area.toLowerCase().contains(query);
                            });
                          },
                          displayStringForOption: (Customer customer) {
                            return '${customer.customerId} - ${customer.name}';
                          },
                          onSelected: (Customer customer) {
                            _searchController.text = customer.customerId;
                            _searchLedger();
                          },
                          fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                            // Sync our controller with the autocomplete controller
                            _searchController.text = controller.text;
                            return TextField(
                              controller: controller,
                              focusNode: focusNode,
                              keyboardType: TextInputType.text,
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon: controller.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear),
                                        onPressed: () {
                                          controller.clear();
                                          _searchController.clear();
                                          setState(() {
                                            _ledgerResult = null;
                                            _selectedCustomer = null;
                                            _errorMessage = null;
                                          });
                                          // Request focus after clearing
                                          focusNode.requestFocus();
                                        },
                                      )
                                    : null,
                              ),
                              textCapitalization: TextCapitalization.characters,
                              onSubmitted: (_) {
                                _searchController.text = controller.text;
                                _searchLedger();
                              },
                              onChanged: (value) {
                                _searchController.text = value;
                                setState(() {});
                              },
                            );
                          },
                          optionsViewBuilder: (context, onSelected, options) {
                            return Align(
                              alignment: Alignment.topLeft,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Material(
                                  elevation: 8.0,
                                  borderRadius: BorderRadius.circular(8.0),
                                  color: Colors.white,
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxHeight: 200,
                                      maxWidth: MediaQuery.of(context).size.width - 72,
                                    ),
                                    child: ListView.builder(
                                      padding: EdgeInsets.zero,
                                      shrinkWrap: true,
                                      itemCount: options.length,
                                      itemBuilder: (context, index) {
                                        final customer = options.elementAt(index);
                                      return ListTile(
                                        dense: true,
                                        title: Text(
                                          customer.customerId,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Theme.of(context).colorScheme.primary,
                                          ),
                                        ),
                                        subtitle: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(customer.name),
                                            if (customer.area.isNotEmpty)
                                              Text(
                                                customer.area,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                          ],
                                        ),
                                        trailing: customer.mobileNumber.isNotEmpty
                                            ? Text(
                                                customer.mobileNumber,
                                                style: TextStyle(
                                                  color: Colors.grey.shade600,
                                                  fontSize: 12,
                                                ),
                                              )
                                            : null,
                                        onTap: () {
                                          onSelected(customer);
                                        },
                                      );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                if (!widget.hideSearch)
                  const SizedBox(height: 16),

                // Status indicator
                if (!_hasLedgerUrl)
                  Card(
                    color: Colors.amber.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber, color: Colors.amber.shade700),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'No data available. Please configure and save settings first.',
                              style: TextStyle(color: Colors.amber.shade900),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Error message
                if (_errorMessage != null)
                  Card(
                    color: Colors.red.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: Colors.red.shade700),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(color: Colors.red.shade900),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Customer Master Details (shown when customer is found)
                if (_selectedCustomer != null)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        initiallyExpanded: false,
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.person,
                            color: Theme.of(context).colorScheme.primary,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          'Customer Details',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_selectedCustomer!.mobileNumber.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.phone, size: 20),
                                onPressed: () => _makePhoneCall(_selectedCustomer!.mobileNumber),
                                tooltip: 'Call Customer',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            IconButton(
                              icon: const Icon(Icons.edit, size: 20),
                              onPressed: _showEditCustomerDetailsDialog,
                              tooltip: 'Edit Master Contact Details',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            IconButton(
                              icon: const Icon(Icons.print, size: 20),
                              onPressed: () => _printCustomerDetails(context),
                              tooltip: 'Print Customer Details',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            const Icon(Icons.expand_more),
                          ],
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildDetailRow('Customer ID', _selectedCustomer!.customerId),
                                const SizedBox(height: 8),
                                _buildDetailRow('Name', _selectedCustomer!.name),
                                if (_selectedCustomer!.mobileNumber.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  _buildDetailRow('Mobile Number', _selectedCustomer!.mobileNumber),
                                ],
                                if (_selectedCustomer!.area.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  _buildDetailRow('Area', _selectedCustomer!.area),
                                ],
                                if (_selectedCustomer!.groupName.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  _buildDetailRow('Group', _selectedCustomer!.groupName),
                                ],
                                if (_selectedCustomer!.gpay.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  _buildDetailRow('GPAY', _selectedCustomer!.gpay),
                                ],
                                if (_selectedCustomer!.bank.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  _buildDetailRow('Bank', _selectedCustomer!.bank),
                                ],
                                if (_selectedCustomer!.accountNumber.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  _buildDetailRow('A/C NO.', _selectedCustomer!.accountNumber),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Ledger display
                if (_ledgerResult != null)
                  Expanded(
                    child: LedgerDisplay(
                      result: _ledgerResult!,
                      customerMobileNumber: _selectedCustomer?.mobileNumber,
                    ),
                  ),

                // Empty state
                if (_ledgerResult == null && _errorMessage == null && !_isLoading)
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset(
                            'assets/images/ledger_view_logo.png',
                            width: 120,
                            height: 120,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(
                                Icons.receipt_long,
                                size: 100,
                                color: Colors.grey.shade400,
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _hasLoadedCustomers
                                ? 'Enter a customer number, name, or mobile number to view their ledger'
                                : 'Configure settings to get started',
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 16,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const Text(': ', style: TextStyle(fontSize: 13)),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _printCustomerDetails(BuildContext context) async {
    if (_selectedCustomer == null) return;
    
    try {
      await PrintService.printCustomerDetails(_selectedCustomer!);
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

  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri phoneUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(phoneUri)) {
      await launchUrl(phoneUri);
    } else {
      _showError('Could not launch phone dialer');
    }
  }

  Future<void> _showEditCustomerDetailsDialog() async {
    final customer = _selectedCustomer;
    if (customer == null) return;

    final mobileController = TextEditingController(text: customer.mobileNumber);
    final areaController = TextEditingController(text: customer.area);
    final groupController = TextEditingController(text: customer.groupName);
    final gpayController = TextEditingController(text: customer.gpay);
    final bankController = TextEditingController(text: customer.bank);

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit Master Contact Details'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: mobileController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Mobile Number',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: areaController,
                decoration: const InputDecoration(
                  labelText: 'Area',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: groupController,
                decoration: const InputDecoration(
                  labelText: 'Group',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: gpayController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'GPAY',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bankController,
                decoration: const InputDecoration(
                  labelText: 'Bank',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await _saveUpdatedCustomerDetails(
                Customer(
                  customerId: customer.customerId,
                  name: customer.name,
                  mobileNumber: mobileController.text.trim(),
                  area: areaController.text.trim(),
                  groupName: groupController.text.trim(),
                  gpay: gpayController.text.trim(),
                  bank: bankController.text.trim(),
                  accountNumber: customer.accountNumber,
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveUpdatedCustomerDetails(Customer updatedCustomer) async {
    if (_masterWriteApiUrl == null || _masterWriteApiUrl!.trim().isEmpty) {
      _showError('Please configure Master Write API URL in Settings to enable edits.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await CsvService.updateMasterContactDetails(
        writeApiUrl: _masterWriteApiUrl!.trim(),
        customer: updatedCustomer,
      );

      final updatedCustomers = _allCustomers.map((customer) {
        if (customer.customerId.toUpperCase() ==
            updatedCustomer.customerId.toUpperCase()) {
          return updatedCustomer;
        }
        return customer;
      }).toList();

      await _syncUpdatedCustomerInCache(updatedCustomer);

      if (!mounted) return;
      setState(() {
        _allCustomers = updatedCustomers;
        _selectedCustomer = updatedCustomer;
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Master contact details updated and synchronized'),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      _showError(e.toString());
    }
  }

  Future<void> _syncUpdatedCustomerInCache(Customer updatedCustomer) async {
    final cachedData = await StorageService.getCachedMasterData();
    if (cachedData == null || cachedData.isEmpty) return;

    final updatedCache = cachedData.map((row) => List<dynamic>.from(row)).toList();
    final headerIndex = _buildHeaderIndex(updatedCache.first);
    final mobileColumn = _resolveHeaderIndex(
      headerIndex,
      ['mobile no', 'mobile no.', 'mobile number', 'mobile', 'phone'],
      fallback: 1,
    );
    final areaColumn = _resolveHeaderIndex(headerIndex, ['area'], fallback: 2);
    final groupColumn = _resolveHeaderIndex(headerIndex, ['group']);
    final gpayColumn = _resolveHeaderIndex(
      headerIndex,
      ['gpay', 'g pay'],
      fallback: 3,
    );
    final bankColumn = _resolveHeaderIndex(headerIndex, ['bank']);
    final accountColumn = _resolveHeaderIndex(
      headerIndex,
      ['a/c no.', 'a/c no', 'ac no.', 'ac no', 'account no', 'account number'],
    );
    bool customerRowUpdated = false;

    for (int i = 1; i < updatedCache.length; i++) {
      final row = updatedCache[i];
      final parsedCustomer = Customer.fromRow(row, headerIndex: headerIndex);
      final updatedAccountId = updatedCustomer.accountNumber.isNotEmpty
          ? updatedCustomer.accountNumber
          : updatedCustomer.customerId;
      final parsedAccountId = parsedCustomer.accountNumber.isNotEmpty
          ? parsedCustomer.accountNumber
          : parsedCustomer.customerId;

      if (parsedAccountId.toUpperCase() == updatedAccountId.toUpperCase() ||
          parsedCustomer.customerId.toUpperCase() ==
              updatedCustomer.customerId.toUpperCase()) {
        final maxColumn = [
          mobileColumn,
          areaColumn,
          groupColumn,
          gpayColumn,
          bankColumn,
        ].where((index) => index >= 0).fold<int>(0, (max, index) => index > max ? index : max);

        while (row.length <= maxColumn) {
          row.add('');
        }
        if (mobileColumn >= 0) row[mobileColumn] = updatedCustomer.mobileNumber;
        if (areaColumn >= 0) row[areaColumn] = updatedCustomer.area;
        if (groupColumn >= 0) row[groupColumn] = updatedCustomer.groupName;
        if (gpayColumn >= 0) row[gpayColumn] = updatedCustomer.gpay;
        if (bankColumn >= 0) row[bankColumn] = updatedCustomer.bank;
        if (accountColumn >= 0) row[accountColumn] = updatedCustomer.accountNumber;
        customerRowUpdated = true;
        break;
      }
    }

    if (customerRowUpdated) {
      await StorageService.saveCachedMasterData(updatedCache);
    }
  }

  Map<String, int> _buildHeaderIndex(List<dynamic> headerRow) {
    final headerIndex = <String, int>{};
    for (int i = 0; i < headerRow.length; i++) {
      final key = headerRow[i].toString().trim().toLowerCase();
      if (key.isNotEmpty && !headerIndex.containsKey(key)) {
        headerIndex[key] = i;
      }
    }
    return headerIndex;
  }

  int _resolveHeaderIndex(
    Map<String, int> headerIndex,
    List<String> aliases, {
    int fallback = -1,
  }) {
    for (final alias in aliases) {
      final index = headerIndex[alias.toLowerCase()];
      if (index != null) return index;
    }
    return fallback;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
