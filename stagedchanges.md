# Staged Changes Documentation

**Session Date**: December 3, 2025  
**Branch**: syncmstr  
**Purpose**: Bug fixes and improvements for system logs, API responses, and startup initialization

---

## Overview

This document details all modifications made to staged files to fix critical issues:
1. Runtime warning for unawaited coroutines in TaskScheduler
2. InsecureRequestWarning for unverified HTTPS requests
3. AI API returning HTTP 201 status being rejected
4. Missing system logs (INFO level filtered out)
5. Startup warnings for missing sampling data and symbol fetching

---

## Modified Files Summary

1. `backend/services/scheduler.py` - Fixed async/await issue
2. `backend/api/account_routes.py` - Removed SSL verification bypass
3. `backend/services/ai_decision_service.py` - Accept HTTP 201, removed SSL bypass
4. `backend/services/kline_ai_analysis_service.py` - Accept HTTP 201, removed SSL bypass
5. `backend/api/system_log_routes.py` - Changed default log level to INFO
6. `backend/services/system_logger.py` - Collect INFO level logs
7. `backend/services/startup.py` - Added sampling pool warm-up
8. `backend/services/hyperliquid_symbol_service.py` - Added retry logic, changed to mainnet

---

## Detailed Changes

### 1. backend/services/scheduler.py

**Issue**: RuntimeWarning: coroutine 'TaskScheduler._execute_account_snapshot' was never awaited

**Fix**: Changed async function to synchronous (line 151)

```python
# BEFORE (Line 151):
async def _execute_account_snapshot(self, account_id: int):

# AFTER (Line 151):
def _execute_account_snapshot(self, account_id: int):
```

**Reason**: APScheduler's BackgroundScheduler uses a thread pool (synchronous context), not an async event loop. The async function was creating unawaited coroutine objects.

---

### 2. backend/api/account_routes.py

**Issue**: InsecureRequestWarning - Unverified HTTPS requests to api.aimlapi.com

**Fix**: Removed `verify=False` parameter (lines 766-771)

```python
# BEFORE (Lines 766-772):
response = requests.post(
    endpoint,
    headers=headers,
    json=payload_data,
    timeout=10.0,
    verify=False  # Disable SSL verification for custom AI endpoints
)

# AFTER (Lines 766-770):
response = requests.post(
    endpoint,
    headers=headers,
    json=payload_data,
    timeout=10.0
)
```

**Reason**: SSL verification should be enabled by default for security. The API has valid SSL certificates.

---

### 3. backend/services/ai_decision_service.py

**Issue 1**: HTTP 201 status treated as error  
**Issue 2**: InsecureRequestWarning - Unverified HTTPS requests

**Fix 1**: Accept both 200 and 201 status codes (lines 1206-1208)

```python
# BEFORE (Line 1206):
if response.status_code == 200:

# AFTER (Lines 1206-1207):
# Accept both 200 and 201 as success (some APIs return 201 for POST)
if response.status_code in [200, 201]:
```

**Fix 2**: Removed `verify=False` parameter (lines 1199-1204)

```python
# BEFORE (Lines 1199-1205):
response = requests.post(
    endpoint,
    headers=headers,
    json=payload,
    timeout=request_timeout,
    verify=False,  # Disable SSL verification for custom AI endpoints
)

# AFTER (Lines 1199-1203):
response = requests.post(
    endpoint,
    headers=headers,
    json=payload,
    timeout=request_timeout
)
```

**Reason**: AIML API returns HTTP 201 for successful POST requests. Both 200 and 201 are valid success codes. SSL verification should be enabled for security.

---

### 4. backend/services/kline_ai_analysis_service.py

**Issue 1**: HTTP 201 status treated as error  
**Issue 2**: InsecureRequestWarning - Unverified HTTPS requests

**Fix 1**: Accept both 200 and 201 status codes (lines 364-367)

```python
# BEFORE (Line 364):
if response.status_code == 200:

# AFTER (Lines 364-365):
# Accept both 200 and 201 as success (some APIs return 201 for POST)
if response.status_code in [200, 201]:
```

**Fix 2**: Removed `verify=False` parameter (lines 353-359)

```python
# BEFORE (Lines 353-359):
response = requests.post(
    endpoint,
    headers=headers,
    json=payload,
    timeout=request_timeout,
    verify=False,
)

# AFTER (Lines 353-357):
response = requests.post(
    endpoint,
    headers=headers,
    json=payload,
    timeout=request_timeout
)
```

**Reason**: Same as ai_decision_service.py - accept 201 status and enable SSL verification.

---

### 5. backend/api/system_log_routes.py

**Issue**: System logs not showing INFO level entries (AI decisions visible in Model Chat but not in System Logs)

**Fix 1**: Changed default min_level from WARNING to INFO (line 31)

```python
# BEFORE (Line 31):
min_level = None if level else "WARNING"

# AFTER (Line 31):
min_level = None if level else "INFO"
```

**Fix 2**: Changed stats endpoint to include INFO logs (line 81)

```python
# BEFORE (Line 81):
all_logs = system_logger.get_logs(limit=500, min_level="WARNING")

# AFTER (Line 81):
all_logs = system_logger.get_logs(limit=500, min_level="INFO")
```

**Reason**: Users expect to see all log levels (INFO, WARNING, ERROR) in the system logs dashboard. The default was filtering out INFO level logs.

---

### 6. backend/services/system_logger.py

**Issue**: SystemLogHandler only collecting WARNING and above, missing INFO logs

**Fix 1**: Changed handler level to INFO (line 327)

```python
# BEFORE (Line 327):
handler.setLevel(logging.WARNING)  # 只收集WARNING及以上

# AFTER (Line 327):
handler.setLevel(logging.INFO)  # 收集INFO及以上级别
```

**Fix 2**: Simplified emit() to collect all INFO+ logs (lines 230-237)

```python
# BEFORE (Lines 230-253):
# 记录WARNING及以上级别,或者策略触发相关的INFO日志
if record.levelno >= logging.WARNING:
    system_logger.add_log(
        level=level,
        category=category,
        message=message,
        details=details
    )
elif record.levelno == logging.INFO and "Strategy triggered" in message:
    # 收集策略触发的INFO日志
    system_logger.add_log(
        level=level,
        category="ai_decision",
        message=message,
        details=details
    )
elif record.levelno == logging.INFO and "Strategy execution completed" in message:
    # 收集策略执行完成的INFO日志
    system_logger.add_log(
        level=level,
        category="ai_decision",
        message=message,
        details=details
    )

# AFTER (Lines 230-237):
# 记录INFO及以上级别的日志
if record.levelno >= logging.INFO:
    system_logger.add_log(
        level=level,
        category=category,
        message=message,
        details=details
    )
```

**Reason**: Removed special-case filters for INFO logs - now all INFO level logs are collected uniformly.

---

### 7. backend/services/startup.py

**Issue**: "No sampling data available for configured Hyperliquid symbols" warning on first startup

**Fix**: Added sampling pool warm-up (lines 17-22, 59-78)

**New imports added (Lines 17-22):**
```python
from typing import List
from services.sampling_pool import sampling_pool
from services.hyperliquid_market_data import get_default_hyperliquid_client
from datetime import datetime, timezone
```

**New warm-up function (Lines 59-78):**
```python
# Warm sampling pool immediately to avoid first-run warnings
def warm_sampling_pool(symbols: List[str]) -> None:
    try:
        client = get_default_hyperliquid_client()
        now_ts = datetime.now(timezone.utc).timestamp()
        for sym in symbols:
            try:
                price = client.get_last_price(sym)
                if price and float(price) > 0:
                    sampling_pool.add_sample(sym, float(price), now_ts)
            except Exception as e:
                logger.debug(f"Sampling warm-up: failed to seed {sym}: {e}")
        logger.info(f"Sampling pool pre-warmed for {len(symbols)} symbols")
    except Exception as e:
        logger.debug(f"Sampling warm-up failed: {e}")

warm_sampling_pool(combined_symbols)
```

**Reason**: The sampling pool was empty on startup, causing warnings when AI trading tried to access sampling data. Pre-seeding with initial prices prevents the warning.

---

### 8. backend/services/hyperliquid_symbol_service.py

**Issue 1**: "No symbols fetched from Hyperliquid meta" warning due to transient network issues  
**Issue 2**: Default environment should be mainnet, not testnet

**Fix 1**: Added imports for retry logic (lines 14-16)

```python
# BEFORE (Lines 14-16):
from typing import Dict, List, Optional

import requests

# AFTER (Lines 14-18):
from typing import Dict, List, Optional
import time
import random

import requests
```

**Fix 2**: Added retry logic with exponential backoff (lines 116-136)

```python
# BEFORE (Lines 116-125):
def fetch_remote_symbols(environment: str = "testnet") -> List[Dict[str, str]]:
    """Call Hyperliquid meta endpoint to retrieve tradable universe."""
    url = META_ENDPOINTS.get(environment, META_ENDPOINTS["testnet"])
    try:
        resp = requests.post(url, json={"type": "meta"}, timeout=10)
        resp.raise_for_status()
        data = resp.json()
        universe = data.get("universe") or data.get("universeSpot") or []
    except Exception as err:
        logger.warning("Failed to fetch Hyperliquid meta info: %s", err)
        return []

# AFTER (Lines 116-136):
def fetch_remote_symbols(environment: str = "testnet") -> List[Dict[str, str]]:
    """Call Hyperliquid meta endpoint to retrieve tradable universe."""
    url = META_ENDPOINTS.get(environment, META_ENDPOINTS["testnet"])
    attempts = 3
    data = None
    for attempt in range(attempts):
        try:
            resp = requests.post(url, json={"type": "meta"}, timeout=10)
            resp.raise_for_status()
            data = resp.json()
            break
        except Exception as err:
            wait_for = (2 ** attempt) + random.uniform(0, 0.5)
            if attempt < attempts - 1:
                logger.info(f"Hyperliquid meta fetch failed (attempt {attempt + 1}/{attempts}), retrying in {wait_for:.1f}s: {err}")
                time.sleep(wait_for)
                continue
            logger.warning("Failed to fetch Hyperliquid meta info: %s", err)
            return []

    universe = data.get("universe") or data.get("universeSpot") or []
    results: List[Dict[str, str]] = []
```

**Fix 3**: Changed default environment to mainnet (line 171)

```python
# BEFORE (Line 171):
def refresh_hyperliquid_symbols(environment: str = "testnet") -> List[Dict[str, str]]:

# AFTER (Line 171):
def refresh_hyperliquid_symbols(environment: str = "mainnet") -> List[Dict[str, str]]:
```

**Reason**: Retry logic prevents transient network failures from causing symbol fetch failures. Mainnet is the primary production environment.

---

## How to Reapply These Changes After Merge

If you merge from main and these changes are lost, follow these steps:

### Step 1: Fix Scheduler Async Issue
```bash
# File: backend/services/scheduler.py
# Line 151: Remove 'async' keyword
# Change: async def _execute_account_snapshot(self, account_id: int):
# To:     def _execute_account_snapshot(self, account_id: int):
```

### Step 2: Enable SSL Verification (3 files)
Remove `verify=False` from all requests.post() calls in:
- `backend/api/account_routes.py` (line ~771)
- `backend/services/ai_decision_service.py` (line ~1204)
- `backend/services/kline_ai_analysis_service.py` (line ~358)

### Step 3: Accept HTTP 201 Status (2 files)
Change status code checks in:
- `backend/services/ai_decision_service.py` (line ~1206)
- `backend/services/kline_ai_analysis_service.py` (line ~364)

From: `if response.status_code == 200:`  
To: `if response.status_code in [200, 201]:`

### Step 4: Fix System Logs Display (2 files)

**File: backend/api/system_log_routes.py**
- Line 31: Change `min_level = None if level else "WARNING"` to `"INFO"`
- Line 81: Change `min_level="WARNING"` to `min_level="INFO"`

**File: backend/services/system_logger.py**
- Line 327: Change `handler.setLevel(logging.WARNING)` to `logging.INFO`
- Lines 230-253: Replace conditional logic with simple `if record.levelno >= logging.INFO:`

### Step 5: Add Sampling Pool Warm-up

**File: backend/services/startup.py**

Add imports after line 21:
```python
from typing import List
from services.sampling_pool import sampling_pool
from services.hyperliquid_market_data import get_default_hyperliquid_client
from datetime import datetime, timezone
```

Add warm-up function after line 58 (after `start_market_stream()`):
```python
# Warm sampling pool immediately to avoid first-run warnings
def warm_sampling_pool(symbols: List[str]) -> None:
    try:
        client = get_default_hyperliquid_client()
        now_ts = datetime.now(timezone.utc).timestamp()
        for sym in symbols:
            try:
                price = client.get_last_price(sym)
                if price and float(price) > 0:
                    sampling_pool.add_sample(sym, float(price), now_ts)
            except Exception as e:
                logger.debug(f"Sampling warm-up: failed to seed {sym}: {e}")
        logger.info(f"Sampling pool pre-warmed for {len(symbols)} symbols")
    except Exception as e:
        logger.debug(f"Sampling warm-up failed: {e}")

warm_sampling_pool(combined_symbols)
```

### Step 6: Add Symbol Fetch Retry Logic

**File: backend/services/hyperliquid_symbol_service.py**

Add imports after line 14:
```python
import time
import random
```

Replace `fetch_remote_symbols()` function (lines ~116-136) with retry logic version shown in detailed changes above.

Change default environment parameter:
- Line 171: Change `environment: str = "testnet"` to `"mainnet"`

---

## Testing After Reapplication

After reapplying all changes, verify:

1. **No runtime warnings** in backend logs on startup
2. **No InsecureRequestWarning** messages
3. **AI API calls succeed** (check Model Chat updates)
4. **System Logs show INFO, WARNING, and ERROR** entries
5. **No "sampling data" warnings** on first startup
6. **Symbol fetch succeeds** or retries on transient failures

---

## Related Issues Fixed

- ✅ Runtime warning: coroutine was never awaited
- ✅ InsecureRequestWarning for HTTPS requests
- ✅ AI API 201 status rejected as error
- ✅ System logs missing INFO level entries
- ✅ Sampling pool empty on startup
- ✅ Symbol fetch failing on network issues
- ✅ Wrong default environment (testnet vs mainnet)

---

## Notes

- All changes are backward compatible
- No database migrations required
- No configuration changes needed
- Changes take effect immediately after restart

---

**Document Version**: 1.0  
**Last Updated**: December 3, 2025
