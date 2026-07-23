# LedgerView

A modern Flutter Android app to view customer ledger data from Google Sheets CSV.

## Features

- 🔍 **Search by Customer Number**: Enter a customer number, name, or mobile number (e.g., "1139B", "Pushpa", "9876543210") to view their ledger
- 👥 **Customer List**: Browse customer information from Master sheet with search and filter
- ✏️ **Editable Master Contacts**: Update customer contact details in app and sync to the Master sheet through a write API
- 📊 **Professional Ledger Display**: Clean, formatted view in the app; simplified print output with Date, Vch Type (first letter), Vch No., Debit, and Credit columns
- 📈 **Balance Analysis**: Analyze customer balances with advanced filters for outstanding amounts and payment tracking
- 🖨️ **Print/PDF Support**: Generate printable ledger statements with simplified format matching accounting requirements
- 📱 **Multiple Sharing Options**: Share ledger statements via WhatsApp (PDF/Image), general share (PDF/Image), or SMS with automatic country code prefix
- ☁️ **Google Drive Integration**: Fetch live ledger data on each search; refresh master data independently
- 💾 **Persistent Settings**: App data persists until uninstall or manual reset
- 🎨 **Modern UI**: Professional, colorful design with Material Design 3
- 🌈 **Customizable Themes**: Choose from 5 beautiful themes (Light, Dark, Ocean Blue, Nature Green, Royal Purple) to personalize your experience

## App Screens

The app contains 4 main screens accessible via bottom navigation:

1. **Settings** - Paste your Google Sheets share link and enter the tab names for Master and Ledger sheets. Tap *Test Connection* to verify, then Save. Advanced users can override the CSV URLs manually or add a Master Write API URL for contact editing. Also choose the app theme.
2. **Ledger Search** - Search for customer ledgers directly by entering a customer number, name, or mobile number, and edit master contact details
3. **Analysis** - Analyze customer balances with advanced filtering options:
   - Filter by balance amount (greater than or less than a specified amount)
   - Filter by days without credit (customers with no credit entries for N days from today)
   - Combine both filters for precise analysis
   - View customer details including balance and last credit date

## Theme Customization

The app supports 5 beautiful themes that can be changed from the Settings screen:

- **Light** - Clean, bright interface perfect for daylight use
- **Dark** - Easy on the eyes for low-light environments
- **Ocean Blue** - Calming blue tones inspired by the ocean
- **Nature Green** - Fresh, natural green theme
- **Royal Purple** - Elegant purple theme for a premium feel

Your theme preference is saved automatically and persists across app sessions.

## Setup

1. **Share your Google Sheet**:
   - Open your Google Sheet containing customer and ledger data
   - Click **Share** (top-right) → **Anyone with the link** → **Viewer**
   - Copy the link from the browser address bar (it looks like  
     `https://docs.google.com/spreadsheets/d/SPREADSHEET_ID/edit…`)

2. **Configure the app's Settings page**:
   - **Google Sheets Link**: Paste the share link copied above
   - **Master Tab Name**: The exact name of the sheet tab for customer data (default: `Master`)
   - **Ledger Tab Name**: The exact name of the sheet tab for ledger data (default: `Ledger`)
   - Tap **Test Connection** to verify both tabs are readable, then tap **Save Settings**

3. **(Optional) Configure Advanced settings** (expand the *Advanced: Manual URL Override* section):
   - **Master Sheet URL**: Paste a manually prepared CSV publish link if needed  
     (File → Share → Publish to web → CSV)
   - **Ledger Sheet URL**: Same for the Ledger sheet
   - **Master Write API URL**: Required only when editing/syncing master contact details from the app

4. **Search for Ledger**:
   - Use the **Ledger Search** tab to enter a customer number, name, or mobile number
   - Or use the **Customers** tab to browse and click on a customer to view their ledger
   - Ledger data is fetched fresh from Google Sheets on each search

5. **Share Ledger**:
   - From the ledger view, tap the share button to access sharing options:
     1. **WhatsApp (PDF)** - Share ledger as PDF via WhatsApp
     2. **WhatsApp (Image)** - Share ledger as image via WhatsApp
     3. **Share as PDF** - Share ledger as PDF via other apps
     4. **Share as Image** - Share ledger as image via other apps
     5. **Share SMS** - Send ledger summary via SMS

6. **Refresh Data**:
   - Use the refresh button in the Ledger Search screen to update only the master data (customer list)
   - Ledger data is always fetched fresh when you search

## Google Apps Script Web App (Master contact sync)

Use this when your Master sheet already exists in Drive and headers must remain unchanged:

`NAME | Mobile No | Area | Group | GPAY | Bank | A/C NO.`

### 1) Add script to the same spreadsheet

- Open the Master spreadsheet in Google Drive
- Go to **Extensions → Apps Script**
- Paste this code in `Code.gs` and save:

```javascript
const MASTER_SHEET_NAME = 'Master'; // Change only if your tab name is different

function doPost(e) {
  try {
    if (!e || !e.postData || !e.postData.contents) {
      return jsonResponse(false, 'Missing request body');
    }

    const payload = JSON.parse(e.postData.contents);
    const accountNumber = String(payload.accountNumber || '').trim();
    if (!accountNumber) {
      return jsonResponse(false, 'accountNumber is required');
    }

    const ss = SpreadsheetApp.getActiveSpreadsheet();
    const sheet = ss.getSheetByName(MASTER_SHEET_NAME);
    if (!sheet) {
      return jsonResponse(false, `Sheet "${MASTER_SHEET_NAME}" not found`);
    }

    const values = sheet.getDataRange().getValues();
    if (values.length < 2) {
      return jsonResponse(false, 'Master sheet has no data rows');
    }

    const header = values[0].map(v => String(v).trim().toLowerCase());
    const idx = {
      mobile: header.indexOf('mobile no'),
      area: header.indexOf('area'),
      group: header.indexOf('group'),
      gpay: header.indexOf('gpay'),
      bank: header.indexOf('bank'),
      account: header.indexOf('a/c no.')
    };

    if (idx.account < 0) return jsonResponse(false, 'A/C NO. column not found');

    let rowNumber = -1;
    for (let i = 1; i < values.length; i++) {
      const rowAccount = String(values[i][idx.account] || '').trim();
      if (rowAccount === accountNumber) {
        rowNumber = i + 1; // Sheet rows are 1-based
        break;
      }
    }

    if (rowNumber < 0) {
      return jsonResponse(false, `No record found for A/C NO.: ${accountNumber}`);
    }

    // Update only contact fields, never headers
    if (idx.mobile >= 0 && payload.mobileNo !== undefined) sheet.getRange(rowNumber, idx.mobile + 1).setValue(payload.mobileNo);
    if (idx.area >= 0 && payload.area !== undefined) sheet.getRange(rowNumber, idx.area + 1).setValue(payload.area);
    if (idx.group >= 0 && payload.group !== undefined) sheet.getRange(rowNumber, idx.group + 1).setValue(payload.group);
    if (idx.gpay >= 0 && payload.gpay !== undefined) sheet.getRange(rowNumber, idx.gpay + 1).setValue(payload.gpay);
    if (idx.bank >= 0 && payload.bank !== undefined) sheet.getRange(rowNumber, idx.bank + 1).setValue(payload.bank);

    return jsonResponse(true, 'Contact details synchronized', {
      accountNumber,
      rowNumber,
      updatedAt: new Date().toISOString()
    });
  } catch (error) {
    return jsonResponse(false, error.message || String(error));
  }
}

function jsonResponse(success, message, data) {
  return ContentService
    .createTextOutput(JSON.stringify({ success, message, data: data || null }))
    .setMimeType(ContentService.MimeType.JSON);
}
```

### 2) Deploy as Web App

- **Deploy → New deployment → Web app**
- **Execute as:** Me
- **Who has access:** Anyone (or Anyone with Google account, based on your security needs)
- Authorize and copy the Web App URL
- Paste URL into app **Settings → Master Write API URL**

### 3) JSON payload sent from app

```json
{
  "action": "update_master_contact",
  "accountNumber": "133",
  "customerId": "133",
  "name": "Arumugam",
  "mobileNo": "12345466",
  "mobileNumber": "12345466",
  "area": "NSK",
  "group": "Retail",
  "gpay": "9876543210",
  "bank": "SBI"
}
```

### 4) Verification checklist

1. Send one update for an existing `A/C NO.`
2. Confirm only that row changes
3. Confirm header row is unchanged
4. Confirm other rows are unchanged
5. Confirm unknown `A/C NO.` returns not-found response

## Print Format

The app displays full ledger details on screen but prints a simplified format for better clarity:

**On-Screen Display:**
- Date, To/By, Particulars, Vch Type, Debit, Credit

**Print/PDF Output (Optimized for 58mm Thermal Printer):**
- Date (dd/mm/yy format, e.g., 24/04/25), Vch Type (first letter only), Vch No., Debit, Credit
- Examples: Sales → S, Purchase → P, Cash Receipt → C, Bank Receipt → B, Journal → J
- Uses narrow/condensed fonts to maximize space on thermal paper
- Auto-adjustable column widths for debit and credit amounts

This simplified print format follows standard accounting practices for thermal printers and matches the requirements in `sample_bill.xlsx` (Required sheet).

## Building the APK

This repository includes a GitHub Actions workflow to build the APK manually:

1. Go to the **Actions** tab in GitHub
2. Select **Build APK** workflow
3. Click **Run workflow**
4. Choose build type (release/debug)
5. Download the APK from the workflow artifacts

Note: The workflow is only triggered manually (not on push or pull request).

## Data Format

The app expects CSV data in the following format:
- Column A: "Ledger:" header or dates
- Column B: Customer number and name (format: "number.name") or particulars
- Columns C-G: Date range, voucher type, voucher number, debit, credit

Master sheet customer identifier (Column A) supports both:
- `account.name`
- `account_Savings_name` (first segment is account, last segment is name)

Master sheet contact sync supports fixed headers:
- `NAME`, `Mobile No`, `Area`, `Group`, `GPAY`, `Bank`, `A/C NO.`

Example:
```
Ledger:,1139B.Pushpa Malliga Teacher,1-Apr-2025 to 23-Nov-2025,,,
Date,Particulars,,Vch Type,Vch No.,Debit,Credit
2025-04-24,By,Cash,Receipt,16453,,15000
...
```

## Tech Stack

- **Flutter 3.24+**
- **Dart 3.0+**
- **SharedPreferences** for persistent storage
- **HTTP package** for network requests
- **CSV package** for parsing
- **Google Fonts** for typography
- **PDF package** for generating printable documents
- **Printing package** for print/PDF preview

## License

This project is licensed under the GNU General Public License v3.0 (GPLv3).

You may redistribute and/or modify this program under the terms of the GNU GPL as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

See the [LICENSE](LICENSE) file for details.