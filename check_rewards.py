"""
How to use:

python check_rewards.py

or

python check_rewards.py 0x012E82f81e506b8f0EF69FF719a6AC65822b5924

0x012E82f81e506b8f0EF69FF719a6AC65822b5924 - Github HAA
"""

#!/usr/bin/env python3
import requests
import sys

INFO_URL = "https://api.hyperliquid.xyz/info"

# <<< EDIT THIS TO YOUR MAIN WALLET ADDRESS >>>
WALLET_ADDRESS = "0x950D50d2e1C009212B1511e1Ec06F572d577AC15"

def get_referral_state(user_addr: str) -> dict:
    payload = {
        "type": "referral",
        "user": user_addr
    }

    resp = requests.post(INFO_URL, json=payload)
    resp.raise_for_status()
    data = resp.json()

    # /info returns raw JSON, but for type:"referral" most providers just
    # return the referral object directly (no status wrapper).
    # If you ever see a "status" wrapper, adapt this accordingly.
    return data

def main():
    user = WALLET_ADDRESS
    if len(sys.argv) > 1:
        user = sys.argv[1]

    print(f"Querying referral/builder rewards for: {user}")

    ref = get_referral_state(user)

    # Defensive access with .get so it doesn't crash if the schema changes
    cum_vlm          = ref.get("cumVlm")
    unclaimed        = ref.get("unclaimedRewards")
    claimed          = ref.get("claimedRewards")
    builder_rewards  = ref.get("builderRewards")
    referred_by      = ref.get("referredBy")
    referrer_state   = ref.get("referrerState")

    print("\n=== Referral / Builder Rewards State ===")
    print(f"Cumulative volume:        {cum_vlm}")
    print(f"Unclaimed referral rewards: {unclaimed}")
    print(f"Claimed referral rewards:   {claimed}")
    print(f"Builder rewards (total):    {builder_rewards}")

    print("\nReferred by:")
    print(referred_by)

    print("\nReferrer state (if you’re a referrer/builder):")
    print(referrer_state)

if __name__ == "__main__":
    main()