# US Fundamental News Sniper — Multi-Asset Architecture & Monetization Blueprint

This document details the complete system architecture, multi-asset correlation engine, Neteller/crypto payment flow, cryptographic licensing gate, and global financial projections (in **Namibian Dollars / NAD** and **USD**).

---

## 1. Multi-Asset Correlation Engine Architecture

All major US macroeconomic releases (NFP, CPI, Core PCE, FOMC, PPI, Retail Sales, GDP, ADP, Jobless Claims) shift the intrinsic valuation of the **US Dollar (USD Score)**. How individual instruments react depends on their mathematical and structural relationship to the Dollar.

### Asset Class Classification & Reaction Matrix

```
                     ┌──────────────────────────────┐
                     │ US Fundamental News Event    │
                     │ (Actual vs. Forecast/Prior)  │
                     └──────────────┬───────────────┘
                                    │
                                    ▼
                     ┌──────────────────────────────┐
                     │ Unified USD Score Generator  │
                     │  (+USD = Bullish Dollar)     │
                     │  (-USD = Bearish Dollar)     │
                     └──────────────┬───────────────┘
                                    │
        ┌───────────────────────────┼───────────────────────────┐
        ▼                           ▼                           ▼
 ┌──────────────┐            ┌──────────────┐            ┌──────────────┐
 │ Inverse FX & │            │ Direct Base  │            │ US Equity    │
 │ Commodities  │            │ Pairs        │            │ Indices      │
 │ (XAU, EUR,   │            │ (USDJPY,     │            │ (NAS100,     │
 │  GBP)        │            │  USDCAD)     │            │  US30, SPX)  │
 └──────┬───────┘            └──────┬───────┘            └──────┬───────┘
        │                           │                           │
  +USD  │  -USD               +USD  │  -USD               +USD  │  -USD
  ▼     ▼                     ▼     ▼                     ▼     ▼
 SELL  BUY                   BUY   SELL                  SELL  BUY
```

### Supported Asset Matrix & Deviation Multipliers

| Instrument | Class | Relation to USD | Bullish USD Reaction | Bearish USD Reaction | Typical News Impulse |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **`XAUUSD` (Gold)** | Commodity | Inverse (Quote) | **SELL HARD** | **BUY HARD** | 40 – 250+ pips |
| **`EURUSD`** | Major FX | Inverse (Quote) | **SELL** | **BUY** | 25 – 80 pips |
| **`GBPUSD`** | Major FX | Inverse (Quote) | **SELL HARD** | **BUY HARD** | 35 – 110 pips |
| **`USDJPY`** | Major FX | **Direct (Base)** | **BUY HARD** | **SELL HARD** | 40 – 130 pips |
| **`USDCAD`** | Major FX | **Direct (Base)** | **BUY** | **SELL** | 25 – 70 pips |
| **`USDCHF`** | Major FX | **Direct (Base)** | **BUY** | **SELL** | 20 – 60 pips |
| **`NAS100` (Nasdaq)** | Equity Index | Rates Sensitive | **SELL HARD** (High Rates) | **BUY HARD** (Cuts) | 80 – 300+ pts |
| **`US30` (Dow Jones)** | Equity Index | Growth / Rates | **SELL** | **BUY** | 100 – 400+ pts |

---

## 2. Private Neteller & Crypto Payment Architecture

To facilitate seamless recurring payments without standard payment gateway tax overhead or high percentage processing cuts, the system operates on a direct wallet-to-wallet transfer model.

### Payment & Verification Workflow

```
 1. Trader visits Purchase Portal (or Telegram Sales Bot)
 2. Selects Desired Tier:
      - Tier 1: Gold Sniper Edition
      - Tier 2: Multi-Asset Pro Edition (Gold + FX + Indices)
 3. Sends Monthly/Quarterly payment to:
      - Neteller Email Account (P2P Transfer)
      - OR USDT (TRC-20 / TON / BEP-20)
 4. Submits Transaction Reference / Screenshot to Verification Endpoint
 5. System verifies transaction and issues a Cryptographically Signed License Key:
      Format: SNIPER-<TIER>-<EXPIRY_UNIX>-<HMAC_SIGNATURE>
      Example: SNIPER-MULTI-1791650400-9F2B48A1
 6. Trader inputs key into HUD Settings Modal on TradingView
 7. Extension validates key authenticity & expiration date offline/online
 8. Multi-Asset selector unlocks immediately
```

---

## 3. Cryptographic Licensing Engine (Client-Side)

The Chrome extension decrypts and verifies the license key using a public HMAC validation algorithm.

```javascript
// Verification Concept inside Chrome Extension
function verifyLicenseKey(licenseKey, secretSalt) {
  const parts = licenseKey.split("-");
  if (parts.length !== 4 || parts[0] !== "SNIPER") return { valid: false };

  const tier = parts[1]; // "GOLD" or "MULTI"
  const expiryTimestamp = parseInt(parts[2], 10);
  const providedSignature = parts[3];

  // 1. Check expiration date
  if (Date.now() > expiryTimestamp * 1000) {
    return { valid: false, reason: "EXPIRED" };
  }

  // 2. Validate cryptographic hash signature
  const expectedSignature = computeHMAC(`${tier}:${expiryTimestamp}`, secretSalt);
  if (providedSignature !== expectedSignature) {
    return { valid: false, reason: "INVALID_SIGNATURE" };
  }

  return { valid: true, tier: tier, expiresAt: new Date(expiryTimestamp * 1000) };
}
```

### UI Behavior by Tier:
* **`GOLD` Tier**:
  * Asset selector shows `XAUUSD (Gold)` locked.
  * Attempting to select `EURUSD`, `USDJPY`, or `NAS100` triggers a modal:
    * *"Multi-Asset Access Locked. Upgrade to Pro for All FX Pairs & US Indices."*
* **`MULTI` Tier**:
  * Full unrestricted access to all 8 instruments.
  * Instant auto-inversion of signals (e.g. `USDJPY` shows `BUY` when `XAUUSD` shows `SELL`).

---

## 4. Financial Projections & Tiered Pricing Matrix

*Exchange rate benchmark: **$1 USD ≈ N$18.00 NAD**.*

### Recommended Fair-Value Pricing

| Product Tier | Monthly Price (USD) | **Monthly Price (NAD)** | Value Delivered |
| :--- | :---: | :---: | :--- |
| **Tier 1: Gold Sniper (Standard)** | **$9.99 / mo** | **~N$180 NAD / mo** | Dedicated XAUUSD trading terminal HUD, instant release alerts, trade horizon hold, surprise delta. |
| **Tier 2: Multi-Asset Pro (Fairly Priced)** | **$16.99 / mo** | **~N$300 NAD / mo** | All assets unlocked (Gold, EURUSD, GBPUSD, USDJPY, USDCAD, NAS100, US30) with auto-inverted correlations. |
| **Tier 2 (Quarterly Pass - 3 Mo)** | **$45.00 / qtr** | **~N$810 NAD / qtr** | 12% discount for committing quarterly upfront. |
| **Tier 2 (Annual Pass - 1 Year)** | **$149.00 / yr** | **~N$2,680 NAD / yr** | Best value for active full-time traders. |

---

### Scenario A: Blended Revenue Modeling (50% Gold Tier / 50% Multi-Asset Tier)

*Average revenue per user (ARPU): **$13.49 USD ≈ N$240 NAD / month**.*

| Active Subscribers | Monthly Income (USD) | **Monthly Income (NAD)** | **Annual Income (NAD)** |
| :---: | :---: | :---: | :---: |
| **100 traders** | $1,349 | **N$ 24,280 NAD** | **N$ 291,360 NAD** |
| **250 traders** | $3,372 | **N$ 60,700 NAD** | **N$ 728,400 NAD** |
| **500 traders** | $6,745 | **N$ 121,400 NAD** | **N$ 1.45 Million NAD** |
| **1,000 traders** | $13,490 | **N$ 242,800 NAD** | **N$ 2.91 Million NAD** |
| **2,500 traders** | $33,725 | **N$ 607,000 NAD** | **N$ 7.28 Million NAD** |
| **5,000 traders** | $67,450 | **N$ 1,214,000 NAD** | **N$ 14.56 Million NAD** |
| **10,000 traders** | $134,900 | **N$ 2,428,000 NAD** | **N$ 29.13 Million NAD** |

---

### Scenario B: 100% Multi-Asset Access at N$300 NAD ($16.99 / mo)

If marketed primarily to index and forex traders who demand multiple pairs:

| Active Subscribers | Monthly Income (USD) | **Monthly Income (NAD)** | **Annual Income (NAD)** |
| :---: | :---: | :---: | :---: |
| **500 traders** | $8,495 | **N$ 152,910 NAD** | **N$ 1.83 Million NAD** |
| **1,000 traders** | $16,990 | **N$ 305,820 NAD** | **N$ 3.66 Million NAD** |
| **2,500 traders** | $42,475 | **N$ 764,550 NAD** | **N$ 9.17 Million NAD** |
| **5,000 traders** | $84,950 | **N$ 1,529,100 NAD** | **N$ 18.34 Million NAD** |
| **10,000 traders** | $169,900 | **N$ 3,058,200 NAD** | **N$ 36.69 Million NAD** |
| **25,000 traders** | $424,750 | **N$ 7,645,500 NAD** | **N$ 91.74 Million NAD** |

---

## 5. Implementation Steps

1. **Step 1 — In-Extension UI Asset Dropdown**:
   - Add dropdown to HUD: `XAUUSD`, `EURUSD`, `GBPUSD`, `USDJPY`, `USDCAD`, `NAS100`, `US30`.
   - Update calculation formula to invert signal direction for Base pairs (`USDJPY`, `USDCAD`) and apply index point scales to `NAS100` and `US30`.
2. **Step 2 — License Gate Component**:
   - Add activation modal to HUD with `License Key` input.
   - Cache valid license status in `chrome.storage.local`.
3. **Step 3 — Neteller / Crypto Key Issuer Bot**:
   - Provide a simple command-line or Telegram-based key generator to issue 30-day keys upon payment confirmation.
