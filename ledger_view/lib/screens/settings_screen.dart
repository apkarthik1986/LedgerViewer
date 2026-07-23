import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/storage_service.dart';
import '../services/csv_service.dart';
import '../services/theme_service.dart';
import '../providers/theme_provider.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback? onSettingsSaved;

  const SettingsScreen({super.key, this.onSettingsSaved});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Simple-mode controllers
  final TextEditingController _spreadsheetUrlController = TextEditingController();
  final TextEditingController _masterTabNameController = TextEditingController(text: 'Master');
  final TextEditingController _ledgerTabNameController = TextEditingController(text: 'Ledger');

  // Advanced-mode controllers
  final TextEditingController _masterSheetUrlController = TextEditingController();
  final TextEditingController _masterWriteApiUrlController = TextEditingController();
  final TextEditingController _ledgerSheetUrlController = TextEditingController();

  // Shared
  final TextEditingController _countryCodePrefixController = TextEditingController();

  bool _isSaving = false;
  bool _isTesting = false;
  bool _hasChanges = false;
  bool _isAdvancedMode = false;

  // Country code validation regex - must start with + followed by 1-4 digits
  static final RegExp _countryCodeRegex = RegExp(r'^\+\d{1,4}$');

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final spreadsheetUrl = await StorageService.getSpreadsheetUrl();
    final masterTabName = await StorageService.getMasterTabName();
    final ledgerTabName = await StorageService.getLedgerTabName();
    final masterUrl = await StorageService.getMasterSheetUrl();
    final masterWriteApiUrl = await StorageService.getMasterWriteApiUrl();
    final ledgerUrl = await StorageService.getLedgerSheetUrl();
    final countryCodePrefix = await StorageService.getCountryCodePrefix();
    setState(() {
      _spreadsheetUrlController.text = spreadsheetUrl ?? '';
      _masterTabNameController.text = masterTabName;
      _ledgerTabNameController.text = ledgerTabName;
      _masterSheetUrlController.text = masterUrl ?? '';
      _masterWriteApiUrlController.text = masterWriteApiUrl ?? '';
      _ledgerSheetUrlController.text = ledgerUrl ?? '';
      _countryCodePrefixController.text = countryCodePrefix;
      // If there is no spreadsheet URL but there are manual URLs, start in advanced mode
      if ((spreadsheetUrl == null || spreadsheetUrl.isEmpty) &&
          (masterUrl != null && masterUrl.isNotEmpty)) {
        _isAdvancedMode = true;
      }
    });
  }

  Future<void> _saveSettings() async {
    final countryCodePrefix = _countryCodePrefixController.text.trim();

    // Validate country code prefix
    if (countryCodePrefix.isEmpty || !_countryCodeRegex.hasMatch(countryCodePrefix)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Please provide a valid country code (e.g., +91, +1)'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    String masterUrl;
    String ledgerUrl;
    final masterWriteApiUrl = _masterWriteApiUrlController.text.trim();

    if (!_isAdvancedMode) {
      // Simple mode: derive CSV URLs from spreadsheet URL + tab names
      final sheetUrl = _spreadsheetUrlController.text.trim();
      final masterTab = _masterTabNameController.text.trim();
      final ledgerTab = _ledgerTabNameController.text.trim();

      if (sheetUrl.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Please provide the Google Sheets link'),
              backgroundColor: Colors.red.shade600,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      if (masterTab.isEmpty || ledgerTab.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Please provide both Master and Ledger tab names'),
              backgroundColor: Colors.red.shade600,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      final derivedMaster = CsvService.buildCsvUrlFromSheetUrl(sheetUrl, masterTab);
      final derivedLedger = CsvService.buildCsvUrlFromSheetUrl(sheetUrl, ledgerTab);
      if (derivedMaster == null || derivedLedger == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Could not extract spreadsheet ID from the link. Please check the URL.'),
              backgroundColor: Colors.red.shade600,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      masterUrl = derivedMaster;
      ledgerUrl = derivedLedger;
    } else {
      // Advanced mode: use manual URLs
      masterUrl = _masterSheetUrlController.text.trim();
      ledgerUrl = _ledgerSheetUrlController.text.trim();

      if (masterUrl.isEmpty || ledgerUrl.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Please provide both Master and Ledger Sheet URLs'),
              backgroundColor: Colors.red.shade600,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
    }

    setState(() {
      _isSaving = true;
    });
    
    try {
      // Save simple-mode fields
      await StorageService.saveSpreadsheetUrl(_spreadsheetUrlController.text.trim());
      await StorageService.saveMasterTabName(_masterTabNameController.text.trim());
      await StorageService.saveLedgerTabName(_ledgerTabNameController.text.trim());

      // Save derived/manual CSV URLs and other settings
      await StorageService.saveMasterSheetUrl(masterUrl);
      await StorageService.saveMasterWriteApiUrl(masterWriteApiUrl);
      await StorageService.saveLedgerSheetUrl(ledgerUrl);
      await StorageService.saveCountryCodePrefix(countryCodePrefix);

      // Fetch and cache Master data
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
                Text('Fetching Master data...'),
              ],
            ),
            backgroundColor: Colors.blue.shade600,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 30),
          ),
        );
      }
      
      final masterData = await CsvService.fetchCsvData(masterUrl);
      await StorageService.saveCachedMasterData(masterData);

      setState(() {
        _isSaving = false;
        _hasChanges = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('Settings saved and master data cached successfully'),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        
        // Notify that settings were saved
        widget.onSettingsSaved?.call();
      }
    } catch (e) {
      setState(() {
        _isSaving = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _testConnection() async {
    final sheetUrl = _isAdvancedMode ? '' : _spreadsheetUrlController.text.trim();
    final masterTab = _masterTabNameController.text.trim();
    final ledgerTab = _ledgerTabNameController.text.trim();

    String masterUrl;
    String ledgerUrl;

    if (!_isAdvancedMode) {
      if (sheetUrl.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Please enter the Google Sheets link first'),
            backgroundColor: Colors.orange.shade600,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      final derivedMaster = CsvService.buildCsvUrlFromSheetUrl(sheetUrl, masterTab);
      final derivedLedger = CsvService.buildCsvUrlFromSheetUrl(sheetUrl, ledgerTab);
      if (derivedMaster == null || derivedLedger == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Invalid Google Sheets link. Cannot extract spreadsheet ID.'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      masterUrl = derivedMaster;
      ledgerUrl = derivedLedger;
    } else {
      masterUrl = _masterSheetUrlController.text.trim();
      ledgerUrl = _ledgerSheetUrlController.text.trim();
      if (masterUrl.isEmpty || ledgerUrl.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Please fill in both Master and Ledger Sheet URLs first'),
            backgroundColor: Colors.orange.shade600,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    setState(() { _isTesting = true; });

    bool masterOk = false;
    bool ledgerOk = false;
    String masterError = '';
    String ledgerError = '';

    try {
      await CsvService.fetchCsvData(masterUrl);
      masterOk = true;
    } catch (e) {
      masterError = e.toString();
    }

    try {
      await CsvService.fetchCsvData(ledgerUrl);
      ledgerOk = true;
    } catch (e) {
      ledgerError = e.toString();
    }

    setState(() { _isTesting = false; });

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.network_check, color: Colors.blue),
            SizedBox(width: 8),
            Text('Connection Test'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _testResultRow('Master Sheet', masterOk, masterError),
            const SizedBox(height: 12),
            _testResultRow('Ledger Sheet', ledgerOk, ledgerError),
            if (!masterOk || !ledgerOk) ...[
              const SizedBox(height: 16),
              const Text(
                'Tip: Make sure the spreadsheet is shared as "Anyone with the link can view".',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _testResultRow(String label, bool ok, String error) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(ok ? Icons.check_circle : Icons.error, color: ok ? Colors.green : Colors.red, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
              if (!ok)
                Text(error, style: const TextStyle(fontSize: 11, color: Colors.red)),
            ],
          ),
        ),
      ],
    );
  }


  Future<void> _resetSettings() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Settings'),
        content: const Text(
          'Are you sure you want to clear all settings? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await StorageService.clearAll();
      setState(() {
        _spreadsheetUrlController.clear();
        _masterTabNameController.text = 'Master';
        _ledgerTabNameController.text = 'Ledger';
        _masterSheetUrlController.clear();
        _masterWriteApiUrlController.clear();
        _ledgerSheetUrlController.clear();
        _countryCodePrefixController.text = '+91'; // Reset to default
        _isAdvancedMode = false;
        _hasChanges = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('Settings reset successfully'),
              ],
            ),
            backgroundColor: Colors.orange.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  Future<void> _pasteFromClipboard(TextEditingController controller, String label) async {
    try {
      final data = await Clipboard.getData('text/plain');
      if (data != null && data.text != null) {
        setState(() {
          controller.text = data.text!;
          _hasChanges = true;
        });
        // Remove the snackbar notification to prevent duplicate alerts
        // The user can see the URL is pasted in the text field
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to paste: $e'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
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
                '1. Open your Google Sheet and share it\n'
                '   (Share → Anyone with the link → Viewer)\n'
                '2. Copy the link from the browser address bar\n'
                '3. Paste it into "Google Sheets Link" in Settings\n'
                '4. Enter the tab names for Master & Ledger sheets\n'
                '5. Tap "Test Connection" to verify, then Save\n'
                '6. (Optional) Add Master Write API URL for contact editing',
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
        title: const Text('Settings'),
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
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Instructions Card
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '1. Open your Google Sheet and share it\n'
                        '   (Share → Anyone with the link → Viewer)\n'
                        '2. Copy the link from the browser address bar\n'
                        '3. Paste it below, enter your tab names, then Save',
                        style: TextStyle(color: Colors.blue.shade900, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── Simple Mode: Google Sheets Link + Tab Names ──────────────
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.indigo.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.table_chart, color: Colors.indigo),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Google Sheets Link',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                                Text(
                                  'The share link of your spreadsheet',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Colors.grey.shade600,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _spreadsheetUrlController,
                        decoration: const InputDecoration(
                          hintText: 'https://docs.google.com/spreadsheets/d/…/edit',
                          prefixIcon: Icon(Icons.link),
                        ),
                        maxLines: 2,
                        keyboardType: TextInputType.url,
                        onChanged: (_) => setState(() => _hasChanges = true),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _pasteFromClipboard(_spreadsheetUrlController, 'Google Sheets Link'),
                          icon: const Icon(Icons.content_paste),
                          label: const Text('Paste from Clipboard'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.indigo,
                            side: const BorderSide(color: Colors.indigo),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _masterTabNameController,
                              decoration: const InputDecoration(
                                labelText: 'Master Tab Name',
                                hintText: 'Master',
                                prefixIcon: Icon(Icons.people, color: Colors.green),
                              ),
                              onChanged: (_) => setState(() => _hasChanges = true),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _ledgerTabNameController,
                              decoration: InputDecoration(
                                labelText: 'Ledger Tab Name',
                                hintText: 'Ledger',
                                prefixIcon: Icon(
                                  Icons.receipt_long,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              onChanged: (_) => setState(() => _hasChanges = true),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _isTesting ? null : _testConnection,
                          icon: _isTesting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.wifi_tethering),
                          label: Text(_isTesting ? 'Testing…' : 'Test Connection'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.teal,
                            side: const BorderSide(color: Colors.teal),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // ── Advanced Mode Toggle ──────────────────────────────────────
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    leading: const Icon(Icons.tune, color: Colors.grey),
                    title: const Text('Advanced: Manual URL Override'),
                    subtitle: const Text(
                      'Enter CSV publish links directly instead of a share link',
                      style: TextStyle(fontSize: 12),
                    ),
                    initiallyExpanded: _isAdvancedMode,
                    onExpansionChanged: (expanded) {
                      setState(() => _isAdvancedMode = expanded);
                    },
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Column(
                          children: [
                            // Master Sheet URL
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        Colors.green.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(Icons.people, color: Colors.green, size: 20),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Master Sheet URL',
                                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                          ),
                                          Text(
                                            'CSV link (File → Share → Publish to web)',
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                  color: Colors.grey.shade600,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: _masterSheetUrlController,
                                  decoration: const InputDecoration(
                                    hintText: 'https://docs.google.com/spreadsheets/d/…/pub?output=csv&…',
                                    prefixIcon: Icon(Icons.cloud_download),
                                  ),
                                  maxLines: 2,
                                  keyboardType: TextInputType.url,
                                  onChanged: (_) => setState(() => _hasChanges = true),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: () => _pasteFromClipboard(_masterSheetUrlController, 'Master Sheet'),
                                    icon: const Icon(Icons.content_paste),
                                    label: const Text('Paste Master URL'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.green,
                                      side: const BorderSide(color: Colors.green),
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const Divider(height: 24),

                            // Ledger Sheet URL
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(Icons.receipt_long, color: Theme.of(context).colorScheme.primary, size: 20),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Ledger Sheet URL',
                                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                          ),
                                          Text(
                                            'CSV link (File → Share → Publish to web)',
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                  color: Colors.grey.shade600,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: _ledgerSheetUrlController,
                                  decoration: const InputDecoration(
                                    hintText: 'https://docs.google.com/spreadsheets/d/…/pub?output=csv&…',
                                    prefixIcon: Icon(Icons.cloud_download),
                                  ),
                                  maxLines: 2,
                                  keyboardType: TextInputType.url,
                                  onChanged: (_) => setState(() => _hasChanges = true),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: () => _pasteFromClipboard(_ledgerSheetUrlController, 'Ledger Sheet'),
                                    icon: const Icon(Icons.content_paste),
                                    label: const Text('Paste Ledger URL'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Theme.of(context).colorScheme.primary,
                                      side: BorderSide(color: Theme.of(context).colorScheme.primary),
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const Divider(height: 24),

                            // Master Write API URL (always in advanced section)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(Icons.edit_note, color: Colors.orange, size: 20),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Master Write API URL',
                                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                          ),
                                          Text(
                                            'Optional — needed only for editing contacts',
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                  color: Colors.grey.shade600,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: _masterWriteApiUrlController,
                                  decoration: const InputDecoration(
                                    hintText: 'https://script.google.com/macros/s/…/exec',
                                    prefixIcon: Icon(Icons.cloud_upload),
                                  ),
                                  maxLines: 2,
                                  keyboardType: TextInputType.url,
                                  onChanged: (_) => setState(() => _hasChanges = true),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: () => _pasteFromClipboard(_masterWriteApiUrlController, 'Master Write API'),
                                    icon: const Icon(Icons.content_paste),
                                    label: const Text('Paste API URL'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.orange,
                                      side: const BorderSide(color: Colors.orange),
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Save Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveSettings,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.save),
                  label: const Text('Save Settings'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Reset Settings Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.restore, color: Colors.red.shade400),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Reset Settings',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                                Text(
                                  'Clear all saved data and settings',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Colors.grey.shade600,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _resetSettings,
                          icon: const Icon(Icons.delete_forever),
                          label: const Text('Reset All Settings'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Theme Selection Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.palette,
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'App Theme',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                                Text(
                                  'Choose your preferred color scheme',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Colors.grey.shade600,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Consumer<ThemeProvider>(
                        builder: (context, themeProvider, child) {
                          return DropdownButtonFormField<AppTheme>(
                            value: themeProvider.currentTheme,
                            decoration: InputDecoration(
                              prefixIcon: Icon(
                                ThemeService.getThemeIcon(themeProvider.currentTheme),
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey.shade300),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: 2,
                                ),
                              ),
                            ),
                            items: AppTheme.values.map((theme) {
                              return DropdownMenuItem<AppTheme>(
                                value: theme,
                                child: Row(
                                  children: [
                                    Icon(
                                      ThemeService.getThemeIcon(theme),
                                      size: 20,
                                      color: Colors.grey.shade600,
                                    ),
                                    const SizedBox(width: 12),
                                    Text(ThemeService.getThemeName(theme)),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (AppTheme? theme) {
                              if (theme != null) {
                                themeProvider.setTheme(theme);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Theme changed to ${ThemeService.getThemeName(theme)}'),
                                    backgroundColor: Theme.of(context).colorScheme.primary,
                                    behavior: SnackBarBehavior.floating,
                                    duration: const Duration(seconds: 1),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                );
                              }
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // WhatsApp Country Code Prefix Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.phone, color: Colors.green.shade700),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'WhatsApp Country Code',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                                Text(
                                  'Default prefix for phone numbers',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Colors.grey.shade600,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _countryCodePrefixController,
                        decoration: InputDecoration(
                          labelText: 'Country Code Prefix',
                          hintText: '+91',
                          helperText: 'This prefix will be added to phone numbers without country code',
                          prefixIcon: Icon(Icons.add_circle_outline, color: Colors.green.shade700),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.green.shade700, width: 2),
                          ),
                        ),
                        keyboardType: TextInputType.phone,
                        onChanged: (_) => setState(() => _hasChanges = true),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // App Info
              Center(
                child: Column(
                  children: [
                    Image.asset(
                      'assets/images/ledger_view_logo.png',
                      width: 80,
                      height: 80,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'LedgerView',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Version 1.1.0',
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _spreadsheetUrlController.dispose();
    _masterTabNameController.dispose();
    _ledgerTabNameController.dispose();
    _masterSheetUrlController.dispose();
    _masterWriteApiUrlController.dispose();
    _ledgerSheetUrlController.dispose();
    _countryCodePrefixController.dispose();
    super.dispose();
  }
}
