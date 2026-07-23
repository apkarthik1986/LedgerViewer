import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class StorageService {
  static const String _excelFilePathKey = 'excel_file_path';
  static const String _lastSearchKey = 'last_search';
  static const String _csvUrlKey = 'csv_url';
  static const String _masterSheetUrlKey = 'master_sheet_url';
  static const String _masterWriteApiUrlKey = 'master_write_api_url';
  static const String _ledgerSheetUrlKey = 'ledger_sheet_url';
  static const String _migrationCompleteKey = 'migration_complete';
  static const String _cachedMasterDataKey = 'cached_master_data';
  static const String _cachedLedgerDataKey = 'cached_ledger_data';
  static const String _themeKey = 'app_theme';
  static const String _countryCodePrefixKey = 'country_code_prefix';
  static const String _defaultCountryCodePrefix = '+91';

  // Simple-mode inputs
  static const String _spreadsheetUrlKey = 'spreadsheet_url';
  static const String _masterTabNameKey = 'master_tab_name';
  static const String _ledgerTabNameKey = 'ledger_tab_name';
  static const String _defaultMasterTabName = 'Master';
  static const String _defaultLedgerTabName = 'Ledger';

  static Future<SharedPreferences> _getPrefs() async {
    return await SharedPreferences.getInstance();
  }

  /// Migrate legacy CSV URL to new Ledger sheet URL (one-time migration)
  static Future<void> _migrateIfNeeded() async {
    final prefs = await _getPrefs();
    final migrationComplete = prefs.getBool(_migrationCompleteKey) ?? false;
    
    if (!migrationComplete) {
      final legacyUrl = prefs.getString(_csvUrlKey);
      final ledgerUrl = prefs.getString(_ledgerSheetUrlKey);
      
      // If there's a legacy URL and no ledger URL set, migrate it
      if (legacyUrl != null && legacyUrl.isNotEmpty && (ledgerUrl == null || ledgerUrl.isEmpty)) {
        await prefs.setString(_ledgerSheetUrlKey, legacyUrl);
      }
      
      await prefs.setBool(_migrationCompleteKey, true);
    }
  }

  /// Save the Excel file path or URL to persistent storage
  static Future<void> saveExcelFilePath(String path) async {
    final prefs = await _getPrefs();
    await prefs.setString(_excelFilePathKey, path);
  }

  /// Get the saved Excel file path or URL from persistent storage
  static Future<String?> getExcelFilePath() async {
    final prefs = await _getPrefs();
    return prefs.getString(_excelFilePathKey);
  }

  /// Save the last search query
  static Future<void> saveLastSearch(String query) async {
    final prefs = await _getPrefs();
    await prefs.setString(_lastSearchKey, query);
  }

  /// Get the last search query
  static Future<String?> getLastSearch() async {
    final prefs = await _getPrefs();
    return prefs.getString(_lastSearchKey);
  }

  /// Save the Master sheet URL
  static Future<void> saveMasterSheetUrl(String url) async {
    final prefs = await _getPrefs();
    await prefs.setString(_masterSheetUrlKey, url);
  }

  /// Get the Master sheet URL
  static Future<String?> getMasterSheetUrl() async {
    final prefs = await _getPrefs();
    return prefs.getString(_masterSheetUrlKey);
  }

  /// Save the Master sheet write API URL
  static Future<void> saveMasterWriteApiUrl(String url) async {
    final prefs = await _getPrefs();
    await prefs.setString(_masterWriteApiUrlKey, url);
  }

  /// Get the Master sheet write API URL
  static Future<String?> getMasterWriteApiUrl() async {
    final prefs = await _getPrefs();
    return prefs.getString(_masterWriteApiUrlKey);
  }

  /// Save the Ledger sheet URL
  static Future<void> saveLedgerSheetUrl(String url) async {
    final prefs = await _getPrefs();
    await prefs.setString(_ledgerSheetUrlKey, url);
  }

  /// Get the Ledger sheet URL
  static Future<String?> getLedgerSheetUrl() async {
    await _migrateIfNeeded();  // Ensure migration runs before getting URL
    final prefs = await _getPrefs();
    return prefs.getString(_ledgerSheetUrlKey);
  }

  /// Save cached Master data (customer list) to local storage
  static Future<void> saveCachedMasterData(List<List<dynamic>> data) async {
    final prefs = await _getPrefs();
    final jsonString = jsonEncode(data);
    await prefs.setString(_cachedMasterDataKey, jsonString);
  }

  /// Get cached Master data from local storage
  static Future<List<List<dynamic>>?> getCachedMasterData() async {
    final prefs = await _getPrefs();
    final jsonString = prefs.getString(_cachedMasterDataKey);
    if (jsonString == null) return null;
    
    try {
      final decoded = jsonDecode(jsonString) as List<dynamic>;
      return decoded.cast<List<dynamic>>();
    } catch (e) {
      return null;
    }
  }

  /// Save cached Ledger data to local storage
  static Future<void> saveCachedLedgerData(List<List<dynamic>> data) async {
    final prefs = await _getPrefs();
    final jsonString = jsonEncode(data);
    await prefs.setString(_cachedLedgerDataKey, jsonString);
  }

  /// Get cached Ledger data from local storage
  static Future<List<List<dynamic>>?> getCachedLedgerData() async {
    final prefs = await _getPrefs();
    final jsonString = prefs.getString(_cachedLedgerDataKey);
    if (jsonString == null) return null;
    
    try {
      final decoded = jsonDecode(jsonString) as List<dynamic>;
      return decoded.cast<List<dynamic>>();
    } catch (e) {
      return null;
    }
  }

  /// Save the selected theme
  static Future<void> saveTheme(String themeName) async {
    final prefs = await _getPrefs();
    await prefs.setString(_themeKey, themeName);
  }

  /// Get the selected theme
  static Future<String?> getTheme() async {
    final prefs = await _getPrefs();
    return prefs.getString(_themeKey);
  }

  /// Save the country code prefix for WhatsApp sharing
  static Future<void> saveCountryCodePrefix(String prefix) async {
    final prefs = await _getPrefs();
    await prefs.setString(_countryCodePrefixKey, prefix);
  }

  /// Get the country code prefix for WhatsApp sharing
  /// Returns the default prefix (+91) if not set
  static Future<String> getCountryCodePrefix() async {
    final prefs = await _getPrefs();
    return prefs.getString(_countryCodePrefixKey) ?? _defaultCountryCodePrefix;
  }

  /// Save the Google Sheets share/edit URL (simple mode)
  static Future<void> saveSpreadsheetUrl(String url) async {
    final prefs = await _getPrefs();
    await prefs.setString(_spreadsheetUrlKey, url);
  }

  /// Get the Google Sheets share/edit URL (simple mode)
  static Future<String?> getSpreadsheetUrl() async {
    final prefs = await _getPrefs();
    return prefs.getString(_spreadsheetUrlKey);
  }

  /// Save the Master tab name (simple mode)
  static Future<void> saveMasterTabName(String name) async {
    final prefs = await _getPrefs();
    await prefs.setString(_masterTabNameKey, name);
  }

  /// Get the Master tab name (simple mode), default 'Master'
  static Future<String> getMasterTabName() async {
    final prefs = await _getPrefs();
    return prefs.getString(_masterTabNameKey) ?? _defaultMasterTabName;
  }

  /// Save the Ledger tab name (simple mode)
  static Future<void> saveLedgerTabName(String name) async {
    final prefs = await _getPrefs();
    await prefs.setString(_ledgerTabNameKey, name);
  }

  /// Get the Ledger tab name (simple mode), default 'Ledger'
  static Future<String> getLedgerTabName() async {
    final prefs = await _getPrefs();
    return prefs.getString(_ledgerTabNameKey) ?? _defaultLedgerTabName;
  }

  /// Clear all settings (reset)
  static Future<void> clearAll() async {
    final prefs = await _getPrefs();
    await prefs.clear();
  }
}
